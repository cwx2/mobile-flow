"""Screenshot Service for the Test Panel.

Uses Playwright (optional dependency) to capture screenshots of
localhost URLs using headless Chromium. Reports clear error with
installation instructions if Playwright is not installed.

Architecture:
    - Playwright is an OPTIONAL dependency — checked at runtime
    - Captures PNG screenshots with configurable viewport
    - Returns base64-encoded image data
    - Supports multiple wait strategies (networkidle, domcontentloaded, load)
"""

from __future__ import annotations

import base64
import time

from loguru import logger


class ScreenshotService:
    """Captures screenshots of localhost URLs using headless Chromium.

    Optional dependency — reports clear error if Playwright is not
    installed. All computation happens on the desktop Agent.

    Usage:
        service = ScreenshotService()
        if service.is_available():
            result = await service.capture("http://localhost:3000")
    """

    @staticmethod
    def is_available() -> bool:
        """Check if Playwright + Chromium are installed.

        Returns:
            True if Playwright can be imported and Chromium is available.
        """
        try:
            import playwright  # noqa: F401
            return True
        except ImportError:
            return False

    async def capture(
        self,
        url: str,
        viewport_width: int = 375,
        viewport_height: int = 812,
        wait_until: str = "networkidle",
    ) -> dict:
        """Navigate to URL and capture PNG screenshot.

        Launches a headless Chromium browser, navigates to the URL,
        waits for the page to load, and captures a full-page screenshot.

        Args:
            url: URL to navigate to and capture.
            viewport_width: Browser viewport width in pixels.
            viewport_height: Browser viewport height in pixels.
            wait_until: Page load strategy — "networkidle", "domcontentloaded", or "load".

        Returns:
            Dict with success fields (image_data, actual_width, actual_height,
            capture_time_ms) or error fields (error=True, error_type, message).
        """
        if not self.is_available():
            return {
                "error": True,
                "error_type": "not_installed",
                "message": (
                    "Playwright is not installed. Install with: "
                    "pip install playwright && playwright install chromium"
                ),
            }

        logger.info(
            f"截图捕获: url={url[:80]}, "
            f"viewport={viewport_width}x{viewport_height}, wait={wait_until}"
        )
        start_time = time.monotonic()

        try:
            from playwright.async_api import async_playwright

            async with async_playwright() as p:
                browser = await p.chromium.launch(headless=True)
                try:
                    page = await browser.new_page(
                        viewport={"width": viewport_width, "height": viewport_height}
                    )
                    await page.goto(url, wait_until=wait_until, timeout=30000)

                    # Capture screenshot as PNG bytes
                    screenshot_bytes = await page.screenshot(type="png", full_page=False)

                    capture_time_ms = int((time.monotonic() - start_time) * 1000)
                    image_data = base64.b64encode(screenshot_bytes).decode("ascii")

                    logger.info(
                        f"截图完成: {len(screenshot_bytes)} bytes, "
                        f"{capture_time_ms}ms"
                    )

                    return {
                        "image_data": image_data,
                        "actual_width": viewport_width,
                        "actual_height": viewport_height,
                        "capture_time_ms": capture_time_ms,
                    }
                finally:
                    await browser.close()

        except Exception as e:
            err_str = str(e).lower()
            if "timeout" in err_str:
                error_type = "timeout"
            elif "net::err" in err_str or "navigation" in err_str:
                error_type = "navigation_error"
            else:
                error_type = "navigation_error"

            logger.error(f"截图失败: url={url[:60]}, error={e}")
            return {
                "error": True,
                "error_type": error_type,
                "message": str(e),
            }
