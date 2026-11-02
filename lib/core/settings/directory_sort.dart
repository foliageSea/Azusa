enum DirectorySort {
  nameAscending,
  nameDescending,
  modifiedDescending,
  modifiedAscending,
  sizeDescending,
  sizeAscending;

  bool get ascending => switch (this) {
    nameAscending || modifiedAscending || sizeAscending => true,
    _ => false,
  };

  DirectorySort get reversed => switch (this) {
    nameAscending => nameDescending,
    nameDescending => nameAscending,
    modifiedAscending => modifiedDescending,
    modifiedDescending => modifiedAscending,
    sizeAscending => sizeDescending,
    sizeDescending => sizeAscending,
  };

  bool sameField(DirectorySort other) => this == other || reversed == other;

  static DirectorySort fromName(Object? name) => values.firstWhere(
    (value) => value.name == name,
    orElse: () => nameAscending,
  );
}
