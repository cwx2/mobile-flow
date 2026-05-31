"""PyInstaller runtime hook: set production environment for packaged builds.

This hook runs before the main entry point. It sets MOBILEFLOW_ENV=production
so the config loader picks up production.json (INFO-level logs) instead of
development.json (DEBUG-level logs). Users can still override by setting
MOBILEFLOW_ENV=development before launching the exe.

Note: The env var name MOBILEFLOW_ENV is the standard name used by the
MobileFlow Agent for environment selection.
"""
import os

if "MOBILEFLOW_ENV" not in os.environ:
    os.environ["MOBILEFLOW_ENV"] = "production"
