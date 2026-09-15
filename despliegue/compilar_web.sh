#!/usr/bin/env bash
# Paso "build" de Vercel: arma el .env y compila la landing en build/web.
#
# El .env no esta en el repositorio (esta en .gitignore), pero pubspec.yaml
# lo declara como asset y sin el la compilacion falla. En Vercel se escribe
# con las variables de entorno del proyecto (Settings -> Environment
# Variables); en el computador se usa el .env que ya existe.

set -euo pipefail
cd "$(dirname "$0")/.."

# Claves que la landing lee del .env (ver .env.ejemplo).
readonly CLAVES_ENV=(SUPABASE_URL SUPABASE_ANON_KEY ORIGEN_DATOS)
readonly CARPETA_FLUTTER="${FLUTTER_HOME:-$HOME/flutter}"

# 1. Credenciales: se revisan antes de compilar para fallar en segundos y
#    no despues de varios minutos.
if [[ -n "${SUPABASE_URL:-}" && -n "${SUPABASE_ANON_KEY:-}" ]]; then
  echo "Creando .env con las variables de entorno del despliegue."
  : > .env
  for clave in "${CLAVES_ENV[@]}"; do
    if [[ -n "${!clave:-}" ]]; then
      printf '%s=%s\n' "$clave" "${!clave}" >> .env
    fi
  done
elif [[ "${ORIGEN_DATOS:-}" == "memoria" ]]; then
  echo "ORIGEN_DATOS=memoria: se publica la versión de demostración, sin Supabase."
  printf 'ORIGEN_DATOS=memoria\n' > .env
elif [[ -f .env ]]; then
  echo "Usando el .env que ya existe."
else
  cat >&2 <<'AVISO'
ERROR: faltan las credenciales de Supabase.

En Vercel, abre el proyecto -> Settings -> Environment Variables y agrega
(los valores estan en el .env del proyecto):
  SUPABASE_URL       https://TU-PROYECTO.supabase.co
  SUPABASE_ANON_KEY  la clave publica (anon) del proyecto
Luego vuelve a desplegar. Nunca uses la service_role key: todo lo que va en
el .env llega al navegador.
AVISO
  exit 1
fi

# 2. Flutter en el PATH (el paso install ya lo descargo y corrio pub get).
if ! command -v flutter >/dev/null 2>&1; then
  if [[ ! -x "$CARPETA_FLUTTER/bin/flutter" ]]; then
    bash despliegue/instalar_flutter.sh
  fi
  export PATH="$CARPETA_FLUTTER/bin:$PATH"
fi

# 3. Compilacion.
flutter --suppress-analytics build web --release --no-wasm-dry-run

if [[ ! -f build/web/index.html ]]; then
  echo "ERROR: la compilación no generó build/web/index.html." >&2
  exit 1
fi
echo "Sitio listo en build/web."
