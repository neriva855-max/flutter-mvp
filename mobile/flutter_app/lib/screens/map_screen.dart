import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../services/api_service.dart';

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

  bool _isRouteLoading = false;
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  String? _distanceText;
  String? _durationText;

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
      if (!mounted) return;
      final target = LatLng(position.latitude, position.longitude);
      setState(() {
        _currentPosition = target;
        _errorMessage = null;
      });
      if (_mapController != null) {
        _mapController!.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: target, zoom: 14),
          ),
        );
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

  Future<void> _getRoute() async {
    final originText = _currentPositionController.text.trim();
    final destinationText = _destinationController.text.trim();

    if (originText.isEmpty || destinationText.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter both current position and destination.';
      });
      return;
    }

    setState(() {
      _isRouteLoading = true;
      _errorMessage = null;
    });

    final result = await ApiService().getRoute(
      origin: originText,
      destination: destinationText,
    );

    if (!mounted) return;

    setState(() {
      _isRouteLoading = false;
    });

    if (result['success'] != true) {
      setState(() {
        _errorMessage =
            result['message'] as String? ?? 'Failed to fetch route.';
      });
      return;
    }

    final points = (result['points'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();

    if (points.length < 2) {
      setState(() {
        _errorMessage = 'Route data is incomplete.';
      });
      return;
    }

    final List<LatLng> routePoints = points
        .map(
          (p) => LatLng(
            (p['lat'] as num).toDouble(),
            (p['lng'] as num).toDouble(),
          ),
        )
        .toList();

    final originLatLng = routePoints.first;
    final destinationLatLng = routePoints.last;

    final markers = <Marker>{
      Marker(
        markerId: const MarkerId('origin'),
        position: originLatLng,
        infoWindow: const InfoWindow(title: 'Origin'),
      ),
      Marker(
        markerId: const MarkerId('destination'),
        position: destinationLatLng,
        infoWindow: const InfoWindow(title: 'Destination'),
      ),
    };

    final routePolyline = Polyline(
      polylineId: const PolylineId('route'),
      color: Theme.of(context).colorScheme.primary,
      width: 5,
      points: routePoints,
    );

    setState(() {
      _markers = markers;
      _polylines = {routePolyline};
      _distanceText = result['distance_text'] as String?;
      _durationText = result['duration_text'] as String?;
    });

    if (_mapController != null) {
      final bounds = _boundsFromLatLngList(routePoints);
      if (bounds != null) {
        await _mapController!.animateCamera(
          CameraUpdate.newLatLngBounds(bounds, 60),
        );
      }
    }
  }

  LatLngBounds? _boundsFromLatLngList(List<LatLng> points) {
    if (points.isEmpty) return null;
    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;

    for (final p in points.skip(1)) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
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
      resizeToAvoidBottomInset: true,
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
                    if (_currentPosition != null) {
                      _mapController!.moveCamera(
                        CameraUpdate.newCameraPosition(
                          CameraPosition(
                            target: _currentPosition!,
                            zoom: 14,
                          ),
                        ),
                      );
                    } else if (_locationPermissionGranted) {
                      _getCurrentPosition();
                    }
                  },
                  myLocationEnabled: _locationPermissionGranted,
                  myLocationButtonEnabled: false,
                  markers: _markers,
                  polylines: _polylines,
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
                isRouteLoading: _isRouteLoading,
                distanceText: _distanceText,
                durationText: _durationText,
                onGetRoute: _getRoute,
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
    required this.isRouteLoading,
    required this.distanceText,
    required this.durationText,
    required this.onGetRoute,
  });

  final TextEditingController currentPositionController;
  final TextEditingController destinationController;
  final bool isRouteLoading;
  final String? distanceText;
  final String? durationText;
  final VoidCallback onGetRoute;

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
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                20,
                12,
                20,
                16 + MediaQuery.of(context).viewInsets.bottom,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.outline
                              .withValues(alpha: 0.7),
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
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
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
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
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
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton(
                            onPressed: isRouteLoading ? null : onGetRoute,
                            child: isRouteLoading
                                ? const SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Get Route'),
                          ),
                        ),
                      ],
                    ),
                    if (distanceText != null || durationText != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        [
                          distanceText,
                          durationText,
                        ].whereType<String>().join(' • '),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
