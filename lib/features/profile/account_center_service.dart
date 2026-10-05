import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:rms/core/constants/api_constants.dart';
import 'package:rms/features/auth/auth_service.dart';

class AccountCenterService {
  String get _authBase => ApiConstants.authBaseUrl;
  String get _accountBase => '${ApiConstants.apiHost}/account';

  Map<String, String> _headers(String token) => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };

  String? get _token => AuthService().token;

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final token = _token;
    if (token == null || token.isEmpty) throw Exception('No autenticado');
    final response = await http.post(
      Uri.parse('$_authBase/change-password'),
      headers: _headers(token),
      body: json.encode({
        'currentPassword': currentPassword,
        'newPassword': newPassword,
      }),
    );
    if (response.statusCode != 200) {
      final err = _parseError(response.body);
      throw Exception(err);
    }
  }

  Future<Map<String, dynamic>> getSecuritySettings() async {
    final token = _token;
    if (token == null || token.isEmpty) throw Exception('No autenticado');
    final response = await http.get(
      Uri.parse('$_authBase/security-settings'),
      headers: _headers(token),
    );
    if (response.statusCode != 200) {
      throw Exception(_parseError(response.body));
    }
    return json.decode(response.body) as Map<String, dynamic>;
  }

  Future<void> setLoginAlertsEnabled(bool enabled) async {
    final token = _token;
    if (token == null || token.isEmpty) throw Exception('No autenticado');
    final response = await http.patch(
      Uri.parse('$_authBase/security-settings'),
      headers: _headers(token),
      body: json.encode({'loginAlertsEnabled': enabled}),
    );
    if (response.statusCode != 200) {
      throw Exception(_parseError(response.body));
    }
  }

  Future<Map<String, dynamic>> setupTwoFactor() async {
    final token = _token;
    if (token == null || token.isEmpty) throw Exception('No autenticado');
    final response = await http.post(
      Uri.parse('$_authBase/2fa/setup'),
      headers: _headers(token),
    );
    if (response.statusCode != 200) {
      throw Exception(_parseError(response.body));
    }
    return json.decode(response.body) as Map<String, dynamic>;
  }

  Future<void> confirmTwoFactor(String code) async {
    final token = _token;
    if (token == null || token.isEmpty) throw Exception('No autenticado');
    final response = await http.post(
      Uri.parse('$_authBase/2fa/confirm'),
      headers: _headers(token),
      body: json.encode({'code': code}),
    );
    if (response.statusCode != 200) {
      throw Exception(_parseError(response.body));
    }
  }

  Future<void> disableTwoFactor(String password) async {
    final token = _token;
    if (token == null || token.isEmpty) throw Exception('No autenticado');
    final response = await http.post(
      Uri.parse('$_authBase/2fa/disable'),
      headers: _headers(token),
      body: json.encode({'password': password}),
    );
    if (response.statusCode != 200) {
      throw Exception(_parseError(response.body));
    }
  }

  Future<List<Map<String, dynamic>>> listSessions() async {
    final token = _token;
    if (token == null || token.isEmpty) throw Exception('No autenticado');
    final response = await http.get(
      Uri.parse('$_authBase/sessions'),
      headers: _headers(token),
    );
    if (response.statusCode != 200) {
      throw Exception(_parseError(response.body));
    }
    final list = json.decode(response.body) as List<dynamic>;
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> revokeSession(int id) async {
    final token = _token;
    if (token == null || token.isEmpty) throw Exception('No autenticado');
    final response = await http.delete(
      Uri.parse('$_authBase/sessions/$id'),
      headers: _headers(token),
    );
    if (response.statusCode != 200) {
      throw Exception(_parseError(response.body));
    }
  }

  Future<List<Map<String, dynamic>>> listLoginAlerts() async {
    final token = _token;
    if (token == null || token.isEmpty) throw Exception('No autenticado');
    final response = await http.get(
      Uri.parse('$_authBase/login-alerts'),
      headers: _headers(token),
    );
    if (response.statusCode != 200) {
      throw Exception(_parseError(response.body));
    }
    final list = json.decode(response.body) as List<dynamic>;
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<List<Map<String, dynamic>>> listPaymentMethods() async {
    final token = _token;
    if (token == null || token.isEmpty) throw Exception('No autenticado');
    final response = await http.get(
      Uri.parse('$_accountBase/payments/methods'),
      headers: _headers(token),
    );
    if (response.statusCode != 200) {
      throw Exception(_parseError(response.body));
    }
    final list = json.decode(response.body) as List<dynamic>;
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>> addPaymentMethod({
    required String cardNumber,
    required String holderName,
    required int expMonth,
    required int expYear,
  }) async {
    final token = _token;
    if (token == null || token.isEmpty) throw Exception('No autenticado');
    final response = await http.post(
      Uri.parse('$_accountBase/payments/methods'),
      headers: _headers(token),
      body: json.encode({
        'cardNumber': cardNumber,
        'holderName': holderName,
        'expMonth': expMonth,
        'expYear': expYear,
      }),
    );
    if (response.statusCode != 201) {
      throw Exception(_parseError(response.body));
    }
    return json.decode(response.body) as Map<String, dynamic>;
  }

  String _parseError(String body) {
    try {
      final m = json.decode(body) as Map<String, dynamic>;
      return m['error']?.toString() ?? 'Error';
    } catch (_) {
      return 'Error del servidor';
    }
  }
}
