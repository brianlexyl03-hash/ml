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

echo "Using the Android SDK platform installed by the official Qt toolchain..."
# The Qt 6.12 Android toolchain currently provisions API 35. Avoid a second
# sdkmanager bootstrap here: it aborts in GitHub Actions with a broken-pipe
# license prompt before the application build even starts.
if [[ ! -d "$SDK_PATH/platforms/android-35" ]]; then
    echo "Required Android SDK platform 35 is missing from $SDK_PATH." >&2
    exit 1
fi

echo "Stripping native debug symbols from the Android wheels to reduce APK size..."
LLVM_STRIP="$(find "$NDK_PATH/toolchains/llvm/prebuilt" -name llvm-strip -print -quit)"
if [[ -z "$LLVM_STRIP" ]]; then
    echo "Could not locate the NDK llvm-strip utility." >&2
    exit 1
fi
python - "$LLVM_STRIP" "$PYSIDE_WHEEL" "$SHIBOKEN_WHEEL" <<'PY'
import base64
import csv
import hashlib
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

strip_tool, *wheel_paths = sys.argv[1:]

for wheel_path in wheel_paths:
    wheel = Path(wheel_path)
    with tempfile.TemporaryDirectory(prefix="eva-wheel-") as temporary:
        root = Path(temporary)
        with zipfile.ZipFile(wheel) as archive:
            archive.extractall(root)

        stripped = 0
        for native_library in root.rglob("*.so"):
            subprocess.run(
                [strip_tool, "--strip-unneeded", str(native_library)],
                check=True,
                stdout=subprocess.DEVNULL,
            )
            stripped += 1

        record_path = next(root.glob("*.dist-info/RECORD"))
        rows = []
        for file_path in sorted(root.rglob("*")):
            if not file_path.is_file():
                continue
            relative = file_path.relative_to(root).as_posix()
            if file_path == record_path:
                rows.append((relative, "", ""))
                continue
            digest = base64.urlsafe_b64encode(
                hashlib.sha256(file_path.read_bytes()).digest()
            ).decode("ascii").rstrip("=")
            rows.append((relative, "sha256=" + digest, str(file_path.stat().st_size)))

        with record_path.open("w", encoding="utf-8", newline="") as record_file:
            csv.writer(record_file, lineterminator="\n").writerows(rows)

        rebuilt = wheel.with_suffix(".stripped.whl")
        with zipfile.ZipFile(rebuilt, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
            for file_path in sorted(root.rglob("*")):
                if file_path.is_file():
                    archive.write(file_path, file_path.relative_to(root).as_posix())
        rebuilt.replace(wheel)
        print(f"Stripped {stripped} native libraries in {wheel.name}")
PY

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
    "cryptography==46.0.3",
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
app["version"] = "6.5.2"
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
# Pin python-for-android to the upstream fix for its broken pip self-upgrade.
app["p4a.branch"] = "develop"
app["p4a.commit"] = "0382d27de2f7315ed98e74884bafb30365decdee"

with spec_path.open("w", encoding="utf-8") as output:
    spec.write(output)

print("Android requirements:", app["requirements"])
PY

echo "Preparing the Qt Android bootstrap with the pinned python-for-android fix..."

echo "Adding a pure-Python pdfminer.six recipe to avoid its Android pip resolver conflict..."
python - <<'PY'
from pathlib import Path

p4a_root = Path(".buildozer/android/platform/python-for-android")
recipe_dir = Path("deployment/recipes/pdfminer.six")
recipe_dir.mkdir(parents=True, exist_ok=True)
recipe = """from pythonforandroid.recipe import PythonRecipe


class PdfminerSixRecipe(PythonRecipe):
    name = "pdfminer.six"
    version = "20260107"
    url = "https://files.pythonhosted.org/packages/34/a4/5cec1112009f0439a5ca6afa8ace321f0ab2f48da3255b7a1c8953014670/pdfminer_six-20260107.tar.gz"
    depends = ["python3"]
    python_depends = ["charset-normalizer"]
    site_packages_name = "pdfminer"
    hostpython_prerequisites = ["setuptools", "setuptools-scm"]
    setup_extra_args = ["--no-deps", "--no-build-isolation"]


recipe = PdfminerSixRecipe()
"""
(recipe_dir / "__init__.py").write_text(recipe, encoding="utf-8")
print(f"Installed local recipe: {recipe_dir}")
PY

# Start from a clean distribution so the pinned p4a source is used.
rm -rf "$ROOT_DIR/.buildozer/android/platform/build-arm64-v8a/dists/scihubeva"
export VIRTUAL_ENV="${VIRTUAL_ENV:-$(python -c 'import sys; print(sys.prefix)')}"
export PATH="$(dirname "$(command -v python)"):$PATH"
python -m buildozer android update

echo "Patching Qt bootstrap library order so QtCore initializes before QtQuick..."
python - <<'PY'
from pathlib import Path

search_roots = [
    Path.cwd() / ".buildozer",
    Path.home() / ".buildozer",
]
templates = []
for base in search_roots:
    if base.exists():
        templates.extend(base.rglob("libs.tmpl.xml"))

templates = [
    path for path in templates
    if "bootstraps/qt/build/templates/libs.tmpl.xml" in path.as_posix()
]
if not templates:
    raise SystemExit(
        "Qt bootstrap libs.tmpl.xml was not found after 'buildozer android update'; "
        "refusing to build without the QtCore-first JNI initialization fix."
    )

needle = """    <array name="qt_libs">
        <item>{{ arch }};c++_shared</item>
        {%- for qt_lib in qt_libs %}
"""
replacement = """    <array name="qt_libs">
        <item>{{ arch }};c++_shared</item>
        <!-- QtCore JNI_OnLoad caches JavaVM; it must run before QtQuick. -->
        <item>{{ arch }};Qt6Core_{{ arch }}</item>
        {%- for qt_lib in qt_libs if qt_lib != "Core" %}
"""
patched = 0
for path in templates:
    source = path.read_text(encoding="utf-8")
    if "Qt6Core_{{ arch }}" in source:
        patched += 1
        continue
    if needle not in source:
        continue
    path.write_text(source.replace(needle, replacement, 1), encoding="utf-8")
    patched += 1

if not patched:
    raise SystemExit(
        "Qt bootstrap template was found, but its qt_libs block differed; "
        "refusing an unsafe patch."
    )
print(f"Applied QtCore-first library ordering to {patched} Qt bootstrap template(s).")
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
echo "Building the Play Store Android App Bundle..."
if [[ -n "${ANDROID_KEYSTORE_BASE64:-}" ]]; then
    KEYSTORE_PATH="$RUNNER_TMP/eva-upload-key.jks"
    printf '%s' "$ANDROID_KEYSTORE_BASE64" | base64 --decode > "$KEYSTORE_PATH"
    export P4A_RELEASE_KEYSTORE="$KEYSTORE_PATH"
    export P4A_RELEASE_KEYSTORE_PASSWD="${ANDROID_KEYSTORE_PASSWORD:?Missing ANDROID_KEYSTORE_PASSWORD secret}"
    export P4A_RELEASE_KEYALIAS="${ANDROID_KEY_ALIAS:?Missing ANDROID_KEY_ALIAS secret}"
    export P4A_RELEASE_KEYALIAS_PASSWD="${ANDROID_KEY_ALIAS_PASSWORD:?Missing ANDROID_KEY_ALIAS_PASSWORD secret}"
    echo "Using the configured Android upload key to sign the AAB."
else
    echo "No upload key configured; the AAB will be unsigned and cannot be uploaded to Play Console yet."
fi
if python -m buildozer android release; then
    AAB_PATH="$(find "$ROOT_DIR/bin" -type f -name '*.aab' -print -quit)"
    if [[ -n "$AAB_PATH" ]]; then
        cp "$AAB_PATH" "$ROOT_DIR/artifacts/EVA-android-arm64-unsigned.aab"
        echo "AAB created: artifacts/EVA-android-arm64-unsigned.aab"
    else
        echo "Buildozer release completed without an AAB; APK remains available." >&2
    fi
else
    echo "AAB build failed; preserving the successful debug APK." >&2
fi
