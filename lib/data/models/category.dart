/// Whether a category is for money going out or coming in.
enum CategoryKind { expense, income }

/// A spending or income category, with keywords used to guess it.
class Category {
  factory Category.fromMap(Map<String, Object?> m) => Category(
    id: m['id'] as int,
    name: m['name'] as String,
    kind: CategoryKind.values.byName(m['kind'] as String),
    icon: m['icon'] as String,
    color: m['color'] as int,
    keywords: ((m['keywords'] as String?) ?? '').split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList(),
    archived: (m['archived'] as int) == 1,
    sortOrder: m['sort_order'] as int,
  );

  const Category({
    this.id,
    required this.name,
    required this.kind,
    this.icon = '•',
    this.color = 0xFF9E9E9E,
    this.keywords = const [],
    this.archived = false,
    this.sortOrder = 0,
  });

  final int? id;
  final String name;
  final CategoryKind kind;

  /// An emoji shown next to the name.
  final String icon;

  /// ARGB colour used in charts.
  final int color;

  /// Extra words that map to this category in voice and screenshot entry,
  /// e.g. Food: lunch, tea, breakfast. The category name always matches too.
  final List<String> keywords;
  final bool archived;
  final int sortOrder;

  String get label => '$icon $name';

  Category copyWith({
    int? id,
    String? name,
    CategoryKind? kind,
    String? icon,
    int? color,
    List<String>? keywords,
    bool? archived,
    int? sortOrder,
  }) => Category(
    id: id ?? this.id,
    name: name ?? this.name,
    kind: kind ?? this.kind,
    icon: icon ?? this.icon,
    color: color ?? this.color,
    keywords: keywords ?? this.keywords,
    archived: archived ?? this.archived,
    sortOrder: sortOrder ?? this.sortOrder,
  );

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    'name': name,
    'kind': kind.name,
    'icon': icon,
    'color': color,
    'keywords': keywords.join(','),
    'archived': archived ? 1 : 0,
    'sort_order': sortOrder,
  };
}
