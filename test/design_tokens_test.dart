// 锁定 `DESIGN.md` 的设计 token 落地状态。
//
// 背景：审计发现 `ThemeData` 完全没有 `textTheme`，排版 scale 只存在于设计文档里，
// 没有任何强制力；品牌种子则被 `ColorScheme.fromSeed` 的默认 tonalSpot 压成低 chroma。
// 这些断言的作用是：token 一旦被无意改动，这里立刻红，而不是等到肉眼评审才发现。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liusheng/core/theme.dart';

String hex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

void main() {
  group('品牌种子与生成色', () {
    test('种子是流声蓝', () {
      expect(LiushengTheme.seed, const Color(0xFF1565C0));
    });

    test('浅色用 vibrant、深色保留 tonalSpot', () {
      // tonalSpot 会把种子 #1565C0 压成 #405F90，浅色品牌蓝不可见。
      expect(DynamicThemeLogic.lightVariant, DynamicSchemeVariant.vibrant);
      // 深色必须留在 tonalSpot：vibrant 的 onPrimary 是深绿。
      expect(DynamicThemeLogic.darkVariant, DynamicSchemeVariant.tonalSpot);
      expect(
        DynamicThemeLogic.variantFor(Brightness.light),
        DynamicSchemeVariant.vibrant,
      );
      expect(
        DynamicThemeLogic.variantFor(Brightness.dark),
        DynamicSchemeVariant.tonalSpot,
      );
    });

    test('浅色 primary 锁定 vibrant 取值', () {
      final scheme = DynamicThemeLogic.fallback(brightness: Brightness.light);
      expect(hex(scheme.primary), '#005DB7');
    });

    test('浅色 primary 保持蓝色相，没有被 expressive / fruitSalad 换掉', () {
      final scheme = DynamicThemeLogic.fallback(brightness: Brightness.light);
      // expressive 的 #3A6931 约 114°（绿），fruitSalad 的 #006876 约 187°（青），
      // 流声蓝种子 #1565C0 约 209°。只比 RGB 分量排不掉青色，必须比色相。
      final hue = HSVColor.fromColor(scheme.primary).hue;
      expect(hue, greaterThan(195));
      expect(hue, lessThan(225));
    });

    test('深色 primary 保持 #A9C7FF', () {
      final scheme = DynamicThemeLogic.fallback(brightness: Brightness.dark);
      expect(hex(scheme.primary), '#A9C7FF');
    });

    test('深色播放键图标不会变绿（onPrimary 回归防护）', () {
      final scheme = DynamicThemeLogic.fallback(brightness: Brightness.dark);
      // DESIGN.md 规定主播放键用 primary + onPrimary。深色下若跟着换 vibrant，
      // onPrimary 会从深蓝 #08305F 变成深绿 #003D03，播放键图标就变绿了。
      expect(hex(scheme.onPrimary), '#08305F');
      final hue = HSVColor.fromColor(scheme.onPrimary).hue;
      expect(hue, greaterThan(190));
      expect(hue, lessThan(230));
    });

    test('不可用的系统强调色退回种子色', () {
      // 纯黑与纯白都不能当种子，否则会生成一套无色相的主题。
      expect(
        DynamicThemeLogic.isUsableAccent(const Color(0xFF000000)),
        isFalse,
      );
      expect(
        DynamicThemeLogic.isUsableAccent(const Color(0xFFFFFFFF)),
        isFalse,
      );
      expect(DynamicThemeLogic.isUsableAccent(LiushengTheme.seed), isTrue);
    });
  });

  group('typography scale 已落地', () {
    // DESIGN.md typography 段：headline 24 w700 / title 16 w600 /
    // body 14 w400 / label 12 w500 letterSpacing 0.4。
    test('浅色下每个角色的字号与字重符合 DESIGN.md', () {
      final t = LiushengTheme.light().textTheme;
      expect(t.headlineSmall?.fontSize, 24);
      expect(t.headlineSmall?.fontWeight, FontWeight.w700);
      expect(t.titleLarge?.fontSize, 22);
      expect(t.titleMedium?.fontSize, 16);
      expect(t.titleMedium?.fontWeight, FontWeight.w600);
      expect(t.titleSmall?.fontSize, 14);
      expect(t.titleSmall?.fontWeight, FontWeight.w600);
      expect(t.bodyLarge?.fontSize, 16);
      expect(t.bodyMedium?.fontSize, 14);
      expect(t.bodySmall?.fontSize, 12);
      expect(t.labelLarge?.fontSize, 14);
      expect(t.labelLarge?.fontWeight, FontWeight.w600);
      expect(t.labelMedium?.fontSize, 12);
      expect(t.labelMedium?.fontWeight, FontWeight.w500);
      expect(t.labelMedium?.letterSpacing, 0.4);
      expect(t.labelSmall?.fontSize, 11);
    });

    test('深色下 scale 与浅色一致，只是颜色相反', () {
      final light = LiushengTheme.light().textTheme;
      final dark = LiushengTheme.dark().textTheme;
      expect(dark.headlineSmall?.fontSize, light.headlineSmall?.fontSize);
      expect(dark.headlineSmall?.fontWeight, light.headlineSmall?.fontWeight);
      expect(dark.titleMedium?.fontSize, light.titleMedium?.fontSize);
      expect(dark.titleMedium?.fontWeight, light.titleMedium?.fontWeight);
      expect(dark.titleSmall?.fontWeight, light.titleSmall?.fontWeight);
      expect(dark.bodyMedium?.fontSize, light.bodyMedium?.fontSize);
      expect(dark.labelLarge?.fontWeight, light.labelLarge?.fontWeight);
      expect(dark.labelMedium?.letterSpacing, light.labelMedium?.letterSpacing);
    });

    test('本系统不使用 Display 角色，不被本次落地改动', () {
      // DESIGN.md 声明 Display 角色不使用；这里只保证 display* 仍可安全取用，
      // 避免 theme 被判 null 导致调用方崩溃。
      final t = LiushengTheme.light().textTheme;
      expect(t.displaySmall, isNotNull);
    });
  });

  group('形状与结构 token', () {
    test('按钮是体育场形，卡片 12，对话框 28，芯片 8', () {
      final light = LiushengTheme.light();
      expect(
        (light.filledButtonTheme.style?.shape?.resolve({}) as StadiumBorder?),
        isNotNull,
      );
      expect(
        (light.cardTheme.shape as RoundedRectangleBorder).borderRadius,
        BorderRadius.circular(12),
      );
      expect(
        (light.dialogTheme.shape as RoundedRectangleBorder).borderRadius,
        BorderRadius.circular(28),
      );
      expect(
        (light.chipTheme.shape as RoundedRectangleBorder).borderRadius,
        BorderRadius.circular(8),
      );
    });

    test('列表底边 16 与 900px 断点', () {
      expect(LiushengTheme.listBottomPadding, 16.0);
      expect(LiushengTheme.railBreakpoint, 900.0);
    });
  });
}
