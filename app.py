import multiprocessing
import sys
import traceback
from pathlib import Path

from PySide6.QtCore import QCoreApplication, QStandardPaths, QTranslator
from PySide6.QtGui import QGuiApplication, QIcon

from scihub_eva.globals.preferences import APPEARANCE_LANGUAGE_KEY
from scihub_eva.globals.versions import (
    APPLICATION_NAME,
    ORGANIZATION_DOMAIN,
    ORGANIZATION_NAME,
)
from scihub_eva.utils.preferences_utils import Preferences
from scihub_eva.utils.sys_utils import SYSTEM_LANGUAGE
from scihub_eva.utils.ui_utils import set_ui_env


def _install_startup_crash_logger() -> None:
    previous_hook = sys.excepthook

    def write_crash_log(exc_type, exc_value, exc_traceback) -> None:
        try:
            app_data = QStandardPaths.writableLocation(
                QStandardPaths.StandardLocation.AppDataLocation
            )
            if app_data:
                log_path = Path(app_data) / 'startup-crash.log'
                log_path.parent.mkdir(parents=True, exist_ok=True)
                with log_path.open('a', encoding='utf-8') as crash_log:
                    crash_log.write('\\n--- EVA startup failure ---\\n')
                    traceback.print_exception(
                        exc_type, exc_value, exc_traceback, file=crash_log
                    )
        except Exception:
            pass
        previous_hook(exc_type, exc_value, exc_traceback)

    sys.excepthook = write_crash_log


def main() -> None:
    multiprocessing.freeze_support()

    QCoreApplication.setOrganizationName(ORGANIZATION_NAME)
    QCoreApplication.setOrganizationDomain(ORGANIZATION_DOMAIN)
    QCoreApplication.setApplicationName(APPLICATION_NAME)

    # Qt reads several Quick Controls settings during application startup.
    set_ui_env()

    app = QGuiApplication(sys.argv)
    _install_startup_crash_logger()

    # Import path-dependent application modules only after QGuiApplication
    # exists. Android's QStandardPaths needs the application identity above.
    import scihub_eva.resources
    from scihub_eva.ui.main import UISciHubEVA

    lang = Preferences.get_or_default(APPEARANCE_LANGUAGE_KEY, SYSTEM_LANGUAGE)
    translator = QTranslator()
    if translator.load(':/i18n/SciHubEVA_{lang}.qm'.format(lang=lang)):
        app.installTranslator(translator)

    app.setWindowIcon(QIcon(':/images/SciHubEVA-icon.png'))

    UISciHubEVA()
    sys.exit(app.exec())


if __name__ == '__main__':
    main()
