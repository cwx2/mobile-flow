#!/usr/bin/env pwsh
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

git config core.hooksPath .githooks
git config i18n.commitEncoding utf-8
git config i18n.logOutputEncoding utf-8

Write-Host "Git hooks enabled: .githooks"
Write-Host "Commit/log encoding set to UTF-8"
Write-Host "Done. Your commits will now run encoding checks before commit."
