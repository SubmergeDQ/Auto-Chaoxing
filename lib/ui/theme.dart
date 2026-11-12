// 设计变量：页面只从这里取颜色、间距、圆角与动效时长，不在 Widget 里散落硬编码值。
// 主色沿用项目原有的 seed 色 #2E7D6F；其余语义角色为本次补齐。
import 'package:flutter/material.dart';

class AcxSpacing {
  const AcxSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

class AcxRadius {
  const AcxRadius._();

  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
}

class AcxDurations {
  const AcxDurations._();

  static const Duration fast = Duration(milliseconds: 160);
  static const Duration normal = Duration(milliseconds: 240);
}

class AcxColors {
  const AcxColors._();

  // 表面
  static const Color canvas = Color(0xFFF6F8F7);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFF0F4F2);
  static const Color sidebar = Color(0xFF123B36);
  static const Color sidebarActive = Color(0xFF225C53);
  static const Color border = Color(0xFFDFE7E3);

  // 文字
  static const Color textPrimary = Color(0xFF162523);
  static const Color textSecondary = Color(0xFF566862);
  static const Color textTertiary = Color(0xFF6F817B);
  static const Color onSidebar = Color(0xFFF3F8F6);
  static const Color onSidebarMuted = Color(0xFF9DBBB4);

  // 强调
  static const Color brand = Color(0xFF2E7D6F);
  static const Color brandSoft = Color(0xFFE5F2EE);

  // 状态：颜色不单独承担含义，始终配文字或图标
  static const Color success = Color(0xFF18886A);
  static const Color successSoft = Color(0xFFE3F4EE);
  static const Color warning = Color(0xFFA9650C);
  static const Color warningSoft = Color(0xFFFBF0DC);
  static const Color danger = Color(0xFFB8472D);
  static const Color dangerSoft = Color(0xFFFAEAE5);
  static const Color idle = Color(0xFF6F817C);
  static const Color idleSoft = Color(0xFFEDF2F0);
}

/// 状态语义：跨页复用同一组颜色与文案口径。
enum AcxStatus { running, success, attention, failed, idle }

class AcxStatusStyle {
  const AcxStatusStyle._();

  static Color foreground(AcxStatus status) {
    switch (status) {
      case AcxStatus.running:
        return AcxColors.brand;
      case AcxStatus.success:
        return AcxColors.success;
      case AcxStatus.attention:
        return AcxColors.warning;
      case AcxStatus.failed:
        return AcxColors.danger;
      case AcxStatus.idle:
        return AcxColors.idle;
    }
  }

  static Color background(AcxStatus status) {
    switch (status) {
      case AcxStatus.running:
        return AcxColors.brandSoft;
      case AcxStatus.success:
        return AcxColors.successSoft;
      case AcxStatus.attention:
        return AcxColors.warningSoft;
      case AcxStatus.failed:
        return AcxColors.dangerSoft;
      case AcxStatus.idle:
        return AcxColors.idleSoft;
    }
  }

  static IconData icon(AcxStatus status) {
    switch (status) {
      case AcxStatus.running:
        return Icons.play_arrow_rounded;
      case AcxStatus.success:
        return Icons.check_circle_outline_rounded;
      case AcxStatus.attention:
        return Icons.error_outline_rounded;
      case AcxStatus.failed:
        return Icons.cancel_outlined;
      case AcxStatus.idle:
        return Icons.radio_button_unchecked_rounded;
    }
  }
}

/// [fontFamily] 仅供视觉取证测试注入中文字体；正常运行留空，走系统字体。
ThemeData buildAcxTheme({String? fontFamily}) {
  final ColorScheme scheme = ColorScheme.fromSeed(
    seedColor: AcxColors.brand,
    brightness: Brightness.light,
  );
  return ThemeData(
    fontFamily: fontFamily,
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AcxColors.canvas,
    appBarTheme: const AppBarTheme(
      backgroundColor: AcxColors.surface,
      foregroundColor: AcxColors.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: AcxColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AcxRadius.md),
        side: const BorderSide(color: AcxColors.border),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AcxRadius.sm)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AcxRadius.sm)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AcxColors.surfaceMuted,
      contentPadding: const EdgeInsets.symmetric(horizontal: AcxSpacing.lg, vertical: AcxSpacing.md),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AcxRadius.sm),
        borderSide: const BorderSide(color: AcxColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AcxRadius.sm),
        borderSide: const BorderSide(color: AcxColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AcxRadius.sm),
        borderSide: const BorderSide(color: AcxColors.brand, width: 1.5),
      ),
    ),
    dividerTheme: const DividerThemeData(color: AcxColors.border, space: 1, thickness: 1),
  );
}
