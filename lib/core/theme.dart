import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme/app_skin.dart';

export 'theme/app_skin.dart';

/// 外观：跟随系统 / 浅色 / 深色。旧版开关会把「关」写成浅色，从此不再跟系统。
abstract final class ThemeModeLogic {
  static ThemeMode parse(String? raw) => switch (raw) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };

  static String persist(ThemeMode mode) => switch (mode) {
    ThemeMode.light => 'light',
    ThemeMode.dark => 'dark',
    ThemeMode.system => 'system',
  };

  static String label(ThemeMode mode) => switch (mode) {
    ThemeMode.system => '跟随系统',
    ThemeMode.light => '浅色',
    ThemeMode.dark => '深色',
  };

  static String subtitle(ThemeMode mode) => switch (mode) {
    ThemeMode.system => '与系统浅色、深色同步',
    ThemeMode.light => '始终使用浅色',
    ThemeMode.dark => '始终使用深色',
  };
}

/// 列表密度：只作用在电台 / 单集 `ListTile`，不改全局 `ThemeData.visualDensity`。
abstract final class ListDensityLogic {
  static const defaultCompact = false;

  static VisualDensity visualDensity({required bool compact}) =>
      compact ? VisualDensity.compact : VisualDensity.standard;

  static String subtitle({required bool compact}) =>
      compact ? '电台和单集行更密；底栏、芯片和设置不变' : '标准行距；只压电台和单集列表，不压底栏';
}

/// 壁纸 / 系统强调色 → ColorScheme。没有平台色时退回流声蓝种子。
abstract final class DynamicThemeLogic {
  /// 浅色生成策略：`vibrant`。
  ///
  /// Material 默认的 `tonalSpot` 会把种子压成低 chroma 的 `#405F90`，品牌蓝在界面上
  /// 基本看不见；`vibrant` 生成的 `#005DB7` 最接近流声蓝种子 `#1565C0`。
  /// 不能选 `expressive`（变绿 `#3A6931`）或 `fruitSalad`（变青 `#006876`）——
  /// 那会把品牌从蓝变成别的色相。
  static const lightVariant = DynamicSchemeVariant.vibrant;

  /// 深色保留 Material 默认的 `tonalSpot`，**不要**跟着换成 `vibrant`。
  ///
  /// 实测（`docs/color-scheme-cards.png`）：`vibrant` 在深色下 `primary` 仍是
  /// `#A9C7FF`，`onPrimary` 是深蓝 `#003063`——颜色本身没问题（早期记录的
  /// "深绿 #003D03" 不成立），但换过去没有收益：深色 `primary` 本来就是清晰的
  /// 浅蓝，不存在浅色那种"品牌蓝不可见"，保留 `tonalSpot` 改动最小。
  static const darkVariant = DynamicSchemeVariant.tonalSpot;

  static DynamicSchemeVariant variantFor(Brightness brightness) =>
      brightness == Brightness.dark ? darkVariant : lightVariant;

  static ColorScheme fallback({required Brightness brightness}) {
    return ColorScheme.fromSeed(
      seedColor: LiushengTheme.seed,
      brightness: brightness,
      dynamicSchemeVariant: variantFor(brightness),
    );
  }

  static ColorScheme resolve({
    required Brightness brightness,
    required bool enabled,
    ColorScheme? platformScheme,
    Color? accent,
  }) {
    if (!enabled) return fallback(brightness: brightness);
    if (platformScheme != null && platformScheme.brightness == brightness) {
      return platformScheme;
    }
    if (accent != null && isUsableAccent(accent)) {
      // 与品牌种子共用同一个 variant：用户选系统强调色时也要鲜明，
      // 否则会出现"品牌色 vivid、系统色发灰"的分裂感。
      return ColorScheme.fromSeed(
        seedColor: accent,
        brightness: brightness,
        dynamicSchemeVariant: variantFor(brightness),
      );
    }
    return fallback(brightness: brightness);
  }

  static bool isUsableAccent(Color color) {
    final r = (color.r * 255).round();
    final g = (color.g * 255).round();
    final b = (color.b * 255).round();
    if (r < 8 && g < 8 && b < 8) return false;
    if (r > 247 && g > 247 && b > 247) return false;
    return true;
  }
}

/// 流声 Material 3 主题。默认种子是流声蓝；Android 12+ 可改用壁纸配色。
abstract final class LiushengTheme {
  static const seed = Color(0xFF1565C0);
  static const railBreakpoint = 900.0;
  static const listBottomPadding = 16.0;

  static ThemeData light({ColorScheme? scheme}) => _build(
    scheme ?? DynamicThemeLogic.fallback(brightness: Brightness.light),
  );

  static ThemeData dark({ColorScheme? scheme}) =>
      _build(scheme ?? DynamicThemeLogic.fallback(brightness: Brightness.dark));

  static SystemUiOverlayStyle overlayFor(Brightness brightness, Color surface) {
    final lightIcons = brightness == Brightness.dark;
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: lightIcons ? Brightness.light : Brightness.dark,
      statusBarBrightness: lightIcons ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: surface,
      systemNavigationBarIconBrightness:
          lightIcons ? Brightness.light : Brightness.dark,
    );
  }

  static ThemeData _build(ColorScheme scheme) {
    final brightness = scheme.brightness;

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      visualDensity: VisualDensity.standard,
      textTheme: _textTheme(brightness),
      extensions: const [LiushengSkinTheme()],
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(shape: const StadiumBorder()),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(shape: const StadiumBorder()),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(shape: const StadiumBorder()),
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        scrolledUnderElevation: 0,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        systemOverlayStyle: overlayFor(brightness, scheme.surface),
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        backgroundColor: scheme.surface,
        indicatorColor: scheme.secondaryContainer,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 24,
            color:
                selected
                    ? scheme.onSecondaryContainer
                    : scheme.onSurfaceVariant,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
          );
        }),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.secondaryContainer,
        selectedIconTheme: IconThemeData(color: scheme.onSecondaryContainer),
        unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
        selectedLabelTextStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
        unselectedLabelTextStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: scheme.onSurfaceVariant,
        ),
      ),
      listTileTheme: ListTileThemeData(
        selectedTileColor: scheme.primaryContainer.withValues(alpha: 0.55),
        textColor: scheme.onSurface,
        iconColor: scheme.onSurfaceVariant,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
        border: const OutlineInputBorder(),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
      ),
      chipTheme: ChipThemeData(
        selectedColor: scheme.secondaryContainer,
        checkmarkColor: scheme.onSecondaryContainer,
        backgroundColor: scheme.surface,
        labelStyle: TextStyle(color: scheme.onSurface),
        secondaryLabelStyle: TextStyle(color: scheme.onSecondaryContainer),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        space: 1,
        thickness: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: TextStyle(color: scheme.onInverseSurface),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        dragHandleColor: scheme.onSurface.withValues(alpha: 0.25),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary),
    );
  }

  /// 把 `DESIGN.md` 的 typography scale 钉进 `ThemeData.textTheme`。
  ///
  /// 之前 `ThemeData` 完全没有 `textTheme`，排版 scale 只存在于设计文档里，没有任何
  /// 强制力。这里显式写全每个角色的字号、字重与行高比，不依赖 Material 默认值。
  ///
  /// **不能只基于 `Typography.material2021()` 的角色做 `copyWith`**：Material 3 把
  /// 早期版本下沉的字号与字重从角色样式里移走了，那些角色只带 `color` / `family` /
  /// `decoration`，`fontSize` 是 null。只补 `fontWeight` 会得到"看起来设置了、其实字号
  /// 一个都没落"的假实现。
  ///
  /// 行高用 `DESIGN.md` 的比例：headline 1.33、title 1.5、body 1.43、label 1.33。
  /// `DESIGN.md` 声明本系统不使用 Display 角色，因此不覆盖 `display*`。
  static TextTheme _textTheme(Brightness brightness) {
    final base =
        brightness == Brightness.dark
            ? Typography.material2021().white
            : Typography.material2021().black;
    TextStyle role(
      double size,
      FontWeight weight,
      double height, [
      double? spacing,
    ]) => TextStyle(
      fontSize: size,
      fontWeight: weight,
      height: height,
      letterSpacing: spacing,
    );
    return base.copyWith(
      // headline：24px w700，Now Playing 台名与睡眠倒计时，App 内最大的字。
      headlineSmall: role(24, FontWeight.w700, 1.33),
      // titleLarge 22 用于分区头；titleMedium / titleSmall 走 16 与 14，均 w600。
      titleLarge: role(22, FontWeight.w400, 1.27),
      titleMedium: role(16, FontWeight.w600, 1.5),
      titleSmall: role(14, FontWeight.w600, 1.43),
      // body：16 / 14 / 12 三档，信息密度主力，w400。
      bodyLarge: role(16, FontWeight.w400, 1.5),
      bodyMedium: role(14, FontWeight.w400, 1.43),
      bodySmall: role(12, FontWeight.w400, 1.33),
      // label：labelLarge 14 w600 用于设置分组标题与倒计时；
      // labelMedium 12 w500 带 0.4px 字距；labelSmall 11 用于迷你条紧凑倒计时。
      labelLarge: role(14, FontWeight.w600, 1.43),
      labelMedium: role(12, FontWeight.w500, 1.33, 0.4),
      labelSmall: role(11, FontWeight.w500, 1.45),
    );
  }
}
