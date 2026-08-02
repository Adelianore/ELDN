import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:latlong2/latlong.dart' as latlng;
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'config/firebase_config.dart';
import 'theme.dart';
import 'package:permission_handler/permission_handler.dart';
import 'web_utils_stub.dart' if (dart.library.html) 'web_utils_web.dart';
// Removed duplicate firebase_core import

// Shared Firebase options for both Web and Android
const firebaseOptions = FirebaseOptions(
  apiKey: 'AIzaSyDwY5wWSwBLXecbdkKcdSrORyLG2jrSgS4',
  appId: '1:668816548295:web:66eb9449492e9a89a739e2',
  messagingSenderId: '668816548295',
  projectId: 'eldn-olivia-dash',
  databaseURL:
      'https://eldn-olivia-dash-default-rtdb.asia-southeast1.firebasedatabase.app',
  storageBucket: 'eldn-olivia-dash.firebasestorage.app',
);

const androidFirebaseOptions = FirebaseOptions(
  apiKey: 'AIzaSyAtX7DmKO_vWV3QNXoKfmFjFpVvGyaMwNc',
  appId: '1:668816548295:android:f14a8519a7e141faa739e2',
  messagingSenderId: '668816548295',
  projectId: 'eldn-olivia-dash',
  databaseURL:
      'https://eldn-olivia-dash-default-rtdb.asia-southeast1.firebasedatabase.app',
  storageBucket: 'eldn-olivia-dash.firebasestorage.app',
);

const String mapLibreTileTemplate =
    'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png';
const List<String> mapLibreSubdomains = ['a', 'b', 'c'];

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    if (Firebase.apps.isEmpty) {
      if (kIsWeb) {
        await Firebase.initializeApp(options: firebaseOptions);
      } else {
        // Use google-services.json on Android to avoid manual credentials mismatch.
        await Firebase.initializeApp();
      }
    }
  } catch (e, stackTrace) {
    debugPrint('Firebase main initialization error: $e\n$stackTrace');
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ELDN Dashboard',
      theme: appTheme,
      home: const ELDNDashboard(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class VictimData {
  final String id;
  final double lat;
  final double lng;
  final DateTime detectedAt;
  String? photoUrl;
  final String? vibrationStatus;
  final String? soundStatus;
  final int? soundValue;

  VictimData({
    required this.id,
    required this.lat,
    required this.lng,
    required this.detectedAt,
    this.photoUrl,
    this.vibrationStatus,
    this.soundStatus,
    this.soundValue,
  });

  factory VictimData.fromSnapshot(DataSnapshot snapshot) {
    final rawValue = snapshot.value;
    if (rawValue is! Map) {
      throw FormatException(
        'Expected Map for victim snapshot but got ${rawValue.runtimeType} for key ${snapshot.key}',
      );
    }

    final data = rawValue.cast<dynamic, dynamic>();
    final id = snapshot.key ?? 'Unknown';
    final lat = _parseDouble(data['lat']);
    final lng = _parseDouble(data['lng']);
    final timestamp = _parseInt(data['timestamp']);
    final detectedAt = timestamp != null
        ? DateTime.fromMillisecondsSinceEpoch(timestamp)
        : DateTime.now();

    return VictimData(
      id: id,
      lat: lat,
      lng: lng,
      detectedAt: detectedAt,
      photoUrl: _parseString(data['photoUrl']),
      vibrationStatus: _parseString(data['vibrationStatus']),
      soundStatus: _parseString(data['soundStatus']),
      soundValue: _parseInt(data['soundValue']),
    );
  }

  static VictimData? tryFromSnapshot(DataSnapshot snapshot) {
    try {
      return VictimData.fromSnapshot(snapshot);
    } catch (error) {
      debugPrint('Skipping invalid victim snapshot ${snapshot.key}: $error');
      return null;
    }
  }

  static double _parseDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) {
      final normalized = value.trim().replaceAll(' ', '').replaceAll(',', '.');
      return double.tryParse(normalized) ?? 0.0;
    }
    return 0.0;
  }

  static int? _parseInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) {
      final normalized = value.trim().replaceAll(' ', '');
      return int.tryParse(normalized);
    }
    return null;
  }

  static String? _parseString(dynamic value) {
    if (value == null) return null;
    return value.toString();
  }
}

class ELDNDashboard extends StatefulWidget {
  const ELDNDashboard({super.key});

  @override
  State<ELDNDashboard> createState() => _ELDNDashboardState();
}

class _ELDNDashboardState extends State<ELDNDashboard>
    with SingleTickerProviderStateMixin {
  late DatabaseReference _dbRef;
  final fm.MapController _mapController = fm.MapController();
  final List<VictimData> _victims = [];
  bool _isConnected = false;
  String? _debugStatus;
  int? _liveSoundValue;
  late StreamSubscription _connectionStream;
  StreamSubscription? _dbSubscription;
  StreamSubscription? _deviceStatusSubscription;
  String _rawDeviceStatus = 'mati';
  String _vibrationState = 'UNKNOWN'; // status ON/OFF
  int _vibrationCounter = 0; // counter getaran

  DateTime? _lastDeviceHeartbeatTime;
  Timer? _deviceStatusTimer;
  Timer? _dbRefreshTimer;
  final Map<String, DateTime> _firstSeenTimes = {};
  late TabController _tabController;

  final Map<String, List<double>> _soundHistory = {};
  static const int _chartWindowSize = 50;

  String get deviceStatus {
    if (_rawDeviceStatus == 'mati') return 'Mati';
    if (_lastDeviceHeartbeatTime == null) return 'Mati';
    final difference = DateTime.now().difference(_lastDeviceHeartbeatTime!);
    if (difference.inSeconds > 15) {
      return 'Mati';
    }
    return _rawDeviceStatus == 'mendeteksi' ? 'Mendeteksi' : 'Standby';
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _requestPermissions();
    _initializeFirebase();
    _deviceStatusTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  Future<void> _requestPermissions() async {
    final status = await Permission.locationWhenInUse.status;
    if (!status.isGranted) {
      await Permission.locationWhenInUse.request();
    }
  }

  Future<void> _initializeFirebase() async {
    // Firebase is already initialized in main() function. We only configure the DB client settings here.
    setState(() {
      _debugStatus = 'Menghubungkan ke Firebase...';
    });

    final databaseUrl = FirebaseConfig.databaseUrl;
    final dbInstance = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL: databaseUrl,
    );

    try {
      if (!kIsWeb) {
        dbInstance.setPersistenceEnabled(true);
      }
      dbInstance.goOnline();

      // Setup Firebase Realtime Database reference
      _dbRef = dbInstance.ref(FirebaseConfig.victimPath);

      // Monitor Firebase connection status
      _connectionStream = dbInstance
          .ref('.info/connected')
          .onValue
          .listen(
            (event) {
              setState(() {
                _isConnected = event.snapshot.value == true;
              });
            },
            onError: (error) {
              debugPrint('Firebase connection status error: $error');
              setState(() {
                _isConnected = false;
                _debugStatus = 'Koneksi Firebase gagal: $error';
              });
            },
          );

      // Monitor Device Status Heartbeat
      _deviceStatusSubscription = dbInstance
          .ref('eldn/device_status')
          .onValue
          .listen((event) {
            final value = event.snapshot.value;
            if (value is Map) {
              final data = value.cast<dynamic, dynamic>();
              _rawDeviceStatus = data['status']?.toString() ?? 'mati';
              _vibrationState = data['vibrationState']?.toString() ?? 'UNKNOWN';
              _vibrationCounter =
                  VictimData._parseInt(data['vibrationCounter']) ?? 0;
              _lastDeviceHeartbeatTime = DateTime.now();
              setState(() {});
            }
          });

      // Listen to data changes from ESP32
      _listenToDatabase();
      _dbRefreshTimer = Timer.periodic(
        const Duration(seconds: 5),
        (_) => _refreshDatabase(),
      );
    } catch (error, stackTrace) {
      debugPrint('Firebase initialization failed: $error\n$stackTrace');
      setState(() {
        _isConnected = false;
        _debugStatus = 'Firebase initialization error: $error';
      });
    }
  }

  VictimData? _selectedVictim;

  void _listenToDatabase() {
    _dbSubscription = _dbRef.onValue.listen(
      _handleDatabaseEvent,
      onError: (error) {
        debugPrint('Firebase onValue error: $error');
        setState(() {
          _debugStatus = 'Firebase error: $error';
        });
      },
    );
  }

  void _handleDatabaseEvent(DatabaseEvent event) {
    final value = event.snapshot.value;
    debugPrint('Firebase raw value: $value');
    _processDatabaseValue(value);
  }

  Future<void> _refreshDatabase() async {
    try {
      final snapshot = await _dbRef.get();
      debugPrint('Firebase refresh snapshot value: ${snapshot.value}');
      _processDatabaseValue(snapshot.value);
    } catch (error) {
      debugPrint('Firebase refresh failed: $error');
    }
  }

  void _processDatabaseValue(dynamic value) {
    if (value == null) {
      setState(() {
        _victims.clear();
        _selectedVictim = null;
        _debugStatus = 'Database kosong (null)';
      });
      return;
    }

    if (value is! Map) {
      setState(() {
        _debugStatus = 'Format data tidak dikenal: ${value.runtimeType}';
      });
      return;
    }

    final map = value.cast<dynamic, dynamic>();
    final List<VictimData> victims = _buildVictimsFromMap(map);

    setState(() {
      _debugStatus = 'Data terdeteksi (List: ${victims.length} item)';
      _syncVictimsWithDatabase(victims);
    });
  }

  List<VictimData> _buildVictimsFromMap(Map<dynamic, dynamic> map) {
    final List<VictimData> parsedVictims = [];

    if (map.containsKey('lat') || map.containsKey('lng')) {
      final victim = _parseSingleVictim('korban', map);
      if (victim != null) {
        final coordKey =
            "${victim.lat.toStringAsFixed(5)}_${victim.lng.toStringAsFixed(5)}";
        if (!_firstSeenTimes.containsKey(coordKey)) {
          _firstSeenTimes[coordKey] = victim.detectedAt;
        }
        parsedVictims.add(
          VictimData(
            id: victim.id,
            lat: victim.lat,
            lng: victim.lng,
            detectedAt: _firstSeenTimes[coordKey]!,
            photoUrl: victim.photoUrl,
            vibrationStatus: victim.vibrationStatus,
            soundStatus: victim.soundStatus,
            soundValue: victim.soundValue,
          ),
        );
      }
      return parsedVictims;
    }

    map.forEach((key, val) {
      if (val is Map) {
        final victim = _parseSingleVictim(
          key.toString(),
          val.cast<dynamic, dynamic>(),
        );
        if (victim != null) {
          parsedVictims.add(victim);
        }
      }
    });

    parsedVictims.sort((a, b) => a.detectedAt.compareTo(b.detectedAt));

    return parsedVictims.map((v) {
      final coordKey =
          "${v.lat.toStringAsFixed(5)}_${v.lng.toStringAsFixed(5)}";
      if (!_firstSeenTimes.containsKey(coordKey)) {
        _firstSeenTimes[coordKey] = v.detectedAt;
      }
      return VictimData(
        id: v.id,
        lat: v.lat,
        lng: v.lng,
        detectedAt: _firstSeenTimes[coordKey]!,
        photoUrl: v.photoUrl,
        vibrationStatus: v.vibrationStatus,
        soundStatus: v.soundStatus,
        soundValue: v.soundValue,
      );
    }).toList();
  }

  VictimData? _parseSingleVictim(String id, Map<dynamic, dynamic> data) {
    try {
      final lat = VictimData._parseDouble(data['lat']);
      final lng = VictimData._parseDouble(data['lng']);
      final timestamp = VictimData._parseInt(data['timestamp']);
      final detectedAt = timestamp != null
          ? DateTime.fromMillisecondsSinceEpoch(timestamp)
          : DateTime.now();

      return VictimData(
        id: id,
        lat: lat,
        lng: lng,
        detectedAt: detectedAt,
        photoUrl: VictimData._parseString(data['photoUrl']),
        vibrationStatus: VictimData._parseString(data['vibrationStatus']),
        soundStatus: VictimData._parseString(data['soundStatus']),
        soundValue: VictimData._parseInt(data['soundValue']),
      );
    } catch (e) {
      debugPrint('Error parsing victim $id: $e');
      return null;
    }
  }

  void _syncVictimsWithDatabase(List<VictimData> incomingVictims) {
    // Sinkronkan korban dengan data terbaru dari Firebase
    final incomingIds = incomingVictims.map((v) => v.id).toSet();
    _victims.removeWhere((v) => !incomingIds.contains(v.id));

    for (final victim in incomingVictims) {
      final index = _victims.indexWhere((v) => v.id == victim.id);
      if (index >= 0) {
        _victims[index] = victim;
      } else {
        _victims.add(victim);
      }
    }

    _victims.sort((a, b) {
      final aNum = int.tryParse(a.id.replaceAll(RegExp(r'\D'), '')) ?? 0;
      final bNum = int.tryParse(b.id.replaceAll(RegExp(r'\D'), '')) ?? 0;
      if (aNum != bNum) {
        return aNum.compareTo(bNum);
      }
      return a.detectedAt.compareTo(b.detectedAt);
    });

    if (_selectedVictim != null) {
      final updatedSelected = _victims.firstWhere(
        (v) => v.id == _selectedVictim!.id,
        orElse: () => _selectedVictim!,
      );
      _selectedVictim = updatedSelected;
    }

    for (final victim in incomingVictims) {
      _appendSoundReading(victim.id, victim.soundValue ?? 0);
    }

    if (_tabController.index == 0 && _victims.isNotEmpty) {
      final lastV = _victims.last;
      if (lastV.lat != 0.0 && lastV.lng != 0.0) {
        _mapController.move(latlng.LatLng(lastV.lat, lastV.lng), 16);
      }
    }
  }

  void _showVictimDetail(VictimData victim) {
    setState(() {
      _selectedVictim = victim;
    });
  }

  void _appendSoundReading(String victimId, int value) {
    final history = _soundHistory.putIfAbsent(victimId, () => []);
    history.add(value.toDouble().clamp(0, 4095).toDouble());
    if (history.length > _chartWindowSize) {
      history.removeAt(0);
    }
    if (_selectedVictim?.id == victimId) {
      _liveSoundValue = value.clamp(0, 4095);
    }
  }

  List<double> _getSoundHistory(String victimId) {
    return List<double>.from(
      _soundHistory[victimId] ?? List<double>.filled(_chartWindowSize, 0),
    );
  }

  Widget _buildWebDetailPanel(VictimData? selectedVictim) {
    final victim =
        selectedVictim ?? (_victims.isNotEmpty ? _victims.last : null);

    if (victim == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.radar, size: 54, color: Colors.redAccent),
              SizedBox(height: 16),
              Text(
                'Menunggu Data Korban...',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white70,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Hubungkan perangkat ESP32 GPS untuk memulai pemantauan real-time.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.white54),
              ),
            ],
          ),
        ),
      );
    }

    final hasVibration =
        victim.vibrationStatus?.toLowerCase().contains('detect') == true ||
        victim.vibrationStatus?.toLowerCase().contains('ada') == true ||
        victim.vibrationStatus?.toLowerCase().contains('high') == true ||
        victim.vibrationStatus?.toLowerCase().contains('getaran') == true;

    final hasSound =
        victim.soundStatus?.toLowerCase().contains('detect') == true ||
        victim.soundStatus?.toLowerCase().contains('ada') == true ||
        victim.soundStatus?.toLowerCase().contains('suara') == true ||
        victim.soundStatus?.toLowerCase().contains('noise') == true ||
        (victim.soundStatus != null &&
            int.tryParse(victim.soundStatus!) != null);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    const Icon(
                      Icons.person_pin_circle,
                      color: Colors.redAccent,
                      size: 28,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        victim.id.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              if (_selectedVictim != null)
                IconButton(
                  onPressed: () => setState(() => _selectedVictim = null),
                  icon: const Icon(Icons.close, color: Colors.white54),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'DETEKSI TERAKHIR: ${DateFormat('dd/MM/yyyy HH:mm:ss').format(victim.detectedAt)}',
            style: const TextStyle(
              fontSize: 11,
              color: Colors.redAccent,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Divider(height: 24, color: Colors.white12),

          // Koordinat
          const Text(
            'LOKASI GPS',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.white54,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.02),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Latitude',
                      style: TextStyle(color: Colors.white38, fontSize: 13),
                    ),
                    Text(
                      victim.lat.toStringAsFixed(6),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        fontFamily: 'monospace',
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Longitude',
                      style: TextStyle(color: Colors.white38, fontSize: 13),
                    ),
                    Text(
                      victim.lng.toStringAsFixed(6),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        fontFamily: 'monospace',
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Sensor Status Telemetry
          const Text(
            'STATUS SENSOR TELEMETRI',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.white54,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 14,
                    horizontal: 12,
                  ),
                  decoration: BoxDecoration(
                    color: hasVibration
                        ? Colors.redAccent.withValues(alpha: 0.12)
                        : Colors.white.withValues(alpha: 0.02),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: hasVibration
                          ? Colors.redAccent.withValues(alpha: 0.4)
                          : Colors.white.withValues(alpha: 0.06),
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.vibration,
                        color: hasVibration ? Colors.redAccent : Colors.white38,
                        size: 28,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Sensor Getaran',
                        style: TextStyle(fontSize: 12, color: Colors.white70),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        victim.vibrationStatus ?? 'Aman',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: hasVibration
                              ? Colors.redAccent
                              : Colors.white38,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 14,
                    horizontal: 12,
                  ),
                  decoration: BoxDecoration(
                    color: hasSound
                        ? Colors.amberAccent.withValues(alpha: 0.12)
                        : Colors.white.withValues(alpha: 0.02),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: hasSound
                          ? Colors.amberAccent.withValues(alpha: 0.4)
                          : Colors.white.withValues(alpha: 0.06),
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.volume_up,
                        color: hasSound ? Colors.amberAccent : Colors.white38,
                        size: 28,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Sensor Suara',
                        style: TextStyle(fontSize: 12, color: Colors.white70),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        victim.soundStatus != null
                            ? '${victim.soundStatus}${victim.soundValue != null ? " (${victim.soundValue})" : ""}'
                            : 'Aman',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: hasSound ? Colors.amberAccent : Colors.white38,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          const Text(
            'SERIES SUARA REAL-TIME',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.white54,
            ),
          ),
          const SizedBox(height: 10),
          _buildSoundChart(victim),
          if (_liveSoundValue != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(
                  Icons.graphic_eq,
                  color: Colors.amberAccent,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Text(
                  'Live suara: $_liveSoundValue / 4095',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const Spacer(),
                Text(
                  _liveSoundValue! > 2500 ? 'TINGGI' : 'RENDAH',
                  style: TextStyle(
                    color: _liveSoundValue! > 2500
                        ? Colors.amberAccent
                        : Colors.greenAccent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 20),

          // Foto Korban
          const Text(
            'VISUALISASI / FOTO ESP32-CAM',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.white54,
            ),
          ),
          const SizedBox(height: 8),
          if (victim.photoUrl != null)
            GestureDetector(
              onTap: () => showDialog(
                context: context,
                builder: (_) => Dialog(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: InteractiveViewer(
                      child: Image.network(
                        victim.photoUrl!,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  victim.photoUrl!,
                  height: 180,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      _buildNoPhotoWidget(),
                ),
              ),
            )
          else
            _buildNoPhotoWidget(),
          const SizedBox(height: 20),

          // Google Maps Action Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                final url =
                    'https://maps.google.com/?q=${victim.lat},${victim.lng}';
                openUrl(url);
              },
              icon: const Icon(Icons.navigation, size: 18),
              label: const Text('BUKA GOOGLE MAPS'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoPhotoWidget() {
    return Container(
      height: 140,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.01),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.videocam_off_outlined, color: Colors.white24, size: 36),
            SizedBox(height: 8),
            Text(
              'Kamera Tidak Aktif / Belum Ada Foto',
              style: TextStyle(color: Colors.white30, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _isConnected ? Colors.greenAccent : Colors.redAccent,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color:
                          (_isConnected ? Colors.greenAccent : Colors.redAccent)
                              .withValues(alpha: 0.6),
                      blurRadius: 8,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                "ELDN MONITOR",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (deviceStatus == 'Mati'
                      ? Colors.grey.withValues(alpha: 0.12)
                      : (deviceStatus == 'Mendeteksi'
                            ? Colors.redAccent.withValues(alpha: 0.12)
                            : Colors.greenAccent.withValues(alpha: 0.12))),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: (deviceStatus == 'Mati'
                        ? Colors.white24
                        : (deviceStatus == 'Mendeteksi'
                              ? Colors.redAccent.withValues(alpha: 0.4)
                              : Colors.greenAccent.withValues(alpha: 0.4))),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: (deviceStatus == 'Mati'
                            ? Colors.grey
                            : (deviceStatus == 'Mendeteksi'
                                  ? Colors.redAccent
                                  : Colors.greenAccent)),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'ALAT: ${deviceStatus.toUpperCase()}',
                      style: TextStyle(fontSize: 9, color: Colors.white70),
                    ),
                    const SizedBox(width: 8),
                    // VIBRATION STATE CARD
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: _vibrationState == 'ON'
                            ? Colors.redAccent.withValues(alpha: 0.15)
                            : Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _vibrationState == 'ON'
                              ? Colors.redAccent
                              : Colors.white24,
                        ),
                      ),
                      child: Text(
                        'GETARAN: $_vibrationState',
                        style: TextStyle(
                          fontSize: 9,
                          color: _vibrationState == 'ON'
                              ? Colors.redAccent
                              : Colors.white70,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // VIBRATION COUNTER CARD
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.blueAccent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blueAccent),
                      ),
                      child: Text(
                        'KOUNTER: $_vibrationCounter',
                        style: const TextStyle(
                          fontSize: 9,
                          color: Colors.blueAccent,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        elevation: 0,
        centerTitle: true,
        actions: kIsWeb
            ? [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Row(
                    children: [
                      Text(
                        'Firebase: ${_isConnected ? "ON" : "OFF"}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _isConnected
                              ? Colors.greenAccent
                              : Colors.redAccent,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Total: ${_victims.length}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.blueAccent,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ]
            : null,
      ),
      body: _buildWebView(),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final confirm = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Hapus Data'),
              content: const Text(
                'Apakah Anda yakin ingin menghapus semua riwayat data korban? Tindakan ini permanen.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text(
                    'BATAL',
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                  ),
                  child: const Text('HAPUS SEMUA'),
                ),
              ],
            ),
          );

          if (confirm == true) {
            _dbRef.remove(); // Clear semua data
            setState(() {
              _victims.clear();
              _selectedVictim = null;
              _firstSeenTimes.clear();
            });
          }
        },
        backgroundColor: const Color(0xFFEF4444),
        tooltip: 'Reset Data',
        child: const Icon(Icons.delete_sweep, color: Colors.white),
      ),
    );
  }

  Widget _buildWebView() {
    final selectedVictim =
        _selectedVictim ?? (_victims.isNotEmpty ? _victims.last : null);

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          if (_debugStatus != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Text(
                _debugStatus!,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
            const SizedBox(height: 16),
          ],
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // PANEL 1: NODE LIST ONLY
                Expanded(
                  flex: 4,
                  child: Card(
                    elevation: 4,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Available Nodes',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Tap a node to select it and show details on the right.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white54,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Expanded(child: _buildNodeListView()),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),

                // PANEL 2: MAP VIEW
                Expanded(
                  flex: 5,
                  child: Card(
                    elevation: 4,
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      children: [
                        _buildMapView(),
                        Positioned(
                          top: 16,
                          left: 16,
                          right: 16,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFF0F172A,
                              ).withValues(alpha: 0.85),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.08),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.25),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: _isConnected
                                            ? Colors.greenAccent
                                            : Colors.redAccent,
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color:
                                                (_isConnected
                                                        ? Colors.greenAccent
                                                        : Colors.redAccent)
                                                    .withValues(alpha: 0.5),
                                            blurRadius: 6,
                                            spreadRadius: 2,
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      _isConnected
                                          ? 'Koneksi Cloud Aktif'
                                          : 'Terputus dari Firebase',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                                Text(
                                  'Update Terakhir: ${_victims.isNotEmpty ? DateFormat('HH:mm:ss').format(_victims.last.detectedAt) : "Tidak Ada"}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.white54,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),

                // PANEL 3: TELEMETRY DETAIL
                Expanded(
                  flex: 4,
                  child: Card(
                    elevation: 4,
                    child: _buildWebDetailPanel(selectedVictim),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapView() {
    return _buildMapLibreMap();
  }

  Widget _buildMapLibreMap() {
    final markers = _victims
        .where((victim) => victim.lat != 0.0 && victim.lng != 0.0)
        .map(
          (victim) => fm.Marker(
            point: latlng.LatLng(victim.lat, victim.lng),
            width: 56,
            height: 56,
            child: GestureDetector(
              onTap: () => _showVictimDetail(victim),
              child: const Icon(
                Icons.location_on,
                color: Colors.redAccent,
                size: 36,
              ),
            ),
          ),
        )
        .toList();

    final center =
        _victims.isNotEmpty &&
            _victims.last.lat != 0.0 &&
            _victims.last.lng != 0.0
        ? latlng.LatLng(_victims.last.lat, _victims.last.lng)
        : latlng.LatLng(-6.599925, 106.812398);

    return fm.FlutterMap(
      mapController: _mapController,
      options: fm.MapOptions(initialCenter: center, initialZoom: 16),
      children: [
        fm.TileLayer(
          urlTemplate: mapLibreTileTemplate,
          subdomains: mapLibreSubdomains,
          userAgentPackageName: 'com.example.olivia',
        ),
        fm.MarkerLayer(markers: markers),
      ],
    );
  }

  Widget _buildNodeListView() {
    if (_victims.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.devices_outlined, size: 54, color: Colors.white24),
            SizedBox(height: 16),
            Text(
              'Tidak ada node tersedia',
              style: TextStyle(fontSize: 14, color: Colors.white30),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: _victims.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final victim = _victims[_victims.length - 1 - index];
        final isSelected = _selectedVictim?.id == victim.id;

        return InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _showVictimDetail(victim),
          child: Container(
            decoration: BoxDecoration(
              color: isSelected
                  ? Colors.white.withValues(alpha: 0.04)
                  : Colors.white.withValues(alpha: 0.02),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected
                    ? Colors.amberAccent
                    : Colors.white.withValues(alpha: 0.08),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            child: Row(
              children: [
                Icon(
                  Icons.graphic_eq,
                  color: isSelected ? Colors.amberAccent : Colors.white54,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        victim.id.toUpperCase(),
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.white70,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Terakhir: ${DateFormat('HH:mm:ss').format(victim.detectedAt)}',
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.white24),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSoundChart(VictimData victim) {
    final history = _getSoundHistory(victim.id);
    return SizedBox(
      height: 220,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: 4095,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (value) =>
                FlLine(color: Colors.white12, strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: List.generate(
                history.length,
                (index) => FlSpot(index.toDouble(), history[index]),
              ),
              isCurved: true,
              color: Colors.amberAccent,
              barWidth: 2.8,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: Colors.amberAccent.withValues(alpha: 0.16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _connectionStream.cancel();
    _dbSubscription?.cancel();
    _deviceStatusSubscription?.cancel();
    _deviceStatusTimer?.cancel();
    _dbRefreshTimer?.cancel();
    super.dispose();
  }
}

class VictimListTile extends StatelessWidget {
  final VictimData victim;
  final VoidCallback onTap;

  const VictimListTile({super.key, required this.victim, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final hasVibration =
        victim.vibrationStatus?.toLowerCase().contains('detect') == true ||
        victim.vibrationStatus?.toLowerCase().contains('ada') == true ||
        victim.vibrationStatus?.toLowerCase().contains('high') == true ||
        victim.vibrationStatus?.toLowerCase().contains('getaran') == true;

    final hasSound =
        victim.soundStatus?.toLowerCase().contains('detect') == true ||
        victim.soundStatus?.toLowerCase().contains('ada') == true ||
        victim.soundStatus?.toLowerCase().contains('suara') == true ||
        victim.soundStatus?.toLowerCase().contains('noise') == true ||
        (victim.soundStatus != null &&
            int.tryParse(victim.soundStatus!) != null);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: (hasVibration || hasSound)
              ? Colors.redAccent.withValues(alpha: 0.3)
              : Colors.white.withValues(alpha: 0.06),
          width: 1.2,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
              // Left Avatar / Image / Alert Indicator
              Stack(
                alignment: Alignment.bottomRight,
                children: [
                  GestureDetector(
                    onTap: victim.photoUrl != null
                        ? () {
                            showDialog(
                              context: context,
                              builder: (context) => Dialog(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: InteractiveViewer(
                                    child: Image.network(
                                      victim.photoUrl!,
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }
                        : null,
                    child: victim.photoUrl != null
                        ? Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              image: DecorationImage(
                                image: NetworkImage(victim.photoUrl!),
                                fit: BoxFit.cover,
                              ),
                            ),
                          )
                        : Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: Colors.redAccent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.location_on,
                              color: Colors.redAccent,
                              size: 24,
                            ),
                          ),
                  ),
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: (hasVibration || hasSound)
                          ? Colors.redAccent
                          : Colors.greenAccent,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF0F172A),
                        width: 2,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),

              // Middle Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            victim.id.toUpperCase(),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              letterSpacing: 0.5,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          DateFormat('HH:mm:ss').format(victim.detectedAt),
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.white38,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          Icons.pin_drop,
                          size: 10,
                          color: Colors.white38,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            '${victim.lat.toStringAsFixed(5)}, ${victim.lng.toStringAsFixed(5)}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.white70,
                              fontFamily: 'monospace',
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Quick Sensor Pills - Dibungkus Wrap agar otomatis turun baris di layar sempit tanpa memicu overflow
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _buildQuickSensorPill(
                          'Getaran',
                          hasVibration ? 'Deteksi' : 'Aman',
                          hasVibration ? Colors.redAccent : Colors.white24,
                        ),
                        _buildQuickSensorPill(
                          'Suara',
                          hasSound
                              ? 'Deteksi${victim.soundValue != null ? " (${victim.soundValue})" : ""}'
                              : 'Aman',
                          hasSound ? Colors.amberAccent : Colors.white24,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right, color: Colors.white30, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickSensorPill(String label, String value, Color statusColor) {
    final isActive = statusColor != Colors.white24;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isActive
            ? statusColor.withValues(alpha: 0.12)
            : Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isActive
              ? statusColor.withValues(alpha: 0.3)
              : Colors.white.withValues(alpha: 0.05),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 4,
            height: 4,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '$label: $value',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: isActive ? statusColor : Colors.white38,
            ),
          ),
        ],
      ),
    );
  }
}

class VictimDetailDialog extends StatelessWidget {
  final VictimData victim;

  const VictimDetailDialog({super.key, required this.victim});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    victim.id,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(),
              const SizedBox(height: 16),
              _buildDetailRow(
                '⏰ Waktu Deteksi',
                DateFormat('dd/MM/yyyy HH:mm:ss').format(victim.detectedAt),
              ),
              const SizedBox(height: 12),
              _buildDetailRow('📍 Latitude', victim.lat.toStringAsFixed(6)),
              const SizedBox(height: 12),
              _buildDetailRow('📍 Longitude', victim.lng.toStringAsFixed(6)),
              if (victim.vibrationStatus != null) ...[
                const SizedBox(height: 12),
                _buildDetailRow('📳 Status Vibration', victim.vibrationStatus!),
              ],
              if (victim.soundStatus != null) ...[
                const SizedBox(height: 12),
                _buildDetailRow(
                  '🔊 Status Sound',
                  '${victim.soundStatus!}${victim.soundValue != null ? " (${victim.soundValue})" : ""}',
                ),
              ],
              const SizedBox(height: 20),
              // Foto dari Firebase atau ESP32-CAM
              if (victim.photoUrl != null) ...[
                const Text(
                  'Foto Korban:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  height: 300,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      victim.photoUrl!,
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Center(
                          child: CircularProgressIndicator(
                            value: loadingProgress.expectedTotalBytes != null
                                ? loadingProgress.cumulativeBytesLoaded /
                                      loadingProgress.expectedTotalBytes!
                                : null,
                          ),
                        );
                      },
                      errorBuilder: (context, error, stackTrace) {
                        return const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.image_not_supported,
                                size: 48,
                                color: Colors.grey,
                              ),
                              SizedBox(height: 12),
                              Text('Foto tidak tersedia'),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ] else
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                  child: Container(
                    width: double.infinity,
                    height: 200,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(8),
                      color: Colors.grey[100],
                    ),
                    child: const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.camera_alt, size: 48, color: Colors.grey),
                          SizedBox(height: 12),
                          Text('Belum ada foto'),
                        ],
                      ),
                    ),
                  ),
                ),
              // Google Maps Link
              const SizedBox(height: 12),
              InkWell(
                onTap: () {
                  final url =
                      'https://maps.google.com/?q=${victim.lat},${victim.lng}';
                  openUrl(url);
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.blue.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.navigation,
                            color: Colors.blueAccent,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Buka di Google Maps:',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.blue[200] ?? Colors.blueAccent,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'https://maps.google.com/?q=${victim.lat},${victim.lng}',
                        style: const TextStyle(
                          color: Colors.blueAccent,
                          decoration: TextDecoration.underline,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text(
                    'Tutup',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(fontFamily: 'Courier'),
          ),
        ),
      ],
    );
  }
}
