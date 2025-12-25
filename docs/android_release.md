# Android Release Checklist (DayScript)

## 1) App icon / splash

1. Save the icon image as `assets/dayscript_app_icon.png` (1024×1024 recommended).
2. Generate icons:
   - `flutter pub run flutter_launcher_icons`
3. Generate splash:
   - `flutter pub run flutter_native_splash:create`

## 2) Versioning

- Update `pubspec.yaml`:
  - `version: x.y.z+buildNumber`

## 3) Signing (Play App Signing recommended)

### Create upload keystore (local only)

Example (Windows):
- `keytool -genkey -v -keystore %USERPROFILE%\\dayscript-upload.jks -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 -alias upload`

### Create `android/key.properties` (local only)

```
storeFile=C:\\Users\\<you>\\dayscript-upload.jks
storePassword=YOUR_STORE_PASSWORD
keyPassword=YOUR_KEY_PASSWORD
keyAlias=upload
```

`android/key.properties` is git-ignored.

## 4) Build AAB

- `flutter build appbundle --release`

## 5) Play Console

- Create app → upload AAB → internal test → production
- Fill in:
  - App name / short description / full description
  - Screenshots (phone)
  - Privacy policy URL
  - Data safety (Firebase + Ad ingestion)
  - Content rating

