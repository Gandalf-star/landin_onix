#!/usr/bin/env bash
# Deja Flutter listo para compilar la web.
#
# Vercel no trae Flutter: sin este paso publicaba la raiz del repositorio tal
# cual y, como ahi no hay ningun index.html, respondia 404 NOT_FOUND. Aqui se
# descarga la misma version con la que se desarrolla el proyecto. Si Flutter
# ya esta en el PATH (por ejemplo al probarlo en el computador) no descarga
# nada.
#
# Se puede ejecutar solo (installCommand de Vercel) o con `source` desde
# compilar_web.sh, que lo necesita para tener `flutter` en el PATH.

set -euo pipefail

VERSION_FLUTTER="${FLUTTER_VERSION:-3.47.1}"
CARPETA_FLUTTER="${FLUTTER_HOME:-$HOME/flutter}"

if command -v flutter >/dev/null 2>&1; then
  echo "Flutter ya está disponible: $(command -v flutter)"
else
  if [[ ! -x "$CARPETA_FLUTTER/bin/flutter" ]]; then
    # Flutter descomprime el SDK de Dart con unzip.
    if ! command -v unzip >/dev/null 2>&1 && command -v dnf >/dev/null 2>&1; then
      echo "Instalando unzip…"
      dnf install -y unzip >/dev/null
    fi
    echo "Descargando Flutter $VERSION_FLUTTER en $CARPETA_FLUTTER…"
    git clone --depth 1 --branch "$VERSION_FLUTTER" \
      https://github.com/flutter/flutter.git "$CARPETA_FLUTTER"
  fi
  export PATH="$CARPETA_FLUTTER/bin:$PATH"
fi

flutter --suppress-analytics --version
flutter --suppress-analytics pub get
