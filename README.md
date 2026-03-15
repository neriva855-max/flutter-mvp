# Flutter MVP App

A simple mobile app with user authentication and a map that shows your current location.

## Backend (FastAPI)

Run the backend first so the app can sign up and log in.

### 1. Install backend dependencies

```bash
cd backend
pip install -r requirements.txt
```

### 2. Start the backend

```bash
uvicorn main:app --reload
```

The API runs at `http://localhost:8000`. To use it from a phone or emulator, use your laptop's IP and port `8000` (see **Backend URL** below).

---

## Flutter app

### 1. Install dependencies

```bash
cd mobile/flutter_app
flutter pub get
```

### 2. Run the app

```bash
flutter run
```

Choose an Android or iOS device/emulator when prompted.

---

## Required setup: replace placeholders

You must replace two placeholders before the app works end-to-end.

### 1. Google Maps API key

The map screen needs a Google Maps API key.

- Create a key in [Google Cloud Console](https://console.cloud.google.com/):
  - Enable **Maps SDK for Android** and **Maps SDK for iOS** for your project.
  - Create an API key (Credentials → Create credentials → API key).
- Replace **`YOUR_GOOGLE_MAPS_API_KEY_HERE`** with this key in **all** of these files:

| Platform | File | What to do |
|----------|------|------------|
| Android | `android/app/src/main/AndroidManifest.xml` | Find the `<meta-data>` with `com.google.android.geo.API_KEY` and set `android:value="YOUR_ACTUAL_KEY"`. |
| iOS | `ios/Runner/AppDelegate.swift` | Find `GMSServices.provideAPIKey("YOUR_GOOGLE_MAPS_API_KEY_HERE")` and replace the string with your key. |

Without a valid key, the map may not load or may show a blank/broken map.

### 2. Backend URL (your laptop IP)

The app talks to the FastAPI backend over HTTP. You must set the backend base URL to your machine’s IP (and port) so that a physical device or emulator can reach it.

- Open **`lib/services/api_service.dart`**.
- Find the line:
  ```dart
  const String BASE_URL = 'http://YOUR_LAPTOP_IP_HERE:8000';
  ```
- Replace **`YOUR_LAPTOP_IP_HERE`** with:
  - **Android emulator:** use **`10.0.2.2`** (this is the emulator’s alias for your host machine’s `localhost`).
  - **Physical device or iOS simulator:** use your laptop’s local IP (e.g. `192.168.1.100`). Find it with:
    - macOS/Linux: `ifconfig` or `ip addr`
    - Windows: `ipconfig`

Examples:

- Android emulator: `http://10.0.2.2:8000`
- Phone on same Wi‑Fi (e.g. laptop IP 192.168.1.100): `http://192.168.1.100:8000`

Make sure the backend is running (`uvicorn main:app --reload`) and that your firewall allows incoming connections on port 8000.

---

## Summary checklist

- [ ] Backend: `pip install -r requirements.txt` and `uvicorn main:app --reload`
- [ ] Flutter: `flutter pub get` and `flutter run`
- [ ] Replace **Google Maps API key** in `AndroidManifest.xml` and `AppDelegate.swift`
- [ ] Replace **backend URL** in `lib/services/api_service.dart` (use `10.0.2.2` for Android emulator, or your laptop IP for device/simulator)
