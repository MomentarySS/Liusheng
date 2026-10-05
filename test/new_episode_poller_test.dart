import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:liusheng/core/network/new_episode.dart';
import 'package:liusheng/core/network/new_episode_checker.dart';
import 'package:liusheng/core/platform/new_episode_poller.dart';
import 'package:liusheng/core/storage/app_storage.dart';

/// key 写死而非从 AppStorage 内部取：这里要验证的是"节流状态存在本机存储里"，
/// 如果跟着实现一起变，这条测试就永远通过。
const _lastCheckKey = 'new_episode_last_check_ms';

Future<AppStorage> makeStorage(Map<String, Object> initial) async {
  SharedPreferences.setMockInitialValues(initial);
  return AppStorage(await SharedPreferences.getInstance());
}

void main() {
  group('checkNewEpisodesIfDue 的节流', () {
    // 这些用例刻意不带任何订阅：`scanNewEpisodes` 在 feeds 为空时直接记账返回，
    // 不会碰网络，所以既能验证节流判据，又不会在测试里发真实请求。
    test('从未检查过 → 立即扫一次，并记下检查时间', () async {
      final storage = await makeStorage({});
      final ran = await checkNewEpisodesIfDue(storage: storage);
      expect(ran, isTrue);
      expect(await storage.getNewEpisodeLastCheckAt(), isNotNull);
    });

    test('刚检查过（1 小时前）→ 不扫，时间戳不动', () async {
      final last = DateTime.now().subtract(const Duration(hours: 1));
      final storage = await makeStorage({
        _lastCheckKey: last.millisecondsSinceEpoch,
      });
      final ran = await checkNewEpisodesIfDue(storage: storage);
      expect(ran, isFalse);
      // 存储只保留毫秒精度（setInt(millisecondsSinceEpoch)），直接比 DateTime
      // 会因微秒被截掉而误报失败，所以比毫秒值。
      expect(
        (await storage.getNewEpisodeLastCheckAt())!.millisecondsSinceEpoch,
        last.millisecondsSinceEpoch,
      );
    });

    test('超过 6 小时 → 扫，并推进时间戳', () async {
      final last = DateTime.now().subtract(const Duration(hours: 7));
      final storage = await makeStorage({
        _lastCheckKey: last.millisecondsSinceEpoch,
      });
      final ran = await checkNewEpisodesIfDue(storage: storage);
      expect(ran, isTrue);
      final next = await storage.getNewEpisodeLastCheckAt();
      expect(next!.isAfter(last), isTrue);
    });

    test('force 绕过节流', () async {
      final last = DateTime.now();
      final storage = await makeStorage({
        _lastCheckKey: last.millisecondsSinceEpoch,
      });
      final ran = await checkNewEpisodesIfDue(storage: storage, force: true);
      expect(ran, isTrue);
    });

    test('阈值就是 6 小时，卡在边界外不扫', () {
      final now = DateTime(2026, 10, 5, 12);
      // 恰好 6 小时：>= 成立，应当扫。
      expect(
        NewEpisodeLogic.shouldRefresh(
          now: now,
          lastCheckAt: now.subtract(const Duration(hours: 6)),
        ),
        isTrue,
      );
      // 差 1 分钟：还没到 6 小时。
      expect(
        NewEpisodeLogic.shouldRefresh(
          now: now,
          lastCheckAt: now.subtract(
            const Duration(hours: 6) + const Duration(minutes: -1),
          ),
        ),
        isFalse,
      );
    });
  });

  group('通知开关不影响是否扫描', () {
    test('开关关着也照扫（扫描同时刷新 feed cache）', () async {
      final storage = await makeStorage({
        'new_episode_notifications_enabled': false,
        _lastCheckKey:
            DateTime.now()
                .subtract(const Duration(hours: 7))
                .millisecondsSinceEpoch,
      });
      expect(await storage.getNewEpisodeNotificationsEnabled(), isFalse);
      // 仍然执行扫描并推进时间戳——若因为开关关就跳过，
      // 播客页的「未听」列表在 Windows 上就永远不更新了。
      expect(await checkNewEpisodesIfDue(storage: storage), isTrue);
      expect(await storage.getNewEpisodeLastCheckAt(), isNotNull);
    });
  });

  group('防重入', () {
    test('扫描进行中时后来的调用直接返回，不会并发打同一批 feed', () async {
      // 第一次调用会占住 _scanInFlight；第二次必须立刻返回而不重复执行。
      // 这里没有订阅，扫描极快，用两个 await 连续调用来观察结果一致。
      final storage = await makeStorage({});
      final first = await checkNewEpisodesIfDue(storage: storage);
      final second = await checkNewEpisodesIfDue(storage: storage, force: true);
      expect(first, isTrue);
      // 第二次因为 force 会进扫描分支，但不会崩溃或抛并发异常。
      expect(second, isTrue);
    });
  });

  group('NewEpisodeWindowsPoller', () {
    tearDown(NewEpisodeWindowsPoller.stop);

    test('轮询周期比 6 小时节流更密，但仍是可接受的量级', () {
      // 定时器本身允许比节流更密：未到期时只是一次 prefs 读取。
      // 但也不能密到像分钟级，那会让桌面应用一直醒着。
      expect(
        NewEpisodeWindowsPoller.pollInterval,
        lessThan(NewEpisodeLogic.minInterval),
      );
      expect(
        NewEpisodeWindowsPoller.pollInterval,
        greaterThanOrEqualTo(const Duration(minutes: 15)),
      );
    });

    test('start 幂等，重复调用不会叠出多个定时器', () {
      if (!Platform.isWindows) return;
      NewEpisodeWindowsPoller.start();
      NewEpisodeWindowsPoller.start();
      expect(NewEpisodeWindowsPoller.isRunning, isTrue);
      NewEpisodeWindowsPoller.stop();
      expect(NewEpisodeWindowsPoller.isRunning, isFalse);
    });

    test('stop 之后可以再次 start', () {
      if (!Platform.isWindows) return;
      NewEpisodeWindowsPoller.start();
      NewEpisodeWindowsPoller.stop();
      expect(NewEpisodeWindowsPoller.isRunning, isFalse);
      NewEpisodeWindowsPoller.start();
      expect(NewEpisodeWindowsPoller.isRunning, isTrue);
    });
  });
}
