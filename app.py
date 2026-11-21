import multiprocessing
import os
import sys

from PySide6.QtCore import QCoreApplication, QTranslator
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


def main() -> None:
    multiprocessing.freeze_support()

    QCoreApplication.setOrganizationName(ORGANIZATION_NAME)
    QCoreApplication.setOrganizationDomain(ORGANIZATION_DOMAIN)
    QCoreApplication.setApplicationName(APPLICATION_NAME)

    # Qt reads several Quick Controls settings during application startup.
    set_ui_env()

    app = QGuiApplication(sys.argv)

    # Import path-dependent application modules only after QGuiApplication
    # exists. Android's QStandardPaths needs the application identity above.
    import scihub_eva.resources
    from scihub_eva.ui.main import UISciHubEVA
    from scihub_eva.utils.path_utils import I18N_DIR, IMAGES_DIR

    lang = Preferences.get_or_default(APPEARANCE_LANGUAGE_KEY, SYSTEM_LANGUAGE)
    lang_file_path = (
        (I18N_DIR / 'SciHubEVA_{lang}.qm'.format(lang=lang)).resolve().as_posix()
    )

    if os.path.exists(lang_file_path):
        translator = QTranslator()
        translator.load(lang_file_path)
        app.installTranslator(translator)

    icon_file_path = (IMAGES_DIR / 'SciHubEVA-icon.png').resolve().as_posix()
    app.setWindowIcon(QIcon(icon_file_path))

    UISciHubEVA()
    sys.exit(app.exec())


if __name__ == '__main__':
    main()
