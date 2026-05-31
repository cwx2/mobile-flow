#!/usr/bin/env python3
"""Cross-platform build script for MobileFlow Agent.

Usage:
    python build/scripts/build.py [--verbose]

Runs PyInstaller with the spec file and outputs build progress to stdout.
"""

import subprocess
import sys
import time
from pathlib import Path


def main():
    project_root = Path(__file__).parent.parent.parent
    spec_file = project_root / "build" / "mobileflow-agent.spec"
    dist_dir = project_root / "dist"
    work_dir = project_root / "build" / "temp"

    if not spec_file.exists():
        print(f"[ERROR] Spec file not found: {spec_file}")
        sys.exit(1)

    verbose = "--verbose" in sys.argv

    print("=" * 60)
    print("  MobileFlow Agent Build")
    print("=" * 60)
    print(f"  Platform : {sys.platform}")
    print(f"  Python   : {sys.version.split()[0]}")
    print(f"  Spec     : {spec_file}")
    print(f"  Output   : {dist_dir}")
    print(f"  Verbose  : {verbose}")
    print("=" * 60)
    print()

    # Step 1: Clean previous build
    print("[1/3] Cleaning previous build artifacts...")
    if work_dir.exists():
        import shutil
        shutil.rmtree(work_dir, ignore_errors=True)
        print("  -> Cleaned build/temp/")

    # Step 2: Run PyInstaller
    print("[2/3] Running PyInstaller...")
    start_time = time.time()

    cmd = [
        sys.executable, "-m", "PyInstaller",
        "--clean",
        "--distpath", str(dist_dir),
        "--workpath", str(work_dir),
        str(spec_file),
    ]

    if verbose:
        # Show full PyInstaller output
        result = subprocess.run(cmd, cwd=str(project_root))
    else:
        # Capture output, only show on error
        result = subprocess.run(
            cmd, cwd=str(project_root),
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, errors="replace",
        )

    elapsed = time.time() - start_time

    if result.returncode != 0:
        print(f"\n[ERROR] PyInstaller failed (exit code {result.returncode})")
        if not verbose and hasattr(result, "stdout") and result.stdout:
            print("\n--- PyInstaller Output ---")
            # Show last 50 lines of output for debugging
            lines = result.stdout.strip().split("\n")
            for line in lines[-50:]:
                print(f"  {line}")
            print("--- End Output ---")
        print(f"\nTip: Run with --verbose for full output")
        sys.exit(result.returncode)

    # Step 3: Verify output
    print(f"[3/3] Verifying build output...")
    if sys.platform == "win32":
        output = dist_dir / "mobileflow-agent.exe"
    else:
        output = dist_dir / "mobileflow-agent"

    if output.exists():
        size_mb = output.stat().st_size / (1024 * 1024)
        print(f"  -> {output.name}: {size_mb:.1f} MB")
        print()
        print("=" * 60)
        print(f"  BUILD SUCCESSFUL ({elapsed:.1f}s)")
        print(f"  Output: {output}")
        print("=" * 60)
    else:
        print(f"\n[ERROR] Expected output not found: {output}")
        print(f"  Check {dist_dir}/ for actual output files")
        sys.exit(1)


if __name__ == "__main__":
    main()
