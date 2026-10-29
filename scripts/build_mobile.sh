#!/usr/bin/env bash
# Compila todos los artefactos móviles disponibles en este host.
# Android siempre; iOS solo si se ejecuta en macOS.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

printf '\n===== Android =====\n'
"$SCRIPT_DIR/build_android.sh"

if [ "$(uname -s)" = "Darwin" ]; then
  printf '\n===== iOS =====\n'
  "$SCRIPT_DIR/build_ios.sh" "$@"
else
  printf '\n===== iOS =====\n'
  printf 'Omitido: la compilación iOS requiere macOS con Xcode.\n'
fi
