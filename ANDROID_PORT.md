# Android port status

This fork is being prepared for an Android build while retaining the existing
desktop application and its features.

## Current state

- [x] Add the `main.py` entry point required by Qt for Python's Android
  deployment tool. It delegates to the existing `app.main()`; desktop startup
  remains unchanged.
- [ ] Verify every runtime dependency has an Android-compatible recipe/wheel.
- [ ] Adapt file selection and save destinations to Android's storage model.
- [ ] Adapt log export and open-file/open-directory actions for Android.
- [ ] Verify QML layouts, dialogs, keyboard behavior, and screen rotation on a
  physical ARM64 device.
- [ ] Build, install, and test a signed/release APK.

## Important build constraints

The project currently pins PySide6 6.10.2 and also depends on lxml, pdfminer.six,
pathvalidate, PySocks, requests, and urllib3. A successful desktop install does
not prove these packages can be built for Android. The Android Qt wheels must
match the Qt/PySide version used by the application. Do not silently upgrade
the desktop dependency set just to make an Android build appear to work.

Qt's `pyside6-android-deploy` requires a Unix build host, Python 3.10+, JDK 17+,
Android SDK/NDK, and Android PySide6/Shiboken wheels. Current Qt documentation
specifies NDK r28c (28.2.13676358) for current Android deployment. The tool
expects the application entry point to be named `main.py`.

## Feature-preservation requirements

The Android port must retain, or provide a clearly documented Android-native
equivalent for:

- single URL, PMID, DOI, and title queries;
- range queries and text-file batch queries;
- selectable download destination and filename behavior;
- failed-query export and logs;
- API/XPath preferences;
- language and light/dark/system appearance preferences;
- timeout, retry, and proxy preferences;
- user-entered CAPTCHA where supported by an authorized service.

Desktop-only actions such as opening a directory in the operating system's
file manager need Android-specific replacements rather than being called
through `xdg-open`.

## Security and access behavior

TLS certificate verification must remain enabled. The upstream API code
currently passes `verify=False` to requests; this must be corrected and
regression-tested as part of the network layer work.

The Android port will not add mechanisms to evade anti-bot challenges or
access controls. CAPTCHA support, where retained, is for user-entered
verification on services the user is authorized to access.

## Release rule

Do not publish an APK as ready until the Android build succeeds, the APK installs
on a physical ARM64 device, and the feature checks above have been exercised.
