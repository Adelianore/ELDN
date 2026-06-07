#include <WiFi.h>
#include <FirebaseESP32.h>
#include <TinyGPS++.h>

// =================== KONFIGURASI WIFI & FIREBASE ===================
const char* ssid = "Xiaomi Pad 7";
const char* pass = "anjay2102";

#define FIREBASE_HOST "eldn-olivia-dash-default-rtdb.asia-southeast1.firebasedatabase.app"
#define FIREBASE_AUTH "AIzaSyAtX7DmKO_vWV3QNXoKfmFjFpVvGyaMwNc"

// =================== KONFIGURASI PIN HARDWARE ===================
#define SOUND_PIN 34     // Sensor Suara (Analog)
#define VIBRATION_PIN 27 // Sensor Vibrasi/Getaran (Digital)

// Menggunakan Hardware Serial 1 Bawaan ESP32 untuk GPS (Pin 32 RX & 33 TX)
HardwareSerial gpsSerial(1); 
TinyGPSPlus gps;

// =================== INISIALISASI OBJEK ===================
FirebaseData fbdo;
FirebaseAuth auth;
FirebaseConfig config;

double lastValidLat = 0.0;
double lastValidLng = 0.0;

// =================== VARIABEL FILTER NYATA (BERUNTUN TANPA JEDA) ===================
unsigned long lastVibeTime = 0;     // Mencatat waktu ketukan terakhir
int vibrationCounter = 0;           // Menghitung jumlah ketukan beruntun
const int REQUIRED_KNOCKS = 4;      // Minimal ketukan beruntun cepat untuk dianggap manusia
const int MAX_INTERVAL = 400;       // Jeda maksimal antar ketukan (400 ms). Lebih dari ini = Faktor Lingkungan
const int DEBOUNCE_TIME = 50;       // Jeda minimal agar tidak *double-read* pada satu ketukan yang sama
bool lastVibeState = LOW;           // Menyimpan status sensor sebelumnya

void setup() {
  Serial.begin(115200);
  delay(1000);
  Serial.println("\n--- ELDN ESP32 (FAST BURST HUMAN FILTER) STARTING ---");

  gpsSerial.begin(9600, SERIAL_8N1, 32, 33); 
  Serial2.begin(115200, SERIAL_8N1, 26, 25); 
  
  pinMode(SOUND_PIN, INPUT);
  pinMode(VIBRATION_PIN, INPUT);

  Serial.print("Menghubungkan ESP32 ke WiFi...");
  WiFi.begin(ssid, pass);
  int timeout = 0;
  while (WiFi.status() != WL_CONNECTED && timeout < 20) {
    Serial.print(".");
    delay(500);
    timeout++;
  }
  
  if (WiFi.status() == WL_CONNECTED) {
    Serial.println(" TERHUBUNG INTERNET!");
  } else {
    Serial.println(" WIFI GAGAL!");
  }
  
  config.host = FIREBASE_HOST;
  config.signer.tokens.legacy_token = FIREBASE_AUTH;
  Firebase.begin(&config, &auth);
  Firebase.reconnectWiFi(true);
  Serial.println("Koneksi Firebase Berhasil Disiapkan!");
}

void loop() {
  // 1. Baca aliran data satelit GPS terus-menerus
  while (gpsSerial.available() > 0) {
    char c = gpsSerial.read();
    gps.encode(c);
  }

  if (gps.location.isValid()) {
    lastValidLat = gps.location.lat();
    lastValidLng = gps.location.lng();
  }

  // 2. Baca Semua Sensor
  int soundValue = analogRead(SOUND_PIN); 
  int currentVibeState = digitalRead(VIBRATION_PIN); 
  unsigned long currentTime = millis();
  Serial.print("Vibration State: "); Serial.println(currentVibeState == HIGH ? "ON" : "OFF");

  // 3. Logika Filter: Deteksi ketukan baru (Transisi LOW ke HIGH)
  if (currentVibeState == HIGH && lastVibeState == LOW) {
    unsigned long interval = currentTime - lastVibeTime;

    if (interval > DEBOUNCE_TIME) { // Validasi bukan noise hardware
      
      // Jika ini ketukan pertama, atau ketukan berikutnya terjadi dengan cepat (di bawah 400ms)
      if (vibrationCounter == 0 || interval <= MAX_INTERVAL) {
        vibrationCounter++;
        Serial.print("[PULSE] Ketukan cepat beruntun! Counter: "); 
        Serial.print(vibrationCounter);
        Serial.print(" | Jeda: "); Serial.print(interval); Serial.println(" ms");
      } 
      // JIKA ADA JEDA (Interval > 400ms), berarti hanya ketukan tunggal / faktor lingkungan
      else {
        Serial.print("[RESET] Jeda terlalu lama ("); Serial.print(interval); 
        Serial.println(" ms). Dianggap Faktor Lingkungan.");
        vibrationCounter = 1; // Mulai hitung dari 1 lagi untuk pola baru
      }
      
      lastVibeTime = currentTime;
    }
  }
  
  // Jika korban berhenti mengetuk di tengah jalan dan mendadak hening lebih dari MAX_INTERVAL
  if (vibrationCounter > 0 && (currentTime - lastVibeTime > MAX_INTERVAL)) {
    vibrationCounter = 0; 
  }

  lastVibeState = currentVibeState; // Simpan state terakhir

  // 4. Heartbeat berkala status standby ke Firebase setiap 5 detik
  static unsigned long lastHeartbeat = 0;
  static int heartbeatCount = 0;
  if (millis() - lastHeartbeat >= 5000) {
    lastHeartbeat = millis();
    if (WiFi.status() == WL_CONNECTED) {
      Firebase.setString(fbdo, "/eldn/device_status/status", "standby");
      Firebase.setInt(fbdo, "/eldn/device_status/heartbeat", ++heartbeatCount);
      Firebase.setInt(fbdo, "/eldn/device_status/soundValue", soundValue);
      Firebase.setInt(fbdo, "/eldn/device_status/vibrationCounter", vibrationCounter);
      Firebase.setString(fbdo, "/eldn/device_status/vibrationState", currentVibeState == HIGH ? "ON" : "OFF");

      if (lastValidLat != 0.0 && lastValidLng != 0.0) {
        Firebase.setDouble(fbdo, "/eldn/korban/korban_1/lat", lastValidLat);
        Firebase.setDouble(fbdo, "/eldn/korban/korban_1/lng", lastValidLng);
      }
    }
  }

  // 5. Logika Pemicu Utama (Jika suara sangat keras ATAU counter ketukan cepat terpenuhi)
  if (soundValue > 2500 || vibrationCounter >= REQUIRED_KNOCKS) { 
    Serial.println("\n==================================================");
    if (vibrationCounter >= REQUIRED_KNOCKS) {
      Serial.println("VALID: Deteksi Gedokan Beruntun Cepat dari Korban!");
    } else {
      Serial.println("VALID: Suara Teriakan Keras Terdeteksi!");
    }
    Serial.print("Sound Value: "); Serial.print(soundValue);
    Serial.print(" | Total Ketukan Beruntun: "); Serial.println(vibrationCounter);

    if (WiFi.status() == WL_CONNECTED) {
      Firebase.setString(fbdo, "/eldn/device_status/status", "mendeteksi");
      Firebase.setInt(fbdo, "/eldn/device_status/soundValue", soundValue);
      
      String victimId = "korban_1";
      String path = "/eldn/korban/" + victimId;

      Firebase.deleteNode(fbdo, path + "/photoUrl");

      if (lastValidLat != 0.0 && lastValidLng != 0.0) {
        Firebase.setDouble(fbdo, path + "/lat", lastValidLat);
        Firebase.setDouble(fbdo, path + "/lng", lastValidLng);
      } else {
        Firebase.setDouble(fbdo, path + "/lat", 0.0);
        Firebase.setDouble(fbdo, path + "/lng", 0.0);
      }

      Firebase.setString(fbdo, path + "/soundStatus", String(soundValue));
      Firebase.setInt(fbdo, path + "/soundValue", soundValue);
      Firebase.setString(fbdo, path + "/vibrationStatus", "KORBAN_GEDOK_RAPID");
      Firebase.setInt(fbdo, path + "/vibrationKnocks", vibrationCounter);
      Firebase.setString(fbdo, path + "/timestamp", String(millis()));

      Serial.println("SUKSES: Data korban gedok-gedok beruntun berhasil dikirim ke Firebase!");

      // Trigger ESP32-CAM ambil foto
      Serial2.write('T'); 
      Serial.println("Request foto dari ESP32-CAM");
    }
    Serial.println("==================================================");
    
    vibrationCounter = 0; 
    delay(5000); // Jeda aman sistem
  }
  delay(10);
}