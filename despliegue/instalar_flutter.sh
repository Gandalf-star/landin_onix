#!/usr/bin/env bash
# Paso "install" de Vercel: deja Flutter y las dependencias listos.
#
# Vercel no trae Flutter, asi que se descarga la misma version con la que se
# desarrolla el proyecto. Si Flutter ya esta en el PATH (por ejemplo en el
# computador) no descarga nada.

set -euo pipefail
cd "$(dirname "$0")/.."

readonly VERSION_FLUTTER="${FLUTTER_VERSION:-3.47.1}"
readonly CARPETA_FLUTTER="${FLUTTER_HOME:-$HOME/flutter}"

if ! command -v flutter >/dev/null 2>&1; then
  if [[ ! -x "$CARPETA_FLUTTER/bin/flutter" ]]; then
    # Flutter descomprime el SDK de Dart con unzip.
    if ! command -v unzip >/dev/null 2>&1 && command -v dnf >/dev/null 2>&1; then
      echo "Instalando unzip…"
      dnf install -y unzip >/dev/null
    fi
    echo "Descargando Flutter $VERSION_FLUTTER en $CARPETA_FLUTTER…"
    git -c advice.detachedHead=false clone --quiet --depth 1 \
      --branch "$VERSION_FLUTTER" https://github.com/flutter/flutter.git \
      "$CARPETA_FLUTTER"
  fi
  export PATH="$CARPETA_FLUTTER/bin:$PATH"
fi

flutter --suppress-analytics --version
flutter --suppress-analytics pub get
