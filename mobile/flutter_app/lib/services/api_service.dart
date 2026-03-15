import 'dart:convert';
import 'package:http/http.dart' as http;

/// Base URL for the FastAPI backend.
/// Replace YOUR_LAPTOP_IP_HERE with your machine's IP (e.g. 192.168.1.100).
/// On Android emulator use 10.0.2.2 instead of localhost.
// ignore: constant_identifier_names
const String BASE_URL = 'http://192.168.0.60:8000';

class ApiService {
  static final ApiService _instance = ApiService._();
  factory ApiService() => _instance;

  ApiService._();

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
