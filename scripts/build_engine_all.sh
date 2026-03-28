#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$ROOT_DIR/scripts/build_engine_host.sh"
"$ROOT_DIR/scripts/build_engine_ios.sh"
"$ROOT_DIR/scripts/build_engine_android.sh"

echo "Fusion Video engine artifacts are ready."
