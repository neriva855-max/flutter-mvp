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
  StreamSubscription<UserAccelerometerEvent>? _userAccelSub;
  StreamSubscription<GyroscopeEvent>? _gyroSub;

  _SensorStrategy? _strategy;
  _MotionMetricSource _motionSource = _MotionMetricSource.none;

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

  // Motion metrics (session = "current ride" while this page is active).
  double _currentAccel = 0.0; // m/s^2 (magnitude)
  double _currentVelocity = 0.0; // m/s (estimated; drift-prone)
  double _maxAccel = 0.0; // m/s^2
  double _maxVelocity = 0.0; // m/s
  DateTime? _lastMotionTs;

  DateTime? _lastGyroTs;
  String? _sensorError;

  @override
  void initState() {
    super.initState();
    _initSensors();
  }

  Future<void> _initSensors() async {
    setState(() {
      _strategy = null;
      _sensorError = null;
    });

    // sensors_plus does not provide explicit availability APIs on all platforms.
    // Practical strategy: attempt to receive the first event from each stream
    // with a short timeout. If it times out or throws, treat as unavailable.
    final accelAvailable = await _probeStream<AccelerometerEvent>(
      () => accelerometerEventStream(),
    );
    final userAccelAvailable = await _probeStream<UserAccelerometerEvent>(
      () => userAccelerometerEventStream(),
    );
    final gyroAvailable = await _probeStream<GyroscopeEvent>(
      () => gyroscopeEventStream(),
    );

    if (!mounted) return;

    _motionSource = userAccelAvailable
        ? _MotionMetricSource.userAccel
        : (accelAvailable ? _MotionMetricSource.accelHighPass : _MotionMetricSource.none);

    if (accelAvailable && gyroAvailable) {
      setState(() => _strategy = _SensorStrategy.fused);
      _startFusedSensors();
    } else if (accelAvailable) {
      setState(() => _strategy = _SensorStrategy.accelOnly);
      _startAccelOnly();
    } else if (gyroAvailable) {
      setState(() => _strategy = _SensorStrategy.gyroOnly);
      _startGyroOnly();
    } else {
      setState(() => _strategy = _SensorStrategy.none);
    }
  }

  Future<bool> _probeStream<T>(Stream<T> Function() streamFactory) async {
    try {
      await streamFactory()
          .first
          .timeout(const Duration(milliseconds: 700));
      return true;
    } catch (_) {
      return false;
    }
  }

  void _startFusedSensors() {
    _cancelSubs();
    _lastGyroTs = null;
    _sensorError = null;
    _lastMotionTs = null;

    // ACCEL: updates the long-term absolute tilt estimate.
    _accelSub = accelerometerEventStream().listen((event) {
      final ax = event.x;
      final ay = event.y;
      final az = event.z;

      final pitch = math.atan2(-ax, math.sqrt(ay * ay + az * az));
      final roll = math.atan2(ay, az);

      _accelPitchRad = _wrapPi(pitch);
      _accelRollRad = _wrapPi(roll);

      // Motion metrics fallback (if no user accelerometer): high-pass magnitude estimate.
      if (_motionSource == _MotionMetricSource.accelHighPass) {
        final mag = math.sqrt(ax * ax + ay * ay + az * az);
        // Subtract ~g to remove gravity; clamp and smooth.
        final lin = (mag - 9.81).abs();
        _updateMotionMetrics(lin);
      }
    }, onError: (e) {
      if (mounted) setState(() => _sensorError = e.toString());
    });

    if (_motionSource == _MotionMetricSource.userAccel) {
      _userAccelSub = userAccelerometerEventStream().listen((event) {
        final ax = event.x;
        final ay = event.y;
        final az = event.z;
        final mag = math.sqrt(ax * ax + ay * ay + az * az);
        _updateMotionMetrics(mag);
      }, onError: (e) {
        if (mounted) setState(() => _sensorError = e.toString());
      });
    }

    // GYRO: integrates fast motion; fused with accel for stability.
    _gyroSub = gyroscopeEventStream().listen((event) {
      final now = DateTime.now();
      final last = _lastGyroTs;
      _lastGyroTs = now;
      if (last == null) return;

      final dt = now.difference(last).inMicroseconds / 1e6;
      if (dt <= 0 || dt > 0.2) return;

      _gyroPitchRad = _wrapPi(_gyroPitchRad + event.x * dt);
      _gyroRollRad = _wrapPi(_gyroRollRad + event.y * dt);

      const k = 0.98; // gyro weight (higher = more responsive, lower = more stable)
      _pitchRad = _wrapPi(k * _gyroPitchRad + (1 - k) * _accelPitchRad);
      _rollRad = _wrapPi(k * _gyroRollRad + (1 - k) * _accelRollRad);

      // Keep integrator anchored to fused output to minimize drift buildup.
      _gyroPitchRad = _pitchRad;
      _gyroRollRad = _rollRad;

      const uiAlpha = 0.22;
      _pitchSmoothed = _lerp(_pitchSmoothed, _pitchRad, uiAlpha);
      _rollSmoothed = _lerp(_rollSmoothed, _rollRad, uiAlpha);

      if (mounted) setState(() {});
    }, onError: (e) {
      if (mounted) setState(() => _sensorError = e.toString());
    });
  }

  void _startAccelOnly() {
    _cancelSubs();
    _sensorError = null;
    _lastMotionTs = null;

    _accelSub = accelerometerEventStream().listen((event) {
      final ax = event.x;
      final ay = event.y;
      final az = event.z;

      final pitch = math.atan2(-ax, math.sqrt(ay * ay + az * az));
      final roll = math.atan2(ay, az);

      _pitchRad = _wrapPi(pitch);
      _rollRad = _wrapPi(roll);

      const uiAlpha = 0.22;
      _pitchSmoothed = _lerp(_pitchSmoothed, _pitchRad, uiAlpha);
      _rollSmoothed = _lerp(_rollSmoothed, _rollRad, uiAlpha);

      if (_motionSource == _MotionMetricSource.accelHighPass) {
        final mag = math.sqrt(ax * ax + ay * ay + az * az);
        final lin = (mag - 9.81).abs();
        _updateMotionMetrics(lin);
      }

      if (mounted) setState(() {});
    }, onError: (e) {
      if (mounted) setState(() => _sensorError = e.toString());
    });

    if (_motionSource == _MotionMetricSource.userAccel) {
      _userAccelSub = userAccelerometerEventStream().listen((event) {
        final ax = event.x;
        final ay = event.y;
        final az = event.z;
        final mag = math.sqrt(ax * ax + ay * ay + az * az);
        _updateMotionMetrics(mag);
        if (mounted) setState(() {});
      }, onError: (e) {
        if (mounted) setState(() => _sensorError = e.toString());
      });
    }
  }

  void _startGyroOnly() {
    _cancelSubs();
    _lastGyroTs = null;
    _sensorError = null;
    _lastMotionTs = null;

    // Gyro-only is drift-prone: angles are relative (not absolute) and will
    // slowly drift over time. This is a fallback when no accelerometer is available.
    _gyroSub = gyroscopeEventStream().listen((event) {
      final now = DateTime.now();
      final last = _lastGyroTs;
      _lastGyroTs = now;
      if (last == null) return;

      final dt = now.difference(last).inMicroseconds / 1e6;
      if (dt <= 0 || dt > 0.2) return;

      _pitchRad = _wrapPi(_pitchRad + event.x * dt);
      _rollRad = _wrapPi(_rollRad + event.y * dt);

      const uiAlpha = 0.22;
      _pitchSmoothed = _lerp(_pitchSmoothed, _pitchRad, uiAlpha);
      _rollSmoothed = _lerp(_rollSmoothed, _rollRad, uiAlpha);

      if (mounted) setState(() {});
    }, onError: (e) {
      if (mounted) setState(() => _sensorError = e.toString());
    });
  }

  void _updateMotionMetrics(double rawAccel) {
    // Production-friendly guards: clamp spikes and smooth.
    final now = DateTime.now();
    final last = _lastMotionTs;
    _lastMotionTs = now;
    final dt = last == null ? null : now.difference(last).inMicroseconds / 1e6;

    // Clamp absurd spikes from sensor glitches.
    final clamped = rawAccel.clamp(0.0, 30.0);

    // Smooth acceleration magnitude.
    const accelAlpha = 0.18;
    _currentAccel = _lerp(_currentAccel, clamped, accelAlpha);

    // Update max acceleration with a small noise floor.
    if (_currentAccel.isFinite && _currentAccel > 0.3) {
      _maxAccel = math.max(_maxAccel, _currentAccel);
    }

    // Velocity estimate (drift-prone): integrate acceleration magnitude.
    // We apply a small decay to prevent runaway drift during UI testing.
    if (dt != null && dt > 0 && dt < 0.2) {
      // Ignore tiny accelerations (noise) for integration.
      final effectiveAccel = (_currentAccel < 0.25) ? 0.0 : _currentAccel;

      // Integrate as "speed magnitude". This is not true vehicle speed.
      _currentVelocity += effectiveAccel * dt;

      // Drift guard: gentle decay (simulates friction / bias removal).
      const decayPerSecond = 0.35; // m/s per second
      _currentVelocity = math.max(0.0, _currentVelocity - decayPerSecond * dt);

      // Clamp to reasonable display range.
      _currentVelocity = _currentVelocity.clamp(0.0, 60.0);
      _maxVelocity = math.max(_maxVelocity, _currentVelocity);
    }
  }

  void _resetRideStats() {
    setState(() {
      _currentAccel = 0.0;
      _currentVelocity = 0.0;
      _maxAccel = 0.0;
      _maxVelocity = 0.0;
      _lastMotionTs = null;
    });
  }

  void _cancelSubs() {
    _accelSub?.cancel();
    _userAccelSub?.cancel();
    _gyroSub?.cancel();
    _accelSub = null;
    _userAccelSub = null;
    _gyroSub = null;
  }

  @override
  void dispose() {
    _cancelSubs();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentKmh = _currentVelocity * 3.6;
    final maxKmh = _maxVelocity * 3.6;

    final peak0100Seconds = _computeZeroToHundredSeconds(_maxAccel);
    final leanDeg = _pitchSmoothed.abs() * 180 / math.pi;
    final leanDanger = leanDeg >= 45.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Monitoring'),
        actions: [
          IconButton(
            tooltip: 'Reset ride stats',
            onPressed: _strategy == null || _strategy == _SensorStrategy.none
                ? null
                : _resetRideStats,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final spacing = 12.0;
              final boxSize = ((constraints.maxWidth - spacing) / 2)
                  .clamp(150.0, 260.0);

              if (_strategy == null) {
                return const Center(child: CircularProgressIndicator());
              }

              if (_strategy == _SensorStrategy.none) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Feature not available',
                          style: theme.textTheme.titleMedium,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Motion sensors were not detected on this device.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                );
              }

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
                        label: 'Lean Angle',
                        angleRad: _pitchSmoothed,
                        size: boxSize,
                        mode: _TiltMode.pitch,
                        danger: leanDanger,
                      ),
                      const SizedBox(width: 12),
                      _TiltBox(
                        label: 'Steering Angle',
                        angleRad: _rollSmoothed,
                        size: boxSize,
                        mode: _TiltMode.roll,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _strategy == _SensorStrategy.fused
                        ? 'Using accelerometer + gyroscope (fused)'
                        : _strategy == _SensorStrategy.accelOnly
                            ? 'Using accelerometer only'
                            : 'Using gyroscope only (drift-prone)',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Motion metrics',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _MetricCard(
                        title: 'Current Acceleration',
                        value: '${_currentAccel.toStringAsFixed(2)} m/s²',
                        emphasizeValue: true,
                        subline: _motionSource == _MotionMetricSource.none
                            ? 'No acceleration source available'
                            : 'Live',
                      ),
                      _MetricCard(
                        title: 'Current Velocity',
                        value: '${currentKmh.toStringAsFixed(1)} km/h',
                        emphasizeValue: true,
                        subline:
                            'Estimated (from phone sensors; may drift)',
                      ),
                      _MetricCard(
                        title: 'Max Acceleration (ride)',
                        value: '${_maxAccel.toStringAsFixed(2)} m/s²',
                        subline: 'Session peak',
                      ),
                      _MetricCard(
                        title: 'Max Velocity (ride)',
                        value: '${maxKmh.toStringAsFixed(1)} km/h',
                        subline: 'Session peak',
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _ZeroToHundredBar(seconds: peak0100Seconds),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

enum _SensorStrategy { fused, accelOnly, gyroOnly, none }

enum _MotionMetricSource { userAccel, accelHighPass, none }

enum _TiltMode { pitch, roll }

double? _computeZeroToHundredSeconds(double accel) {
  // 100 km/h in m/s.
  const deltaV = 100 / 3.6;
  // Guard against noise/tiny/negative/absurd acceleration.
  if (!accel.isFinite) return null;
  if (accel < 0.5) return null;
  if (accel > 20) return null;
  final t = deltaV / accel;
  if (!t.isFinite || t <= 0) return null;
  // Cap to avoid absurd values from near-zero accel.
  return t.clamp(0.0, 120.0);
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    required this.subline,
    this.emphasizeValue = false,
  });

  final String title;
  final String value;
  final String subline;
  final bool emphasizeValue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = (MediaQuery.of(context).size.width - 16 * 2 - 12) / 2;

    return SizedBox(
      width: width.clamp(160.0, 360.0),
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: emphasizeValue ? FontWeight.w600 : null,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                value,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: emphasizeValue ? FontWeight.w700 : null,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                subline,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TiltBox extends StatelessWidget {
  const _TiltBox({
    required this.label,
    required this.angleRad,
    required this.size,
    required this.mode,
    this.danger = false,
  });

  final String label;
  final double angleRad;
  final double size;
  final _TiltMode mode;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final angleDeg = angleRad * 180 / math.pi;
    final textColor = danger ? theme.colorScheme.error : Colors.white;
    final barColor = danger ? theme.colorScheme.error : Colors.white;

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _TiltBoxPainter(
          angleRad: angleRad,
          mode: mode,
          backgroundColor: Colors.black,
          foregroundColor: barColor,
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: textColor,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${angleDeg.toStringAsFixed(1)}°',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: textColor.withValues(alpha: 0.85),
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

class _ZeroToHundredBar extends StatelessWidget {
  const _ZeroToHundredBar({required this.seconds});

  final double? seconds;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = seconds == null
        ? 'Peak acceleration equivalent 0–100 km/h: —'
        : 'Peak acceleration equivalent 0–100 km/h: ${seconds!.toStringAsFixed(1)} s';

    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(
              Icons.timer_outlined,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
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

