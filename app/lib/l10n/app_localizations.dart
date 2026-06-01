import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of S
/// returned by `S.of(context)`.
///
/// Applications need to include `S.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: S.localizationsDelegates,
///   supportedLocales: S.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the S.supportedLocales
/// property.
abstract class S {
  S(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static S of(BuildContext context) {
    return Localizations.of<S>(context, S)!;
  }

  static const LocalizationsDelegate<S> delegate = _SDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh')
  ];

  /// No description provided for @commonCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// No description provided for @commonConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get commonConfirm;

  /// No description provided for @commonDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get commonDelete;

  /// No description provided for @commonRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get commonRemove;

  /// No description provided for @commonRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get commonRetry;

  /// No description provided for @commonAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get commonAdd;

  /// No description provided for @commonGotIt.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get commonGotIt;

  /// No description provided for @commonInstall.
  ///
  /// In en, this message translates to:
  /// **'Install'**
  String get commonInstall;

  /// No description provided for @commonUninstall.
  ///
  /// In en, this message translates to:
  /// **'Uninstall'**
  String get commonUninstall;

  /// No description provided for @commonOr.
  ///
  /// In en, this message translates to:
  /// **'or'**
  String get commonOr;

  /// No description provided for @commonCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get commonCopied;

  /// No description provided for @commonSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get commonSaved;

  /// No description provided for @commonCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get commonCopy;

  /// No description provided for @commonCollapse.
  ///
  /// In en, this message translates to:
  /// **'Collapse'**
  String get commonCollapse;

  /// App name shown in title bar
  ///
  /// In en, this message translates to:
  /// **'MobileFlow'**
  String get appTitle;

  /// Subtitle on splash screen
  ///
  /// In en, this message translates to:
  /// **'Mobile AI Coding Assistant'**
  String get appSubtitle;

  /// No description provided for @connectHeroTitle.
  ///
  /// In en, this message translates to:
  /// **'Connect to your desktop AI coding environment'**
  String get connectHeroTitle;

  /// No description provided for @connectStatusConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get connectStatusConnected;

  /// No description provided for @connectStatusWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting to connect'**
  String get connectStatusWaiting;

  /// No description provided for @connectLanTab.
  ///
  /// In en, this message translates to:
  /// **'LAN'**
  String get connectLanTab;

  /// No description provided for @connectRelayTab.
  ///
  /// In en, this message translates to:
  /// **'Relay'**
  String get connectRelayTab;

  /// No description provided for @connectTunnelTab.
  ///
  /// In en, this message translates to:
  /// **'Tunnel'**
  String get connectTunnelTab;

  /// No description provided for @connectLanHeadline.
  ///
  /// In en, this message translates to:
  /// **'Fastest connection'**
  String get connectLanHeadline;

  /// No description provided for @connectLanDescription.
  ///
  /// In en, this message translates to:
  /// **'Use this mode when your phone and computer are on the same network. Enter IP, port, and password to connect.'**
  String get connectLanDescription;

  /// No description provided for @connectLanBadge.
  ///
  /// In en, this message translates to:
  /// **'Low latency · Fewest hops'**
  String get connectLanBadge;

  /// No description provided for @connectIpLabel.
  ///
  /// In en, this message translates to:
  /// **'Computer IP Address'**
  String get connectIpLabel;

  /// No description provided for @connectIpHint.
  ///
  /// In en, this message translates to:
  /// **'192.168.1.100'**
  String get connectIpHint;

  /// No description provided for @connectPortLabel.
  ///
  /// In en, this message translates to:
  /// **'Port'**
  String get connectPortLabel;

  /// No description provided for @connectPortHint.
  ///
  /// In en, this message translates to:
  /// **'9600'**
  String get connectPortHint;

  /// No description provided for @connectPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Connection Password'**
  String get connectPasswordLabel;

  /// No description provided for @connectPasswordHint.
  ///
  /// In en, this message translates to:
  /// **'Check your computer terminal'**
  String get connectPasswordHint;

  /// No description provided for @connectButton.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get connectButton;

  /// No description provided for @connectingButton.
  ///
  /// In en, this message translates to:
  /// **'Connecting...'**
  String get connectingButton;

  /// No description provided for @connectRelayHeadline.
  ///
  /// In en, this message translates to:
  /// **'For remote connections'**
  String get connectRelayHeadline;

  /// No description provided for @connectRelayDescription.
  ///
  /// In en, this message translates to:
  /// **'End-to-end encrypted even through relay. Scan QR code or paste the pairing code from your computer.'**
  String get connectRelayDescription;

  /// No description provided for @connectRelayBadge.
  ///
  /// In en, this message translates to:
  /// **'Works anywhere · Stable pairing'**
  String get connectRelayBadge;

  /// No description provided for @connectScanQr.
  ///
  /// In en, this message translates to:
  /// **'Scan QR Code'**
  String get connectScanQr;

  /// No description provided for @connectScanQrNote.
  ///
  /// In en, this message translates to:
  /// **'Current version supports pasting QR content or pairing code. Full camera scanning coming soon.'**
  String get connectScanQrNote;

  /// No description provided for @connectPairingCodeLabel.
  ///
  /// In en, this message translates to:
  /// **'Pairing Code'**
  String get connectPairingCodeLabel;

  /// No description provided for @connectPairingCodeHint.
  ///
  /// In en, this message translates to:
  /// **'Check your computer terminal'**
  String get connectPairingCodeHint;

  /// No description provided for @connectRelayButton.
  ///
  /// In en, this message translates to:
  /// **'Remote Connect'**
  String get connectRelayButton;

  /// No description provided for @connectTunnelHeadline.
  ///
  /// In en, this message translates to:
  /// **'For self-hosted servers'**
  String get connectTunnelHeadline;

  /// No description provided for @connectTunnelDescription.
  ///
  /// In en, this message translates to:
  /// **'If you have your own WebSocket gateway or deployment, enter the address and token here.'**
  String get connectTunnelDescription;

  /// No description provided for @connectTunnelBadge.
  ///
  /// In en, this message translates to:
  /// **'Self-controlled · Flexible'**
  String get connectTunnelBadge;

  /// No description provided for @connectTunnelUrlLabel.
  ///
  /// In en, this message translates to:
  /// **'WebSocket Address'**
  String get connectTunnelUrlLabel;

  /// No description provided for @connectTunnelUrlHint.
  ///
  /// In en, this message translates to:
  /// **'wss://your-server.com:8765'**
  String get connectTunnelUrlHint;

  /// No description provided for @connectTunnelTokenLabel.
  ///
  /// In en, this message translates to:
  /// **'Bearer Token (optional)'**
  String get connectTunnelTokenLabel;

  /// No description provided for @connectTunnelTokenHint.
  ///
  /// In en, this message translates to:
  /// **'Auth token'**
  String get connectTunnelTokenHint;

  /// No description provided for @connectTunnelButton.
  ///
  /// In en, this message translates to:
  /// **'Direct Connect'**
  String get connectTunnelButton;

  /// No description provided for @connectSwitchModeTitle.
  ///
  /// In en, this message translates to:
  /// **'Switch Connection Mode'**
  String get connectSwitchModeTitle;

  /// No description provided for @connectSwitchModeMessage.
  ///
  /// In en, this message translates to:
  /// **'Switching mode will disconnect the current connection. Continue?'**
  String get connectSwitchModeMessage;

  /// No description provided for @connectSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Connect your phone to desktop AI coding environment'**
  String get connectSubtitle;

  /// No description provided for @connectConnect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get connectConnect;

  /// No description provided for @connectConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting...'**
  String get connectConnecting;

  /// No description provided for @connectLanHostLabel.
  ///
  /// In en, this message translates to:
  /// **'Computer IP address'**
  String get connectLanHostLabel;

  /// No description provided for @connectLanPortLabel.
  ///
  /// In en, this message translates to:
  /// **'Port'**
  String get connectLanPortLabel;

  /// No description provided for @connectLanPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Connection password'**
  String get connectLanPasswordLabel;

  /// No description provided for @connectLanPasswordHint.
  ///
  /// In en, this message translates to:
  /// **'Check in computer terminal'**
  String get connectLanPasswordHint;

  /// No description provided for @connectRelayScanDialogMessage.
  ///
  /// In en, this message translates to:
  /// **'Paste the pairing code from your computer terminal'**
  String get connectRelayScanDialogMessage;

  /// No description provided for @connectRelayScanDialogHint.
  ///
  /// In en, this message translates to:
  /// **'Paste pairing code...'**
  String get connectRelayScanDialogHint;

  /// No description provided for @connectErrorNoHost.
  ///
  /// In en, this message translates to:
  /// **'Please enter computer IP address'**
  String get connectErrorNoHost;

  /// No description provided for @connectErrorNoPassword.
  ///
  /// In en, this message translates to:
  /// **'Please enter connection password'**
  String get connectErrorNoPassword;

  /// No description provided for @connectErrorNoRelayCode.
  ///
  /// In en, this message translates to:
  /// **'Please enter pairing code'**
  String get connectErrorNoRelayCode;

  /// No description provided for @connectErrorInvalidRelayCode.
  ///
  /// In en, this message translates to:
  /// **'Invalid pairing code'**
  String get connectErrorInvalidRelayCode;

  /// No description provided for @connectErrorInvalidRelayCodeRescan.
  ///
  /// In en, this message translates to:
  /// **'Invalid pairing code, please scan again'**
  String get connectErrorInvalidRelayCodeRescan;

  /// No description provided for @connectErrorInvalidSecret.
  ///
  /// In en, this message translates to:
  /// **'Invalid key in pairing code'**
  String get connectErrorInvalidSecret;

  /// No description provided for @connectErrorNoTunnelUrl.
  ///
  /// In en, this message translates to:
  /// **'Please enter WebSocket address'**
  String get connectErrorNoTunnelUrl;

  /// No description provided for @connectErrorNetworkUnreachable.
  ///
  /// In en, this message translates to:
  /// **'Cannot reach this IP address. Make sure your phone and computer are on the same network.'**
  String get connectErrorNetworkUnreachable;

  /// No description provided for @connectErrorPortRefused.
  ///
  /// In en, this message translates to:
  /// **'Connection refused on this port. Make sure the Agent is running and listening.'**
  String get connectErrorPortRefused;

  /// No description provided for @connectErrorWrongPairingCode.
  ///
  /// In en, this message translates to:
  /// **'Wrong pairing code. Check the 6-digit code shown in your computer terminal.'**
  String get connectErrorWrongPairingCode;

  /// No description provided for @connectErrorRelayUnreachable.
  ///
  /// In en, this message translates to:
  /// **'Relay server unavailable. Check your network connection.'**
  String get connectErrorRelayUnreachable;

  /// No description provided for @connectErrorTlsFailure.
  ///
  /// In en, this message translates to:
  /// **'TLS connection failed. Check the server certificate configuration.'**
  String get connectErrorTlsFailure;

  /// No description provided for @connectErrorTimeout.
  ///
  /// In en, this message translates to:
  /// **'Connection timed out. Check your network.'**
  String get connectErrorTimeout;

  /// No description provided for @connectErrorSessionExpired.
  ///
  /// In en, this message translates to:
  /// **'Session expired. Please reconnect.'**
  String get connectErrorSessionExpired;

  /// No description provided for @connectErrorLockout.
  ///
  /// In en, this message translates to:
  /// **'Too many pairing attempts. Please wait {seconds} seconds before retrying.'**
  String connectErrorLockout(int seconds);

  /// No description provided for @connectErrorTunnelAuthFailed.
  ///
  /// In en, this message translates to:
  /// **'Authentication failed. Check your Bearer Token.'**
  String get connectErrorTunnelAuthFailed;

  /// No description provided for @connectErrorGeneric.
  ///
  /// In en, this message translates to:
  /// **'Connection failed. Check your network settings.'**
  String get connectErrorGeneric;

  /// No description provided for @connectRelayScanQr.
  ///
  /// In en, this message translates to:
  /// **'Scan QR Code'**
  String get connectRelayScanQr;

  /// No description provided for @connectRelayScanNote.
  ///
  /// In en, this message translates to:
  /// **'Current version supports pasting QR content or pairing code. Full camera scanning coming soon.'**
  String get connectRelayScanNote;

  /// No description provided for @connectRelayCodeLabel.
  ///
  /// In en, this message translates to:
  /// **'Pairing Code'**
  String get connectRelayCodeLabel;

  /// No description provided for @connectRelayCodeHint.
  ///
  /// In en, this message translates to:
  /// **'Check your computer terminal'**
  String get connectRelayCodeHint;

  /// No description provided for @connectRelayConnect.
  ///
  /// In en, this message translates to:
  /// **'Remote Connect'**
  String get connectRelayConnect;

  /// No description provided for @connectTunnelConnect.
  ///
  /// In en, this message translates to:
  /// **'Direct Connect'**
  String get connectTunnelConnect;

  /// No description provided for @connectScanInstruction.
  ///
  /// In en, this message translates to:
  /// **'Point camera at the QR code on your computer dashboard'**
  String get connectScanInstruction;

  /// No description provided for @connectQrInvalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid QR code. Please scan the code from MobileFlow dashboard.'**
  String get connectQrInvalid;

  /// No description provided for @connectQrInvalidPort.
  ///
  /// In en, this message translates to:
  /// **'Invalid connection parameters in QR code.'**
  String get connectQrInvalidPort;

  /// No description provided for @connectScanCameraRequired.
  ///
  /// In en, this message translates to:
  /// **'Camera access is required to scan QR codes.'**
  String get connectScanCameraRequired;

  /// No description provided for @connectScanClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get connectScanClose;

  /// No description provided for @chatEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Start coding with AI!'**
  String get chatEmptyTitle;

  /// No description provided for @chatEmptySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Type a message or use / commands'**
  String get chatEmptySubtitle;

  /// No description provided for @chatSuggestion1.
  ///
  /// In en, this message translates to:
  /// **'Show me the project structure'**
  String get chatSuggestion1;

  /// No description provided for @chatSuggestion2.
  ///
  /// In en, this message translates to:
  /// **'Check for code issues'**
  String get chatSuggestion2;

  /// No description provided for @chatSuggestion3.
  ///
  /// In en, this message translates to:
  /// **'Explain this project'**
  String get chatSuggestion3;

  /// No description provided for @chatNoProjectTitle.
  ///
  /// In en, this message translates to:
  /// **'Add a project first'**
  String get chatNoProjectTitle;

  /// No description provided for @chatNoProjectDescription.
  ///
  /// In en, this message translates to:
  /// **'Add a project directory in Settings'**
  String get chatNoProjectDescription;

  /// No description provided for @chatAiThinking.
  ///
  /// In en, this message translates to:
  /// **'AI thinking...'**
  String get chatAiThinking;

  /// No description provided for @chatAiToolRunning.
  ///
  /// In en, this message translates to:
  /// **'Tool running...'**
  String get chatAiToolRunning;

  /// No description provided for @chatAiToolRunningDetail.
  ///
  /// In en, this message translates to:
  /// **'Running: {detail}'**
  String chatAiToolRunningDetail(String detail);

  /// No description provided for @chatAiStreaming.
  ///
  /// In en, this message translates to:
  /// **'Responding...'**
  String get chatAiStreaming;

  /// No description provided for @chatAuthRequired.
  ///
  /// In en, this message translates to:
  /// **'Authentication Required'**
  String get chatAuthRequired;

  /// No description provided for @chatAuthRequiredDesc.
  ///
  /// In en, this message translates to:
  /// **'This Agent requires an API Key to use'**
  String get chatAuthRequiredDesc;

  /// No description provided for @chatNoAuthMethods.
  ///
  /// In en, this message translates to:
  /// **'No authentication methods received'**
  String get chatNoAuthMethods;

  /// No description provided for @chatPermissionDeny.
  ///
  /// In en, this message translates to:
  /// **'Deny'**
  String get chatPermissionDeny;

  /// No description provided for @chatPermissionAllow.
  ///
  /// In en, this message translates to:
  /// **'Allow'**
  String get chatPermissionAllow;

  /// No description provided for @chatPermissionAlwaysAllow.
  ///
  /// In en, this message translates to:
  /// **'Always Allow'**
  String get chatPermissionAlwaysAllow;

  /// No description provided for @chatHistorySessions.
  ///
  /// In en, this message translates to:
  /// **'History Sessions'**
  String get chatHistorySessions;

  /// No description provided for @chatNoHistorySessions.
  ///
  /// In en, this message translates to:
  /// **'No history sessions'**
  String get chatNoHistorySessions;

  /// No description provided for @chatLoadingHistory.
  ///
  /// In en, this message translates to:
  /// **'Loading history...'**
  String get chatLoadingHistory;

  /// No description provided for @chatScrollUpForMore.
  ///
  /// In en, this message translates to:
  /// **'↑ Scroll up for more'**
  String get chatScrollUpForMore;

  /// No description provided for @chatNewSessionConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'AI is responding'**
  String get chatNewSessionConfirmTitle;

  /// No description provided for @chatNewSessionConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'Switching sessions will interrupt the current conversation. Continue?'**
  String get chatNewSessionConfirmMessage;

  /// No description provided for @chatContinueSwitch.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get chatContinueSwitch;

  /// No description provided for @chatScrollLoadMore.
  ///
  /// In en, this message translates to:
  /// **'↑ Scroll up to load more'**
  String get chatScrollLoadMore;

  /// No description provided for @chatConnectingAgent.
  ///
  /// In en, this message translates to:
  /// **'Connecting to AI Agent...'**
  String get chatConnectingAgent;

  /// No description provided for @chatAuthApiKeyNeeded.
  ///
  /// In en, this message translates to:
  /// **'This Agent requires an API Key'**
  String get chatAuthApiKeyNeeded;

  /// No description provided for @chatAuthNoMethods.
  ///
  /// In en, this message translates to:
  /// **'No authentication methods received'**
  String get chatAuthNoMethods;

  /// No description provided for @chatStatusThinking.
  ///
  /// In en, this message translates to:
  /// **'AI thinking...'**
  String get chatStatusThinking;

  /// No description provided for @chatStatusExecuting.
  ///
  /// In en, this message translates to:
  /// **'Executing'**
  String get chatStatusExecuting;

  /// No description provided for @chatStatusToolRunning.
  ///
  /// In en, this message translates to:
  /// **'Tool running...'**
  String get chatStatusToolRunning;

  /// No description provided for @chatStatusStreaming.
  ///
  /// In en, this message translates to:
  /// **'Responding...'**
  String get chatStatusStreaming;

  /// No description provided for @chatStreamInterrupted.
  ///
  /// In en, this message translates to:
  /// **'Response interrupted — connection lost'**
  String get chatStreamInterrupted;

  /// No description provided for @chatPermissionToolCall.
  ///
  /// In en, this message translates to:
  /// **'Tool call'**
  String get chatPermissionToolCall;

  /// No description provided for @chatAiResponding.
  ///
  /// In en, this message translates to:
  /// **'AI is responding'**
  String get chatAiResponding;

  /// No description provided for @chatSwitchSessionWarning.
  ///
  /// In en, this message translates to:
  /// **'Switching session will interrupt the current conversation. Continue?'**
  String get chatSwitchSessionWarning;

  /// No description provided for @chatSwitchSessionConfirm.
  ///
  /// In en, this message translates to:
  /// **'Switch anyway'**
  String get chatSwitchSessionConfirm;

  /// No description provided for @chatSessionHistory.
  ///
  /// In en, this message translates to:
  /// **'Session history'**
  String get chatSessionHistory;

  /// No description provided for @chatNoSessions.
  ///
  /// In en, this message translates to:
  /// **'No session history'**
  String get chatNoSessions;

  /// No description provided for @chatEmptySession.
  ///
  /// In en, this message translates to:
  /// **'(Empty session)'**
  String get chatEmptySession;

  /// No description provided for @chatManageProjectHint.
  ///
  /// In en, this message translates to:
  /// **'Manage projects in Settings'**
  String get chatManageProjectHint;

  /// No description provided for @chatTapToInput.
  ///
  /// In en, this message translates to:
  /// **'Tap to input'**
  String get chatTapToInput;

  /// No description provided for @chatInputInstallAgent.
  ///
  /// In en, this message translates to:
  /// **'Please install an AI Agent in Settings first'**
  String get chatInputInstallAgent;

  /// No description provided for @chatInputVoiceReleaseCancel.
  ///
  /// In en, this message translates to:
  /// **'Release to cancel'**
  String get chatInputVoiceReleaseCancel;

  /// No description provided for @chatInputVoiceListening.
  ///
  /// In en, this message translates to:
  /// **'Listening...'**
  String get chatInputVoiceListening;

  /// No description provided for @chatInputVoiceHoldToTalk.
  ///
  /// In en, this message translates to:
  /// **'Hold to talk, release to input'**
  String get chatInputVoiceHoldToTalk;

  /// No description provided for @chatInputVoiceReleaseToCancel.
  ///
  /// In en, this message translates to:
  /// **'Release to cancel'**
  String get chatInputVoiceReleaseToCancel;

  /// No description provided for @chatInputVoiceSwipeToCancel.
  ///
  /// In en, this message translates to:
  /// **'Swipe up to cancel'**
  String get chatInputVoiceSwipeToCancel;

  /// No description provided for @chatInputVoiceHoldToSpeak.
  ///
  /// In en, this message translates to:
  /// **'Hold to speak'**
  String get chatInputVoiceHoldToSpeak;

  /// No description provided for @chatInputPhotoFailed.
  ///
  /// In en, this message translates to:
  /// **'Photo failed'**
  String get chatInputPhotoFailed;

  /// No description provided for @chatInputListening.
  ///
  /// In en, this message translates to:
  /// **'Listening...'**
  String get chatInputListening;

  /// No description provided for @chatInputAgentStarting.
  ///
  /// In en, this message translates to:
  /// **'Agent starting...'**
  String get chatInputAgentStarting;

  /// No description provided for @chatInputAgentFailed.
  ///
  /// In en, this message translates to:
  /// **'Agent failed, tap to retry'**
  String get chatInputAgentFailed;

  /// No description provided for @chatInputAuthRequired.
  ///
  /// In en, this message translates to:
  /// **'Please authenticate first'**
  String get chatInputAuthRequired;

  /// No description provided for @chatInputQueuedHint.
  ///
  /// In en, this message translates to:
  /// **'Queued, tap stop...'**
  String get chatInputQueuedHint;

  /// No description provided for @chatInputAttachmentHint.
  ///
  /// In en, this message translates to:
  /// **'Add a description or send directly...'**
  String get chatInputAttachmentHint;

  /// No description provided for @chatInputDefaultHint.
  ///
  /// In en, this message translates to:
  /// **'Ask a question or describe a task...'**
  String get chatInputDefaultHint;

  /// No description provided for @chatInputTooltipReference.
  ///
  /// In en, this message translates to:
  /// **'Reference file'**
  String get chatInputTooltipReference;

  /// No description provided for @chatInputTooltipAttachment.
  ///
  /// In en, this message translates to:
  /// **'Add attachment'**
  String get chatInputTooltipAttachment;

  /// No description provided for @chatInputAgentNotReady.
  ///
  /// In en, this message translates to:
  /// **'Agent not ready'**
  String get chatInputAgentNotReady;

  /// No description provided for @chatInputTooltipHistory.
  ///
  /// In en, this message translates to:
  /// **'Input history'**
  String get chatInputTooltipHistory;

  /// No description provided for @chatInputMaxReferences.
  ///
  /// In en, this message translates to:
  /// **'Context reference limit reached'**
  String get chatInputMaxReferences;

  /// No description provided for @chatInputQueueCount.
  ///
  /// In en, this message translates to:
  /// **'Queued ({count})'**
  String chatInputQueueCount(int count);

  /// No description provided for @chatInputVoiceNoResult.
  ///
  /// In en, this message translates to:
  /// **'No speech detected, please try again'**
  String get chatInputVoiceNoResult;

  /// No description provided for @chatInputVoiceUnsupported.
  ///
  /// In en, this message translates to:
  /// **'This device does not support speech-to-text, and the CLI does not support audio input'**
  String get chatInputVoiceUnsupported;

  /// No description provided for @chatInputNoHistory.
  ///
  /// In en, this message translates to:
  /// **'No input history'**
  String get chatInputNoHistory;

  /// No description provided for @chatInputHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Input History'**
  String get chatInputHistoryTitle;

  /// No description provided for @chatAgentReady.
  ///
  /// In en, this message translates to:
  /// **'AI Agent ready'**
  String get chatAgentReady;

  /// No description provided for @errorUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown error'**
  String get errorUnknown;

  /// No description provided for @widgetNoMatchingFiles.
  ///
  /// In en, this message translates to:
  /// **'No matching files'**
  String get widgetNoMatchingFiles;

  /// No description provided for @widgetExpandAll.
  ///
  /// In en, this message translates to:
  /// **'Expand all ({count} chars)'**
  String widgetExpandAll(int count);

  /// No description provided for @homeTabChat.
  ///
  /// In en, this message translates to:
  /// **'Chat'**
  String get homeTabChat;

  /// No description provided for @homeTabTerminal.
  ///
  /// In en, this message translates to:
  /// **'Terminal'**
  String get homeTabTerminal;

  /// No description provided for @homeTabProject.
  ///
  /// In en, this message translates to:
  /// **'Project'**
  String get homeTabProject;

  /// No description provided for @homeTabSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get homeTabSettings;

  /// No description provided for @terminalSwitchCli.
  ///
  /// In en, this message translates to:
  /// **'Switch CLI'**
  String get terminalSwitchCli;

  /// No description provided for @terminalNoProjectTitle.
  ///
  /// In en, this message translates to:
  /// **'Add a project first'**
  String get terminalNoProjectTitle;

  /// No description provided for @terminalNoProjectDescription.
  ///
  /// In en, this message translates to:
  /// **'Add a project directory in Settings'**
  String get terminalNoProjectDescription;

  /// No description provided for @terminalNoAgent.
  ///
  /// In en, this message translates to:
  /// **'No AI Agent detected'**
  String get terminalNoAgent;

  /// No description provided for @terminalNoAgentDescription.
  ///
  /// In en, this message translates to:
  /// **'Install an AI Agent in Settings'**
  String get terminalNoAgentDescription;

  /// No description provided for @terminalSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search...'**
  String get terminalSearchHint;

  /// No description provided for @terminalStarting.
  ///
  /// In en, this message translates to:
  /// **'Starting terminal...'**
  String get terminalStarting;

  /// No description provided for @terminalConnectingCli.
  ///
  /// In en, this message translates to:
  /// **'Connecting to desktop CLI'**
  String get terminalConnectingCli;

  /// No description provided for @terminalExtraKeyPaste.
  ///
  /// In en, this message translates to:
  /// **'Paste'**
  String get terminalExtraKeyPaste;

  /// No description provided for @filesTitle.
  ///
  /// In en, this message translates to:
  /// **'Project'**
  String get filesTitle;

  /// No description provided for @filesTreeNotReady.
  ///
  /// In en, this message translates to:
  /// **'File tree not ready'**
  String get filesTreeNotReady;

  /// No description provided for @filesNoProjectTitle.
  ///
  /// In en, this message translates to:
  /// **'Add a project first'**
  String get filesNoProjectTitle;

  /// No description provided for @filesNoProjectDescription.
  ///
  /// In en, this message translates to:
  /// **'Bind a workspace in Settings first to load the file browser.'**
  String get filesNoProjectDescription;

  /// No description provided for @filesNewFile.
  ///
  /// In en, this message translates to:
  /// **'New file'**
  String get filesNewFile;

  /// No description provided for @filesNewFolder.
  ///
  /// In en, this message translates to:
  /// **'New folder'**
  String get filesNewFolder;

  /// No description provided for @filesNewFileHint.
  ///
  /// In en, this message translates to:
  /// **'Enter file name'**
  String get filesNewFileHint;

  /// No description provided for @filesNewFolderHint.
  ///
  /// In en, this message translates to:
  /// **'Enter folder name'**
  String get filesNewFolderHint;

  /// No description provided for @filesCreateFailed.
  ///
  /// In en, this message translates to:
  /// **'Creation failed'**
  String get filesCreateFailed;

  /// No description provided for @filesRenameFailed.
  ///
  /// In en, this message translates to:
  /// **'Rename failed'**
  String get filesRenameFailed;

  /// No description provided for @filesDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Delete failed'**
  String get filesDeleteFailed;

  /// No description provided for @filesLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Loading failed'**
  String get filesLoadFailed;

  /// No description provided for @filesNoFiles.
  ///
  /// In en, this message translates to:
  /// **'No files'**
  String get filesNoFiles;

  /// No description provided for @filesUndo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get filesUndo;

  /// No description provided for @filesRedo.
  ///
  /// In en, this message translates to:
  /// **'Redo'**
  String get filesRedo;

  /// No description provided for @filesSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get filesSave;

  /// No description provided for @filesSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get filesSearch;

  /// No description provided for @filesViewMode.
  ///
  /// In en, this message translates to:
  /// **'View mode'**
  String get filesViewMode;

  /// No description provided for @filesEditMode.
  ///
  /// In en, this message translates to:
  /// **'Edit mode'**
  String get filesEditMode;

  /// No description provided for @filesSendToAi.
  ///
  /// In en, this message translates to:
  /// **'Send to AI'**
  String get filesSendToAi;

  /// No description provided for @filesNew.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get filesNew;

  /// No description provided for @filesCollapseAll.
  ///
  /// In en, this message translates to:
  /// **'Collapse all'**
  String get filesCollapseAll;

  /// No description provided for @filesRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get filesRefresh;

  /// No description provided for @filesSearchFilename.
  ///
  /// In en, this message translates to:
  /// **'Search file name...'**
  String get filesSearchFilename;

  /// No description provided for @filesSearchContent.
  ///
  /// In en, this message translates to:
  /// **'Search file content...'**
  String get filesSearchContent;

  /// No description provided for @filesSearchFileTab.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get filesSearchFileTab;

  /// No description provided for @filesSearchContentTab.
  ///
  /// In en, this message translates to:
  /// **'Content'**
  String get filesSearchContentTab;

  /// No description provided for @filesSearchRegex.
  ///
  /// In en, this message translates to:
  /// **'Regular expression'**
  String get filesSearchRegex;

  /// No description provided for @filesSearchCaseSensitive.
  ///
  /// In en, this message translates to:
  /// **'Case sensitive'**
  String get filesSearchCaseSensitive;

  /// No description provided for @filesSearchWholeWord.
  ///
  /// In en, this message translates to:
  /// **'Whole word'**
  String get filesSearchWholeWord;

  /// No description provided for @filesUnsavedTitle.
  ///
  /// In en, this message translates to:
  /// **'Unsaved changes'**
  String get filesUnsavedTitle;

  /// No description provided for @filesUnsavedMessage.
  ///
  /// In en, this message translates to:
  /// **'{fileName} has unsaved changes'**
  String filesUnsavedMessage(String fileName);

  /// No description provided for @fileViewerSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get fileViewerSearch;

  /// No description provided for @fileViewerUndo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get fileViewerUndo;

  /// No description provided for @fileViewerRedo.
  ///
  /// In en, this message translates to:
  /// **'Redo'**
  String get fileViewerRedo;

  /// No description provided for @fileViewerSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get fileViewerSave;

  /// No description provided for @fileViewerViewMode.
  ///
  /// In en, this message translates to:
  /// **'View mode'**
  String get fileViewerViewMode;

  /// No description provided for @fileViewerEditMode.
  ///
  /// In en, this message translates to:
  /// **'Edit mode'**
  String get fileViewerEditMode;

  /// No description provided for @fileViewerEmptyContent.
  ///
  /// In en, this message translates to:
  /// **'File content is empty'**
  String get fileViewerEmptyContent;

  /// No description provided for @gitNoWorkDir.
  ///
  /// In en, this message translates to:
  /// **'No working directory selected'**
  String get gitNoWorkDir;

  /// No description provided for @gitNoWorkDirDescription.
  ///
  /// In en, this message translates to:
  /// **'Add a project directory in Settings first.'**
  String get gitNoWorkDirDescription;

  /// No description provided for @gitPushUpToDate.
  ///
  /// In en, this message translates to:
  /// **'Already up to date'**
  String get gitPushUpToDate;

  /// No description provided for @gitPushSuccess.
  ///
  /// In en, this message translates to:
  /// **'Push succeeded'**
  String get gitPushSuccess;

  /// No description provided for @gitPullUpToDate.
  ///
  /// In en, this message translates to:
  /// **'Already up to date'**
  String get gitPullUpToDate;

  /// No description provided for @gitPullSuccess.
  ///
  /// In en, this message translates to:
  /// **'Pull succeeded'**
  String get gitPullSuccess;

  /// No description provided for @gitExecSuccess.
  ///
  /// In en, this message translates to:
  /// **'Command executed'**
  String get gitExecSuccess;

  /// No description provided for @gitPushNoCommits.
  ///
  /// In en, this message translates to:
  /// **'Push (no unpushed commits)'**
  String get gitPushNoCommits;

  /// No description provided for @gitTabChanges.
  ///
  /// In en, this message translates to:
  /// **'Changes'**
  String get gitTabChanges;

  /// No description provided for @gitTabCommit.
  ///
  /// In en, this message translates to:
  /// **'Commit'**
  String get gitTabCommit;

  /// No description provided for @gitTabHistory.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get gitTabHistory;

  /// No description provided for @gitProcessing.
  ///
  /// In en, this message translates to:
  /// **'Processing...'**
  String get gitProcessing;

  /// No description provided for @gitLoadTimeout.
  ///
  /// In en, this message translates to:
  /// **'Loading timed out'**
  String get gitLoadTimeout;

  /// No description provided for @gitRecheck.
  ///
  /// In en, this message translates to:
  /// **'Recheck'**
  String get gitRecheck;

  /// No description provided for @gitChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking...'**
  String get gitChecking;

  /// No description provided for @gitNoRepoDetected.
  ///
  /// In en, this message translates to:
  /// **'No Git repository detected'**
  String get gitNoRepoDetected;

  /// No description provided for @gitNoRepoHint.
  ///
  /// In en, this message translates to:
  /// **'Run git init in terminal to initialize.'**
  String get gitNoRepoHint;

  /// No description provided for @gitFoundRepos.
  ///
  /// In en, this message translates to:
  /// **'Found {count} Git repositories'**
  String gitFoundRepos(int count);

  /// No description provided for @gitDiscardTitle.
  ///
  /// In en, this message translates to:
  /// **'Discard changes'**
  String get gitDiscardTitle;

  /// No description provided for @gitDiscardMessage.
  ///
  /// In en, this message translates to:
  /// **'Discard all unstaged changes in {path}? Cannot be undone.'**
  String gitDiscardMessage(String path);

  /// No description provided for @gitDiscard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get gitDiscard;

  /// No description provided for @gitSwitchRepo.
  ///
  /// In en, this message translates to:
  /// **'Switch repository ({count})'**
  String gitSwitchRepo(int count);

  /// No description provided for @gitSwitchBranch.
  ///
  /// In en, this message translates to:
  /// **'Switch branch'**
  String get gitSwitchBranch;

  /// No description provided for @gitCopyHash.
  ///
  /// In en, this message translates to:
  /// **'Copy Hash'**
  String get gitCopyHash;

  /// No description provided for @gitBinaryFileToast.
  ///
  /// In en, this message translates to:
  /// **'Cannot get file content (binary file)'**
  String get gitBinaryFileToast;

  /// No description provided for @gitChangedFiles.
  ///
  /// In en, this message translates to:
  /// **'Changed files ({count})'**
  String gitChangedFiles(int count);

  /// No description provided for @gitChangesClean.
  ///
  /// In en, this message translates to:
  /// **'Working tree clean'**
  String get gitChangesClean;

  /// No description provided for @gitChangesCleanDesc.
  ///
  /// In en, this message translates to:
  /// **'No uncommitted changes'**
  String get gitChangesCleanDesc;

  /// No description provided for @gitChangesStagedCount.
  ///
  /// In en, this message translates to:
  /// **'Staged ({count})'**
  String gitChangesStagedCount(int count);

  /// No description provided for @gitChangesUnstageAll.
  ///
  /// In en, this message translates to:
  /// **'Unstage all'**
  String get gitChangesUnstageAll;

  /// No description provided for @gitChangesUnstagedCount.
  ///
  /// In en, this message translates to:
  /// **'Unstaged ({count})'**
  String gitChangesUnstagedCount(int count);

  /// No description provided for @gitChangesStageAll.
  ///
  /// In en, this message translates to:
  /// **'Stage all'**
  String get gitChangesStageAll;

  /// No description provided for @gitChangesUntrackedCount.
  ///
  /// In en, this message translates to:
  /// **'Untracked ({count})'**
  String gitChangesUntrackedCount(int count);

  /// No description provided for @gitChangesAddAll.
  ///
  /// In en, this message translates to:
  /// **'Add all'**
  String get gitChangesAddAll;

  /// No description provided for @gitCommitStagedReady.
  ///
  /// In en, this message translates to:
  /// **'{count} files staged, ready to commit'**
  String gitCommitStagedReady(int count);

  /// No description provided for @gitCommitNoStaged.
  ///
  /// In en, this message translates to:
  /// **'No staged files'**
  String get gitCommitNoStaged;

  /// No description provided for @gitCommitMessageHint.
  ///
  /// In en, this message translates to:
  /// **'Enter commit message...'**
  String get gitCommitMessageHint;

  /// No description provided for @gitCommitButton.
  ///
  /// In en, this message translates to:
  /// **'Commit'**
  String get gitCommitButton;

  /// No description provided for @gitCommitPulling.
  ///
  /// In en, this message translates to:
  /// **'Pulling...'**
  String get gitCommitPulling;

  /// No description provided for @gitCommitPushing.
  ///
  /// In en, this message translates to:
  /// **'Pushing...'**
  String get gitCommitPushing;

  /// No description provided for @gitLogSelectBranch.
  ///
  /// In en, this message translates to:
  /// **'Select branch'**
  String get gitLogSelectBranch;

  /// No description provided for @gitLogSelectAuthor.
  ///
  /// In en, this message translates to:
  /// **'Select author'**
  String get gitLogSelectAuthor;

  /// No description provided for @gitLogSelectDateRange.
  ///
  /// In en, this message translates to:
  /// **'Select date range'**
  String get gitLogSelectDateRange;

  /// No description provided for @gitLogToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get gitLogToday;

  /// No description provided for @gitLogLast7Days.
  ///
  /// In en, this message translates to:
  /// **'Last 7 days'**
  String get gitLogLast7Days;

  /// No description provided for @gitLogLast30Days.
  ///
  /// In en, this message translates to:
  /// **'Last 30 days'**
  String get gitLogLast30Days;

  /// No description provided for @gitLogLast90Days.
  ///
  /// In en, this message translates to:
  /// **'Last 90 days'**
  String get gitLogLast90Days;

  /// No description provided for @gitLogCustomRange.
  ///
  /// In en, this message translates to:
  /// **'Custom range'**
  String get gitLogCustomRange;

  /// No description provided for @gitLogClearDateFilter.
  ///
  /// In en, this message translates to:
  /// **'Clear date filter'**
  String get gitLogClearDateFilter;

  /// No description provided for @gitLogSearchCommit.
  ///
  /// In en, this message translates to:
  /// **'Search commit...'**
  String get gitLogSearchCommit;

  /// No description provided for @gitLogBranch.
  ///
  /// In en, this message translates to:
  /// **'Branch'**
  String get gitLogBranch;

  /// No description provided for @gitLogAuthor.
  ///
  /// In en, this message translates to:
  /// **'Author'**
  String get gitLogAuthor;

  /// No description provided for @gitLogDate.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get gitLogDate;

  /// No description provided for @gitLogFrom.
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get gitLogFrom;

  /// No description provided for @gitLogUntil.
  ///
  /// In en, this message translates to:
  /// **'Until'**
  String get gitLogUntil;

  /// No description provided for @gitLogRemote.
  ///
  /// In en, this message translates to:
  /// **'Remote'**
  String get gitLogRemote;

  /// No description provided for @gitLogLocal.
  ///
  /// In en, this message translates to:
  /// **'Local'**
  String get gitLogLocal;

  /// No description provided for @gitShellHint.
  ///
  /// In en, this message translates to:
  /// **'Enter git commands'**
  String get gitShellHint;

  /// No description provided for @gitShellRestriction.
  ///
  /// In en, this message translates to:
  /// **'Only git operations allowed'**
  String get gitShellRestriction;

  /// No description provided for @gitShellConfirmExecute.
  ///
  /// In en, this message translates to:
  /// **'Confirm execute'**
  String get gitShellConfirmExecute;

  /// No description provided for @gitLogNoMatchingCommits.
  ///
  /// In en, this message translates to:
  /// **'No matching commits'**
  String get gitLogNoMatchingCommits;

  /// No description provided for @gitLogNoFilteredCommits.
  ///
  /// In en, this message translates to:
  /// **'No commits match filters'**
  String get gitLogNoFilteredCommits;

  /// No description provided for @gitLogNoHistory.
  ///
  /// In en, this message translates to:
  /// **'No commit history'**
  String get gitLogNoHistory;

  /// No description provided for @pluginTitle.
  ///
  /// In en, this message translates to:
  /// **'Plugin Management'**
  String get pluginTitle;

  /// No description provided for @pluginEmpty.
  ///
  /// In en, this message translates to:
  /// **'No plugins'**
  String get pluginEmpty;

  /// No description provided for @pluginEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Tap + to install plugins'**
  String get pluginEmptyHint;

  /// No description provided for @pluginStatusActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get pluginStatusActive;

  /// No description provided for @pluginStatusDisabled.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get pluginStatusDisabled;

  /// No description provided for @pluginStatusError.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get pluginStatusError;

  /// No description provided for @pluginStatusUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get pluginStatusUnavailable;

  /// No description provided for @pluginStatusUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get pluginStatusUnknown;

  /// No description provided for @pluginUninstallTitle.
  ///
  /// In en, this message translates to:
  /// **'Uninstall plugin'**
  String get pluginUninstallTitle;

  /// No description provided for @pluginUninstallMessage.
  ///
  /// In en, this message translates to:
  /// **'Uninstall \"{name}\"?'**
  String pluginUninstallMessage(String name);

  /// No description provided for @pluginInstallTitle.
  ///
  /// In en, this message translates to:
  /// **'Install plugin'**
  String get pluginInstallTitle;

  /// No description provided for @pluginInstallSource.
  ///
  /// In en, this message translates to:
  /// **'Install source'**
  String get pluginInstallSource;

  /// No description provided for @pluginInstallFailed.
  ///
  /// In en, this message translates to:
  /// **'Installation failed'**
  String get pluginInstallFailed;

  /// No description provided for @pluginLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Loading failed'**
  String get pluginLoadFailed;

  /// No description provided for @thoughtBlockThinking.
  ///
  /// In en, this message translates to:
  /// **'Thinking...'**
  String get thoughtBlockThinking;

  /// No description provided for @thoughtBlockDone.
  ///
  /// In en, this message translates to:
  /// **'Thought process'**
  String get thoughtBlockDone;

  /// No description provided for @codeBlockCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get codeBlockCopy;

  /// No description provided for @codeBlockCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied to clipboard'**
  String get codeBlockCopied;

  /// No description provided for @planCardTitle.
  ///
  /// In en, this message translates to:
  /// **'Plan'**
  String get planCardTitle;

  /// No description provided for @diffNoChanges.
  ///
  /// In en, this message translates to:
  /// **'No changes'**
  String get diffNoChanges;

  /// No description provided for @toolCallKindExecute.
  ///
  /// In en, this message translates to:
  /// **'Command'**
  String get toolCallKindExecute;

  /// No description provided for @toolCallKindEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get toolCallKindEdit;

  /// No description provided for @toolCallKindSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get toolCallKindSearch;

  /// No description provided for @toolCallKindFetch.
  ///
  /// In en, this message translates to:
  /// **'Network'**
  String get toolCallKindFetch;

  /// No description provided for @toolCallKindMove.
  ///
  /// In en, this message translates to:
  /// **'Move'**
  String get toolCallKindMove;

  /// No description provided for @toolCallKindDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get toolCallKindDelete;

  /// No description provided for @toolCallKindThink.
  ///
  /// In en, this message translates to:
  /// **'Reason'**
  String get toolCallKindThink;

  /// No description provided for @toolCallKindRead.
  ///
  /// In en, this message translates to:
  /// **'Read'**
  String get toolCallKindRead;

  /// No description provided for @toolCallKindDefault.
  ///
  /// In en, this message translates to:
  /// **'Tool'**
  String get toolCallKindDefault;

  /// No description provided for @toolCallDefaultName.
  ///
  /// In en, this message translates to:
  /// **'Tool call'**
  String get toolCallDefaultName;

  /// No description provided for @toolCallAddedToContext.
  ///
  /// In en, this message translates to:
  /// **'Added to context'**
  String get toolCallAddedToContext;

  /// No description provided for @toolCallWaitingTerminal.
  ///
  /// In en, this message translates to:
  /// **'Waiting for terminal output...'**
  String get toolCallWaitingTerminal;

  /// No description provided for @connectionBannerReconnected.
  ///
  /// In en, this message translates to:
  /// **'Reconnected'**
  String get connectionBannerReconnected;

  /// No description provided for @connectionBannerReconnecting.
  ///
  /// In en, this message translates to:
  /// **'Disconnected, reconnecting ({attempt}/{maxAttempts})...'**
  String connectionBannerReconnecting(int attempt, int maxAttempts);

  /// No description provided for @connectionBannerFailed.
  ///
  /// In en, this message translates to:
  /// **'Connection failed'**
  String get connectionBannerFailed;

  /// No description provided for @connectionBannerDisconnect.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get connectionBannerDisconnect;

  /// No description provided for @connectionStatusLan.
  ///
  /// In en, this message translates to:
  /// **'LAN Direct'**
  String get connectionStatusLan;

  /// No description provided for @connectionStatusRelay.
  ///
  /// In en, this message translates to:
  /// **'Relay'**
  String get connectionStatusRelay;

  /// No description provided for @connectionStatusTunnel.
  ///
  /// In en, this message translates to:
  /// **'Tunnel'**
  String get connectionStatusTunnel;

  /// No description provided for @connectionStatusTimeout.
  ///
  /// In en, this message translates to:
  /// **'Timeout'**
  String get connectionStatusTimeout;

  /// No description provided for @connectionStatusDetails.
  ///
  /// In en, this message translates to:
  /// **'Connection Details'**
  String get connectionStatusDetails;

  /// No description provided for @connectionStatusMode.
  ///
  /// In en, this message translates to:
  /// **'Mode'**
  String get connectionStatusMode;

  /// No description provided for @connectionStatusAddress.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get connectionStatusAddress;

  /// No description provided for @connectionStatusLatency.
  ///
  /// In en, this message translates to:
  /// **'Latency'**
  String get connectionStatusLatency;

  /// No description provided for @connectionStatusUptime.
  ///
  /// In en, this message translates to:
  /// **'Uptime'**
  String get connectionStatusUptime;

  /// No description provided for @connectionStatusDisconnect.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get connectionStatusDisconnect;

  /// No description provided for @authFormGetKey.
  ///
  /// In en, this message translates to:
  /// **'Get Key'**
  String get authFormGetKey;

  /// No description provided for @authFormAuthenticate.
  ///
  /// In en, this message translates to:
  /// **'Authenticate'**
  String get authFormAuthenticate;

  /// No description provided for @authFormOptional.
  ///
  /// In en, this message translates to:
  /// **'optional'**
  String get authFormOptional;

  /// No description provided for @authFormPasteKey.
  ///
  /// In en, this message translates to:
  /// **'Paste key...'**
  String get authFormPasteKey;

  /// No description provided for @authFormEnterValue.
  ///
  /// In en, this message translates to:
  /// **'Enter value...'**
  String get authFormEnterValue;

  /// No description provided for @authFormFillField.
  ///
  /// In en, this message translates to:
  /// **'Please fill in {field}'**
  String authFormFillField(String field);

  /// No description provided for @authFormLinkCopied.
  ///
  /// In en, this message translates to:
  /// **'Link copied'**
  String get authFormLinkCopied;

  /// No description provided for @deviceCodeTitle.
  ///
  /// In en, this message translates to:
  /// **'Login in browser'**
  String get deviceCodeTitle;

  /// No description provided for @deviceCodeDescription.
  ///
  /// In en, this message translates to:
  /// **'Open the link and enter the code'**
  String get deviceCodeDescription;

  /// No description provided for @deviceCodeLabel.
  ///
  /// In en, this message translates to:
  /// **'Verification code'**
  String get deviceCodeLabel;

  /// No description provided for @deviceCodeTapToCopy.
  ///
  /// In en, this message translates to:
  /// **'Tap to copy code'**
  String get deviceCodeTapToCopy;

  /// No description provided for @deviceCodeCopied.
  ///
  /// In en, this message translates to:
  /// **'Code copied'**
  String get deviceCodeCopied;

  /// No description provided for @deviceCodeWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting for login...'**
  String get deviceCodeWaiting;

  /// No description provided for @deviceCodeUrlCopied.
  ///
  /// In en, this message translates to:
  /// **'Link copied'**
  String get deviceCodeUrlCopied;

  /// No description provided for @deviceCodeSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip for now'**
  String get deviceCodeSkip;

  /// No description provided for @deviceCodeOpenBrowser.
  ///
  /// In en, this message translates to:
  /// **'Open in browser'**
  String get deviceCodeOpenBrowser;

  /// No description provided for @deviceCodeCannotOpenBrowser.
  ///
  /// In en, this message translates to:
  /// **'Cannot open browser'**
  String get deviceCodeCannotOpenBrowser;

  /// No description provided for @deviceCodeLinkCopied.
  ///
  /// In en, this message translates to:
  /// **'Link copied to clipboard'**
  String get deviceCodeLinkCopied;

  /// No description provided for @deviceCodeCheckTerminal.
  ///
  /// In en, this message translates to:
  /// **'Check computer terminal for code'**
  String get deviceCodeCheckTerminal;

  /// No description provided for @contextPickerTitle.
  ///
  /// In en, this message translates to:
  /// **'Add Context'**
  String get contextPickerTitle;

  /// No description provided for @contextPickerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Select context type'**
  String get contextPickerSubtitle;

  /// No description provided for @contextPickerFilesHint.
  ///
  /// In en, this message translates to:
  /// **'Search files'**
  String get contextPickerFilesHint;

  /// No description provided for @contextPickerFolderHint.
  ///
  /// In en, this message translates to:
  /// **'Select folder'**
  String get contextPickerFolderHint;

  /// No description provided for @contextPickerCurrentFileHint.
  ///
  /// In en, this message translates to:
  /// **'Reference current file'**
  String get contextPickerCurrentFileHint;

  /// No description provided for @contextPickerTerminalHint.
  ///
  /// In en, this message translates to:
  /// **'Reference terminal output'**
  String get contextPickerTerminalHint;

  /// No description provided for @contextPickerUrlHint.
  ///
  /// In en, this message translates to:
  /// **'Enter URL'**
  String get contextPickerUrlHint;

  /// No description provided for @contextPickerGitDiffHint.
  ///
  /// In en, this message translates to:
  /// **'Reference git changes'**
  String get contextPickerGitDiffHint;

  /// No description provided for @contextPickerProblemsHint.
  ///
  /// In en, this message translates to:
  /// **'Reference problems'**
  String get contextPickerProblemsHint;

  /// No description provided for @contextPickerFileCount.
  ///
  /// In en, this message translates to:
  /// **'{count} files'**
  String contextPickerFileCount(int count);

  /// No description provided for @contextPickerNoCurrentFile.
  ///
  /// In en, this message translates to:
  /// **'No file open'**
  String get contextPickerNoCurrentFile;

  /// No description provided for @contextPickerNoTerminalOutput.
  ///
  /// In en, this message translates to:
  /// **'No terminal output'**
  String get contextPickerNoTerminalOutput;

  /// No description provided for @contextPickerNoFolders.
  ///
  /// In en, this message translates to:
  /// **'No folders available'**
  String get contextPickerNoFolders;

  /// No description provided for @slashCmdNew.
  ///
  /// In en, this message translates to:
  /// **'New session'**
  String get slashCmdNew;

  /// No description provided for @slashCmdClear.
  ///
  /// In en, this message translates to:
  /// **'Clear chat'**
  String get slashCmdClear;

  /// No description provided for @slashCmdHistory.
  ///
  /// In en, this message translates to:
  /// **'View history'**
  String get slashCmdHistory;

  /// No description provided for @slashCmdFiles.
  ///
  /// In en, this message translates to:
  /// **'View files'**
  String get slashCmdFiles;

  /// No description provided for @slashCmdTerminal.
  ///
  /// In en, this message translates to:
  /// **'Open terminal'**
  String get slashCmdTerminal;

  /// No description provided for @slashCmdDiff.
  ///
  /// In en, this message translates to:
  /// **'View changes'**
  String get slashCmdDiff;

  /// No description provided for @slashCmdModel.
  ///
  /// In en, this message translates to:
  /// **'Switch model'**
  String get slashCmdModel;

  /// No description provided for @slashCmdProject.
  ///
  /// In en, this message translates to:
  /// **'Switch project'**
  String get slashCmdProject;

  /// No description provided for @slashCategorySession.
  ///
  /// In en, this message translates to:
  /// **'Session'**
  String get slashCategorySession;

  /// No description provided for @slashCategoryTools.
  ///
  /// In en, this message translates to:
  /// **'Tools'**
  String get slashCategoryTools;

  /// No description provided for @slashCategoryConfig.
  ///
  /// In en, this message translates to:
  /// **'Config'**
  String get slashCategoryConfig;

  /// No description provided for @slashCategoryCli.
  ///
  /// In en, this message translates to:
  /// **'CLI Commands'**
  String get slashCategoryCli;

  /// No description provided for @slashCmdHint.
  ///
  /// In en, this message translates to:
  /// **'Tap to select · Esc to close'**
  String get slashCmdHint;

  /// No description provided for @codeEditorSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search...'**
  String get codeEditorSearchHint;

  /// No description provided for @codeEditorReplaceHint.
  ///
  /// In en, this message translates to:
  /// **'Replace...'**
  String get codeEditorReplaceHint;

  /// No description provided for @codeEditorReplace.
  ///
  /// In en, this message translates to:
  /// **'Replace'**
  String get codeEditorReplace;

  /// No description provided for @codeEditorReplaceAll.
  ///
  /// In en, this message translates to:
  /// **'Replace all'**
  String get codeEditorReplaceAll;

  /// No description provided for @fileActionsAddToContext.
  ///
  /// In en, this message translates to:
  /// **'Add to context'**
  String get fileActionsAddToContext;

  /// No description provided for @fileActionsAddedToContext.
  ///
  /// In en, this message translates to:
  /// **'Added to context'**
  String get fileActionsAddedToContext;

  /// No description provided for @fileActionsNewFile.
  ///
  /// In en, this message translates to:
  /// **'New file'**
  String get fileActionsNewFile;

  /// No description provided for @fileActionsNewFolder.
  ///
  /// In en, this message translates to:
  /// **'New folder'**
  String get fileActionsNewFolder;

  /// No description provided for @fileActionsCopyPath.
  ///
  /// In en, this message translates to:
  /// **'Copy path'**
  String get fileActionsCopyPath;

  /// No description provided for @fileActionsPathCopied.
  ///
  /// In en, this message translates to:
  /// **'Path copied'**
  String get fileActionsPathCopied;

  /// No description provided for @fileActionsSendToAi.
  ///
  /// In en, this message translates to:
  /// **'Send to AI'**
  String get fileActionsSendToAi;

  /// No description provided for @fileActionsRunFile.
  ///
  /// In en, this message translates to:
  /// **'Run file'**
  String get fileActionsRunFile;

  /// No description provided for @fileActionsRename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get fileActionsRename;

  /// No description provided for @fileActionsEnterNewName.
  ///
  /// In en, this message translates to:
  /// **'Enter new name'**
  String get fileActionsEnterNewName;

  /// No description provided for @fileActionsConfirmDelete.
  ///
  /// In en, this message translates to:
  /// **'Confirm delete'**
  String get fileActionsConfirmDelete;

  /// No description provided for @fileActionsDeleteMessage.
  ///
  /// In en, this message translates to:
  /// **'Delete {name}?'**
  String fileActionsDeleteMessage(String name);

  /// No description provided for @fileActionsEnterFileName.
  ///
  /// In en, this message translates to:
  /// **'Enter file name'**
  String get fileActionsEnterFileName;

  /// No description provided for @fileActionsEnterFolderName.
  ///
  /// In en, this message translates to:
  /// **'Enter folder name'**
  String get fileActionsEnterFolderName;

  /// No description provided for @fileSearchTypeToSearch.
  ///
  /// In en, this message translates to:
  /// **'Type to search'**
  String get fileSearchTypeToSearch;

  /// No description provided for @fileSearchNoFileMatch.
  ///
  /// In en, this message translates to:
  /// **'No matching files'**
  String get fileSearchNoFileMatch;

  /// No description provided for @fileSearchNoContentMatch.
  ///
  /// In en, this message translates to:
  /// **'No matching content'**
  String get fileSearchNoContentMatch;

  /// No description provided for @fileSearchResultCount.
  ///
  /// In en, this message translates to:
  /// **'{matchCount} results in {fileCount} files'**
  String fileSearchResultCount(int fileCount, int matchCount);

  /// No description provided for @attachmentAgentNotReady.
  ///
  /// In en, this message translates to:
  /// **'Agent not ready'**
  String get attachmentAgentNotReady;

  /// No description provided for @attachmentImage.
  ///
  /// In en, this message translates to:
  /// **'Image'**
  String get attachmentImage;

  /// No description provided for @attachmentImageNotSupported.
  ///
  /// In en, this message translates to:
  /// **'Images not supported'**
  String get attachmentImageNotSupported;

  /// No description provided for @attachmentAudio.
  ///
  /// In en, this message translates to:
  /// **'Audio'**
  String get attachmentAudio;

  /// No description provided for @attachmentAudioNotSupported.
  ///
  /// In en, this message translates to:
  /// **'Audio not supported'**
  String get attachmentAudioNotSupported;

  /// No description provided for @attachmentAudioComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Audio coming soon'**
  String get attachmentAudioComingSoon;

  /// No description provided for @attachmentFileRef.
  ///
  /// In en, this message translates to:
  /// **'File reference'**
  String get attachmentFileRef;

  /// No description provided for @attachmentNotSupported.
  ///
  /// In en, this message translates to:
  /// **'Not supported'**
  String get attachmentNotSupported;

  /// No description provided for @cliSelectorTitle.
  ///
  /// In en, this message translates to:
  /// **'Select CLI'**
  String get cliSelectorTitle;

  /// No description provided for @configPanelAgentSettings.
  ///
  /// In en, this message translates to:
  /// **'Agent Settings'**
  String get configPanelAgentSettings;

  /// No description provided for @configPanelAutoApprove.
  ///
  /// In en, this message translates to:
  /// **'Auto-approve permissions'**
  String get configPanelAutoApprove;

  /// No description provided for @configPanelAutoApproveDesc.
  ///
  /// In en, this message translates to:
  /// **'Don\'t ask for operations'**
  String get configPanelAutoApproveDesc;

  /// No description provided for @configPanelSwitchedTo.
  ///
  /// In en, this message translates to:
  /// **'Switched to {name}'**
  String configPanelSwitchedTo(String name);

  /// No description provided for @configPanelOn.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get configPanelOn;

  /// No description provided for @configPanelOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get configPanelOff;

  /// No description provided for @slashCmdImmediate.
  ///
  /// In en, this message translates to:
  /// **'Instant'**
  String get slashCmdImmediate;

  /// No description provided for @contextPickerSelectTerminal.
  ///
  /// In en, this message translates to:
  /// **'Select Terminal'**
  String get contextPickerSelectTerminal;

  /// No description provided for @contextPickerTerminalN.
  ///
  /// In en, this message translates to:
  /// **'Terminal {id}'**
  String contextPickerTerminalN(String id);

  /// No description provided for @contextPickerTerminalLines.
  ///
  /// In en, this message translates to:
  /// **'{count} lines of output'**
  String contextPickerTerminalLines(int count);

  /// No description provided for @contextPickerEnterUrl.
  ///
  /// In en, this message translates to:
  /// **'Enter URL'**
  String get contextPickerEnterUrl;

  /// No description provided for @projectPickerTitle.
  ///
  /// In en, this message translates to:
  /// **'Select Project'**
  String get projectPickerTitle;

  /// No description provided for @projectPickerSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search project name...'**
  String get projectPickerSearchHint;

  /// No description provided for @projectPickerFirstProject.
  ///
  /// In en, this message translates to:
  /// **'Start your first project'**
  String get projectPickerFirstProject;

  /// No description provided for @projectPickerFirstProjectDesc.
  ///
  /// In en, this message translates to:
  /// **'Search project name, browse directories, or enter path manually'**
  String get projectPickerFirstProjectDesc;

  /// No description provided for @projectPickerRecent.
  ///
  /// In en, this message translates to:
  /// **'Recent Projects'**
  String get projectPickerRecent;

  /// No description provided for @projectPickerNoMatch.
  ///
  /// In en, this message translates to:
  /// **'No matching projects'**
  String get projectPickerNoMatch;

  /// No description provided for @projectPickerNoMatchDesc.
  ///
  /// In en, this message translates to:
  /// **'Try a different keyword, or browse directories manually'**
  String get projectPickerNoMatchDesc;

  /// No description provided for @projectPickerFoundCount.
  ///
  /// In en, this message translates to:
  /// **'Found {count} projects'**
  String projectPickerFoundCount(int count);

  /// No description provided for @projectPickerDirNotExist.
  ///
  /// In en, this message translates to:
  /// **'{path} (directory not found)'**
  String projectPickerDirNotExist(String path);

  /// No description provided for @projectPickerBrowse.
  ///
  /// In en, this message translates to:
  /// **'Browse Directories'**
  String get projectPickerBrowse;

  /// No description provided for @projectPickerBrowseDesc.
  ///
  /// In en, this message translates to:
  /// **'Select a project directory from the file system'**
  String get projectPickerBrowseDesc;

  /// No description provided for @projectPickerManualInput.
  ///
  /// In en, this message translates to:
  /// **'Enter Path Manually'**
  String get projectPickerManualInput;

  /// No description provided for @projectPickerManualInputDesc.
  ///
  /// In en, this message translates to:
  /// **'Enter the full path to your project'**
  String get projectPickerManualInputDesc;

  /// No description provided for @projectPickerDirEmpty.
  ///
  /// In en, this message translates to:
  /// **'This directory is empty'**
  String get projectPickerDirEmpty;

  /// No description provided for @projectPickerDirEmptyDesc.
  ///
  /// In en, this message translates to:
  /// **'No subdirectories found'**
  String get projectPickerDirEmptyDesc;

  /// No description provided for @projectPickerSelectDir.
  ///
  /// In en, this message translates to:
  /// **'Select This Directory'**
  String get projectPickerSelectDir;

  /// No description provided for @componentDialogSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get componentDialogSave;

  /// No description provided for @componentDialogDiscard.
  ///
  /// In en, this message translates to:
  /// **'Don\'t save'**
  String get componentDialogDiscard;

  /// No description provided for @componentSearchClearFilter.
  ///
  /// In en, this message translates to:
  /// **'Clear filter'**
  String get componentSearchClearFilter;

  /// No description provided for @componentSearchNoMatch.
  ///
  /// In en, this message translates to:
  /// **'No matches'**
  String get componentSearchNoMatch;

  /// No description provided for @componentSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search...'**
  String get componentSearchHint;

  /// No description provided for @componentSendToAiHint.
  ///
  /// In en, this message translates to:
  /// **'Describe what you want AI to do...'**
  String get componentSendToAiHint;

  /// No description provided for @componentSendToAiButton.
  ///
  /// In en, this message translates to:
  /// **'Send to AI'**
  String get componentSendToAiButton;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsControlCenterSubtitle.
  ///
  /// In en, this message translates to:
  /// **'MobileFlow Control Center'**
  String get settingsControlCenterSubtitle;

  /// No description provided for @settingsControlCenterDescription.
  ///
  /// In en, this message translates to:
  /// **'Manage projects, connections, and AI tools like a portable dev workstation.'**
  String get settingsControlCenterDescription;

  /// No description provided for @settingsLinkOnline.
  ///
  /// In en, this message translates to:
  /// **'Link Online'**
  String get settingsLinkOnline;

  /// No description provided for @settingsLinkOffline.
  ///
  /// In en, this message translates to:
  /// **'Waiting to connect'**
  String get settingsLinkOffline;

  /// No description provided for @settingsProjectsSection.
  ///
  /// In en, this message translates to:
  /// **'Projects'**
  String get settingsProjectsSection;

  /// No description provided for @settingsAddProject.
  ///
  /// In en, this message translates to:
  /// **'Add Project'**
  String get settingsAddProject;

  /// No description provided for @settingsConnectionSection.
  ///
  /// In en, this message translates to:
  /// **'Connection'**
  String get settingsConnectionSection;

  /// No description provided for @settingsConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get settingsConnected;

  /// No description provided for @settingsDisconnected.
  ///
  /// In en, this message translates to:
  /// **'Disconnected'**
  String get settingsDisconnected;

  /// No description provided for @settingsClearConnections.
  ///
  /// In en, this message translates to:
  /// **'Clear Saved Connections'**
  String get settingsClearConnections;

  /// No description provided for @settingsClearConnectionsDesc.
  ///
  /// In en, this message translates to:
  /// **'Clear all saved connection info and keys'**
  String get settingsClearConnectionsDesc;

  /// No description provided for @settingsClearedConnections.
  ///
  /// In en, this message translates to:
  /// **'All saved connection info cleared'**
  String get settingsClearedConnections;

  /// No description provided for @settingsAppearanceSection.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsAppearanceSection;

  /// No description provided for @settingsDarkTheme.
  ///
  /// In en, this message translates to:
  /// **'Dark Theme'**
  String get settingsDarkTheme;

  /// No description provided for @settingsLanguageLabel.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguageLabel;

  /// No description provided for @settingsEditorSection.
  ///
  /// In en, this message translates to:
  /// **'Editor'**
  String get settingsEditorSection;

  /// No description provided for @settingsCodeTheme.
  ///
  /// In en, this message translates to:
  /// **'Code Theme'**
  String get settingsCodeTheme;

  /// No description provided for @settingsSelectCodeTheme.
  ///
  /// In en, this message translates to:
  /// **'Select Code Theme'**
  String get settingsSelectCodeTheme;

  /// No description provided for @settingsWordWrap.
  ///
  /// In en, this message translates to:
  /// **'Word Wrap'**
  String get settingsWordWrap;

  /// No description provided for @settingsWordWrapOn.
  ///
  /// In en, this message translates to:
  /// **'Long lines wrap'**
  String get settingsWordWrapOn;

  /// No description provided for @settingsWordWrapOff.
  ///
  /// In en, this message translates to:
  /// **'Long lines scroll horizontally'**
  String get settingsWordWrapOff;

  /// No description provided for @settingsShowLineNumbers.
  ///
  /// In en, this message translates to:
  /// **'Show Line Numbers'**
  String get settingsShowLineNumbers;

  /// No description provided for @settingsFontSize.
  ///
  /// In en, this message translates to:
  /// **'Font Size'**
  String get settingsFontSize;

  /// No description provided for @settingsPluginsSection.
  ///
  /// In en, this message translates to:
  /// **'Plugins'**
  String get settingsPluginsSection;

  /// No description provided for @settingsPluginManagement.
  ///
  /// In en, this message translates to:
  /// **'Plugin Management'**
  String get settingsPluginManagement;

  /// No description provided for @settingsPluginManagementDesc.
  ///
  /// In en, this message translates to:
  /// **'Install, enable, and manage extension plugins'**
  String get settingsPluginManagementDesc;

  /// No description provided for @settingsCliToolsSection.
  ///
  /// In en, this message translates to:
  /// **'AI CLI Tools'**
  String get settingsCliToolsSection;

  /// No description provided for @settingsAddCustomAgent.
  ///
  /// In en, this message translates to:
  /// **'Add Custom Agent'**
  String get settingsAddCustomAgent;

  /// No description provided for @settingsInstalled.
  ///
  /// In en, this message translates to:
  /// **'Installed'**
  String get settingsInstalled;

  /// No description provided for @settingsNotInstalled.
  ///
  /// In en, this message translates to:
  /// **'Not installed'**
  String get settingsNotInstalled;

  /// No description provided for @settingsNProjects.
  ///
  /// In en, this message translates to:
  /// **'{count} projects'**
  String settingsNProjects(int count);

  /// No description provided for @settingsNClis.
  ///
  /// In en, this message translates to:
  /// **'{count} CLIs'**
  String settingsNClis(int count);

  /// No description provided for @settingsSwitchedTo.
  ///
  /// In en, this message translates to:
  /// **'Switched to: {name}'**
  String settingsSwitchedTo(String name);

  /// No description provided for @settingsRemoveTooltip.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get settingsRemoveTooltip;

  /// No description provided for @settingsUninstallTooltip.
  ///
  /// In en, this message translates to:
  /// **'Uninstall'**
  String get settingsUninstallTooltip;

  /// No description provided for @settingsPreparingInstall.
  ///
  /// In en, this message translates to:
  /// **'Preparing to install...'**
  String get settingsPreparingInstall;

  /// No description provided for @settingsInstallingProgress.
  ///
  /// In en, this message translates to:
  /// **'Installing {label} ({step}/{total})...'**
  String settingsInstallingProgress(String label, int step, int total);

  /// No description provided for @settingsInstallFailed.
  ///
  /// In en, this message translates to:
  /// **'Install Failed'**
  String get settingsInstallFailed;

  /// No description provided for @settingsUninstallAgent.
  ///
  /// In en, this message translates to:
  /// **'Uninstall Agent'**
  String get settingsUninstallAgent;

  /// No description provided for @settingsUninstallConfirm.
  ///
  /// In en, this message translates to:
  /// **'Uninstall \"{name}\"?\nAll related components will be removed.'**
  String settingsUninstallConfirm(String name);

  /// No description provided for @settingsPreparingUninstall.
  ///
  /// In en, this message translates to:
  /// **'Preparing to uninstall...'**
  String get settingsPreparingUninstall;

  /// No description provided for @settingsUninstallingProgress.
  ///
  /// In en, this message translates to:
  /// **'Uninstalling {label} ({step}/{total})...'**
  String settingsUninstallingProgress(String label, int step, int total);

  /// No description provided for @settingsAddCustomAgentTitle.
  ///
  /// In en, this message translates to:
  /// **'Add Custom Agent'**
  String get settingsAddCustomAgentTitle;

  /// No description provided for @settingsAgentNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get settingsAgentNameLabel;

  /// No description provided for @settingsAgentNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. My Agent'**
  String get settingsAgentNameHint;

  /// No description provided for @settingsAgentCommandLabel.
  ///
  /// In en, this message translates to:
  /// **'Command'**
  String get settingsAgentCommandLabel;

  /// No description provided for @settingsAgentCommandHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. my-agent'**
  String get settingsAgentCommandHint;

  /// No description provided for @settingsAgentArgsLabel.
  ///
  /// In en, this message translates to:
  /// **'Arguments (space separated)'**
  String get settingsAgentArgsLabel;

  /// No description provided for @settingsAgentArgsHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. acp or --acp'**
  String get settingsAgentArgsHint;

  /// No description provided for @settingsRemoveAgent.
  ///
  /// In en, this message translates to:
  /// **'Remove Agent'**
  String get settingsRemoveAgent;

  /// No description provided for @settingsRemoveAgentConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove \"{name}\"?'**
  String settingsRemoveAgentConfirm(String name);

  /// No description provided for @settingsDeleteProject.
  ///
  /// In en, this message translates to:
  /// **'Delete Project'**
  String get settingsDeleteProject;

  /// No description provided for @settingsDeleteProjectConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove \"{name}\" from the list?\n(Files will not be deleted)'**
  String settingsDeleteProjectConfirm(String name);

  /// No description provided for @settingsAgentCapabilities.
  ///
  /// In en, this message translates to:
  /// **'ACP Capabilities'**
  String get settingsAgentCapabilities;

  /// No description provided for @settingsAgentModes.
  ///
  /// In en, this message translates to:
  /// **'Available Modes'**
  String get settingsAgentModes;

  /// No description provided for @settingsAgentConfig.
  ///
  /// In en, this message translates to:
  /// **'Configuration'**
  String get settingsAgentConfig;

  /// No description provided for @settingsAgentActive.
  ///
  /// In en, this message translates to:
  /// **'Currently active'**
  String get settingsAgentActive;

  /// No description provided for @settingsAgentInactive.
  ///
  /// In en, this message translates to:
  /// **'Not active'**
  String get settingsAgentInactive;

  /// No description provided for @settingsAgentSourceBuiltin.
  ///
  /// In en, this message translates to:
  /// **'Built-in'**
  String get settingsAgentSourceBuiltin;

  /// No description provided for @settingsAgentSourceCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get settingsAgentSourceCustom;

  /// No description provided for @settingsAgentSourcePlugin.
  ///
  /// In en, this message translates to:
  /// **'Plugin'**
  String get settingsAgentSourcePlugin;

  /// No description provided for @settingsAgentCurrentlyUsing.
  ///
  /// In en, this message translates to:
  /// **'Currently Using'**
  String get settingsAgentCurrentlyUsing;

  /// No description provided for @settingsAgentUseThis.
  ///
  /// In en, this message translates to:
  /// **'Use This Agent'**
  String get settingsAgentUseThis;

  /// No description provided for @settingsAgentModeSwitched.
  ///
  /// In en, this message translates to:
  /// **'Mode: {name}'**
  String settingsAgentModeSwitched(String name);

  /// No description provided for @settingsAgentSwitchToConfig.
  ///
  /// In en, this message translates to:
  /// **'Switch to this agent to view and modify modes and configuration'**
  String get settingsAgentSwitchToConfig;

  /// No description provided for @settingsAgentSwitchToViewCaps.
  ///
  /// In en, this message translates to:
  /// **'Switch to this agent to view its ACP capabilities'**
  String get settingsAgentSwitchToViewCaps;

  /// No description provided for @settingsCapSessionLoad.
  ///
  /// In en, this message translates to:
  /// **'Session Load'**
  String get settingsCapSessionLoad;

  /// No description provided for @settingsCapSessionList.
  ///
  /// In en, this message translates to:
  /// **'Session List'**
  String get settingsCapSessionList;

  /// No description provided for @settingsCapSessionClose.
  ///
  /// In en, this message translates to:
  /// **'Session Close'**
  String get settingsCapSessionClose;

  /// No description provided for @settingsCapSessionFork.
  ///
  /// In en, this message translates to:
  /// **'Session Fork'**
  String get settingsCapSessionFork;

  /// No description provided for @settingsCapSessionResume.
  ///
  /// In en, this message translates to:
  /// **'Session Resume'**
  String get settingsCapSessionResume;

  /// No description provided for @settingsCapImage.
  ///
  /// In en, this message translates to:
  /// **'Image Input'**
  String get settingsCapImage;

  /// No description provided for @settingsCapAudio.
  ///
  /// In en, this message translates to:
  /// **'Audio Input'**
  String get settingsCapAudio;

  /// No description provided for @settingsCapEmbeddedContext.
  ///
  /// In en, this message translates to:
  /// **'Embedded Context'**
  String get settingsCapEmbeddedContext;

  /// No description provided for @settingsCapMcpHttp.
  ///
  /// In en, this message translates to:
  /// **'MCP HTTP'**
  String get settingsCapMcpHttp;

  /// No description provided for @settingsCapMcpSse.
  ///
  /// In en, this message translates to:
  /// **'MCP SSE'**
  String get settingsCapMcpSse;

  /// No description provided for @testPanelTabPreview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get testPanelTabPreview;

  /// No description provided for @testPanelTabScript.
  ///
  /// In en, this message translates to:
  /// **'Script'**
  String get testPanelTabScript;

  /// No description provided for @testPanelTabApi.
  ///
  /// In en, this message translates to:
  /// **'API'**
  String get testPanelTabApi;

  /// No description provided for @testPanelTab.
  ///
  /// In en, this message translates to:
  /// **'Test'**
  String get testPanelTab;

  /// No description provided for @previewPortHint.
  ///
  /// In en, this message translates to:
  /// **'Port (optional, auto-detect)'**
  String get previewPortHint;

  /// No description provided for @previewCommandHint.
  ///
  /// In en, this message translates to:
  /// **'Start command (e.g. npm run dev)'**
  String get previewCommandHint;

  /// No description provided for @previewCwdHint.
  ///
  /// In en, this message translates to:
  /// **'Working directory (optional, default: project root)'**
  String get previewCwdHint;

  /// No description provided for @previewIdleTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter a start command to auto-detect port and preview'**
  String get previewIdleTitle;

  /// No description provided for @previewIdleSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Or enter port only to connect to an existing server'**
  String get previewIdleSubtitle;

  /// No description provided for @previewStarting.
  ///
  /// In en, this message translates to:
  /// **'Starting preview...'**
  String get previewStarting;

  /// No description provided for @previewStopping.
  ///
  /// In en, this message translates to:
  /// **'Stopping preview...'**
  String get previewStopping;

  /// No description provided for @previewErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Preview Error'**
  String get previewErrorTitle;

  /// No description provided for @previewStartTooltip.
  ///
  /// In en, this message translates to:
  /// **'Start Preview'**
  String get previewStartTooltip;

  /// No description provided for @previewStopTooltip.
  ///
  /// In en, this message translates to:
  /// **'Stop Preview'**
  String get previewStopTooltip;

  /// No description provided for @previewInvalidPort.
  ///
  /// In en, this message translates to:
  /// **'Invalid port number (1-65535)'**
  String get previewInvalidPort;

  /// No description provided for @previewNeedPortOrCommand.
  ///
  /// In en, this message translates to:
  /// **'Enter a command or port number'**
  String get previewNeedPortOrCommand;

  /// No description provided for @previewVisualDiffCaptured.
  ///
  /// In en, this message translates to:
  /// **'Visual diff baseline captured. Make changes, then compare.'**
  String get previewVisualDiffCaptured;

  /// No description provided for @previewCrashFallback.
  ///
  /// In en, this message translates to:
  /// **'Preview crashed unexpectedly'**
  String get previewCrashFallback;

  /// No description provided for @scriptCommandHint.
  ///
  /// In en, this message translates to:
  /// **'Enter command...'**
  String get scriptCommandHint;

  /// No description provided for @scriptCwdHint.
  ///
  /// In en, this message translates to:
  /// **'Working directory (optional)'**
  String get scriptCwdHint;

  /// No description provided for @scriptHistoryTooltip.
  ///
  /// In en, this message translates to:
  /// **'Command history'**
  String get scriptHistoryTooltip;

  /// No description provided for @scriptHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Command History'**
  String get scriptHistoryTitle;

  /// No description provided for @scriptRunTooltip.
  ///
  /// In en, this message translates to:
  /// **'Run'**
  String get scriptRunTooltip;

  /// No description provided for @scriptStopTooltip.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get scriptStopTooltip;

  /// No description provided for @scriptIdleHint.
  ///
  /// In en, this message translates to:
  /// **'Run a command to see output here'**
  String get scriptIdleHint;

  /// No description provided for @scriptExitKilled.
  ///
  /// In en, this message translates to:
  /// **'Killed'**
  String get scriptExitKilled;

  /// No description provided for @scriptExitCode.
  ///
  /// In en, this message translates to:
  /// **'Exit: {code}'**
  String scriptExitCode(int code);

  /// No description provided for @apiHeadersLabel.
  ///
  /// In en, this message translates to:
  /// **'Headers'**
  String get apiHeadersLabel;

  /// No description provided for @apiBodyLabel.
  ///
  /// In en, this message translates to:
  /// **'Body'**
  String get apiBodyLabel;

  /// No description provided for @apiHeaderKeyHint.
  ///
  /// In en, this message translates to:
  /// **'Key'**
  String get apiHeaderKeyHint;

  /// No description provided for @apiHeaderValueHint.
  ///
  /// In en, this message translates to:
  /// **'Value'**
  String get apiHeaderValueHint;

  /// No description provided for @apiSendButton.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get apiSendButton;

  /// No description provided for @apiSavePresetTooltip.
  ///
  /// In en, this message translates to:
  /// **'Save as preset'**
  String get apiSavePresetTooltip;

  /// No description provided for @apiSavePresetTitle.
  ///
  /// In en, this message translates to:
  /// **'Save Preset'**
  String get apiSavePresetTitle;

  /// No description provided for @apiPresetNameHint.
  ///
  /// In en, this message translates to:
  /// **'Preset name'**
  String get apiPresetNameHint;

  /// No description provided for @apiResponseCopied.
  ///
  /// In en, this message translates to:
  /// **'Response copied'**
  String get apiResponseCopied;

  /// No description provided for @apiCopyResponseTooltip.
  ///
  /// In en, this message translates to:
  /// **'Copy response'**
  String get apiCopyResponseTooltip;

  /// No description provided for @apiResponseTruncated.
  ///
  /// In en, this message translates to:
  /// **'[Response truncated: > 1MB]'**
  String get apiResponseTruncated;

  /// No description provided for @runConfigQuickRun.
  ///
  /// In en, this message translates to:
  /// **'Quick Run'**
  String get runConfigQuickRun;

  /// No description provided for @runConfigQuickRunHint.
  ///
  /// In en, this message translates to:
  /// **'Enter command (e.g. npm run dev)'**
  String get runConfigQuickRunHint;

  /// No description provided for @runConfigCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get runConfigCancel;

  /// No description provided for @runConfigRun.
  ///
  /// In en, this message translates to:
  /// **'Run'**
  String get runConfigRun;

  /// No description provided for @runConfigNoConfigs.
  ///
  /// In en, this message translates to:
  /// **'No Run Configurations'**
  String get runConfigNoConfigs;

  /// No description provided for @runConfigNoConfigsDesc.
  ///
  /// In en, this message translates to:
  /// **'Create a configuration from the desktop dashboard to get started.'**
  String get runConfigNoConfigsDesc;

  /// No description provided for @runConfigViewOutput.
  ///
  /// In en, this message translates to:
  /// **'View Output'**
  String get runConfigViewOutput;

  /// No description provided for @runConfigStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get runConfigStop;

  /// No description provided for @runConfigRestart.
  ///
  /// In en, this message translates to:
  /// **'Restart'**
  String get runConfigRestart;

  /// No description provided for @runConfigStateIdle.
  ///
  /// In en, this message translates to:
  /// **'Idle'**
  String get runConfigStateIdle;

  /// No description provided for @runConfigStateBeforeRun.
  ///
  /// In en, this message translates to:
  /// **'Running tasks...'**
  String get runConfigStateBeforeRun;

  /// No description provided for @runConfigStateStarting.
  ///
  /// In en, this message translates to:
  /// **'Starting...'**
  String get runConfigStateStarting;

  /// No description provided for @runConfigStateRunning.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get runConfigStateRunning;

  /// No description provided for @runConfigStateStopping.
  ///
  /// In en, this message translates to:
  /// **'Stopping...'**
  String get runConfigStateStopping;

  /// No description provided for @runConfigStateStopped.
  ///
  /// In en, this message translates to:
  /// **'Stopped'**
  String get runConfigStateStopped;

  /// No description provided for @runConfigWaitingOutput.
  ///
  /// In en, this message translates to:
  /// **'Waiting for output...'**
  String get runConfigWaitingOutput;

  /// No description provided for @runConfigOutputTab.
  ///
  /// In en, this message translates to:
  /// **'Output'**
  String get runConfigOutputTab;

  /// No description provided for @runConfigPreviewTab.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get runConfigPreviewTab;

  /// No description provided for @runConfigRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get runConfigRefresh;

  /// No description provided for @runConfigExitCode.
  ///
  /// In en, this message translates to:
  /// **'Exit code: {code}'**
  String runConfigExitCode(int code);

  /// No description provided for @previewUrlHint.
  ///
  /// In en, this message translates to:
  /// **'URL (e.g. https://localhost:3000)'**
  String get previewUrlHint;

  /// No description provided for @runConfigDetailTitle.
  ///
  /// In en, this message translates to:
  /// **'Configuration'**
  String get runConfigDetailTitle;

  /// No description provided for @runConfigNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get runConfigNameLabel;

  /// No description provided for @runConfigCommandLabel.
  ///
  /// In en, this message translates to:
  /// **'Command'**
  String get runConfigCommandLabel;

  /// No description provided for @runConfigWorkDirLabel.
  ///
  /// In en, this message translates to:
  /// **'Working Directory'**
  String get runConfigWorkDirLabel;

  /// No description provided for @runConfigPreviewUrlLabel.
  ///
  /// In en, this message translates to:
  /// **'Preview URL'**
  String get runConfigPreviewUrlLabel;

  /// No description provided for @runConfigHostHeaderLabel.
  ///
  /// In en, this message translates to:
  /// **'Host Header'**
  String get runConfigHostHeaderLabel;

  /// No description provided for @runConfigDeleteConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete Configuration'**
  String get runConfigDeleteConfirmTitle;

  /// No description provided for @runConfigDeleteConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete \"{name}\"?'**
  String runConfigDeleteConfirmBody(String name);

  /// No description provided for @foregroundServiceConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected · Coding assistant running'**
  String get foregroundServiceConnected;

  /// No description provided for @foregroundServiceStreaming.
  ///
  /// In en, this message translates to:
  /// **'✨ AI is responding...'**
  String get foregroundServiceStreaming;

  /// No description provided for @foregroundServiceDone.
  ///
  /// In en, this message translates to:
  /// **'✅ Response complete'**
  String get foregroundServiceDone;
}

class _SDelegate extends LocalizationsDelegate<S> {
  const _SDelegate();

  @override
  Future<S> load(Locale locale) {
    return SynchronousFuture<S>(lookupS(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_SDelegate old) => false;
}

S lookupS(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return SEn();
    case 'zh':
      return SZh();
  }

  throw FlutterError(
      'S.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
