"""Une los archivos SQL de la campana en uno solo, listo para pegar.

El esquema se mantiene partido en cuatro porque son cosas distintas:

- `esquema_supabase.sql`: tablas de la campana (participantes,
  invitaciones con su dispositivo anclado, referidos).
- `esquema_supabase_cuentas.sql`: cuentas con usuario y contrasena, sesiones
  y registro verificado con Twilio.
- `esquema_supabase_premios.sql`: el premio de las tres cajas.
- `esquema_supabase_admin.sql`: cuentas y funciones del panel admin.

Pegarlos por separado en el editor de Supabase invita a equivocarse de
orden, asi que este script genera `esquema_supabase_completo.sql`, que es el
que se copia y se pega.

Uso, desde la raiz del proyecto:

    python docs/generar_esquema_completo.py
"""

import datetime
import io
import os

CARPETA = os.path.dirname(os.path.abspath(__file__))

# En el orden en que hay que ejecutarlos: cada parte usa lo de la anterior.
PARTES = [
    ('esquema_supabase.sql', None),
    ('esquema_supabase_cuentas.sql',
     'SEGUNDA PARTE · CUENTAS, SESIONES Y VERIFICACIÓN CON TWILIO'),
    ('esquema_supabase_premios.sql',
     'TERCERA PARTE · PREMIO DE LAS TRES CAJAS'),
    ('esquema_supabase_admin.sql',
     'CUARTA PARTE · PANEL ADMIN'),
]
ARCHIVO_SALIDA = os.path.join(CARPETA, 'esquema_supabase_completo.sql')

CABECERA = """-- =====================================================================
--  Reto 50 Onix · SCRIPT COMPLETO PARA SUPABASE
--
--  Copia este archivo entero y pégalo en el editor SQL del panel de
--  Supabase (SQL Editor → New query → Run). Es lo único que hay que
--  ejecutar en la base: contiene el esquema de la campaña, las cuentas
--  verificadas con Twilio, el premio de las tres cajas y el panel admin,
--  en el orden correcto.
--
--  Además hay que desplegar la Edge Function `verificar-telefono` y
--  cargarle los secretos de Twilio: ver la sección «Twilio» del README.
--
--  Se puede volver a ejecutar las veces que haga falta sin romper nada:
--  todas las sentencias son idempotentes (`if not exists`, `or replace`,
--  y cada política se borra antes de crearse).
--
--  ARCHIVO GENERADO · no editar a mano
--  -----------------------------------
--  Sale de unir, en orden, docs/esquema_supabase.sql,
--  docs/esquema_supabase_cuentas.sql, docs/esquema_supabase_premios.sql y
--  docs/esquema_supabase_admin.sql. Para regenerarlo después de tocar
--  cualquiera de ellos:
--
--    python docs/generar_esquema_completo.py
--
--  Generado el {fecha}
-- =====================================================================

"""

SEPARADOR = """

-- =====================================================================
--  ↓↓↓  {titulo}  ↓↓↓
-- =====================================================================

"""


def leer(ruta):
    with io.open(ruta, encoding='utf-8') as archivo:
        return archivo.read()


def generar():
    completo = CABECERA.format(fecha=datetime.date.today().isoformat())
    for archivo, titulo in PARTES:
        contenido = leer(os.path.join(CARPETA, archivo))
        if titulo is None:
            completo += contenido.rstrip()
        else:
            completo += SEPARADOR.format(titulo=titulo) + contenido.strip()
    completo += '\n'

    # newline='\n' a proposito: el editor SQL de Supabase se lleva mejor con
    # saltos de linea de Unix, aunque el proyecto viva en Windows.
    with io.open(ARCHIVO_SALIDA, 'w', encoding='utf-8', newline='\n') as salida:
        salida.write(completo)

    print('Generado %s' % ARCHIVO_SALIDA)
    print('%d lineas, %d caracteres' % (completo.count('\n') + 1, len(completo)))


if __name__ == '__main__':
    generar()
