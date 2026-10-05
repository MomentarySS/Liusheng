import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/podcast.dart';
import '../../core/podcast/feed_groups.dart';
import '../../core/providers/app_providers.dart';

/// 分组定义与 `feedId -> groupId` 映射的合并状态。
///
/// 两者必须原子更新：删一个分组要同时把指向它的订阅放回未分组，所以不拆成两个
/// provider，否则中间态会让筛选行显示出一个不存在的分组。
class FeedGroupState {
  const FeedGroupState({required this.groups, required this.map});

  const FeedGroupState.empty() : groups = const [], map = const {};

  final List<FeedGroup> groups;
  final Map<String, String> map;

  bool get isEmpty => groups.isEmpty;

  /// 按当前筛选的分组过滤。传 [FeedGroupLogic.allGroups] 表示"全部"。
  List<PodcastFeed> filter(List<PodcastFeed> feeds, String groupId) =>
      FeedGroupLogic.filter(feeds, map, groupId);

  /// 各分组的订阅数（含未分组），给筛选行显示计数。
  Map<String, int> counts(List<PodcastFeed> feeds) =>
      FeedGroupLogic.counts(feeds, map);

  String groupName(String groupId) {
    if (groupId.isEmpty) return '未分组';
    for (final group in groups) {
      if (group.id == groupId) return group.name;
    }
    return '未分组';
  }
}

final feedGroupsProvider =
    StateNotifierProvider<FeedGroupsNotifier, AsyncValue<FeedGroupState>>((
      ref,
    ) {
      return FeedGroupsNotifier(ref);
    });

/// 播客页当前选中的分组筛选。默认"全部"。
///
/// 分组被删除时若正好选中它，筛选行会回落到"全部"，避免指着一个不存在的分组。
final podcastGroupFilterProvider = StateProvider<String>(
  (ref) => FeedGroupLogic.allGroups,
);

/// 当前生效的分组筛选。
///
/// 纯派生，**不写 state**。选中的分组被删掉（或从备份恢复后不存在）时，这里直接回落到
/// "全部"，避免筛选指向一个空分组把列表卡成空的。曾想在这里 `scheduleMicrotask` 复位
/// `podcastGroupFilterProvider`，但 provider 内没有 `ref.mounted`，且 provider 里写另一个
/// provider 是反模式——纯派生拿不到同样的效果却更简单。
final resolvedGroupFilterProvider = Provider<String>((ref) {
  final selected = ref.watch(podcastGroupFilterProvider);
  if (selected == FeedGroupLogic.allGroups) return selected;
  final data = ref.watch(feedGroupsProvider).valueOrNull;
  if (data == null) return selected;
  if (data.isEmpty || data.groups.any((g) => g.id == selected)) {
    return selected;
  }
  return FeedGroupLogic.allGroups;
});

/// 播客订阅分组管理。
///
/// 刻意独立于 `SubscribedFeedsNotifier`：分组是叠加在订阅之上的筛选维度，
/// 不进 `PodcastFeed` 也不进 `subscribed_podcast_feeds`，所以旧数据与旧备份
/// 不需要迁移，删掉所有分组就能回到改动前的行为。
class FeedGroupsNotifier extends StateNotifier<AsyncValue<FeedGroupState>> {
  FeedGroupsNotifier(this._ref) : super(const AsyncLoading()) {
    _load();
  }

  final Ref _ref;

  Future<void> _load() async {
    final storage = await _ref.read(appStorageProvider.future);
    final groups = await storage.getFeedGroups();
    final map = await storage.getFeedGroupMap(groups);
    state = AsyncData(FeedGroupState(groups: groups, map: map));
  }

  /// 取出当前数据；未加载完成时按空处理，避免调用方各处判空。
  FeedGroupState _data() => state.valueOrNull ?? const FeedGroupState.empty();

  Future<void> _persist(FeedGroupState next) async {
    state = AsyncData(next);
    final storage = await _ref.read(appStorageProvider.future);
    await storage.setFeedGroups(next.groups);
    await storage.setFeedGroupMap(next.map);
  }

  /// 新建分组。空名与重名会被 [FeedGroupLogic.sanitize] 丢掉。
  Future<FeedGroup?> createGroup(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return null;
    final current = _data();
    if (current.groups.any((g) => g.name == trimmed)) return null;
    final group = FeedGroup(id: FeedGroupLogic.newId(), name: trimmed);
    await _persist(
      FeedGroupState(groups: [...current.groups, group], map: current.map),
    );
    return group;
  }

  Future<void> renameGroup(String id, String name) async {
    final current = _data();
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    if (current.groups.any((g) => g.id != id && g.name == trimmed)) return;
    final next = [
      for (final group in current.groups)
        if (group.id == id) FeedGroup(id: id, name: trimmed) else group,
    ];
    await _persist(FeedGroupState(groups: next, map: current.map));
  }

  /// 删分组。指向它的订阅回到未分组，不会被删掉也不会被隐藏。
  Future<void> deleteGroup(String id) async {
    final current = _data();
    if (!current.groups.any((g) => g.id == id)) return;
    await _persist(
      FeedGroupState(
        groups: [
          for (final group in current.groups)
            if (group.id != id) group,
        ],
        map: FeedGroupLogic.withoutGroup(current.map, id),
      ),
    );
  }

  /// 移动订阅。[groupId] 传 [FeedGroupLogic.ungrouped] 表示移出分组。
  Future<void> assignFeed(String feedId, String groupId) async {
    if (feedId.isEmpty) return;
    final current = _data();
    if (groupId.isNotEmpty && !current.groups.any((g) => g.id == groupId)) {
      return;
    }
    final next = Map<String, String>.from(current.map);
    if (groupId.isEmpty) {
      next.remove(feedId);
    } else {
      next[feedId] = groupId;
    }
    await _persist(FeedGroupState(groups: current.groups, map: next));
  }

  /// 删订阅后清掉映射里的孤儿键。由 `SubscribedFeedsNotifier.removeFeed` 调用。
  Future<void> pruneFeed(String feedId) async {
    final current = _data();
    if (!current.map.containsKey(feedId)) return;
    await _persist(
      FeedGroupState(
        groups: current.groups,
        map: FeedGroupLogic.withoutFeed(current.map, feedId),
      ),
    );
  }
}
