from __future__ import annotations

import argparse
from pathlib import Path
import re
import subprocess
import sys
from urllib.parse import unquote, urlsplit


ROOT = Path(__file__).resolve().parents[1]
IGNORED_DIRS = {".git", "__pycache__", "logs"}
WEIGHT_EXTENSIONS = {
    ".bin",
    ".gguf",
    ".onnx",
    ".pt",
    ".pth",
    ".safetensors",
}
TEXT_EXTENSIONS = {
    "",
    ".json",
    ".md",
    ".modelfile",
    ".ps1",
    ".py",
    ".txt",
    ".yml",
    ".yaml",
}
MAX_FILE_BYTES = 5 * 1024 * 1024

SECRET_PATTERNS = {
    "private key": re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
    "AWS access key": re.compile(r"\bAKIA[0-9A-Z]{16}\b"),
    "GitHub token": re.compile(r"\bgh[pousr]_[A-Za-z0-9]{30,}\b"),
    "OpenAI-style key": re.compile(r"\bsk-[A-Za-z0-9_-]{20,}\b"),
    "Slack token": re.compile(r"\bxox[baprs]-[A-Za-z0-9-]{20,}\b"),
    "credential in URL": re.compile(r"https?://[^/\s:@]+:[^@\s]+@"),
}
PRIVATE_PATH_PATTERNS = {
    "Windows user path": re.compile(r"(?i)\b[A-Z]:\\Users\\[^\\\r\n]+"),
    "macOS user path": re.compile(
        r"(?i)(?<!\w)/" + "Users" + r"/[^/\s]+"
    ),
    "Linux home path": re.compile(
        r"(?i)(?<!\w)/" + "home" + r"/[^/\s]+"
    ),
    "file URI": re.compile(r"(?i)\bfile://"),
}
MARKDOWN_LINK = re.compile(r"!?\[[^\]]*\]\(([^)]+)\)")


def tracked_files() -> list[Path]:
    completed = subprocess.run(
        ["git", "ls-files", "-z"],
        cwd=ROOT,
        check=True,
        capture_output=True,
    )
    return [
        ROOT / item.decode("utf-8")
        for item in completed.stdout.split(b"\0")
        if item
    ]


def workspace_files() -> list[Path]:
    return [
        path
        for path in ROOT.rglob("*")
        if path.is_file()
        and not any(part in IGNORED_DIRS for part in path.relative_to(ROOT).parts)
    ]


def strip_fenced_code(text: str) -> str:
    output: list[str] = []
    fence: str | None = None
    for line in text.splitlines():
        stripped = line.lstrip()
        marker = "```" if stripped.startswith("```") else (
            "~~~" if stripped.startswith("~~~") else None
        )
        if marker:
            fence = None if fence == marker else marker
            continue
        if fence is None:
            output.append(line)
    return "\n".join(output)


def local_link_target(markdown: Path, raw_target: str) -> Path | None:
    target = raw_target.strip().strip("<>")
    if not target or target.startswith("#"):
        return None
    parsed = urlsplit(target)
    if parsed.scheme or parsed.netloc:
        return None
    relative = unquote(parsed.path)
    if not relative:
        return None
    return (markdown.parent / relative).resolve()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--tracked",
        action="store_true",
        help="scan only files tracked by Git",
    )
    args = parser.parse_args()

    files = tracked_files() if args.tracked else workspace_files()
    relative_paths = {
        path.resolve().relative_to(ROOT).as_posix()
        for path in files
    }
    failures: list[str] = []

    manifest_path = ROOT / "PUBLIC_MANIFEST.txt"
    if args.tracked and manifest_path.exists():
        manifest_paths = {
            line.strip()
            for line in manifest_path.read_text(encoding="utf-8").splitlines()
            if line.strip() and not line.lstrip().startswith("#")
        }
        if manifest_paths != relative_paths:
            missing = sorted(manifest_paths - relative_paths)
            extra = sorted(relative_paths - manifest_paths)
            if missing:
                failures.append("manifest missing from Git: " + ", ".join(missing))
            if extra:
                failures.append("unapproved tracked files: " + ", ".join(extra))

    for path in files:
        relative = path.resolve().relative_to(ROOT).as_posix()
        lowered_parts = {part.lower() for part in Path(relative).parts}
        lowered_name = path.name.lower()

        if path.is_symlink():
            failures.append(f"{relative}: symbolic link is not allowed")
        if path.stat().st_size > MAX_FILE_BYTES:
            failures.append(f"{relative}: file exceeds 5 MiB")
        if path.suffix.lower() in WEIGHT_EXTENSIONS:
            failures.append(f"{relative}: model/binary weight file is not allowed")
        if lowered_name.startswith(".env"):
            failures.append(f"{relative}: environment file is not allowed")
        if lowered_name == "config.yaml" or lowered_name.startswith(
            "config.before-local-"
        ):
            failures.append(f"{relative}: private Hermes config is not allowed")
        if lowered_parts & {"logs", "__pycache__", ".codex", "sessions", "memories"}:
            failures.append(f"{relative}: private/runtime directory is not allowed")

        if path.suffix.lower() not in TEXT_EXTENSIONS:
            continue
        try:
            text = path.read_text(encoding="utf-8-sig")
        except UnicodeDecodeError:
            failures.append(f"{relative}: text file is not valid UTF-8")
            continue

        for name, pattern in {**SECRET_PATTERNS, **PRIVATE_PATH_PATTERNS}.items():
            if pattern.search(text):
                failures.append(f"{relative}: possible {name}")

        if path.suffix.lower() == ".md":
            for raw_target in MARKDOWN_LINK.findall(strip_fenced_code(text)):
                target = local_link_target(path, raw_target)
                if target is None:
                    continue
                try:
                    target.relative_to(ROOT)
                except ValueError:
                    failures.append(f"{relative}: link escapes repository")
                    continue
                if not target.exists():
                    failures.append(f"{relative}: broken link {raw_target}")
                    continue
                target_relative = target.relative_to(ROOT).as_posix()
                if args.tracked and target.is_file() and target_relative not in relative_paths:
                    failures.append(
                        f"{relative}: link target is not tracked {raw_target}"
                    )

    readme = (ROOT / "README.md").read_text(encoding="utf-8-sig")
    readme_en = (ROOT / "README.en.md").read_text(encoding="utf-8-sig")
    if "README.en.md" not in readme:
        failures.append("README.md: English language link is missing")
    if "README.md" not in readme_en:
        failures.append("README.en.md: Korean language link is missing")

    if failures:
        for failure in failures:
            print(f"FAIL: {failure}")
        print(f"Public release checks failed: {len(failures)}")
        return 1

    print(f"Public release checks passed: {len(files)} files")
    return 0


if __name__ == "__main__":
    sys.exit(main())
