#!/usr/bin/env python3
"""Detect encoding issues, mojibake, and old brand names in git files.

Runs as a pre-commit hook (--staged) or CI check (--all) to catch:
  1. Non-UTF-8 files
  2. Mojibake / garbled characters (common with AI-generated code)
  3. Old brand names that should have been replaced
  4. Hardcoded layout dimensions in Dart files (mobile UI safety)

Usage:
  python scripts/check_encoding.py --staged   # pre-commit hook
  python scripts/check_encoding.py --all      # CI full check
"""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]

SUSPICIOUS_TOKENS = (
    "\ufffd",  # replacement character
    "\u00e2\u20ac\u201d",  # cp1252/utf8 mojibake pattern
    "\u00e2\u20ac\u201c",
    "\u00e2\u20ac\u02dc",
    "\u00e2\u20ac\u2122",
    "\u00e2\u20ac\u0153",
    "\u00ef\u00bb\u00bf",  # UTF-8 BOM displayed as text
)

BINARY_EXTENSIONS = {
    ".png", ".jpg", ".jpeg", ".gif", ".webp", ".ico", ".pdf",
    ".zip", ".apk", ".aab", ".jar", ".ttf", ".otf", ".woff",
    ".woff2", ".so", ".dll", ".dylib", ".exe", ".mp3", ".mp4",
    ".mov", ".lock",
}

# Old brand patterns to reject
_OLD_BRAND_PATTERNS = (
    "Pocket Coder",
    "PocketCoder",
    "com.pocketcoder",
    "pocketcoder://",
)

# Files that intentionally contain old brand names (naming table, legacy docs)
_BRAND_CHECK_SKIP = {
    "AGENTS.md", "dev-workflow.md", "check_encoding.py",
    # Legacy Android package (com.pocketcoder.app) — kept for migration
    "KeepAliveService.kt", "MainActivity.kt",
    # Old build spec (references old name in metadata)
    "pocket-coder-agent.spec",
    # Historical docs (not user-facing)
    "SESSION_CONTEXT.md", "codex-acp-bridge-plan.md",
    "dev-lessons.md", "vscode-auth-pattern.md",
}

# Layout size patterns for Dart files (catches hardcoded dimensions)
_LAYOUT_SIZE_PATTERNS = [
    (re.compile(r'SizedBox\(\s*width:\s*(\d+)'), "SizedBox with fixed width"),
    (re.compile(r'SizedBox\(\s*height:\s*(\d+)'), "SizedBox with fixed height"),
    (re.compile(r'Container\(\s*[^)]*\bwidth:\s*(\d+)'), "Container with fixed width"),
    (re.compile(r'Container\(\s*[^)]*\bheight:\s*(\d+)'), "Container with fixed height"),
]
_LAYOUT_SIZE_THRESHOLD = 200
_LAYOUT_CHECK_SKIP = {"splash_screen.dart", "diff_theme.dart", "code_theme.dart"}


def _run(cmd: list[str]) -> str:
    result = subprocess.run(
        cmd, cwd=REPO_ROOT,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False,
    )
    if result.returncode != 0:
        raise RuntimeError(f"Command failed: {' '.join(cmd)}")
    return result.stdout.decode("utf-8", errors="replace")


def _git_paths(mode: str) -> list[str]:
    if mode == "staged":
        out = _run(["git", "diff", "--cached", "--name-only", "--diff-filter=ACMR", "-z"])
    else:
        out = _run(["git", "ls-files", "-z"])
    return [p for p in out.split("\x00") if p]


def _is_binary_path(path: str) -> bool:
    return Path(path).suffix.lower() in BINARY_EXTENSIONS


def _get_file_bytes(path: str, mode: str) -> bytes:
    if mode == "staged":
        cmd = ["git", "show", f":{path}"]
    else:
        cmd = ["git", "show", f"HEAD:{path}"]
    result = subprocess.run(
        cmd, cwd=REPO_ROOT,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False,
    )
    if result.returncode != 0:
        fs_path = REPO_ROOT / path
        if fs_path.exists():
            return fs_path.read_bytes()
        raise RuntimeError(f"Unable to read: {path}")
    return result.stdout


def _find_issues(path: str, data: bytes) -> list[str]:
    issues: list[str] = []

    # Skip binary content
    if b"\x00" in data:
        return issues

    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError as exc:
        issues.append(f"{path}: not valid UTF-8 (byte offset {exc.start})")
        return issues

    # Check for mojibake tokens
    for token in SUSPICIOUS_TOKENS:
        if token in text:
            issues.append(f"{path}: contains mojibake character")
            break

    # Brand name check
    filename = Path(path).name
    if filename not in _BRAND_CHECK_SKIP:
        for pattern in _OLD_BRAND_PATTERNS:
            if pattern in text:
                issues.append(f"{path}: contains old brand name '{pattern}'")

    # Layout adaptation check (Dart files only)
    if path.endswith(".dart") and "/test/" not in path:
        if filename not in _LAYOUT_CHECK_SKIP:
            for line_num, line in enumerate(text.splitlines(), 1):
                stripped = line.strip()
                if stripped.startswith("//") or stripped.startswith("import "):
                    continue
                for pattern, desc in _LAYOUT_SIZE_PATTERNS:
                    match = pattern.search(line)
                    if match:
                        value = int(match.group(1))
                        if value > _LAYOUT_SIZE_THRESHOLD:
                            issues.append(
                                f"{path}:{line_num}: {desc} = {value}px "
                                f"(>{_LAYOUT_SIZE_THRESHOLD}px, may overflow on small screens)"
                            )

    return issues


def main() -> int:
    parser = argparse.ArgumentParser(description="Check encoding and code quality.")
    parser.add_argument("--staged", action="store_true", help="Check staged files only")
    parser.add_argument("--all", action="store_true", help="Check all tracked files")
    args = parser.parse_args()

    mode = "staged" if args.staged else "all"

    try:
        paths = _git_paths(mode)
    except RuntimeError as exc:
        print(f"[encoding-check] {exc}")
        return 2

    if mode == "staged" and not paths:
        print("[encoding-check] No staged files.")
        return 0

    all_issues: list[str] = []
    for path in paths:
        if _is_binary_path(path):
            continue
        try:
            data = _get_file_bytes(path, mode)
        except RuntimeError as exc:
            all_issues.append(str(exc))
            continue
        all_issues.extend(_find_issues(path, data))

    if all_issues:
        print("[encoding-check] FAILED:")
        for issue in all_issues:
            safe = issue.encode(sys.stdout.encoding or "utf-8", errors="backslashreplace").decode(
                sys.stdout.encoding or "utf-8")
            print(f"  - {safe}")
        return 1

    scope = "staged files" if mode == "staged" else "tracked files"
    print(f"[encoding-check] OK ({scope}).")
    return 0


if __name__ == "__main__":
    os.chdir(REPO_ROOT)
    raise SystemExit(main())
