// lib/widgets/skeleton_loader.dart
import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════════
// 🎨 SKELETON COLORS
// ═══════════════════════════════════════════════════════════════
class SkeletonColors {
  static Color base(BuildContext ctx) {
    final isDark = Theme.of(ctx).brightness == Brightness.dark;
    return isDark ? const Color(0xFF27272A) : const Color(0xFFE5E7EB);
  }

  static Color highlight(BuildContext ctx) {
    final isDark = Theme.of(ctx).brightness == Brightness.dark;
    return isDark ? const Color(0xFF3F3F46) : const Color(0xFFF3F4F6);
  }

  static Color border(BuildContext ctx) {
    final isDark = Theme.of(ctx).brightness == Brightness.dark;
    return isDark ? const Color(0xFF3F3F46) : const Color(0xFFD1D5DB);
  }

  static Color bg(BuildContext ctx) {
    final isDark = Theme.of(ctx).brightness == Brightness.dark;
    return isDark ? const Color(0xFF0F0F10) : Colors.white;
  }
}

// ═══════════════════════════════════════════════════════════════
// ✨ SHIMMER ANIMATION WRAPPER
// ═══════════════════════════════════════════════════════════════
class ShimmerBox extends StatefulWidget {
  final Widget child;
  final bool enabled;

  const ShimmerBox({super.key, required this.child, this.enabled = true});

  @override
  State<ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<ShimmerBox>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    _anim = Tween<double>(begin: -2.0, end: 2.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    return AnimatedBuilder(
      animation: _anim,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            final baseColor = SkeletonColors.base(context);
            final highlight = SkeletonColors.highlight(context);

            return LinearGradient(
              begin: Alignment(_anim.value - 1, 0),
              end: Alignment(_anim.value + 1, 0),
              colors: [baseColor, highlight, baseColor],
              stops: const [0.0, 0.5, 1.0],
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 🧱 BASE SKELETON BLOCK
// ═══════════════════════════════════════════════════════════════
class SkeletonBlock extends StatelessWidget {
  final double? width;
  final double? height;
  final double radius;
  final EdgeInsets? margin;

  const SkeletonBlock({
    super.key,
    this.width,
    this.height,
    this.radius = 8,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        color: SkeletonColors.base(context),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

// ─── Text line skeleton ────────────────────────────────────────
class SkeletonText extends StatelessWidget {
  final double width;
  final double height;
  final double radius;

  const SkeletonText({
    super.key,
    this.width = double.infinity,
    this.height = 12,
    this.radius = 4,
  });

  @override
  Widget build(BuildContext context) {
    return SkeletonBlock(width: width, height: height, radius: radius);
  }
}

// ─── Circle avatar skeleton ────────────────────────────────────
class SkeletonCircle extends StatelessWidget {
  final double size;

  const SkeletonCircle({super.key, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: SkeletonColors.base(context),
        shape: BoxShape.circle,
      ),
    );
  }
}

// ─── Rounded card skeleton ─────────────────────────────────────
class SkeletonCard extends StatelessWidget {
  final double? height;
  final double? width;
  final EdgeInsets? padding;
  final EdgeInsets? margin;
  final Widget? child;
  final double radius;

  const SkeletonCard({
    super.key,
    this.height,
    this.width,
    this.padding,
    this.margin,
    this.child,
    this.radius = 16,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: width,
      padding: padding,
      margin: margin,
      decoration: BoxDecoration(
        color: SkeletonColors.bg(context),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: SkeletonColors.border(context), width: 1.15),
      ),
      child: child,
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 📴 OFFLINE BANNER (optional overlay)
// ═══════════════════════════════════════════════════════════════
class OfflineBanner extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const OfflineBanner({
    super.key,
    this.message = 'No internet connection. Showing placeholder...',
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        border: Border(
          bottom: BorderSide(color: const Color(0xFFF59E0B), width: 1),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded,
              color: Color(0xFF92400E), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF92400E),
              ),
            ),
          ),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 28),
              ),
              child: const Text('Retry',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
            ),
        ],
      ),
    );
  }
}