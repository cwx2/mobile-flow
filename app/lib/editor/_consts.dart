/// _consts.dart — Platform detection constants.
///
/// Exposes [kIsMacOS], [kIsAndroid], and [kIsIOS] as top-level finals
/// derived from [defaultTargetPlatform]. Used throughout the editor to
/// branch on platform-specific behavior (e.g. keyboard shortcuts,
/// selection gestures, floating cursor support).
part of editor;

final kIsMacOS = defaultTargetPlatform == TargetPlatform.macOS;
final kIsAndroid = defaultTargetPlatform == TargetPlatform.android;
final kIsIOS = defaultTargetPlatform == TargetPlatform.iOS;
