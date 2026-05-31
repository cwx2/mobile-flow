"""Plugin loader: discovery, validation, and installation.

Module: plugins/
Responsibility:
    Scan the extensions directory, parse ``mobileflow.plugin.json`` manifests
    and ``package.json`` metadata, validate directory security (symlink escape),
    filter by platform, and return PluginInfo instances.
    A single plugin load failure does not affect other plugins (fault isolation).

Called by:
    - plugins/registry.py (startup scan and refresh).
"""

from __future__ import annotations

import asyncio
import json
import platform
import shutil
import tarfile
import tempfile
import urllib.request
import zipfile
from pathlib import Path

from loguru import logger

from ..utils.command import which
from ..utils.encoding import decode_process_output
from .manifest import PluginInfo, PluginManifest, PluginMetadata

# ── Constants ──
MANIFEST_FILE = "mobileflow.plugin.json"
METADATA_FILE = "package.json"
MAX_MANIFEST_SIZE = 1_048_576  # 1 MB

# Platform mapping: platform.system() → manifest platform identifier
_PLATFORM_MAP: dict[str, str] = {
    "Windows": "windows",
    "Darwin": "macos",
    "Linux": "linux",
}


class PluginLoader:
    """Plugin discovery, validation, and installation."""

    def scan_extensions(self, ext_dir: Path) -> list[PluginInfo]:
        """Scan the extensions directory and return all discovered plugins.

        Creates ``ext_dir`` if it does not exist.  Individual plugin load
        failures are logged and skipped (fault isolation).

        Args:
            ext_dir: Path to the extensions directory.

        Returns:
            List of successfully loaded PluginInfo instances.
        """
        ext_dir.mkdir(parents=True, exist_ok=True)
        logger.debug(f"扫描插件目录: {ext_dir}")

        current_platform = _PLATFORM_MAP.get(platform.system())
        plugins: list[PluginInfo] = []

        for child in sorted(ext_dir.iterdir()):
            if not child.is_dir():
                continue

            try:
                plugin = self._load_single(child, ext_dir, current_platform)
                if plugin is not None:
                    plugins.append(plugin)
            except Exception as exc:
                logger.warning(f"加载插件目录 {child.name} 失败：{exc}")

        logger.info(f"插件扫描完成: 发现 {len(plugins)} 个插件")
        return plugins

    # ── Internal helpers ──

    def _load_single(
        self,
        plugin_dir: Path,
        ext_dir: Path,
        current_platform: str | None,
    ) -> PluginInfo | None:
        """Load a single plugin directory.

        Args:
            plugin_dir: Path to the plugin directory.
            ext_dir: Parent extensions directory (for symlink validation).
            current_platform: Current OS platform identifier.

        Returns:
            PluginInfo on success, or None if the directory should be skipped.
        """
        manifest_path = plugin_dir / MANIFEST_FILE

        if not manifest_path.exists():
            return None

        # Security: reject directories with symlinks escaping ext_dir
        if not self.validate_directory(plugin_dir, ext_dir):
            logger.warning(
                f"插件 {plugin_dir.name} 包含不安全的文件链接，已拒绝加载"
            )
            return None

        manifest = self.parse_manifest(manifest_path)

        # Platform filter
        if manifest.platforms is not None and current_platform is not None:
            if current_platform not in manifest.platforms:
                logger.info(
                    f"插件 {manifest.id} 不支持当前平台 "
                    f"({current_platform})，已跳过"
                )
                return None

        # Parse metadata (silent degradation on failure)
        metadata = self.parse_metadata(plugin_dir / METADATA_FILE)

        return PluginInfo(
            id=manifest.id,
            manifest=manifest,
            metadata=metadata,
            directory=plugin_dir,
            enabled=manifest.enabled_by_default,
            status="active",
        )

    # ── Public parsing methods ──

    def parse_manifest(self, manifest_path: Path) -> PluginManifest:
        """Parse and validate a plugin manifest file.

        Enforces a 1 MB size limit and uses Pydantic for field validation.
        No plugin code is executed.  Reads with ``utf-8-sig`` encoding to
        handle Windows BOM-prefixed UTF-8 files.

        Args:
            manifest_path: Path to the manifest JSON file.

        Returns:
            Validated PluginManifest instance.

        Raises:
            ValueError: If the file exceeds the size limit.
            pydantic.ValidationError: If the manifest content is invalid.
        """
        size = manifest_path.stat().st_size
        if size > MAX_MANIFEST_SIZE:
            raise ValueError(
                f"插件配置文件过大（{size} 字节，上限 {MAX_MANIFEST_SIZE} 字节），"
                "请联系插件作者"
            )

        raw = manifest_path.read_text(encoding="utf-8-sig")
        data = json.loads(raw)
        manifest = PluginManifest.model_validate(data)
        logger.debug(f"解析插件清单: id={manifest.id}, providers={len(manifest.providers)}")
        return manifest

    def parse_metadata(self, pkg_path: Path) -> PluginMetadata:
        """Parse ``package.json`` metadata with silent degradation.

        Returns an empty PluginMetadata if the file is missing or malformed.

        Args:
            pkg_path: Path to the ``package.json`` file.

        Returns:
            PluginMetadata instance.
        """
        try:
            if not pkg_path.exists():
                return PluginMetadata()
            raw = pkg_path.read_text(encoding="utf-8-sig")
            data = json.loads(raw)
            return PluginMetadata(
                name=data.get("name", ""),
                version=data.get("version", ""),
                description=data.get("description", ""),
                author=data.get("author", ""),
                license=data.get("license", ""),
                repository=data.get("repository", ""),
            )
        except Exception as exc:
            logger.warning(f"解析 {pkg_path} 失败，使用空元数据：{exc}")
            return PluginMetadata()

    def validate_directory(self, plugin_dir: Path, ext_dir: Path) -> bool:
        """Validate that a plugin directory contains no symlinks escaping ext_dir.

        Args:
            plugin_dir: Plugin directory to validate.
            ext_dir: Parent extensions directory (security boundary).

        Returns:
            True if the directory is safe, False if a symlink escape is detected.
        """
        resolved_ext = ext_dir.resolve()

        for item in plugin_dir.rglob("*"):
            if item.is_symlink():
                target = item.resolve()
                if not str(target).startswith(str(resolved_ext)):
                    return False
        return True

    # ── Installation methods ──

    async def install_from_git(self, url: str, ext_dir: Path) -> PluginInfo:
        """Install a plugin by cloning a Git repository (120 s timeout).

        Args:
            url: Git repository URL.
            ext_dir: Extensions directory to clone into.

        Returns:
            PluginInfo for the newly installed plugin.

        Raises:
            RuntimeError: On clone failure, timeout, or missing manifest.
        """
        ext_dir.mkdir(parents=True, exist_ok=True)

        # Derive directory name from the URL (strip trailing .git)
        repo_name = url.rstrip("/").rsplit("/", 1)[-1]
        if repo_name.endswith(".git"):
            repo_name = repo_name[:-4]
        target_dir = ext_dir / repo_name

        if target_dir.exists():
            raise RuntimeError(
                f"插件目录 '{repo_name}' 已存在，"
                "请先卸载已有插件或手动删除该目录后重试"
            )

        try:
            proc = await asyncio.wait_for(
                self._run_git_clone(url, str(target_dir)),
                timeout=120,
            )
            if proc.returncode != 0:
                stderr = decode_process_output(await proc.stderr.read()).strip()
                raise RuntimeError(
                    f"无法从 Git 仓库下载，请检查 URL 和网络：{stderr}"
                )

            manifest_path = target_dir / MANIFEST_FILE
            if not manifest_path.exists():
                raise FileNotFoundError(
                    "仓库中未找到 mobileflow.plugin.json 清单文件"
                )

            manifest = self.parse_manifest(manifest_path)
            metadata = self.parse_metadata(target_dir / METADATA_FILE)

            return PluginInfo(
                id=manifest.id,
                manifest=manifest,
                metadata=metadata,
                directory=target_dir,
                enabled=manifest.enabled_by_default,
                status="active",
            )

        except asyncio.TimeoutError:
            self._cleanup(target_dir)
            raise RuntimeError("网络连接超时，请检查网络后重试")
        except RuntimeError:
            self._cleanup(target_dir)
            raise
        except Exception as exc:
            self._cleanup(target_dir)
            raise RuntimeError(f"插件安装失败：{exc}") from exc

    async def install_from_npm(self, package: str, ext_dir: Path) -> PluginInfo:
        """Install a plugin from npm (120 s timeout).

        Args:
            package: npm package name (e.g. ``@scope/plugin-name``).
            ext_dir: Extensions directory.

        Returns:
            PluginInfo for the newly installed plugin.

        Raises:
            RuntimeError: On npm failure, timeout, or missing manifest.
        """
        ext_dir.mkdir(parents=True, exist_ok=True)

        # Derive directory name from the package name
        dir_name = package.replace("@", "").replace("/", "-").strip("-")
        target_dir = ext_dir / dir_name

        if target_dir.exists() and any(target_dir.iterdir()):
            raise RuntimeError(
                f"插件目录 '{dir_name}' 已存在，"
                "请先卸载已有插件或手动删除该目录后重试"
            )

        try:
            target_dir.mkdir(parents=True, exist_ok=True)

            proc = await asyncio.wait_for(
                self._run_npm_install(package, str(target_dir)),
                timeout=120,
            )
            if proc.returncode != 0:
                stderr = decode_process_output(await proc.stderr.read()).strip()
                raise RuntimeError(
                    f"npm 安装出错，请检查包名是否正确：{stderr}"
                )

            manifest_path = target_dir / MANIFEST_FILE
            if not manifest_path.exists():
                # npm packages may place the manifest under node_modules
                for child in (target_dir / "node_modules").iterdir():
                    candidate = child / MANIFEST_FILE
                    if candidate.exists():
                        manifest_path = candidate
                        break

            if not manifest_path.exists():
                raise FileNotFoundError(
                    "npm 包中未找到 mobileflow.plugin.json 清单文件"
                )

            manifest = self.parse_manifest(manifest_path)
            metadata = self.parse_metadata(manifest_path.parent / METADATA_FILE)

            return PluginInfo(
                id=manifest.id,
                manifest=manifest,
                metadata=metadata,
                directory=target_dir,
                enabled=manifest.enabled_by_default,
                status="active",
            )

        except asyncio.TimeoutError:
            self._cleanup(target_dir)
            raise RuntimeError("网络连接超时，请检查网络后重试")
        except RuntimeError:
            self._cleanup(target_dir)
            raise
        except Exception as exc:
            self._cleanup(target_dir)
            raise RuntimeError(f"插件安装失败：{exc}") from exc

    async def install_from_url(self, url: str, ext_dir: Path) -> PluginInfo:
        """Install a plugin from a URL (supports .zip and .tar.gz, 60 s timeout).

        Args:
            url: Download URL for the plugin archive.
            ext_dir: Extensions directory.

        Returns:
            PluginInfo for the newly installed plugin.

        Raises:
            RuntimeError: On download failure, timeout, or missing manifest.
        """
        ext_dir.mkdir(parents=True, exist_ok=True)
        target_dir: Path | None = None

        try:
            target_dir = await asyncio.wait_for(
                asyncio.get_event_loop().run_in_executor(
                    None, self._download_and_extract, url, ext_dir,
                ),
                timeout=60,
            )

            manifest_path = target_dir / MANIFEST_FILE
            if not manifest_path.exists():
                raise FileNotFoundError(
                    "下载的包中未找到 mobileflow.plugin.json 清单文件"
                )

            manifest = self.parse_manifest(manifest_path)
            metadata = self.parse_metadata(target_dir / METADATA_FILE)

            return PluginInfo(
                id=manifest.id,
                manifest=manifest,
                metadata=metadata,
                directory=target_dir,
                enabled=manifest.enabled_by_default,
                status="active",
            )

        except asyncio.TimeoutError:
            if target_dir:
                self._cleanup(target_dir)
            raise RuntimeError("网络连接超时，请检查网络后重试")
        except RuntimeError:
            if target_dir:
                self._cleanup(target_dir)
            raise
        except Exception as exc:
            if target_dir:
                self._cleanup(target_dir)
            raise RuntimeError(f"插件安装失败：{exc}") from exc

    async def uninstall(self, plugin_id: str, ext_dir: Path) -> bool:
        """Uninstall a plugin by deleting its directory.

        Args:
            plugin_id: Plugin identifier to match against manifests.
            ext_dir: Extensions directory to search.

        Returns:
            True if the plugin was found and deleted, False otherwise.
        """
        for child in ext_dir.iterdir():
            if not child.is_dir():
                continue
            manifest_path = child / MANIFEST_FILE
            if not manifest_path.exists():
                continue
            try:
                data = json.loads(manifest_path.read_text(encoding="utf-8"))
                if data.get("id") == plugin_id:
                    shutil.rmtree(child)
                    return True
            except Exception:
                continue
        return False

    # ── Installation helpers ──
    #
    # Note: On Windows, globally installed npm/git binaries are .cmd files
    # (e.g. npm.cmd, git.cmd).  utils/command.py:which() resolves the full
    # path including .cmd/.bat suffixes automatically.
    #
    # Plugin Agent Windows .cmd/.bat detection and WSL probing are handled
    # by ProviderRegistry.detect_all() → _probe_all() / _probe_wsl_batch().
    # Plugin Agents injected via inject_plugin_agent() participate in that
    # detection flow automatically.

    @staticmethod
    async def _run_git_clone(url: str, target: str) -> asyncio.subprocess.Process:
        """Clone a git repository.

        Args:
            url: Repository URL.
            target: Local directory to clone into.

        Returns:
            The completed subprocess.

        Raises:
            RuntimeError: If git is not installed.
        """
        git_cmd = which("git")
        if not git_cmd:
            raise RuntimeError("未检测到 git，请先安装 Git")
        proc = await asyncio.create_subprocess_exec(
            git_cmd, "clone", url, target,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        await proc.wait()
        return proc

    @staticmethod
    async def _run_npm_install(package: str, cwd: str) -> asyncio.subprocess.Process:
        """Run ``npm install`` for a package.

        Args:
            package: npm package specifier.
            cwd: Working directory for the npm command.

        Returns:
            The completed subprocess.

        Raises:
            RuntimeError: If npm is not installed.
        """
        npm_cmd = which("npm")
        if not npm_cmd:
            raise RuntimeError("未检测到 npm，请先安装 Node.js")
        proc = await asyncio.create_subprocess_exec(
            npm_cmd, "install", package,
            cwd=cwd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        await proc.wait()
        return proc

    @staticmethod
    def _download_and_extract(url: str, ext_dir: Path) -> Path:
        """Download and extract a .zip or .tar.gz archive into ext_dir.

        Args:
            url: Download URL.
            ext_dir: Target extraction directory.

        Returns:
            Path to the extracted plugin directory.

        Raises:
            ValueError: If the archive format is unsupported.
        """
        with tempfile.NamedTemporaryFile(delete=False) as tmp:
            tmp_path = Path(tmp.name)
            try:
                urllib.request.urlretrieve(url, tmp_path)

                if url.endswith(".zip"):
                    with zipfile.ZipFile(tmp_path) as zf:
                        # Use the top-level directory from the archive
                        top_dirs = {n.split("/")[0] for n in zf.namelist() if "/" in n}
                        if len(top_dirs) == 1:
                            extract_name = top_dirs.pop()
                        else:
                            extract_name = tmp_path.stem
                        target_dir = ext_dir / extract_name
                        zf.extractall(ext_dir)

                elif url.endswith(".tar.gz") or url.endswith(".tgz"):
                    with tarfile.open(tmp_path, "r:gz") as tf:
                        top_dirs = {m.name.split("/")[0] for m in tf.getmembers() if "/" in m.name}
                        if len(top_dirs) == 1:
                            extract_name = top_dirs.pop()
                        else:
                            extract_name = tmp_path.stem.replace(".tar", "")
                        target_dir = ext_dir / extract_name
                        tf.extractall(ext_dir)
                else:
                    raise ValueError(
                        f"不支持的文件格式，仅支持 .zip 和 .tar.gz：{url}"
                    )

                return target_dir
            finally:
                tmp_path.unlink(missing_ok=True)

    @staticmethod
    def _cleanup(path: Path) -> None:
        """Safely remove a directory, ignoring errors.

        Args:
            path: Directory to remove.
        """
        try:
            if path.exists():
                shutil.rmtree(path)
        except Exception as exc:
            logger.warning(f"清理目录 {path} 失败：{exc}")
