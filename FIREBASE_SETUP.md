# 🚨 ELDN Dashboard - Firebase Setup Guide

## Langkah 1: Setup Firebase Project

### A. Buka Firebase Console
1. Pergi ke [Firebase Console](https://console.firebase.google.com/)
2. Login dengan akun Google Anda
3. Klik **"Create a new project"** atau pilih project yang ada

### B. Buat Real-time Database
1. Di sidebar, pilih **Realtime Database**
2. Klik **"Create Database"**
3. Pilih **"Start in test mode"** (untuk development)
4. Pilih region terdekat (contoh: `asia-southeast1` untuk Indonesia)
5. Klik **"Enable"**

### C. Setup Database Rules
1. Di Realtime Database, buka tab **"Rules"**
2. Ganti dengan rules berikut:

```json
{
  "rules": {
    "eldn": {
      "korban": {
        ".read": true,
        ".write": true,
        "$id": {
          ".validate": "newData.hasChildren(['lat', 'lng'])",
          "lat": {
            ".validate": "newData.isNumber()"
          },
          "lng": {
            ".validate": "newData.isNumber()"
          },
          "photoUrl": {
            ".validate": "newData.isString() || newData.val() == null"
          },
          "vibrationStatus": {
            ".validate": "newData.isString() || newData.val() == null"
          },
          "soundStatus": {
            ".validate": "newData.isString() || newData.val() == null"
          }
        }
      }
    }
  }
}
```

3. Klik **"Publish"**

---

## Langkah 2: Setup Android

### A. Download `google-services.json`
1. Di Firebase Console, buka **Project Settings** (gear icon)
2. Pilih tab **"Your apps"**
3. Pilih app Android Anda (atau create baru jika belum ada)
4. Download file `google-services.json`
5. Letakkan file di: `android/app/`

### B. Update Android Gradle
File `android/build.gradle.kts` (project level):

```kotlin
buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath 'com.android.tools.build:gradle:7.4.1'
        classpath 'org.jetbrains.kotlin:kotlin-gradle-plugin:1.8.10'
        classpath 'com.google.gms:google-services:4.3.15'  // Tambahkan ini
    }
}
```

File `android/app/build.gradle.kts` (app level):

```kotlin
plugins {
    id 'com.android.application'
    id 'kotlin-android'
    id 'com.google.gms.google-services'  // Tambahkan ini di bagian atas plugins
}

android {
    compileSdkVersion 34
    // ... rest of config
}

dependencies {
    // Firebase sudah akan included via FlutterFire
}
```

---

## Langkah 3: Setup iOS

### A. Download `GoogleService-Info.plist`
1. Di Firebase Console, buka **Project Settings**
2. Pilih app iOS Anda
3. Download `GoogleService-Info.plist`
4. Di Xcode, drag & drop file ke `ios/Runner` folder
5. Pastikan **"Copy items if needed"** dicheck

### B. Update iOS Podfile
File `ios/Podfile`, uncomment dan update section berikut:

```ruby
post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)
    target.build_configurations.each do |config|
      config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= [
        '$(inherited)',
        'FIREBASE_CORE_VERSION=M112',
      ]
    end
  end
end
```

---

## Langkah 4: Testing Firebase Connection

### A. Jalankan Flutter App
```bash
flutter pub get
flutter run
```

### B. Monitor Firebase
Jika berhasil, connection indicator di AppBar akan menunjukkan **🟢 hijau**.

---

## Langkah 5: Setup ESP32 untuk Mengirim Data

Update kode ESP32 dengan Firebase credentials:

```cpp
#define FIREBASE_HOST "YOUR_PROJECT.firebaseio.com"
#define FIREBASE_AUTH "YOUR_WEB_API_KEY"
```

Struktur data yang dikirim dari ESP32:

```json
{
  "eldn": {
    "korban": {
      "device_1": {
        "lat": -6.123456,
        "lng": 106.123456,
        "photoUrl": "https://...",
        "vibrationStatus": "DETECTED",
        "soundStatus": "HIGH"
      }
    }
  }
}
```

---

## Database Structure

Struktur Realtime Database yang diharapkan:

```
eldn/
└── korban/
    ├── korban_1/
    │   ├── lat: -6.123456
    │   ├── lng: 106.123456
    │   ├── photoUrl: "https://..."
    │   ├── vibrationStatus: "HIGH"
    │   └── soundStatus: "DETECTED"
    └── korban_2/
        ├── lat: -6.234567
        ├── lng: 106.234567
        └── ...
```

---

## Troubleshooting

### 1. Firebase Not Connected (Offline)
- Cek koneksi internet
- Pastikan `google-services.json` sudah di `android/app/`
- Run: `flutter clean` → `flutter pub get` → `flutter run`

### 2. Error: "Could not find google-services.json"
- Download dari Firebase Console
- Letakkan di `android/app/google-services.json`

### 3. iOS Build Error
- Run: `cd ios && pod install --repo-update`

### 4. Data Tidak Terlihat di Dashboard
- Pastikan data dikirim ke path `/eldn/korban/`
- Check Firebase Rules di console
- Verify data format (lat, lng harus number)

---

## Notes

- Mode **Test** firebase aman untuk development, tapi harus diubah ke **Production Rules** untuk production
- Setiap ESP32 bisa punya ID unik di database (contoh: `esp32_001`, `esp32_002`, dll)
- Photo bisa di-upload ke Firebase Storage atau URL eksternal

---

**Pertanyaan? Lihat dokumentasi resmi:**
- [Firebase Console](https://console.firebase.google.com/)
- [FlutterFire Documentation](https://firebase.flutter.dev/)
