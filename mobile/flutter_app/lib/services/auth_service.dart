import 'api_service.dart';

/// Simple auth state: we only track whether the user is "logged in".
/// No JWT; login/signup success means the user is authenticated for this session.
class AuthService {
  static final AuthService _instance = AuthService._();
  factory AuthService() => _instance;

  AuthService._();

  bool _isLoggedIn = false;

  bool get isLoggedIn => _isLoggedIn;

  Future<Map<String, dynamic>> login(String email, String password) async {
    if (email.trim().isEmpty || password.isEmpty) {
      return {'success': false, 'message': 'Email and password are required'};
    }
    final result = await ApiService().login(email.trim(), password);
    if (result['success'] == true) {
      _isLoggedIn = true;
    }
    return result;
  }

  Future<Map<String, dynamic>> signup(
    String email,
    String password,
    String confirmPassword,
  ) async {
    if (email.trim().isEmpty) {
      return {'success': false, 'message': 'Email is required'};
    }
    if (password.isEmpty) {
      return {'success': false, 'message': 'Password is required'};
    }
    if (password != confirmPassword) {
      return {'success': false, 'message': 'Passwords do not match'};
    }
    if (password.length < 6) {
      return {'success': false, 'message': 'Password must be at least 6 characters'};
    }
    final result = await ApiService().signup(email.trim(), password);
    if (result['success'] == true) {
      _isLoggedIn = true;
    }
    return result;
  }

  void logout() {
    _isLoggedIn = false;
  }
}
