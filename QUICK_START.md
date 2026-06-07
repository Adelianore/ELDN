# 🚀 ELDN Dashboard - Quick Start Guide

## 5 Menit Setup

### 1️⃣ Firebase Console (2 menit)
1. Go: https://console.firebase.google.com
2. **Create project** → Name it "ELDN"
3. **Realtime Database** → Create → Test Mode → Indonesia region
4. **Project Settings** (gear icon) → Your apps → Android
5. **Download** `google-services.json` → Paste ke `android/app/`
6. Copy **Database URL** (contoh: `https://eldn-abc123.firebaseio.com`)

### 2️⃣ Update Flutter Code (1 menit)
Edit `lib/config/firebase_config.dart`:
```dart
static const String databaseUrl = 'https://YOUR_PROJECT.firebaseio.com';
```

### 3️⃣ Run Flutter (1 menit)
```bash
cd c:\xampp\htdocs\OLIVIA
flutter pub get
flutter run
```

### 4️⃣ Update ESP32 (1 menit)
Edit `ESP32_FIREBASE_CODE.ino`:
```cpp
#define FIREBASE_HOST "eldn-abc123.firebaseio.com"
#define FIREBASE_AUTH "YOUR_WEB_API_KEY"
```
Upload to ESP32

---

## ✅ Verify Setup

- [ ] Firebase status di app: **🟢 Connected**
- [ ] ESP32 Serial Monitor: **"✅ Koneksi Firebase Berhasil"**
- [ ] Firebase Console: Bisa lihat data korban masuk

---

## 🆘 If Something Wrong

| Error | Fix |
|-------|-----|
| ❌ Firebase offline | Check internet + run `flutter clean` |
| ❌ google-services.json not found | Download dari Firebase Console ke `android/app/` |
| ❌ App can't connect | Check `databaseUrl` di firebase_config.dart |

---

## 📖 Full Guide

- **Setup Detail**: Read `FIREBASE_SETUP.md`
- **All Changes**: Read `UPDATE_SUMMARY.md`
- **ESP32 Code**: Check `ESP32_FIREBASE_CODE.ino`

---

**Done! Dashboard siap digunakan.** 🎉
