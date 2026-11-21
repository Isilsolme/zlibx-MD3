import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../models/nav_label_mode.dart';
import 'liquid_nav_bar.dart' show LiquidNavDestination;

/// The liquid-glass bottom bar.
///
/// The glass surface comes from liquid_glass_widgets (one AdaptiveGlass
/// layer, standard quality); the motion and layout are ours, ported from
/// the pre-glass bar so it matches the reference apps:
///
/// * the selection pill tracks the finger 1:1 while dragging and springs
///   to the nearest tab on release;
/// * the bar height never changes with the label mode. With labels off the
///   icon centers in the whole item, exactly like miuix's NavigationBar
///   (IconOnly uses Arrangement.Center over a fixed item height);
/// * with [NavLabelMode.auto] the selected icon animates up and its label
///   fades in, the other icons sit centered — miuix's IconWithSelectedLabel.
///
/// The old implementation re-blurred the backdrop inside the moving lens
/// and repainted the lens every frame; this one has a single glass layer
/// and a cheap painted pill, which is what made it feel laggy before.
class GlassNavBar extends StatefulWidget {
  const GlassNavBar({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    this.labelMode = NavLabelMode.always,
  }) : assert(destinations.length > 1, 'needs at least two destinations');

  final List<LiquidNavDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final NavLabelMode labelMode;

  static const double barHeight = 64;
  static const double horizontalMargin = 20;
  static const double _padH = 4;

  /// Space a scrollable should reserve at the bottom so content clears the
  /// floating bar.
  static double bottomClearance(BuildContext context) {
    final inset = MediaQuery.viewPaddingOf(context).bottom;
    return barHeight + 8 + inset + 16;
  }

  @override
  State<GlassNavBar> createState() => _GlassNavBarState();
}

class _GlassNavBarState extends State<GlassNavBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progress;
  bool _dragging = false;
  Size _barSize = Size.zero;

  int get _count => widget.destinations.length;

  @override
  void initState() {
    super.initState();
    _progress = AnimationController.unbounded(
      vsync: this,
      value: widget.selectedIndex.toDouble(),
    );
  }

  @override
  void didUpdateWidget(covariant GlassNavBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_dragging && oldWidget.selectedIndex != widget.selectedIndex) {
      _springTo(widget.selectedIndex);
    }
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  void _springTo(int index) {
    if (MediaQuery.disableAnimationsOf(context)) {
      _progress.value = index.toDouble();
      return;
    }
    _progress.animateWith(
      SpringSimulation(
        const SpringDescription(mass: 1, stiffness: 520, damping: 40),
        _progress.value,
        index.toDouble(),
        0,
      ),
    );
  }

  double _tabWidth(Size size) => (size.width - GlassNavBar._padH * 2) / _count;

  int _indexAt(Size size, double dx) {
    final tab = _tabWidth(size);
    if (tab <= 0) return 0;
    return ((dx - GlassNavBar._padH) / tab).floor().clamp(0, _count - 1);
  }

  double _continuousAt(Size size, double dx) {
    final tab = _tabWidth(size);
    if (tab <= 0) return 0;
    return ((dx - GlassNavBar._padH) / tab - 0.5)
        .clamp(-0.2, (_count - 1) + 0.2)
        .toDouble();
  }

  void _select(int index) {
    _springTo(index);
    if (index != widget.selectedIndex) widget.onSelected(index);
  }

  void _handleTapUp(TapUpDetails details) {
    if (_barSize.width <= 0) return;
    _select(_indexAt(_barSize, details.localPosition.dx));
  }

  void _handleDragStart(DragStartDetails details) {
    _dragging = true;
    _progress.value = _continuousAt(_barSize, details.localPosition.dx);
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (!_dragging) return;
    // 1:1 with the finger: no spring while the finger is down. This is what
    // "跟手" means here — the old lens eased toward the pointer with a
    // 150 ms spring, which read as input lag.
    _progress.value = _continuousAt(_barSize, details.localPosition.dx);
  }

  void _handleDragEnd() {
    if (!_dragging) return;
    _dragging = false;
    final target = _progress.value.round().clamp(0, _count - 1);
    _springTo(target);
    if (target != widget.selectedIndex) widget.onSelected(target);
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final inset = MediaQuery.viewPaddingOf(context).bottom;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        GlassNavBar.horizontalMargin,
        0,
        GlassNavBar.horizontalMargin,
        8 + inset,
      ),
      child: AdaptiveGlass(
        shape: const LiquidRoundedSuperellipse(borderRadius: 32),
        quality: GlassQuality.standard,
        settings: const LiquidGlassSettings(
          // No opaque MD3 fill: the body is the blurred backdrop plus a
          // faint tint, like NeriPlayer's glass surface. The old bar's
          // surfaceContainer gradient is gone.
          glassColor: Color.fromARGB(10, 255, 255, 255),
          blur: 14,
          thickness: 24,
          lightIntensity: 0.35,
          saturation: 1.25,
          shadowElevation: 0.6,
        ),
        child: SizedBox(
          height: GlassNavBar.barHeight,
          child: LayoutBuilder(
            builder: (context, constraints) {
              _barSize = Size(constraints.maxWidth, GlassNavBar.barHeight);
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: _handleTapUp,
                onHorizontalDragStart: _handleDragStart,
                onHorizontalDragUpdate: _handleDragUpdate,
                onHorizontalDragEnd: (_) => _handleDragEnd(),
                onHorizontalDragCancel: _handleDragEnd,
                child: Stack(
                  children: <Widget>[
                    Positioned.fill(
                      child: IgnorePointer(
                        child: AnimatedBuilder(
                          animation: _progress,
                          builder: (context, _) => CustomPaint(
                            painter: _PillPainter(
                              progress: _progress.value,
                              count: _count,
                              isDark: isDark,
                              reduceMotion: reduceMotion,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: AnimatedBuilder(
                        animation: _progress,
                        builder: (context, _) {
                          final active = _progress.value.round().clamp(
                            0,
                            _count - 1,
                          );
                          return Row(
                            children: <Widget>[
                              for (var i = 0; i < _count; i++)
                                Expanded(
                                  child: _NavItem(
                                    destination: widget.destinations[i],
                                    active: i == active,
                                    labelMode: widget.labelMode,
                                    activeColor: cs.primary,
                                    inactiveColor: cs.onSurfaceVariant,
                                    onTap: () => _select(i),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.destination,
    required this.active,
    required this.labelMode,
    required this.activeColor,
    required this.inactiveColor,
    required this.onTap,
  });

  final LiquidNavDestination destination;
  final bool active;
  final NavLabelMode labelMode;
  final Color activeColor;
  final Color inactiveColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? activeColor : inactiveColor;
    final showLabels = labelMode != NavLabelMode.never;
    final labelVisible =
        labelMode == NavLabelMode.always ||
        (labelMode == NavLabelMode.auto && active);

    // miuix's NavigationBarItem: a fixed-height item, icons top-aligned
    // when a label is present and centered when there is none. In auto
    // mode the selected row moves up and its label fades in; the item
    // height never changes.
    final iconAlignment = !showLabels
        ? Alignment.center
        : (labelMode == NavLabelMode.always || active)
        ? const Alignment(0, -0.45)
        : const Alignment(0, 0.15);

    return Semantics(
      button: true,
      selected: active,
      label: destination.label,
      onTap: onTap,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          AnimatedAlign(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: iconAlignment,
            child: AnimatedScale(
              scale: active ? 1.06 : 1.0,
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutBack,
              child: Icon(
                active ? destination.selectedIcon : destination.icon,
                size: 23,
                color: color,
              ),
            ),
          ),
          if (showLabels)
            Align(
              alignment: const Alignment(0, 0.72),
              child: AnimatedOpacity(
                opacity: labelVisible ? 1 : 0,
                duration: const Duration(milliseconds: 180),
                child: Text(
                  destination.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.1,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    color: color,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PillPainter extends CustomPainter {
  _PillPainter({
    required this.progress,
    required this.count,
    required this.isDark,
    required this.reduceMotion,
  });

  final double progress;
  final int count;
  final bool isDark;
  final bool reduceMotion;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    const padH = GlassNavBar._padH;
    final tab = (size.width - padH * 2) / count;
    final centerX = (padH + (progress + 0.5) * tab)
        .clamp(padH + tab / 2, size.width - padH - tab / 2)
        .toDouble();
    final width = math.max(28.0, tab - 10);
    const height = 48.0;
    final rrect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(centerX, size.height / 2),
        width: width,
        height: height,
      ),
      const Radius.circular(height / 2),
    );
    canvas.drawRRect(
      rrect,
      Paint()..color = Colors.white.withValues(alpha: isDark ? 0.14 : 0.34),
    );
    canvas.drawRRect(
      rrect.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: isDark ? 0.18 : 0.45),
    );
  }

  @override
  bool shouldRepaint(covariant _PillPainter old) =>
      old.progress != progress ||
      old.count != count ||
      old.isDark != isDark ||
      old.reduceMotion != reduceMotion;
}
