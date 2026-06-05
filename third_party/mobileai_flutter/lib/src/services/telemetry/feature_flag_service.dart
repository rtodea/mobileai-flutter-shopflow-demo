import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../utils/logger.dart';

/// FeatureFlagService — Remote feature flag synchronization.
///
/// Uses MurmurHash3 for deterministic assignment.
/// Flags are fetched from the server and cached locally.
class FeatureFlagService {
  final String baseUrl;

  // Cached flags
  final Map<String, String> _flags = {};

  // Pending fetches
  final Map<String, Future<String>> _pendingFetches = {};

  FeatureFlagService({required this.baseUrl});

  /// Fetch all flags from the server
  Future<void> fetch(String analyticsKey) async {
    final endpoint = '$baseUrl/api/v1/flags';

    try {
      final response = await http.get(
        Uri.parse(endpoint),
        headers: {
          'Authorization': 'Bearer $analyticsKey',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final flags = data['flags'] as Map<String, dynamic>? ?? {};

        flags.forEach((key, value) {
          _flags[key] = value.toString();
        });

        Logger.debug('[FeatureFlag] Fetched ${flags.length} flags');
      } else {
        Logger.warn('[FeatureFlag] Fetch failed: ${response.statusCode}');
      }
    } catch (e) {
      Logger.warn('[FeatureFlag] Fetch error: $e');
    }
  }

  /// Get a flag value for the current device
  ///
  /// Uses deterministic hashing to assign the same value to the same device.
  /// [key] - Flag key
  /// [defaultValue] - Fallback if flag not found
  /// [deviceId] - Optional device ID for hashing (defaults to random)
  String getFlag(
    String key, {
    String? defaultValue,
    String? deviceId,
  }) {
    if (_flags.containsKey(key)) {
      final flag = _flags[key]!;
      final value = _parseFlagValue(flag, deviceId);
      return value ?? defaultValue ?? '';
    }

    return defaultValue ?? '';
  }

  /// Check if a flag is enabled (boolean-style)
  bool isEnabled(String key, {String? deviceId}) {
    final value = getFlag(key, defaultValue: 'false', deviceId: deviceId);
    return value.toLowerCase() == 'true' ||
        value == '1' ||
        value.toLowerCase() == 'on' ||
        value.toLowerCase() == 'yes';
  }

  /// Get a numeric flag value
  int getNumericFlag(
    String key, {
    int defaultValue = 0,
    String? deviceId,
  }) {
    final value = getFlag(key, defaultValue: defaultValue.toString(), deviceId: deviceId);
    return int.tryParse(value) ?? defaultValue;
  }

  /// Parse flag value based on type
  String? _parseFlagValue(String flagValue, String? deviceId) {
    // If the flag value is a simple string, return it
    if (!flagValue.contains('{') && !flagValue.contains('[')) {
      return flagValue;
    }

    try {
      final data = jsonDecode(flagValue) as Map<String, dynamic>;

      // Check for percentage-based rollout
      if (data.containsKey('percentage')) {
        final percentage = (data['percentage'] as num).toInt();
        final variants = data['variants'] as List<dynamic>? ?? [];

        if (variants.isEmpty) {
          return data['default']?.toString();
        }

        // Use deterministic hash to select variant
        final hashInput = deviceId ?? flagValue;
        final hash = _murmurHash3(hashInput);
        final bucket = hash % 100;

        if (bucket < percentage) {
          // Select variant based on hash
          final variantIndex = hash % variants.length;
          return variants[variantIndex].toString();
        }

        return data['default']?.toString();
      }

      // Check for conditional variants
      if (data.containsKey('variants')) {
        final variants = data['variants'] as List<dynamic>;
        if (variants.isNotEmpty) {
          final hashInput = deviceId ?? flagValue;
          final hash = _murmurHash3(hashInput);
          final variantIndex = hash % variants.length;
          return variants[variantIndex].toString();
        }
      }

      return data['default']?.toString();
    } catch (e) {
      Logger.warn('[FeatureFlag] Parse error: $e');
      return flagValue;
    }
  }

  /// MurmurHash3 - deterministic hash function
  /// Used for consistent flag assignment across sessions
  int _murmurHash3(String input) {
    final data = utf8.encode(input);
    final length = data.length;
    const seed = 0x5BD1E995;

    int h = seed ^ length;

    int i = 0;
    final remainder = length % 4;

    // Process 4 bytes at a time
    while (i < length - remainder) {
      final k = _readInt32(data, i);
      i += 4;

      final k1 = _mixK1(k);
      h = _mixH(h, k1);
    }

    // Process remaining bytes
    switch (remainder) {
      case 3:
        h ^= data[i + 2] << 16;
        // fall through
      case 2:
        h ^= data[i + 1] << 8;
        // fall through
      case 1:
        h ^= data[i];
        h = _mixHFinal(h);
    }

    // Final avalanche
    h ^= h >> 13;
    h = _multiplyByPrime(h);
    h ^= h >> 15;

    return h & 0xFFFFFFFF;
  }

  int _readInt32(List<int> data, int offset) {
    return (data[offset] & 0xFF) |
        ((data[offset + 1] & 0xFF) << 8) |
        ((data[offset + 2] & 0xFF) << 16) |
        ((data[offset + 3] & 0xFF) << 24);
  }

  int _mixK1(int k) {
    const c1 = 0xCC9E2D51;
    k = k * c1 & 0xFFFFFFFF;
    k = (k << 15 | k >> 17) & 0xFFFFFFFF; // ROTL32(k, 15)
    k = k * 0x1B873593 & 0xFFFFFFFF;
    return k;
  }

  int _mixH(int h, int k) {
    h = (h + k) & 0xFFFFFFFF;
    h = (h << 13 | h >> 19) & 0xFFFFFFFF; // ROTL32(h, 13)
    h = (h * 5 + 0xE6546B64) & 0xFFFFFFFF;
    return h;
  }

  int _mixHFinal(int h) {
    const c2 = 0x85EBCA6B;
    h = (h * c2) & 0xFFFFFFFF;
    h = (h << 13 | h >> 19) & 0xFFFFFFFF; // ROTL32(h, 13)
    h = (h * 0x1B873593) & 0xFFFFFFFF;
    return h;
  }

  int _multiplyByPrime(int h) {
    return (h * 5 + 0xE6546B64) & 0xFFFFFFFF;
  }

  /// Clear all cached flags
  void clear() {
    _flags.clear();
    _pendingFetches.clear();
  }

  /// Get all cached flags
  Map<String, String> get flags => Map.unmodifiable(_flags);
}
