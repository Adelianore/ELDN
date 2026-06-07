// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Opens a URL in a new browser tab on Web platform.
void openUrl(String url) {
  html.window.open(url, '_blank');
}
