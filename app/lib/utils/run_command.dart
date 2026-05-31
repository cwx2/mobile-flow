/// run_command.dart — Run command mapping utility.
//
// 根据文件扩展名返回对应的终端运行命令。

/// 根据文件路径返回终端运行命令，不支持的类型返回 null
String? getRunCommand(String path) {
  final ext = path.split('.').last.toLowerCase();
  return switch (ext) {
    'py' => 'python $path',
    'js' => 'node $path',
    'sh' => 'bash $path',
    'ts' => 'npx ts-node $path',
    'dart' => 'dart run $path',
    _ => null,
  };
}
