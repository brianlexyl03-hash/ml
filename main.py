"""Android-compatible entry point for the PySide6 deployment tool.

The desktop application historically starts from app.py. Qt's
pyside6-android-deploy expects the Python entry point to be named main.py,
so this thin shim preserves the existing startup implementation.
"""

from app import main


if __name__ == "__main__":
    main()
