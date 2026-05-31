// 全局测试配置
//
// 禁用 google_fonts 的运行时字体下载，避免测试中的网络请求失败。

import 'dart:async';

import 'package:google_fonts/google_fonts.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  GoogleFonts.config.allowRuntimeFetching = false;
  await testMain();
}
