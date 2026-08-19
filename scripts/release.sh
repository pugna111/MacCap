#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

if [[ -z "${MACCAP_SIGN_IDENTITY:-}" || "$MACCAP_SIGN_IDENTITY" == "-" ]]; then
  echo "错误：正式发布前请设置 MACCAP_SIGN_IDENTITY。" >&2
  exit 1
fi
: "${MACCAP_NOTARY_PROFILE:?正式发布前请设置 MACCAP_NOTARY_PROFILE}"

bash "$ROOT_DIR/scripts/create-dmg.sh"
bash "$ROOT_DIR/scripts/notarize.sh"
