# Reto 50 Onix · Landing de sorteo y referidos

Landing page en **Flutter Web** para la campaña de referidos que promociona
**Onix Drive** en Chile y Venezuela. Quien quiere invitar crea su cuenta
(nombre, celular y contraseña) confirmando su celular con un código por SMS y
pulsa «Compartir link por WhatsApp»: en WhatsApp elige a todos los contactos
que quiera. Todos reciben el mismo link, pero **cada persona que lo abre en su
celular recibe su propio código**, atado a ese dispositivo. La persona
invitada **no crea cuenta ni recibe SMS**: escribe su celular, valida el
código y éste queda anclado a su número y a su dispositivo. En ese momento
quien la invitó suma **un ticket**. Con
**50 tickets** se reclama el premio: se elige una de **tres cajas cerradas**
y se gana lo que esconde (1 viaje gratis, un regalo Onix o $3.000 de saldo
Onix), con un ticket ganador y su código de confirmación.

Los reclamos se reciben y verifican en el **panel admin**, un proyecto aparte
en `../panel_admin_onix` conectado al mismo Supabase (ver su README).

Es un proyecto **independiente**: no se conecta al backend, la base de datos ni
los servicios de Onix Drive (tampoco a su cuenta de Twilio). Sólo toma
prestada su identidad visual.

## Cómo correrlo

```bash
flutter pub get
cp .env.ejemplo .env           # y completar con las credenciales del proyecto
flutter run -d chrome          # desarrollo
flutter test                   # pruebas de reglas anti-trampa y de la UI
flutter build web --release    # producción, queda en build/web
```

En VS Code basta con **F5** (configuraciones en `.vscode/launch.json`).

Para probar el flujo de invitación, entra al panel de un participante y copia
el link de «Invita a tus contactos» (o pulsa «Compartir link por WhatsApp»).
Después ábrelo en **otro navegador o dispositivo**:

```
http://localhost:PUERTO/?inv=XXXXXXXXXX     link para muchos contactos
http://localhost:PUERTO/?ref=ONX-XXXX-XXXX  código individual
```

La tarjeta se abre en «Tengo un código» con un código exclusivo ya escrito:
basta el celular para validarlo, sin cuenta ni SMS. Cada navegador distinto que
abre el link recibe un código distinto; el mismo navegador recibe siempre el
mismo. Desde el dispositivo de quien invita el link no entrega códigos (el
anclaje lo bloquea), y un número sólo puede validar una invitación.

Abajo a la izquierda, un distintivo indica de dónde salen los datos: verde
«Datos en vivo · Supabase» o ámbar «Datos de demostración» con el motivo por el
que no se pudo usar el backend.

Con `ORIGEN_DATOS=memoria` la landing funciona sin backend: no se envían SMS,
el código de verificación se muestra en pantalla con el aviso «Modo
demostración» y el panel trae botones `+1` y `+10` para simular invitados,
llegar a los 50 tickets y abrir las cajas (y «Reiniciar premio» para repetir).

## El premio: tres cajas

| Paso | Qué pasa |
| --- | --- |
| **Reclamar premio** | Aparece en el panel con 50 tickets (o con el modo prueba del admin). `sesion_reclamar_premio` crea el reclamo y **esconde los tres premios en las tres cajas con un orden aleatorio generado en la base** (bytes criptográficos). |
| **Elegir caja** | La landing solo sabe que hay tres cajas cerradas: el orden **no viaja al navegador** hasta abrir, así que inspeccionar la red o el código no revela nada. |
| **Abrir** | `sesion_abrir_caja` fija la elección una sola vez (bloqueo de fila), genera el **código de confirmación** `PRM-XXXXX-XXXXX`, avisa al panel admin por Realtime y recién entonces devuelve el premio y dónde estaban los otros dos. |
| **Verificar y entregar** | El admin busca el código, revisa a los invitados y marca el premio como verificado y entregado. |

- Cada reclamo tiene su propio orden: los premios nunca están fijos en la
  misma caja, y una cuenta de prueba que vuelve a jugar nunca repite el orden
  anterior.
- No se puede reclamar dos veces ni volver a barajar: hay un único reclamo
  vigente por participante y una caja abierta es definitiva (trigger).
- La animación usa `assets/animaciones/confeti.json` (el Lottie de la
  campaña), dibujado dos veces, tal cual y reflejado, para que la lluvia
  quede simétrica sobre el ticket.

## Cuentas y verificación del teléfono

| Momento | Qué se pide | SMS |
| --- | --- | --- |
| **Crear cuenta** (quien invita) | Nombre, celular y contraseña | Sí, una sola vez, con Twilio Verify |
| **Iniciar sesión** | Celular y contraseña | No |
| **Validar un código** (quien fue invitado) | Su celular (el código lo entrega el link), **sin cuenta** | **No** |

El registro es de dos pasos y la cuenta **no existe** hasta que Twilio aprueba
el código:

```
Navegador ──► Edge Function `verificar-telefono` ──► cuenta_preparar_registro (SQL)
                     │                                  reglas anti-fraude, bcrypt,
                     │                                  límites de SMS
                     └──► Twilio Verify: envía el SMS

Navegador ──► Edge Function (código) ──► Twilio VerificationCheck
                     └── si "approved" ──► cuenta_completar_registro (SQL)
                                            crea la cuenta y abre la sesión
```

La invitación no pasa por Twilio, sólo por funciones públicas de la base:

```
Quien invita ──► sesion_mi_enlace ──► link ?inv=XXXXXXXXXX ──► WhatsApp (muchos contactos)

Cada contacto ──► invitado_obtener_codigo ──► su propio código, atado a su dispositivo
              ──► invitado_validar_codigo ──► ancla teléfono y dispositivo, suma el ticket
```

- Las credenciales de Twilio viven **sólo** como secretos de la Edge Function.
- Las funciones SQL del registro sólo las puede ejecutar `service_role` (la
  Edge Function): nadie puede crear una cuenta saltándose Twilio con la anon
  key. Las del canje son públicas y aplican todas las reglas en la base.
- La contraseña se guarda cifrada con bcrypt. Tras 5 intentos fallidos el
  número queda bloqueado 15 minutos.
- Límites contra el abuso de SMS: 45 s entre envíos, 5 SMS por número por
  hora, 10 por IP y 6 por dispositivo.

## Supabase

La interfaz de usuario nunca habla con el backend: sólo conoce
`RepositorioReferidos`. Hoy esa interfaz tiene dos implementaciones,
`RepositorioEnMemoria` (sin backend) y `RepositorioSupabase`, y `arrancar()`
elige una u otra al iniciar.

### Puesta en marcha

1. En el panel de Supabase, abrir **SQL Editor → New query**, pegar
   `docs/esquema_supabase_completo.sql` entero y darle **Run**. Ese archivo
   es lo único que hay que ejecutar en la base y se puede repetir sin romper
   nada.
2. Desplegar la Edge Function y cargarle los secretos de Twilio (sección
   siguiente).
3. Copiar `.env.ejemplo` a `.env` y poner la URL del proyecto y la clave
   pública (*anon*), que están en **Project Settings → API**.
4. `flutter run -d chrome`. El distintivo de abajo a la izquierda debe quedar
   en verde.

### Variables del `.env`

| Variable | Para qué sirve |
| --- | --- |
| `SUPABASE_URL` | URL del proyecto. |
| `SUPABASE_ANON_KEY` | Clave pública. Va al navegador; la protege RLS. |
| `ORIGEN_DATOS` | `supabase` o `memoria` para trabajar sin conexión. |

El `.env` está en `.gitignore`. Nunca poner ahí la `service_role` key ni las
credenciales de Twilio: en una app web todo lo que se empaqueta llega al
navegador.

El esquema vive partido en cinco archivos y `esquema_supabase_completo.sql`
es la unión de todos, que es lo que se pega. Después de tocar cualquiera hay
que regenerarlo:

```bash
python docs/generar_esquema_completo.py
```

## Twilio

Hay que usar una cuenta de Twilio **propia de la landing**, nunca la de Onix
Drive.

### 1. Crear el servicio de Verify

1. Crear la cuenta en <https://www.twilio.com/try-twilio> y cargarle saldo
   (la cuenta de prueba sólo envía SMS a números verificados en la consola).
2. **Console → Account Info**: copiar `Account SID` (empieza con `AC`) y
   `Auth Token`.
3. **Verify → Services → Create new**: nombre `Reto 50 Onix`, canal SMS
   activado. Copiar el `Service SID` (empieza con `VA`).
4. Recomendado dentro del servicio: dejar **Fraud Guard** activo y, en
   **Messaging Geo-Permissions** de la cuenta, permitir sólo Chile y
   Venezuela.

### 2. Cargar los secretos en Supabase

```bash
cp supabase/.env.ejemplo supabase/.env      # completar con los valores de arriba
npx supabase login
npx supabase secrets set --env-file supabase/.env --project-ref dznogtqwxhiiytqifeqt
```

También se pueden pegar a mano en el panel: **Edge Functions → Secrets**.

| Secreto | Obligatorio | Para qué sirve |
| --- | --- | --- |
| `TWILIO_ACCOUNT_SID` | Sí | Cuenta de Twilio (`AC...`). |
| `TWILIO_AUTH_TOKEN` | Sí | Token de esa cuenta. |
| `TWILIO_VERIFY_SERVICE_SID` | Sí | Servicio de Verify (`VA...`). |
| `TWILIO_CANAL` | No | `sms` (por defecto) o `whatsapp`. |
| `TWILIO_VALIDAR_TIPO_LINEA` | No | `true` rechaza números VoIP y fijos con Twilio Lookup (cuesta por consulta). |

Los secretos se aplican al instante, sin volver a desplegar.

### 3. Desplegar la Edge Function

Ya está desplegada en el proyecto. Si se modifica
`supabase/functions/verificar-telefono/index.ts`:

```bash
npx supabase functions deploy verificar-telefono --project-ref dznogtqwxhiiytqifeqt
```

### 4. Comprobar

```bash
curl -X POST "$SUPABASE_URL/functions/v1/verificar-telefono" \
  -H "Authorization: Bearer $SUPABASE_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '{"accion":"estado"}'
```

Debe responder `"twilio_configurado": true`. Mientras sea `false`, el registro
muestra «La verificación por SMS no está disponible en este momento» y el
inicio de sesión sigue funcionando. Los errores de Twilio quedan en
**Edge Functions → verificar-telefono → Logs**.

## Estructura

```
lib/
  main.dart
  src/
    app.dart                      Inyección del repositorio y tema
    nucleo/
      tema_onix.dart              Paleta y tipografía de Onix Drive
      config_campana.dart         Premios, metas, textos, FAQ
      entorno.dart                Lectura del .env
      arranque.dart               Elige Supabase o memoria al iniciar
    datos/
      modelos.dart                Participante, EventoReferido, ...
      repositorio_referidos.dart  Interfaz (el contrato con el backend)
      repositorio_memoria.dart    Implementación sin backend
      repositorio_supabase.dart   Implementación contra Supabase
      controlador_referidos.dart  Estado compartido de la campaña
    utiles/
      telefono.dart               Normalización E.164 (Chile y Venezuela)
      credenciales.dart           Reglas de la contraseña
      codigo_referido.dart        Generación y validación de códigos
      dispositivo*.dart           Huella y firma del navegador (anclaje)
    ui/
      pagina_landing.dart         Composición de la página
      secciones/                  Hero, premios, reclamo, ranking, FAQ, ...
      registro/                   Validar código, crear cuenta, verificación e ingreso
      panel/                      Panel del participante
      premio/                     Cajas, confeti, ticket y escena del reclamo
      componentes/                Piezas reutilizables
assets/
  animaciones/confeti.json        Lottie del confeti al abrir la caja
supabase/
  functions/verificar-telefono/   Edge Function que habla con Twilio Verify
  .env.ejemplo                    Secretos de Twilio (el .env no se versiona)
  config.toml                     Configuración mínima para la CLI
docs/
  esquema_supabase_completo.sql   ← el que se pega en Supabase (generado)
  esquema_supabase.sql            Tablas de la campaña, anclaje, RLS, vistas
  esquema_supabase_cuentas.sql    Cuentas, sesiones y registro con Twilio
  esquema_supabase_invitados.sql  Links de invitación y canje sin cuenta ni SMS
  esquema_supabase_premios.sql    Reclamo y apertura de las tres cajas
  esquema_supabase_admin.sql      Cuentas y funciones del panel admin
  generar_esquema_completo.py     Une los cinco en el completo
.env                              Credenciales públicas (no se versiona)
```

### Estructura del panel admin

Ver `../panel_admin_onix/README.md`.

### Antes de abrir la campaña al público

`docs/esquema_supabase_cuentas.sql` termina con un bloque comentado que borra
los participantes, invitaciones y registros creados durante las pruebas.
Hay que ejecutarlo antes del lanzamiento.

## Reglas anti-trampa

- Un teléfono verificado equivale a una cuenta: `telefono_e164` es único y
  se confirma con Twilio antes de crear la cuenta.
- Cada código de invitación es de **un solo uso** y, en cuanto se valida (o
  vence el plazo), queda cerrado para siempre.
- **Un código por dispositivo**: el link entrega un código distinto a cada
  dispositivo que lo abre, y ese código sólo se valida desde ese mismo
  dispositivo. Quien borra los datos del navegador o usa incógnito vuelve a
  recibir el mismo código (misma firma y conexión). Máximo 50 códigos por
  link y 30 por conexión cada hora.
- Una invitación validada es **inmutable**: nadie puede volver a usarla ni
  reasignarla (trigger).
- **Anclaje del teléfono**: el número queda anclado al código que valida
  (índice único). Un número sólo puede aceptar una invitación en toda la
  campaña, y nunca la de su propio dueño. Sin SMS, se rechazan además los
  números obviamente inventados.
- **Anclaje del dispositivo**: el navegador desde el que el invitado valida
  el código queda anclado a ese código (índice único en la base). Un
  dispositivo no puede aceptar una segunda invitación, y un código no se
  puede validar desde el dispositivo de quien lo generó (ni desde uno donde
  inició sesión, ni con su misma firma y conexión de registro). Tampoco
  valida un dispositivo con la firma y la conexión de otro invitado ya
  validado de la misma persona. Sin los dos anclajes no hay ticket.
- Freno a quien prueba links o códigos al azar: 8 inválidos por
  dispositivo y 20 por IP cada hora.
- Quien borra los datos del navegador o usa modo incógnito obtiene una
  huella nueva, pero la **firma del navegador** (pantalla, idioma, zona
  horaria, motor gráfico…) y la IP quedan guardadas: el panel admin marca las
  coincidencias entre los invitados y con el ganador antes de entregar.
- Sin autorreferidos ni cadenas circulares.
- Límite de registros por dispositivo, de SMS por número, IP y dispositivo, de
  intentos de verificación y de intentos de inicio de sesión.
- Rechazo de números obviamente falsos; opcionalmente, de números VoIP y
  fijos con Twilio Lookup, además del Fraud Guard de Twilio Verify.
- Premio sellado en el servidor, código de confirmación único por ticket y
  revisión del admin antes de cada entrega.
- La landing ya no muestra contadores públicos (personas participando,
  invitaciones válidas ni intentos bloqueados): esas cifras solo están en el
  panel admin.
