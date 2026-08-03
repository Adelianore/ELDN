import 'dart:io';

class NetworkInfo {
  static Future<String?> getLocalIpv4Address() async {
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      includeLinkLocal: false,
      type: InternetAddressType.IPv4,
    );

    String? fallback;
    for (final interface in interfaces) {
      final name = interface.name.toLowerCase();
      final addresses = interface.addresses
          .where((addr) => addr.type == InternetAddressType.IPv4)
          .where((addr) => addr.address != '127.0.0.1')
          .toList();
      if (addresses.isEmpty) continue;

      if (name.contains('wifi') ||
          name.contains('wlan') ||
          name.contains('hotspot') ||
          name.contains('wireless') ||
          name.contains('wi-fi')) {
        return addresses.first.address;
      }

      fallback ??= addresses.first.address;
    }

    return fallback;
  }
}
