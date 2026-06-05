import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

const String _storageKey = '@mobileai_flutter_device_id';
String? _cachedId;

/// Get the cached device ID.
///
/// Returns null if not yet initialized.
String? getDeviceId() => _cachedId;

/// Initialize or retrieve the persistent device ID.
///
/// Call once on app startup. Subsequent getDeviceId() calls are synchronous.
Future<String> initDeviceId() async {
  if (_cachedId != null) return _cachedId!;

  final prefs = await SharedPreferences.getInstance();
  final stored = prefs.getString(_storageKey);

  if (stored != null && stored.isNotEmpty) {
    _cachedId = stored;
    return _cachedId!;
  }

  // Generate new device ID
  final newId = const Uuid().v4();
  await prefs.setString(_storageKey, newId);
  _cachedId = newId;
  return newId;
}

/// Generate a deterministic device ID for testing or fallback purposes.
///
/// Uses a simple hash of platform info. Not recommended for production
/// as it changes when platform info changes.
String generateFallbackDeviceId(String platform, String model) {
  final input = '$platform-$model-${DateTime.now().millisecondsSinceEpoch ~/ 100000}';
  final bytes = input.codeUnits;
  var hash = 0;
  for (var i = 0; i < bytes.length; i++) {
    hash = ((hash << 5) - hash) + bytes[i];
    hash = hash & 0xFFFFFFFF; // Convert to 32-bit integer
  }
  return 'dev-${hash.toRadixString(16).padLeft(8, '0')}';
}
