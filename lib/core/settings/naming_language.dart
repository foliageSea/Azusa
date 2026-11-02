enum NamingLanguage {
  simplifiedChinese('zh-CN', '简体中文'),
  english('en-US', 'English');

  const NamingLanguage(this.code, this.label);

  final String code;
  final String label;

  static NamingLanguage fromCode(Object? code) => values.firstWhere(
    (language) => language.code == code,
    orElse: () => simplifiedChinese,
  );
}
