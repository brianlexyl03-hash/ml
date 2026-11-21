import multiprocessing
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

    lang = Preferences.get_or_default(APPEARANCE_LANGUAGE_KEY, SYSTEM_LANGUAGE)
    translator = QTranslator()
    if translator.load(':/i18n/SciHubEVA_{lang}.qm'.format(lang=lang)):
        app.installTranslator(translator)

    app.setWindowIcon(QIcon(':/images/SciHubEVA-icon.png'))

    UISciHubEVA()
    sys.exit(app.exec())


if __name__ == '__main__':
    main()
