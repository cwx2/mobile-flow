/// error_block.dart — Error message block.
///
/// Displays error messages during AI response with a red background
/// and error icon for prominent visibility.

import 'package:flutter/material.dart';

/// Displays an error message with red styling.
class ErrorBlock extends StatelessWidget {
  final String text;
  const ErrorBlock({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF352030),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 16, color: Color(0xFFEB6F92)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: const TextStyle(fontSize: 13, color: Color(0xFFEB6F92))),
          ),
        ],
      ),
    );
  }
}
