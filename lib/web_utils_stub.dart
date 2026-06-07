import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart';

/// Stub implementation for non-web platforms (Android, iOS, Desktop).
void openUrl(String url) async {
  final Uri uri = Uri.parse(url);
  try {
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      debugPrint('Could not launch $url - canLaunchUrl returned false');
    }
  } catch (e) {
    debugPrint('Error launching URL $url: $e');
  }
}
