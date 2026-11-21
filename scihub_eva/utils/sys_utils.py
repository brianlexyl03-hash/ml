import locale
import os
import platform
import subprocess
import sys
from pathlib import Path
from tempfile import NamedTemporaryFile

from PySide6.QtCore import QFile, QIODevice, QUrl, qVersion
from PySide6.QtGui import QDesktopServices

DEFAULT_ENCODING = 'utf-8'
SYSTEM_LANGUAGE = locale.getdefaultlocale()[0]

PYTHON_VERSION = '.'.join(str(v) for v in sys.version_info[:3])
QT_VERSION = qVersion()


def is_windows() -> bool:
    return platform.system() == 'Windows'


def is_macos() -> bool:
    return platform.system() == 'Darwin'


def is_android() -> bool:
    return sys.platform == 'android' or 'ANDROID_ARGUMENT' in os.environ


def is_linux() -> bool:
    return platform.system() == 'Linux' and not is_android()


def open_file(file_path: str, timeout: int = 3) -> None:
    if is_android():
        QDesktopServices.openUrl(QUrl.fromLocalFile(str(file_path)))
    elif is_windows():
        os.startfile(file_path)  # type: ignore
    elif is_macos():
        subprocess.call(['open', file_path], timeout=timeout)
    elif is_linux():
        subprocess.call(['xdg-open', file_path], timeout=timeout)
    else:
        return


def open_directory(directory: str, timeout: int = 3) -> None:
    if is_android():
        QDesktopServices.openUrl(QUrl.fromLocalFile(str(directory)))
    elif is_windows():
        subprocess.call(['explorer', str(Path(directory))], timeout=timeout)
    elif is_macos():
        subprocess.call(['open', directory], timeout=timeout)
    elif is_linux():
        subprocess.call(['xdg-open', directory], timeout=timeout)
    else:
        return


def copy_content_uri_to_temp_file(uri: str) -> str:
    """Copy a user-selected Android document URI into app-readable temp storage."""
    if not is_android():
        return uri
    if uri.startswith('file://'):
        return QUrl(uri).toLocalFile()
    if not uri.startswith('content://'):
        return uri

    source = QFile(uri)
    if not source.open(QIODevice.OpenModeFlag.ReadOnly):
        raise OSError(source.errorString())

    try:
        contents = bytes(source.readAll())
    finally:
        source.close()

    with NamedTemporaryFile(mode='wb', suffix='.txt', delete=False) as temp_file:
        temp_file.write(contents)
        return temp_file.name


def write_text_file(path: str, contents: str) -> None:
    """Write text to a local path or an Android Storage Access Framework URI."""
    if is_android() and path.startswith('file://'):
        path = QUrl(path).toLocalFile()

    if is_android() and path.startswith('content://'):
        target = QFile(path)
        mode = QIODevice.OpenModeFlag.WriteOnly | QIODevice.OpenModeFlag.Truncate
        if not target.open(mode):
            raise OSError(target.errorString())
        try:
            written = target.write(contents.encode('utf-8'))
            if written < 0:
                raise OSError(target.errorString())
        finally:
            target.close()
        return

    with open(path, 'wt', encoding='utf-8') as output_file:
        output_file.write(contents)


def is_text_file(path: str) -> bool:
    try:
        with open(path, 'rt') as f:
            f.readlines()
    except:
        return False

    return True


__all__ = [
    'DEFAULT_ENCODING',
    'SYSTEM_LANGUAGE',
    'PYTHON_VERSION',
    'QT_VERSION',
    'is_windows',
    'is_macos',
    'is_linux',
    'is_android',
    'copy_content_uri_to_temp_file',
    'write_text_file',
    'open_file',
    'open_directory',
    'is_text_file',
]
