import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

class LiveMonitoringScreen extends StatefulWidget {
  const LiveMonitoringScreen({super.key});

  @override
  State<LiveMonitoringScreen> createState() => _LiveMonitoringScreenState();
}

class _LiveMonitoringScreenState extends State<LiveMonitoringScreen> {
  StreamSubscription<GyroscopeEvent>? _gyroSub;

  // Integrated angles (radians). This is a simple gyro integration suitable for
  // a lightweight MVP visualization (it will drift over time).
  double _pitch = 0.0; // rotation around x axis
  double _roll = 0.0; // rotation around y axis
  double _yaw = 0.0; // rotation around z axis

  // Smoothed angles to make the UI feel responsive but stable.
  double _pitchSmoothed = 0.0;
  double _rollSmoothed = 0.0;
  double _yawSmoothed = 0.0;

  DateTime? _lastGyroTs;
  String? _sensorError;

  @override
  void initState() {
    super.initState();
    _startGyro();
  }

  void _startGyro() {
    try {
      _gyroSub = gyroscopeEventStream().listen((event) {
        final now = DateTime.now();
        final last = _lastGyroTs;
        _lastGyroTs = now;
        if (last == null) return;

        final dt = now.difference(last).inMicroseconds / 1e6;
        if (dt <= 0 || dt > 0.2) return; // ignore long gaps

        // Integrate gyro angular velocity (rad/s) into angles (rad).
        _pitch += event.x * dt;
        _roll += event.y * dt;
        _yaw += event.z * dt;

        // Wrap to [-pi, pi] to keep values bounded.
        _pitch = _wrapPi(_pitch);
        _roll = _wrapPi(_roll);
        _yaw = _wrapPi(_yaw);

        // Smooth the visual output.
        const alpha = 0.18; // lower = smoother, higher = snappier
        _pitchSmoothed = _lerp(_pitchSmoothed, _pitch, alpha);
        _rollSmoothed = _lerp(_rollSmoothed, _roll, alpha);
        _yawSmoothed = _lerp(_yawSmoothed, _yaw, alpha);

        if (mounted) setState(() {});
      }, onError: (e) {
        if (mounted) setState(() => _sensorError = e.toString());
      });
    } catch (e) {
      _sensorError = e.toString();
    }
  }

  @override
  void dispose() {
    _gyroSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Live Monitoring')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final spacing = 12.0;
              final boxSize =
                  ((constraints.maxWidth - spacing) / 2).clamp(140.0, 220.0);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_sensorError != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Sensor error: $_sensorError',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ),
                  Wrap(
                    spacing: spacing,
                    runSpacing: spacing,
                    children: [
                      _MonitorBox(
                        label: 'Pitch',
                        angleRad: _pitchSmoothed,
                        size: boxSize,
                      ),
                      _MonitorBox(
                        label: 'Yaw',
                        angleRad: _yawSmoothed,
                        size: boxSize,
                      ),
                      _MonitorBox(
                        label: 'Roll',
                        angleRad: _rollSmoothed,
                        size: boxSize,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Tip: rotate/move your phone to see the bars update.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _MonitorBox extends StatelessWidget {
  const _MonitorBox({
    required this.label,
    required this.angleRad,
    required this.size,
  });

  final String label;
  final double angleRad;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final angleDeg = angleRad * 180 / math.pi;

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _MonitorBoxPainter(
          angleRad: angleRad,
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${angleDeg.toStringAsFixed(1)}°',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.85),
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

class _MonitorBoxPainter extends CustomPainter {
  _MonitorBoxPainter({
    required this.angleRad,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final double angleRad;
  final Color backgroundColor;
  final Color foregroundColor;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(18),
    );
    final bgPaint = Paint()..color = backgroundColor;
    canvas.drawRRect(rrect, bgPaint);

    // Clip so dotted line and bar stay inside rounded corners.
    canvas.save();
    canvas.clipRRect(rrect);

    final cx = size.width / 2;
    final cy = size.height / 2;

    // Dotted white reference line: from midpoint down to bottom center.
    final refPaint = Paint()
      ..color = foregroundColor.withValues(alpha: 0.85)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    _drawDashedLine(
      canvas,
      refPaint,
      Offset(cx, cy),
      Offset(cx, size.height - 14),
      dash: 6,
      gap: 6,
    );

    // Orientation bar: pivot around the midpoint.
    // Angle is relative to the reference line (vertical downward).
    // We interpret 0 rad as aligned with reference; rotate around center.
    final barLength = size.height * 0.42;
    final barPaint = Paint()
      ..color = foregroundColor
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;

    // Clamp the visual rotation so it remains readable in the square box.
    final clamped = angleRad.clamp(-math.pi / 2, math.pi / 2);

    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(clamped);
    // Draw from center downward (reference direction).
    canvas.drawLine(
      const Offset(0, 0),
      Offset(0, barLength),
      barPaint,
    );
    canvas.restore();

    canvas.restore();
  }

  void _drawDashedLine(
    Canvas canvas,
    Paint paint,
    Offset start,
    Offset end, {
    required double dash,
    required double gap,
  }) {
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final length = math.sqrt(dx * dx + dy * dy);
    if (length == 0) return;

    final dirX = dx / length;
    final dirY = dy / length;

    double dist = 0;
    while (dist < length) {
      final x1 = start.dx + dirX * dist;
      final y1 = start.dy + dirY * dist;
      final x2 = start.dx + dirX * math.min(dist + dash, length);
      final y2 = start.dy + dirY * math.min(dist + dash, length);
      canvas.drawLine(Offset(x1, y1), Offset(x2, y2), paint);
      dist += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _MonitorBoxPainter oldDelegate) {
    return oldDelegate.angleRad != angleRad ||
        oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.foregroundColor != foregroundColor;
  }
}

double _wrapPi(double v) {
  const twoPi = math.pi * 2;
  while (v > math.pi) {
    v -= twoPi;
  }
  while (v < -math.pi) {
    v += twoPi;
  }
  return v;
}

double _lerp(double a, double b, double t) => a + (b - a) * t;

