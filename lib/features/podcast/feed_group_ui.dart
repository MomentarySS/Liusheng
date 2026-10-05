import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/podcast.dart';
import '../../core/podcast/feed_groups.dart';
import 'podcast_providers.dart';

/// 播客页的分组筛选行：全部 + 各分组（带订阅数）+ 管理入口。
///
/// 没有分组时整行不渲染，所以用户不建分组时界面与改动前完全一致。
class FeedGroupFilterBar extends ConsumerWidget {
  const FeedGroupFilterBar({super.key, required this.feeds});

  final List<PodcastFeed> feeds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(feedGroupsProvider).valueOrNull;
    if (data == null || data.isEmpty) return const SizedBox.shrink();

    final filter = ref.watch(resolvedGroupFilterProvider);
    final counts = data.counts(feeds);
    final ungroupedCount = counts[FeedGroupLogic.ungrouped] ?? 0;

    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          _chip(
            context,
            label: '全部 ${feeds.length}',
            selected: filter == FeedGroupLogic.allGroups,
            onSelected:
                () =>
                    ref.read(podcastGroupFilterProvider.notifier).state =
                        FeedGroupLogic.allGroups,
          ),
          for (final group in data.groups)
            _chip(
              context,
              label: '${group.name} ${counts[group.id] ?? 0}',
              selected: filter == group.id,
              onSelected:
                  () =>
                      ref.read(podcastGroupFilterProvider.notifier).state =
                          group.id,
            ),
          if (ungroupedCount > 0)
            _chip(
              context,
              label: '未分组 $ungroupedCount',
              selected: filter == FeedGroupLogic.ungrouped,
              onSelected:
                  () =>
                      ref.read(podcastGroupFilterProvider.notifier).state =
                          FeedGroupLogic.ungrouped,
            ),
          ActionChip(
            avatar: const Icon(Icons.folder_outlined, size: 18),
            label: const Text('管理'),
            onPressed: () => showFeedGroupsSheet(context),
          ),
        ],
      ),
    );
  }

  Widget _chip(
    BuildContext context, {
    required String label,
    required bool selected,
    required VoidCallback onSelected,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onSelected(),
      ),
    );
  }
}

/// 「管理分组」底部 sheet。
Future<void> showFeedGroupsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => const _FeedGroupsSheet(),
  );
}

class _FeedGroupsSheet extends ConsumerWidget {
  const _FeedGroupsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(feedGroupsProvider).valueOrNull;
    final feeds =
        ref.watch(subscribedFeedsProvider).valueOrNull ?? const <PodcastFeed>[];
    final counts = data == null ? const <String, int>{} : data.counts(feeds);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('分组', style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                TextButton(
                  onPressed: () => _createGroup(context, ref),
                  child: const Text('新建分组'),
                ),
              ],
            ),
            Text(
              '一个订阅属于一个分组；删分组不会删订阅。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (data == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (data.groups.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    '还没有分组',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final group in data.groups)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(group.name),
                        subtitle: Text('${counts[group.id] ?? 0} 个订阅'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: '重命名',
                              icon: const Icon(Icons.edit_outlined),
                              onPressed:
                                  () => _renameGroup(context, ref, group),
                            ),
                            IconButton(
                              tooltip: '删除',
                              icon: const Icon(Icons.delete_outline),
                              onPressed:
                                  () => _deleteGroup(context, ref, group),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _createGroup(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('新建分组'),
            content: TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(hintText: '例如：新闻'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(controller.text),
                child: const Text('创建'),
              ),
            ],
          ),
    );
    controller.dispose();
    if (name == null || !context.mounted) return;
    final created = await ref
        .read(feedGroupsProvider.notifier)
        .createGroup(name);
    if (created == null && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('分组名为空或与已有分组重名')));
    }
  }

  Future<void> _renameGroup(
    BuildContext context,
    WidgetRef ref,
    FeedGroup group,
  ) async {
    final controller = TextEditingController(text: group.name);
    final name = await showDialog<String>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('重命名分组'),
            content: TextField(controller: controller, autofocus: true),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(controller.text),
                child: const Text('保存'),
              ),
            ],
          ),
    );
    controller.dispose();
    if (name == null || !context.mounted) return;
    await ref.read(feedGroupsProvider.notifier).renameGroup(group.id, name);
  }

  Future<void> _deleteGroup(
    BuildContext context,
    WidgetRef ref,
    FeedGroup group,
  ) async {
    final notifier = ref.read(feedGroupsProvider.notifier);
    final feeds =
        ref.read(subscribedFeedsProvider).valueOrNull ?? const <PodcastFeed>[];
    final data = ref.read(feedGroupsProvider).valueOrNull;
    final affected = data == null ? 0 : data.counts(feeds)[group.id] ?? 0;
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text('删除「${group.name}」？'),
            content: Text(
              affected == 0
                  ? '这个分组是空的，删除后不影响任何订阅。'
                  : '这 $affected 个订阅会回到「未分组」，不会被删除。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('删除'),
              ),
            ],
          ),
    );
    if (ok != true || !context.mounted) return;
    await notifier.deleteGroup(group.id);
  }
}

/// 「移动到分组」底部 sheet。长按订阅时从菜单调起。
Future<void> showFeedGroupPicker(
  BuildContext context,
  WidgetRef ref,
  PodcastFeed feed,
) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (context) => _FeedGroupPicker(feed: feed),
  );
}

class _FeedGroupPicker extends ConsumerWidget {
  const _FeedGroupPicker({required this.feed});

  final PodcastFeed feed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(feedGroupsProvider).valueOrNull;
    final notifier = ref.read(feedGroupsProvider.notifier);
    final current = data?.map[feed.id] ?? FeedGroupLogic.ungrouped;

    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          const SizedBox(height: 8),
          ListTile(
            title: Text(
              '移动「${feed.title}」',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text('当前：${data?.groupName(current) ?? '未分组'}'),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.inbox_outlined),
            title: const Text('未分组'),
            trailing:
                current == FeedGroupLogic.ungrouped
                    ? const Icon(Icons.check)
                    : null,
            onTap: () async {
              await notifier.assignFeed(feed.id, FeedGroupLogic.ungrouped);
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
          for (final group in data?.groups ?? const <FeedGroup>[])
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: Text(group.name),
              trailing: current == group.id ? const Icon(Icons.check) : null,
              onTap: () async {
                await notifier.assignFeed(feed.id, group.id);
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.create_new_folder_outlined),
            title: const Text('新建分组…'),
            onTap: () async {
              final created = await _promptNewGroup(context, ref);
              if (created == null) return;
              await notifier.assignFeed(feed.id, created);
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }

  Future<String?> _promptNewGroup(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('新建分组'),
            content: TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(hintText: '例如：科技'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(controller.text),
                child: const Text('创建'),
              ),
            ],
          ),
    );
    controller.dispose();
    if (name == null) return null;
    final created = await ref
        .read(feedGroupsProvider.notifier)
        .createGroup(name);
    return created?.id;
  }
}
