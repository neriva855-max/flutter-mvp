import 'dart:convert';
import 'package:http/http.dart' as http;

/// Base URL for the FastAPI backend.
/// Replace YOUR_LAPTOP_IP_HERE with your machine's IP (e.g. 192.168.1.100).
/// On Android emulator use 10.0.2.2 instead of localhost.
// ignore: constant_identifier_names
const String BASE_URL = 'http://100.80.71.4:8000';

class ApiService {
  static final ApiService _instance = ApiService._();
  factory ApiService() => _instance;

  ApiService._();

  /// Send ride telemetry to backend once per sample.
  ///
  /// Backend endpoint:
  ///   POST $BASE_URL/ride_data
  ///
  /// Request body:
  /// {
  ///   "latitude": 53.0793,
  ///   "longitude": 8.8017,
  ///   "velocity": 12.4
  /// }
  Future<Map<String, dynamic>> postRideData({
    required double latitude,
    required double longitude,
    required double velocity,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$BASE_URL/ride_data'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
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

  /// Places autocomplete suggestions.
  ///
  /// Expects backend endpoint:
  ///   POST $BASE_URL/places/autocomplete
  ///
  /// Request body:
  ///   { "query": "bremen cen" }
  ///
  /// Response:
  /// {
  ///   "success": true,
  ///   "suggestions": [
  ///     {
  ///       "place_id": "abc123",
  ///       "main_text": "Bremen Central Station",
  ///       "secondary_text": "Bremen, Germany",
  ///       "full_text": "Bremen Central Station, Bremen, Germany"
  ///     }
  ///   ]
  /// }
  Future<Map<String, dynamic>> placesAutocomplete({required String query}) async {
    try {
      final response = await http.post(
        Uri.parse('$BASE_URL/places/autocomplete'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'query': query}),
      );
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return {'success': data['success'] == true, ...data};
      }
      return {
        'success': false,
        'message': data['message'] ?? 'Autocomplete request failed',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Cannot reach server. Check BASE_URL and network.',
      };
    }
  }

  /// Request a route between an origin and destination.
  ///
  /// Expects a backend endpoint at POST $BASE_URL/route with a JSON body:
  /// {
  ///   "origin": "...",
  ///   "destination": "..."
  /// }
  ///
  /// And a response of the form:
  /// {
  ///   "success": true,
  ///   "distance_text": "12.4 km",
  ///   "duration_text": "18 min",
  ///   "points": [
  ///     {"lat": 53.0793, "lng": 8.8017},
  ///     {"lat": 53.0801, "lng": 8.8052}
  ///   ]
  /// }
  Future<Map<String, dynamic>> getRoute({
    required String origin,
    required String destination,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$BASE_URL/route'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'origin': origin,
          'destination': destination,
        }),
      );
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return {'success': data['success'] == true, ...data};
      }
      return {
        'success': false,
        'message': data['message'] ?? 'Route request failed',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Cannot reach server. Check BASE_URL and network.',
      };
    }
  }

  Future<Map<String, dynamic>> signup(String email, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$BASE_URL/signup'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return {'success': true, ...data};
      }
      return {
        'success': false,
        'message': data['message'] ?? data['detail'] ?? 'Signup failed',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Cannot reach server. Check BASE_URL and network.',
      };
    }
  }

  Future<Map<String, dynamic>> login(String email, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$BASE_URL/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return {'success': true, ...data};
      }
      return {
        'success': false,
        'message': data['message'] ?? data['detail'] ?? 'Invalid credentials',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Cannot reach server. Check BASE_URL and network.',
      };
    }
  }

  Future<bool> healthCheck() async {
    try {
      final response = await http.get(Uri.parse('$BASE_URL/health'));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
