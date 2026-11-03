/// Repeat navigation written at a bar: segno and coda where the bar starts,
/// the others where it ends. [text] is how it is written.
enum NavigationMark {
  segno('Segno', atEnd: false),
  coda('Coda', atEnd: false),
  fine('Fine', atEnd: true),
  toCoda('To Coda', atEnd: true),
  daCapo('D.C.', atEnd: true),
  daCapoAlFine('D.C. al Fine', atEnd: true),
  daCapoAlCoda('D.C. al Coda', atEnd: true),
  dalSegno('D.S.', atEnd: true),
  dalSegnoAlFine('D.S. al Fine', atEnd: true),
  dalSegnoAlCoda('D.S. al Coda', atEnd: true);

  const NavigationMark(this.text, {required this.atEnd});

  final String text;
  final bool atEnd;

  /// A jump back to the start (D.C.) or to the segno (D.S.).
  bool get isJump => index >= daCapo.index;
  bool get toSegno => index >= dalSegno.index;
  bool get alFine => this == daCapoAlFine || this == dalSegnoAlFine;
  bool get alCoda => this == daCapoAlCoda || this == dalSegnoAlCoda;

  static List<NavigationMark> listFromJson(Object? json) => json is List
      ? [
          for (final name in json)
            ?values.where((m) => m.name == name).firstOrNull,
        ]
      : const [];
}

/// How a first/second ending's bracket closes at its last bar.
enum EndingEnd { closed, open }
