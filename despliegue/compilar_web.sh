#!/usr/bin/env bash
# Compila la landing para Vercel y deja el sitio listo en build/web.
#
# 1. Deja Flutter en el PATH (instalar_flutter.sh).
# 2. Arma el .env. No esta en el repositorio (esta en .gitignore), pero
#    pubspec.yaml lo declara como asset: sin el archivo la compilacion falla.
#    En Vercel se escribe con las variables de entorno del proyecto
#    (Settings -> Environment Variables); en el computador se usa el .env
#    que ya existe.
# 3. Compila la web en modo release.

set -euo pipefail
cd "$(dirname "$0")/.."

# Claves que la landing lee del .env (ver .env.ejemplo).
CLAVES_ENV=(SUPABASE_URL SUPABASE_ANON_KEY ORIGEN_DATOS)

source despliegue/instalar_flutter.sh

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

En Vercel, abre el proyecto -> Settings -> Environment Variables y agrega:
  SUPABASE_URL       https://TU-PROYECTO.supabase.co
  SUPABASE_ANON_KEY  la clave publica (anon) del proyecto
Luego vuelve a desplegar. Nunca uses la service_role key: todo lo que va en
el .env llega al navegador.
AVISO
  exit 1
fi

flutter --suppress-analytics build web --release --no-wasm-dry-run

if [[ ! -f build/web/index.html ]]; then
  echo "ERROR: la compilación no generó build/web/index.html." >&2
  exit 1
fi
echo "Sitio listo en build/web."
