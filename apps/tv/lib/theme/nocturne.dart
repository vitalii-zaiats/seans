import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// The Nocturne palette, straight from the design system's token sheet.
///
/// A near-neutral blue-grey ground with one accent that is used as a line and
/// a glow rather than a flood. The neutrals never change; the accent and the
/// ground are chosen in settings, so read those two through [TvPalette] on
/// `BuildContext` rather than from here.
abstract final class Nocturne {
  static const text = Color(0xFFE9E9ED);

  /// The default accent and ground — what the design was drawn in, and the
  /// fallback wherever no palette is in scope.
  static const accent = Color(0xFF9184D9);
  static const bg = Color(0xFF161826);

  static const surface = Color(0xFF232532);

  // Neutral ramp. On this dark ground the deep steps (700–900) are for tinted
  // fills and borders, 500 is the base, and the light steps are text on them.
  //
  // 100 is the one near-white in the app: a QR code needs a light quiet zone
  // to scan, and the design forbids pure white.
  static const neutral100 = Color(0xFFF3F5FE);

  static const neutral300 = Color(0xFFCFD3E5);
  static const neutral400 = Color(0xFFB2B6CA);
  static const neutral500 = Color(0xFF9397AB);
  static const neutral600 = Color(0xFF75798C);
  static const neutral700 = Color(0xFF595D6C);
  static const neutral800 = Color(0xFF3F424D);
  static const neutral900 = Color(0xFF292B31);

  /// Muted body text; the accent itself is too low-contrast for paragraphs.
  static const muted = neutral500;

  /// The system prefers whitespace to rules; 8px is the one radius.
  static const radius = 8.0;

  static Color divider = text.withValues(alpha: 0.16);

  /// The accents offered in settings.
  ///
  /// Every one is a mid-chroma hue that keeps at least 3:1 against the dark
  /// grounds — enough for a ring, a glow and interface chrome, which is all
  /// the accent is ever used for here.
  static const accents = <PaletteOption>[
    PaletteOption('blurple', 'Бузковий', Color(0xFF9184D9)),
    PaletteOption('teal', 'Бірюзовий', Color(0xFF4FB3A7)),
    PaletteOption('amber', 'Бурштиновий', Color(0xFFD9A441)),
    PaletteOption('rose', 'Трояндовий', Color(0xFFD9738A)),
    PaletteOption('sky', 'Небесний', Color(0xFF5B9BD9)),
    PaletteOption('lime', 'Лаймовий', Color(0xFF8FBF52)),
  ];

  /// The grounds offered in settings.
  static const grounds = <PaletteOption>[
    PaletteOption('nocturne', 'Ноктюрн', Color(0xFF161826)),
    PaletteOption('midnight', 'Опівніч', Color(0xFF0E1013)),
    PaletteOption('ink', 'Чорнило', Color(0xFF000000)),
    PaletteOption('indigo', 'Індиго', Color(0xFF1A1B2E)),
  ];

  static Color accentById(String id) => accents
      .firstWhere((option) => option.id == id, orElse: () => accents.first)
      .color;

  static Color groundById(String id) => grounds
      .firstWhere((option) => option.id == id, orElse: () => grounds.first)
      .color;

  /// A theme built around one accent and one ground.
  static ThemeData themeFor({
    required Color accent,
    required Color ground,
    bool focusGlow = true,
    double uiScale = 1,
    bool pointer = false,
  }) {
    final scheme = ColorScheme.dark(
      primary: accent,
      onPrimary: ground,
      secondary: accent,
      surface: ground,
      onSurface: text,
      surfaceContainerHighest: _surfaceOn(ground),
      onSurfaceVariant: neutral500,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: ground,
      // Carried on the theme rather than through a provider, so a widget test
      // that renders a tile on its own still gets a sensible default.
      extensions: [
        TvChrome(focusGlow: focusGlow, uiScale: uiScale, pointer: pointer),
      ],
      // Inter is the design's face; a television has no Inter, so this falls
      // through to the platform sans at the same weights.
      fontFamily: 'Inter',
      fontFamilyFallback: const ['Roboto', 'sans-serif'],
      textTheme: const TextTheme(
        displayLarge: TextStyle(fontWeight: FontWeight.w500, color: text),
        headlineLarge: TextStyle(fontWeight: FontWeight.w500, color: text),
        titleLarge: TextStyle(fontWeight: FontWeight.w500, color: text),
        bodyLarge: TextStyle(color: text),
        bodyMedium: TextStyle(color: neutral300),
        labelLarge: TextStyle(color: neutral400, letterSpacing: 0.6),
      ),
    );
  }

  /// Panels sit one step above whatever ground was chosen, so a card still
  /// reads as raised on a pure-black screen as well as on the blue-grey one.
  static Color _surfaceOn(Color ground) =>
      Color.lerp(ground, const Color(0xFFB2B6CA), 0.11)!;
}

/// Chrome the design carries that a `ColorScheme` has no field for.
class TvChrome extends ThemeExtension<TvChrome> {
  const TvChrome({
    required this.focusGlow,
    required this.uiScale,
    required this.pointer,
  });

  /// Whether the focused tile's glow breathes.
  final bool focusGlow;

  /// Multiplies every measurement taken off the design.
  final double uiScale;

  /// Whether a pointer moves focus. Only an air mouse produces one.
  final bool pointer;

  @override
  TvChrome copyWith({bool? focusGlow, double? uiScale, bool? pointer}) =>
      TvChrome(
        focusGlow: focusGlow ?? this.focusGlow,
        uiScale: uiScale ?? this.uiScale,
        pointer: pointer ?? this.pointer,
      );

  @override
  TvChrome lerp(TvChrome? other, double t) => other == null
      ? this
      : TvChrome(
          focusGlow: t < 0.5 ? focusGlow : other.focusGlow,
          uiScale: lerpDouble(uiScale, other.uiScale, t) ?? uiScale,
          pointer: t < 0.5 ? pointer : other.pointer,
        );
}

/// One selectable colour, with the name it goes by in settings.
class PaletteOption {
  const PaletteOption(this.id, this.label, this.color);

  final String id;
  final String label;
  final Color color;
}

/// Maps the design's 1920×1080 measurements onto whatever the television
/// actually reports.
///
/// A 1080p box usually hands Flutter 960×540 logical pixels at a device ratio
/// of 2, so a number taken straight off the artboard would come out twice the
/// size it should be. Everything laid out from the design goes through [px].
extension TvScale on BuildContext {
  /// Logical pixels per design pixel, after the viewer's own scaling factor.
  ///
  /// The panel's width sets the base; the setting on top of it is what makes
  /// the same layout readable from a sofa five metres back.
  double get scale =>
      MediaQuery.sizeOf(this).width /
      1920 *
      (Theme.of(this).extension<TvChrome>()?.uiScale ?? 1);

  /// [design] pixels off the 1920-wide artboard, in logical pixels here.
  double px(double design) => design * scale;

  /// A text size off the artboard.
  double sp(double design) => design * scale;

  /// The margin the design keeps clear of the panel edge. Televisions
  /// overscan; nothing meaningful goes outside this.
  EdgeInsets get safe =>
      EdgeInsets.symmetric(horizontal: px(80), vertical: px(48));
}

/// The chosen colours, and the shades derived from them.
///
/// Derived rather than tabulated: an accent picked in settings has no ramp of
/// its own, and mixing towards the text colour and the ground keeps every
/// shade at the same visual weight whichever hue is chosen.
extension TvPalette on BuildContext {
  ColorScheme get _scheme => Theme.of(this).colorScheme;

  /// The accent at full strength: rings, marks, small caps labels.
  Color get accent => _scheme.primary;

  /// The ground the whole interface sits on.
  Color get ground => _scheme.surface;

  /// Panels and chips.
  Color get surface => _scheme.surfaceContainerHighest;

  /// Text on an accent-tinted fill.
  Color get accentText => Color.lerp(accent, Nocturne.text, 0.62)!;

  /// Paragraph-size text in the accent, lifted for contrast.
  Color get accentSoft => Color.lerp(accent, Nocturne.text, 0.42)!;

  /// A pressed or hovered step past the base.
  Color get accentBright => Color.lerp(accent, Nocturne.text, 0.22)!;

  /// A tinted fill: the accent barely mixed into the ground.
  Color get accentTint => Color.lerp(ground, accent, 0.22)!;

  /// Whether the focused tile's glow breathes. Defaults to on wherever no
  /// theme extension is in scope.
  bool get focusGlow => Theme.of(this).extension<TvChrome>()?.focusGlow ?? true;

  /// Whether a pointer moves focus. Off unless something produces one — a
  /// remote without a gyroscope never will.
  bool get pointer => Theme.of(this).extension<TvChrome>()?.pointer ?? false;
}
