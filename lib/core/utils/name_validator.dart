import 'package:flutter/services.dart';

/// Single source of truth for username validation rules.
///
/// Rules:
/// - Letters (a–z, A–Z) and single spaces between words only
/// - No numbers, special characters, or emoji
/// - Minimum 1 character (after trimming)
/// - Maximum [maxLength] characters
class NameValidator {
  NameValidator._();

  static const int maxLength = 100;

  /// Regex: only Unicode letters and spaces allowed.
  static final RegExp _validPattern = RegExp(r"^[\p{L} ]+$", unicode: true);

  /// Regex to detect disallowed characters for targeted error messages.
  static final RegExp _hasDigit = RegExp(r'\d');
  static final RegExp _hasEmoji = RegExp(
    r'[\u{1F600}-\u{1F64F}'
    r'\u{1F300}-\u{1F5FF}'
    r'\u{1F680}-\u{1F6FF}'
    r'\u{1F700}-\u{1F77F}'
    r'\u{1F780}-\u{1F7FF}'
    r'\u{1F800}-\u{1F8FF}'
    r'\u{1F900}-\u{1F9FF}'
    r'\u{1FA00}-\u{1FA6F}'
    r'\u{1FA70}-\u{1FAFF}'
    r'\u{2600}-\u{26FF}'
    r'\u{2700}-\u{27BF}]',
    unicode: true,
  );

  /// Returns an error string if invalid, or `null` if the value is valid.
  /// Pass the raw (untrimmed) controller text.
  static String? validate(String value) {
    if (value.isEmpty) return null; // empty = no error yet, just disabled

    final trimmed = value.trim();

    if (trimmed.isEmpty) return 'Name cannot be only spaces';
    if (trimmed.length > maxLength) return 'Name is too long';

    if (_hasEmoji.hasMatch(value)) {
      return 'Emoji are not allowed';
    }
    if (_hasDigit.hasMatch(value)) {
      return 'Numbers are not allowed';
    }
    if (!_validPattern.hasMatch(trimmed)) {
      return 'Only letters and spaces are allowed';
    }

    return null; // valid
  }

  /// [TextInputFormatter] that silently blocks any character that is not a
  /// Unicode letter or a space.
  static final TextInputFormatter inputFormatter =
      FilteringTextInputFormatter.allow(
    RegExp(r'[\p{L} ]', unicode: true),
  );
}