// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class SEn extends S {
  SEn([String locale = 'en']) : super(locale);

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonConfirm => 'Confirm';

  @override
  String get commonDelete => 'Delete';

  @override
  String get commonRemove => 'Remove';

  @override
  String get commonRetry => 'Retry';

  @override
  String get commonAdd => 'Add';

  @override
  String get commonGotIt => 'Got it';

  @override
  String get commonInstall => 'Install';

  @override
  String get commonUninstall => 'Uninstall';

  @override
  String get commonOr => 'or';

  @override
  String get commonCopied => 'Copied';

  @override
  String get commonSaved => 'Saved';

  @override
  String get commonCopy => 'Copy';

  @override
  String get commonCollapse => 'Collapse';

  @override
  String get appTitle => 'MobileFlow';

  @override
  String get appSubtitle => 'Mobile AI Coding Assistant';

  @override
  String get connectHeroTitle =>
      'Connect to your desktop AI coding environment';

  @override
  String get connectStatusConnected => 'Connected';

  @override
  String get connectStatusWaiting => 'Waiting to connect';

  @override
  String get connectLanTab => 'LAN';

  @override
  String get connectRelayTab => 'Relay';

  @override
  String get connectTunnelTab => 'Tunnel';

  @override
  String get connectLanHeadline => 'Fastest connection';

  @override
  String get connectLanDescription =>
      'Use this mode when your phone and computer are on the same network. Enter IP, port, and password to connect.';

  @override
  String get connectLanBadge => 'Low latency · Fewest hops';

  @override
  String get connectIpLabel => 'Computer IP Address';

  @override
  String get connectIpHint => '192.168.1.100';

  @override
  String get connectPortLabel => 'Port';

  @override
  String get connectPortHint => '9600';

  @override
  String get connectPasswordLabel => 'Connection Password';

  @override
  String get connectPasswordHint => 'Check your computer terminal';

  @override
  String get connectButton => 'Connect';

  @override
  String get connectingButton => 'Connecting...';

  @override
  String get connectRelayHeadline => 'For remote connections';

  @override
  String get connectRelayDescription =>
      'End-to-end encrypted even through relay. Scan QR code or paste the pairing code from your computer.';

  @override
  String get connectRelayBadge => 'Works anywhere · Stable pairing';

  @override
  String get connectScanQr => 'Scan QR Code';

  @override
  String get connectScanQrNote =>
      'Current version supports pasting QR content or pairing code. Full camera scanning coming soon.';

  @override
  String get connectPairingCodeLabel => 'Pairing Code';

  @override
  String get connectPairingCodeHint => 'Check your computer terminal';

  @override
  String get connectRelayButton => 'Remote Connect';

  @override
  String get connectTunnelHeadline => 'For self-hosted servers';

  @override
  String get connectTunnelDescription =>
      'If you have your own WebSocket gateway or deployment, enter the address and token here.';

  @override
  String get connectTunnelBadge => 'Self-controlled · Flexible';

  @override
  String get connectTunnelUrlLabel => 'WebSocket Address';

  @override
  String get connectTunnelUrlHint => 'wss://your-server.com:8765';

  @override
  String get connectTunnelTokenLabel => 'Bearer Token (optional)';

  @override
  String get connectTunnelTokenHint => 'Auth token';

  @override
  String get connectTunnelButton => 'Direct Connect';

  @override
  String get connectSwitchModeTitle => 'Switch Connection Mode';

  @override
  String get connectSwitchModeMessage =>
      'Switching mode will disconnect the current connection. Continue?';

  @override
  String get connectSubtitle =>
      'Connect your phone to desktop AI coding environment';

  @override
  String get connectConnect => 'Connect';

  @override
  String get connectConnecting => 'Connecting...';

  @override
  String get connectLanHostLabel => 'Computer IP address';

  @override
  String get connectLanPortLabel => 'Port';

  @override
  String get connectLanPasswordLabel => 'Connection password';

  @override
  String get connectLanPasswordHint => 'Check in computer terminal';

  @override
  String get connectRelayScanDialogMessage =>
      'Paste the pairing code from your computer terminal';

  @override
  String get connectRelayScanDialogHint => 'Paste pairing code...';

  @override
  String get connectErrorNoHost => 'Please enter computer IP address';

  @override
  String get connectErrorNoPassword => 'Please enter connection password';

  @override
  String get connectErrorNoRelayCode => 'Please enter pairing code';

  @override
  String get connectErrorInvalidRelayCode => 'Invalid pairing code';

  @override
  String get connectErrorInvalidRelayCodeRescan =>
      'Invalid pairing code, please scan again';

  @override
  String get connectErrorInvalidSecret => 'Invalid key in pairing code';

  @override
  String get connectErrorNoTunnelUrl => 'Please enter WebSocket address';

  @override
  String get connectErrorNetworkUnreachable =>
      'Cannot reach this IP address. Make sure your phone and computer are on the same network.';

  @override
  String get connectErrorPortRefused =>
      'Connection refused on this port. Make sure the Agent is running and listening.';

  @override
  String get connectErrorWrongPairingCode =>
      'Wrong pairing code. Check the 6-digit code shown in your computer terminal.';

  @override
  String get connectErrorRelayUnreachable =>
      'Relay server unavailable. Check your network connection.';

  @override
  String get connectErrorTlsFailure =>
      'TLS connection failed. Check the server certificate configuration.';

  @override
  String get connectErrorTimeout => 'Connection timed out. Check your network.';

  @override
  String get connectErrorSessionExpired => 'Session expired. Please reconnect.';

  @override
  String connectErrorLockout(int seconds) {
    return 'Too many pairing attempts. Please wait $seconds seconds before retrying.';
  }

  @override
  String get connectErrorTunnelAuthFailed =>
      'Authentication failed. Check your Bearer Token.';

  @override
  String get connectErrorGeneric =>
      'Connection failed. Check your network settings.';

  @override
  String get connectRelayScanQr => 'Scan QR Code';

  @override
  String get connectRelayScanNote =>
      'Current version supports pasting QR content or pairing code. Full camera scanning coming soon.';

  @override
  String get connectRelayCodeLabel => 'Pairing Code';

  @override
  String get connectRelayCodeHint => 'Check your computer terminal';

  @override
  String get connectRelayConnect => 'Remote Connect';

  @override
  String get connectTunnelConnect => 'Direct Connect';

  @override
  String get connectScanInstruction =>
      'Point camera at the QR code on your computer dashboard';

  @override
  String get connectQrInvalid =>
      'Invalid QR code. Please scan the code from MobileFlow dashboard.';

  @override
  String get connectQrInvalidPort =>
      'Invalid connection parameters in QR code.';

  @override
  String get connectScanCameraRequired =>
      'Camera access is required to scan QR codes.';

  @override
  String get connectScanClose => 'Close';

  @override
  String get chatEmptyTitle => 'Start coding with AI!';

  @override
  String get chatEmptySubtitle => 'Type a message or use / commands';

  @override
  String get chatSuggestion1 => 'Show me the project structure';

  @override
  String get chatSuggestion2 => 'Check for code issues';

  @override
  String get chatSuggestion3 => 'Explain this project';

  @override
  String get chatNoProjectTitle => 'Add a project first';

  @override
  String get chatNoProjectDescription => 'Add a project directory in Settings';

  @override
  String get chatAiThinking => 'AI thinking...';

  @override
  String get chatAiToolRunning => 'Tool running...';

  @override
  String chatAiToolRunningDetail(String detail) {
    return 'Running: $detail';
  }

  @override
  String get chatAiStreaming => 'Responding...';

  @override
  String get chatAuthRequired => 'Authentication Required';

  @override
  String get chatAuthRequiredDesc => 'This Agent requires an API Key to use';

  @override
  String get chatNoAuthMethods => 'No authentication methods received';

  @override
  String get chatPermissionDeny => 'Deny';

  @override
  String get chatPermissionAllow => 'Allow';

  @override
  String get chatPermissionAlwaysAllow => 'Always Allow';

  @override
  String get chatHistorySessions => 'History Sessions';

  @override
  String get chatNoHistorySessions => 'No history sessions';

  @override
  String get chatLoadingHistory => 'Loading history...';

  @override
  String get chatScrollUpForMore => '↑ Scroll up for more';

  @override
  String get chatNewSessionConfirmTitle => 'AI is responding';

  @override
  String get chatNewSessionConfirmMessage =>
      'Switching sessions will interrupt the current conversation. Continue?';

  @override
  String get chatContinueSwitch => 'Continue';

  @override
  String get chatScrollLoadMore => '↑ Scroll up to load more';

  @override
  String get chatConnectingAgent => 'Connecting to AI Agent...';

  @override
  String get chatAuthApiKeyNeeded => 'This Agent requires an API Key';

  @override
  String get chatAuthNoMethods => 'No authentication methods received';

  @override
  String get chatStatusThinking => 'AI thinking...';

  @override
  String get chatStatusExecuting => 'Executing';

  @override
  String get chatStatusToolRunning => 'Tool running...';

  @override
  String get chatStatusStreaming => 'Responding...';

  @override
  String get chatStreamInterrupted => 'Response interrupted — connection lost';

  @override
  String get chatPermissionToolCall => 'Tool call';

  @override
  String get chatAiResponding => 'AI is responding';

  @override
  String get chatSwitchSessionWarning =>
      'Switching session will interrupt the current conversation. Continue?';

  @override
  String get chatSwitchSessionConfirm => 'Switch anyway';

  @override
  String get chatSessionHistory => 'Session history';

  @override
  String get chatNoSessions => 'No session history';

  @override
  String get chatEmptySession => '(Empty session)';

  @override
  String get chatManageProjectHint => 'Manage projects in Settings';

  @override
  String get chatTapToInput => 'Tap to input';

  @override
  String get chatInputInstallAgent =>
      'Please install an AI Agent in Settings first';

  @override
  String get chatInputVoiceReleaseCancel => 'Release to cancel';

  @override
  String get chatInputVoiceListening => 'Listening...';

  @override
  String get chatInputVoiceHoldToTalk => 'Hold to talk, release to input';

  @override
  String get chatInputVoiceReleaseToCancel => 'Release to cancel';

  @override
  String get chatInputVoiceSwipeToCancel => 'Swipe up to cancel';

  @override
  String get chatInputVoiceHoldToSpeak => 'Hold to speak';

  @override
  String get chatInputPhotoFailed => 'Photo failed';

  @override
  String get chatInputListening => 'Listening...';

  @override
  String get chatInputAgentStarting => 'Agent starting...';

  @override
  String get chatInputAgentFailed => 'Agent failed, tap to retry';

  @override
  String get chatInputAuthRequired => 'Please authenticate first';

  @override
  String get chatInputQueuedHint => 'Queued, tap stop...';

  @override
  String get chatInputAttachmentHint => 'Add a description or send directly...';

  @override
  String get chatInputDefaultHint => 'Ask a question or describe a task...';

  @override
  String get chatInputTooltipReference => 'Reference file';

  @override
  String get chatInputTooltipAttachment => 'Add attachment';

  @override
  String get chatInputAgentNotReady => 'Agent not ready';

  @override
  String get chatInputTooltipHistory => 'Input history';

  @override
  String get chatInputMaxReferences => 'Context reference limit reached';

  @override
  String chatInputQueueCount(int count) {
    return 'Queued ($count)';
  }

  @override
  String get chatInputVoiceNoResult => 'No speech detected, please try again';

  @override
  String get chatInputVoiceUnsupported =>
      'This device does not support speech-to-text, and the CLI does not support audio input';

  @override
  String get chatInputNoHistory => 'No input history';

  @override
  String get chatInputHistoryTitle => 'Input History';

  @override
  String get chatAgentReady => 'AI Agent ready';

  @override
  String get errorUnknown => 'Unknown error';

  @override
  String get widgetNoMatchingFiles => 'No matching files';

  @override
  String widgetExpandAll(int count) {
    return 'Expand all ($count chars)';
  }

  @override
  String get homeTabChat => 'Chat';

  @override
  String get homeTabTerminal => 'Terminal';

  @override
  String get homeTabProject => 'Project';

  @override
  String get homeTabSettings => 'Settings';

  @override
  String get terminalSwitchCli => 'Switch CLI';

  @override
  String get terminalNoProjectTitle => 'Add a project first';

  @override
  String get terminalNoProjectDescription =>
      'Add a project directory in Settings';

  @override
  String get terminalNoAgent => 'No AI Agent detected';

  @override
  String get terminalNoAgentDescription => 'Install an AI Agent in Settings';

  @override
  String get terminalSearchHint => 'Search...';

  @override
  String get terminalStarting => 'Starting terminal...';

  @override
  String get terminalConnectingCli => 'Connecting to desktop CLI';

  @override
  String get terminalExtraKeyPaste => 'Paste';

  @override
  String get filesTitle => 'Project';

  @override
  String get filesTreeNotReady => 'File tree not ready';

  @override
  String get filesNoProjectTitle => 'Add a project first';

  @override
  String get filesNoProjectDescription =>
      'Bind a workspace in Settings first to load the file browser.';

  @override
  String get filesNewFile => 'New file';

  @override
  String get filesNewFolder => 'New folder';

  @override
  String get filesNewFileHint => 'Enter file name';

  @override
  String get filesNewFolderHint => 'Enter folder name';

  @override
  String get filesCreateFailed => 'Creation failed';

  @override
  String get filesRenameFailed => 'Rename failed';

  @override
  String get filesDeleteFailed => 'Delete failed';

  @override
  String get filesLoadFailed => 'Loading failed';

  @override
  String get filesNoFiles => 'No files';

  @override
  String get filesUndo => 'Undo';

  @override
  String get filesRedo => 'Redo';

  @override
  String get filesSave => 'Save';

  @override
  String get filesSearch => 'Search';

  @override
  String get filesViewMode => 'View mode';

  @override
  String get filesEditMode => 'Edit mode';

  @override
  String get filesSendToAi => 'Send to AI';

  @override
  String get filesNew => 'New';

  @override
  String get filesCollapseAll => 'Collapse all';

  @override
  String get filesRefresh => 'Refresh';

  @override
  String get filesSearchFilename => 'Search file name...';

  @override
  String get filesSearchContent => 'Search file content...';

  @override
  String get filesSearchFileTab => 'File';

  @override
  String get filesSearchContentTab => 'Content';

  @override
  String get filesSearchRegex => 'Regular expression';

  @override
  String get filesSearchCaseSensitive => 'Case sensitive';

  @override
  String get filesSearchWholeWord => 'Whole word';

  @override
  String get filesUnsavedTitle => 'Unsaved changes';

  @override
  String filesUnsavedMessage(String fileName) {
    return '$fileName has unsaved changes';
  }

  @override
  String get fileViewerSearch => 'Search';

  @override
  String get fileViewerUndo => 'Undo';

  @override
  String get fileViewerRedo => 'Redo';

  @override
  String get fileViewerSave => 'Save';

  @override
  String get fileViewerViewMode => 'View mode';

  @override
  String get fileViewerEditMode => 'Edit mode';

  @override
  String get fileViewerEmptyContent => 'File content is empty';

  @override
  String get gitNoWorkDir => 'No working directory selected';

  @override
  String get gitNoWorkDirDescription =>
      'Add a project directory in Settings first.';

  @override
  String get gitPushUpToDate => 'Already up to date';

  @override
  String get gitPushSuccess => 'Push succeeded';

  @override
  String get gitPullUpToDate => 'Already up to date';

  @override
  String get gitPullSuccess => 'Pull succeeded';

  @override
  String get gitExecSuccess => 'Command executed';

  @override
  String get gitPushNoCommits => 'Push (no unpushed commits)';

  @override
  String get gitTabChanges => 'Changes';

  @override
  String get gitTabCommit => 'Commit';

  @override
  String get gitTabHistory => 'History';

  @override
  String get gitProcessing => 'Processing...';

  @override
  String get gitLoadTimeout => 'Loading timed out';

  @override
  String get gitRecheck => 'Recheck';

  @override
  String get gitChecking => 'Checking...';

  @override
  String get gitNoRepoDetected => 'No Git repository detected';

  @override
  String get gitNoRepoHint => 'Run git init in terminal to initialize.';

  @override
  String gitFoundRepos(int count) {
    return 'Found $count Git repositories';
  }

  @override
  String get gitDiscardTitle => 'Discard changes';

  @override
  String gitDiscardMessage(String path) {
    return 'Discard all unstaged changes in $path? Cannot be undone.';
  }

  @override
  String get gitDiscard => 'Discard';

  @override
  String gitSwitchRepo(int count) {
    return 'Switch repository ($count)';
  }

  @override
  String get gitSwitchBranch => 'Switch branch';

  @override
  String get gitCopyHash => 'Copy Hash';

  @override
  String get gitBinaryFileToast => 'Cannot get file content (binary file)';

  @override
  String gitChangedFiles(int count) {
    return 'Changed files ($count)';
  }

  @override
  String get gitChangesClean => 'Working tree clean';

  @override
  String get gitChangesCleanDesc => 'No uncommitted changes';

  @override
  String gitChangesStagedCount(int count) {
    return 'Staged ($count)';
  }

  @override
  String get gitChangesUnstageAll => 'Unstage all';

  @override
  String gitChangesUnstagedCount(int count) {
    return 'Unstaged ($count)';
  }

  @override
  String get gitChangesStageAll => 'Stage all';

  @override
  String gitChangesUntrackedCount(int count) {
    return 'Untracked ($count)';
  }

  @override
  String get gitChangesAddAll => 'Add all';

  @override
  String gitCommitStagedReady(int count) {
    return '$count files staged, ready to commit';
  }

  @override
  String get gitCommitNoStaged => 'No staged files';

  @override
  String get gitCommitMessageHint => 'Enter commit message...';

  @override
  String get gitCommitButton => 'Commit';

  @override
  String get gitCommitPulling => 'Pulling...';

  @override
  String get gitCommitPushing => 'Pushing...';

  @override
  String get gitLogSelectBranch => 'Select branch';

  @override
  String get gitLogSelectAuthor => 'Select author';

  @override
  String get gitLogSelectDateRange => 'Select date range';

  @override
  String get gitLogToday => 'Today';

  @override
  String get gitLogLast7Days => 'Last 7 days';

  @override
  String get gitLogLast30Days => 'Last 30 days';

  @override
  String get gitLogLast90Days => 'Last 90 days';

  @override
  String get gitLogCustomRange => 'Custom range';

  @override
  String get gitLogClearDateFilter => 'Clear date filter';

  @override
  String get gitLogSearchCommit => 'Search commit...';

  @override
  String get gitLogBranch => 'Branch';

  @override
  String get gitLogAuthor => 'Author';

  @override
  String get gitLogDate => 'Date';

  @override
  String get gitLogFrom => 'From';

  @override
  String get gitLogUntil => 'Until';

  @override
  String get gitLogRemote => 'Remote';

  @override
  String get gitLogLocal => 'Local';

  @override
  String get gitShellHint => 'Enter git commands';

  @override
  String get gitShellRestriction => 'Only git operations allowed';

  @override
  String get gitShellConfirmExecute => 'Confirm execute';

  @override
  String get gitLogNoMatchingCommits => 'No matching commits';

  @override
  String get gitLogNoFilteredCommits => 'No commits match filters';

  @override
  String get gitLogNoHistory => 'No commit history';

  @override
  String get pluginTitle => 'Plugin Management';

  @override
  String get pluginEmpty => 'No plugins';

  @override
  String get pluginEmptyHint => 'Tap + to install plugins';

  @override
  String get pluginStatusActive => 'Active';

  @override
  String get pluginStatusDisabled => 'Disabled';

  @override
  String get pluginStatusError => 'Error';

  @override
  String get pluginStatusUnavailable => 'Unavailable';

  @override
  String get pluginStatusUnknown => 'Unknown';

  @override
  String get pluginUninstallTitle => 'Uninstall plugin';

  @override
  String pluginUninstallMessage(String name) {
    return 'Uninstall \"$name\"?';
  }

  @override
  String get pluginInstallTitle => 'Install plugin';

  @override
  String get pluginInstallSource => 'Install source';

  @override
  String get pluginInstallFailed => 'Installation failed';

  @override
  String get pluginLoadFailed => 'Loading failed';

  @override
  String get thoughtBlockThinking => 'Thinking...';

  @override
  String get thoughtBlockDone => 'Thought process';

  @override
  String get codeBlockCopy => 'Copy';

  @override
  String get codeBlockCopied => 'Copied to clipboard';

  @override
  String get planCardTitle => 'Plan';

  @override
  String get diffNoChanges => 'No changes';

  @override
  String get toolCallKindExecute => 'Command';

  @override
  String get toolCallKindEdit => 'Edit';

  @override
  String get toolCallKindSearch => 'Search';

  @override
  String get toolCallKindFetch => 'Network';

  @override
  String get toolCallKindMove => 'Move';

  @override
  String get toolCallKindDelete => 'Delete';

  @override
  String get toolCallKindThink => 'Reason';

  @override
  String get toolCallKindRead => 'Read';

  @override
  String get toolCallKindDefault => 'Tool';

  @override
  String get toolCallDefaultName => 'Tool call';

  @override
  String get toolCallAddedToContext => 'Added to context';

  @override
  String get toolCallWaitingTerminal => 'Waiting for terminal output...';

  @override
  String get connectionBannerReconnected => 'Reconnected';

  @override
  String connectionBannerReconnecting(int attempt, int maxAttempts) {
    return 'Disconnected, reconnecting ($attempt/$maxAttempts)...';
  }

  @override
  String get connectionBannerFailed => 'Connection failed';

  @override
  String get connectionBannerDisconnect => 'Disconnect';

  @override
  String get connectionStatusLan => 'LAN Direct';

  @override
  String get connectionStatusRelay => 'Relay';

  @override
  String get connectionStatusTunnel => 'Tunnel';

  @override
  String get connectionStatusTimeout => 'Timeout';

  @override
  String get connectionStatusDetails => 'Connection Details';

  @override
  String get connectionStatusMode => 'Mode';

  @override
  String get connectionStatusAddress => 'Address';

  @override
  String get connectionStatusLatency => 'Latency';

  @override
  String get connectionStatusUptime => 'Uptime';

  @override
  String get connectionStatusDisconnect => 'Disconnect';

  @override
  String get authFormGetKey => 'Get Key';

  @override
  String get authFormAuthenticate => 'Authenticate';

  @override
  String get authFormOptional => 'optional';

  @override
  String get authFormPasteKey => 'Paste key...';

  @override
  String get authFormEnterValue => 'Enter value...';

  @override
  String authFormFillField(String field) {
    return 'Please fill in $field';
  }

  @override
  String get authFormLinkCopied => 'Link copied';

  @override
  String get deviceCodeTitle => 'Login in browser';

  @override
  String get deviceCodeDescription => 'Open the link and enter the code';

  @override
  String get deviceCodeLabel => 'Verification code';

  @override
  String get deviceCodeTapToCopy => 'Tap to copy code';

  @override
  String get deviceCodeCopied => 'Code copied';

  @override
  String get deviceCodeWaiting => 'Waiting for login...';

  @override
  String get deviceCodeUrlCopied => 'Link copied';

  @override
  String get deviceCodeSkip => 'Skip for now';

  @override
  String get deviceCodeOpenBrowser => 'Open in browser';

  @override
  String get deviceCodeCannotOpenBrowser => 'Cannot open browser';

  @override
  String get deviceCodeLinkCopied => 'Link copied to clipboard';

  @override
  String get deviceCodeCheckTerminal => 'Check computer terminal for code';

  @override
  String get contextPickerTitle => 'Add Context';

  @override
  String get contextPickerSubtitle => 'Select context type';

  @override
  String get contextPickerFilesHint => 'Search files';

  @override
  String get contextPickerFolderHint => 'Select folder';

  @override
  String get contextPickerCurrentFileHint => 'Reference current file';

  @override
  String get contextPickerTerminalHint => 'Reference terminal output';

  @override
  String get contextPickerUrlHint => 'Enter URL';

  @override
  String get contextPickerGitDiffHint => 'Reference git changes';

  @override
  String get contextPickerProblemsHint => 'Reference problems';

  @override
  String contextPickerFileCount(int count) {
    return '$count files';
  }

  @override
  String get contextPickerNoCurrentFile => 'No file open';

  @override
  String get contextPickerNoTerminalOutput => 'No terminal output';

  @override
  String get contextPickerNoFolders => 'No folders available';

  @override
  String get slashCmdNew => 'New session';

  @override
  String get slashCmdClear => 'Clear chat';

  @override
  String get slashCmdHistory => 'View history';

  @override
  String get slashCmdFiles => 'View files';

  @override
  String get slashCmdTerminal => 'Open terminal';

  @override
  String get slashCmdDiff => 'View changes';

  @override
  String get slashCmdModel => 'Switch model';

  @override
  String get slashCmdProject => 'Switch project';

  @override
  String get slashCategorySession => 'Session';

  @override
  String get slashCategoryTools => 'Tools';

  @override
  String get slashCategoryConfig => 'Config';

  @override
  String get slashCategoryCli => 'CLI Commands';

  @override
  String get slashCmdHint => 'Tap to select · Esc to close';

  @override
  String get codeEditorSearchHint => 'Search...';

  @override
  String get codeEditorReplaceHint => 'Replace...';

  @override
  String get codeEditorReplace => 'Replace';

  @override
  String get codeEditorReplaceAll => 'Replace all';

  @override
  String get fileActionsAddToContext => 'Add to context';

  @override
  String get fileActionsAddedToContext => 'Added to context';

  @override
  String get fileActionsNewFile => 'New file';

  @override
  String get fileActionsNewFolder => 'New folder';

  @override
  String get fileActionsCopyPath => 'Copy path';

  @override
  String get fileActionsPathCopied => 'Path copied';

  @override
  String get fileActionsSendToAi => 'Send to AI';

  @override
  String get fileActionsRunFile => 'Run file';

  @override
  String get fileActionsRename => 'Rename';

  @override
  String get fileActionsEnterNewName => 'Enter new name';

  @override
  String get fileActionsConfirmDelete => 'Confirm delete';

  @override
  String fileActionsDeleteMessage(String name) {
    return 'Delete $name?';
  }

  @override
  String get fileActionsEnterFileName => 'Enter file name';

  @override
  String get fileActionsEnterFolderName => 'Enter folder name';

  @override
  String get fileSearchTypeToSearch => 'Type to search';

  @override
  String get fileSearchNoFileMatch => 'No matching files';

  @override
  String get fileSearchNoContentMatch => 'No matching content';

  @override
  String fileSearchResultCount(int fileCount, int matchCount) {
    return '$matchCount results in $fileCount files';
  }

  @override
  String get attachmentAgentNotReady => 'Agent not ready';

  @override
  String get attachmentImage => 'Image';

  @override
  String get attachmentImageNotSupported => 'Images not supported';

  @override
  String get attachmentAudio => 'Audio';

  @override
  String get attachmentAudioNotSupported => 'Audio not supported';

  @override
  String get attachmentAudioComingSoon => 'Audio coming soon';

  @override
  String get attachmentFileRef => 'File reference';

  @override
  String get attachmentNotSupported => 'Not supported';

  @override
  String get cliSelectorTitle => 'Select CLI';

  @override
  String get configPanelAgentSettings => 'Agent Settings';

  @override
  String get configPanelAutoApprove => 'Auto-approve permissions';

  @override
  String get configPanelAutoApproveDesc => 'Don\'t ask for operations';

  @override
  String configPanelSwitchedTo(String name) {
    return 'Switched to $name';
  }

  @override
  String get configPanelOn => 'On';

  @override
  String get configPanelOff => 'Off';

  @override
  String get slashCmdImmediate => 'Instant';

  @override
  String get contextPickerSelectTerminal => 'Select Terminal';

  @override
  String contextPickerTerminalN(String id) {
    return 'Terminal $id';
  }

  @override
  String contextPickerTerminalLines(int count) {
    return '$count lines of output';
  }

  @override
  String get contextPickerEnterUrl => 'Enter URL';

  @override
  String get projectPickerTitle => 'Select Project';

  @override
  String get projectPickerSearchHint => 'Search project name...';

  @override
  String get projectPickerFirstProject => 'Start your first project';

  @override
  String get projectPickerFirstProjectDesc =>
      'Search project name, browse directories, or enter path manually';

  @override
  String get projectPickerRecent => 'Recent Projects';

  @override
  String get projectPickerNoMatch => 'No matching projects';

  @override
  String get projectPickerNoMatchDesc =>
      'Try a different keyword, or browse directories manually';

  @override
  String projectPickerFoundCount(int count) {
    return 'Found $count projects';
  }

  @override
  String projectPickerDirNotExist(String path) {
    return '$path (directory not found)';
  }

  @override
  String get projectPickerBrowse => 'Browse Directories';

  @override
  String get projectPickerBrowseDesc =>
      'Select a project directory from the file system';

  @override
  String get projectPickerManualInput => 'Enter Path Manually';

  @override
  String get projectPickerManualInputDesc =>
      'Enter the full path to your project';

  @override
  String get projectPickerDirEmpty => 'This directory is empty';

  @override
  String get projectPickerDirEmptyDesc => 'No subdirectories found';

  @override
  String get projectPickerSelectDir => 'Select This Directory';

  @override
  String get componentDialogSave => 'Save';

  @override
  String get componentDialogDiscard => 'Don\'t save';

  @override
  String get componentSearchClearFilter => 'Clear filter';

  @override
  String get componentSearchNoMatch => 'No matches';

  @override
  String get componentSearchHint => 'Search...';

  @override
  String get componentSendToAiHint => 'Describe what you want AI to do...';

  @override
  String get componentSendToAiButton => 'Send to AI';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsControlCenterSubtitle => 'MobileFlow Control Center';

  @override
  String get settingsControlCenterDescription =>
      'Manage projects, connections, and AI tools like a portable dev workstation.';

  @override
  String get settingsLinkOnline => 'Link Online';

  @override
  String get settingsLinkOffline => 'Waiting to connect';

  @override
  String get settingsProjectsSection => 'Projects';

  @override
  String get settingsAddProject => 'Add Project';

  @override
  String get settingsConnectionSection => 'Connection';

  @override
  String get settingsConnected => 'Connected';

  @override
  String get settingsDisconnected => 'Disconnected';

  @override
  String get settingsClearConnections => 'Clear Saved Connections';

  @override
  String get settingsClearConnectionsDesc =>
      'Clear all saved connection info and keys';

  @override
  String get settingsClearedConnections => 'All saved connection info cleared';

  @override
  String get settingsAppearanceSection => 'Appearance';

  @override
  String get settingsDarkTheme => 'Dark Theme';

  @override
  String get settingsLanguageLabel => 'Language';

  @override
  String get settingsEditorSection => 'Editor';

  @override
  String get settingsCodeTheme => 'Code Theme';

  @override
  String get settingsSelectCodeTheme => 'Select Code Theme';

  @override
  String get settingsWordWrap => 'Word Wrap';

  @override
  String get settingsWordWrapOn => 'Long lines wrap';

  @override
  String get settingsWordWrapOff => 'Long lines scroll horizontally';

  @override
  String get settingsShowLineNumbers => 'Show Line Numbers';

  @override
  String get settingsFontSize => 'Font Size';

  @override
  String get settingsPluginsSection => 'Plugins';

  @override
  String get settingsPluginManagement => 'Plugin Management';

  @override
  String get settingsPluginManagementDesc =>
      'Install, enable, and manage extension plugins';

  @override
  String get settingsCliToolsSection => 'AI CLI Tools';

  @override
  String get settingsAddCustomAgent => 'Add Custom Agent';

  @override
  String get settingsInstalled => 'Installed';

  @override
  String get settingsNotInstalled => 'Not installed';

  @override
  String settingsNProjects(int count) {
    return '$count projects';
  }

  @override
  String settingsNClis(int count) {
    return '$count CLIs';
  }

  @override
  String settingsSwitchedTo(String name) {
    return 'Switched to: $name';
  }

  @override
  String get settingsRemoveTooltip => 'Remove';

  @override
  String get settingsUninstallTooltip => 'Uninstall';

  @override
  String get settingsPreparingInstall => 'Preparing to install...';

  @override
  String settingsInstallingProgress(String label, int step, int total) {
    return 'Installing $label ($step/$total)...';
  }

  @override
  String get settingsInstallFailed => 'Install Failed';

  @override
  String get settingsUninstallAgent => 'Uninstall Agent';

  @override
  String settingsUninstallConfirm(String name) {
    return 'Uninstall \"$name\"?\nAll related components will be removed.';
  }

  @override
  String get settingsPreparingUninstall => 'Preparing to uninstall...';

  @override
  String settingsUninstallingProgress(String label, int step, int total) {
    return 'Uninstalling $label ($step/$total)...';
  }

  @override
  String get settingsAddCustomAgentTitle => 'Add Custom Agent';

  @override
  String get settingsAgentNameLabel => 'Name';

  @override
  String get settingsAgentNameHint => 'e.g. My Agent';

  @override
  String get settingsAgentCommandLabel => 'Command';

  @override
  String get settingsAgentCommandHint => 'e.g. my-agent';

  @override
  String get settingsAgentArgsLabel => 'Arguments (space separated)';

  @override
  String get settingsAgentArgsHint => 'e.g. acp or --acp';

  @override
  String get settingsRemoveAgent => 'Remove Agent';

  @override
  String settingsRemoveAgentConfirm(String name) {
    return 'Remove \"$name\"?';
  }

  @override
  String get settingsDeleteProject => 'Delete Project';

  @override
  String settingsDeleteProjectConfirm(String name) {
    return 'Remove \"$name\" from the list?\n(Files will not be deleted)';
  }

  @override
  String get settingsAgentCapabilities => 'ACP Capabilities';

  @override
  String get settingsAgentModes => 'Available Modes';

  @override
  String get settingsAgentConfig => 'Configuration';

  @override
  String get settingsAgentActive => 'Currently active';

  @override
  String get settingsAgentInactive => 'Not active';

  @override
  String get settingsAgentSourceBuiltin => 'Built-in';

  @override
  String get settingsAgentSourceCustom => 'Custom';

  @override
  String get settingsAgentSourcePlugin => 'Plugin';

  @override
  String get settingsAgentCurrentlyUsing => 'Currently Using';

  @override
  String get settingsAgentUseThis => 'Use This Agent';

  @override
  String settingsAgentModeSwitched(String name) {
    return 'Mode: $name';
  }

  @override
  String get settingsAgentSwitchToConfig =>
      'Switch to this agent to view and modify modes and configuration';

  @override
  String get settingsAgentSwitchToViewCaps =>
      'Switch to this agent to view its ACP capabilities';

  @override
  String get settingsCapSessionLoad => 'Session Load';

  @override
  String get settingsCapSessionList => 'Session List';

  @override
  String get settingsCapSessionClose => 'Session Close';

  @override
  String get settingsCapSessionFork => 'Session Fork';

  @override
  String get settingsCapSessionResume => 'Session Resume';

  @override
  String get settingsCapImage => 'Image Input';

  @override
  String get settingsCapAudio => 'Audio Input';

  @override
  String get settingsCapEmbeddedContext => 'Embedded Context';

  @override
  String get settingsCapMcpHttp => 'MCP HTTP';

  @override
  String get settingsCapMcpSse => 'MCP SSE';

  @override
  String get testPanelTabPreview => 'Preview';

  @override
  String get testPanelTabScript => 'Script';

  @override
  String get testPanelTabApi => 'API';

  @override
  String get testPanelTab => 'Test';

  @override
  String get previewPortHint => 'Port (optional, auto-detect)';

  @override
  String get previewCommandHint => 'Start command (e.g. npm run dev)';

  @override
  String get previewCwdHint =>
      'Working directory (optional, default: project root)';

  @override
  String get previewIdleTitle =>
      'Enter a start command to auto-detect port and preview';

  @override
  String get previewIdleSubtitle =>
      'Or enter port only to connect to an existing server';

  @override
  String get previewStarting => 'Starting preview...';

  @override
  String get previewStopping => 'Stopping preview...';

  @override
  String get previewErrorTitle => 'Preview Error';

  @override
  String get previewStartTooltip => 'Start Preview';

  @override
  String get previewStopTooltip => 'Stop Preview';

  @override
  String get previewInvalidPort => 'Invalid port number (1-65535)';

  @override
  String get previewNeedPortOrCommand => 'Enter a command or port number';

  @override
  String get previewVisualDiffCaptured =>
      'Visual diff baseline captured. Make changes, then compare.';

  @override
  String get previewCrashFallback => 'Preview crashed unexpectedly';

  @override
  String get scriptCommandHint => 'Enter command...';

  @override
  String get scriptCwdHint => 'Working directory (optional)';

  @override
  String get scriptHistoryTooltip => 'Command history';

  @override
  String get scriptHistoryTitle => 'Command History';

  @override
  String get scriptRunTooltip => 'Run';

  @override
  String get scriptStopTooltip => 'Stop';

  @override
  String get scriptIdleHint => 'Run a command to see output here';

  @override
  String get scriptExitKilled => 'Killed';

  @override
  String scriptExitCode(int code) {
    return 'Exit: $code';
  }

  @override
  String get apiHeadersLabel => 'Headers';

  @override
  String get apiBodyLabel => 'Body';

  @override
  String get apiHeaderKeyHint => 'Key';

  @override
  String get apiHeaderValueHint => 'Value';

  @override
  String get apiSendButton => 'Send';

  @override
  String get apiSavePresetTooltip => 'Save as preset';

  @override
  String get apiSavePresetTitle => 'Save Preset';

  @override
  String get apiPresetNameHint => 'Preset name';

  @override
  String get apiResponseCopied => 'Response copied';

  @override
  String get apiCopyResponseTooltip => 'Copy response';

  @override
  String get apiResponseTruncated => '[Response truncated: > 1MB]';

  @override
  String get runConfigQuickRun => 'Quick Run';

  @override
  String get runConfigQuickRunHint => 'Enter command (e.g. npm run dev)';

  @override
  String get runConfigCancel => 'Cancel';

  @override
  String get runConfigRun => 'Run';

  @override
  String get runConfigNoConfigs => 'No Run Configurations';

  @override
  String get runConfigNoConfigsDesc =>
      'Create a configuration from the desktop dashboard to get started.';

  @override
  String get runConfigViewOutput => 'View Output';

  @override
  String get runConfigStop => 'Stop';

  @override
  String get runConfigRestart => 'Restart';

  @override
  String get runConfigStateIdle => 'Idle';

  @override
  String get runConfigStateBeforeRun => 'Running tasks...';

  @override
  String get runConfigStateStarting => 'Starting...';

  @override
  String get runConfigStateRunning => 'Running';

  @override
  String get runConfigStateStopping => 'Stopping...';

  @override
  String get runConfigStateStopped => 'Stopped';

  @override
  String get runConfigWaitingOutput => 'Waiting for output...';

  @override
  String get runConfigOutputTab => 'Output';

  @override
  String get runConfigPreviewTab => 'Preview';

  @override
  String get runConfigRefresh => 'Refresh';

  @override
  String runConfigExitCode(int code) {
    return 'Exit code: $code';
  }

  @override
  String get previewUrlHint => 'URL (e.g. https://localhost:3000)';

  @override
  String get runConfigDetailTitle => 'Configuration';

  @override
  String get runConfigNameLabel => 'Name';

  @override
  String get runConfigCommandLabel => 'Command';

  @override
  String get runConfigWorkDirLabel => 'Working Directory';

  @override
  String get runConfigPreviewUrlLabel => 'Preview URL';

  @override
  String get runConfigHostHeaderLabel => 'Host Header';

  @override
  String get runConfigDeleteConfirmTitle => 'Delete Configuration';

  @override
  String runConfigDeleteConfirmBody(String name) {
    return 'Are you sure you want to delete \"$name\"?';
  }

  @override
  String get foregroundServiceConnected =>
      'Connected · Coding assistant running';

  @override
  String get foregroundServiceStreaming => '✨ AI is responding...';

  @override
  String get foregroundServiceDone => '✅ Response complete';
}
