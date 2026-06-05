import 'dart:io';

/// Device metadata for analytics and escalation.
class DeviceMetadata {
  final String platform;
  final String osVersion;

  const DeviceMetadata({
    required this.platform,
    required this.osVersion,
  });

  Map<String, dynamic> toJson() {
    return {
      'platform': platform,
      'osVersion': osVersion,
    };
  }

  factory DeviceMetadata.fromJson(Map<String, dynamic> json) {
    return DeviceMetadata(
      platform: json['platform'] as String? ?? 'unknown',
      osVersion: json['osVersion'] as String? ?? 'unknown',
    );
  }

  @override
  String toString() => 'DeviceMetadata($platform $osVersion)';
}

/// Get device metadata for the current platform.
DeviceMetadata getDeviceMetadata() {
  if (Platform.isAndroid) {
    return DeviceMetadata(
      platform: 'Android',
      osVersion: _androidVersion(),
    );
  } else if (Platform.isIOS) {
    return DeviceMetadata(
      platform: 'iOS',
      osVersion: _iosVersion(),
    );
  } else if (Platform.isMacOS) {
    return DeviceMetadata(
      platform: 'macOS',
      osVersion: _macosVersion(),
    );
  } else if (Platform.isWindows) {
    return DeviceMetadata(
      platform: 'Windows',
      osVersion: _windowsVersion(),
    );
  } else if (Platform.isLinux) {
    return DeviceMetadata(
      platform: 'Linux',
      osVersion: 'unknown',
    );
  }

  return const DeviceMetadata(
    platform: 'unknown',
    osVersion: 'unknown',
  );
}

String _androidVersion() {
  // In a real implementation, you'd use device_info_plus or similar
  // For now, return a placeholder
  return 'Android';
}

String _iosVersion() {
  // In a real implementation, you'd use device_info_plus or similar
  // For now, return a placeholder
  return 'iOS';
}

String _macosVersion() {
  return 'macOS';
}

String _windowsVersion() {
  return 'Windows';
}
