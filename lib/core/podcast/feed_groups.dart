import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../models/podcast.dart';

/// 播客订阅分组。
///
/// 分组是**筛选维度**，不是嵌套文件夹：一个订阅最多属于一个分组，列表仍然平铺。
/// 分组关系单独存一份 `feedId -> groupId` 映射，**不写进 [PodcastFeed]**，
/// 因此既有订阅数据（`subscribed_podcast_feeds`）与备份格式都不需要迁移。
class FeedGroup {
  const FeedGroup({required this.id, required this.name});

  factory FeedGroup.fromJson(Map<String, dynamic> json) => FeedGroup(
    id: json['id']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
  );

  final String id;
  final String name;

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is FeedGroup && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// 分组的编解码、清洗与筛选。全部是纯逻辑，不依赖 Riverpod 或 SharedPreferences。
abstract final class FeedGroupLogic {
  /// 未分组的哨兵值。存成空串而不是 null，方便放进 Map 序列化。
  static const ungrouped = '';

  /// 筛选器里"显示全部"的取值。
  ///
  /// 刻意**不**复用 [ungrouped]：那里空串表示"这个订阅没归组"，这里空串若也表示
  /// "全部"，两处语义会悄悄串起来。给一个不可能与 UUID 撞上的独立字面量。
  static const allGroups = '__all__';

  /// 分组名最长长度，避免一个名字撑爆筛选行。
  static const maxNameLength = 24;

  static String newId() => const Uuid().v4();

  /// 规范化分组列表：丢空 id / 空名、重名去重、截断过长名字、保持原顺序。
  static List<FeedGroup> sanitize(List<FeedGroup> groups) {
    final seenIds = <String>{};
    final seenNames = <String>{};
    final out = <FeedGroup>[];
    for (final group in groups) {
      final id = group.id.trim();
      final name = group.name.trim();
      if (id.isEmpty || name.isEmpty) continue;
      if (!seenIds.add(id)) continue;
      final short =
          name.length > maxNameLength ? name.substring(0, maxNameLength) : name;
      if (!seenNames.add(short)) continue;
      out.add(FeedGroup(id: id, name: short));
    }
    return out;
  }

  static List<FeedGroup> decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return sanitize([
        for (final item in decoded)
          if (item is Map) FeedGroup.fromJson(Map<String, dynamic>.from(item)),
      ]);
    } catch (_) {
      return const [];
    }
  }

  static String encodeList(List<FeedGroup> groups) =>
      jsonEncode([for (final g in sanitize(groups)) g.toJson()]);

  /// 解析 `feedId -> groupId` 映射。
  ///
  /// **会丢弃指向不存在分组的孤儿项**。这是有意的：备份可能来自旧版本，或用户
  /// 在别的设备上删过分组；留着孤儿会让筛选项指向一个空分组，列表莫名其妙少订阅。
  static Map<String, String> decodeMap(String? raw, List<FeedGroup> groups) {
    if (raw == null || raw.isEmpty) return {};
    final known = {for (final g in groups) g.id};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final out = <String, String>{};
      for (final entry in decoded.entries) {
        final feedId = entry.key.toString();
        final groupId = entry.value?.toString() ?? '';
        if (feedId.isEmpty) continue;
        if (groupId.isEmpty) continue;
        if (!known.contains(groupId)) continue;
        out[feedId] = groupId;
      }
      return out;
    } catch (_) {
      return {};
    }
  }

  static String encodeMap(Map<String, String> map) {
    final cleaned = {
      for (final entry in map.entries)
        if (entry.key.isNotEmpty && entry.value.isNotEmpty)
          entry.key: entry.value,
    };
    return jsonEncode(cleaned);
  }

  /// 删掉一个分组后，映射里指向它的订阅回到未分组。
  static Map<String, String> withoutGroup(Map<String, String> map, String id) {
    final out = <String, String>{};
    for (final entry in map.entries) {
      if (entry.value == id) continue;
      out[entry.key] = entry.value;
    }
    return out;
  }

  /// 删掉一个订阅后，从映射里清掉它，避免留下永远用不到的孤儿键。
  static Map<String, String> withoutFeed(
    Map<String, String> map,
    String feedId,
  ) {
    final out = Map<String, String>.from(map);
    out.remove(feedId);
    return out;
  }

  /// 按分组筛选订阅。
  ///
  /// [groupId] 传 [allGroups] 返回全部；传 [ungrouped]（空串）只返回没归组的订阅。
  /// **判据必须是 `== allGroups` 而不是 `isEmpty`**：`ungrouped` 本身就是空串，
  /// 写成 `groupId.isEmpty` 会把"只看未分组"悄悄变成"看全部"，而 `allGroups`
  /// 反而会掉进过滤分支返回空列表。
  static List<PodcastFeed> filter(
    List<PodcastFeed> feeds,
    Map<String, String> map,
    String groupId,
  ) {
    if (groupId == allGroups) return feeds;
    return [
      for (final feed in feeds)
        if ((map[feed.id] ?? ungrouped) == groupId) feed,
    ];
  }

  /// 每个分组里有多少个订阅，用于筛选行上的计数。
  static Map<String, int> counts(
    List<PodcastFeed> feeds,
    Map<String, String> map,
  ) {
    final out = <String, int>{};
    for (final feed in feeds) {
      final groupId = map[feed.id] ?? ungrouped;
      out[groupId] = (out[groupId] ?? 0) + 1;
    }
    return out;
  }
}
