// lib/config/firebase_config.dart
// Firebase Configuration - Customize sesuai project Anda

class FirebaseConfig {
  // ⚠️ GANTI DENGAN DATA FIREBASE KAMU
  static const String databaseUrl = 'https://eldn-olivia-dash-default-rtdb.asia-southeast1.firebasedatabase.app';
  
  // Database paths
  static const String victimPath = 'eldn/korban';
  
  // Sensor thresholds
  static const int soundThreshold = 1200;      // Bisa disesuaikan
  static const bool vibrationEnabled = true;  // Enable/disable vibration sensor
  
  // Location defaults
  static const double defaultLatitude = -6.595;   // Jakarta
  static const double defaultLongitude = 106.816;
  static const double mapZoomLevel = 15.0;
  
  // UI Config
  static const String appTitle = "🚨 ELDN Dashboard";
  static const String appSubtitle = "Emergency Location Detection Network";
  
  // Connection retry config
  static const int retryDelaySeconds = 5;
  static const int maxRetries = 3;
  
  // Photo config
  static const double photoWidgetHeight = 300;
  static const String placeholderPhotoUrl = '';
}
