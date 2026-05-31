"""Visual Diff Service for the Test Panel.

Captures before/after screenshots and computes pixel diff using
PIL/Pillow. All computation happens on the desktop Agent CPU.

Architecture:
    - Stores "before" baseline screenshot in memory
    - Captures "after" screenshot on demand
    - Computes pixel diff overlay (changed regions in pink/red)
    - Returns all three images as base64-encoded PNGs
    - Pillow is used for image comparison (standard dependency)
"""

from __future__ import annotations

import base64
import io

from loguru import logger

from .screenshot_service import ScreenshotService


class VisualDiffService:
    """Manages before/after screenshot pairs and computes pixel diffs.

    Stores the "before" baseline, captures "after" on demand,
    and computes a diff overlay image highlighting changed regions.

    Usage:
        service = VisualDiffService(screenshot_service)
        await service.capture_before("http://localhost:3000", 375, 812)
        # ... code changes happen ...
        result = await service.capture_and_compare()
    """

    def __init__(self, screenshot_service: ScreenshotService) -> None:
        self._screenshot = screenshot_service
        self._before_data: str | None = None  # base64 PNG
        self._before_url: str | None = None
        self._before_width: int = 375
        self._before_height: int = 812

    async def capture_before(
        self,
        url: str,
        viewport_width: int = 375,
        viewport_height: int = 812,
    ) -> dict | None:
        """Capture and store the 'before' baseline screenshot.

        Args:
            url: URL to capture as the baseline.
            viewport_width: Browser viewport width in pixels.
            viewport_height: Browser viewport height in pixels.

        Returns:
            None on success, or error dict on failure.
        """
        logger.info(f"视觉对比: 捕获 before 基线, url={url[:80]}")

        result = await self._screenshot.capture(
            url=url,
            viewport_width=viewport_width,
            viewport_height=viewport_height,
        )

        if result.get("error"):
            return result

        self._before_data = result["image_data"]
        self._before_url = url
        self._before_width = viewport_width
        self._before_height = viewport_height

        logger.info("视觉对比: before 基线已保存")
        return None

    async def capture_and_compare(self) -> dict:
        """Capture 'after' screenshot and compute pixel diff.

        Captures a new screenshot of the same URL with the same viewport,
        then computes a pixel-level diff between before and after.

        Returns:
            Dict with before_image, after_image, diff_image (all base64),
            changed_percentage, and has_changes. Or error dict on failure.
        """
        if self._before_data is None or self._before_url is None:
            return {
                "error": True,
                "error_type": "unknown",
                "message": "No 'before' baseline captured. Call visual_diff.start first.",
            }

        logger.info(f"视觉对比: 捕获 after 截图, url={self._before_url[:80]}")

        # Capture "after" screenshot
        result = await self._screenshot.capture(
            url=self._before_url,
            viewport_width=self._before_width,
            viewport_height=self._before_height,
        )

        if result.get("error"):
            return result

        after_data = result["image_data"]

        # Compute pixel diff
        diff_result = self._compute_diff(self._before_data, after_data)

        logger.info(
            f"视觉对比完成: changed={diff_result['changed_percentage']:.2f}%, "
            f"has_changes={diff_result['has_changes']}"
        )

        return {
            "before_image": self._before_data,
            "after_image": after_data,
            "diff_image": diff_result["diff_image"],
            "changed_percentage": diff_result["changed_percentage"],
            "has_changes": diff_result["has_changes"],
        }

    def _compute_diff(self, before_b64: str, after_b64: str) -> dict:
        """Compute pixel diff between two base64-encoded PNG images.

        Uses Pillow with vectorized operations (point() + histogram) for
        performance. Avoids per-pixel Python loops which are extremely
        slow for mobile-sized screenshots (300k+ pixels).

        Args:
            before_b64: Base64-encoded PNG of the "before" state.
            after_b64: Base64-encoded PNG of the "after" state.

        Returns:
            Dict with diff_image (base64), changed_percentage, has_changes.
        """
        try:
            from PIL import Image, ImageChops

            # Decode images
            before_bytes = base64.b64decode(before_b64)
            after_bytes = base64.b64decode(after_b64)

            before_img = Image.open(io.BytesIO(before_bytes)).convert("RGBA")
            after_img = Image.open(io.BytesIO(after_bytes)).convert("RGBA")

            # Ensure same size (resize after to match before if needed)
            if before_img.size != after_img.size:
                after_img = after_img.resize(before_img.size, Image.LANCZOS)

            # Compute difference using vectorized Pillow operations
            diff = ImageChops.difference(
                before_img.convert("RGB"),
                after_img.convert("RGB"),
            )

            # Threshold: convert diff to grayscale, then apply point() filter
            # to create a binary mask of changed pixels (avoids Python loop)
            threshold = 10
            grayscale_diff = diff.convert("L")
            # point() applies a lookup table: pixel > threshold -> 255, else 0
            mask = grayscale_diff.point(lambda p: 255 if p > threshold else 0, mode="1")

            # Count changed pixels using histogram on the binary mask
            mask_l = mask.convert("L")
            histogram = mask_l.histogram()
            # histogram[255] = number of white (changed) pixels
            changed_pixels = histogram[255] if len(histogram) > 255 else 0
            total_pixels = before_img.size[0] * before_img.size[1]
            changed_percentage = (changed_pixels / total_pixels * 100) if total_pixels > 0 else 0.0
            has_changes = changed_pixels > 0

            # Create diff overlay: blend pink tint onto changed regions
            pink_overlay = Image.new("RGBA", before_img.size, (255, 80, 80, 100))
            # Composite: where mask is white use pink overlay, else use after image
            diff_overlay = after_img.copy()
            diff_overlay.paste(
                Image.composite(pink_overlay, after_img, mask.convert("L")),
                (0, 0),
            )

            # Encode diff overlay to base64 PNG
            buffer = io.BytesIO()
            diff_overlay.save(buffer, format="PNG")
            diff_b64 = base64.b64encode(buffer.getvalue()).decode("ascii")

            return {
                "diff_image": diff_b64,
                "changed_percentage": round(changed_percentage, 2),
                "has_changes": has_changes,
            }

        except ImportError:
            logger.warning("Pillow 未安装，无法计算视觉差异")
            return {
                "diff_image": after_b64,  # Fallback: use after image as diff
                "changed_percentage": 0.0,
                "has_changes": False,
            }
        except Exception as e:
            logger.error(f"视觉差异计算失败: {e}")
            return {
                "diff_image": after_b64,
                "changed_percentage": 0.0,
                "has_changes": False,
            }
