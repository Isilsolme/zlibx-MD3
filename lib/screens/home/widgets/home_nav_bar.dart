import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/settings_provider.dart';
import '../../../services/glass_support.dart';
import '../../../widgets/glass_nav_bar.dart';
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
    // Android 13+ can show the shader glass bar; the setting lets the user
    // turn it off and fall back to the opaque Material bar.
    if (GlassSupport.enabled && ref.watch(glassNavEnabledProvider)) {
      return GlassNavBar(
        destinations: homeDestinations(context),
        selectedIndex: selectedIndex,
        onSelected: onDestinationSelected,
        labelMode: ref.watch(navLabelModeProvider),
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
