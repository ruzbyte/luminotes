import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Lowercase hex SHA-256 of [bytes]. Used as the content identity of a file.
String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

/// Convenience for callers holding a [Uint8List].
String sha256OfBytes(Uint8List bytes) => sha256Hex(bytes);
