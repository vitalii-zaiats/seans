/// What sits at the top of the home screen.
enum HomeHero {
  /// The catalogue's own slider: a backdrop, a synopsis and buttons.
  slider('slider', 'Банер', 'Обкладинки з каталогу'),

  /// A clock over slow abstract shapes in the chosen palette. Nothing is
  /// promoted and nothing is fetched.
  clock('clock', 'Годинник', 'Час і кольорові плями, без обкладинок'),

  /// Nothing at all — the rows start at the top.
  none('none', 'Нічого', 'Одразу рядки');

  const HomeHero(this.id, this.title, this.note);

  final String id;
  final String title;
  final String note;

  /// Whether the catalogue's slider has to be fetched at all.
  bool get needsSlider => this == HomeHero.slider;

  static HomeHero fromId(String? id) =>
      values.firstWhere((mode) => mode.id == id, orElse: () => HomeHero.slider);
}
