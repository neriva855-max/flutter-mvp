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
  StreamSubscription<AccelerometerEvent>? _accelSub;
  StreamSubscription<GyroscopeEvent>? _gyroSub;

  // Accelerometer-based pitch/roll (stable absolute tilt, disturbed by linear acceleration).
  double _accelPitchRad = 0.0;
  double _accelRollRad = 0.0;

  // Gyro-integrated pitch/roll (responsive, but drifts).
  double _gyroPitchRad = 0.0;
  double _gyroRollRad = 0.0;

  // Fused pitch/roll (complementary filter output).
  double _pitchRad = 0.0;
  double _rollRad = 0.0;

  // Smoothed for UI responsiveness (final output).
  double _pitchSmoothed = 0.0;
  double _rollSmoothed = 0.0;

  DateTime? _lastGyroTs;
  String? _sensorError;

  @override
  void initState() {
    super.initState();
    _startSensors();
  }

  void _startSensors() {
    try {
      _accelSub = accelerometerEventStream().listen((event) {
        // sensors_plus: x,y,z in m/s^2. When stationary, the vector mostly
        // represents gravity. We'll derive tilt angles from this vector.
        final ax = event.x;
        final ay = event.y;
        final az = event.z;

        // Pitch: rotation around device x-axis (tilt forward/back).
        // Roll: rotation around device y-axis (tilt left/right).
        //
        // Note: formulas can vary by coordinate convention; this provides a
        // stable, intuitive tilt visualization for most devices.
        final pitch = math.atan2(-ax, math.sqrt(ay * ay + az * az));
        final roll = math.atan2(ay, az);

        _accelPitchRad = _wrapPi(pitch);
        _accelRollRad = _wrapPi(roll);
      }, onError: (e) {
        if (mounted) setState(() => _sensorError = e.toString());
      });

      _gyroSub = gyroscopeEventStream().listen((event) {
        final now = DateTime.now();
        final last = _lastGyroTs;
        _lastGyroTs = now;
        if (last == null) return;

        final dt = now.difference(last).inMicroseconds / 1e6;
        if (dt <= 0 || dt > 0.2) return;

        // Integrate gyro rates (rad/s) -> angles (rad)
        _gyroPitchRad = _wrapPi(_gyroPitchRad + event.x * dt);
        _gyroRollRad = _wrapPi(_gyroRollRad + event.y * dt);

        // Complementary filter: trust gyro for short-term changes, accel for long-term stability.
        // Typical values: 0.95..0.99.
        const k = 0.98;
        _pitchRad = _wrapPi(k * _gyroPitchRad + (1 - k) * _accelPitchRad);
        _rollRad = _wrapPi(k * _gyroRollRad + (1 - k) * _accelRollRad);

        // Keep the integrator near the fused output to reduce drift buildup.
        _gyroPitchRad = _pitchRad;
        _gyroRollRad = _rollRad;

        const uiAlpha = 0.22;
        _pitchSmoothed = _lerp(_pitchSmoothed, _pitchRad, uiAlpha);
        _rollSmoothed = _lerp(_rollSmoothed, _rollRad, uiAlpha);

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
    _accelSub?.cancel();
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
              final boxSize = ((constraints.maxWidth - spacing) / 2)
                  .clamp(150.0, 260.0);

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
                  Row(
                    children: [
                      _TiltBox(
                        label: 'Pitch',
                        angleRad: _pitchSmoothed,
                        size: boxSize,
                        mode: _TiltMode.pitch,
                      ),
                      const SizedBox(width: 12),
                      _TiltBox(
                        label: 'Roll',
                        angleRad: _rollSmoothed,
                        size: boxSize,
                        mode: _TiltMode.roll,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Tip: tilt your phone to see pitch/roll update.',
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

enum _TiltMode { pitch, roll }

class _TiltBox extends StatelessWidget {
  const _TiltBox({
    required this.label,
    required this.angleRad,
    required this.size,
    required this.mode,
  });

  final String label;
  final double angleRad;
  final double size;
  final _TiltMode mode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final angleDeg = angleRad * 180 / math.pi;

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _TiltBoxPainter(
          angleRad: angleRad,
          mode: mode,
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

class _TiltBoxPainter extends CustomPainter {
  _TiltBoxPainter({
    required this.angleRad,
    required this.mode,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final double angleRad;
  final _TiltMode mode;
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

    // Dotted white reference line (normal):
    // - Pitch: vertical line through center.
    // - Roll: horizontal line through center.
    final refPaint = Paint()
      ..color = foregroundColor.withValues(alpha: 0.85)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    if (mode == _TiltMode.pitch) {
      _drawDashedLine(
        canvas,
        refPaint,
        Offset(cx, 14),
        Offset(cx, size.height - 14),
        dash: 6,
        gap: 6,
      );
    } else {
      _drawDashedLine(
        canvas,
        refPaint,
        Offset(14, cy),
        Offset(size.width - 14, cy),
        dash: 6,
        gap: 6,
      );
    }

    // Floating orientation bar: centered, not attached to any edge.
    final barLength = size.width * 0.58;
    final barPaint = Paint()
      ..color = foregroundColor
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;

    // Clamp the visual rotation so it remains readable in the square box.
    final clamped = angleRad.clamp(-math.pi / 2, math.pi / 2);

    // Add a subtle "float" offset so it visually deviates from the normal line
    // even when rotation is small.
    final floatOffset = math.sin(clamped) * (size.width * 0.08);

    canvas.save();
    canvas.translate(cx, cy);
    if (mode == _TiltMode.pitch) {
      // Vertical bar that tilts and floats slightly up/down.
      canvas.translate(0, -floatOffset);
      canvas.rotate(clamped);
      canvas.drawLine(
        Offset(0, -barLength / 2),
        Offset(0, barLength / 2),
        barPaint,
      );
    } else {
      // Horizontal bar that tilts and floats slightly left/right.
      canvas.translate(floatOffset, 0);
      canvas.rotate(clamped);
      canvas.drawLine(
        Offset(-barLength / 2, 0),
        Offset(barLength / 2, 0),
        barPaint,
      );
    }
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
  bool shouldRepaint(covariant _TiltBoxPainter oldDelegate) {
    return oldDelegate.angleRad != angleRad ||
        oldDelegate.mode != mode ||
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

