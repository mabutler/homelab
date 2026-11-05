#!/usr/bin/env bash
set -e

SHOW_HELP=false
FORCE=false
TARGET=""

for arg in "$@"; do
  case "$arg" in
    -h|--help) SHOW_HELP=true ;;
    --force) FORCE=true ;;
    -*) echo "ERROR: Unknown option $arg" >&2; exit 1 ;;
    *) if [ -z "$TARGET" ]; then TARGET="$arg"; else echo "ERROR: Unexpected argument $arg" >&2; exit 1; fi ;;
  esac
done

if [ "$SHOW_HELP" = true ]; then
  echo "Usage: ./bootstrap-speckit.sh <target-repo> [--force] [--help|-h]"
  exit 0
fi

if [ -z "$TARGET" ]; then
  echo "ERROR: Target repository path is required. Run with --help for usage." >&2
  exit 1
fi

if [ -e "$TARGET" ] && [ ! -d "$TARGET" ]; then
  echo "ERROR: Target path exists and is a file, not a directory: $TARGET" >&2
  exit 1
fi

SRC_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p "$TARGET"
TARGET_DIR="$(cd "$TARGET" && pwd)"

if [ "$SRC_ROOT" = "$TARGET_DIR" ]; then
  echo "ERROR: Target repository cannot be the source toolkit repository itself." >&2
  exit 1
fi

if [ ! -w "$TARGET_DIR" ]; then
  echo "ERROR: Target directory is not writable: $TARGET" >&2
  exit 1
fi

# Verify source bundle
for req in ".specify/templates/spec-template.md" ".specify/templates/plan-template.md" \
           ".specify/templates/tasks-template.md" ".specify/templates/checklist-template.md" \
           ".specify/templates/constitution-template.md" ".specify/templates/coding-standards-template.md" \
           ".specify/templates/logging-standards-template.md" ".specify/templates/roadmap-template.md" \
           ".specify/extensions.yml" ".agents/agents/speckit-reasoner.md" ".agents/agents/speckit-executor.md"; do
  if [ ! -f "$SRC_ROOT/$req" ]; then
    echo "CRITICAL: Source bundle is missing required assets: $req" >&2
    exit 1
  fi
done

MODE_DESC="Normal (skipping existing managed files)"
[ "$FORCE" = true ] && MODE_DESC="Force (overwriting managed files)"

echo "=== Spec Kit Bootstrapper Seeder ==="
echo "Target Repository: $TARGET_DIR"
echo "Mode: $MODE_DESC"
echo ""

COPIED=0
SKIPPED=0
SPECIFY_COUNT=0
AGENTS_COUNT=0

copy_file() {
  local rel="$1"
  local src="$SRC_ROOT/$rel"
  local dst="$TARGET_DIR/$rel"
  [ ! -f "$src" ] && return 0
  mkdir -p "$(dirname "$dst")"
  if [ -f "$dst" ] && [ "$FORCE" != true ]; then
    SKIPPED=$((SKIPPED + 1))
  else
    cp "$src" "$dst"
    COPIED=$((COPIED + 1))
    case "$rel" in
      .specify/*) SPECIFY_COUNT=$((SPECIFY_COUNT + 1)) ;;
      .agents/*) AGENTS_COUNT=$((AGENTS_COUNT + 1)) ;;
    esac
  fi
}

# Copy managed files from .specify and .agents
# Protected User-State Boundary (PRESERVE_USER_STATE):
# Never clobbers .specify/memory/*, overrides, feature.json, local profiles, specs/*, or root ROADMAP.md
while IFS= read -r rel; do
  [ -z "$rel" ] && continue
  copy_file "$rel"
done < <(cd "$SRC_ROOT" && find .specify .agents -type f \
  ! -path ".specify/memory/*" \
  ! -path ".specify/templates/overrides/*" \
  ! -path ".specify/feature.json" \
  ! -path ".agents/agents/*.local.md" \
  ! -path ".agents/agents/speckit-*.local.md" \
  | sort)

# Maintain .gitignore
GITIGNORE="$TARGET_DIR/.gitignore"
PATTERN=".agents/agents/*.local.md"
if [ ! -f "$GITIGNORE" ]; then
  echo "$PATTERN" > "$GITIGNORE"
  echo "[INFO] Created .gitignore with $PATTERN"
elif ! grep -qF "$PATTERN" "$GITIGNORE"; then
  echo "" >> "$GITIGNORE"
  echo "# Spec Kit local agent profiles" >> "$GITIGNORE"
  echo "$PATTERN" >> "$GITIGNORE"
  echo "[INFO] Updated .gitignore with $PATTERN"
else
  echo "[INFO] Verified .gitignore contains $PATTERN"
fi

echo "[INFO] Verified source bundle integrity"
echo "[INFO] Seeded .specify/ configuration and templates ($SPECIFY_COUNT files)"
echo "[INFO] Seeded .agents/ skills and agent definitions ($AGENTS_COUNT files)"

echo ""
echo "Files Copied: $COPIED"
echo "Files Skipped: $SKIPPED (existing)"
echo ""
echo "Next Steps:"
echo "1. Open your AI agent in the target repository"
echo "2. Run /speckit-bootstrap to verify configuration and manifests"
echo "3. Run /speckit-constitution to ratify project governance standards"
echo "===================================="
