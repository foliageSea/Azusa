enum DirectorySort {
  nameAscending,
  nameDescending,
  modifiedDescending,
  modifiedAscending,
  sizeDescending,
  sizeAscending;

  static DirectorySort fromName(Object? name) => values.firstWhere(
    (value) => value.name == name,
    orElse: () => nameAscending,
  );
}
