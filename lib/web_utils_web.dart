import 'package:web/web.dart';

/// Opens a URL in a new browser tab on Web platform.
void openUrl(String url) {
  window.open(url, '_blank');
}
