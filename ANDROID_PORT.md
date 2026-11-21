# Android port status

This fork is being adapted for Android ARM64 while retaining the original
desktop application. The desktop build scripts and existing query engine remain
in place.

## Implemented in this fork

- [x] Add the `main.py` entry point required by Qt for Python's Android
  deployment tool; it delegates to the existing `app.main()`.
- [x] Add a phone-sized responsive layout for the main screen and CAPTCHA dialog.
- [x] Make the preferences navigation fit a phone screen.
- [x] Resolve Android app-private storage after Qt application initialization.
- [x] Use an app-private Downloads directory as the default Android PDF location.
- [x] Add Android document-URI read/write handling for batch-list import and
  failed-query export.
- [x] Bundle compiled translations and the application icon in Qt resources.
- [x] Enable TLS certificate verification in the requests layer.
- [x] Add an ARM64 Android build script and a GitHub Actions workflow that
  produces an APK artifact when the build succeeds.
- [x] Patch the Qt Android loader to load QtCore before QtQuick so QtCore's
  `JNI_OnLoad` caches the JavaVM before QtQuick requests a JNI environment.
- [x] Publish successful APK builds as a stable GitHub Release download with
  SHA-256 checksums.

## Not yet verified

- [ ] Confirm every runtime dependency builds and runs in the Android
  python-for-android environment, especially lxml and pdfminer.six.
- [ ] Complete a successful GitHub Actions Android build.
- [ ] Install the APK and exercise queries, downloads, batch import/export,
  CAPTCHA, preferences, proxy settings, and log access on a physical ARM64
  device.
- [ ] Verify rotation, keyboard behavior, touch targets, and Android file
  provider behavior on the target device.
- [ ] Produce and test a signed release APK.
- [ ] Install and launch the QtCore-first build on the Redmi Android 16 device.
- [ ] Produce a signed Play Store AAB and complete Google Play policy review.

## Build setup

The project uses PySide6 6.12.0 so the Android deployment tool and matching
Android PySide6/Shiboken wheels use the same Qt release. The Android build
script:

1. Installs the project dependencies and translation tools.
2. Compiles the translations and Qt resource collection.
3. Downloads matching Android ARM64 PySide6 and Shiboken wheels.
4. Downloads the Qt Android SDK/NDK toolchain (NDK r28c).
5. Runs `pyside6-android-deploy` and stages the resulting debug APK.

Run the build on Linux with:

```bash
./building/build_android.sh
```

Or run the **Android ARM64 APK** workflow from GitHub Actions. A successful
workflow uploads the APK and, when the release build succeeds, an Android App
Bundle. The APK is published at:

`https://github.com/brianlexyl03-hash/ml/releases/download/android-latest/EVA-android-arm64.apk`

For signed Play Store bundles, configure these repository Actions secrets:
`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`,
and `ANDROID_KEY_ALIAS_PASSWORD`. Without them, the workflow can produce an
unsigned AAB for inspection, but it cannot be uploaded to Play Console.

Qt's deployment tool requires a Unix build host, Python 3.10–3.14, a supported
JDK, Android SDK/NDK, and matching Android PySide6/Shiboken wheels. Current Qt
6.12 deployment uses NDK r28c for 16 KB page-size compatibility.

## Feature-preservation requirements

The Android build must retain, or provide a clearly documented Android-native
equivalent for:

- single URL, PMID, DOI, and title queries;
- range queries and text-file batch queries;
- filename formatting and overwrite behavior;
- failed-query export and logs;
- API URL and XPath preferences;
- language and light/dark/system appearance preferences;
- timeout, retry, and proxy preferences;
- user-entered CAPTCHA where supported by an authorized service.

Android currently saves PDFs to the app-private Downloads directory by default.
This is not the same as a user-selected public Downloads folder. The Android
storage/export workflow must be tested and improved before claiming full
storage-feature parity with desktop.

## Security and access behavior

TLS certificate verification stays enabled. Access-control or anti-bot
responses are reported as failures; the Android port does not add mechanisms to
evade those controls. CAPTCHA support is for user-entered verification on
services the user is authorized to access.

## Release rule

Do not publish an APK as ready until the Android build succeeds, the APK
installs on a physical ARM64 device, and the feature checks above have been
exercised.
