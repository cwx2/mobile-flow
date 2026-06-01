// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class SZh extends S {
  SZh([String locale = 'zh']) : super(locale);

  @override
  String get commonCancel => '取消';

  @override
  String get commonConfirm => '确认';

  @override
  String get commonDelete => '删除';

  @override
  String get commonRemove => '移除';

  @override
  String get commonRetry => '重试';

  @override
  String get commonAdd => '添加';

  @override
  String get commonGotIt => '知道了';

  @override
  String get commonInstall => '安装';

  @override
  String get commonUninstall => '卸载';

  @override
  String get commonOr => '或';

  @override
  String get commonCopied => '已复制';

  @override
  String get commonSaved => '已保存';

  @override
  String get commonCopy => '复制';

  @override
  String get commonCollapse => '收起';

  @override
  String get appTitle => 'MobileFlow';

  @override
  String get appSubtitle => '移动端 AI 编程助手';

  @override
  String get connectHeroTitle => '手机连接你的桌面 AI 编程环境';

  @override
  String get connectStatusConnected => '当前已连接';

  @override
  String get connectStatusWaiting => '等待连接';

  @override
  String get connectLanTab => '局域网';

  @override
  String get connectRelayTab => '中继';

  @override
  String get connectTunnelTab => '直连';

  @override
  String get connectLanHeadline => '最快的连接方式';

  @override
  String get connectLanDescription =>
      '手机和电脑在同一网络下时，优先使用这个模式。输入 IP、端口和连接密码即可连接。';

  @override
  String get connectLanBadge => '低延迟 · 最少跳数';

  @override
  String get connectIpLabel => '电脑 IP 地址';

  @override
  String get connectIpHint => '192.168.1.100';

  @override
  String get connectPortLabel => '端口';

  @override
  String get connectPortHint => '9600';

  @override
  String get connectPasswordLabel => '连接密码';

  @override
  String get connectPasswordHint => '在电脑终端中查看';

  @override
  String get connectButton => '连接';

  @override
  String get connectingButton => '连接中...';

  @override
  String get connectRelayHeadline => '适合异地连接';

  @override
  String get connectRelayDescription =>
      '走中继时仍保持端到端加密。你可以扫码配对，也可以直接粘贴电脑侧显示的配对码。';

  @override
  String get connectRelayBadge => '异地可用 · 配对更稳';

  @override
  String get connectScanQr => '扫码配对';

  @override
  String get connectScanQrNote => '当前版本支持粘贴二维码内容或配对码，后续会补全完整相机扫码体验。';

  @override
  String get connectPairingCodeLabel => '配对码';

  @override
  String get connectPairingCodeHint => '在电脑终端中查看';

  @override
  String get connectRelayButton => '远程连接';

  @override
  String get connectTunnelHeadline => '适合自有服务端';

  @override
  String get connectTunnelDescription =>
      '如果你已经有自己的 WebSocket 网关或部署服务，可以在这里直接填写地址和令牌。';

  @override
  String get connectTunnelBadge => '自控服务端 · 更灵活';

  @override
  String get connectTunnelUrlLabel => 'WebSocket 地址';

  @override
  String get connectTunnelUrlHint => 'wss://your-server.com:8765';

  @override
  String get connectTunnelTokenLabel => 'Bearer Token（可选）';

  @override
  String get connectTunnelTokenHint => '认证令牌';

  @override
  String get connectTunnelButton => '直连';

  @override
  String get connectSwitchModeTitle => '切换连接模式';

  @override
  String get connectSwitchModeMessage => '切换连接模式将断开当前连接，是否继续？';

  @override
  String get connectSubtitle => '手机连接你的桌面 AI 编程环境';

  @override
  String get connectConnect => '连接';

  @override
  String get connectConnecting => '连接中...';

  @override
  String get connectLanHostLabel => '电脑 IP 地址';

  @override
  String get connectLanPortLabel => '端口';

  @override
  String get connectLanPasswordLabel => '连接密码';

  @override
  String get connectLanPasswordHint => '在电脑终端中查看';

  @override
  String get connectRelayScanDialogMessage => '请粘贴电脑终端显示的配对码';

  @override
  String get connectRelayScanDialogHint => '粘贴配对码...';

  @override
  String get connectErrorNoHost => '请输入电脑 IP 地址';

  @override
  String get connectErrorNoPassword => '请输入连接密码';

  @override
  String get connectErrorNoRelayCode => '请输入配对码';

  @override
  String get connectErrorInvalidRelayCode => '无效的配对码，请检查输入';

  @override
  String get connectErrorInvalidRelayCodeRescan => '无效的配对码，请重新扫描';

  @override
  String get connectErrorInvalidSecret => '配对码中的密钥无效';

  @override
  String get connectErrorNoTunnelUrl => '请输入 WebSocket 地址';

  @override
  String get connectErrorNetworkUnreachable => '无法连接到该 IP 地址，请检查电脑和手机是否在同一网络';

  @override
  String get connectErrorPortRefused => '端口连接被拒绝，请确认 Agent 已启动并监听该端口';

  @override
  String get connectErrorWrongPairingCode => '配对码错误，请检查电脑终端显示的 6 位数字';

  @override
  String get connectErrorRelayUnreachable => '中继服务器不可用，请检查网络连接';

  @override
  String get connectErrorTlsFailure => 'TLS 连接失败，请检查服务器证书配置';

  @override
  String get connectErrorTimeout => '连接超时，请检查网络状况';

  @override
  String get connectErrorSessionExpired => '会话已过期，请重新连接';

  @override
  String connectErrorLockout(int seconds) {
    return '配对尝试过多，请等待 $seconds 秒后重试';
  }

  @override
  String get connectErrorTunnelAuthFailed => '认证失败，请检查 Bearer Token 是否正确';

  @override
  String get connectErrorGeneric => '连接失败，请检查网络设置';

  @override
  String get connectRelayScanQr => '扫码配对';

  @override
  String get connectRelayScanNote => '当前版本支持粘贴二维码内容或配对码，后续会补全完整相机扫码体验。';

  @override
  String get connectRelayCodeLabel => '配对码';

  @override
  String get connectRelayCodeHint => '在电脑终端中查看';

  @override
  String get connectRelayConnect => '远程连接';

  @override
  String get connectTunnelConnect => '直连';

  @override
  String get connectScanInstruction => '将摄像头对准电脑仪表盘上的二维码';

  @override
  String get connectQrInvalid => '无效二维码，请扫描 MobileFlow 仪表盘上的二维码';

  @override
  String get connectQrInvalidPort => '二维码中的连接参数无效';

  @override
  String get connectScanCameraRequired => '需要相机权限才能扫描二维码';

  @override
  String get connectScanClose => '关闭';

  @override
  String get chatEmptyTitle => '开始和 AI 一起编程吧！';

  @override
  String get chatEmptySubtitle => '输入消息或使用 / 命令';

  @override
  String get chatSuggestion1 => '帮我看看项目结构';

  @override
  String get chatSuggestion2 => '检查代码问题';

  @override
  String get chatSuggestion3 => '解释这个项目';

  @override
  String get chatNoProjectTitle => '请先添加项目';

  @override
  String get chatNoProjectDescription => '在设置页面添加一个项目目录';

  @override
  String get chatAiThinking => 'AI 思考中...';

  @override
  String get chatAiToolRunning => '工具执行中...';

  @override
  String chatAiToolRunningDetail(String detail) {
    return '执行: $detail';
  }

  @override
  String get chatAiStreaming => '回复中...';

  @override
  String get chatAuthRequired => '需要认证';

  @override
  String get chatAuthRequiredDesc => '此 Agent 需要 API Key 才能使用';

  @override
  String get chatNoAuthMethods => '未收到认证方式信息';

  @override
  String get chatPermissionDeny => '拒绝';

  @override
  String get chatPermissionAllow => '允许';

  @override
  String get chatPermissionAlwaysAllow => '始终允许';

  @override
  String get chatHistorySessions => '历史会话';

  @override
  String get chatNoHistorySessions => '没有历史会话';

  @override
  String get chatLoadingHistory => '加载历史会话...';

  @override
  String get chatScrollUpForMore => '↑ 上滑加载更多';

  @override
  String get chatNewSessionConfirmTitle => 'AI 正在回复中';

  @override
  String get chatNewSessionConfirmMessage => '切换会话将中断当前对话，是否继续？';

  @override
  String get chatContinueSwitch => '继续切换';

  @override
  String get chatScrollLoadMore => '↑ 上滑加载更多';

  @override
  String get chatConnectingAgent => '正在连接 AI Agent...';

  @override
  String get chatAuthApiKeyNeeded => '此 Agent 需要 API Key 才能使用';

  @override
  String get chatAuthNoMethods => '未收到认证方式信息';

  @override
  String get chatStatusThinking => 'AI 思考中...';

  @override
  String get chatStatusExecuting => '执行';

  @override
  String get chatStatusToolRunning => '工具执行中...';

  @override
  String get chatStatusStreaming => '回复中...';

  @override
  String get chatStreamInterrupted => '回复中断 — 连接已断开';

  @override
  String get chatPermissionToolCall => '工具调用';

  @override
  String get chatAiResponding => 'AI 正在回复中';

  @override
  String get chatSwitchSessionWarning => '切换会话将中断当前对话，是否继续？';

  @override
  String get chatSwitchSessionConfirm => '继续切换';

  @override
  String get chatSessionHistory => '历史会话';

  @override
  String get chatNoSessions => '没有历史会话';

  @override
  String get chatEmptySession => '(空会话)';

  @override
  String get chatManageProjectHint => '请在设置页面管理项目';

  @override
  String get chatTapToInput => '点击输入';

  @override
  String get chatInputInstallAgent => '请先在设置中安装一个 AI Agent';

  @override
  String get chatInputVoiceReleaseCancel => '松开取消';

  @override
  String get chatInputVoiceListening => '正在聆听...';

  @override
  String get chatInputVoiceHoldToTalk => '长按说话，松开输入';

  @override
  String get chatInputVoiceReleaseToCancel => '松开 取消';

  @override
  String get chatInputVoiceSwipeToCancel => '上滑 取消';

  @override
  String get chatInputVoiceHoldToSpeak => '按住 说话';

  @override
  String get chatInputPhotoFailed => '拍照失败';

  @override
  String get chatInputListening => '正在听...';

  @override
  String get chatInputAgentStarting => 'Agent 正在启动...';

  @override
  String get chatInputAgentFailed => 'Agent 启动失败，请点击重试';

  @override
  String get chatInputAuthRequired => '请先完成认证';

  @override
  String get chatInputQueuedHint => '排队发送中，点击停止...';

  @override
  String get chatInputAttachmentHint => '添加描述或直接发送图片...';

  @override
  String get chatInputDefaultHint => '提问或描述任务...';

  @override
  String get chatInputTooltipReference => '引用文件';

  @override
  String get chatInputTooltipAttachment => '添加附件';

  @override
  String get chatInputAgentNotReady => 'Agent 尚未就绪';

  @override
  String get chatInputTooltipHistory => '输入历史';

  @override
  String get chatInputMaxReferences => '已达到上下文引用上限';

  @override
  String chatInputQueueCount(int count) {
    return '排队中 ($count)';
  }

  @override
  String get chatInputVoiceNoResult => '未识别到语音，请重试';

  @override
  String get chatInputVoiceUnsupported => '当前设备不支持语音转文字，且 CLI 不支持音频输入';

  @override
  String get chatInputNoHistory => '没有输入历史';

  @override
  String get chatInputHistoryTitle => '输入历史';

  @override
  String get chatAgentReady => 'AI Agent 已就绪';

  @override
  String get errorUnknown => '未知错误';

  @override
  String get widgetNoMatchingFiles => '没有匹配的文件';

  @override
  String widgetExpandAll(int count) {
    return '展开全部 ($count 字符)';
  }

  @override
  String get homeTabChat => '对话';

  @override
  String get homeTabTerminal => '终端';

  @override
  String get homeTabProject => '项目';

  @override
  String get homeTabSettings => '设置';

  @override
  String get terminalSwitchCli => '切换 CLI';

  @override
  String get terminalNoProjectTitle => '请先添加项目';

  @override
  String get terminalNoProjectDescription => '在设置页面添加一个项目目录';

  @override
  String get terminalNoAgent => '未检测到 AI Agent';

  @override
  String get terminalNoAgentDescription => '请在设置中安装一个 AI Agent';

  @override
  String get terminalSearchHint => '搜索...';

  @override
  String get terminalStarting => '正在启动终端...';

  @override
  String get terminalConnectingCli => '连接到电脑 CLI';

  @override
  String get terminalExtraKeyPaste => '粘贴';

  @override
  String get filesTitle => '项目';

  @override
  String get filesTreeNotReady => '文件树未就绪';

  @override
  String get filesNoProjectTitle => '请先添加项目';

  @override
  String get filesNoProjectDescription => '先在设置页绑定工作区，文件浏览器才能加载目录和编辑文件。';

  @override
  String get filesNewFile => '新建文件';

  @override
  String get filesNewFolder => '新建文件夹';

  @override
  String get filesNewFileHint => '输入文件名';

  @override
  String get filesNewFolderHint => '输入文件夹名';

  @override
  String get filesCreateFailed => '创建失败';

  @override
  String get filesRenameFailed => '重命名失败';

  @override
  String get filesDeleteFailed => '删除失败';

  @override
  String get filesLoadFailed => '加载失败';

  @override
  String get filesNoFiles => '没有文件';

  @override
  String get filesUndo => '撤销';

  @override
  String get filesRedo => '重做';

  @override
  String get filesSave => '保存';

  @override
  String get filesSearch => '搜索';

  @override
  String get filesViewMode => '查看模式';

  @override
  String get filesEditMode => '编辑模式';

  @override
  String get filesSendToAi => '发送给 AI';

  @override
  String get filesNew => '新建';

  @override
  String get filesCollapseAll => '全部折叠';

  @override
  String get filesRefresh => '刷新';

  @override
  String get filesSearchFilename => '搜索文件名...';

  @override
  String get filesSearchContent => '搜索文件内容...';

  @override
  String get filesSearchFileTab => '文件';

  @override
  String get filesSearchContentTab => '内容';

  @override
  String get filesSearchRegex => '正则表达式';

  @override
  String get filesSearchCaseSensitive => '区分大小写';

  @override
  String get filesSearchWholeWord => '全词匹配';

  @override
  String get filesUnsavedTitle => '未保存的修改';

  @override
  String filesUnsavedMessage(String fileName) {
    return '$fileName 有未保存的修改';
  }

  @override
  String get fileViewerSearch => '搜索';

  @override
  String get fileViewerUndo => '撤销';

  @override
  String get fileViewerRedo => '重做';

  @override
  String get fileViewerSave => '保存';

  @override
  String get fileViewerViewMode => '查看模式';

  @override
  String get fileViewerEditMode => '编辑模式';

  @override
  String get fileViewerEmptyContent => '文件内容为空';

  @override
  String get gitNoWorkDir => '未选择工作目录';

  @override
  String get gitNoWorkDirDescription => '请先在设置页添加一个项目目录，Git 面板将自动检测仓库。';

  @override
  String get gitPushUpToDate => '已经是最新的，无需推送';

  @override
  String get gitPushSuccess => 'Push 成功';

  @override
  String get gitPullUpToDate => '已经是最新的';

  @override
  String get gitPullSuccess => 'Pull 成功';

  @override
  String get gitExecSuccess => '命令执行成功';

  @override
  String get gitPushNoCommits => 'Push (无未推送提交)';

  @override
  String get gitTabChanges => '变更';

  @override
  String get gitTabCommit => '提交';

  @override
  String get gitTabHistory => '历史';

  @override
  String get gitProcessing => '处理中...';

  @override
  String get gitLoadTimeout => '加载超时';

  @override
  String get gitRecheck => '重新检查';

  @override
  String get gitChecking => '检查中...';

  @override
  String get gitNoRepoDetected => '未检测到 Git 仓库';

  @override
  String get gitNoRepoHint => '可以在终端执行 git init 初始化仓库。';

  @override
  String gitFoundRepos(int count) {
    return '发现 $count 个 Git 仓库';
  }

  @override
  String get gitDiscardTitle => '丢弃变更';

  @override
  String gitDiscardMessage(String path) {
    return '确定要丢弃 $path 的所有未暂存变更吗？此操作不可撤销。';
  }

  @override
  String get gitDiscard => '丢弃';

  @override
  String gitSwitchRepo(int count) {
    return '切换仓库 ($count)';
  }

  @override
  String get gitSwitchBranch => '切换分支';

  @override
  String get gitCopyHash => '复制 Hash';

  @override
  String get gitBinaryFileToast => '无法获取文件内容（可能是二进制文件）';

  @override
  String gitChangedFiles(int count) {
    return '改动文件 ($count)';
  }

  @override
  String get gitChangesClean => '工作区干净';

  @override
  String get gitChangesCleanDesc => '没有未提交、未暂存或未跟踪的文件';

  @override
  String gitChangesStagedCount(int count) {
    return '已暂存 ($count)';
  }

  @override
  String get gitChangesUnstageAll => '全部取消暂存';

  @override
  String gitChangesUnstagedCount(int count) {
    return '未暂存 ($count)';
  }

  @override
  String get gitChangesStageAll => '全部暂存';

  @override
  String gitChangesUntrackedCount(int count) {
    return '未跟踪 ($count)';
  }

  @override
  String get gitChangesAddAll => '全部添加';

  @override
  String gitCommitStagedReady(int count) {
    return '$count 个文件已暂存，准备提交';
  }

  @override
  String get gitCommitNoStaged => '没有暂存的文件，请先暂存变更';

  @override
  String get gitCommitMessageHint => '输入提交信息...';

  @override
  String get gitCommitButton => '提交';

  @override
  String get gitCommitPulling => '拉取中...';

  @override
  String get gitCommitPushing => '推送中...';

  @override
  String get gitLogSelectBranch => '选择分支';

  @override
  String get gitLogSelectAuthor => '选择作者';

  @override
  String get gitLogSelectDateRange => '选择日期范围';

  @override
  String get gitLogToday => '今天';

  @override
  String get gitLogLast7Days => '最近 7 天';

  @override
  String get gitLogLast30Days => '最近 30 天';

  @override
  String get gitLogLast90Days => '最近 90 天';

  @override
  String get gitLogCustomRange => '自定义范围';

  @override
  String get gitLogClearDateFilter => '清除日期筛选';

  @override
  String get gitLogSearchCommit => '搜索 commit...';

  @override
  String get gitLogBranch => '分支';

  @override
  String get gitLogAuthor => '作者';

  @override
  String get gitLogDate => '日期';

  @override
  String get gitLogFrom => '从';

  @override
  String get gitLogUntil => '到';

  @override
  String get gitLogRemote => '远程';

  @override
  String get gitLogLocal => '本地';

  @override
  String get gitShellHint => '输入 git 命令，如 rebase、cherry-pick、stash';

  @override
  String get gitShellRestriction => '只允许 git 操作，其他命令会被拦截';

  @override
  String get gitShellConfirmExecute => '确认执行';

  @override
  String get gitLogNoMatchingCommits => '没有匹配的提交';

  @override
  String get gitLogNoFilteredCommits => '没有符合条件的提交';

  @override
  String get gitLogNoHistory => '没有提交历史';

  @override
  String get pluginTitle => '插件管理';

  @override
  String get pluginEmpty => '暂无插件';

  @override
  String get pluginEmptyHint => '点击右下角 + 安装插件';

  @override
  String get pluginStatusActive => '运行中';

  @override
  String get pluginStatusDisabled => '已禁用';

  @override
  String get pluginStatusError => '出错';

  @override
  String get pluginStatusUnavailable => '不可用';

  @override
  String get pluginStatusUnknown => '未知';

  @override
  String get pluginUninstallTitle => '卸载插件';

  @override
  String pluginUninstallMessage(String name) {
    return '确定要卸载 \"$name\" 吗？';
  }

  @override
  String get pluginInstallTitle => '安装插件';

  @override
  String get pluginInstallSource => '安装来源';

  @override
  String get pluginInstallFailed => '安装失败';

  @override
  String get pluginLoadFailed => '加载失败';

  @override
  String get thoughtBlockThinking => '思考中...';

  @override
  String get thoughtBlockDone => '思考过程';

  @override
  String get codeBlockCopy => '复制';

  @override
  String get codeBlockCopied => '已复制到剪贴板';

  @override
  String get planCardTitle => '计划';

  @override
  String get diffNoChanges => '没有变化';

  @override
  String get toolCallKindExecute => '命令';

  @override
  String get toolCallKindEdit => '编辑';

  @override
  String get toolCallKindSearch => '搜索';

  @override
  String get toolCallKindFetch => '网络';

  @override
  String get toolCallKindMove => '移动';

  @override
  String get toolCallKindDelete => '删除';

  @override
  String get toolCallKindThink => '推理';

  @override
  String get toolCallKindRead => '读取';

  @override
  String get toolCallKindDefault => '工具';

  @override
  String get toolCallDefaultName => '工具调用';

  @override
  String get toolCallAddedToContext => '已添加到上下文';

  @override
  String get toolCallWaitingTerminal => '等待终端输出...';

  @override
  String get connectionBannerReconnected => '已重新连接';

  @override
  String connectionBannerReconnecting(int attempt, int maxAttempts) {
    return '连接已断开，正在重连 (第 $attempt/$maxAttempts 次)...';
  }

  @override
  String get connectionBannerFailed => '连接失败';

  @override
  String get connectionBannerDisconnect => '断开';

  @override
  String get connectionStatusLan => 'LAN 直连';

  @override
  String get connectionStatusRelay => 'Relay 中继';

  @override
  String get connectionStatusTunnel => 'Tunnel 隧道';

  @override
  String get connectionStatusTimeout => '超时';

  @override
  String get connectionStatusDetails => '连接详情';

  @override
  String get connectionStatusMode => '模式';

  @override
  String get connectionStatusAddress => '地址';

  @override
  String get connectionStatusLatency => '延迟';

  @override
  String get connectionStatusUptime => '在线时长';

  @override
  String get connectionStatusDisconnect => '断开连接';

  @override
  String get authFormGetKey => '获取 Key';

  @override
  String get authFormAuthenticate => '认证';

  @override
  String get authFormOptional => '可选';

  @override
  String get authFormPasteKey => '粘贴密钥...';

  @override
  String get authFormEnterValue => '输入值...';

  @override
  String authFormFillField(String field) {
    return '请填写 $field';
  }

  @override
  String get authFormLinkCopied => '链接已复制到剪贴板';

  @override
  String get deviceCodeTitle => '在浏览器中登录';

  @override
  String get deviceCodeDescription => '打开下方链接，输入验证码完成登录';

  @override
  String get deviceCodeLabel => '验证码';

  @override
  String get deviceCodeTapToCopy => '点击复制验证码';

  @override
  String get deviceCodeCopied => '验证码已复制';

  @override
  String get deviceCodeWaiting => '等待登录完成...';

  @override
  String get deviceCodeUrlCopied => '链接已复制';

  @override
  String get deviceCodeSkip => '暂不认证';

  @override
  String get deviceCodeOpenBrowser => '在浏览器中打开';

  @override
  String get deviceCodeCannotOpenBrowser => '无法打开浏览器，请手动复制链接';

  @override
  String get deviceCodeLinkCopied => '链接已复制到剪贴板，请在浏览器中打开';

  @override
  String get deviceCodeCheckTerminal => '如果浏览器中需要输入验证码，请查看电脑终端';

  @override
  String get contextPickerTitle => '添加上下文';

  @override
  String get contextPickerSubtitle => '选择要引用的上下文类型';

  @override
  String get contextPickerFilesHint => '搜索文件（支持 file.ts:42 或 file.ts:42-50）';

  @override
  String get contextPickerFolderHint => '选择文件夹';

  @override
  String get contextPickerCurrentFileHint => '引用当前查看的文件';

  @override
  String get contextPickerTerminalHint => '引用终端输出';

  @override
  String get contextPickerUrlHint => '输入网址引用';

  @override
  String get contextPickerGitDiffHint => '引用当前 git 变更';

  @override
  String get contextPickerProblemsHint => '引用当前问题/错误';

  @override
  String contextPickerFileCount(int count) {
    return '$count 个文件';
  }

  @override
  String get contextPickerNoCurrentFile => '没有当前查看的文件';

  @override
  String get contextPickerNoTerminalOutput => '没有终端输出';

  @override
  String get contextPickerNoFolders => '当前项目没有可选文件夹';

  @override
  String get slashCmdNew => '新建会话';

  @override
  String get slashCmdClear => '清空当前对话';

  @override
  String get slashCmdHistory => '查看历史会话';

  @override
  String get slashCmdFiles => '查看项目文件';

  @override
  String get slashCmdTerminal => '打开终端';

  @override
  String get slashCmdDiff => '查看文件变更';

  @override
  String get slashCmdModel => '切换 AI 模型';

  @override
  String get slashCmdProject => '切换项目';

  @override
  String get slashCategorySession => '会话';

  @override
  String get slashCategoryTools => '工具';

  @override
  String get slashCategoryConfig => '配置';

  @override
  String get slashCategoryCli => 'CLI 命令';

  @override
  String get slashCmdHint => '点击选择命令 · Esc 关闭';

  @override
  String get codeEditorSearchHint => '搜索...';

  @override
  String get codeEditorReplaceHint => '替换...';

  @override
  String get codeEditorReplace => '替换';

  @override
  String get codeEditorReplaceAll => '全部替换';

  @override
  String get fileActionsAddToContext => '添加到上下文';

  @override
  String get fileActionsAddedToContext => '已添加到上下文';

  @override
  String get fileActionsNewFile => '新建文件';

  @override
  String get fileActionsNewFolder => '新建文件夹';

  @override
  String get fileActionsCopyPath => '复制路径';

  @override
  String get fileActionsPathCopied => '路径已复制';

  @override
  String get fileActionsSendToAi => '发送给 AI';

  @override
  String get fileActionsRunFile => '运行文件';

  @override
  String get fileActionsRename => '重命名';

  @override
  String get fileActionsEnterNewName => '输入新名称';

  @override
  String get fileActionsConfirmDelete => '确认删除';

  @override
  String fileActionsDeleteMessage(String name) {
    return '确定要删除 $name 吗？此操作不可撤销';
  }

  @override
  String get fileActionsEnterFileName => '输入文件名';

  @override
  String get fileActionsEnterFolderName => '输入文件夹名';

  @override
  String get fileSearchTypeToSearch => '输入关键词开始搜索';

  @override
  String get fileSearchNoFileMatch => '未找到匹配文件';

  @override
  String get fileSearchNoContentMatch => '未找到匹配内容';

  @override
  String fileSearchResultCount(int fileCount, int matchCount) {
    return '$fileCount 个文件中有 $matchCount 个结果';
  }

  @override
  String get attachmentAgentNotReady => 'Agent 尚未就绪';

  @override
  String get attachmentImage => '图片';

  @override
  String get attachmentImageNotSupported => '当前 Agent 不支持图片';

  @override
  String get attachmentAudio => '音频';

  @override
  String get attachmentAudioNotSupported => '当前 Agent 不支持音频';

  @override
  String get attachmentAudioComingSoon => '音频文件选择即将支持，敬请期待';

  @override
  String get attachmentFileRef => '文件引用';

  @override
  String get attachmentNotSupported => '当前 Agent 不支持此功能';

  @override
  String get cliSelectorTitle => '选择 CLI';

  @override
  String get configPanelAgentSettings => 'Agent 设置';

  @override
  String get configPanelAutoApprove => '自动批准权限';

  @override
  String get configPanelAutoApproveDesc => 'AI 执行操作时不再询问';

  @override
  String configPanelSwitchedTo(String name) {
    return '已切换到 $name';
  }

  @override
  String get configPanelOn => '开启';

  @override
  String get configPanelOff => '关闭';

  @override
  String get slashCmdImmediate => '即时';

  @override
  String get contextPickerSelectTerminal => '选择终端';

  @override
  String contextPickerTerminalN(String id) {
    return '终端 $id';
  }

  @override
  String contextPickerTerminalLines(int count) {
    return '$count 行输出';
  }

  @override
  String get contextPickerEnterUrl => '输入 URL';

  @override
  String get projectPickerTitle => '选择项目';

  @override
  String get projectPickerSearchHint => '搜索项目名称...';

  @override
  String get projectPickerFirstProject => '开始你的第一个项目';

  @override
  String get projectPickerFirstProjectDesc => '搜索项目名称、浏览目录或手动输入路径';

  @override
  String get projectPickerRecent => '最近项目';

  @override
  String get projectPickerNoMatch => '未找到匹配项目';

  @override
  String get projectPickerNoMatchDesc => '换个关键词试试，或浏览目录手动查找';

  @override
  String projectPickerFoundCount(int count) {
    return '找到 $count 个项目';
  }

  @override
  String projectPickerDirNotExist(String path) {
    return '$path (目录不存在)';
  }

  @override
  String get projectPickerBrowse => '浏览目录';

  @override
  String get projectPickerBrowseDesc => '从文件系统中选择项目目录';

  @override
  String get projectPickerManualInput => '手动输入路径';

  @override
  String get projectPickerManualInputDesc => '直接输入项目的完整路径';

  @override
  String get projectPickerDirEmpty => '此目录为空';

  @override
  String get projectPickerDirEmptyDesc => '没有找到子目录';

  @override
  String get projectPickerSelectDir => '选择此目录';

  @override
  String get componentDialogSave => '保存';

  @override
  String get componentDialogDiscard => '不保存';

  @override
  String get componentSearchClearFilter => '清除筛选';

  @override
  String get componentSearchNoMatch => '没有匹配项';

  @override
  String get componentSearchHint => '搜索...';

  @override
  String get componentSendToAiHint => '描述一下你想让 AI 做什么...';

  @override
  String get componentSendToAiButton => '发送给 AI';

  @override
  String get settingsTitle => '设置';

  @override
  String get settingsControlCenterSubtitle => 'MobileFlow 控制中心';

  @override
  String get settingsControlCenterDescription =>
      '像操控一台随身开发工作站一样管理项目、链路和 AI 工具。';

  @override
  String get settingsLinkOnline => '链路在线';

  @override
  String get settingsLinkOffline => '等待连接';

  @override
  String get settingsProjectsSection => '项目';

  @override
  String get settingsAddProject => '添加项目';

  @override
  String get settingsConnectionSection => '连接';

  @override
  String get settingsConnected => '已连接';

  @override
  String get settingsDisconnected => '未连接';

  @override
  String get settingsClearConnections => '清除保存的连接';

  @override
  String get settingsClearConnectionsDesc => '清除所有已保存的连接信息和密钥';

  @override
  String get settingsClearedConnections => '已清除所有保存的连接信息';

  @override
  String get settingsAppearanceSection => '外观';

  @override
  String get settingsDarkTheme => '暗色主题';

  @override
  String get settingsLanguageLabel => '语言';

  @override
  String get settingsEditorSection => '编辑器';

  @override
  String get settingsCodeTheme => '代码主题';

  @override
  String get settingsSelectCodeTheme => '选择代码主题';

  @override
  String get settingsWordWrap => '自动换行';

  @override
  String get settingsWordWrapOn => '长行折行显示';

  @override
  String get settingsWordWrapOff => '长行横向滚动';

  @override
  String get settingsShowLineNumbers => '显示行号';

  @override
  String get settingsFontSize => '字体大小';

  @override
  String get settingsPluginsSection => '插件';

  @override
  String get settingsPluginManagement => '插件管理';

  @override
  String get settingsPluginManagementDesc => '安装、启用和管理扩展插件';

  @override
  String get settingsCliToolsSection => 'AI CLI 工具';

  @override
  String get settingsAddCustomAgent => '添加自定义 Agent';

  @override
  String get settingsInstalled => '已安装';

  @override
  String get settingsNotInstalled => '未安装';

  @override
  String settingsNProjects(int count) {
    return '$count 个项目';
  }

  @override
  String settingsNClis(int count) {
    return '$count 个 CLI';
  }

  @override
  String settingsSwitchedTo(String name) {
    return '已切换到: $name';
  }

  @override
  String get settingsRemoveTooltip => '移除';

  @override
  String get settingsUninstallTooltip => '卸载';

  @override
  String get settingsPreparingInstall => '正在准备安装...';

  @override
  String settingsInstallingProgress(String label, int step, int total) {
    return '正在安装 $label ($step/$total)...';
  }

  @override
  String get settingsInstallFailed => '安装失败';

  @override
  String get settingsUninstallAgent => '卸载 Agent';

  @override
  String settingsUninstallConfirm(String name) {
    return '确定要卸载 \"$name\" 吗？\n将移除所有相关组件。';
  }

  @override
  String get settingsPreparingUninstall => '正在准备卸载...';

  @override
  String settingsUninstallingProgress(String label, int step, int total) {
    return '正在卸载 $label ($step/$total)...';
  }

  @override
  String get settingsAddCustomAgentTitle => '添加自定义 Agent';

  @override
  String get settingsAgentNameLabel => '名称';

  @override
  String get settingsAgentNameHint => '如: My Agent';

  @override
  String get settingsAgentCommandLabel => '命令';

  @override
  String get settingsAgentCommandHint => '如: my-agent';

  @override
  String get settingsAgentArgsLabel => '参数（空格分隔）';

  @override
  String get settingsAgentArgsHint => '如: acp 或 --acp';

  @override
  String get settingsRemoveAgent => '移除 Agent';

  @override
  String settingsRemoveAgentConfirm(String name) {
    return '确定要移除 \"$name\" 吗？';
  }

  @override
  String get settingsDeleteProject => '删除项目';

  @override
  String settingsDeleteProjectConfirm(String name) {
    return '确定要从列表中移除 \"$name\" 吗？\n（不会删除实际文件）';
  }

  @override
  String get settingsAgentCapabilities => 'ACP 能力';

  @override
  String get settingsAgentModes => '可用模式';

  @override
  String get settingsAgentConfig => '配置选项';

  @override
  String get settingsAgentActive => '当前使用中';

  @override
  String get settingsAgentInactive => '未激活';

  @override
  String get settingsAgentSourceBuiltin => '内置';

  @override
  String get settingsAgentSourceCustom => '自定义';

  @override
  String get settingsAgentSourcePlugin => '插件';

  @override
  String get settingsAgentCurrentlyUsing => '当前使用中';

  @override
  String get settingsAgentUseThis => '使用此 Agent';

  @override
  String settingsAgentModeSwitched(String name) {
    return '模式: $name';
  }

  @override
  String get settingsAgentSwitchToConfig => '切换到此 Agent 后可查看和修改模式与配置';

  @override
  String get settingsAgentSwitchToViewCaps => '切换到此 Agent 后可查看 ACP 能力信息';

  @override
  String get settingsCapSessionLoad => '会话加载';

  @override
  String get settingsCapSessionList => '会话列表';

  @override
  String get settingsCapSessionClose => '会话关闭';

  @override
  String get settingsCapSessionFork => '会话分叉';

  @override
  String get settingsCapSessionResume => '会话恢复';

  @override
  String get settingsCapImage => '图片输入';

  @override
  String get settingsCapAudio => '音频输入';

  @override
  String get settingsCapEmbeddedContext => '嵌入上下文';

  @override
  String get settingsCapMcpHttp => 'MCP HTTP';

  @override
  String get settingsCapMcpSse => 'MCP SSE';

  @override
  String get testPanelTabPreview => '预览';

  @override
  String get testPanelTabScript => '脚本';

  @override
  String get testPanelTabApi => 'API';

  @override
  String get testPanelTab => '测试';

  @override
  String get previewPortHint => '端口 (可选，自动检测)';

  @override
  String get previewCommandHint => '启动命令 (如 npm run dev)';

  @override
  String get previewCwdHint => '工作目录 (可选，默认: 项目根目录)';

  @override
  String get previewIdleTitle => '输入启动命令，自动检测端口并预览';

  @override
  String get previewIdleSubtitle => '也可只填端口号连接已有服务';

  @override
  String get previewStarting => '正在启动预览...';

  @override
  String get previewStopping => '正在停止预览...';

  @override
  String get previewErrorTitle => '预览出错';

  @override
  String get previewStartTooltip => '启动预览';

  @override
  String get previewStopTooltip => '停止预览';

  @override
  String get previewInvalidPort => '端口号无效 (1-65535)';

  @override
  String get previewNeedPortOrCommand => '请输入命令或端口号';

  @override
  String get previewVisualDiffCaptured => '已捕获视觉对比基线。修改代码后点击对比查看差异。';

  @override
  String get previewCrashFallback => '预览意外崩溃';

  @override
  String get scriptCommandHint => '输入命令...';

  @override
  String get scriptCwdHint => '工作目录 (可选)';

  @override
  String get scriptHistoryTooltip => '命令历史';

  @override
  String get scriptHistoryTitle => '命令历史';

  @override
  String get scriptRunTooltip => '运行';

  @override
  String get scriptStopTooltip => '停止';

  @override
  String get scriptIdleHint => '运行命令后输出将显示在这里';

  @override
  String get scriptExitKilled => '已终止';

  @override
  String scriptExitCode(int code) {
    return '退出码: $code';
  }

  @override
  String get apiHeadersLabel => '请求头';

  @override
  String get apiBodyLabel => '请求体';

  @override
  String get apiHeaderKeyHint => '键';

  @override
  String get apiHeaderValueHint => '值';

  @override
  String get apiSendButton => '发送';

  @override
  String get apiSavePresetTooltip => '保存为预设';

  @override
  String get apiSavePresetTitle => '保存预设';

  @override
  String get apiPresetNameHint => '预设名称';

  @override
  String get apiResponseCopied => '响应已复制';

  @override
  String get apiCopyResponseTooltip => '复制响应';

  @override
  String get apiResponseTruncated => '[响应已截断: 超过 1MB]';

  @override
  String get runConfigQuickRun => '快速运行';

  @override
  String get runConfigQuickRunHint => '输入命令（如 npm run dev）';

  @override
  String get runConfigCancel => '取消';

  @override
  String get runConfigRun => '运行';

  @override
  String get runConfigNoConfigs => '暂无运行配置';

  @override
  String get runConfigNoConfigsDesc => '在桌面端 Dashboard 创建配置即可开始使用。';

  @override
  String get runConfigViewOutput => '查看输出';

  @override
  String get runConfigStop => '停止';

  @override
  String get runConfigRestart => '重启';

  @override
  String get runConfigStateIdle => '空闲';

  @override
  String get runConfigStateBeforeRun => '执行前置任务...';

  @override
  String get runConfigStateStarting => '启动中...';

  @override
  String get runConfigStateRunning => '运行中';

  @override
  String get runConfigStateStopping => '停止中...';

  @override
  String get runConfigStateStopped => '已停止';

  @override
  String get runConfigWaitingOutput => '等待输出...';

  @override
  String get runConfigOutputTab => '输出';

  @override
  String get runConfigPreviewTab => '预览';

  @override
  String get runConfigRefresh => '刷新';

  @override
  String runConfigExitCode(int code) {
    return '退出码: $code';
  }

  @override
  String get previewUrlHint => 'URL（如 https://localhost:3000）';

  @override
  String get runConfigDetailTitle => '配置详情';

  @override
  String get runConfigNameLabel => '名称';

  @override
  String get runConfigCommandLabel => '命令';

  @override
  String get runConfigWorkDirLabel => '工作目录';

  @override
  String get runConfigPreviewUrlLabel => '预览 URL';

  @override
  String get runConfigHostHeaderLabel => 'Host Header';

  @override
  String get runConfigDeleteConfirmTitle => '删除配置';

  @override
  String runConfigDeleteConfirmBody(String name) {
    return '确定要删除 \"$name\" 吗？';
  }

  @override
  String get foregroundServiceConnected => '已连接 · 编程助手运行中';

  @override
  String get foregroundServiceStreaming => '✨ AI 正在回复...';

  @override
  String get foregroundServiceDone => '✅ 回复完成';
}
