// GENERATED CODE — DO NOT EDIT BY HAND
// Generated from mobileflow_protocol v1
//
// To regenerate, run from pocket-coder/protocol/:
//   python generate_dart.py
//
// Source: protocol/src/mobileflow_protocol/types.py

/// Protocol version for App-Agent WebSocket communication.
const int protocolVersion = 1;

/// All WebSocket message type constants.
///
/// Auto-generated from the Python mobileflow_protocol package.
/// Each constant maps to a protocol message exchanged between
/// the Flutter app and the Python agent over WebSocket.
class MessageType {
  // ── Authentication ──
  static const authPair = 'auth.pair'; // App -> Agent: initial 6-digit pairing [request]
  static const authConnect = 'auth.connect'; // App -> Agent: reconnect with session token [request]
  static const authResult = 'auth.result'; // Agent -> App: auth outcome (success/failure) [request]
  static const authSubmit = 'auth.submit'; // App -> Agent: submit CLI auth credentials [command]

  // ── Chat ──
  static const chatSend = 'chat.send'; // App -> Agent: user message to AI [request]
  static const chatStream = 'chat.stream'; // Agent -> App: streaming response chunk [notification]
  static const chatDone = 'chat.done'; // Agent -> App: AI turn complete [notification]
  static const chatError = 'chat.error'; // Agent -> App: prompt-level error [notification]
  static const chatCancel = 'chat.cancel'; // App -> Agent: cancel current AI operation [command]
  static const chatHistory = 'chat.history'; // App -> Agent: request conversation history [request]
  static const chatHistoryResult = 'chat.history.result'; // Agent -> App: history page [request]
  static const chatHistoryMore = 'chat.history.more'; // App -> Agent: request next page [request]
  static const chatHistoryMoreResult = 'chat.history.more.result'; // Agent -> App: next page [request]
  static const chatReplay = 'chat.replay'; // App -> Agent: request buffered chunks after reconnect [request]
  static const chatReplayResult = 'chat.replay.result'; // Agent -> App: replayed chunks batch [request]

  // ── Session ──
  static const sessionList = 'session.list'; // App -> Agent: list available sessions [request]
  static const sessionListResult = 'session.list.result'; // Agent -> App: session list [request]
  static const sessionNew = 'session.new'; // App -> Agent: create new session [request]
  static const sessionSwitch = 'session.switch'; // App -> Agent: switch to existing session [request]
  static const sessionClose = 'session.close'; // App -> Agent: close a session [request]

  // ── ACP Configuration ──
  static const modeSet = 'mode.set'; // App -> Agent: switch session mode [command]

  static const configSet = 'config.set'; // App -> Agent: set config option value [command]

  // ── File Operations ──
  static const fileTree = 'file.tree'; // App -> Agent: request directory tree [request]
  static const fileTreeResult = 'file.tree.result'; // Agent -> App: directory tree data [request]
  static const fileRead = 'file.read'; // App -> Agent: read file content [request]
  static const fileReadResult = 'file.read.result'; // Agent -> App: file content [request]
  static const fileWrite = 'file.write'; // App -> Agent: write file content [request]
  static const fileWriteResult = 'file.write.result'; // Agent -> App: write result [request]
  static const fileSearch = 'file.search'; // App -> Agent: search files/content [request]
  static const fileSearchResult = 'file.search.result'; // Agent -> App: search results (final) [request]
  static const fileSearchStream = 'file.search.stream'; // Agent -> App: search results (streaming) [request]
  static const fileCreate = 'file.create'; // App -> Agent: create file or directory [request]
  static const fileCreateResult = 'file.create.result'; // Agent -> App: create result [request]
  static const fileRename = 'file.rename'; // App -> Agent: rename file or directory [request]
  static const fileRenameResult = 'file.rename.result'; // Agent -> App: rename result [request]
  static const fileDelete = 'file.delete'; // App -> Agent: delete file or directory [request]
  static const fileDeleteResult = 'file.delete.result'; // Agent -> App: delete result [request]
  static const fileChanged = 'file.changed'; // Agent -> App: file system change notification [notification]

  // ── Diff Operations ──
  static const diffPreview = 'diff.preview'; // Agent -> App: proposed diff for review [notification]
  static const diffApply = 'diff.apply'; // App -> Agent: accept proposed diff [command]
  static const diffReject = 'diff.reject'; // App -> Agent: reject proposed diff [command]

  // ── Git Operations ──
  static const gitStatus = 'git.status'; // App -> Agent: request repo status [request]
  static const gitStatusResult = 'git.status.result'; // Agent -> App: repo status [request]
  static const gitDiff = 'git.diff'; // App -> Agent: request file diff [request]
  static const gitDiffResult = 'git.diff.result'; // Agent -> App: diff content [request]
  static const gitStage = 'git.stage'; // App -> Agent: stage files [request]
  static const gitStageResult = 'git.stage.result'; // Agent -> App: stage result [request]
  static const gitUnstage = 'git.unstage'; // App -> Agent: unstage files [request]
  static const gitUnstageResult = 'git.unstage.result'; // Agent -> App: unstage result [request]
  static const gitCommit = 'git.commit'; // App -> Agent: create commit [request]
  static const gitCommitResult = 'git.commit.result'; // Agent -> App: commit result [request]
  static const gitPush = 'git.push'; // App -> Agent: push to remote [request]
  static const gitPushResult = 'git.push.result'; // Agent -> App: push result [request]
  static const gitPull = 'git.pull'; // App -> Agent: pull from remote [request]
  static const gitPullResult = 'git.pull.result'; // Agent -> App: pull result [request]
  static const gitBranches = 'git.branches'; // App -> Agent: list branches [request]
  static const gitBranchesResult = 'git.branches.result'; // Agent -> App: branch list [request]
  static const gitCheckout = 'git.checkout'; // App -> Agent: switch branch [request]
  static const gitCheckoutResult = 'git.checkout.result'; // Agent -> App: checkout result [request]
  static const gitLog = 'git.log'; // App -> Agent: request commit log [request]
  static const gitLogResult = 'git.log.result'; // Agent -> App: commit log [request]
  static const gitLogSearch = 'git.log.search'; // App -> Agent: search commit log [request]
  static const gitLogSearchResult = 'git.log.search.result'; // Agent -> App: search results [request]
  static const gitLogAuthors = 'git.log.authors'; // App -> Agent: list commit authors [request]
  static const gitLogAuthorsResult = 'git.log.authors.result'; // Agent -> App: author list [request]
  static const gitShow = 'git.show'; // App -> Agent: show commit details [request]
  static const gitShowResult = 'git.show.result'; // Agent -> App: commit details [request]
  static const gitDiffCommit = 'git.diff.commit'; // App -> Agent: diff a specific commit file [request]
  static const gitDiffCommitResult = 'git.diff.commit.result'; // Agent -> App: commit file diff [request]
  static const gitDiscard = 'git.discard'; // App -> Agent: discard file changes [request]
  static const gitDiscardResult = 'git.discard.result'; // Agent -> App: discard result [request]
  static const gitRepos = 'git.repos'; // App -> Agent: discover git repositories [request]
  static const gitReposResult = 'git.repos.result'; // Agent -> App: repository list [request]
  static const gitSwitchRepo = 'git.switch_repo'; // App -> Agent: switch active repository [request]
  static const gitExec = 'git.exec'; // App -> Agent: execute arbitrary git command [request]
  static const gitExecResult = 'git.exec.result'; // Agent -> App: execution result [request]

  // ── Terminal ──
  static const terminalStart = 'terminal.start'; // App -> Agent: start terminal session [request]
  static const terminalStarted = 'terminal.started'; // Agent -> App: terminal session ready [notification]
  static const terminalInput = 'terminal.input'; // App -> Agent: user keyboard input [command]
  static const terminalOutput = 'terminal.output'; // Agent -> App: terminal output (base64) [notification]
  static const terminalResize = 'terminal.resize'; // App -> Agent: resize terminal dimensions [command]
  static const terminalStop = 'terminal.stop'; // App -> Agent: stop terminal session [command]

  // ── CLI Management ──
  static const cliList = 'cli.list'; // App -> Agent: list all CLI adapters [request]
  static const cliListResult = 'cli.list.result'; // Agent -> App: adapter list with capabilities [request]
  static const cliSwitch = 'cli.switch'; // App -> Agent: switch active CLI [command]
  static const cliStatus = 'cli.status'; // Agent -> App: CLI lifecycle state push [notification]
  static const cliRetry = 'cli.retry'; // App -> Agent: retry failed CLI initialization [command]
  static const cliInstall = 'cli.install'; // App -> Agent: install a CLI [request]
  static const cliInstallResult = 'cli.install.result'; // Agent -> App: install outcome [request]
  static const cliInstallProgress = 'cli.install.progress'; // Agent -> App: install step progress [notification]
  static const cliUninstall = 'cli.uninstall'; // App -> Agent: uninstall a CLI [request]
  static const cliUninstallResult = 'cli.uninstall.result'; // Agent -> App: uninstall outcome [request]
  static const cliAdd = 'cli.add'; // App -> Agent: add custom agent [request]
  static const cliRemove = 'cli.remove'; // App -> Agent: remove custom agent [command]
  static const cliCommands = 'cli.commands'; // Agent -> App: CLI-advertised slash commands [notification]

  // ── Permissions ──
  static const permissionRequest = 'permission.request'; // Agent -> App: request tool permission [notification]
  static const permissionResponse = 'permission.response'; // App -> Agent: user permission decision [command]
  static const permissionPolicy = 'permission.policy'; // Agent -> App: permission policy update [notification]

  // ── Confirm (legacy) ──
  static const confirmRequest = 'confirm.request'; // Agent -> App: confirm dangerous operation [request]
  static const confirmResponse = 'confirm.response'; // App -> Agent: user confirmation [command]

  // ── Project Management ──
  static const projectList = 'project.list'; // App -> Agent: list registered projects [request]
  static const projectListResult = 'project.list.result'; // Agent -> App: project list [request]
  static const projectAdd = 'project.add'; // App -> Agent: add project directory [request]
  static const projectRemove = 'project.remove'; // App -> Agent: remove project [command]
  static const projectSwitch = 'project.switch'; // App -> Agent: switch active project [command]
  static const projectCurrent = 'project.current'; // Agent -> App: current project info [notification]
  static const projectSearch = 'project.search'; // App -> Agent: search/browse for projects [request]
  static const projectSearchResult = 'project.search.result'; // Agent -> App: search results [request]

  // ── Plugin Management ──
  static const pluginList = 'plugin.list'; // App -> Agent: list installed plugins [request]
  static const pluginListResult = 'plugin.list.result'; // Agent -> App: plugin list [request]
  static const pluginEnable = 'plugin.enable'; // App -> Agent: enable a plugin [command]
  static const pluginDisable = 'plugin.disable'; // App -> Agent: disable a plugin [command]
  static const pluginUninstall = 'plugin.uninstall'; // App -> Agent: uninstall a plugin [command]
  static const pluginStateChanged = 'plugin.state_changed'; // Agent -> App: plugin state change [notification]
  static const pluginInstall = 'plugin.install'; // App -> Agent: install a plugin [request]
  static const pluginInstallResult = 'plugin.install.result'; // Agent -> App: install outcome [request]
  static const pluginConfigGet = 'plugin.config.get'; // App -> Agent: get plugin config [request]
  static const pluginConfigGetResult = 'plugin.config.get.result'; // Agent -> App: plugin config [request]
  static const pluginConfigSet = 'plugin.config.set'; // App -> Agent: set plugin config [request]
  static const pluginConfigSetResult = 'plugin.config.set.result'; // Agent -> App: set result [request]

  // ── Heartbeat ──
  static const statusPing = 'status.ping'; // App -> Agent: ping [command]
  static const statusPong = 'status.pong'; // Agent -> App: pong [command]

  // ── State Push ──
  static const statePush = 'state.push'; // Agent -> App: cached state update [notification]

  // ── Script ──
  static const scriptRun = 'script.run'; // App -> Agent: execute a command [request]
  static const scriptOutput = 'script.output'; // Agent -> App: stdout/stderr stream chunk [request]
  static const scriptDone = 'script.done'; // Agent -> App: command completed [request]
  static const scriptStop = 'script.stop'; // App -> Agent: stop running command [request]

  // ── Api ──
  static const apiRequest = 'api.request'; // App -> Agent: execute HTTP request [request]
  static const apiResponse = 'api.response'; // Agent -> App: HTTP response [request]
  static const apiError = 'api.error'; // Agent -> App: request error [request]

  // ── Preview ──
  static const previewStart = 'preview.start'; // App -> Agent: start dev server + proxy [request]
  static const previewReady = 'preview.ready'; // Agent -> App: preview URL available [request]
  static const previewOutput = 'preview.output'; // Agent -> App: dev server stdout/stderr [request]
  static const previewStop = 'preview.stop'; // App -> Agent: stop dev server + proxy [request]
  static const previewStopped = 'preview.stopped'; // Agent -> App: dev server terminated [request]
  static const previewFileChanged = 'preview.file_changed'; // Agent -> App: file change during preview [request]
  static const previewDetect = 'preview.detect'; // App -> Agent: detect project type (plugin) [request]
  static const previewDetectResult = 'preview.detect.result'; // Agent -> App: detection result [request]

  // ── Screenshot ──
  static const screenshotCapture = 'screenshot.capture'; // App -> Agent: capture screenshot [request]
  static const screenshotResult = 'screenshot.result'; // Agent -> App: screenshot image [request]
  static const screenshotError = 'screenshot.error'; // Agent -> App: capture error [request]

  // ── Visual_diff ──
  static const visualDiffStart = 'visual_diff.start'; // App -> Agent: capture "before" baseline [request]
  static const visualDiffCompare = 'visual_diff.compare'; // App -> Agent: capture "after" and diff [request]
  static const visualDiffResult = 'visual_diff.result'; // Agent -> App: diff result with images [request]

  // ── Runtime ──
  static const runtimeResolve = 'runtime.resolve'; // App -> Agent: resolve file → command mapping [request]
  static const runtimeResolveResult = 'runtime.resolve.result'; // Agent -> App: resolved command [request]

  // ── Run_config ──
  static const runConfigList = 'run_config.list'; // App -> Agent: list all configurations [request]
  static const runConfigListResult = 'run_config.list_result'; // Agent -> App: configuration list [request]
  static const runConfigCreate = 'run_config.create'; // App -> Agent: create new configuration [request]
  static const runConfigCreated = 'run_config.created'; // Agent -> App: newly created config [request]
  static const runConfigUpdate = 'run_config.update'; // App -> Agent: update configuration fields [request]
  static const runConfigUpdated = 'run_config.updated'; // Agent -> App: updated configuration [request]
  static const runConfigDelete = 'run_config.delete'; // App -> Agent: delete a configuration [request]
  static const runConfigDeleted = 'run_config.deleted'; // Agent -> App: deletion confirmation [request]
  static const runConfigSelect = 'run_config.select'; // App -> Agent: set selected configuration [request]
  static const runConfigChanged = 'run_config.changed'; // Agent -> All: broadcast config list change [request]
  static const runConfigStart = 'run_config.start'; // App -> Agent: start execution [request]
  static const runConfigStop = 'run_config.stop'; // App -> Agent: stop execution [request]
  static const runConfigRestart = 'run_config.restart'; // App -> Agent: restart execution [request]
  static const runConfigOutput = 'run_config.output'; // Agent -> App: process output stream [request]
  static const runConfigStateChanged = 'run_config.state_changed'; // Agent -> App: lifecycle state transition [request]
  static const runConfigStatus = 'run_config.status'; // App -> Agent: get all running states [request]
  static const runConfigStatusResult = 'run_config.status_result'; // Agent -> App: running states map [request]
}
