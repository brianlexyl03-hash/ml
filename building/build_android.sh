#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER_TMP="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
CACHE_DIR="$HOME/.pyside6_android_deploy"
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
])
PY
python -m compileall -q app.py main.py scihub_eva
python building/convert_i18n_zh.py
pyside6-lrelease i18n/SciHubEVA_*.ts
# Qt for Android is built without zstd resource support.
pyside6-rcc --no-compress SciHubEVA.qrc -o scihub_eva/resources.py

echo "Downloading the official Qt for Python Android ARM64 wheels..."
mkdir -p "$WHEEL_DIR"
PYSIDE_WHEEL="$WHEEL_DIR/pyside6-6.12.0-6.12.0-cp310-abi3-android_aarch64.whl"
SHIBOKEN_WHEEL="$WHEEL_DIR/shiboken6-6.12.0-6.12.0-cp310-abi3-android_aarch64.whl"
curl --fail --location --retry 3 --output "$PYSIDE_WHEEL" \
    "https://download.qt.io/official_releases/QtForPython/pyside6/pyside6-6.12.0-6.12.0-cp310-abi3-android_aarch64.whl"
curl --fail --location --retry 3 --output "$SHIBOKEN_WHEEL" \
    "https://download.qt.io/official_releases/QtForPython/shiboken6/shiboken6-6.12.0-6.12.0-cp310-abi3-android_aarch64.whl"


echo "Preparing the official Qt Android SDK/NDK toolchain..."
if [[ ! -d "$CACHE_DIR" ]] || [[ -z "$(find "$CACHE_DIR" -type d -name 'android-ndk-r28c' -print -quit)" ]]; then
    git clone --depth 1 --branch 6.12 https://code.qt.io/pyside/pyside-setup "$TOOLCHAIN_DIR"
    python -m pip install \
        -r "$TOOLCHAIN_DIR/requirements.txt" \
        -r "$TOOLCHAIN_DIR/tools/cross_compile_android/requirements.txt"
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

echo "Installing the Qt Android deployment tool requirements..."
PYSIDE_ANDROID_REQUIREMENTS="$(python - <<'PY'
from pathlib import Path
import PySide6
print(Path(PySide6.__file__).parent / "scripts" / "requirements-android.txt")
PY
)"
python -m pip install -r "$PYSIDE_ANDROID_REQUIREMENTS"

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
    "requests==2.32.5",
    "urllib3==2.6.3",
    "idna==3.20",
    "certifi==2026.11.20",
    "charset-normalizer==3.5.2",
    "PySocks==1.7.1",
    "lxml==6.0.2",
    "pdfminer.six==20260107",
    "pathvalidate==3.3.1",
]
seen = {item.lower() for item in requirements}
requirements.extend(item for item in additional if item.lower() not in seen)
app["requirements"] = ",".join(requirements)

app["title"] = "EVA"
app["package.name"] = "scihubeva"
app["package.domain"] = "io.github.brianlexyl03hash"
app["version"] = "6.5.1"
app["orientation"] = "portrait"
app["icon.filename"] = "images/SciHubEVA-icon.png"
app["source.exclude_dirs"] = ".git,building,design,docs,tests,dist,artifacts,.github,deployment,bin,.buildozer"
app["source.exclude_patterns"] = "scihub_eva/api/scihub_fake_server.py,*.pyc,*.pyo"
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
