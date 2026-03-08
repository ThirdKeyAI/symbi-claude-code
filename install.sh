#!/bin/bash
# Install symbi binary and verify prerequisites
set -e

# Check for jq (required by hook scripts)
if ! command -v jq &> /dev/null; then
    echo "Warning: jq is not installed. Hook scripts require jq for JSON parsing."
    echo "  Install via: apt install jq / brew install jq"
fi

echo "Installing Symbiont CLI..."

if command -v cargo &> /dev/null; then
    echo "Installing from crates.io..."
    cargo install symbi
elif command -v docker &> /dev/null; then
    echo "Docker detected. You can use symbi via Docker:"
    echo "  docker pull ghcr.io/thirdkeyai/symbi:latest"
    echo "  alias symbi='docker run --rm -v \$(pwd):/workspace ghcr.io/thirdkeyai/symbi:latest'"
else
    echo "Neither cargo nor docker found."
    echo "Install Rust: https://rustup.rs"
    echo "Or Docker: https://docs.docker.com/get-docker/"
    exit 1
fi

echo "Done! Run 'symbi --version' to verify."
