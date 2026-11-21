import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
        onTabSelected: (index) {
          // The package has no haptics; the old Material bar clicked on
          // every selection and drag settle. Keep parity.
          HapticFeedback.selectionClick();
          onDestinationSelected(index);
        },
        // Premium is the shader path (real Gaussian backdrop sampling);
        // standard is the lightweight approximation that turns blocky on a
        // large blur. The Android 13+ gate is the only downgrade — the
        // package's adaptive quality scope is disabled in main().
        quality: GlassQuality.premium,
        backgroundQuality: GlassQuality.premium,
        // Masking must stay high: the package's "simple" (off) mode draws
        // the whole selected-tab row squeezed into one tab slot, which is
        // the pile of overlapping icons. Ghosting is instead kept down by
        // the thin, non-chromatic lens below.
        maskingQuality: MaskingQuality.high,
        magnification: 1.0,
        indicatorPinchStrength: 0,
        interactionBehavior: GlassInteractionBehavior.none,
        interactionGlowColor: Colors.transparent,
        glowOpacity: 0,
        settings: LiquidGlassSettings(
          glassColor: const Color.fromARGB(10, 255, 255, 255),
          // High gaussian blur; the cost is kept down by removing the
          // frost pass, rim light/shade, glow and chromatic aberration
          // below, not by lowering the blur.
          blur: 24,
          thickness: 6,
          frost: 0,
          lightIntensity: 0.25,
          saturation: 1.1,
          chromaticAberration: 0,
          rimLight: 0,
          rimShade: 0,
          glowIntensity: 0,
          fresnelStrength: 0.2,
          refractiveIndex: 1.06,
          lensModel: GlassLensModel.paraxial,
          shadowElevation: 0.6,
        ),
        indicatorSettings: const LiquidGlassSettings(
          glassColor: Color.fromARGB(0, 255, 255, 255),
          blur: 16,
          // The lens needs a real bevel to bend the icons underneath: at
          // thickness 4 / n 1.05 the displacement is under a pixel, so the
          // pill read as a flat mirror with a colour change. 18dp of bevel
          // at n=1.12 gives ~17px of edge displacement while staying below
          // the paraxial fold threshold (n≈1.125), so no mirrored copy.
          thickness: 18,
          frost: 0,
          lightIntensity: 0.25,
          saturation: 1.05,
          chromaticAberration: 0,
          rimLight: 0,
          rimShade: 0,
          glowIntensity: 0,
          fresnelStrength: 0.2,
          refractiveIndex: 1.12,
          lensModel: GlassLensModel.paraxial,
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
