import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workmanager/workmanager.dart';

import '../models/podcast.dart';
import '../platform/local_notifications.dart';
import '../podcast/feed_cache.dart';
import '../providers/app_providers.dart';
import '../storage/app_storage.dart';
import 'new_episode.dart';
import 'podcast_service.dart';

const newEpisodeWorkName = 'liusheng_new_episode';

final newEpisodeCheckerProvider = Provider<NewEpisodeChecker>((ref) {
  return NewEpisodeChecker(ref);
});

class NewEpisodeChecker {
  NewEpisodeChecker(this._ref);

  final Ref _ref;

  Future<void> checkIfDue({bool force = false}) async {
    final storage = await _ref.read(appStorageProvider.future);
    await checkNewEpisodesIfDue(storage: storage, force: force);
  }

  Future<void> run({required AppStorage storage, bool force = false}) async {
    await runNewEpisodeScan(storage: storage, force: force);
  }

  /// Android 侧注册 / 取消 workmanager 周期任务。
  ///
  /// Windows 上直接返回：那边没有等价的后台调度，由 `NewEpisodeWindowsPoller`
  /// 的常驻定时器负责，设置页会另行启停。
  Future<void> syncBackgroundSchedule({required bool enabled}) async {
    if (!Platform.isAndroid) return;
    try {
      if (enabled) {
        await Workmanager().registerPeriodicTask(
          newEpisodeWorkName,
          newEpisodeWorkName,
          frequency: NewEpisodeLogic.minInterval,
          existingWorkPolicy: ExistingWorkPolicy.keep,
          constraints: Constraints(networkType: NetworkType.connected),
        );
      } else {
        await Workmanager().cancelByUniqueName(newEpisodeWorkName);
      }
    } catch (_) {}
  }
}

/// 扫描防重入。模块级而不是实例级：Windows 的常驻定时器与 Riverpod 侧的手动检查
/// 会各自持有 `NewEpisodeChecker`，共用这一个标志才不会并发打同一批 feed。
var _scanInFlight = false;

/// 跑一次"到期就扫"。不依赖 Riverpod，Windows 的常驻定时器可以直接调。
///
/// 返回是否真的执行了扫描；未到期时返回 false 且不做任何网络请求。
Future<bool> checkNewEpisodesIfDue({
  required AppStorage storage,
  bool force = false,
}) async {
  final due = NewEpisodeLogic.shouldRefresh(
    now: DateTime.now(),
    lastCheckAt: force ? null : await storage.getNewEpisodeLastCheckAt(),
  );
  if (!due) return false;
  await runNewEpisodeScan(storage: storage, force: force);
  return true;
}

/// 扫一轮并按开关决定要不要弹通知。
///
/// 无论开关开不开都会扫：扫描同时刷新 feed cache，播客页的「未听」列表靠它。
/// 这与 Android 上 workmanager 的行为一致，不要因为通知关了就跳过扫描。
Future<void> runNewEpisodeScan({
  required AppStorage storage,
  bool force = false,
}) async {
  if (_scanInFlight) return;
  _scanInFlight = true;
  try {
    final enabled = await storage.getNewEpisodeNotificationsEnabled();
    final hits = await scanNewEpisodes(storage: storage, force: force);
    if (!enabled) return;
    await _notifyUnmuted(storage, hits);
  } finally {
    _scanInFlight = false;
  }
}

Future<void> _notifyUnmuted(
  AppStorage storage,
  List<NewEpisodeHit> hits,
) async {
  final muted = await storage.getMutedNewEpisodeFeedIds();
  for (final hit in hits) {
    if (!NewEpisodeLogic.shouldNotifyFeed(
      globallyEnabled: true,
      muted: muted.contains(hit.feed.id),
    )) {
      continue;
    }
    await showNewEpisodeNotification(hit);
  }
}

Future<List<NewEpisodeHit>> scanNewEpisodes({
  required AppStorage storage,
  PodcastService? service,
  DateTime? now,
  bool force = false,
}) async {
  final raw = await storage.getSubscribedFeeds();
  final feeds = raw.map(PodcastFeed.fromJson).toList();
  final scannedAt = now ?? DateTime.now();
  if (feeds.isEmpty) {
    await storage.setNewEpisodeLastCheckAt(scannedAt);
    return const [];
  }
  final cache = await storage.getFeedCache();
  final toScan = FeedCacheLogic.feedsToRefresh(
    feeds: feeds,
    cache: cache,
    now: scannedAt,
    force: force,
  );
  if (toScan.isEmpty) {
    await storage.setNewEpisodeLastCheckAt(scannedAt);
    return const [];
  }
  final lastGuids = await storage.getNewEpisodeLastGuids();
  final nextGuids = Map<String, String>.from(lastGuids);
  final hits = <NewEpisodeHit>[];
  final client = service ?? PodcastService();
  final keepIds = {for (final feed in feeds) feed.id};
  for (final feed in toScan) {
    try {
      final detail = await client.fetchFeed(feed);
      final snapshot = FeedCacheLogic.snapshotFromDetail(
        detail,
        fetchedAt: scannedAt,
      );
      final latest = await storage.getFeedCache();
      latest[feed.id] = snapshot;
      latest.removeWhere((id, _) => !keepIds.contains(id));
      await storage.setFeedCache(latest);
      final newest = NewEpisodeLogic.newestEpisode(detail.episodes);
      if (newest == null) continue;
      final hit = NewEpisodeLogic.detect(
        feed: feed,
        episodes: detail.episodes,
        lastGuids: lastGuids,
      );
      if (hit != null) hits.add(hit);
      nextGuids[feed.id] = newest.guid;
    } catch (_) {}
  }
  await storage.setNewEpisodeLastGuids(nextGuids);
  await storage.setNewEpisodeLastCheckAt(scannedAt);
  return hits;
}

@pragma('vm:entry-point')
void newEpisodeCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      final storage = await AppStorage.create();
      final enabled = await storage.getNewEpisodeNotificationsEnabled();
      if (!NewEpisodeLogic.shouldCheck(
        enabled: enabled,
        now: DateTime.now(),
        lastCheckAt: await storage.getNewEpisodeLastCheckAt(),
      )) {
        return true;
      }
      final hits = await scanNewEpisodes(storage: storage);
      await _notifyUnmuted(storage, hits);
    } catch (_) {}
    return true;
  });
}
