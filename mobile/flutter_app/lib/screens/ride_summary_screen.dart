import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import '../services/api_service.dart' show BASE_URL;

class RideSummaryScreen extends StatefulWidget {
  const RideSummaryScreen({super.key, this.userId});

  final String? userId;

  @override
  State<RideSummaryScreen> createState() => _RideSummaryScreenState();
}

class _RideSummaryScreenState extends State<RideSummaryScreen> {
  Timer? _sendTimer;
  bool _isSending = false;
  bool _isStarting = false;
  String _status = 'Press Start to begin ride data streaming.';
  int? _activeRideNo;

  String? get _normalizedUserId {
    final value = widget.userId?.trim().toLowerCase();
    if (value == null || value.isEmpty) return null;
    return value;
  }

  Future<void> _toggleSending() async {
    if (_isStarting) return;
    if (_isSending) {
      await _stopSending();
      return;
    }
    await _startSending();
  }

  Future<void> _startSending() async {
    if (_isSending || _isStarting) return;

    final userId = _normalizedUserId;
    if (userId == null) {
      setState(() {
        _status = 'Cannot start ride: missing user email. Please login again.';
      });
      return;
    }

    setState(() {
      _isStarting = true;
      _status = 'Checking location permissions...';
    });

    final allowed = await _ensureLocationPermission();
    if (!mounted) return;

    if (!allowed) {
      setState(() {
        _isStarting = false;
        _status = 'Location permission is required to send ride data.';
      });
      return;
    }

    final rideStart = await _startRide(userId: userId);
    if (!mounted) return;
    if (rideStart['success'] != true) {
      setState(() {
        _isStarting = false;
        _status = rideStart['message'] as String? ?? 'Could not start ride.';
      });
      return;
    }

    final rideNo = rideStart['ride_no'];
    if (rideNo is! int || rideNo <= 0) {
      setState(() {
        _isStarting = false;
        _status = 'Could not start ride: invalid ride number from server.';
      });
      return;
    }

    setState(() {
      _isStarting = false;
      _isSending = true;
      _activeRideNo = rideNo;
      _status = 'Ride #$rideNo started (1 sample/sec).';
    });

    // Prevent duplicate timers, send immediate sample,
    // then continue at 1 sample per second.
    _sendTimer?.cancel();
    await _sendRideSample();
    _sendTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _sendRideSample();
    });
  }

  Future<void> _stopSending() async {
    if (!_isSending) return;

    _sendTimer?.cancel();
    _sendTimer = null;

    setState(() {
      _isSending = false;
      _activeRideNo = null;
      _status = 'Ride data streaming stopped.';
    });
  }

  Future<bool> _ensureLocationPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    return permission != LocationPermission.denied &&
        permission != LocationPermission.deniedForever;
  }

  Future<void> _sendRideSample() async {
    final userId = _normalizedUserId;
    final rideNo = _activeRideNo;
    if (userId == null || rideNo == null || rideNo <= 0) {
      if (!mounted) return;
      setState(() {
        _status = 'Cannot send telemetry: ride not initialized.';
      });
      return;
    }

    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation,
      );

      final latitude = pos.latitude;
      final longitude = pos.longitude;
      final velocity = pos.speed.isFinite ? pos.speed.clamp(0.0, 120.0) : 0.0;

      final result = await _postRideData(
        userId: userId,
        rideNo: rideNo,
        latitude: latitude,
        longitude: longitude,
        velocity: velocity,
      );

      if (!mounted) return;
      setState(() {
        if (result['success'] == true) {
          _status =
              'Ride #$rideNo sent: lat ${latitude.toStringAsFixed(5)}, lng ${longitude.toStringAsFixed(5)}, v ${velocity.toStringAsFixed(2)} m/s';
        } else {
          _status = result['message'] as String? ?? 'Failed to send ride data.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = 'Could not read/send ride sample: $e';
      });
    }
  }

  Future<Map<String, dynamic>> _postRideData({
    required String userId,
    required int rideNo,
    required double latitude,
    required double longitude,
    required double velocity,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$BASE_URL/ride_data'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': userId,
          'ride_no': rideNo,
          'timestamp': _formatTimestamp(DateTime.now()),
          'latitude': latitude,
          'longitude': longitude,
          'velocity': velocity,
        }),
      );

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return {'success': data['success'] == true, ...data};
      }

      return {
        'success': false,
        'message': data['message'] ?? 'Ride data request failed',
      };
    } catch (_) {
      return {
        'success': false,
        'message': 'Cannot reach server. Check BASE_URL and network.',
      };
    }
  }

  Future<Map<String, dynamic>> _startRide({required String userId}) async {
    try {
      final response = await http.post(
        Uri.parse('$BASE_URL/ride/start'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user_id': userId}),
      );
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return {'success': data['success'] == true, ...data};
      }
      return {
        'success': false,
        'message': data['message'] ?? 'Ride start request failed',
      };
    } catch (_) {
      return {
        'success': false,
        'message': 'Cannot reach server. Check BASE_URL and network.',
      };
    }
  }

  String _formatTimestamp(DateTime t) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  @override
  void dispose() {
    _sendTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ride Summary'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              Text(
                'Ride Summary',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 10),
              Text(
                _normalizedUserId == null
                    ? 'No user email available. Please login again to use Ride Summary.'
                    : 'Tap Start to stream ride telemetry to the backend.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: _normalizedUserId == null
                      ? theme.colorScheme.error
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 28),
              Center(
                child: GestureDetector(
                  onTap: _isStarting ? null : _toggleSending,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 180),
                    opacity: _isStarting ? 0.8 : 1.0,
                    child: Column(
                      children: [
                        Container(
                          width: 170,
                          height: 170,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(28),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x33000000),
                                blurRadius: 18,
                                offset: Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Center(
                            child: Icon(
                              _isSending
                                  ? Icons.stop_circle_rounded
                                  : Icons.play_circle_fill_rounded,
                              size: 62,
                              color: _isSending
                                  ? Colors.red.shade600
                                  : Colors.purple.shade600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _isStarting
                              ? 'Starting...'
                              : (_isSending ? 'Stop' : 'Start'),
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Text(
                _status,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
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