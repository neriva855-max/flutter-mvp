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
  bool _isSearchActive = false;

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

  Future<LatLng?> _getOrRequestCurrentLatLng() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        setState(() => _errorMessage = 'Location services are disabled.');
      }
      return null;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever ||
        permission == LocationPermission.denied) {
      if (mounted) {
        setState(() => _errorMessage = 'Location permission denied.');
      }
      return null;
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final target = LatLng(position.latitude, position.longitude);
      if (mounted) {
        setState(() {
          _currentPosition = target;
          _locationPermissionGranted = true;
          _errorMessage = null;
        });
      }
      if (_mapController != null) {
        await _mapController!.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: target, zoom: 14),
          ),
        );
      }
      return target;
    } catch (_) {
      if (mounted) {
        setState(() => _errorMessage = 'Could not get location.');
      }
      return null;
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

    return Scaffold(
      // Keep the map stable; the bottom sheet handles keyboard insets itself.
      resizeToAvoidBottomInset: false,
      appBar: AppBar(title: const Text('Map')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final height = constraints.maxHeight;
          final keyboardBottomInset = MediaQuery.of(context).viewInsets.bottom;
          final isKeyboardVisible = keyboardBottomInset > 0;

          // Refinement: only collapse the map when the keyboard is visible.
          // This prioritizes search suggestions during typing, but restores the
          // normal preview map size when the keyboard is dismissed.
          const double collapsedFraction = 0.22;
          final double normalFraction = 0.45;

          final shouldCollapseMap = isKeyboardVisible && _isSearchActive;
          final mapHeight = _isMapExpanded
              ? height
              : height * (shouldCollapseMap ? collapsedFraction : normalFraction);

          return Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                height: mapHeight,
                width: double.infinity,
                child: Stack(
                  children: [
                    // Prevent keyboard insets (MediaQuery.viewInsets) from
                    // propagating into the map subtree. This reduces rebuild/
                    // relayout work when the keyboard opens, which helps the
                    // keyboard animation feel more responsive.
                    MediaQuery.removeViewInsets(
                      context: context,
                      removeBottom: true,
                      child: RepaintBoundary(
                        child: GoogleMap(
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
                      ),
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
                    getCurrentLatLng: _getOrRequestCurrentLatLng,
                    onSearchActiveChanged: (active) {
                      if (_isSearchActive != active) {
                        setState(() => _isSearchActive = active);
                      }
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _RoutePlannerPanel extends StatefulWidget {
  const _RoutePlannerPanel({
    required this.currentPositionController,
    required this.destinationController,
    required this.isRouteLoading,
    required this.distanceText,
    required this.durationText,
    required this.onGetRoute,
    required this.getCurrentLatLng,
    required this.onSearchActiveChanged,
  });

  final TextEditingController currentPositionController;
  final TextEditingController destinationController;
  final bool isRouteLoading;
  final String? distanceText;
  final String? durationText;
  final VoidCallback onGetRoute;
  final Future<LatLng?> Function() getCurrentLatLng;
  final ValueChanged<bool> onSearchActiveChanged;

  @override
  State<_RoutePlannerPanel> createState() => _RoutePlannerPanelState();
}

class _RoutePlannerPanelState extends State<_RoutePlannerPanel> {
  final FocusNode _originFocusNode = FocusNode();
  final FocusNode _destinationFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  final GlobalKey _originFieldKey = GlobalKey();
  final GlobalKey _destinationFieldKey = GlobalKey();

  Timer? _originDebounce;
  Timer? _destinationDebounce;

  bool _isOriginSuggestionsLoading = false;
  bool _isDestinationSuggestionsLoading = false;
  List<_PlaceSuggestion> _originSuggestions = [];
  List<_PlaceSuggestion> _destinationSuggestions = [];
  String? _originSuggestionsError;
  String? _destinationSuggestionsError;
  bool _showOriginSuggestionsBox = false;
  bool _showDestinationSuggestionsBox = false;

  bool _isCurrentLocationLoading = false;
  String? _currentLocationError;
  // ignore: unused_field
  LatLng? _originLatLng; // stored for future use (origin by coordinates)

  // Stored for future routing/geocoding (place_id + selected text).
  // ignore: unused_field
  String? _selectedOriginPlaceId;
  String? _selectedOriginFullText;
  // ignore: unused_field
  String? _selectedDestinationPlaceId;
  String? _selectedDestinationFullText;

  @override
  void initState() {
    super.initState();
    _originFocusNode.addListener(() {
      if (_originFocusNode.hasFocus) {
        setState(() {
          _showOriginSuggestionsBox = true;
          _showDestinationSuggestionsBox = false;
        });
        widget.onSearchActiveChanged(true);
        _scrollToKey(_originFieldKey);
      } else {
        setState(() => _showOriginSuggestionsBox = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted &&
              !_originFocusNode.hasFocus &&
              !_destinationFocusNode.hasFocus) {
            widget.onSearchActiveChanged(false);
          }
        });
      }
    });
    _destinationFocusNode.addListener(() {
      if (_destinationFocusNode.hasFocus) {
        setState(() {
          _showDestinationSuggestionsBox = true;
          _showOriginSuggestionsBox = false;
        });
        widget.onSearchActiveChanged(true);
        _scrollToKey(_destinationFieldKey);
      } else {
        setState(() => _showDestinationSuggestionsBox = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted &&
              !_originFocusNode.hasFocus &&
              !_destinationFocusNode.hasFocus) {
            widget.onSearchActiveChanged(false);
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _originDebounce?.cancel();
    _destinationDebounce?.cancel();
    _originFocusNode.dispose();
    _destinationFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToKey(GlobalKey key) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = key.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        alignment: 0.08,
      );
    });
  }

  Future<void> _useCurrentLocationForOrigin() async {
    setState(() {
      _isCurrentLocationLoading = true;
      _currentLocationError = null;
    });
    final latLng = await widget.getCurrentLatLng();
    if (!mounted) return;
    if (latLng == null) {
      setState(() {
        _isCurrentLocationLoading = false;
        _currentLocationError = 'Unable to access current location.';
      });
      return;
    }

    setState(() {
      _isCurrentLocationLoading = false;
      _currentLocationError = null;
      _originLatLng = latLng;
      _originSuggestions = [];
      _originSuggestionsError = null;
      _isOriginSuggestionsLoading = false;
      _showOriginSuggestionsBox = false;
    });

    widget.currentPositionController.text = 'Current location';
    _destinationFocusNode.requestFocus();
  }

  void _onOriginChanged(String value) {
    final query = value.trim();
    if (_selectedOriginFullText != null && query != _selectedOriginFullText) {
      _selectedOriginFullText = null;
      _selectedOriginPlaceId = null;
    }
    _originLatLng = null;

    _originDebounce?.cancel();
    if (query.length < 2) {
      setState(() {
        _originSuggestions = [];
        _originSuggestionsError = null;
        _isOriginSuggestionsLoading = false;
        _showOriginSuggestionsBox = _originFocusNode.hasFocus;
      });
      return;
    }

    // Do minimal work on each keystroke; network + setState happens after debounce.
    _originDebounce = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted) return;
      setState(() {
        _isOriginSuggestionsLoading = true;
        _originSuggestionsError = null;
        _showOriginSuggestionsBox = _originFocusNode.hasFocus;
      });
      final result = await ApiService().placesAutocomplete(query: query);
      if (!mounted) return;
      if (result['success'] != true) {
        setState(() {
          _isOriginSuggestionsLoading = false;
          _originSuggestions = [];
          _originSuggestionsError =
              result['message'] as String? ?? 'Failed to fetch suggestions.';
          _showOriginSuggestionsBox = _originFocusNode.hasFocus;
        });
        return;
      }
      final raw = (result['suggestions'] as List<dynamic>? ?? []);
      final suggestions = raw
          .whereType<Map<String, dynamic>>()
          .map(_PlaceSuggestion.fromJson)
          .toList();
      setState(() {
        _isOriginSuggestionsLoading = false;
        _originSuggestions = suggestions;
        _originSuggestionsError = null;
        _showOriginSuggestionsBox = _originFocusNode.hasFocus;
      });
    });
  }

  void _onDestinationChanged(String value) {
    final query = value.trim();
    if (_selectedDestinationFullText != null &&
        query != _selectedDestinationFullText) {
      _selectedDestinationFullText = null;
      _selectedDestinationPlaceId = null;
    }

    _destinationDebounce?.cancel();
    if (query.length < 2) {
      setState(() {
        _destinationSuggestions = [];
        _destinationSuggestionsError = null;
        _isDestinationSuggestionsLoading = false;
        _showDestinationSuggestionsBox = _destinationFocusNode.hasFocus;
      });
      return;
    }

    _destinationDebounce = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted) return;
      setState(() {
        _isDestinationSuggestionsLoading = true;
        _destinationSuggestionsError = null;
        _showDestinationSuggestionsBox = _destinationFocusNode.hasFocus;
      });
      final result = await ApiService().placesAutocomplete(query: query);
      if (!mounted) return;
      if (result['success'] != true) {
        setState(() {
          _isDestinationSuggestionsLoading = false;
          _destinationSuggestions = [];
          _destinationSuggestionsError =
              result['message'] as String? ?? 'Failed to fetch suggestions.';
          _showDestinationSuggestionsBox = _destinationFocusNode.hasFocus;
        });
        return;
      }
      final raw = (result['suggestions'] as List<dynamic>? ?? []);
      final suggestions = raw
          .whereType<Map<String, dynamic>>()
          .map(_PlaceSuggestion.fromJson)
          .toList();
      setState(() {
        _isDestinationSuggestionsLoading = false;
        _destinationSuggestions = suggestions;
        _destinationSuggestionsError = null;
        _showDestinationSuggestionsBox = _destinationFocusNode.hasFocus;
      });
    });
  }

  void _selectOriginSuggestion(_PlaceSuggestion s) {
    setState(() {
      _selectedOriginPlaceId = s.placeId;
      _selectedOriginFullText = s.fullText;
      _originSuggestions = [];
      _originSuggestionsError = null;
      _isOriginSuggestionsLoading = false;
      _showOriginSuggestionsBox = false;
    });
    widget.currentPositionController.text = s.fullText;
    _destinationFocusNode.requestFocus();
  }

  void _selectDestinationSuggestion(_PlaceSuggestion s) {
    setState(() {
      _selectedDestinationPlaceId = s.placeId;
      _selectedDestinationFullText = s.fullText;
      _destinationSuggestions = [];
      _destinationSuggestionsError = null;
      _isDestinationSuggestionsLoading = false;
      _showDestinationSuggestionsBox = false;
    });
    widget.destinationController.text = s.fullText;
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final viewInsetsBottom = MediaQuery.of(context).viewInsets.bottom;
    final isKeyboardVisible = viewInsetsBottom > 0;
    final isSearching = _originFocusNode.hasFocus || _destinationFocusNode.hasFocus;

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
            return AnimatedPadding(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              padding: EdgeInsets.fromLTRB(
                20,
                isSearching ? 6 : 12,
                20,
                16 + viewInsetsBottom,
              ),
              child: SingleChildScrollView(
                controller: _scrollController,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
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
                    Container(
                      key: _originFieldKey,
                      child: TextField(
                        controller: widget.currentPositionController,
                        focusNode: _originFocusNode,
                        onChanged: _onOriginChanged,
                        textInputAction: TextInputAction.next,
                        onSubmitted: (_) =>
                            _destinationFocusNode.requestFocus(),
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.my_location),
                          hintText: 'Search origin',
                        ),
                      ),
                    ),
                    if (_showOriginSuggestionsBox)
                      _SuggestionsDropdown(
                        suggestions: _originSuggestions,
                        isLoading:
                            _isOriginSuggestionsLoading || _isCurrentLocationLoading,
                        errorMessage: _originSuggestionsError ?? _currentLocationError,
                        emptyMessage: 'Type to search places',
                        onTapSuggestion: _selectOriginSuggestion,
                        showWhenEmpty: true,
                        maxHeight: isKeyboardVisible ? 240 : 280,
                        header: _CurrentLocationRow(
                          onTap: _useCurrentLocationForOrigin,
                          isLoading: _isCurrentLocationLoading,
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
                    Container(
                      key: _destinationFieldKey,
                      child: TextField(
                        controller: widget.destinationController,
                        focusNode: _destinationFocusNode,
                        onChanged: _onDestinationChanged,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => FocusScope.of(context).unfocus(),
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.place),
                          hintText: 'Search destination',
                        ),
                      ),
                    ),
                    if (_showDestinationSuggestionsBox)
                      _SuggestionsDropdown(
                        suggestions: _destinationSuggestions,
                        isLoading: _isDestinationSuggestionsLoading,
                        errorMessage: _destinationSuggestionsError,
                        emptyMessage: 'Type to search places',
                        onTapSuggestion: _selectDestinationSuggestion,
                        showWhenEmpty: true,
                        maxHeight: isKeyboardVisible ? 240 : 280,
                      ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton(
                            onPressed:
                                widget.isRouteLoading ? null : widget.onGetRoute,
                            child: widget.isRouteLoading
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
                    if (widget.distanceText != null ||
                        widget.durationText != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        [
                          widget.distanceText,
                          widget.durationText,
                        ].whereType<String>().join(' • '),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SuggestionsDropdown extends StatelessWidget {
  const _SuggestionsDropdown({
    required this.suggestions,
    required this.isLoading,
    required this.errorMessage,
    required this.emptyMessage,
    required this.onTapSuggestion,
    required this.showWhenEmpty,
    required this.maxHeight,
    this.header,
  });

  final List<_PlaceSuggestion> suggestions;
  final bool isLoading;
  final String? errorMessage;
  final String emptyMessage;
  final ValueChanged<_PlaceSuggestion> onTapSuggestion;
  final bool showWhenEmpty;
  final double maxHeight;
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!showWhenEmpty && !isLoading && errorMessage == null && suggestions.isEmpty) {
      return const SizedBox.shrink();
    }

    const minListHeight = 56.0 * 3; // ~3 visible rows

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            // Keep a stable visible height so suggestions don't get hidden
            // behind the keyboard and we always show ~3 rows.
            minHeight: header == null ? minListHeight : (minListHeight + 56),
            maxHeight: maxHeight,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (header case final Widget h) h,
              Expanded(
                child: Builder(
                  builder: (context) {
                    if (isLoading) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(
                                height: 16,
                                width: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'Searching...',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    if (errorMessage != null) {
                      return Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          errorMessage!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      );
                    }

                    if (suggestions.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          emptyMessage,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      );
                    }

                    return ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      physics: const ClampingScrollPhysics(),
                      itemCount: suggestions.length,
                      separatorBuilder: (context, index) => Divider(
                        height: 1,
                        thickness: 1,
                        color: theme.colorScheme.outline.withValues(alpha: 0.35),
                      ),
                      itemBuilder: (context, index) {
                        final s = suggestions[index];
                        return InkWell(
                          onTap: () => onTapSuggestion(s),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.place,
                                  size: 18,
                                  color: theme.colorScheme.primary,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        s.mainText,
                                        style: theme.textTheme.bodyMedium?.copyWith(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      if (s.secondaryText.isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          s.secondaryText,
                                          style: theme.textTheme.bodySmall?.copyWith(
                                            color: theme
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CurrentLocationRow extends StatelessWidget {
  const _CurrentLocationRow({
    required this.onTap,
    required this.isLoading,
  });

  final VoidCallback onTap;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: isLoading ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          children: [
            Icon(
              Icons.my_location,
              size: 18,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Current location',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (isLoading)
              const SizedBox(
                height: 16,
                width: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
      ),
    );
  }
}

class _PlaceSuggestion {
  _PlaceSuggestion({
    required this.placeId,
    required this.mainText,
    required this.secondaryText,
    required this.fullText,
  });

  final String placeId;
  final String mainText;
  final String secondaryText;
  final String fullText;

  factory _PlaceSuggestion.fromJson(Map<String, dynamic> json) {
    return _PlaceSuggestion(
      placeId: (json['place_id'] ?? '').toString(),
      mainText: (json['main_text'] ?? '').toString(),
      secondaryText: (json['secondary_text'] ?? '').toString(),
      fullText: (json['full_text'] ?? '').toString(),
    );
  }
}
