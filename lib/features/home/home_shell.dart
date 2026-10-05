import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/podcast_download.dart';
import '../../core/network/new_episode_checker.dart';
import '../../core/platform/desk_tray_sync.dart';
import '../../core/platform/desk_widget_sync.dart';
import '../../core/platform/notification_permission.dart';
import '../../core/providers/app_providers.dart';
import '../../core/platform/desk_window_mode.dart';
import '../../core/theme.dart';
import '../../shared/widgets/desk_mini_bar.dart';
import '../../shared/widgets/desk_sidebar_window.dart';
import '../../shared/widgets/mini_player.dart';
import '../../shared/widgets/now_playing_route.dart';
import '../../shared/widgets/offline_banner.dart';
import '../../shared/widgets/shake_sleep_listener.dart';
import '../listening/listening_screen.dart';
import '../podcast/podcast_providers.dart';
import '../podcast/podcast_screen.dart';
import '../radio/radio_providers.dart';
import '../radio/radio_screen.dart';
import '../radio/station_catalog_setup_screen.dart';
import '../settings/settings_screen.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;
  late final List<Widget?> _pages = <Widget?>[
    const RadioScreen(),
    null,
    null,
    null,
  ];

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      await requestPlaybackNotificationPermission();
      if (!mounted) return;
      final storage = await ref.read(appStorageProvider.future);
      if (!await storage.getStationCatalogConfigured() && mounted) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            fullscreenDialog: true,
            builder: (_) => const StationCatalogSetupScreen(firstLaunch: true),
          ),
        );
      }
      if (!mounted) return;
      await ref.read(playerControllerProvider).restoreLastSession();
      if (!mounted) return;
      await handleDeskWidgetLaunch(ref);
      if (!mounted) return;
      await ref.read(newEpisodeCheckerProvider).checkIfDue();
      if (!mounted) return;
      await ref.read(feedCacheProvider.notifier).reload();
    });
  }

  static const _destinations = [
    NavigationDestination(
      icon: Icon(Icons.radio_outlined),
      selectedIcon: Icon(Icons.radio),
      label: '电台',
    ),
    NavigationDestination(
      icon: Icon(Icons.podcasts_outlined),
      selectedIcon: Icon(Icons.podcasts),
      label: '播客',
    ),
    NavigationDestination(
      icon: Icon(Icons.headphones_outlined),
      selectedIcon: Icon(Icons.headphones),
      label: '收听',
    ),
    NavigationDestination(
      icon: Icon(Icons.settings_outlined),
      selectedIcon: Icon(Icons.settings),
      label: '设置',
    ),
  ];

  Widget _pageFor(int index) => switch (index) {
    0 => const RadioScreen(),
    1 => const PodcastScreen(),
    2 => const ListeningScreen(),
    _ => const SettingsScreen(),
  };

  void _selectPage(int index) {
    if (_pages[index] == null) {
      _pages[index] = _pageFor(index);
    }
    setState(() => _index = index);
  }

  /// 已经为哪个紧凑形态退回过根路由。用来避免每次 build 都排一次 pop。
  DeskWindowMode? _poppedToRootFor;

  /// 浮条 / 侧栏是**换壳**不是加层。
  ///
  /// 设置子页（`settings_screen.dart`）、Now Playing、底部弹窗都是 push 到
  /// `HomeShell` **之上**的路由，而切窗口形态只改窗口尺寸、不动导航栈
  /// （`DeskWindowModeNotifier.setMode` 只写存储 + 调 `DeskWindow.apply`）。
  /// 于是那条路由会原样留在 456x100 的浮窗上、把迷你条盖掉——表现就是
  /// 「浮窗第一次显示的是设置页，点一次返回才变回迷你条」。
  ///
  /// 放在 build 里而不是 `ref.listen`：[下方] 渲染迷你条用的就是这个
  /// `ref.watch(deskWindowModeProvider)`。build 跑不到，迷你条也出不来，
  /// 两者必然同时发生，不会出现「壳换了但栈没清」的中间态。
  ///
  /// 两个紧凑壳自身都不 push 路由（`desk_mini_bar.dart` /
  /// `desk_sidebar_window.dart` 均无 Navigator 调用），所以这里退回根
  /// 不会误伤任何合法导航。
  void _resetNavigationToRoot(DeskWindowMode mode) {
    if (_poppedToRootFor == mode) return;
    _poppedToRootFor = mode;
    // 路由不能在 build 里直接动，挪到本帧之后。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final navigator = Navigator.of(context);
      if (navigator.canPop()) {
        navigator.popUntil((route) => route.isFirst);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(sleepTimerProvider, (previous, next) {
      if (next.stoppedByTimer) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已按定时停止播放')));
      }
    });
    ref.listen(podcastDownloadsProvider, (previous, next) {
      if (!PodcastDownloadLogic.shouldShowFailureNotice(
        previousSeq: previous?.failureSeq,
        nextSeq: next.failureSeq,
        title: next.lastFailureTitle,
      )) {
        return;
      }
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('「${next.lastFailureTitle}」下载失败')),
      );
    });
    ref.listen(isOfflineProvider, (previous, next) {
      final wasOffline = previous?.value ?? false;
      final offline = next.value ?? false;
      if (wasOffline && !offline) {
        ref.read(stationsProvider.notifier).reload();
      }
    });

    ref.watch(autoBrowseSyncProvider);
    ref.watch(podcastQueueSyncProvider);
    ref.watch(autoDownloadLatestSyncProvider);
    ref.watch(podcastCatalogPrewarmProvider);
    ref.watch(deskWidgetSyncProvider);
    ref.watch(deskTraySyncProvider);
    ref.watch(deskLaunchAtStartupProvider);
    ref.watch(podcastSkipStepProvider);
    ref.watch(lastSleepValueProvider);
    final deskWindowMode =
        ref.watch(deskWindowModeProvider).value ?? DeskWindowMode.main;
    // 离开紧凑形态必须清标记，否则「浮条 → 完整窗口 → 再切回浮条」这一轮
    // 会被上一轮留下的 `_poppedToRootFor == miniBar` 挡掉，导航栈就再也
    // 回不去 —— 表现是 bug 看起来"只坏一次"，改完第一次就好了、第二次照旧。
    if (deskWindowMode == DeskWindowMode.main) {
      _poppedToRootFor = null;
    }
    final useRail =
        MediaQuery.sizeOf(context).width >= LiushengTheme.railBreakpoint;

    void openNowPlaying() {
      Navigator.of(context).push(NowPlayingPageRoute());
    }

    final body = SafeArea(
      bottom: false,
      child: Column(
        children: [
          const OfflineBanner(),
          Expanded(
            child: IndexedStack(
              index: _index,
              children: [
                for (final page in _pages) page ?? const SizedBox.shrink(),
              ],
            ),
          ),
          MiniPlayer(
            onExpand: openNowPlaying,
            enableSwipe: Platform.isAndroid && !useRail,
          ),
        ],
      ),
    );

    if (deskWindowMode == DeskWindowMode.miniBar) {
      _resetNavigationToRoot(DeskWindowMode.miniBar);
      return ShakeSleepListener(
        child: Material(
          type: MaterialType.transparency,
          child: DeskMiniBar(
            onExit:
                () => ref
                    .read(deskWindowModeProvider.notifier)
                    .setMode(DeskWindowMode.main),
            onSidebar:
                () => ref
                    .read(deskWindowModeProvider.notifier)
                    .setMode(DeskWindowMode.sidebar),
          ),
        ),
      );
    }

    if (deskWindowMode == DeskWindowMode.sidebar) {
      _resetNavigationToRoot(DeskWindowMode.sidebar);
      return const DeskSidebarKeyboardNavigation(child: DeskSidebarWindow());
    }

    if (useRail) {
      return ShakeSleepListener(
        child: Scaffold(
          backgroundColor: Theme.of(context).colorScheme.surface,
          body: Row(
            children: [
              NavigationRail(
                selectedIndex: _index,
                onDestinationSelected: _selectPage,
                labelType: NavigationRailLabelType.all,
                destinations:
                    _destinations
                        .map(
                          (item) => NavigationRailDestination(
                            icon: item.icon,
                            selectedIcon: item.selectedIcon,
                            label: Text(item.label),
                          ),
                        )
                        .toList(),
              ),
              const VerticalDivider(width: 1),
              Expanded(child: body),
            ],
          ),
        ),
      );
    }

    return ShakeSleepListener(
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        body: body,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: _selectPage,
          destinations: _destinations,
        ),
      ),
    );
  }
}
