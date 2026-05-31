"""Language detection utilities.

Maps file extensions to language identifiers used by code editors
and syntax highlighters. Shared across FileService, ContextResolver,
and any future module that needs language detection.

The mapping covers mainstream languages, config formats, and markup.
Unknown extensions return empty string — callers decide the fallback.
"""

# File extension → language identifier (VS Code / TextMate convention)
LANG_MAP: dict[str, str] = {
    # Systems / compiled
    ".c": "c",
    ".cpp": "cpp",
    ".cc": "cpp",
    ".cxx": "cpp",
    ".h": "c",
    ".hpp": "cpp",
    ".cs": "csharp",
    ".go": "go",
    ".rs": "rust",
    ".zig": "zig",
    ".nim": "nim",
    # JVM
    ".java": "java",
    ".kt": "kotlin",
    ".kts": "kotlin",
    ".scala": "scala",
    ".gradle": "groovy",
    # Web / JS ecosystem
    ".js": "javascript",
    ".jsx": "javascriptreact",
    ".ts": "typescript",
    ".tsx": "typescriptreact",
    ".vue": "vue",
    ".svelte": "svelte",
    ".astro": "astro",
    # Mobile
    ".dart": "dart",
    ".swift": "swift",
    # Scripting
    ".py": "python",
    ".rb": "ruby",
    ".php": "php",
    ".lua": "lua",
    ".pl": "perl",
    ".pm": "perl",
    ".r": "r",
    ".R": "r",
    ".ex": "elixir",
    ".exs": "elixir",
    ".sh": "shell",
    ".bash": "shell",
    ".zsh": "shell",
    ".fish": "shell",
    ".ps1": "powershell",
    # Markup / docs
    ".html": "html",
    ".htm": "html",
    ".css": "css",
    ".scss": "scss",
    ".less": "less",
    ".md": "markdown",
    ".mdx": "markdown",
    ".tex": "latex",
    ".xml": "xml",
    ".svg": "xml",
    # Data / config
    ".json": "json",
    ".jsonc": "jsonc",
    ".yaml": "yaml",
    ".yml": "yaml",
    ".toml": "toml",
    ".ini": "ini",
    ".cfg": "ini",
    ".env": "dotenv",
    ".properties": "properties",
    # Infrastructure
    ".sql": "sql",
    ".graphql": "graphql",
    ".gql": "graphql",
    ".proto": "protobuf",
    ".tf": "terraform",
    ".hcl": "hcl",
    ".dockerfile": "dockerfile",
    # Other
    ".csv": "csv",
    ".txt": "plaintext",
    ".log": "log",
    ".diff": "diff",
    ".patch": "diff",
    ".gitignore": "ignore",
}


def detect_language(path: str) -> str:
    """Detect programming language from file extension.

    Uses the shared LANG_MAP for consistent language identification
    across all modules (FileService, ContextResolver, etc.).

    Args:
        path: File path or name (only the extension is used).

    Returns:
        Language identifier string (e.g. "python", "typescript"),
        or empty string if the extension is not recognised.
    """
    from pathlib import Path as P
    ext = P(path).suffix.lower()
    return LANG_MAP.get(ext, "")
