#!/usr/bin/env bash
# Auditoría en un clic: dependencias, análisis estático y pruebas.
# Opcional: ./scripts/audit.sh --build-linux
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

log()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
fail() { printf '\n\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

find_flutter() {
  command -v flutter >/dev/null 2>&1 && return 0
  local candidate
  for candidate in \
    "$HOME/flutter/bin" \
    "$HOME/development/flutter/bin" \
    "/opt/flutter/bin" \
    "/usr/local/flutter/bin"; do
    if [ -x "$candidate/flutter" ]; then
      export PATH="$candidate:$PATH"
      return 0
    fi
  done
  return 1
}

find_flutter || fail "Flutter no está instalado o no está en PATH."

log "Flutter"
flutter --version | sed -n '1p'

log "Dependencias"
flutter pub get

log "Análisis estático (lib + test)"
flutter analyze lib test

log "Pruebas automatizadas"
flutter test

if [ "${1:-}" = "--build-linux" ]; then
  log "Build Linux release"
  flutter build linux --release
fi

printf '\n\033[1;32mAuditoría completada sin errores.\033[0m\n'
