import 'package:highlight/highlight.dart' show highlight, Node;

void main() {
  final code = 'def hello():\n    print("hello world")\n\nx = 42';
  final result = highlight.parse(code, language: 'python');
  print('nodes: ${result.nodes?.length}');
  print('relevance: ${result.relevance}');
  if (result.nodes != null) {
    for (final node in result.nodes!) {
      _printNode(node, 0);
    }
  }
}

void _printNode(Node node, int depth) {
  final indent = '  ' * depth;
  if (node.value != null) {
    print('${indent}TEXT: "${node.value}" class=${node.className}');
  }
  if (node.children != null) {
    print('${indent}NODE class=${node.className}');
    for (final child in node.children!) {
      _printNode(child, depth + 1);
    }
  }
}
