class AuthState {
  final bool isAuthenticated;
  final String? token;
  final String? error;

  AuthState({this.isAuthenticated = false, this.token, this.error});
}
