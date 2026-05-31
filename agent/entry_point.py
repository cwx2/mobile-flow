"""PyInstaller entry point for MobileFlow Agent.

This wrapper script exists because PyInstaller cannot handle relative
imports in __main__.py when it's used as the Analysis entry point.
By importing and calling main() from here, the package context is
properly established and relative imports work correctly.
"""

from mobileflow_agent.__main__ import main

if __name__ == "__main__":
    main()
