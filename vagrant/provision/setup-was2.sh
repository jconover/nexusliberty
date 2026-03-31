#!/usr/bin/env bash
# setup-was2.sh — Thin wrapper: WAS Managed Node 2 (AppServer2)
# Delegates to the shared setup-was-node.sh with node-specific parameters.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${SCRIPT_DIR}/setup-was-node.sh" AppSrv02 AppServer2 9811 7273 2
