// lib/widgets/geofence_indicator.dart
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../services/geofence_service.dart';
import '../theme/app_theme.dart';

class GeofenceStatusCard extends StatefulWidget {
  final GeofenceResult? result;
  final bool isLoading;
  final VoidCallback onRetry;

  const GeofenceStatusCard({
    super.key,
    required this.result,
    required this.isLoading,
    required this.onRetry,
  });

  @override
  State<GeofenceStatusCard> createState() => _GeofenceStatusCardState();
}

class _GeofenceStatusCardState extends State<GeofenceStatusCard>
    with TickerProviderStateMixin {
  late AnimationController _radarCtrl;
  late AnimationController _pulseCtrl;
  late Animation<double> _radarAnim;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _radarCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _radarAnim = Tween<double>(begin: 0, end: 1).animate(_radarCtrl);
    _pulseAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _radarCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final result       = widget.result;
    final isInside     = result?.isInside ?? false;
    final isError      = result?.isError ?? false;
    final isPermission = result?.isPermissionDenied ?? false;
    final isLoading    = widget.isLoading;

    Color statusColor;
    IconData statusIcon;
    String statusLabel;

    if (isLoading) {
      statusColor = AppColors.orange;
      statusIcon  = Icons.gps_fixed_rounded;
      statusLabel = 'Locating...';
    } else if (result == null) {
      statusColor = AppColors.textMuted;
      statusIcon  = Icons.location_off_rounded;
      statusLabel = 'Not checked';
    } else if (isInside) {
      statusColor = AppColors.success;
      statusIcon  = Icons.location_on_rounded;
      statusLabel = 'Inside zone ✓';
    } else if (isPermission) {
      statusColor = AppColors.error;
      statusIcon  = Icons.location_disabled_rounded;
      statusLabel = 'Permission denied';
    } else if (result.status == GeofenceStatus.serviceDisabled) {
      statusColor = AppColors.error;
      statusIcon  = Icons.gps_off_rounded;
      statusLabel = 'GPS disabled';
    } else if (isError) {
      statusColor = AppColors.error;
      statusIcon  = Icons.error_outline_rounded;
      statusLabel = 'GPS error';
    } else {
      statusColor = AppColors.error;
      statusIcon  = Icons.location_off_rounded;
      statusLabel = 'Outside zone';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: statusColor.withValues(alpha: 0.35), width: 1.5),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 64, height: 64,
            child: isLoading
                ? _LoadingRadar(color: statusColor)
                : _RadarGraphic(
              color: statusColor,
              isInside: isInside,
              radarAnim: _radarAnim,
              pulseAnim: _pulseAnim,
              distanceMeters: result?.distanceMeters,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(statusIcon, color: statusColor, size: 14),
                  const SizedBox(width: 5),
                  Text(statusLabel,
                      style: TextStyle(
                          color: statusColor, fontSize: 12,
                          fontWeight: FontWeight.w800, letterSpacing: 0.3)),
                ]),
                const SizedBox(height: 4),
                if (isLoading)
                  const Text('Getting GPS location...',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 11, height: 1.4))
                else if (result != null) ...[
                  Text(_buildInfoText(result),
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 11, height: 1.4),
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  if (result.accuracyMeters != null) ...[
                    const SizedBox(height: 4),
                    _AccuracyBar(accuracy: result.accuracyMeters!),
                  ],
                ] else
                  const Text('Tap refresh to check location',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
              ],
            ),
          ),
          GestureDetector(
            onTap: widget.onRetry,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1), shape: BoxShape.circle),
              child: Icon(
                isLoading ? Icons.hourglass_empty_rounded : Icons.refresh_rounded,
                color: statusColor, size: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _buildInfoText(GeofenceResult result) {
    if (result.distanceMeters != null) {
      final d = result.distanceMeters!;
      final radius = GeofenceService.allowedRadius;
      if (result.isInside) {
        return '${d.toStringAsFixed(0)} m from office · ${(radius - d).toStringAsFixed(0)} m to boundary';
      } else {
        return '${d.toStringAsFixed(0)} m from office · ${(d - radius).toStringAsFixed(0)} m outside zone';
      }
    }
    return result.message.split('\n').first;
  }
}

class _RadarGraphic extends StatelessWidget {
  final Color color;
  final bool isInside;
  final Animation<double> radarAnim;
  final Animation<double> pulseAnim;
  final double? distanceMeters;

  const _RadarGraphic({
    required this.color, required this.isInside,
    required this.radarAnim, required this.pulseAnim,
    this.distanceMeters,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([radarAnim, pulseAnim]),
      builder: (context, _) => CustomPaint(
        painter: _RadarPainter(
          color: color, isInside: isInside,
          radarProgress: radarAnim.value, pulseScale: pulseAnim.value,
          distanceFraction: distanceMeters != null
              ? (distanceMeters! / (GeofenceService.allowedRadius * 3)).clamp(0.0, 1.0)
              : null,
        ),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  final Color color;
  final bool isInside;
  final double radarProgress;
  final double pulseScale;
  final double? distanceFraction;

  const _RadarPainter({
    required this.color, required this.isInside,
    required this.radarProgress, required this.pulseScale,
    this.distanceFraction,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center    = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;

    for (int i = 3; i >= 1; i--) {
      canvas.drawCircle(center, maxRadius * (i / 3),
          Paint()..color = color.withValues(alpha: 0.07)
            ..style = PaintingStyle.stroke ..strokeWidth = 0.8);
    }
    canvas.drawCircle(center, maxRadius * 0.45,
        Paint()..color = color.withValues(alpha: isInside ? 0.12 : 0.06)
          ..style = PaintingStyle.fill);
    canvas.drawCircle(center, maxRadius * 0.45,
        Paint()..color = color.withValues(alpha: 0.4)
          ..style = PaintingStyle.stroke ..strokeWidth = 1.5);

    final sweepRect = Rect.fromCircle(center: center, radius: maxRadius * 0.95);
    canvas.drawArc(sweepRect, radarProgress * 2 * pi - pi / 6, pi / 3, true,
        Paint()
          ..shader = SweepGradient(
            startAngle: 0, endAngle: pi / 3,
            colors: [Colors.transparent, color.withValues(alpha: 0.3)],
            transform: GradientRotation(radarProgress * 2 * pi - pi / 6),
          ).createShader(sweepRect)
          ..style = PaintingStyle.fill);

    canvas.drawCircle(center, 3, Paint()..color = color);

    if (distanceFraction != null) {
      final fraction = isInside
          ? distanceFraction! * 0.45
          : 0.45 + (distanceFraction! - 0.45) * 1.5;
      final userOffset = center + Offset(
        cos(radarProgress * 2 * pi) * maxRadius * fraction.clamp(0, 0.95),
        sin(radarProgress * 2 * pi) * maxRadius * fraction.clamp(0, 0.95),
      );
      final dotColor = isInside ? AppColors.success : AppColors.error;
      canvas.drawCircle(userOffset, 4, Paint()..color = dotColor);
      canvas.drawCircle(userOffset, 4 * pulseScale,
          Paint()..color = dotColor.withValues(alpha: 0.4)
            ..style = PaintingStyle.stroke ..strokeWidth = 1.5);
    }
  }

  @override
  bool shouldRepaint(_RadarPainter old) =>
      old.radarProgress != radarProgress ||
          old.pulseScale != pulseScale ||
          old.isInside != isInside;
}

class _LoadingRadar extends StatelessWidget {
  final Color color;
  const _LoadingRadar({required this.color});

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        SizedBox(
          width: 56, height: 56,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: color.withValues(alpha: 0.4)),
        ),
        Icon(Icons.gps_fixed_rounded, color: color, size: 22),
      ],
    );
  }
}

class _AccuracyBar extends StatelessWidget {
  final double accuracy;
  const _AccuracyBar({required this.accuracy});

  @override
  Widget build(BuildContext context) {
    Color barColor; String label; double fraction;
    if (accuracy < 10)      { barColor = AppColors.success; label = 'Excellent'; fraction = 1.0; }
    else if (accuracy < 30) { barColor = AppColors.success; label = 'Good';      fraction = 0.75; }
    else if (accuracy < 50) { barColor = AppColors.warning; label = 'Fair';      fraction = 0.5; }
    else                    { barColor = AppColors.error;   label = 'Poor';      fraction = 0.25; }

    return Row(children: [
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: fraction, backgroundColor: AppColors.cardBorder,
            valueColor: AlwaysStoppedAnimation(barColor), minHeight: 3,
          ),
        ),
      ),
      const SizedBox(width: 6),
      Text('GPS ±${accuracy.toStringAsFixed(0)}m · $label',
          style: TextStyle(color: barColor, fontSize: 9, fontWeight: FontWeight.w700)),
    ]);
  }
}

class GeofenceBlockedDialog extends StatelessWidget {
  final GeofenceResult result;
  final VoidCallback onRetry;
  final VoidCallback onDismiss;

  const GeofenceBlockedDialog({
    super.key,
    required this.result, required this.onRetry, required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final isPermission = result.isPermissionDenied;
    final isService    = result.status == GeofenceStatus.serviceDisabled;
    final isOutside    = result.isOutside;

    Color accentColor = AppColors.error;
    IconData icon;
    String title;

    if (isPermission || isService) {
      icon  = Icons.location_disabled_rounded;
      title = isService ? 'GPS Disabled' : 'Permission Required';
    } else if (isOutside) {
      icon  = Icons.location_off_rounded;
      title = 'Outside Office Zone';
    } else {
      icon  = Icons.error_outline_rounded;
      title = 'Location Error';
    }

    return Dialog(
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.1), shape: BoxShape.circle,
                border: Border.all(color: accentColor.withValues(alpha: 0.3), width: 2),
              ),
              child: Icon(icon, color: accentColor, size: 40),
            ),
            const SizedBox(height: 20),
            Text(title, textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary, letterSpacing: -0.5)),
            const SizedBox(height: 12),

            if (isOutside && result.distanceMeters != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.error.withValues(alpha: 0.2)),
                ),
                child: Column(children: [
                  _InfoRow(label: 'Your distance',
                      value: '${result.distanceMeters!.toStringAsFixed(0)} m from office',
                      valueColor: AppColors.error),
                  const SizedBox(height: 6),
                  _InfoRow(label: 'Allowed radius',
                      value: '${GeofenceService.allowedRadius.toStringAsFixed(0)} m',
                      valueColor: AppColors.textSecondary),
                  const SizedBox(height: 6),
                  _InfoRow(label: 'Move closer by',
                      value: '${(result.distanceMeters! - GeofenceService.allowedRadius).toStringAsFixed(0)} m',
                      valueColor: AppColors.warning),
                ]),
              ),
              const SizedBox(height: 12),
            ],

            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: AppColors.surfaceLight, borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                const Icon(Icons.business_rounded, color: AppColors.orange, size: 16),
                const SizedBox(width: 8),
                Expanded(child: Text(GeofenceService.officeAddress,
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.4))),
              ]),
            ),
            const SizedBox(height: 8),
            Text(_friendlyMessage(result), textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.5)),
            const SizedBox(height: 24),

            // ✅ FIX: async/await on openAppSettings & openLocationSettings
            if (isPermission)
              _ActionButton(
                label: 'Open Settings', icon: Icons.settings_rounded, color: accentColor,
                onTap: () async { await Geolocator.openAppSettings(); onDismiss(); },
              )
            else if (isService)
              _ActionButton(
                label: 'Enable GPS', icon: Icons.gps_fixed_rounded, color: accentColor,
                onTap: () async { await Geolocator.openLocationSettings(); onDismiss(); },
              )
            else
              _ActionButton(label: 'Try Again', icon: Icons.refresh_rounded,
                  color: accentColor, onTap: onRetry),

            const SizedBox(height: 10),
            TextButton(
              onPressed: onDismiss,
              child: const Text('DISMISS',
                  style: TextStyle(color: AppColors.textMuted,
                      fontWeight: FontWeight.w700, letterSpacing: 1, fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }

  String _friendlyMessage(GeofenceResult r) {
    switch (r.status) {
      case GeofenceStatus.serviceDisabled:
        return 'Please turn on your device GPS / Location Services to use attendance.';
      case GeofenceStatus.permissionDenied:
        return 'Location access is needed to verify you are at the office before clocking in/out.';
      case GeofenceStatus.permissionPermanentlyDenied:
        return 'Open App Settings and grant Location permission to continue.';
      case GeofenceStatus.outside:
        return 'You must be physically present at the office to record attendance.';
      case GeofenceStatus.error:
        return 'Could not determine your location. Check your GPS signal and try again.';
      default:
        return r.message;
    }
  }
}

class _InfoRow extends StatelessWidget {
  final String label; final String value; final Color valueColor;
  const _InfoRow({required this.label, required this.value, required this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w500)),
        Text(value, style: TextStyle(color: valueColor, fontSize: 11, fontWeight: FontWeight.w800)),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label; final IconData icon;
  final Color color; final VoidCallback onTap;
  const _ActionButton({required this.label, required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [color, color.withValues(alpha: 0.7)]),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4))],
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
        ]),
      ),
    );
  }
}