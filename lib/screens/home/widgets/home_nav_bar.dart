import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../../models/nav_label_mode.dart';
import '../../../providers/settings_provider.dart';
import '../../../services/glass_support.dart';
import '../../../widgets/liquid_nav_bar.dart';
import 'nav_destinations.dart';

/// The four-destination navigation bar: the package's shader glass bar on
/// supported devices, the opaque Material bar everywhere else.
class HomeNavBar extends ConsumerWidget {
  const HomeNavBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.pageController,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final PageController pageController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final glassOn = GlassSupport.enabled && ref.watch(glassNavEnabledProvider);
    if (glassOn) {
      final destinations = homeDestinations(context);
      final cs = Theme.of(context).colorScheme;
      final isDark = Theme.of(context).brightness == Brightness.dark;
      final labelMode = ref.watch(navLabelModeProvider);
      return GlassTabBar.bottom(
        tabs: <GlassTab>[
          for (var i = 0; i < destinations.length; i++)
            GlassTab(
              icon: Icon(destinations[i].icon),
              activeIcon: Icon(destinations[i].selectedIcon),
              // Same mapping as miuix's NavigationBarDisplayMode: the
              // package centers an icon-only item, and an item with a label
              // keeps icon+label as one centered group. Fixed barHeight
              // means the bar never changes size between modes.
              label: switch (labelMode) {
                NavLabelMode.always => destinations[i].label,
                NavLabelMode.auto =>
                  i == selectedIndex ? destinations[i].label : null,
                NavLabelMode.never => null,
              },
              semanticLabel: destinations[i].label,
            ),
        ],
        selectedIndex: selectedIndex,
        onTabSelected: onDestinationSelected,
        quality: GlassQuality.standard,
        backgroundQuality: GlassQuality.standard,
        // One pass, but keep the tint to a translucent white so the bar
        // reads as glass instead of a Material surface.
        settings: LiquidGlassSettings(
          glassColor: const Color.fromARGB(8, 255, 255, 255),
          blur: 14,
          thickness: 24,
          lightIntensity: 0.35,
          saturation: 1.3,
          shadowElevation: 0.6,
        ),
        indicatorSettings: const LiquidGlassSettings(
          glassColor: Color.fromARGB(0, 255, 255, 255),
          blur: 6,
          thickness: 18,
          lightIntensity: 0.4,
        ),
        indicatorColor: Colors.white.withValues(alpha: isDark ? 0.10 : 0.18),
        barHeight: 64,
        horizontalPadding: 20,
        verticalPadding: 8,
        iconSize: 23,
        labelFontSize: 11.5,
        selectedIconColor: cs.primary,
        unselectedIconColor: cs.onSurfaceVariant,
        selectedLabelColor: cs.primary,
        unselectedLabelColor: cs.onSurfaceVariant,
        interactionGlowColor: cs.primary,
      );
    }

    final blurEnabled = ref.watch(blurEnabledProvider);
    final floatingNav = ref.watch(floatingNavProvider);
    final hideNavOnScroll = ref.watch(hideNavOnScrollProvider);
    final navVisible = ref.watch(navBarVisibleProvider);
    final labelMode = ref.watch(navLabelModeProvider);
    final hideEnabled = floatingNav && hideNavOnScroll;

    return LiquidNavBar(
      destinations: homeDestinations(context),
      selectedIndex: selectedIndex,
      onSelected: onDestinationSelected,
      pageController: pageController,
      blurEnabled: blurEnabled,
      floating: floatingNav,
      labelMode: labelMode,
      visible: !hideEnabled || navVisible,
    );
  }
}
