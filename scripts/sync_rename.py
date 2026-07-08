#!/usr/bin/env python3
"""
Sync and rename Flutter plugin package between two repos.

Usage:
    python3 scripts/sync_rename.py <source_repo> <target_repo>

Example:
    python3 scripts/sync_rename.py /path/to/em_chat_callkit /path/to/agora_chat_callkit

This script:
  1. Copies source repo content to target repo (preserving target's .git)
  2. Replaces all naming patterns (snake_case, PascalCase, camelCase)
  3. Renames files and directories accordingly
  4. Runs `flutter clean && flutter pub get` in the example directory
"""

import argparse
import os
import shutil
import subprocess
import sys

# ── Naming rules ──────────────────────────────────────────────────────────────
# Each source repo has a "prefix" that appears before `_chat_callkit`.
# For em_chat_callkit   → prefix = "em"
# For agora_chat_callkit → prefix = "agora"
#
# Derived patterns:
#   snake_case : {prefix}_chat_callkit          (em_chat_callkit / agora_chat_callkit)
#   PascalCase : {Prefix}ChatCallkit            (EmChatCallkit   / AgoraChatCallkit)
#   camelCase  : {prefix}ChatCallkit            (emChatCallkit   / agoraChatCallkit)

SKIP_DIRS = {'.git', 'build', '.dart_tool', 'Pods', '.symlinks', '.plugin_symlinks'}
SKIP_FILES = {'pubspec.lock', 'Podfile.lock', 'Manifest.lock',
              'GeneratedPluginRegistrant.m', 'GeneratedPluginRegistrant.swift',
              '.flutter-plugins', '.flutter-plugins-dependencies'}

TEXT_EXTENSIONS = {
    '.dart', '.yaml', '.yml', '.java', '.kt', '.h', '.m', '.swift',
    '.gradle', '.xml', '.podspec', '.md', '.plist', '.pbxproj',
    '.xcconfig', '.json', '.txt', '.properties', '.kts',
}


def detect_prefix(repo_path):
    """Detect the prefix from the pubspec.yaml name field."""
    pubspec = os.path.join(repo_path, 'pubspec.yaml')
    if not os.path.isfile(pubspec):
        sys.exit(f"Error: {pubspec} not found. Is this a Flutter plugin repo?")
    with open(pubspec, 'r') as f:
        for line in f:
            line = line.strip()
            if line.startswith('name:'):
                pkg_name = line.split(':', 1)[1].strip()
                suffix = '_chat_callkit'
                if not pkg_name.endswith(suffix):
                    sys.exit(f"Error: package name '{pkg_name}' does not end with '{suffix}'")
                prefix = pkg_name[:-len(suffix)]
                if not prefix:
                    sys.exit(f"Error: no prefix found in package name '{pkg_name}'")
                return prefix
    sys.exit(f"Error: 'name:' field not found in {pubspec}")


def build_replacements(src_prefix, dst_prefix):
    """Build ordered list of (old, new) text replacements."""
    def to_pascal(s):
        return s[0].upper() + s[1:] if s else s

    def to_camel(s):
        return s[0].lower() + s[1:] if s else s

    src_snake = f"{src_prefix}_chat_callkit"
    dst_snake = f"{dst_prefix}_chat_callkit"
    src_pascal = f"{to_pascal(src_prefix)}ChatCallkit"
    dst_pascal = f"{to_pascal(dst_prefix)}ChatCallkit"
    src_camel = f"{to_camel(src_prefix)}ChatCallkit"
    dst_camel = f"{to_camel(dst_prefix)}ChatCallkit"

    # Order matters: longer/more-specific patterns first to avoid partial matches
    return [
        (src_pascal, dst_pascal),   # EmChatCallkit → AgoraChatCallkit
        (src_camel, dst_camel),     # emChatCallkit → agoraChatCallkit
        (src_snake, dst_snake),     # em_chat_callkit → agora_chat_callkit
    ]


def should_skip_dir(dirname):
    return dirname in SKIP_DIRS


def should_skip_file(filename):
    return filename in SKIP_FILES


def is_text_file(filepath):
    _, ext = os.path.splitext(filepath)
    return ext.lower() in TEXT_EXTENSIONS


def replace_in_text(text, replacements):
    for old, new in replacements:
        text = text.replace(old, new)
    return text


def replace_in_path(path, replacements):
    for old, new in replacements:
        path = path.replace(old, new)
    return path


def check_target_git_status(dst_repo):
    """Check target repo git status. Exit if dirty, clean untracked files if clean."""
    dst_repo = os.path.abspath(dst_repo)
    dst_git = os.path.join(dst_repo, '.git')

    if not os.path.isdir(dst_git):
        print(f"  Target is not a git repo, skipping git checks.")
        return

    # Check for uncommitted changes (staged + unstaged + unmerged)
    result = subprocess.run(
        ['git', 'status', '--porcelain'],
        cwd=dst_repo, capture_output=True, text=True
    )
    if result.returncode != 0:
        sys.exit(f"Error: failed to run git status in target repo:\n{result.stderr}")

    # Filter out untracked files — only check for modified/staged/deleted
    dirty_lines = [line for line in result.stdout.strip().splitlines()
                   if line and not line.startswith('??')]
    if dirty_lines:
        print(f"\nError: target repo has uncommitted changes:")
        for line in dirty_lines:
            print(f"  {line}")
        sys.exit("Please commit or stash changes in the target repo before syncing.")

    # Clean untracked files and ignored files to remove build artifacts
    print(f"  Target repo is clean. Running git clean ...")
    result = subprocess.run(
        ['git', 'clean', '-fdx',
         '-e', '.git',
         '-e', 'scripts/',
         ],
        cwd=dst_repo, capture_output=True, text=True
    )
    if result.returncode != 0:
        print(f"  Warning: git clean failed:\n{result.stderr}")
    else:
        cleaned = result.stdout.strip()
        if cleaned:
            count = len(cleaned.splitlines())
            print(f"  Cleaned {count} untracked/ignored items.")
        else:
            print(f"  Nothing to clean.")


def sync_repo(src_repo, dst_repo, replacements):
    """Copy src to dst, applying text replacements and path renames."""
    src_repo = os.path.abspath(src_repo)
    dst_repo = os.path.abspath(dst_repo)

    if not os.path.isdir(src_repo):
        sys.exit(f"Error: source repo not found: {src_repo}")

    # Directories to preserve in target (not overwritten by source)
    preserve_dirs = {'.git', 'scripts'}

    # Clean target tracked content (keep preserved dirs)
    if os.path.isdir(dst_repo):
        for item in os.listdir(dst_repo):
            if item in preserve_dirs:
                continue
            item_path = os.path.join(dst_repo, item)
            if os.path.isdir(item_path):
                shutil.rmtree(item_path)
            else:
                os.remove(item_path)
    else:
        os.makedirs(dst_repo, exist_ok=True)

    file_count = 0
    rename_count = 0

    for root, dirs, files in os.walk(src_repo):
        # Skip unwanted directories and preserved directories
        dirs[:] = [d for d in dirs
                   if not should_skip_dir(d) and d not in preserve_dirs]

        rel_root = os.path.relpath(root, src_repo)
        dst_root = os.path.join(dst_repo, replace_in_path(rel_root, replacements))

        os.makedirs(dst_root, exist_ok=True)

        for filename in files:
            if should_skip_file(filename):
                continue

            src_file = os.path.join(root, filename)
            dst_filename = replace_in_path(filename, replacements)
            dst_file = os.path.join(dst_root, dst_filename)

            if filename != dst_filename:
                rename_count += 1

            if is_text_file(src_file):
                try:
                    with open(src_file, 'r', encoding='utf-8') as f:
                        content = f.read()
                    content = replace_in_text(content, replacements)
                    with open(dst_file, 'w', encoding='utf-8') as f:
                        f.write(content)
                    file_count += 1
                except UnicodeDecodeError:
                    shutil.copy2(src_file, dst_file)
                    file_count += 1
            else:
                shutil.copy2(src_file, dst_file)
                file_count += 1

    return file_count, rename_count


def run_flutter_commands(dst_repo):
    """Run flutter clean and pub get in the example directory."""
    example_dir = os.path.join(dst_repo, 'example')
    if not os.path.isdir(example_dir):
        print("  No example/ directory found, skipping flutter commands.")
        return

    print("  Running flutter clean ...")
    subprocess.run(['flutter', 'clean'], cwd=example_dir,
                   capture_output=True, text=True)

    print("  Running flutter pub get ...")
    result = subprocess.run(['flutter', 'pub', 'get'], cwd=example_dir,
                            capture_output=True, text=True)
    if result.returncode != 0:
        print(f"  Warning: flutter pub get failed:\n{result.stderr}")
    else:
        print("  flutter pub get succeeded.")


def main():
    parser = argparse.ArgumentParser(
        description='Sync and rename a Flutter plugin between two repos.')
    parser.add_argument('source', help='Path to source repo (e.g. em_chat_callkit)')
    parser.add_argument('target', help='Path to target repo (e.g. agora_chat_callkit)')
    parser.add_argument('--skip-flutter', action='store_true',
                        help='Skip running flutter clean/pub get')
    args = parser.parse_args()

    src_repo = args.source
    dst_repo = args.target

    print(f"Source: {os.path.abspath(src_repo)}")
    print(f"Target: {os.path.abspath(dst_repo)}")

    # Detect prefixes
    src_prefix = detect_prefix(src_repo)

    # Try to detect target prefix from existing pubspec, otherwise infer from dir name
    if os.path.isfile(os.path.join(dst_repo, 'pubspec.yaml')):
        dst_prefix = detect_prefix(dst_repo)
    else:
        # Infer from directory name
        dirname = os.path.basename(os.path.abspath(dst_repo))
        suffix = '_chat_callkit'
        if dirname.endswith(suffix):
            dst_prefix = dirname[:-len(suffix)]
        else:
            sys.exit(f"Error: cannot infer target prefix from directory name '{dirname}'. "
                     f"Target directory should end with '{suffix}' or contain a pubspec.yaml.")

    print(f"Source prefix: '{src_prefix}' ({src_prefix}_chat_callkit)")
    print(f"Target prefix: '{dst_prefix}' ({dst_prefix}_chat_callkit)")

    replacements = build_replacements(src_prefix, dst_prefix)
    print(f"\nReplacement rules:")
    for old, new in replacements:
        print(f"  {old} → {new}")

    # Check target repo git status
    print(f"\nChecking target repo ...")
    check_target_git_status(dst_repo)

    print(f"\nSyncing ...")
    file_count, rename_count = sync_repo(src_repo, dst_repo, replacements)
    print(f"  Copied {file_count} files, renamed {rename_count} files/dirs.")

    if not args.skip_flutter:
        print(f"\nRunning Flutter commands ...")
        run_flutter_commands(dst_repo)

    print(f"\nDone!")


if __name__ == '__main__':
    main()
