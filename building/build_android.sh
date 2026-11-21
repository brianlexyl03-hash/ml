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
python -m compileall -q app.py main.py scihub_eva
python building/convert_i18n_zh.py
pyside6-lrelease i18n/SciHubEVA_*.ts
# Qt for Android is built without zstd resource support.
pyside6-rcc --no-compress SciHubEVA.qrc -o scihub_eva/resources.py

echo "Downloading matching PySide6 and Shiboken6 Android ARM64 wheels..."
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

echo "Generating the Qt deployment recipes and Buildozer configuration..."
pyside6-android-deploy --init \
    --name SciHubEVA \
    --wheel-pyside="$PYSIDE_WHEEL" \
    --wheel-shiboken="$SHIBOKEN_WHEEL" \
    --ndk-path="$NDK_PATH" \
    --sdk-path="$SDK_PATH" \
    --force --keep-deployment-files

echo "Adding the app's Python requirements and Android metadata..."
python - <<'PY'
import configparser
from pathlib import Path

spec_path = Path("buildozer.spec")
if not spec_path.is_file():
    raise SystemExit("pyside6-android-deploy did not generate buildozer.spec")

spec = configparser.ConfigParser(interpolation=None)
spec.optionxform = str
spec.read(spec_path, encoding="utf-8")
if "app" not in spec:
    raise SystemExit("Generated buildozer.spec has no [app] section")

app = spec["app"]
requirements = [
    item.strip()
    for item in app.get("requirements", "").split(",")
    if item.strip()
]
additional = [
    "requests",
    "urllib3",
    "idna",
    "certifi",
    "charset-normalizer",
    "PySocks",
    "lxml",
    "pdfminer.six",
    "pathvalidate",
    "darkdetect",
    "cryptography",
    "cffi",
    "pycparser",
]
seen = {item.lower() for item in requirements}
requirements.extend(item for item in additional if item.lower() not in seen)
app["requirements"] = ",".join(requirements)

app["title"] = "SciHubEVA"
app["package.name"] = "scihubeva"
app["package.domain"] = "io.github.brianlexyl03hash"
app["version"] = "6.5.1"
app["orientation"] = "portrait"
app["icon.filename"] = "images/SciHubEVA-icon.png"
app["source.exclude_dirs"] = ".git,building,design,tests,dist,artifacts,.github"
app["android.permissions"] = "INTERNET"
app["android.api"] = "35"
app["android.minapi"] = "28"
app["android.archs"] = "arm64-v8a"
app["android.accept_sdk_license"] = "True"
app["android.skip_update"] = "True"
app["android.allow_backup"] = "False"

with spec_path.open("w", encoding="utf-8") as output:
    spec.write(output)

print("Android requirements:", app["requirements"])
PY

echo "Building the ARM64 debug APK with Buildozer..."
export VIRTUAL_ENV="${VIRTUAL_ENV:-$(python -c 'import sys; print(sys.prefix)')}"
export PATH="$(dirname "$(command -v python)"):$PATH"
python -m buildozer android debug

APK_PATH="$(find "$ROOT_DIR" -type f -name '*.apk' -not -path '*/.git/*' -print -quit)"
if [[ -z "$APK_PATH" ]]; then
    echo "Buildozer completed without producing an APK." >&2
    exit 1
fi
mkdir -p "$ROOT_DIR/artifacts"
cp "$APK_PATH" "$ROOT_DIR/artifacts/SciHubEVA-android-arm64-debug.apk"
echo "APK created: artifacts/SciHubEVA-android-arm64-debug.apk"
