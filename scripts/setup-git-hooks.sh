#!/usr/bin/env sh
set -eu

git config core.hooksPath .githooks
git config i18n.commitEncoding utf-8
git config i18n.logOutputEncoding utf-8

echo "Git hooks enabled: .githooks"
echo "Commit/log encoding set to UTF-8"
echo "Done. Your commits will now run encoding checks before commit."
