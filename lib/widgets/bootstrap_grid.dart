// lib/widgets/bootstrap_grid.dart
import 'package:flutter/material.dart';

/// ═══════════════════════════════════════════════════════════════
/// BOOTSTRAP BREAKPOINTS (Standard Bootstrap 5)
/// ═══════════════════════════════════════════════════════════════
class BsBreakpoints {
  static const double xs  = 0;      // Extra small (phone portrait)
  static const double sm  = 576;    // Small (phone landscape)
  static const double md  = 768;    // Medium (tablet)
  static const double lg  = 992;    // Large (desktop)
  static const double xl  = 1200;   // Extra large
  static const double xxl = 1400;   // Extra extra large

  const BsBreakpoints._();
}

enum BsSize { xs, sm, md, lg, xl, xxl }

/// ═══════════════════════════════════════════════════════════════
/// GET CURRENT BREAKPOINT FROM CONTEXT
/// ═══════════════════════════════════════════════════════════════
class BsResponsive {
  final double width;

  const BsResponsive(this.width);

  factory BsResponsive.of(BuildContext context) {
    return BsResponsive(MediaQuery.of(context).size.width);
  }

  BsSize get size {
    if (width >= BsBreakpoints.xxl) return BsSize.xxl;
    if (width >= BsBreakpoints.xl)  return BsSize.xl;
    if (width >= BsBreakpoints.lg)  return BsSize.lg;
    if (width >= BsBreakpoints.md)  return BsSize.md;
    if (width >= BsBreakpoints.sm)  return BsSize.sm;
    return BsSize.xs;
  }

  bool get isXs => width < BsBreakpoints.sm;
  bool get isSm => width >= BsBreakpoints.sm && width < BsBreakpoints.md;
  bool get isMd => width >= BsBreakpoints.md && width < BsBreakpoints.lg;
  bool get isLg => width >= BsBreakpoints.lg && width < BsBreakpoints.xl;
  bool get isXl => width >= BsBreakpoints.xl && width < BsBreakpoints.xxl;
  bool get isXxl => width >= BsBreakpoints.xxl;

  /// Bootstrap-style: `up('md')` returns true if width >= 768
  bool up(BsSize breakpoint) {
    switch (breakpoint) {
      case BsSize.xs:  return width >= BsBreakpoints.xs;
      case BsSize.sm:  return width >= BsBreakpoints.sm;
      case BsSize.md:  return width >= BsBreakpoints.md;
      case BsSize.lg:  return width >= BsBreakpoints.lg;
      case BsSize.xl:  return width >= BsBreakpoints.xl;
      case BsSize.xxl: return width >= BsBreakpoints.xxl;
    }
  }

  /// Bootstrap-style: `down('md')` returns true if width < 768
  bool down(BsSize breakpoint) => !up(breakpoint);

  /// Get responsive value based on current size
  T responsive<T>({
    required T xs,
    T? sm,
    T? md,
    T? lg,
    T? xl,
    T? xxl,
  }) {
    if (isXxl) return xxl ?? xl ?? lg ?? md ?? sm ?? xs;
    if (isXl)  return xl ?? lg ?? md ?? sm ?? xs;
    if (isLg)  return lg ?? md ?? sm ?? xs;
    if (isMd)  return md ?? sm ?? xs;
    if (isSm)  return sm ?? xs;
    return xs;
  }
}

/// ═══════════════════════════════════════════════════════════════
/// BOOTSTRAP-STYLE GRID — 12 columns
/// ═══════════════════════════════════════════════════════════════

/// Container with max-width like Bootstrap's `.container`
class BsContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final double? maxWidth;

  const BsContainer({
    super.key,
    required this.child,
    this.padding,
    this.maxWidth,
  });

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: padding ??
          const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: child,
    );

    if (maxWidth == null) return content;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth!),
        child: content,
      ),
    );
  }
}

/// Bootstrap-style Row — like `.row`
class BsRow extends StatelessWidget {
  final List<Widget> children;
  final double gutter;

  const BsRow({
    super.key,
    required this.children,
    this.gutter = 16,
  });

  @override
  Widget build(BuildContext context) {
    // Insert spacing between children
    final spaced = <Widget>[];
    for (int i = 0; i < children.length; i++) {
      spaced.add(children[i]);
      if (i < children.length - 1) {
        spaced.add(SizedBox(width: gutter));
      }
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: spaced.map((w) => w is SizedBox ? w : Expanded(child: w)).toList(),
    );
  }
}

/// Bootstrap-style grid with automatic wrapping based on screen size
///
/// Example:
/// ```dart
/// BsGrid(
///   xs: 1,  // 1 column on phone
///   sm: 2,  // 2 columns on phone landscape
///   md: 3,  // 3 columns on tablet
///   lg: 4,  // 4 columns on desktop
///   spacing: 16,
///   children: [card1, card2, card3, card4],
/// )
/// ```
class BsGrid extends StatelessWidget {
  final List<Widget> children;
  final int xs;
  final int? sm;
  final int? md;
  final int? lg;
  final int? xl;
  final int? xxl;
  final double spacing;
  final double? childAspectRatio;

  const BsGrid({
    super.key,
    required this.children,
    this.xs = 1,
    this.sm,
    this.md,
    this.lg,
    this.xl,
    this.xxl,
    this.spacing = 16,
    this.childAspectRatio,
  });

  int _cols(BsSize size) {
    switch (size) {
      case BsSize.xxl: return xxl ?? xl ?? lg ?? md ?? sm ?? xs;
      case BsSize.xl:  return xl ?? lg ?? md ?? sm ?? xs;
      case BsSize.lg:  return lg ?? md ?? sm ?? xs;
      case BsSize.md:  return md ?? sm ?? xs;
      case BsSize.sm:  return sm ?? xs;
      case BsSize.xs:  return xs;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final responsive = BsResponsive(constraints.maxWidth);
        final cols = _cols(responsive.size);

        // Auto-calculate aspect ratio if not provided
        double aspect = childAspectRatio ?? 1.0;
        if (childAspectRatio == null) {
          // Wide screens get wider cards
          if (cols >= 4) aspect = 1.9;
          else if (cols == 3) aspect = 1.6;
          else if (cols == 2) aspect = 1.5;
          else aspect = 1.2;
        }

        return GridView.count(
          crossAxisCount: cols,
          crossAxisSpacing: spacing,
          mainAxisSpacing: spacing,
          childAspectRatio: aspect,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: children,
        );
      },
    );
  }
}

/// Bootstrap-style column — like `.col-md-6`
/// Specify how many columns (out of 12) this widget should take at each breakpoint.
///
/// Example: `BsCol(md: 6, lg: 4)` = 6/12 cols on md, 4/12 on lg
class BsCol extends StatelessWidget {
  final Widget child;
  final int? xs;
  final int? sm;
  final int? md;
  final int? lg;
  final int? xl;
  final int? xxl;

  const BsCol({
    super.key,
    required this.child,
    this.xs,
    this.sm,
    this.md,
    this.lg,
    this.xl,
    this.xxl,
  });

  int _cols(BsSize size) {
    switch (size) {
      case BsSize.xxl: return xxl ?? xl ?? lg ?? md ?? sm ?? xs ?? 12;
      case BsSize.xl:  return xl ?? lg ?? md ?? sm ?? xs ?? 12;
      case BsSize.lg:  return lg ?? md ?? sm ?? xs ?? 12;
      case BsSize.md:  return md ?? sm ?? xs ?? 12;
      case BsSize.sm:  return sm ?? xs ?? 12;
      case BsSize.xs:  return xs ?? 12;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final responsive = BsResponsive(constraints.maxWidth);
        final cols = _cols(responsive.size);
        final width = constraints.maxWidth * cols / 12;
        return SizedBox(
          width: width,
          child: child,
        );
      },
    );
  }
}

/// ═══════════════════════════════════════════════════════════════
/// RESPONSIVE WRAP — auto-stacks on small screens
/// ═══════════════════════════════════════════════════════════════
class BsResponsiveRow extends StatelessWidget {
  final List<Widget> children;
  final double spacing;
  final BsSize stackBelow;

  const BsResponsiveRow({
    super.key,
    required this.children,
    this.spacing = 16,
    this.stackBelow = BsSize.md,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final responsive = BsResponsive(constraints.maxWidth);
        final stack = !responsive.up(stackBelow);

        if (stack) {
          // Stack vertically
          final spaced = <Widget>[];
          for (int i = 0; i < children.length; i++) {
            spaced.add(children[i]);
            if (i < children.length - 1) {
              spaced.add(SizedBox(height: spacing));
            }
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: spaced,
          );
        }

        // Side by side with custom flex
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int i = 0; i < children.length; i++) ...[
              Expanded(
                child: children[i],
              ),
              if (i < children.length - 1) SizedBox(width: spacing),
            ],
          ],
        );
      },
    );
  }
}