import 'package:flutter/services.dart';

class EmojiBlockingFormatter extends TextInputFormatter {
  EmojiBlockingFormatter({required this.onBlocked});

  final VoidCallback onBlocked;

  static final _emojiRegex = RegExp(
    r'[\u{1F300}-\u{1F9FF}\u{1FA00}-\u{1FAFF}\u{2600}-\u{27BF}]',
    unicode: true,
  );

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (_emojiRegex.hasMatch(newValue.text)) {
      onBlocked();
      return oldValue;
    }
    return newValue;
  }
}
