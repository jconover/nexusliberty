#!/usr/bin/env bash
# setup-was1.sh — Thin wrapper: WAS Managed Node 1 (AppServer1)
# Delegates to the shared setup-was-node.sh with node-specific parameters.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${SCRIPT_DIR}/setup-was-node.sh" AppSrv01 AppServer1 9810 7272 1
