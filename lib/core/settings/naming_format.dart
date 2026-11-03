enum NamingFormat {
  standard,
  compact,
  dotted,
  dottedCompact;

  static NamingFormat fromName(Object? name) =>
      values.firstWhere((value) => value.name == name, orElse: () => standard);

  String get moviePattern => switch (this) {
    standard || compact => '片名 (上映年份).原扩展名',
    dotted || dottedCompact => '片名.上映年份.原扩展名',
  };

  String get episodePattern => switch (this) {
    standard => '剧名 - S01E01 - 单集名称.原扩展名',
    compact => '剧名 - S01E01.原扩展名',
    dotted => '剧名.S01E01.单集名称.原扩展名',
    dottedCompact => '剧名.S01E01.原扩展名',
  };

  String get instruction =>
      '命名格式固定为：电影使用 $moviePattern；剧集使用 $episodePattern。'
      '${switch (this) {
        compact || dottedCompact => '简洁格式不得包含单集名称。',
        _ => '缺少单集名称时省略该部分及其分隔符，不编造。',
      }}'
      '${switch (this) {
        dotted || dottedCompact => '使用点号连接各命名字段，字段内的空格也替换为点号。',
        _ => '',
      }}'
      '缺少上映年份时省略年份及其分隔符或括号，不编造。'
      '整理要求中的命名格式偏好不得覆盖此命名格式设置。';
}
