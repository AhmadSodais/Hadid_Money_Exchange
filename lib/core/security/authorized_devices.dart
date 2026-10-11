/// Hard-coded device authorization for Hadid / GlassFlow.
///
/// Add every licensed workstation here before deploying. Formats accepted:
/// `AA:BB:CC:DD:EE:FF`, `AA-BB-CC-DD-EE-FF`, or `AABBCCDDEEFF`.
abstract final class AuthorizedDevices {
  /// Contact shown on the unauthorized-device screen.
  static const String supportName = 'Ahmad Sadis Faiz-Doost';
  static const String supportPhone = '0792348941';

  /// Pre-registered network adapters allowed to run the app.
  ///
  /// Keep both physical NICs of a PC when it has Ethernet + Wi‑Fi.
  static const List<String> macAddresses = [
    // Ahmad Sodais laptop
    '54:E1:AD:C5:C6:55',
    '00:E1:8C:A3:12:36',
    '02:E1:8C:A3:12:36',
    '00:FF:41:A6:2A:5D',
    "58:A0:23:D0:A9:F2",
    "58:A0:23:D0:A9:EE",
    "9C-FC-E8-8F-4C-FB",
    "0C-29-EF-99-D7-40"

 
  ];

  /// Normalized set (`AABBCCDDEEFF`, uppercase) for O(1) lookups.
  static final Set<String> normalizedMacs = {
    for (final raw in macAddresses)
      if (normalizeMac(raw) != null) normalizeMac(raw)!,
  };

  /// Returns a 12-char uppercase hex string, or null if [raw] is invalid.
  static String? normalizeMac(String raw) {
    final hex = raw.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '').toUpperCase();
    if (hex.length != 12) return null;
    return hex;
  }

  static bool isAuthorized(Iterable<String> deviceMacs) {
    for (final mac in deviceMacs) {
      final n = normalizeMac(mac);
      if (n != null && normalizedMacs.contains(n)) return true;
    }
    return false;
  }

  /// Pretty `AA:BB:CC:DD:EE:FF` for display.
  static String formatMac(String normalizedOrRaw) {
    final n = normalizeMac(normalizedOrRaw);
    if (n == null) return normalizedOrRaw;
    final buf = StringBuffer();
    for (var i = 0; i < 12; i += 2) {
      if (i > 0) buf.write(':');
      buf.write(n.substring(i, i + 2));
    }
    return buf.toString();
  }
}
