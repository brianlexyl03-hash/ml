#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER_TMP="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
CACHE_DIR="$HOME/.pyside6-android-deploy"
WHEEL_DIR="$RUNNER_TMP/scihubeva-android-wheels"
TOOLCHAIN_DIR="$RUNNER_TMP/pyside-setup"

cd "$ROOT_DIR"

echo "Preparing Python dependencies and Qt resource files..."
python -m pip install --upgrade pip
python - <<'PY'
import subprocess
import sys
import tomllib

with open("pyproject.toml", "rb") as project_file:
    dependencies = tomllib.load(project_file)["project"]["dependencies"]

subprocess.check_call([
    sys.executable, "-m", "pip", "install",
    *dependencies,
    "opencc-python-reimplemented==0.1.7",
    "qtpip",
])
PY
python building/convert_i18n_zh.py
pyside6-lrelease i18n/SciHubEVA_*.ts
pyside6-rcc SciHubEVA.qrc -o scihub_eva/resources.py

echo "Downloading the matching PySide6 Android ARM64 wheels..."
mkdir -p "$WHEEL_DIR"
(
    cd "$WHEEL_DIR"
    qtpip download PySide6 --android --arch aarch64
    qtpip download shiboken6 --android --arch aarch64
)
PYSIDE_WHEEL="$(find "$WHEEL_DIR" -type f -iname 'PySide6-*-android_aarch64.whl' -print -quit)"
SHIBOKEN_WHEEL="$(find "$WHEEL_DIR" -type f -iname 'shiboken6-*-android_aarch64.whl' -print -quit)"
if [[ -z "$PYSIDE_WHEEL" || -z "$SHIBOKEN_WHEEL" ]]; then
    echo "Could not locate the matching PySide6/Shiboken6 Android wheels." >&2
    find "$WHEEL_DIR" -type f -print >&2
    exit 1
fi

echo "Preparing the official Qt Android SDK/NDK toolchain..."
if [[ ! -d "$CACHE_DIR" ]] || [[ -z "$(find "$CACHE_DIR" -type d -name 'android-ndk-r28c' -print -quit)" ]]; then
    git clone --depth 1 --branch 6.12 https://code.qt.io/pyside/pyside-setup "$TOOLCHAIN_DIR"
    python "$TOOLCHAIN_DIR/tools/cross_compile_android/main.py" \
        --download-only --skip-update --auto-accept-license
fi

NDK_PATH="$(find "$CACHE_DIR" -type d -name 'android-ndk-r28c' -print -quit)"
SDK_PLATFORM_TOOLS="$(find "$CACHE_DIR" -type d -name platform-tools -print -quit)"
if [[ -z "$NDK_PATH" || -z "$SDK_PLATFORM_TOOLS" ]]; then
    echo "Qt Android SDK/NDK cache is incomplete." >&2
    find "$CACHE_DIR" -maxdepth 4 -type d -print >&2 || true
    exit 1
fi
SDK_PATH="$(dirname "$SDK_PLATFORM_TOOLS")"

echo "Building SciHubEVA for Android arm64-v8a..."
pyside6-android-deploy main.py \
    --name SciHubEVA \
    --wheel-pyside="$PYSIDE_WHEEL" \
    --wheel-shiboken="$SHIBOKEN_WHEEL" \
    --ndk-path="$NDK_PATH" \
    --sdk-path="$SDK_PATH" \
    --force --keep-deployment-files

APK_PATH="$(find "$ROOT_DIR" -type f -name '*.apk' -not -path '*/.git/*' -print -quit)"
if [[ -z "$APK_PATH" ]]; then
    echo "Android deployment completed without producing an APK." >&2
    exit 1
fi
mkdir -p "$ROOT_DIR/artifacts"
cp "$APK_PATH" "$ROOT_DIR/artifacts/SciHubEVA-android-arm64-debug.apk"
echo "APK created: artifacts/SciHubEVA-android-arm64-debug.apk"
