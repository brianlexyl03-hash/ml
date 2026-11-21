import os
from pathlib import Path

from PySide6.QtCore import QStandardPaths

from scihub_eva.globals.versions import APPLICATION_NAME, ORGANIZATION_DOMAIN
from scihub_eva.utils.sys_utils import is_android, is_linux, is_macos, is_windows


def _logs_dir():
    if is_android():
        logs_dir_path = APP_DATA_DIR / 'logs'
    elif is_macos():
        logs_dir_path = (
            Path.home() / 'Library' / 'Logs/' / ORGANIZATION_DOMAIN / APPLICATION_NAME
        )
    elif is_windows():
        logs_dir_path = (
            Path.home()
            / 'AppData'
            / 'Local/'
            / ORGANIZATION_DOMAIN
            / APPLICATION_NAME
            / 'logs'
        )
    elif is_linux():
        logs_dir_path = (
            Path.home()
            / '.local'
            / 'share/'
            / ORGANIZATION_DOMAIN
            / APPLICATION_NAME
            / 'logs'
        )
    else:
        logs_dir_path = BASE_DIR / 'logs'

    if not logs_dir_path.exists():
        logs_dir_path.mkdir(parents=True)

    return logs_dir_path


BASE_DIR = Path(os.path.dirname(__file__)) / '../..'

if is_android():
    app_data_location = QStandardPaths.writableLocation(
        QStandardPaths.StandardLocation.AppDataLocation
    )
    APP_DATA_DIR = Path(app_data_location) if app_data_location else Path.home() / 'SciHubEVA'
    APP_DATA_DIR.mkdir(parents=True, exist_ok=True)
else:
    APP_DATA_DIR = BASE_DIR

CONFS_DIR = BASE_DIR / 'confs'
I18N_DIR = BASE_DIR / 'i18n'
IMAGES_DIR = BASE_DIR / 'images'
LOGS_DIR = _logs_dir()
UI_DIR = BASE_DIR / 'ui'


__all__ = [
    'BASE_DIR',
    'APP_DATA_DIR',
    'CONFS_DIR',
    'I18N_DIR',
    'IMAGES_DIR',
    'UI_DIR',
    'LOGS_DIR',
]
