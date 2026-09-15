-- =====================================================================
--  Reto 50 Onix · Cuentas, sesiones y verificación del teléfono
--
--  Cómo funciona
--  -------------
--  Registro (una sola vez por teléfono):
--    1. La landing llama a la Edge Function `verificar-telefono`. Ésta
--       ejecuta `cuenta_preparar_registro`, que aplica las reglas
--       anti-fraude, guarda la contraseña YA cifrada con bcrypt en
--       `registros_pendientes` y, sólo si todo está en orden, la Edge
--       Function pide a Twilio Verify que envíe el SMS.
--    2. La persona escribe el código. La Edge Function lo valida contra
--       Twilio y, únicamente si Twilio responde `approved`, ejecuta
--       `cuenta_completar_registro`, que crea al participante y le abre
--       una sesión.
--
--  Ingreso: nombre de usuario + contraseña (`cuenta_iniciar_sesion`). No se
--  envía ningún SMS al iniciar sesión.
--
--  Seguridad
--  ---------
--  - Las funciones del registro sólo las puede ejecutar `service_role`, es
--    decir, la Edge Function. Si fueran públicas, cualquiera con la anon
--    key podría llamar a `cuenta_completar_registro` y saltarse Twilio.
--  - Las credenciales de Twilio viven como secretos de la Edge Function:
--    nunca llegan al navegador ni a esta base.
--  - La contraseña se cifra con bcrypt (pgcrypto) y jamás se guarda ni se
--    devuelve en claro.
--  - Los errores de negocio se DEVUELVEN como JSON en vez de lanzarse con
--    `raise exception`: una excepción revertiría la transacción y, con
--    ella, los contadores de intentos fallidos que frenan la fuerza bruta.
--
--  Requiere haber ejecutado antes docs/esquema_supabase.sql
-- =====================================================================

-- ---------------------------------------------------------------------
-- Restos del antiguo modo demostración
--
-- Antes el código de verificación lo generaba la base y se mostraba en
-- pantalla, sin probar que el teléfono fuera de quien lo escribía. Ese
-- camino queda eliminado: si la base lo tenía, aquí se borra.
-- ---------------------------------------------------------------------
drop function if exists public.demo_iniciar_registro(text, text, text, text);
drop function if exists public.demo_iniciar_ingreso(text);
drop function if exists public.demo_reenviar(uuid);
drop function if exists public.demo_confirmar(uuid, text);
drop function if exists public.demo_participante(uuid);
drop function if exists public.demo_mis_referidos(uuid);
drop function if exists public.demo_cerrar_sesion(uuid);
drop function if exists public.demo_generar_invitacion(uuid, int);
drop function if exists public.demo_mis_invitaciones(uuid);
drop function if exists public.demo_simular_invitado(uuid);
drop table if exists public.desafios_demo;
drop index if exists public.idx_participantes_token;
alter table public.participantes drop column if exists token_sesion;

-- ---------------------------------------------------------------------
-- Credenciales del participante
-- ---------------------------------------------------------------------
alter table public.participantes
  add column if not exists nombre_usuario text;
alter table public.participantes
  add column if not exists hash_contrasena text;

create unique index if not exists idx_participantes_nombre_usuario
  on public.participantes (nombre_usuario);

-- Minusculas, digitos, punto y guion bajo; de 3 a 20 caracteres. Se guarda
-- ya normalizado, asi el indice UNIQUE no distingue mayusculas.
alter table public.participantes
  drop constraint if exists nombre_usuario_valido;
alter table public.participantes
  add constraint nombre_usuario_valido
  check (nombre_usuario ~ '^[a-z0-9][a-z0-9_.]{2,19}$');

-- ---------------------------------------------------------------------
-- Sesiones
--
-- Una fila por navegador con la sesion abierta: entrar desde el celular
-- no cierra la sesion del computador. El token hace de llave de todas las
-- lecturas del panel.
-- ---------------------------------------------------------------------
create table if not exists public.sesiones (
  token           uuid primary key default gen_random_uuid(),
  participante_id uuid not null references public.participantes (id) on delete cascade,
  huella          text,
  creado_en       timestamptz not null default now(),
  expira_en       timestamptz not null default now() + interval '30 days'
);

create index if not exists idx_sesiones_participante
  on public.sesiones (participante_id);

-- ---------------------------------------------------------------------
-- Registros a la espera del código de Twilio
-- ---------------------------------------------------------------------
create table if not exists public.registros_pendientes (
  id               uuid primary key default gen_random_uuid(),
  nombre           text not null,
  nombre_usuario   text not null,
  hash_contrasena  text not null,
  telefono_e164    text not null,
  codigo_invitador text,
  huella           text,
  ip               inet,
  -- enviado: esperando el codigo · verificado: ya es participante ·
  -- cancelado: Twilio no pudo enviar el SMS (no cuenta para los limites).
  estado           text not null default 'enviado',
  intentos         int not null default 0,
  envios           int not null default 1,
  enviado_en       timestamptz not null default now(),
  -- Twilio Verify vence sus codigos a los 10 minutos.
  expira_en        timestamptz not null default now() + interval '10 minutes',
  creado_en        timestamptz not null default now(),

  constraint estado_registro_valido
    check (estado in ('enviado', 'verificado', 'cancelado'))
);

-- Firma y detalle del dispositivo desde el que se pide el registro. Si trae
-- codigo de invitacion, este dispositivo es el que queda anclado al codigo.
alter table public.registros_pendientes
  add column if not exists firma text;
alter table public.registros_pendientes
  add column if not exists dispositivo jsonb;

create index if not exists idx_pendientes_telefono
  on public.registros_pendientes (telefono_e164, creado_en desc);
create index if not exists idx_pendientes_ip
  on public.registros_pendientes (ip, creado_en desc);
create index if not exists idx_pendientes_huella
  on public.registros_pendientes (huella, creado_en desc);

-- ---------------------------------------------------------------------
-- Intentos de inicio de sesión (freno a la fuerza bruta)
-- ---------------------------------------------------------------------
create table if not exists public.intentos_ingreso (
  id             bigserial primary key,
  nombre_usuario text not null,
  huella         text,
  exito          boolean not null default false,
  creado_en      timestamptz not null default now()
);

create index if not exists idx_intentos_ingreso_usuario
  on public.intentos_ingreso (nombre_usuario, creado_en desc);

-- Ninguna de estas tablas se lee desde el navegador: solo las funciones
-- `security definer` de mas abajo las tocan.
alter table public.sesiones             enable row level security;
alter table public.registros_pendientes enable row level security;
alter table public.intentos_ingreso     enable row level security;
revoke all on table public.sesiones, public.registros_pendientes,
                    public.intentos_ingreso
  from anon, authenticated;

-- ---------------------------------------------------------------------
-- Utilidades compartidas
-- ---------------------------------------------------------------------
-- Se borra antes de crearla porque en versiones anteriores devolvia `void`,
-- y `create or replace function` no permite cambiar el tipo de retorno.
drop function if exists public.fn_error_onix(text, text);
create function public.fn_error_onix(p_motivo text, p_mensaje text)
returns jsonb
language sql
immutable
as $$
  select jsonb_build_object(
    'error', jsonb_build_object('motivo', p_motivo, 'mensaje', p_mensaje)
  );
$$;

-- Nunca incluye el hash de la contrasena.
create or replace function public.fn_participante_json(p public.participantes)
returns jsonb
language sql
stable
set search_path = public
as $$
  select jsonb_build_object(
    'id',                  p.id,
    'nombre',              p.nombre,
    'nombre_usuario',      p.nombre_usuario,
    'telefono_e164',       p.telefono_e164,
    'codigo_invitador',    p.codigo_invitador,
    'telefono_verificado', p.telefono_verificado,
    'ganador_prueba',      p.ganador_prueba,
    'creado_en',           p.creado_en,
    'referidos_validos',   (select count(*) from public.referidos
                             where invitador_id = p.id and estado = 'valido'),
    'referidos_pendientes',(select count(*) from public.referidos
                             where invitador_id = p.id and estado = 'pendiente')
  );
$$;

create or replace function public.fn_invitacion_json(i public.invitaciones)
returns jsonb
language sql
stable
as $$
  select jsonb_build_object(
    'id',              i.id,
    'codigo',          i.codigo,
    'creado_en',       i.creado_en,
    'expira_en',       i.expira_en,
    'usada_en',        i.usada_en,
    'nombre_invitado', (select p.nombre from public.participantes p
                          where p.id = i.usada_por_id)
  );
$$;

create or replace function public.fn_desafio_json(r public.registros_pendientes)
returns jsonb
language sql
stable
as $$
  select jsonb_build_object(
    'id',            r.id,
    'telefono_e164', r.telefono_e164,
    'expira_en',     r.expira_en
  );
$$;

-- Participante activo dueno de un token de sesion vigente, o null.
create or replace function public.fn_participante_de_sesion(p_token uuid)
returns public.participantes
language sql
stable
security definer
set search_path = public
as $$
  select p.*
    from public.sesiones s
    join public.participantes p on p.id = s.participante_id
   where s.token = p_token
     and s.expira_en > now()
     and p.estado = 'activo';
$$;

-- Deja del detalle del dispositivo solo los campos conocidos y con largo
-- acotado: viene del navegador y no se le puede dar un espacio sin limite.
create or replace function public.fn_dispositivo_limpio(p jsonb)
returns jsonb
language sql
immutable
set search_path = public
as $$
  select case
    when p is null or jsonb_typeof(p) <> 'object' then null
    else jsonb_strip_nulls(jsonb_build_object(
      'firma',        left(p->>'firma', 80),
      'descripcion',  left(p->>'descripcion', 120),
      'agente',       left(p->>'agente', 400),
      'plataforma',   left(p->>'plataforma', 60),
      'idioma',       left(p->>'idioma', 40),
      'pantalla',     left(p->>'pantalla', 40),
      'zona_horaria', left(p->>'zona_horaria', 60),
      'nucleos',      left(p->>'nucleos', 8),
      'tactil',       left(p->>'tactil', 8)
    ))
  end;
$$;

-- La version anterior no recibia la huella del dispositivo.
drop function if exists public.fn_revisar_invitacion(text, text);

-- ¿Sirve este codigo de invitacion para este telefono y este dispositivo?
-- Devuelve null si todo esta en orden, o el error listo para devolver al
-- cliente.
create or replace function public.fn_revisar_invitacion(
  p_codigo   text,
  p_telefono text,
  p_huella   text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_invitacion public.invitaciones;
  v_invitador  public.participantes;
begin
  if p_codigo is null then
    return null;
  end if;

  select * into v_invitacion from public.invitaciones where codigo = p_codigo;

  if v_invitacion.id is null then
    return public.fn_error_onix('codigoInexistente',
      'No encontramos ese código de invitación.');
  end if;

  if v_invitacion.usada_en is not null then
    return public.fn_error_onix('codigoYaUsado',
      'Ese código de invitación ya fue usado por otra persona. Pide uno nuevo a quien te invitó.');
  end if;

  if v_invitacion.expira_en < now() then
    return public.fn_error_onix('codigoExpirado',
      'Ese código de invitación venció. Pide uno nuevo a quien te invitó.');
  end if;

  select * into v_invitador
    from public.participantes
   where id = v_invitacion.invitador_id;

  if v_invitador.id is null or v_invitador.estado <> 'activo' then
    return public.fn_error_onix('codigoInexistente',
      'Ese código de invitación ya no está disponible.');
  end if;

  if v_invitador.telefono_e164 = p_telefono then
    return public.fn_error_onix('autoReferido',
      'No puedes invitarte a ti mismo.');
  end if;

  -- Anclaje del dispositivo -------------------------------------------
  -- Sin identificador de dispositivo no hay nada que anclar, y el ticket
  -- del invitador depende justamente de ese anclaje.
  if p_huella is null then
    return public.fn_error_onix('dispositivoNoIdentificado',
      'No pudimos identificar tu dispositivo. Permite que el sitio guarde datos en tu navegador (sin modo incógnito) y vuelve a intentarlo.');
  end if;

  -- Un dispositivo se ancla a un único código en toda la campaña.
  if exists (select 1 from public.invitaciones where huella_invitado = p_huella) then
    return public.fn_error_onix('dispositivoYaAnclado',
      'Este dispositivo ya se usó para aceptar una invitación. Cada invitado debe registrarse desde su propio celular.');
  end if;

  -- Quien invita no puede registrar a sus invitados desde su propio
  -- dispositivo: se compara con el del registro y con los de sus ingresos.
  if v_invitador.huella_dispositivo = p_huella
     or exists (select 1 from public.sesiones
                 where participante_id = v_invitador.id and huella = p_huella)
     or exists (select 1 from public.intentos_ingreso
                 where nombre_usuario = v_invitador.nombre_usuario
                   and exito and huella = p_huella) then
    return public.fn_error_onix('dispositivoDelInvitador',
      'Este código no se puede usar desde el dispositivo de quien te invitó. Regístrate desde tu propio celular.');
  end if;

  return null;
end;
$$;

-- =====================================================================
--  REGISTRO · sólo lo ejecuta la Edge Function (service_role)
-- =====================================================================

-- ---------------------------------------------------------------------
-- Paso 1 · Validar y dejar el registro a la espera del SMS
-- ---------------------------------------------------------------------
-- La version anterior no recibia el detalle del dispositivo.
drop function if exists public.cuenta_preparar_registro(text, text, text, text, text, text, text);

create or replace function public.cuenta_preparar_registro(
  p_nombre           text,
  p_nombre_usuario   text,
  p_contrasena       text,
  p_telefono         text,
  p_codigo_invitador text default null,
  p_huella           text default null,
  p_ip               text default null,
  p_dispositivo      jsonb default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_nombre    text := trim(coalesce(p_nombre, ''));
  v_usuario   text := ltrim(lower(trim(coalesce(p_nombre_usuario, ''))), '@');
  v_telefono  text := trim(coalesce(p_telefono, ''));
  v_codigo    text := nullif(upper(trim(coalesce(p_codigo_invitador, ''))), '');
  v_huella    text := left(nullif(trim(coalesce(p_huella, '')), ''), 120);
  v_dispositivo jsonb := public.fn_dispositivo_limpio(p_dispositivo);
  v_ip        inet;
  v_error     jsonb;
  v_conteo    int;
  v_ultimo    timestamptz;
  v_pendiente public.registros_pendientes;
  c_max_por_dispositivo   constant int := 3;
  c_max_sms_por_telefono  constant int := 5;   -- por hora
  c_max_sms_por_ip        constant int := 10;  -- por hora
  c_max_sms_por_huella    constant int := 6;   -- por hora
begin
  begin
    v_ip := nullif(trim(coalesce(p_ip, '')), '')::inet;
  exception when others then
    v_ip := null;
  end;

  -- Datos de la cuenta -------------------------------------------------
  if char_length(v_nombre) not between 3 and 80 then
    return public.fn_error_onix('desconocido', 'Escribe tu nombre completo.');
  end if;

  if v_usuario !~ '^[a-z0-9][a-z0-9_.]{2,19}$' then
    return public.fn_error_onix('usuarioInvalido',
      'El nombre de usuario debe tener entre 3 y 20 caracteres: letras sin tilde, números, punto o guion bajo.');
  end if;

  if p_contrasena is null
     or char_length(p_contrasena) < 8
     or octet_length(p_contrasena) > 72
     or p_contrasena !~ '[A-Za-z]'
     or p_contrasena !~ '[0-9]' then
    return public.fn_error_onix('contrasenaInvalida',
      'La contraseña debe tener al menos 8 caracteres, con letras y números.');
  end if;

  -- Teléfono ------------------------------------------------------------
  if v_telefono !~ '^\+569[0-9]{8}$' and
     v_telefono !~ '^\+58(412|414|416|424|426)[0-9]{7}$' then
    return public.fn_error_onix('telefonoInvalido',
      'Necesitamos un número móvil chileno o venezolano válido.');
  end if;

  -- Un teléfono, una participación.
  if exists (select 1 from public.participantes where telefono_e164 = v_telefono) then
    return public.fn_error_onix('telefonoYaRegistrado',
      'Este número ya tiene una cuenta. Ingresa con tu usuario y contraseña.');
  end if;

  if exists (select 1 from public.participantes where nombre_usuario = v_usuario) then
    return public.fn_error_onix('usuarioYaRegistrado',
      'Ese nombre de usuario ya está en uso. Prueba con otro.');
  end if;

  -- Límite de cuentas por dispositivo en 24 horas.
  if v_huella is not null then
    select count(*) into v_conteo
      from public.participantes
     where huella_dispositivo = v_huella
       and creado_en > now() - interval '24 hours';

    if v_conteo >= c_max_por_dispositivo then
      insert into public.eventos_auditoria (tipo, detalle, ip)
      values ('limite_dispositivo', jsonb_build_object('huella', v_huella), v_ip);
      return public.fn_error_onix('limiteDispositivo',
        'Se alcanzó el límite de registros desde este dispositivo. Intenta de nuevo en 24 horas.');
    end if;
  end if;

  -- Código de invitación y anclaje del dispositivo.
  v_error := public.fn_revisar_invitacion(v_codigo, v_telefono, v_huella);
  if v_error is not null then
    return v_error;
  end if;

  -- Frenos al envío de SMS ---------------------------------------------
  -- Cada SMS cuesta dinero: estos límites evitan que alguien use la landing
  -- para disparar mensajes en masa (el llamado "SMS pumping").
  select max(enviado_en), coalesce(sum(envios), 0)
    into v_ultimo, v_conteo
    from public.registros_pendientes
   where telefono_e164 = v_telefono
     and estado <> 'cancelado'
     and creado_en > now() - interval '1 hour';

  if v_ultimo is not null and v_ultimo > now() - interval '45 seconds' then
    return public.fn_error_onix('demasiadosIntentos',
      'Espera unos segundos antes de pedir otro código.');
  end if;

  if v_conteo >= c_max_sms_por_telefono then
    return public.fn_error_onix('demasiadosIntentos',
      'Pediste demasiados códigos para este número. Intenta de nuevo en una hora.');
  end if;

  if v_ip is not null then
    select count(*) into v_conteo
      from public.registros_pendientes
     where ip = v_ip
       and estado <> 'cancelado'
       and creado_en > now() - interval '1 hour';

    if v_conteo >= c_max_sms_por_ip then
      return public.fn_error_onix('demasiadosIntentos',
        'Hay demasiadas solicitudes desde tu conexión. Intenta de nuevo en una hora.');
    end if;
  end if;

  if v_huella is not null then
    select count(*) into v_conteo
      from public.registros_pendientes
     where huella = v_huella
       and estado <> 'cancelado'
       and creado_en > now() - interval '1 hour';

    if v_conteo >= c_max_sms_por_huella then
      return public.fn_error_onix('demasiadosIntentos',
        'Hay demasiadas solicitudes desde este dispositivo. Intenta de nuevo en una hora.');
    end if;
  end if;

  insert into public.registros_pendientes (
    nombre, nombre_usuario, hash_contrasena, telefono_e164,
    codigo_invitador, huella, ip, firma, dispositivo
  ) values (
    v_nombre, v_usuario, crypt(p_contrasena, gen_salt('bf', 10)), v_telefono,
    v_codigo, v_huella, v_ip, v_dispositivo->>'firma', v_dispositivo
  )
  returning * into v_pendiente;

  return public.fn_desafio_json(v_pendiente);
end;
$$;

-- Twilio no pudo enviar el SMS: el registro no cuenta para los límites.
create or replace function public.cuenta_anular_envio(p_id uuid)
returns void
language sql
security definer
set search_path = public
as $$
  update public.registros_pendientes
     set estado = 'cancelado'
   where id = p_id and estado = 'enviado';
$$;

-- ---------------------------------------------------------------------
-- Reenvío · se consulta ANTES de pedirle a Twilio otro SMS
-- ---------------------------------------------------------------------
create or replace function public.cuenta_preparar_reenvio(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pendiente public.registros_pendientes;
  c_max_envios constant int := 5;
begin
  select * into v_pendiente
    from public.registros_pendientes
   where id = p_id
     for update;

  if v_pendiente.id is null or v_pendiente.estado <> 'enviado' then
    return public.fn_error_onix('verificacionExpirada',
      'La verificación expiró. Vuelve a empezar.');
  end if;

  if v_pendiente.enviado_en > now() - interval '45 seconds' then
    return public.fn_error_onix('demasiadosIntentos',
      'Espera unos segundos antes de pedir otro código.');
  end if;

  if v_pendiente.envios >= c_max_envios then
    return public.fn_error_onix('demasiadosIntentos',
      'Ya pediste demasiados códigos. Intenta de nuevo en una hora.');
  end if;

  update public.registros_pendientes
     set envios     = envios + 1,
         enviado_en = now(),
         expira_en  = now() + interval '10 minutes',
         intentos   = 0
   where id = p_id
  returning * into v_pendiente;

  return public.fn_desafio_json(v_pendiente);
end;
$$;

-- ---------------------------------------------------------------------
-- Paso 2 · Datos del registro para pedirle a Twilio que revise el código
-- ---------------------------------------------------------------------
create or replace function public.cuenta_registro_para_verificar(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pendiente public.registros_pendientes;
  c_max_intentos constant int := 5;
begin
  select * into v_pendiente from public.registros_pendientes where id = p_id;

  if v_pendiente.id is null
     or v_pendiente.estado <> 'enviado'
     or v_pendiente.expira_en < now() then
    return public.fn_error_onix('verificacionExpirada',
      'El código expiró. Pide uno nuevo.');
  end if;

  if v_pendiente.intentos >= c_max_intentos then
    return public.fn_error_onix('demasiadosIntentos',
      'Demasiados intentos fallidos. Pide un código nuevo.');
  end if;

  return public.fn_desafio_json(v_pendiente);
end;
$$;

-- Twilio dijo que el código no coincide.
create or replace function public.cuenta_registrar_fallo(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pendiente public.registros_pendientes;
  c_max_intentos constant int := 5;
begin
  update public.registros_pendientes
     set intentos = intentos + 1
   where id = p_id and estado = 'enviado'
  returning * into v_pendiente;

  if v_pendiente.id is null then
    return public.fn_error_onix('verificacionExpirada',
      'La verificación expiró. Vuelve a empezar.');
  end if;

  insert into public.intentos_verificacion (telefono_e164, ip, huella, exito)
  values (v_pendiente.telefono_e164, v_pendiente.ip, v_pendiente.huella, false);

  if v_pendiente.intentos >= c_max_intentos then
    return public.fn_error_onix('demasiadosIntentos',
      'Demasiados intentos fallidos. Pide un código nuevo.');
  end if;

  return public.fn_error_onix('codigoVerificacionIncorrecto',
    'El código no coincide. Revisa el SMS e intenta de nuevo.');
end;
$$;

-- ---------------------------------------------------------------------
-- Paso 2 · Twilio aprobó el código: nace el participante
--
-- Es el único punto donde se crea una cuenta y donde un referido pasa a
-- válido: la verificación es la prueba de que hay una persona detrás.
-- ---------------------------------------------------------------------
create or replace function public.cuenta_completar_registro(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pendiente  public.registros_pendientes;
  v_invitacion public.invitaciones;
  v_persona    public.participantes;
  v_error      jsonb;
  v_token      uuid;
  v_restriccion text;
begin
  -- `for update` serializa dos confirmaciones simultáneas del mismo código.
  select * into v_pendiente
    from public.registros_pendientes
   where id = p_id
     for update;

  if v_pendiente.id is null or v_pendiente.estado <> 'enviado' then
    return public.fn_error_onix('verificacionExpirada',
      'La verificación expiró. Vuelve a empezar.');
  end if;

  -- Se vuelve a comprobar todo: entre el paso 1 y el paso 2 pudo
  -- registrarse el mismo número o el mismo usuario, o pudo canjearse o
  -- vencer la invitación.
  if exists (select 1 from public.participantes
              where telefono_e164 = v_pendiente.telefono_e164) then
    return public.fn_error_onix('telefonoYaRegistrado',
      'Este número ya tiene una cuenta. Ingresa con tu usuario y contraseña.');
  end if;

  if exists (select 1 from public.participantes
              where nombre_usuario = v_pendiente.nombre_usuario) then
    return public.fn_error_onix('usuarioYaRegistrado',
      'Otra persona tomó ese nombre de usuario mientras verificabas. Vuelve atrás y elige otro.');
  end if;

  if v_pendiente.codigo_invitador is not null then
    select * into v_invitacion
      from public.invitaciones
     where codigo = v_pendiente.codigo_invitador
       for update;

    v_error := public.fn_revisar_invitacion(
      v_pendiente.codigo_invitador, v_pendiente.telefono_e164,
      v_pendiente.huella);
    if v_error is not null then
      return v_error;
    end if;
  end if;

  -- El alta del participante y el anclaje del dispositivo van en el mismo
  -- bloque: si el dispositivo se ancló a otro código en paralelo, el índice
  -- único salta y se deshacen las dos cosas juntas.
  begin
    insert into public.participantes (
      nombre, nombre_usuario, hash_contrasena, telefono_e164,
      codigo_invitador, telefono_verificado, huella_dispositivo, ip_registro,
      firma_dispositivo, dispositivo
    ) values (
      v_pendiente.nombre, v_pendiente.nombre_usuario,
      v_pendiente.hash_contrasena, v_pendiente.telefono_e164,
      v_invitacion.codigo, true, v_pendiente.huella, v_pendiente.ip,
      v_pendiente.firma, v_pendiente.dispositivo
    )
    returning * into v_persona;

    if v_invitacion.id is not null then
      update public.invitaciones
         set usada_en             = now(),
             usada_por_id         = v_persona.id,
             huella_invitado      = v_pendiente.huella,
             firma_invitado       = v_pendiente.firma,
             dispositivo_invitado = v_pendiente.dispositivo,
             ip_invitado          = v_pendiente.ip
       where id = v_invitacion.id;
    end if;
  exception when unique_violation then
    get stacked diagnostics v_restriccion = constraint_name;
    if v_restriccion = 'idx_invitaciones_huella_invitado' then
      return public.fn_error_onix('dispositivoYaAnclado',
        'Este dispositivo ya se usó para aceptar una invitación. Cada invitado debe registrarse desde su propio celular.');
    end if;
    return public.fn_error_onix('telefonoYaRegistrado',
      'Ese número o ese nombre de usuario acaban de registrarse. Vuelve a intentarlo.');
  end;

  if v_invitacion.id is not null then
    insert into public.referidos (
      invitador_id, invitado_id, estado, validado_en, madura_en
    ) values (
      v_invitacion.invitador_id, v_persona.id, 'valido', now(),
      now() + interval '72 hours'
    );
  end if;

  update public.registros_pendientes
     set estado = 'verificado'
   where id = p_id;

  insert into public.intentos_verificacion (telefono_e164, ip, huella, exito)
  values (v_pendiente.telefono_e164, v_pendiente.ip, v_pendiente.huella, true);

  insert into public.eventos_auditoria (tipo, participante_id, detalle, ip)
  values ('alta_participante', v_persona.id,
          jsonb_build_object('invitador', v_invitacion.codigo,
                             'verificacion', 'twilio',
                             'dispositivo_anclado', v_invitacion.id is not null),
          v_pendiente.ip);

  insert into public.sesiones (participante_id, huella)
  values (v_persona.id, v_pendiente.huella)
  returning token into v_token;

  return public.fn_participante_json(v_persona)
      || jsonb_build_object('token_sesion', v_token);
end;
$$;

-- =====================================================================
--  INGRESO Y PANEL · públicas (anon), protegidas por el token de sesión
-- =====================================================================

-- ---------------------------------------------------------------------
-- Iniciar sesión con usuario y contraseña (sin SMS)
-- ---------------------------------------------------------------------
create or replace function public.cuenta_iniciar_sesion(
  p_nombre_usuario text,
  p_contrasena     text,
  p_huella         text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_usuario  text := ltrim(lower(trim(coalesce(p_nombre_usuario, ''))), '@');
  v_huella   text := nullif(trim(coalesce(p_huella, '')), '');
  v_persona  public.participantes;
  v_fallos   int;
  v_correcta boolean;
  v_token    uuid;
  c_max_fallos constant int := 5;   -- por usuario, cada 15 minutos
begin
  if v_usuario = '' or coalesce(p_contrasena, '') = '' then
    return public.fn_error_onix('credencialesIncorrectas',
      'Escribe tu usuario y tu contraseña.');
  end if;

  select count(*) into v_fallos
    from public.intentos_ingreso
   where nombre_usuario = v_usuario
     and exito = false
     and creado_en > now() - interval '15 minutes';

  if v_fallos >= c_max_fallos then
    return public.fn_error_onix('demasiadosIntentos',
      'Demasiados intentos fallidos. Espera 15 minutos antes de volver a intentar.');
  end if;

  select * into v_persona
    from public.participantes
   where nombre_usuario = v_usuario;

  -- Si el usuario no existe igual se calcula un bcrypt, para que el tiempo
  -- de respuesta no delate qué usuarios existen.
  v_correcta := crypt(
    p_contrasena,
    coalesce(v_persona.hash_contrasena, gen_salt('bf', 10))
  ) = v_persona.hash_contrasena;

  if v_persona.id is null or v_correcta is not true then
    insert into public.intentos_ingreso (nombre_usuario, huella, exito)
    values (v_usuario, v_huella, false);
    return public.fn_error_onix('credencialesIncorrectas',
      'Usuario o contraseña incorrectos.');
  end if;

  if v_persona.estado <> 'activo' then
    return public.fn_error_onix('noRegistrado',
      'Esta cuenta no está habilitada para participar.');
  end if;

  insert into public.intentos_ingreso (nombre_usuario, huella, exito)
  values (v_usuario, v_huella, true);

  -- Aprovecha para limpiar las sesiones vencidas de esta persona.
  delete from public.sesiones
   where participante_id = v_persona.id and expira_en < now();

  insert into public.sesiones (participante_id, huella)
  values (v_persona.id, v_huella)
  returning token into v_token;

  return public.fn_participante_json(v_persona)
      || jsonb_build_object('token_sesion', v_token);
end;
$$;

create or replace function public.sesion_cerrar(p_token uuid)
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.sesiones where token = p_token;
$$;

create or replace function public.sesion_participante(p_token uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_persona public.participantes := public.fn_participante_de_sesion(p_token);
begin
  if v_persona.id is null then
    return null;
  end if;
  return public.fn_participante_json(v_persona);
end;
$$;

create or replace function public.sesion_mis_referidos(p_token uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_persona public.participantes := public.fn_participante_de_sesion(p_token);
begin
  if v_persona.id is null then
    return '[]'::jsonb;
  end if;

  return coalesce((
    select jsonb_agg(fila order by fila->>'creado_en' desc)
      from (
        select jsonb_build_object(
                 'id',                r.id,
                 'nombre_invitado',   split_part(trim(i.nombre), ' ', 1),
                 'telefono_invitado',
                   case
                     when i.telefono_e164 like '+56%' then '+56 9 •••• ••'
                     else '+58 4•• ••• ••'
                   end || right(i.telefono_e164, 2),
                 'estado',            r.estado,
                 'motivo_rechazo',    r.motivo_rechazo,
                 'creado_en',         r.creado_en
               ) as fila
          from public.referidos r
          join public.participantes i on i.id = r.invitado_id
         where r.invitador_id = v_persona.id
      ) s
  ), '[]'::jsonb);
end;
$$;

create or replace function public.sesion_generar_invitacion(
  p_token         uuid,
  p_horas_validez int default 168
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_persona public.participantes := public.fn_participante_de_sesion(p_token);
  v_nueva   public.invitaciones;
  v_horas   int := least(greatest(coalesce(p_horas_validez, 168), 1), 720);
begin
  if v_persona.id is null then
    return public.fn_error_onix('noRegistrado',
      'Tu sesión expiró. Vuelve a ingresar.');
  end if;

  insert into public.invitaciones (invitador_id, codigo, expira_en)
  values (
    v_persona.id,
    public.fn_generar_codigo_invitacion(),
    now() + make_interval(hours => v_horas)
  )
  returning * into v_nueva;

  return public.fn_invitacion_json(v_nueva);
end;
$$;

create or replace function public.sesion_mis_invitaciones(p_token uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_persona public.participantes := public.fn_participante_de_sesion(p_token);
begin
  if v_persona.id is null then
    return '[]'::jsonb;
  end if;

  return coalesce((
    select jsonb_agg(public.fn_invitacion_json(i) order by i.creado_en desc)
      from public.invitaciones i
     where i.invitador_id = v_persona.id
  ), '[]'::jsonb);
end;
$$;

-- ---------------------------------------------------------------------
-- Permisos
--
-- Postgres concede EXECUTE a PUBLIC en toda función nueva, y Supabase
-- además se lo da a `anon` y `authenticated`. Por eso primero se revoca
-- todo y después se concede sólo lo que corresponde.
-- ---------------------------------------------------------------------
revoke execute on function public.fn_participante_de_sesion(uuid)          from public, anon, authenticated;
revoke execute on function public.fn_revisar_invitacion(text, text, text)  from public, anon, authenticated;
revoke execute on function public.cuenta_preparar_registro(text, text, text, text, text, text, text, jsonb) from public, anon, authenticated;
revoke execute on function public.cuenta_anular_envio(uuid)                from public, anon, authenticated;
revoke execute on function public.cuenta_preparar_reenvio(uuid)            from public, anon, authenticated;
revoke execute on function public.cuenta_registro_para_verificar(uuid)     from public, anon, authenticated;
revoke execute on function public.cuenta_registrar_fallo(uuid)             from public, anon, authenticated;
revoke execute on function public.cuenta_completar_registro(uuid)          from public, anon, authenticated;

-- Registro: sólo la Edge Function `verificar-telefono`.
grant execute on function public.cuenta_preparar_registro(text, text, text, text, text, text, text, jsonb) to service_role;
grant execute on function public.cuenta_anular_envio(uuid)                 to service_role;
grant execute on function public.cuenta_preparar_reenvio(uuid)             to service_role;
grant execute on function public.cuenta_registro_para_verificar(uuid)      to service_role;
grant execute on function public.cuenta_registrar_fallo(uuid)              to service_role;
grant execute on function public.cuenta_completar_registro(uuid)           to service_role;

-- Ingreso y panel: el navegador, con el token de sesión como llave.
grant execute on function public.cuenta_iniciar_sesion(text, text, text)   to anon, authenticated;
grant execute on function public.sesion_cerrar(uuid)                       to anon, authenticated;
grant execute on function public.sesion_participante(uuid)                 to anon, authenticated;
grant execute on function public.sesion_mis_referidos(uuid)                to anon, authenticated;
grant execute on function public.sesion_generar_invitacion(uuid, int)      to anon, authenticated;
grant execute on function public.sesion_mis_invitaciones(uuid)             to anon, authenticated;

-- =====================================================================
--  Limpieza de datos de prueba · EJECUTAR ANTES DE ABRIR LA CAMPAÑA
--  Borra participantes, invitaciones y registros creados durante las
--  pruebas. No toca el esquema.
-- =====================================================================
-- truncate public.tickets_sorteo, public.referidos, public.invitaciones,
--          public.sesiones, public.registros_pendientes,
--          public.intentos_verificacion, public.intentos_ingreso,
--          public.eventos_auditoria cascade;
-- delete from public.participantes;
--
-- Los reclamos de premio y las notificaciones del panel admin se borran
-- solos con los participantes (on delete cascade).
