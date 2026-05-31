/// voice_service.dart — Voice input service with STT + audio recording fallback.
///
/// Two-tier voice input strategy:
///   1. System STT (speech_to_text): real-time speech-to-text via Android/iOS
///      native SpeechRecognizer. Best UX (interim results while speaking).
///      Unavailable on devices without a speech engine (e.g. Chinese ROMs
///      without Google services).
///   2. Audio recording fallback (record): records audio to a temp file,
///      returned as bytes for the caller to send as an ACP audio attachment.
///      Works on any device with a microphone. Requires CLI supports_audio.
///
/// The service auto-detects which mode is available at init time.
/// Callers observe state changes via [ChangeNotifier].
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:record/record.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../utils/logger.dart';

final _log = getLogger('VoiceService');

/// Voice input mode determined at initialization.
enum VoiceMode {
  /// System speech-to-text available (real-time transcription).
  stt,

  /// Audio recording fallback (record + send audio to AI).
  recording,

  /// No voice input available (no mic permission or no engine).
  unavailable,
}

/// Current state of a voice input session.
enum VoiceState {
  /// Idle, not recording or listening.
  idle,

  /// Actively listening / recording.
  listening,
}

/// Voice input service: manages STT and audio recording with auto-fallback.
///
/// Usage:
/// ```dart
/// final voice = VoiceService();
/// await voice.init();
/// // Check voice.mode to see what's available
/// voice.startListening();  // starts STT or recording
/// voice.stopListening();   // stops and returns result
/// ```
class VoiceService extends ChangeNotifier {
  final stt.SpeechToText _speech = stt.SpeechToText();
  final AudioRecorder _recorder = AudioRecorder();

  VoiceMode _mode = VoiceMode.unavailable;
  VoiceState _state = VoiceState.idle;
  String _interimText = '';

  /// Tracks whether any recognition result was received in the
  /// current listening session. Reset on startListening, checked
  /// on done status to fire [onNoResult] if empty.
  bool _hasResult = false;

  // Callback for STT final results (text appended to input field)
  void Function(String text)? onFinalResult;

  // Callback for STT interim results (preview while speaking)
  void Function(String text)? onInterimResult;

  // Callback for recording complete (audio bytes ready to send)
  void Function(Uint8List audioBytes, String mimeType)? onAudioRecorded;

  // Callback for errors
  void Function(String error)? onError;

  // Callback when STT session ends with no recognized text
  void Function()? onNoResult;

  /// Current voice input mode.
  VoiceMode get mode => _mode;

  /// Current listening/recording state.
  VoiceState get state => _state;

  /// Whether voice input is available (either STT or recording).
  bool get isAvailable => _mode != VoiceMode.unavailable;

  /// Whether currently listening or recording.
  bool get isListening => _state == VoiceState.listening;

  /// Interim transcription text (STT mode only).
  String get interimText => _interimText;

  /// Initialize: try system STT first, fall back to audio recording.
  Future<void> init() async {
    // Tier 1: try system speech-to-text
    try {
      final sttOk = await _speech.initialize(
        onStatus: _onSttStatus,
        onError: _onSttError,
      );
      if (sttOk) {
        _mode = VoiceMode.stt;
        final locales = await _speech.locales();
        _log.info('🎤 语音模式: STT (系统语音识别), locales=${locales.length}');
        notifyListeners();
        return;
      }
      _log.info('🎤 系统 STT 不可用，尝试录音模式');
    } catch (e) {
      _log.warning('🎤 STT 初始化失败: $e');
    }

    // Tier 2: try audio recording
    try {
      final hasPermission = await _recorder.hasPermission();
      if (hasPermission) {
        _mode = VoiceMode.recording;
        _log.info('🎤 语音模式: 录音 (音频发送给AI)');
        notifyListeners();
        return;
      }
      _log.warning('🎤 麦克风权限被拒绝');
    } catch (e) {
      _log.warning('🎤 录音初始化失败: $e');
    }

    _mode = VoiceMode.unavailable;
    _log.warning('🎤 语音输入不可用: 无系统STT且无麦克风权限');
    notifyListeners();
  }

  /// Start listening (STT) or recording (fallback).
  Future<void> startListening() async {
    if (_state == VoiceState.listening) return;

    switch (_mode) {
      case VoiceMode.stt:
        await _startStt();
      case VoiceMode.recording:
        await _startRecording();
      case VoiceMode.unavailable:
        onError?.call('语音输入不可用');
        return;
    }

    _state = VoiceState.listening;
    _interimText = '';
    _hasResult = false;
    notifyListeners();
  }

  /// Stop listening/recording and finalize results.
  Future<void> stopListening() async {
    if (_state != VoiceState.listening) return;

    switch (_mode) {
      case VoiceMode.stt:
        await _stopStt();
      case VoiceMode.recording:
        await _stopRecording();
      case VoiceMode.unavailable:
        break;
    }

    _state = VoiceState.idle;
    _interimText = '';
    notifyListeners();
  }

  // ── STT (Tier 1) ──

  Future<void> _startStt() async {
    _speech.listen(
      onResult: (result) {
        if (result.finalResult) {
          _interimText = '';
          _hasResult = true;
          onFinalResult?.call(result.recognizedWords);
        } else {
          _interimText = result.recognizedWords;
          onInterimResult?.call(result.recognizedWords);
        }
        notifyListeners();
      },
      listenFor: const Duration(seconds: 60),
      pauseFor: const Duration(seconds: 5),
      localeId: WidgetsBinding.instance.platformDispatcher.locale.toLanguageTag(),
      listenOptions: stt.SpeechListenOptions(
        partialResults: true,
        listenMode: stt.ListenMode.dictation,
      ),
    );
  }

  Future<void> _stopStt() async {
    await _speech.stop();
  }

  void _onSttStatus(String status) {
    _log.fine('🎤 STT status: $status');
    // Both 'notListening' and 'done' indicate the session ended.
    // Some engines fire both in sequence, some only fire one.
    // Guard with _state check to avoid double-processing.
    if ((status == 'done' || status == 'notListening') &&
        _state == VoiceState.listening) {
      _state = VoiceState.idle;
      if (!_hasResult && status == 'done') {
        _log.info('🎤 语音识别结束，未识别到文字');
        onNoResult?.call();
      }
      _interimText = '';
      notifyListeners();
    }
  }

  void _onSttError(dynamic error) {
    final msg = error.errorMsg ?? '$error';
    final permanent = error.permanent ?? true;
    _log.severe('语音识别错误: $msg (permanent=$permanent)');
    _state = VoiceState.idle;
    _interimText = '';
    // User-friendly error messages based on error type
    final userMsg = switch (msg) {
      'error_language_unavailable' =>
        '当前语言不支持语音识别，请在系统设置中下载对应语音包',
      'error_no_match' => '未识别到语音，请重试',
      'error_audio' => '麦克风异常，请检查权限',
      'error_network' => '语音识别需要网络连接',
      'error_permission' => '请授予麦克风权限',
      _ => '语音识别出错: $msg',
    };
    onError?.call(userMsg);
    notifyListeners();
  }

  // ── Audio Recording (Tier 2) ──

  Future<void> _startRecording() async {
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        sampleRate: 16000,
        numChannels: 1,
        bitRate: 64000,
      ),
      path: '',
    );
    _log.info('🎤 开始录音');
  }

  Future<void> _stopRecording() async {
    final path = await _recorder.stop();
    _log.info('🎤 录音结束: $path');

    if (path != null && path.isNotEmpty) {
      try {
        final file = File(path);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          _log.info('🎤 音频大小: ${(bytes.length / 1024).toStringAsFixed(1)}KB');
          onAudioRecorded?.call(bytes, 'audio/mp4');
          await file.delete().catchError((_) => file);
        }
      } catch (e) {
        _log.severe('🎤 读取录音文件失败: $e');
        onError?.call('录音文件读取失败');
      }
    }
  }

  /// Release all resources.
  @override
  void dispose() {
    if (_state == VoiceState.listening) {
      _speech.stop();
      _recorder.stop();
    }
    _recorder.dispose();
    super.dispose();
  }
}
