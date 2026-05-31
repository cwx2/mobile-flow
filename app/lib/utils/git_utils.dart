/// git_utils.dart — Git-related utility functions.
//
// Pure utility functions reused by file browser and other screens.

/// Count the number of Git changed files under a given folder path.
int countFolderChanges(String folderPath, Map<String, String> gitStatusMap) {
  final prefix = folderPath.isEmpty ? '' : '$folderPath/';
  return gitStatusMap.keys
      .where((path) => prefix.isEmpty || path.startsWith(prefix))
      .length;
}
