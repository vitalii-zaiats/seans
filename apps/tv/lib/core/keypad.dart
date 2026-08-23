import 'package:flutter/foundation.dart';

/// One key of a telephone: the digit, and the letters printed on it.
@immutable
class KeypadKey {
  const KeypadKey(this.digit, this.letters);

  final String digit;

  /// In the order they are reached by pressing the key again.
  final String letters;
}

/// The letters a telephone keypad puts under each digit.
///
/// **The same alphabets as `packages/python/t9/src/t9/layouts.py`, spelled out
/// again rather than fetched.** Which letters sit under which digit, and in
/// what order, *is* the code a title gets indexed under: move `Ї` off 4 on one
/// side only and every title indexed before the change stops answering what
/// this types. Written out in full on both sides so that a drift is a diff
/// between two visible strings, rather than something to be worked out from a
/// search that quietly returns nothing.
///
/// Upper case here and lower case there for one reason: this app has no
/// `TextField` and uppercases everything on the way in, and a keypad is
/// case-blind anyway — `Г` and `г` are both 2.
enum Keypad {
  /// Thirty-three letters over eight keys, alphabetically.
  ///
  /// No standard says how Ukrainian sits on a keypad — E.161 only ever covered
  /// Latin — so this is the arrangement the index was built with and nothing
  /// else. Alphabetical because it is the only order somebody can guess at
  /// from the printed letters alone.
  ukrainian('uk', 'УКР', [
    KeypadKey('2', 'АБВГҐ'),
    KeypadKey('3', 'ДЕЄЖЗ'),
    KeypadKey('4', 'ИІЇЙК'),
    KeypadKey('5', 'ЛМНО'),
    KeypadKey('6', 'ПРСТ'),
    KeypadKey('7', 'УФХЦЧ'),
    KeypadKey('8', 'ШЩЬ'),
    KeypadKey('9', 'ЮЯ'),
  ]),

  /// ITU E.161 — the arrangement printed on every telephone ever made.
  latin('en', 'ABC', [
    KeypadKey('2', 'ABC'),
    KeypadKey('3', 'DEF'),
    KeypadKey('4', 'GHI'),
    KeypadKey('5', 'JKL'),
    KeypadKey('6', 'MNO'),
    KeypadKey('7', 'PQRS'),
    KeypadKey('8', 'TUV'),
    KeypadKey('9', 'WXYZ'),
  ]);

  const Keypad(this.id, this.title, this.keys);

  /// Matches the key in the Python package's `LAYOUTS`.
  final String id;

  /// What the key that switches to this one is labelled with.
  final String title;

  final List<KeypadKey> keys;

  /// The letters under [digit], or empty where the digit carries none — 1 and
  /// 0 do here, exactly as on a telephone.
  String lettersFor(String digit) {
    for (final key in keys) {
      if (key.digit == digit) return key.letters;
    }
    return '';
  }

  /// The other alphabet. There are two, and the key that switches between them
  /// is one key rather than a menu.
  Keypad get other => this == ukrainian ? latin : ukrainian;
}

/// How somebody types on this machine.
enum TypingMode {
  /// Seventy letters in a grid, walked with the arrows.
  ///
  /// Every letter is one press once you are on it, and getting on it is what
  /// costs: `Я` is eleven presses from `А`.
  keyboard('keyboard', 'Клавіатура', 'Літери сіткою, стрілками'),

  /// The remote's own number keys, multi-tap, the way a telephone worked.
  ///
  /// Four presses for a letter at worst and no travel at all, because the keys
  /// are already under the thumb.
  keypad('keypad', 'Цифри', 'Кнопки 1–9, як на телефоні');

  const TypingMode(this.id, this.title, this.note);

  final String id;
  final String title;
  final String note;

  static TypingMode fromId(String? id) => values.firstWhere(
    (mode) => mode.id == id,
    orElse: () => TypingMode.keyboard,
  );
}
