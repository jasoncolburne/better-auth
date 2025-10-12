#!/usr/bin/env bash

# Install git hooks by creating symlinks from scripts/hooks/ to .git/hooks/

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_SRC="$SCRIPT_DIR/hooks"
HOOKS_DEST="$SCRIPT_DIR/../.git/hooks"

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_status "Installing git hooks..."

# Check if .git directory exists
if [ ! -d "$SCRIPT_DIR/../.git" ]; then
    print_warning "No .git directory found - are you in a git repository?"
    exit 1
fi

# Create .git/hooks directory if it doesn't exist
mkdir -p "$HOOKS_DEST"

# Install each hook
for hook in "$HOOKS_SRC"/*; do
    if [ -f "$hook" ]; then
        hook_name=$(basename "$hook")
        dest_path="$HOOKS_DEST/$hook_name"

        # If hook already exists and is not a symlink, back it up
        if [ -f "$dest_path" ] && [ ! -L "$dest_path" ]; then
            print_warning "Backing up existing $hook_name to $hook_name.backup"
            mv "$dest_path" "$dest_path.backup"
        fi

        # Create symlink (use relative path for portability)
        ln -sf "../../scripts/hooks/$hook_name" "$dest_path"
        print_success "Installed $hook_name"
    fi
done

echo ""
print_success "Git hooks installed successfully!"
