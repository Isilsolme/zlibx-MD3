import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../../providers/settings_provider.dart';
import '../../../services/glass_support.dart';
import '../../../widgets/liquid_nav_bar.dart';
import 'nav_destinations.dart';

/// The four-destination liquid-glass bar. The host owns the PageController
/// and the current index; this widget only watches the bar's settings.
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
    // Spike: Android 13+ gets the shader-based glass tab bar from
    // liquid_glass_widgets; everywhere else keeps the existing Material
    // bar. The package owns the motion here — the old hand-rolled lens
    // (BackdropFilter + custom painters) is still used on the fallback
    // path only.
    if (GlassSupport.enabled) {
      final destinations = homeDestinations(context);
      final cs = Theme.of(context).colorScheme;
      return GlassTabBar.bottom(
        tabs: <GlassTab>[
          for (final destination in destinations)
            GlassTab(
              icon: Icon(destination.icon),
              activeIcon: Icon(destination.selectedIcon),
              label: destination.label,
              semanticLabel: destination.label,
            ),
        ],
        selectedIndex: selectedIndex,
        onTabSelected: onDestinationSelected,
        // "standard" is the single-pass shader tier: the tab bar sits over
        // scrolling content, which is exactly the case the package
        // recommends standard for. Premium is for static chrome.
        quality: GlassQuality.standard,
        backgroundQuality: GlassQuality.standard,
        maskingQuality: MaskingQuality.high,
        barHeight: 64,
        horizontalPadding: 20,
        verticalPadding: 8,
        iconSize: 23,
        labelFontSize: 11.5,
        selectedIconColor: cs.primary,
        unselectedIconColor: cs.onSurfaceVariant,
        selectedLabelColor: cs.primary,
        unselectedLabelColor: cs.onSurfaceVariant,
        indicatorColor: cs.secondaryContainer,
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
