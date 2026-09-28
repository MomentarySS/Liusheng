/// 流声新项目的对外品牌与技术身份。版本与 `pubspec.yaml` 的 `x.y.z` 对齐。
abstract final class AppBrand {
  static const displayName = '流声';
  static const englishSlug = 'Liusheng';

  /// 产品描述（"做什么"）：README 顶头、商店副标题用这一条。
  static const tagline = '电台与播客，一处收听';

  /// 品牌口号（"气质是什么"）：关于页用这一条。
  /// 与 [tagline] 并列，不要互相替换 —— 见 PRODUCT.md 的 Brand Commitments。
  static const slogan = '一处收听，随时有声';

  static const version = '2.2.1';
  static const userAgent = 'Liusheng/$version (Flutter; liusheng radio)';
  static const podcastUserAgent = 'Liusheng/$version PodcastReader';
  static const podcastFallbackUserAgent =
      'Mozilla/5.0 (compatible; Liusheng/$version; +rss)';
}
