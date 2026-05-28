#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$REPO_ROOT"
source .venv-tf/bin/activate
cd software_golden_model_rps
exec python src/main.py "$@"
