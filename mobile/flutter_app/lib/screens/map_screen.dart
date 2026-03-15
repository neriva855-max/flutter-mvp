import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  static const LatLng _defaultPosition = LatLng(37.4220, -122.0841);
  GoogleMapController? _mapController;
  LatLng? _currentPosition;
  bool _locationPermissionGranted = false;
  String? _errorMessage;
  bool _loadingPermission = true;
  bool _isMapExpanded = false;

  final TextEditingController _currentPositionController =
      TextEditingController();
  final TextEditingController _destinationController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _requestLocationPermission();
  }

  Future<void> _requestLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() {
        _loadingPermission = false;
        _errorMessage = 'Location services are disabled.';
      });
      return;
    }
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      setState(() {
        _loadingPermission = false;
        _errorMessage = 'Location permission permanently denied.';
      });
      return;
    }
    setState(() {
      _loadingPermission = false;
      _locationPermissionGranted = permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always;
    });
    if (_locationPermissionGranted) {
      _getCurrentPosition();
    } else {
      setState(() => _errorMessage = 'Location permission denied.');
    }
  }

  Future<void> _getCurrentPosition() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      if (mounted) {
        setState(() {
          _currentPosition = LatLng(position.latitude, position.longitude);
          _errorMessage = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'Could not get location.');
      }
    }
  }

  void _centerOnCurrentLocation() {
    if (_currentPosition != null && _mapController != null) {
      _mapController!.animateCamera(
        CameraUpdate.newLatLng(_currentPosition!),
      );
    } else {
      _getCurrentPosition().then((_) {
        if (_currentPosition != null && _mapController != null) {
          _mapController!.animateCamera(
            CameraUpdate.newLatLng(_currentPosition!),
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _mapController?.dispose();
     _currentPositionController.dispose();
     _destinationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingPermission) {
      return Scaffold(
        appBar: AppBar(title: const Text('Map')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final mediaQuery = MediaQuery.of(context);
    final height = mediaQuery.size.height;
    final mapHeight = _isMapExpanded ? height : height * 0.45;

    return Scaffold(
      appBar: AppBar(title: const Text('Map')),
      body: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            height: mapHeight,
            width: double.infinity,
            child: Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: _currentPosition ?? _defaultPosition,
                    zoom: 14,
                  ),
                  onMapCreated: (controller) {
                    _mapController = controller;
                  },
                  myLocationEnabled: _locationPermissionGranted,
                  myLocationButtonEnabled: false,
                ),
                if (_errorMessage != null)
                  Positioned(
                    top: 16,
                    left: 16,
                    right: 16,
                    child: Material(
                      color: Theme.of(context).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          _errorMessage!,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onErrorContainer,
                                  ),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  top: 16,
                  right: 16,
                  child: Material(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    shape: const CircleBorder(),
                    child: IconButton(
                      icon: Icon(
                        _isMapExpanded ? Icons.keyboard_arrow_down : Icons.fullscreen,
                      ),
                      tooltip: _isMapExpanded
                          ? 'Collapse map'
                          : 'Expand map',
                      onPressed: () {
                        setState(() {
                          _isMapExpanded = !_isMapExpanded;
                        });
                      },
                    ),
                  ),
                ),
                Positioned(
                  bottom: 16,
                  right: 16,
                  child: FloatingActionButton(
                    onPressed: _centerOnCurrentLocation,
                    child: const Icon(Icons.my_location),
                  ),
                ),
              ],
            ),
          ),
          if (!_isMapExpanded)
            Expanded(
              child: _RoutePlannerPanel(
                currentPositionController: _currentPositionController,
                destinationController: _destinationController,
              ),
            ),
        ],
      ),
    );
  }
}

class _RoutePlannerPanel extends StatelessWidget {
  const _RoutePlannerPanel({
    required this.currentPositionController,
    required this.destinationController,
  });

  final TextEditingController currentPositionController;
  final TextEditingController destinationController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 16,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outline.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              Text(
                'Plan your route',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Text(
                'Current position',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: currentPositionController,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.my_location),
                  hintText: 'Use current location or enter a place',
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Destination',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: destinationController,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.place),
                  hintText: 'Where do you want to go?',
                ),
              ),
              const SizedBox(height: 16),
              // Placeholder for future route-planning actions (e.g. fetch route, summary).
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    'Route options coming soon',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
