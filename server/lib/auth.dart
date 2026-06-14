import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

/// Issues and verifies the JWTs handed to clients after login.
class TokenService {
  TokenService(this.secret, {this.ttl = const Duration(days: 30)});

  final String secret;
  final Duration ttl;

  ({String token, DateTime expiresAt}) issue({
    required String userId,
    required String username,
  }) {
    final expiresAt = DateTime.now().add(ttl);
    final jwt = JWT({'username': username}, subject: userId);
    final token = jwt.sign(SecretKey(secret), expiresIn: ttl);
    return (token: token, expiresAt: expiresAt);
  }

  /// Returns the userId from a valid token, or null if invalid/expired.
  String? verify(String token) {
    try {
      final jwt = JWT.verify(token, SecretKey(secret));
      return jwt.subject;
    } on JWTException {
      return null;
    }
  }
}
