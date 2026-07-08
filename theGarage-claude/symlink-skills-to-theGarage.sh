#!/usr/bin/env bash
# Sets up symlinks so theGarage picks up Claude configs stored in this repo.
#
# Safe to rerun:
#   - Already-correct symlinks are left alone.
#   - Stale symlinks (pointing elsewhere) are replaced.
#   - Real files/dirs at the destination cause an error — remove manually first.
#
# Usage: bash setup-symlinks.sh
set -euo pipefail

# Resolve paths relative to this script so it works from any working directory.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GARAGE_DIR="$(cd "$SCRIPT_DIR/../../theGarage" && pwd)"

# link <source> <destination>
# Creates a symlink at <destination> pointing to <source>.
link() {
  local src="$1"
  local dst="$2"

  if [ -L "$dst" ]; then
    current="$(readlink "$dst")"
    if [ "$current" = "$src" ]; then
      echo "  ok (already linked): $dst"
      return
    fi
    echo "  replacing stale symlink: $dst -> $current"
    rm "$dst"
  elif [ -e "$dst" ]; then
    echo "  ERROR: $dst exists and is not a symlink — remove it manually first"
    exit 1
  fi

  ln -s "$src" "$dst"
  echo "  linked: $dst -> $src"
}

echo "Setting up Claude config symlinks for theGarage..."
link "$SCRIPT_DIR/CLAUDE.md" "$GARAGE_DIR/CLAUDE.md"

# Create .claude directory for individual config symlinks
mkdir -p "$GARAGE_DIR/.claude"

# Symlink individual Claude config subdirectories if they exist at top level
for subdir in agents skills workflows; do
  src="$SCRIPT_DIR/claude/$subdir"
  dst="$GARAGE_DIR/.claude/$subdir"
  if [ -e "$src" ]; then
    link "$src" "$dst"
  fi
done

# Symlink top-level settings file if it exists
if [ -f "$SCRIPT_DIR/claude/settings.json" ]; then
  mkdir -p "$GARAGE_DIR/.claude"
  link "$SCRIPT_DIR/claude/settings.json" "$GARAGE_DIR/.claude/settings.json"
fi

echo "Done. (worktrees/ intentionally not symlinked)"
