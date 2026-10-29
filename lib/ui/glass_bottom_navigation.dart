import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    show GlassQuality, GlassTab, GlassTabBar;

class AppBottomNavigation extends StatelessWidget {
  const AppBottomNavigation({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  // Scaffold.extendBody includes the measured navigation height in this padding.
  static double contentBottomPadding(BuildContext context) =>
      MediaQuery.paddingOf(context).bottom + 16;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    minimum: const EdgeInsets.only(bottom: 8),
    maintainBottomViewPadding: true,
    child: Padding(
      padding: const EdgeInsets.only(top: 8),
      child: GlassTabBar.bottom(
        tabs: [
          GlassTab(icon: const Icon(Icons.event_note_outlined), label: '待办'),
          GlassTab(icon: const Icon(Icons.people_outline), label: '客户'),
          GlassTab(icon: const Icon(Icons.tune_outlined), label: '我的'),
        ],
        selectedIndex: selectedIndex,
        onTabSelected: onSelected,
        quality: GlassQuality.premium,
        backgroundQuality: GlassQuality.standard,
        barHeight: 64,
        horizontalPadding: 16,
        verticalPadding: 0,
        indicatorBorderRadius: 999,
        indicatorExpansion: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        magnification: 1.12,
        enableBlend: true,
        adaptiveBrightness: true,
      ),
    ),
  );
}
