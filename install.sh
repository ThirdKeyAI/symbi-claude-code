#!/bin/bash
# Optional runtime installer. Local hooks only need Python 3.11+ and Bash.
set -e
python3 -I -c 'import sys, tomllib; assert sys.version_info >= (3, 11)' || {
    echo "Python 3.11+ is required for the plugin hooks." >&2
    exit 1
}
command -v cargo >/dev/null || {
    echo "Install the Rust toolchain to use this optional Cargo installer." >&2
    exit 1
}
cargo install symbi
symbi --version
echo "Runtime installed. Configure Cedar policies and MCP integration only if wanted."
