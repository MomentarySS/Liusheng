import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:liusheng/core/models/podcast.dart';
import 'package:liusheng/core/podcast/feed_groups.dart';
import 'package:liusheng/core/providers/app_providers.dart';
import 'package:liusheng/core/storage/app_storage.dart';
import 'package:liusheng/core/storage/device_backup.dart';
import 'package:liusheng/features/podcast/feed_group_providers.dart';

PodcastFeed feed(String id) =>
    PodcastFeed(id: id, title: '节目 $id', feedUrl: 'https://x/$id.xml');

void main() {
  const news = FeedGroup(id: 'g-news', name: '新闻');
  const tech = FeedGroup(id: 'g-tech', name: '科技');

  group('FeedGroupLogic.sanitize', () {
    test('丢掉空 id 与空名', () {
      final out = FeedGroupLogic.sanitize([
        const FeedGroup(id: '', name: '无 id'),
        const FeedGroup(id: 'g1', name: '   '),
        const FeedGroup(id: 'g2', name: '正常'),
      ]);
      expect(out.map((g) => g.id), ['g2']);
    });

    test('重名只留第一个，重 id 也只留一个', () {
      final out = FeedGroupLogic.sanitize([
        const FeedGroup(id: 'g1', name: '新闻'),
        const FeedGroup(id: 'g1', name: '新闻'),
        const FeedGroup(id: 'g2', name: '新闻'),
        const FeedGroup(id: 'g3', name: '科技'),
      ]);
      expect(out.map((g) => g.id), ['g1', 'g3']);
    });

    test('超长名字被截断', () {
      final long = 'x' * 40;
      final out = FeedGroupLogic.sanitize([FeedGroup(id: 'g1', name: long)]);
      expect(out.single.name.length, FeedGroupLogic.maxNameLength);
    });
  });

  group('映射的孤儿清理', () {
    test('decodeMap 丢掉指向不存在分组的项', () {
      // 备份可能来自删过分组的旧设备；留着孤儿会让筛选指向一个空分组。
      final map = FeedGroupLogic.decodeMap(
        '{"f1":"g-news","f2":"g-gone","f3":"g-tech","f4":""}',
        [news, tech],
      );
      expect(map, {'f1': 'g-news', 'f3': 'g-tech'});
    });

    test('decodeMap 遇到坏 JSON 返回空表而不是抛', () {
      expect(FeedGroupLogic.decodeMap('not json', [news]), isEmpty);
      expect(FeedGroupLogic.decodeMap(null, [news]), isEmpty);
    });

    test('删订阅会清掉它留下的孤儿键', () {
      final map = {'f1': 'g-news', 'f2': 'g-news'};
      final pruned = FeedGroupLogic.withoutFeed(map, 'f1');
      expect(pruned.containsKey('f1'), isFalse);
      expect(pruned['f2'], 'g-news');
    });
  });

  group('删分组不影响订阅', () {
    test('删分组后订阅回到未分组，且仍在列表里', () {
      final feeds = [feed('f1'), feed('f2')];
      final map = {'f1': 'g-news'};

      final after = FeedGroupLogic.withoutGroup(map, 'g-news');
      expect(after.containsKey('f1'), isFalse);

      // 关键语义：删分组不是删订阅，f1 必须还能被看到。
      final all = FeedGroupLogic.filter(feeds, after, FeedGroupLogic.allGroups);
      expect(all.length, 2);
      final ungrouped = FeedGroupLogic.filter(
        feeds,
        after,
        FeedGroupLogic.ungrouped,
      );
      expect(ungrouped.map((f) => f.id), ['f1', 'f2']);
    });
  });

  group('筛选', () {
    final feeds = [feed('f1'), feed('f2'), feed('f3')];
    final map = {'f1': 'g-news', 'f2': 'g-news', 'f3': 'g-tech'};

    test('allGroups 返回全部', () {
      expect(
        FeedGroupLogic.filter(feeds, map, FeedGroupLogic.allGroups).length,
        3,
      );
    });

    test('具体分组只返回该组', () {
      expect(FeedGroupLogic.filter(feeds, map, 'g-news').map((f) => f.id), [
        'f1',
        'f2',
      ]);
    });

    test('ungrouped 只返回没有归组的', () {
      final mixed = {'f1': 'g-news', 'f3': 'g-tech'};
      expect(
        FeedGroupLogic.filter(
          feeds,
          mixed,
          FeedGroupLogic.ungrouped,
        ).map((f) => f.id),
        ['f2'],
      );
    });

    test('counts 覆盖各分组与未分组', () {
      final mixed = {'f1': 'g-news'};
      expect(FeedGroupLogic.counts(feeds, mixed), {
        'g-news': 1,
        FeedGroupLogic.ungrouped: 2,
      });
    });

    test('allGroups 与 ungrouped 是不同的值，不会串', () {
      expect(FeedGroupLogic.allGroups, isNot(FeedGroupLogic.ungrouped));
    });
  });

  group('设备备份自动纳入', () {
    test('两个分组 key 不在排除名单里', () {
      expect(DeviceBackupLogic.includeKey('podcast_feed_groups_json'), isTrue);
      expect(
        DeviceBackupLogic.includeKey('podcast_feed_group_map_json'),
        isTrue,
      );
    });

    test('导出的备份里带得上分组与映射', () {
      final raw = DeviceBackupLogic.encode(
        prefs: {
          'podcast_feed_groups_json': FeedGroupLogic.encodeList([news, tech]),
          'podcast_feed_group_map_json': FeedGroupLogic.encodeMap({
            'f1': 'g-news',
          }),
        },
        podcastState: const {},
        exportedAt: DateTime.utc(2026, 10, 5),
        appVersion: '2.2.2',
      );
      final decoded = DeviceBackupLogic.decode(raw);
      expect(decoded.isOk, isTrue);
      final restored = decoded.backup!.prefs;
      expect(restored.containsKey('podcast_feed_groups_json'), isTrue);
      expect(
        FeedGroupLogic.decodeList(
          restored['podcast_feed_groups_json']!.value as String,
        ).map((g) => g.name),
        ['新闻', '科技'],
      );
      expect(
        FeedGroupLogic.decodeMap(
          restored['podcast_feed_group_map_json']!.value as String,
          [news, tech],
        ),
        {'f1': 'g-news'},
      );
    });
  });

  group('FeedGroupsNotifier', () {
    /// StateNotifierProvider 没有 `.future`（那是 FutureProvider 的 API），
    /// 所以先看当前 state，还没就绪再等 stream 里第一帧有值的广播。
    Future<FeedGroupState> loaded(ProviderContainer container) async {
      final current = container.read(feedGroupsProvider);
      if (current.hasValue) return current.value!;
      final next = await container
          .read(feedGroupsProvider.notifier)
          .stream
          .firstWhere((state) => state.hasValue);
      return next.value!;
    }

    Future<ProviderContainer> makeContainer() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          appStorageProvider.overrideWith((ref) async => AppStorage(prefs)),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('新建 / 重名拒绝 / 重命名', () async {
      final container = await makeContainer();
      final notifier = container.read(feedGroupsProvider.notifier);
      await loaded(container);

      final a = await notifier.createGroup('新闻');
      expect(a, isNotNull);
      expect(await notifier.createGroup('新闻'), isNull);
      expect(await notifier.createGroup('  '), isNull);

      await notifier.renameGroup(a!.id, '时事');
      final groups = container.read(feedGroupsProvider).value!.groups;
      expect(groups.single.name, '时事');
    });

    test('删分组把订阅放回未分组，而不是丢订阅', () async {
      final container = await makeContainer();
      final notifier = container.read(feedGroupsProvider.notifier);
      await loaded(container);

      final group = (await notifier.createGroup('新闻'))!;
      await notifier.assignFeed('f1', group.id);
      expect(container.read(feedGroupsProvider).value!.map['f1'], group.id);

      await notifier.deleteGroup(group.id);
      final data = container.read(feedGroupsProvider).value!;
      expect(data.groups, isEmpty);
      expect(data.map.containsKey('f1'), isFalse);
      // 订阅本身没被动过，映射里只是不再有它。
      expect(
        FeedGroupLogic.filter(
          [feed('f1')],
          data.map,
          FeedGroupLogic.allGroups,
        ).length,
        1,
      );
    });

    test('assignFeed 拒绝不存在的分组，并能把订阅移出分组', () async {
      final container = await makeContainer();
      final notifier = container.read(feedGroupsProvider.notifier);
      await loaded(container);

      await notifier.assignFeed('f1', 'g-gone');
      expect(container.read(feedGroupsProvider).value!.map, isEmpty);

      final group = (await notifier.createGroup('科技'))!;
      await notifier.assignFeed('f1', group.id);
      expect(container.read(feedGroupsProvider).value!.map['f1'], group.id);

      await notifier.assignFeed('f1', FeedGroupLogic.ungrouped);
      expect(
        container.read(feedGroupsProvider).value!.map.containsKey('f1'),
        isFalse,
      );
    });

    test('pruneFeed 清掉被删订阅留下的孤儿键', () async {
      final container = await makeContainer();
      final notifier = container.read(feedGroupsProvider.notifier);
      await loaded(container);

      final group = (await notifier.createGroup('新闻'))!;
      await notifier.assignFeed('f1', group.id);
      await notifier.assignFeed('f2', group.id);

      await notifier.pruneFeed('f1');
      expect(container.read(feedGroupsProvider).value!.map, {'f2': group.id});
    });

    test('分组写进本机存储，重建 container 后还在', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      ProviderContainer make() => ProviderContainer(
        overrides: [
          appStorageProvider.overrideWith((ref) async => AppStorage(prefs)),
        ],
      );

      final first = make();
      final notifier = first.read(feedGroupsProvider.notifier);
      await loaded(first);
      final group = (await notifier.createGroup('新闻'))!;
      await notifier.assignFeed('f1', group.id);
      first.dispose();

      final second = make();
      addTearDown(second.dispose);
      final restored = await loaded(second);
      expect(restored.groups.single.name, '新闻');
      expect(restored.map['f1'], group.id);
    });
  });
}
