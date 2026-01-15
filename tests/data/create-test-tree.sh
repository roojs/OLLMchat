#!/bin/bash
# Helper script to create test directory trees for bubblewrap tests
# Usage: ./create-test-tree.sh <base_dir> <tree_name>

set -euo pipefail

BASE_DIR="${1:-.}"
TREE_NAME="${2:-test-tree}"

TREE_DIR="$BASE_DIR/$TREE_NAME"

# Create nested directory structure
mkdir -p "$TREE_DIR/a/b"
mkdir -p "$TREE_DIR/c"
mkdir -p "$TREE_DIR/d/e/f"

# Create files at various levels
echo "file1 content" > "$TREE_DIR/file1"
echo "file2 content" > "$TREE_DIR/a/file2"
echo "file3 content" > "$TREE_DIR/a/b/file3"
echo "file4 content" > "$TREE_DIR/c/file4"
echo "file5 content" > "$TREE_DIR/d/file5"
echo "file6 content" > "$TREE_DIR/d/e/file6"
echo "file7 content" > "$TREE_DIR/d/e/f/file7"

echo "Created test tree at: $TREE_DIR"
echo "Structure:"
find "$TREE_DIR" -type f | sort
