import 'dart:async';
import 'dart:io';

import '../network/new_episode_checker.dart';
import '../storage/app_storage.dart';

/// Windows 的新一集定期检查。
///
/// Android 靠 `workmanager` 的周期性任务，Windows 没有等价的后台调度，只能靠进程
/// 常驻时的 `Timer.periodic`。前提是应用在跑——托盘常驻即算跑着，这与 Windows 侧
/// "关闭主窗口继续在托盘听"的定位一致。
///
/// 通知能力本身早就通了（`local_notifications.dart` 里 Windows 初始化一直都在），
/// 这里补的只是**触发源**：此前 Windows 上除了用户手动刷新，没有任何路径会调它。
abstract final class NewEpisodeWindowsPoller {
  /// 轮询周期。真正的节流在 `NewEpisodeLogic.minInterval`（6 小时）里，
  /// 所以这里可以取得更密——未到期时只是一次 prefs 读取然后返回，没有任何网络请求。
  ///
  /// 取 1 小时而不是 6 小时：若直接用 6 小时，冷启动时机不对就会多等满 6 小时；
  /// 1 小时把最大延迟压到 1 小时，而空转成本仍然可以忽略。
  static const pollInterval = Duration(hours: 1);

  static Timer? _timer;
  static bool _started = false;

  static bool get isRunning => _timer != null;

  static void start() {
    if (!Platform.isWindows || _started) return;
    _started = true;
    // 先按到期判断跑一次：冷启动时若距上次检查已过 6 小时，不该再干等一小时。
    unawaited(_tick());
    _timer = Timer.periodic(pollInterval, (_) => unawaited(_tick()));
  }

  static void stop() {
    _timer?.cancel();
    _timer = null;
    _started = false;
  }

  static Future<void> _tick() async {
    try {
      final storage = await AppStorage.create();
      await checkNewEpisodesIfDue(storage: storage);
    } catch (_) {
      // 离线、存储不可用、单个 feed 拉取失败都不该让定时器停摆。
      // 下一轮还会再试；`checkNewEpisodesIfDue` 内部有防重入与到期判断。
    }
  }
}
