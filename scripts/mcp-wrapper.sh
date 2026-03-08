#!/bin/bash
# MCP transport wrapper: selects stdio or HTTP transport based on environment
#
# Mode A (standalone): Spawns `symbi mcp` over stdio (default behavior)
# Mode B (SYMBIONT_MANAGED): Connects to parent runtime's MCP endpoint via
#   SYMBIONT_MCP_URL instead of spawning a new server process.
#
# This script is used as the MCP server command when environment-aware
# transport switching is needed.

if [ -n "$SYMBIONT_MCP_URL" ]; then
    # Mode B: Connect to parent runtime's MCP endpoint
    # Use npx to bridge HTTP/SSE transport to stdio for Claude Code
    exec npx -y @anthropic-ai/mcp-proxy "$SYMBIONT_MCP_URL"
else
    # Mode A: Spawn local symbi MCP server over stdio
    exec symbi mcp "$@"
fi
