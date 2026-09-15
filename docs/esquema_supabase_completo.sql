-- =====================================================================
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
--  Generado el 2026-09-15
-- =====================================================================

-- =====================================================================
--  Reto 50 Onix · Esquema de la campaña de referidos para Supabase
--  Proyecto independiente de Onix Drive (base de datos propia).
--
--  Estrategia general
--  ------------------
--  1. La identidad de un participante es su teléfono verificado. El
--     teléfono se confirma UNA vez, al crear la cuenta, con un código que
--     envía Twilio Verify desde la Edge Function `verificar-telefono`
--     (ver docs/esquema_supabase_cuentas.sql). Para volver a entrar se usa
--     nombre de usuario y contraseña, sin SMS.
--  2. El cliente NUNCA escribe directo en las tablas. Todo pasa por
--     funciones `security definer` que aplican las reglas anti-fraude.
--  3. Lo que se puede expresar como restricción de base de datos se
--     expresa como restricción: es la única defensa que no se olvida.
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- Participantes
-- ---------------------------------------------------------------------
create table if not exists public.participantes (
  id                  uuid primary key default gen_random_uuid(),
  usuario_id          uuid unique references auth.users (id) on delete cascade,
  nombre              text not null,
  -- Identidad única de la campaña. Movil chileno o venezolano en E.164.
  telefono_e164       text not null unique,
  -- Código de invitación (de un solo uso) que se canjeó al registrarse. NO
  -- es un código propio: para invitar gente, cada participante genera
  -- códigos nuevos en la tabla `invitaciones`. Sin FK inline porque
  -- `invitaciones` referencia a su vez esta tabla (dependencia circular);
  -- la relación se agrega mas abajo con `alter table`.
  codigo_invitador    text,
  telefono_verificado boolean not null default false,
  estado              text not null default 'activo',
  huella_dispositivo  text,
  ip_registro         inet,
  creado_en           timestamptz not null default now(),

  constraint nombre_razonable
    check (char_length(trim(nombre)) between 3 and 80),
  -- Movil chileno (+56 9 XXXXXXXX) o venezolano (+58 4XX XXXXXXX, con las
  -- cinco operadoras que existen hoy: 412, 414, 416, 424, 426).
  constraint telefono_movil_valido
    check (
      telefono_e164 ~ '^\+569[0-9]{8}$' or
      telefono_e164 ~ '^\+58(412|414|416|424|426)[0-9]{7}$'
    ),
  constraint estado_valido
    check (estado in ('activo', 'suspendido', 'descalificado'))
);

create index if not exists idx_participantes_invitador
  on public.participantes (codigo_invitador);
create index if not exists idx_participantes_huella
  on public.participantes (huella_dispositivo, creado_en);

-- Firma del navegador (hash de sus caracteristicas: pantalla, idioma, zona
-- horaria, motor grafico...) y un resumen legible del dispositivo. La
-- huella de arriba es un identificador guardado en el navegador; la firma
-- sirve para detectar a quien borra ese identificador o usa modo incognito.
alter table public.participantes
  add column if not exists firma_dispositivo text;
alter table public.participantes
  add column if not exists dispositivo jsonb;

-- Lo activa el panel admin para que una cuenta pueda probar el reclamo de
-- premio (las tres cajas) sin haber llegado a los 50 tickets.
alter table public.participantes
  add column if not exists ganador_prueba boolean not null default false;

-- Inmutabilidad: el teléfono y el invitador no cambian una vez fijados.
-- Esta es LA regla que impide que alguien reutilice un código de invitación.
create or replace function public.fn_campos_inmutables()
returns trigger
language plpgsql
as $$
begin
  if new.telefono_e164 is distinct from old.telefono_e164 then
    raise exception 'El teléfono de un participante no se puede cambiar';
  end if;
  if old.codigo_invitador is not null
     and new.codigo_invitador is distinct from old.codigo_invitador then
    raise exception 'El código de invitación ya fue aplicado y es definitivo';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_campos_inmutables on public.participantes;
create trigger trg_campos_inmutables
  before update on public.participantes
  for each row execute function public.fn_campos_inmutables();

-- ---------------------------------------------------------------------
-- Referidos (la relación invitador -> invitado)
-- ---------------------------------------------------------------------
create table if not exists public.referidos (
  id              uuid primary key default gen_random_uuid(),
  invitador_id    uuid not null references public.participantes (id) on delete cascade,
  -- UNIQUE: una persona sólo puede ser invitada una vez en toda la campaña.
  invitado_id     uuid not null unique references public.participantes (id) on delete cascade,
  estado          text not null default 'pendiente',
  motivo_rechazo  text,
  creado_en       timestamptz not null default now(),
  validado_en     timestamptz,
  madura_en       timestamptz,

  constraint estado_referido_valido
    check (estado in ('pendiente', 'valido', 'rechazado')),
  constraint sin_autorreferido_fila
    check (invitador_id <> invitado_id)
);

create index if not exists idx_referidos_invitador
  on public.referidos (invitador_id, estado);

-- Verificación redundante contra cadenas circulares. Con el flujo actual el
-- grafo ya es un bosque (cada participante nace con un único padre que ya
-- existía), pero si algún día se permite asignar invitador más tarde, esta
-- función evita que A invite a B y B invite a A.
create or replace function public.fn_sin_ciclos()
returns trigger
language plpgsql
as $$
declare
  actual uuid := new.invitador_id;
  saltos int := 0;
begin
  while actual is not null and saltos < 50 loop
    if actual = new.invitado_id then
      raise exception 'Invitación circular detectada';
    end if;
    select r.invitador_id into actual
      from public.referidos r
     where r.invitado_id = actual;
    saltos := saltos + 1;
  end loop;
  return new;
end;
$$;

drop trigger if exists trg_sin_ciclos on public.referidos;
create trigger trg_sin_ciclos
  before insert or update on public.referidos
  for each row execute function public.fn_sin_ciclos();

-- ---------------------------------------------------------------------
-- Invitaciones: codigos de un solo uso
--
-- Un participante NO tiene un codigo propio y fijo para compartir. Cada vez
-- que quiere invitar a una persona concreta genera una fila nueva aqui, con
-- su propio codigo. En cuanto alguien se registra con ese codigo (o vence
-- el plazo) la fila queda cerrada para siempre.
-- ---------------------------------------------------------------------
create table if not exists public.invitaciones (
  id            uuid primary key default gen_random_uuid(),
  invitador_id  uuid not null references public.participantes (id) on delete cascade,
  -- 8 caracteres del alfabeto sin ambiguedades (mismo formato visible
  -- ONX-XXXX-XXXX que arma el cliente).
  codigo        text not null unique,
  creado_en     timestamptz not null default now(),
  expira_en     timestamptz not null,
  -- Se llenan una unica vez, al canjearse. Ahi vive la garantia de "un
  -- codigo, un uso".
  usada_en      timestamptz,
  usada_por_id  uuid references public.participantes (id) on delete set null,

  constraint usada_es_consistente
    check ((usada_en is null) = (usada_por_id is null))
);

-- Mismo alfabeto que `CodigoReferido.alfabeto` en Dart y que
-- `fn_generar_codigo_invitacion`: sin I, L, O, 0 ni 1. Se recrea aparte
-- porque una version anterior excluia la U y admitia la L, y eso hacia
-- fallar cerca de 1 de cada 4 codigos generados.
alter table public.invitaciones
  drop constraint if exists formato_codigo_invitacion;
alter table public.invitaciones
  add constraint formato_codigo_invitacion
  check (codigo ~ '^[2-9A-HJKMNP-Z]{8}$');

create index if not exists idx_invitaciones_invitador
  on public.invitaciones (invitador_id, creado_en desc);

-- Anclaje del dispositivo del invitado.
--
-- Cuando alguien se registra con un codigo, el dispositivo desde el que lo
-- hace queda anclado a ese codigo para siempre, y solo entonces el
-- invitador suma su ticket. Un dispositivo puede anclarse a UN unico codigo
-- en toda la campana: asi nadie puede registrar a sus "invitados" desde su
-- propio celular. El indice unico es la garantia real; las funciones de
-- registro solo traducen el error a un mensaje entendible.
alter table public.invitaciones
  add column if not exists huella_invitado text;
alter table public.invitaciones
  add column if not exists firma_invitado text;
alter table public.invitaciones
  add column if not exists dispositivo_invitado jsonb;
alter table public.invitaciones
  add column if not exists ip_invitado inet;

create unique index if not exists idx_invitaciones_huella_invitado
  on public.invitaciones (huella_invitado)
  where huella_invitado is not null;
create index if not exists idx_invitaciones_firma_invitado
  on public.invitaciones (firma_invitado)
  where firma_invitado is not null;

-- Una invitacion canjeada siempre tiene un dispositivo anclado. `not valid`
-- deja pasar filas antiguas, si las hubiera, pero obliga a todas las nuevas.
alter table public.invitaciones
  drop constraint if exists invitacion_anclada;
alter table public.invitaciones
  add constraint invitacion_anclada
  check (usada_en is null or huella_invitado is not null) not valid;

-- Ahora que `invitaciones` existe, se cierra la relacion circular: el
-- codigo_invitador de un participante debe ser un codigo de invitacion real.
alter table public.participantes
  drop constraint if exists fk_codigo_invitador;
alter table public.participantes
  add constraint fk_codigo_invitador
  foreign key (codigo_invitador) references public.invitaciones (codigo);

-- Inmutabilidad: una invitacion usada no puede "desusarse" ni reasignarse.
create or replace function public.fn_invitacion_inmutable()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if old.usada_en is not null and new.usada_en is distinct from old.usada_en then
    raise exception 'Esta invitación ya fue canjeada y es definitiva';
  end if;
  if old.huella_invitado is not null
     and new.huella_invitado is distinct from old.huella_invitado then
    raise exception 'El dispositivo anclado a esta invitación es definitivo';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_invitacion_inmutable on public.invitaciones;
create trigger trg_invitacion_inmutable
  before update on public.invitaciones
  for each row execute function public.fn_invitacion_inmutable();

-- ---------------------------------------------------------------------
-- Control de abuso: intentos de verificación y dispositivos
-- ---------------------------------------------------------------------
create table if not exists public.intentos_verificacion (
  id            bigserial primary key,
  telefono_e164 text not null,
  ip            inet,
  huella        text,
  exito         boolean not null default false,
  creado_en     timestamptz not null default now()
);

create index if not exists idx_intentos_telefono
  on public.intentos_verificacion (telefono_e164, creado_en desc);
create index if not exists idx_intentos_ip
  on public.intentos_verificacion (ip, creado_en desc);

-- ---------------------------------------------------------------------
-- Auditoría: append-only, la fuente de verdad ante una disputa
-- ---------------------------------------------------------------------
create table if not exists public.eventos_auditoria (
  id             bigserial primary key,
  tipo           text not null,
  participante_id uuid references public.participantes (id) on delete set null,
  detalle        jsonb not null default '{}'::jsonb,
  ip             inet,
  agente_usuario text,
  creado_en      timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- Sorteo
-- ---------------------------------------------------------------------
create table if not exists public.sorteos (
  id            uuid primary key default gen_random_uuid(),
  nombre        text not null,
  cierra_en     timestamptz not null,
  -- Se publica ANTES de ejecutar el sorteo.
  semilla       text,
  hash_tickets  text,
  ejecutado_en  timestamptz,
  creado_en     timestamptz not null default now()
);

create table if not exists public.tickets_sorteo (
  id             bigserial primary key,
  sorteo_id      uuid not null references public.sorteos (id) on delete cascade,
  participante_id uuid not null references public.participantes (id) on delete cascade,
  referido_id    uuid not null references public.referidos (id) on delete cascade,
  numero         bigint not null,
  creado_en      timestamptz not null default now(),

  -- Un referido válido genera exactamente un ticket por sorteo.
  unique (sorteo_id, referido_id),
  unique (sorteo_id, numero)
);

-- ---------------------------------------------------------------------
-- Vistas públicas (nunca exponen el teléfono completo)
-- ---------------------------------------------------------------------
-- Se borra antes de crearla: `create or replace view` no admite quitar ni
-- reordenar columnas, así que en cuanto la vista cambia de forma el archivo
-- dejaría de poder ejecutarse dos veces.
drop view if exists public.vista_ranking;
create view public.vista_ranking as
select
  row_number() over (
    order by count(r.id) desc, p.creado_en asc
  )                                                    as posicion,
  split_part(trim(p.nombre), ' ', 1) || ' ' ||
    left(coalesce(nullif(split_part(trim(p.nombre), ' ', 2), ''), ''), 1)
    || '.'                                             as nombre_visible,
  case
    when p.telefono_e164 like '+56%' then '+56 9 •••• ••'
    else '+58 4•• ••• ••'
  end || right(p.telefono_e164, 2)                     as telefono_enmascarado,
  count(r.id)                                          as referidos_validos,
  -- Deja que el ranking marque "este eres tú". El id por sí solo no permite
  -- leer nada: RLS sigue protegiendo la fila del participante.
  p.id                                                 as participante_id
from public.participantes p
left join public.referidos r
       on r.invitador_id = p.id
      and r.estado = 'valido'
where p.estado = 'activo'
group by p.id, p.nombre, p.telefono_e164, p.creado_en
order by referidos_validos desc, p.creado_en asc
limit 50;

-- `vista_estadisticas` alimentaba los contadores publicos del hero
-- (personas participando, invitaciones validas e intentos de trampa
-- bloqueados). La landing ya no los muestra y esas cifras quedan solo para
-- el panel admin, que las pide con su sesion.
drop view if exists public.vista_estadisticas;

-- ---------------------------------------------------------------------
-- Generación de códigos únicos de invitación
-- ---------------------------------------------------------------------
create or replace function public.fn_generar_codigo_invitacion()
returns text
language plpgsql
as $$
declare
  alfabeto  text := '23456789ABCDEFGHJKMNPQRSTUVWXYZ';
  cuerpo    text;
  suma      int;
  candidato text;
  intentos  int := 0;
begin
  loop
    cuerpo := '';
    for i in 1..7 loop
      cuerpo := cuerpo || substr(alfabeto, 1 + floor(random() * 31)::int, 1);
    end loop;

    -- Mismo dígito verificador que usa el cliente en Dart.
    suma := 0;
    for i in 1..7 loop
      suma := suma + (strpos(alfabeto, substr(cuerpo, i, 1))) * (i + 1);
    end loop;
    candidato := cuerpo || substr(alfabeto, 1 + (suma % 31), 1);

    exit when not exists (
      select 1 from public.invitaciones where codigo = candidato
    );

    intentos := intentos + 1;
    if intentos > 20 then
      raise exception 'No se pudo generar un código único';
    end if;
  end loop;

  return candidato;
end;
$$;

-- ---------------------------------------------------------------------
-- Alta de participantes e invitaciones
--
-- Una version anterior hacia el alta con Supabase Auth (`auth.uid()`).
-- Ya no se usa: la cuenta la crea `cuenta_completar_registro` despues de
-- que Twilio aprueba el codigo, y las invitaciones se generan con el token
-- de sesion (`sesion_generar_invitacion`). Ambas viven en
-- docs/esquema_supabase_cuentas.sql.
-- ---------------------------------------------------------------------
drop function if exists public.crear_invitacion(int);
drop function if exists public.crear_participacion(text, text, text);

-- ---------------------------------------------------------------------
-- Row Level Security
--
-- Supabase concede por defecto privilegios sobre las tablas nuevas de
-- `public` a los roles `anon` y `authenticated`. Una tabla sin RLS queda
-- por lo tanto legible y escribible por cualquiera que tenga la anon key,
-- que es publica. Por eso TODAS las tablas la activan, incluidas las que
-- la landing no consulta: `sorteos` define los premios y nadie debe poder
-- tocarla desde el navegador.
-- ---------------------------------------------------------------------
alter table public.participantes        enable row level security;
alter table public.referidos            enable row level security;
alter table public.invitaciones         enable row level security;
alter table public.eventos_auditoria    enable row level security;
alter table public.intentos_verificacion enable row level security;
alter table public.sorteos              enable row level security;
alter table public.tickets_sorteo       enable row level security;

-- Cada política se borra antes de crearla: `create policy` no admite
-- `if not exists`, y sin esto el archivo sólo se podría ejecutar una vez.
--
-- Cada quien ve sólo su propia fila. El alta ocurre por la función de
-- arriba (security definer), no por INSERT directo: no hay política de
-- INSERT, UPDATE ni DELETE, así que el cliente no puede escribir nada.
drop policy if exists participante_ve_lo_suyo on public.participantes;
create policy participante_ve_lo_suyo
  on public.participantes for select
  using (usuario_id = auth.uid());

drop policy if exists referidos_del_invitador on public.referidos;
create policy referidos_del_invitador
  on public.referidos for select
  using (
    invitador_id in (
      select id from public.participantes where usuario_id = auth.uid()
    )
  );

drop policy if exists tickets_propios on public.tickets_sorteo;
create policy tickets_propios
  on public.tickets_sorteo for select
  using (
    participante_id in (
      select id from public.participantes where usuario_id = auth.uid()
    )
  );

-- Cada quien ve solo las invitaciones que emitio. El alta ocurre por
-- `crear_invitacion` (security definer), no hay politica de INSERT ni
-- UPDATE: el cliente no puede fabricar ni cerrar codigos por su cuenta.
drop policy if exists invitaciones_del_invitador on public.invitaciones;
create policy invitaciones_del_invitador
  on public.invitaciones for select
  using (
    invitador_id in (
      select id from public.participantes where usuario_id = auth.uid()
    )
  );

-- Las vistas públicas se sirven con permisos explícitos y datos ya
-- enmascarados, por eso pueden leerse sin sesión.
grant select on public.vista_ranking to anon, authenticated;

-- =====================================================================
--  Funciones de lectura que consume la landing
--
--  El formulario necesita saber si un código de invitación sigue vigente
--  sin poder leer al dueño, y eso no se puede hacer con RLS a secas.
-- =====================================================================

-- ¿Sigue vigente este código de invitación (existe, no se usó y no
-- venció)? Se responde sin exponer al dueño.
create or replace function public.fn_invitacion_valida(p_codigo text)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.invitaciones
     where codigo = upper(trim(p_codigo))
       and usada_en is null
       and expira_en > now()
  );
$$;

grant execute on function public.fn_invitacion_valida(text) to anon, authenticated;

-- =====================================================================
--  ↓↓↓  SEGUNDA PARTE · CUENTAS, SESIONES Y VERIFICACIÓN CON TWILIO  ↓↓↓
-- =====================================================================

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

-- =====================================================================
--  ↓↓↓  TERCERA PARTE · PREMIO DE LAS TRES CAJAS  ↓↓↓
-- =====================================================================

-- =====================================================================
--  Reto 50 Onix · Premio de las tres cajas
--
--  Cómo funciona
--  -------------
--  1. Cada invitado que se registra con un código, verifica su teléfono y
--     ancla su dispositivo suma un ticket a quien lo invitó. Con 50
--     tickets aparece el botón «Reclamar premio».
--  2. `sesion_reclamar_premio` crea el reclamo y en ese mismo instante
--     esconde los tres premios (1 viaje gratis, un regalo Onix y $3.000 de
--     saldo Onix) en las tres cajas, con un orden aleatorio generado aquí
--     con bytes criptográficos. Cada reclamo tiene su propio orden: los
--     premios no están nunca fijos en la misma caja.
--  3. Ese orden NO viaja al navegador mientras las cajas están cerradas: la
--     landing solo sabe que hay tres cajas. Inspeccionar la red o el código
--     de la página no sirve para adivinar dónde está cada premio.
--  4. `sesion_abrir_caja` fija la caja elegida (una sola vez, con bloqueo
--     de fila), genera el código de confirmación que se imprime en el
--     ticket y avisa al panel admin. Recién entonces devuelve el premio y
--     dónde estaban los otros dos.
--
--  Requiere haber ejecutado antes docs/esquema_supabase.sql y
--  docs/esquema_supabase_cuentas.sql.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Reclamos de premio
-- ---------------------------------------------------------------------
create table if not exists public.reclamos_premio (
  id                  uuid primary key default gen_random_uuid(),
  participante_id     uuid not null references public.participantes (id) on delete cascade,
  -- Reclamo hecho con una cuenta habilitada como ganadora de prueba desde
  -- el panel admin, sin haber llegado a los 50 tickets.
  es_prueba           boolean not null default false,
  -- Premio escondido en cada caja: posiciones 1, 2 y 3 del arreglo.
  distribucion        text[] not null,
  -- Caja elegida (0, 1 o 2) y lo que había dentro. Se llenan una vez.
  caja_elegida        smallint,
  premio              text,
  codigo_confirmacion text unique,
  -- cajas_listas: reclamado, falta elegir caja
  -- pendiente:    caja abierta, espera la verificación del admin
  -- verificado:   el admin confirmó el código y los invitados
  -- entregado:    el premio ya se entregó
  -- rechazado:    el admin lo anuló (trampa detectada, datos falsos...)
  -- reiniciado:   reclamo de prueba descartado para volver a probar
  estado              text not null default 'cajas_listas',
  tickets_al_reclamar int not null default 0,
  creado_en           timestamptz not null default now(),
  abierto_en          timestamptz,
  revisado_en         timestamptz,
  revisado_por        text,
  nota_admin          text,

  -- Largo 3 y los tres premios presentes = una permutación exacta.
  constraint distribucion_valida check (
    array_length(distribucion, 1) = 3
    and distribucion @> array['viaje', 'regalo', 'saldo']
  ),
  constraint caja_valida check (caja_elegida between 0 and 2),
  constraint estado_reclamo_valido check (
    estado in ('cajas_listas', 'pendiente', 'verificado', 'entregado',
               'rechazado', 'reiniciado')
  ),
  -- O la caja sigue cerrada, o está abierta con TODO lo que corresponde, y
  -- el premio es exactamente el que estaba escondido en esa caja.
  constraint apertura_consistente check (
    (caja_elegida is null and premio is null
      and codigo_confirmacion is null and abierto_en is null)
    or
    (caja_elegida is not null and premio is not null
      and codigo_confirmacion is not null and abierto_en is not null
      and premio = distribucion[caja_elegida + 1])
  ),
  constraint revisar_requiere_caja_abierta check (
    estado in ('cajas_listas', 'reiniciado') or abierto_en is not null
  )
);

-- Un único reclamo vigente por participante: no se puede volver a barajar.
create unique index if not exists idx_reclamo_vigente_por_participante
  on public.reclamos_premio (participante_id)
  where estado <> 'reiniciado';
create index if not exists idx_reclamos_estado
  on public.reclamos_premio (estado, abierto_en desc);

-- Inmutabilidad: el orden de las cajas no cambia nunca y una caja abierta
-- no se puede "volver a elegir".
create or replace function public.fn_reclamo_inmutable()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.distribucion is distinct from old.distribucion then
    raise exception 'La distribución de las cajas es definitiva';
  end if;
  if new.participante_id is distinct from old.participante_id
     or new.es_prueba is distinct from old.es_prueba then
    raise exception 'El dueño de un reclamo no se puede cambiar';
  end if;
  if old.caja_elegida is not null and (
       new.caja_elegida is distinct from old.caja_elegida
       or new.premio is distinct from old.premio
       or new.codigo_confirmacion is distinct from old.codigo_confirmacion
       or new.abierto_en is distinct from old.abierto_en) then
    raise exception 'La caja ya fue abierta y su premio es definitivo';
  end if;
  if old.estado = 'reiniciado' and new.estado <> 'reiniciado' then
    raise exception 'Un reclamo reiniciado no se puede reactivar';
  end if;
  if new.estado = 'reiniciado' and old.estado <> 'reiniciado'
     and not old.es_prueba then
    raise exception 'Solo un reclamo de prueba se puede reiniciar';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_reclamo_inmutable on public.reclamos_premio;
create trigger trg_reclamo_inmutable
  before update on public.reclamos_premio
  for each row execute function public.fn_reclamo_inmutable();

-- ---------------------------------------------------------------------
-- Notificaciones para el panel admin
-- ---------------------------------------------------------------------
create table if not exists public.notificaciones_admin (
  id              bigserial primary key,
  tipo            text not null,
  reclamo_id      uuid references public.reclamos_premio (id) on delete cascade,
  participante_id uuid references public.participantes (id) on delete cascade,
  titulo          text not null,
  detalle         text not null default '',
  creado_en       timestamptz not null default now(),
  leida_en        timestamptz
);

create index if not exists idx_notificaciones_admin_recientes
  on public.notificaciones_admin (creado_en desc);

-- Nada de esto se lee desde el navegador: solo las funciones de abajo.
alter table public.reclamos_premio      enable row level security;
alter table public.notificaciones_admin enable row level security;
revoke all on table public.reclamos_premio, public.notificaciones_admin
  from anon, authenticated;

-- ---------------------------------------------------------------------
-- Utilidades
-- ---------------------------------------------------------------------

-- Tickets necesarios para reclamar el premio.
create or replace function public.fn_meta_tickets()
returns int
language sql
immutable
set search_path = public
as $$
  select 50;
$$;

-- Un ticket por invitado verificado con su dispositivo anclado.
create or replace function public.fn_tickets(p_participante uuid)
returns int
language sql
stable
security definer
set search_path = public
as $$
  select count(*)::int
    from public.referidos
   where invitador_id = p_participante
     and estado = 'valido';
$$;

-- Entero uniforme en [0, p_tope) a partir de bytes criptográficos. Se
-- descartan los bytes del final del rango para que ningún valor salga más
-- seguido que otro (sesgo del módulo).
create or replace function public.fn_entero_aleatorio(p_tope int)
returns int
language plpgsql
volatile
set search_path = public, extensions
as $$
declare
  v_byte int;
begin
  if p_tope < 1 or p_tope > 256 then
    raise exception 'Tope fuera de rango: %', p_tope;
  end if;
  loop
    v_byte := get_byte(gen_random_bytes(1), 0);
    exit when v_byte < 256 - (256 % p_tope);
  end loop;
  return v_byte % p_tope;
end;
$$;

-- Baraja los tres premios (Fisher-Yates). Si se indica `p_evitar`, el
-- resultado nunca repite ese mismo orden: así una cuenta de prueba que
-- vuelve a jugar siempre ve los premios cambiar de lugar.
create or replace function public.fn_distribucion_aleatoria(p_evitar text[] default null)
returns text[]
language plpgsql
volatile
set search_path = public
as $$
declare
  v_orden text[];
  v_j     int;
  v_tmp   text;
  v_vuelta int := 0;
begin
  loop
    v_orden := array['viaje', 'regalo', 'saldo'];
    for v_i in reverse 3..2 loop
      v_j := 1 + public.fn_entero_aleatorio(v_i);
      v_tmp := v_orden[v_i];
      v_orden[v_i] := v_orden[v_j];
      v_orden[v_j] := v_tmp;
    end loop;
    v_vuelta := v_vuelta + 1;
    exit when p_evitar is null or v_orden is distinct from p_evitar or v_vuelta > 50;
  end loop;
  return v_orden;
end;
$$;

-- Código de confirmación del ticket: 10 caracteres sin ambigüedades
-- (sin I, L, O, 0 ni 1). Se muestra como PRM-XXXXX-XXXXX.
create or replace function public.fn_generar_codigo_confirmacion()
returns text
language plpgsql
volatile
set search_path = public
as $$
declare
  alfabeto  text := '23456789ABCDEFGHJKMNPQRSTUVWXYZ';
  candidato text;
  intentos  int := 0;
begin
  loop
    candidato := '';
    for i in 1..10 loop
      candidato := candidato
        || substr(alfabeto, 1 + public.fn_entero_aleatorio(31), 1);
    end loop;
    exit when not exists (
      select 1 from public.reclamos_premio where codigo_confirmacion = candidato
    );
    intentos := intentos + 1;
    if intentos > 20 then
      raise exception 'No se pudo generar un código de confirmación único';
    end if;
  end loop;
  return candidato;
end;
$$;

create or replace function public.fn_codigo_confirmacion_visible(p_codigo text)
returns text
language sql
immutable
set search_path = public
as $$
  select case
    when p_codigo is null then null
    else 'PRM-' || substr(p_codigo, 1, 5) || '-' || substr(p_codigo, 6, 5)
  end;
$$;

create or replace function public.fn_nombre_premio(p_premio text)
returns text
language sql
immutable
set search_path = public
as $$
  select case p_premio
    when 'viaje'  then '1 viaje gratis'
    when 'regalo' then 'Un regalo Onix'
    when 'saldo'  then '$3.000 de saldo Onix'
    else p_premio
  end;
$$;

-- Lo que ve el participante de su reclamo. La distribución SOLO sale una
-- vez abierta la caja: antes, saber dónde está cada premio arruinaría el
-- juego.
create or replace function public.fn_reclamo_json(r public.reclamos_premio)
returns jsonb
language sql
stable
set search_path = public
as $$
  select jsonb_build_object(
    'id',                  r.id,
    'estado',              r.estado,
    'es_prueba',           r.es_prueba,
    'creado_en',           r.creado_en,
    'abierto_en',          r.abierto_en,
    'caja_elegida',        r.caja_elegida,
    'premio',              r.premio,
    'codigo_confirmacion', r.codigo_confirmacion,
    'distribucion',        case when r.caja_elegida is not null
                             then to_jsonb(r.distribucion) end
  );
$$;

-- Despierta al panel admin por Realtime. El mensaje no lleva datos: solo
-- avisa que hay novedades, y el panel pide el detalle con su sesión de
-- administrador. Si Realtime no está disponible, el panel igual se entera
-- en su siguiente consulta periódica.
create or replace function public.fn_avisar_panel_admin(p_evento text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform realtime.send(
    jsonb_build_object('evento', p_evento),
    p_evento,
    'onix-panel-admin',
    false
  );
exception when others then
  null;
end;
$$;

-- =====================================================================
--  LANDING · públicas (anon), protegidas por el token de sesión
-- =====================================================================

-- Estado del premio del participante: tickets, meta y su reclamo si existe.
create or replace function public.sesion_estado_premio(p_token uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_persona public.participantes := public.fn_participante_de_sesion(p_token);
  v_reclamo public.reclamos_premio;
begin
  if v_persona.id is null then
    return public.fn_error_onix('noRegistrado',
      'Tu sesión expiró. Vuelve a ingresar.');
  end if;

  select * into v_reclamo
    from public.reclamos_premio
   where participante_id = v_persona.id
     and estado <> 'reiniciado';

  return jsonb_build_object(
    'tickets',        public.fn_tickets(v_persona.id),
    'meta',           public.fn_meta_tickets(),
    'ganador_prueba', v_persona.ganador_prueba,
    'reclamo',        case when v_reclamo.id is null then null
                           else public.fn_reclamo_json(v_reclamo) end
  );
end;
$$;

-- «Reclamar premio»: crea el reclamo y esconde los premios en las cajas.
create or replace function public.sesion_reclamar_premio(p_token uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_persona  public.participantes := public.fn_participante_de_sesion(p_token);
  v_reclamo  public.reclamos_premio;
  v_anterior text[];
  v_tickets  int;
  v_meta     int := public.fn_meta_tickets();
begin
  if v_persona.id is null then
    return public.fn_error_onix('noRegistrado',
      'Tu sesión expiró. Vuelve a ingresar.');
  end if;

  -- Serializa dos clics simultáneos del mismo participante.
  perform 1 from public.participantes where id = v_persona.id for update;

  -- Idempotente: si ya reclamó, se devuelve el mismo reclamo. No hay forma
  -- de pedir un orden nuevo de cajas.
  select * into v_reclamo
    from public.reclamos_premio
   where participante_id = v_persona.id
     and estado <> 'reiniciado';
  if v_reclamo.id is not null then
    return public.fn_reclamo_json(v_reclamo);
  end if;

  v_tickets := public.fn_tickets(v_persona.id);
  if v_tickets < v_meta and not v_persona.ganador_prueba then
    return public.fn_error_onix('premioNoDisponible',
      format('Te faltan %s tickets para reclamar tu premio.', v_meta - v_tickets));
  end if;

  -- Orden del último reclamo (de prueba) de esta misma cuenta, para que al
  -- volver a jugar los premios cambien de lugar.
  select distribucion into v_anterior
    from public.reclamos_premio
   where participante_id = v_persona.id
   order by creado_en desc
   limit 1;

  insert into public.reclamos_premio (
    participante_id, es_prueba, distribucion, tickets_al_reclamar
  ) values (
    v_persona.id, v_tickets < v_meta,
    public.fn_distribucion_aleatoria(v_anterior), v_tickets
  )
  returning * into v_reclamo;

  insert into public.eventos_auditoria (tipo, participante_id, detalle)
  values ('reclamo_premio', v_persona.id,
          jsonb_build_object('reclamo', v_reclamo.id,
                             'tickets', v_tickets,
                             'prueba', v_reclamo.es_prueba));

  return public.fn_reclamo_json(v_reclamo);
end;
$$;

-- Abre la caja elegida. Una sola vez: después devuelve siempre lo mismo.
create or replace function public.sesion_abrir_caja(
  p_token   uuid,
  p_reclamo uuid,
  p_caja    int
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_persona public.participantes := public.fn_participante_de_sesion(p_token);
  v_reclamo public.reclamos_premio;
begin
  if v_persona.id is null then
    return public.fn_error_onix('noRegistrado',
      'Tu sesión expiró. Vuelve a ingresar.');
  end if;

  if p_caja is null or p_caja not between 0 and 2 then
    return public.fn_error_onix('cajaInvalida', 'Esa caja no existe.');
  end if;

  -- `for update`: si llegan dos clics a la vez sobre cajas distintas, solo
  -- el primero abre; el segundo recibe la caja que ya quedó abierta.
  select * into v_reclamo
    from public.reclamos_premio
   where id = p_reclamo
     and participante_id = v_persona.id
     and estado <> 'reiniciado'
     for update;

  if v_reclamo.id is null then
    return public.fn_error_onix('premioNoDisponible',
      'No encontramos tu reclamo de premio. Recarga la página.');
  end if;

  if v_reclamo.caja_elegida is not null then
    return public.fn_reclamo_json(v_reclamo);
  end if;

  update public.reclamos_premio
     set caja_elegida        = p_caja,
         premio              = distribucion[p_caja + 1],
         codigo_confirmacion = public.fn_generar_codigo_confirmacion(),
         abierto_en          = now(),
         estado              = 'pendiente'
   where id = v_reclamo.id
  returning * into v_reclamo;

  insert into public.notificaciones_admin (
    tipo, reclamo_id, participante_id, titulo, detalle
  ) values (
    'premio_reclamado', v_reclamo.id, v_persona.id,
    case when v_reclamo.es_prueba
      then format('Prueba · %s abrió una caja', v_persona.nombre)
      else format('%s reclamó su premio', v_persona.nombre)
    end,
    format('%s · código %s',
           public.fn_nombre_premio(v_reclamo.premio),
           public.fn_codigo_confirmacion_visible(v_reclamo.codigo_confirmacion))
  );

  insert into public.eventos_auditoria (tipo, participante_id, detalle)
  values ('caja_abierta', v_persona.id,
          jsonb_build_object('reclamo', v_reclamo.id,
                             'caja', p_caja,
                             'premio', v_reclamo.premio,
                             'prueba', v_reclamo.es_prueba));

  perform public.fn_avisar_panel_admin('premio_reclamado');

  return public.fn_reclamo_json(v_reclamo);
end;
$$;

-- ---------------------------------------------------------------------
-- Permisos
-- ---------------------------------------------------------------------
revoke execute on function public.fn_tickets(uuid)                        from public, anon, authenticated;
revoke execute on function public.fn_entero_aleatorio(int)                from public, anon, authenticated;
revoke execute on function public.fn_distribucion_aleatoria(text[])       from public, anon, authenticated;
revoke execute on function public.fn_generar_codigo_confirmacion()        from public, anon, authenticated;
revoke execute on function public.fn_reclamo_json(public.reclamos_premio) from public, anon, authenticated;
revoke execute on function public.fn_avisar_panel_admin(text)             from public, anon, authenticated;

grant execute on function public.sesion_estado_premio(uuid)             to anon, authenticated;
grant execute on function public.sesion_reclamar_premio(uuid)           to anon, authenticated;
grant execute on function public.sesion_abrir_caja(uuid, uuid, int)     to anon, authenticated;

-- =====================================================================
--  ↓↓↓  CUARTA PARTE · PANEL ADMIN  ↓↓↓
-- =====================================================================

-- =====================================================================
--  Reto 50 Onix · Panel admin
--
--  El panel admin (carpeta `panel_admin_onix`, junto a esta landing) usa
--  el mismo proyecto Supabase y la misma clave pública. Lo que lo protege
--  es la sesión de administrador: cada función de este archivo exige un
--  token que solo entrega `admin_iniciar_sesion` con usuario y contraseña.
--
--  Crear o recuperar una cuenta de administrador (en el SQL Editor de
--  Supabase, nunca desde el navegador):
--
--    select public.admin_crear_cuenta('usuario', 'Nombre Visible', 'UnaClaveLarga123');
--
--  Requiere haber ejecutado antes las tres partes anteriores.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Administradores y sesiones
-- ---------------------------------------------------------------------
create table if not exists public.administradores (
  id              uuid primary key default gen_random_uuid(),
  usuario         text not null unique,
  nombre          text not null,
  hash_contrasena text not null,
  activo          boolean not null default true,
  creado_en       timestamptz not null default now(),

  constraint usuario_admin_valido check (usuario ~ '^[a-z0-9][a-z0-9_.]{2,29}$')
);

create table if not exists public.sesiones_admin (
  token            uuid primary key default gen_random_uuid(),
  administrador_id uuid not null references public.administradores (id) on delete cascade,
  creado_en        timestamptz not null default now(),
  expira_en        timestamptz not null default now() + interval '12 hours'
);

create index if not exists idx_sesiones_admin_administrador
  on public.sesiones_admin (administrador_id);

create table if not exists public.intentos_ingreso_admin (
  id        bigserial primary key,
  usuario   text not null,
  exito     boolean not null default false,
  creado_en timestamptz not null default now()
);

create index if not exists idx_intentos_admin_usuario
  on public.intentos_ingreso_admin (usuario, creado_en desc);

alter table public.administradores        enable row level security;
alter table public.sesiones_admin         enable row level security;
alter table public.intentos_ingreso_admin enable row level security;
revoke all on table public.administradores, public.sesiones_admin,
                    public.intentos_ingreso_admin
  from anon, authenticated;

-- ---------------------------------------------------------------------
-- Alta de administradores · SOLO desde el SQL Editor
-- Si el usuario ya existe, cambia su contraseña y lo reactiva.
-- ---------------------------------------------------------------------
create or replace function public.admin_crear_cuenta(
  p_usuario    text,
  p_nombre     text,
  p_contrasena text
)
returns text
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_usuario text := lower(trim(coalesce(p_usuario, '')));
begin
  if v_usuario !~ '^[a-z0-9][a-z0-9_.]{2,29}$' then
    raise exception 'Usuario no válido: de 3 a 30 caracteres, minúsculas, números, punto o guion bajo';
  end if;
  if char_length(coalesce(p_contrasena, '')) < 10
     or p_contrasena !~ '[A-Za-z]' or p_contrasena !~ '[0-9]' then
    raise exception 'La contraseña del administrador debe tener al menos 10 caracteres, con letras y números';
  end if;

  insert into public.administradores (usuario, nombre, hash_contrasena)
  values (v_usuario, coalesce(nullif(trim(p_nombre), ''), v_usuario),
          crypt(p_contrasena, gen_salt('bf', 10)))
  on conflict (usuario) do update
     set nombre          = excluded.nombre,
         hash_contrasena = excluded.hash_contrasena,
         activo          = true;

  -- Cambiar la contraseña cierra las sesiones abiertas con la anterior.
  delete from public.sesiones_admin
   where administrador_id = (select id from public.administradores where usuario = v_usuario);

  return format('Administrador "%s" listo para ingresar al panel.', v_usuario);
end;
$$;

-- ---------------------------------------------------------------------
-- Sesión
-- ---------------------------------------------------------------------
create or replace function public.fn_admin_de_sesion(p_token uuid)
returns public.administradores
language sql
stable
security definer
set search_path = public
as $$
  select a.*
    from public.sesiones_admin s
    join public.administradores a on a.id = s.administrador_id
   where s.token = p_token
     and s.expira_en > now()
     and a.activo;
$$;

create or replace function public.fn_error_sesion_admin()
returns jsonb
language sql
immutable
set search_path = public
as $$
  select public.fn_error_onix('sesionAdminExpirada',
    'Tu sesión de administrador expiró. Vuelve a ingresar.');
$$;

create or replace function public.admin_iniciar_sesion(
  p_usuario    text,
  p_contrasena text
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_usuario  text := lower(trim(coalesce(p_usuario, '')));
  v_admin    public.administradores;
  v_fallos   int;
  v_correcta boolean;
  v_sesion   public.sesiones_admin;
begin
  if v_usuario = '' or coalesce(p_contrasena, '') = '' then
    return public.fn_error_onix('credencialesIncorrectas',
      'Escribe tu usuario y tu contraseña.');
  end if;

  select count(*) into v_fallos
    from public.intentos_ingreso_admin
   where usuario = v_usuario
     and exito = false
     and creado_en > now() - interval '15 minutes';

  if v_fallos >= 5 then
    return public.fn_error_onix('demasiadosIntentos',
      'Demasiados intentos fallidos. Espera 15 minutos antes de volver a intentar.');
  end if;

  select * into v_admin from public.administradores where usuario = v_usuario;

  -- Igual se calcula un bcrypt si el usuario no existe: el tiempo de
  -- respuesta no delata qué usuarios hay.
  v_correcta := crypt(
    p_contrasena,
    coalesce(v_admin.hash_contrasena, gen_salt('bf', 10))
  ) = v_admin.hash_contrasena;

  if v_admin.id is null or v_correcta is not true or not v_admin.activo then
    insert into public.intentos_ingreso_admin (usuario, exito)
    values (v_usuario, false);
    return public.fn_error_onix('credencialesIncorrectas',
      'Usuario o contraseña incorrectos.');
  end if;

  insert into public.intentos_ingreso_admin (usuario, exito)
  values (v_usuario, true);

  delete from public.sesiones_admin
   where administrador_id = v_admin.id and expira_en < now();

  insert into public.sesiones_admin (administrador_id)
  values (v_admin.id)
  returning * into v_sesion;

  return jsonb_build_object(
    'id',           v_admin.id,
    'usuario',      v_admin.usuario,
    'nombre',       v_admin.nombre,
    'token',        v_sesion.token,
    'expira_en',    v_sesion.expira_en,
    'canal_avisos', 'onix-panel-admin'
  );
end;
$$;

create or replace function public.admin_sesion(p_token uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin  public.administradores := public.fn_admin_de_sesion(p_token);
  v_expira timestamptz;
begin
  if v_admin.id is null then
    return null;
  end if;
  select expira_en into v_expira from public.sesiones_admin where token = p_token;
  return jsonb_build_object(
    'id',           v_admin.id,
    'usuario',      v_admin.usuario,
    'nombre',       v_admin.nombre,
    'token',        p_token,
    'expira_en',    v_expira,
    'canal_avisos', 'onix-panel-admin'
  );
end;
$$;

create or replace function public.admin_cerrar_sesion(p_token uuid)
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.sesiones_admin where token = p_token;
$$;

-- ---------------------------------------------------------------------
-- Formatos de salida
-- ---------------------------------------------------------------------

-- Reclamo completo, tal como lo ve el administrador.
create or replace function public.fn_admin_reclamo_json(r public.reclamos_premio)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'id',                  r.id,
    'estado',              r.estado,
    'es_prueba',           r.es_prueba,
    'distribucion',        to_jsonb(r.distribucion),
    'caja_elegida',        r.caja_elegida,
    'premio',              r.premio,
    'codigo_confirmacion', r.codigo_confirmacion,
    'tickets_al_reclamar', r.tickets_al_reclamar,
    'creado_en',           r.creado_en,
    'abierto_en',          r.abierto_en,
    'revisado_en',         r.revisado_en,
    'revisado_por',        r.revisado_por,
    'nota_admin',          r.nota_admin,
    'participante', jsonb_build_object(
      'id',             p.id,
      'nombre',         p.nombre,
      'nombre_usuario', p.nombre_usuario,
      'telefono_e164',  p.telefono_e164,
      'tickets',        public.fn_tickets(p.id),
      'ganador_prueba', p.ganador_prueba
    )
  )
  from public.participantes p
  where p.id = r.participante_id;
$$;

-- Ficha completa de un participante: sus datos, su dispositivo, cada
-- código que compartió y, para los canjeados, el número y el dispositivo
-- anclado del invitado, con las coincidencias sospechosas ya contadas.
create or replace function public.fn_admin_ficha_participante(p_participante uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_persona public.participantes;
begin
  select * into v_persona from public.participantes where id = p_participante;
  if v_persona.id is null then
    return null;
  end if;

  return jsonb_build_object(
    'participante', jsonb_build_object(
      'id',                   v_persona.id,
      'nombre',               v_persona.nombre,
      'nombre_usuario',       v_persona.nombre_usuario,
      'telefono_e164',        v_persona.telefono_e164,
      'estado',               v_persona.estado,
      'ganador_prueba',       v_persona.ganador_prueba,
      'creado_en',            v_persona.creado_en,
      'huella_dispositivo',   v_persona.huella_dispositivo,
      'firma_dispositivo',    v_persona.firma_dispositivo,
      'dispositivo',          v_persona.dispositivo,
      'ip_registro',          host(v_persona.ip_registro),
      'tickets',              public.fn_tickets(v_persona.id),
      'referidos_pendientes', (select count(*) from public.referidos
                                where invitador_id = v_persona.id
                                  and estado = 'pendiente'),
      'codigo_con_que_entro', v_persona.codigo_invitador
    ),
    'invitaciones', coalesce((
      select jsonb_agg(fila order by (fila->>'creado_en') desc)
        from (
          select jsonb_build_object(
                   'id',          i.id,
                   'codigo',      i.codigo,
                   'creado_en',   i.creado_en,
                   'expira_en',   i.expira_en,
                   'usada_en',    i.usada_en,
                   'estado',      case
                                    when i.usada_en is not null then 'usada'
                                    when i.expira_en < now() then 'expirada'
                                    else 'pendiente'
                                  end,
                   'invitado',    case when inv.id is null then null else
                                    jsonb_build_object(
                                      'id',             inv.id,
                                      'nombre',         inv.nombre,
                                      'nombre_usuario', inv.nombre_usuario,
                                      'telefono_e164',  inv.telefono_e164,
                                      'estado',         inv.estado,
                                      'creado_en',      inv.creado_en
                                    ) end,
                   'estado_referido', r.estado,
                   'huella',      i.huella_invitado,
                   'firma',       i.firma_invitado,
                   'dispositivo', i.dispositivo_invitado,
                   'ip',          host(i.ip_invitado),
                   -- Coincidencias entre los invitados de ESTA persona.
                   'misma_firma', case when i.firma_invitado is null then 0 else (
                                    select count(*) from public.invitaciones o
                                     where o.invitador_id = i.invitador_id
                                       and o.id <> i.id
                                       and o.firma_invitado = i.firma_invitado) end,
                   'misma_ip',    case when i.ip_invitado is null then 0 else (
                                    select count(*) from public.invitaciones o
                                     where o.invitador_id = i.invitador_id
                                       and o.id <> i.id
                                       and o.ip_invitado = i.ip_invitado) end,
                   -- ¿El invitado se registró con la misma firma de
                   -- navegador que quien lo invitó?
                   'firma_del_invitador', i.firma_invitado is not null
                                    and i.firma_invitado = v_persona.firma_dispositivo
                 ) as fila
            from public.invitaciones i
            left join public.participantes inv on inv.id = i.usada_por_id
            left join public.referidos r on r.invitado_id = inv.id
           where i.invitador_id = v_persona.id
        ) s
    ), '[]'::jsonb),
    'reclamos', coalesce((
      select jsonb_agg(public.fn_admin_reclamo_json(rp) order by rp.creado_en desc)
        from public.reclamos_premio rp
       where rp.participante_id = v_persona.id
    ), '[]'::jsonb)
  );
end;
$$;

-- =====================================================================
--  FUNCIONES DEL PANEL · exigen token de administrador
-- =====================================================================

create or replace function public.admin_resumen(p_token uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin public.administradores := public.fn_admin_de_sesion(p_token);
begin
  if v_admin.id is null then
    return public.fn_error_sesion_admin();
  end if;

  return jsonb_build_object(
    'participantes',         (select count(*) from public.participantes),
    'invitados_verificados', (select count(*) from public.referidos where estado = 'valido'),
    'metas_alcanzadas',      (select count(*) from (
                                select invitador_id from public.referidos
                                 where estado = 'valido'
                                 group by invitador_id
                                having count(*) >= public.fn_meta_tickets()) m),
    'reclamos_por_revisar',  (select count(*) from public.reclamos_premio
                               where estado = 'pendiente' and not es_prueba),
    'reclamos_verificados',  (select count(*) from public.reclamos_premio
                               where estado = 'verificado' and not es_prueba),
    'reclamos_entregados',   (select count(*) from public.reclamos_premio
                               where estado = 'entregado' and not es_prueba),
    'notificaciones_sin_leer', (select count(*) from public.notificaciones_admin
                                 where leida_en is null),
    'ultima_notificacion',   (select max(id) from public.notificaciones_admin)
  );
end;
$$;

create or replace function public.admin_notificaciones(
  p_token  uuid,
  p_limite int default 40
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin public.administradores := public.fn_admin_de_sesion(p_token);
begin
  if v_admin.id is null then
    return public.fn_error_sesion_admin();
  end if;

  return jsonb_build_object('notificaciones', coalesce((
    select jsonb_agg(fila order by (fila->>'id')::bigint desc)
      from (
        select jsonb_build_object(
                 'id',              n.id,
                 'tipo',            n.tipo,
                 'reclamo_id',      n.reclamo_id,
                 'participante_id', n.participante_id,
                 'titulo',          n.titulo,
                 'detalle',         n.detalle,
                 'creado_en',       n.creado_en,
                 'leida',           n.leida_en is not null
               ) as fila
          from public.notificaciones_admin n
         order by n.id desc
         limit least(greatest(coalesce(p_limite, 40), 1), 200)
      ) s
  ), '[]'::jsonb));
end;
$$;

create or replace function public.admin_marcar_notificaciones(
  p_token uuid,
  p_ids   bigint[] default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin public.administradores := public.fn_admin_de_sesion(p_token);
  v_total int;
begin
  if v_admin.id is null then
    return public.fn_error_sesion_admin();
  end if;

  update public.notificaciones_admin
     set leida_en = now()
   where leida_en is null
     and (p_ids is null or id = any (p_ids));
  get diagnostics v_total = row_count;

  return jsonb_build_object('marcadas', v_total);
end;
$$;

create or replace function public.admin_reclamos(
  p_token  uuid,
  p_estado text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin public.administradores := public.fn_admin_de_sesion(p_token);
begin
  if v_admin.id is null then
    return public.fn_error_sesion_admin();
  end if;

  return jsonb_build_object('reclamos', coalesce((
    select jsonb_agg(public.fn_admin_reclamo_json(r)
                     order by coalesce(r.abierto_en, r.creado_en) desc)
      from (
        select *
          from public.reclamos_premio
         where (p_estado is null and estado <> 'reiniciado')
            or estado = p_estado
         order by coalesce(abierto_en, creado_en) desc
         limit 300
      ) r
  ), '[]'::jsonb));
end;
$$;

create or replace function public.admin_detalle_reclamo(
  p_token   uuid,
  p_reclamo uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin   public.administradores := public.fn_admin_de_sesion(p_token);
  v_reclamo public.reclamos_premio;
begin
  if v_admin.id is null then
    return public.fn_error_sesion_admin();
  end if;

  select * into v_reclamo from public.reclamos_premio where id = p_reclamo;
  if v_reclamo.id is null then
    return public.fn_error_onix('reclamoInexistente', 'Ese reclamo no existe.');
  end if;

  return jsonb_build_object(
    'reclamo', public.fn_admin_reclamo_json(v_reclamo),
    'ficha',   public.fn_admin_ficha_participante(v_reclamo.participante_id)
  );
end;
$$;

-- Verificación con el código de confirmación impreso en el ticket.
create or replace function public.admin_buscar_codigo(
  p_token  uuid,
  p_codigo text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin   public.administradores := public.fn_admin_de_sesion(p_token);
  v_codigo  text := regexp_replace(upper(coalesce(p_codigo, '')), '[^A-Z0-9]', '', 'g');
  v_reclamo public.reclamos_premio;
begin
  if v_admin.id is null then
    return public.fn_error_sesion_admin();
  end if;

  if char_length(v_codigo) = 13 and left(v_codigo, 3) = 'PRM' then
    v_codigo := substr(v_codigo, 4);
  end if;

  if char_length(v_codigo) <> 10 then
    return public.fn_error_onix('codigoConfirmacionInvalido',
      'El código de confirmación tiene el formato PRM-XXXXX-XXXXX.');
  end if;

  select * into v_reclamo
    from public.reclamos_premio
   where codigo_confirmacion = v_codigo;

  if v_reclamo.id is null then
    return public.fn_error_onix('codigoConfirmacionInexistente',
      'Ese código no corresponde a ningún premio. Puede estar mal escrito o ser falso.');
  end if;

  return jsonb_build_object(
    'reclamo', public.fn_admin_reclamo_json(v_reclamo),
    'ficha',   public.fn_admin_ficha_participante(v_reclamo.participante_id)
  );
end;
$$;

create or replace function public.admin_cambiar_estado_reclamo(
  p_token   uuid,
  p_reclamo uuid,
  p_estado  text,
  p_nota    text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin   public.administradores := public.fn_admin_de_sesion(p_token);
  v_reclamo public.reclamos_premio;
  v_permitido boolean;
begin
  if v_admin.id is null then
    return public.fn_error_sesion_admin();
  end if;

  select * into v_reclamo
    from public.reclamos_premio
   where id = p_reclamo
     for update;
  if v_reclamo.id is null then
    return public.fn_error_onix('reclamoInexistente', 'Ese reclamo no existe.');
  end if;

  v_permitido := case v_reclamo.estado
    when 'pendiente'  then p_estado in ('verificado', 'rechazado')
    when 'verificado' then p_estado in ('entregado', 'rechazado', 'pendiente')
    when 'rechazado'  then p_estado in ('pendiente')
    else false
  end;

  if not v_permitido then
    return public.fn_error_onix('transicionInvalida',
      format('Un reclamo en estado «%s» no puede pasar a «%s».', v_reclamo.estado, p_estado));
  end if;

  update public.reclamos_premio
     set estado       = p_estado,
         revisado_en  = now(),
         revisado_por = v_admin.usuario,
         nota_admin   = coalesce(nullif(trim(p_nota), ''), nota_admin)
   where id = v_reclamo.id
  returning * into v_reclamo;

  update public.notificaciones_admin
     set leida_en = now()
   where reclamo_id = v_reclamo.id and leida_en is null;

  insert into public.eventos_auditoria (tipo, participante_id, detalle)
  values ('admin_estado_reclamo', v_reclamo.participante_id,
          jsonb_build_object('reclamo', v_reclamo.id,
                             'estado', p_estado,
                             'admin', v_admin.usuario,
                             'nota', p_nota));

  return jsonb_build_object('reclamo', public.fn_admin_reclamo_json(v_reclamo));
end;
$$;

create or replace function public.admin_participantes(
  p_token    uuid,
  p_busqueda text default null,
  p_limite   int default 60
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin    public.administradores := public.fn_admin_de_sesion(p_token);
  v_texto    text := nullif(lower(trim(coalesce(p_busqueda, ''))), '');
  v_digitos  text := nullif(regexp_replace(coalesce(p_busqueda, ''), '\D', '', 'g'), '');
begin
  if v_admin.id is null then
    return public.fn_error_sesion_admin();
  end if;

  return jsonb_build_object('participantes', coalesce((
    select jsonb_agg(fila order by tickets desc, creado_en desc)
      from (
        select t.tickets, p.creado_en, jsonb_build_object(
                 'id',             p.id,
                 'nombre',         p.nombre,
                 'nombre_usuario', p.nombre_usuario,
                 'telefono_e164',  p.telefono_e164,
                 'estado',         p.estado,
                 'ganador_prueba', p.ganador_prueba,
                 'creado_en',      p.creado_en,
                 'tickets',        t.tickets,
                 'estado_reclamo', rp.estado,
                 'reclamo_id',     rp.id,
                 'reclamo_prueba', rp.es_prueba
               ) as fila
          from public.participantes p
          cross join lateral (select public.fn_tickets(p.id) as tickets) t
          left join public.reclamos_premio rp
                 on rp.participante_id = p.id and rp.estado <> 'reiniciado'
         where v_texto is null
            or lower(p.nombre) like '%' || v_texto || '%'
            or p.nombre_usuario like '%' || ltrim(v_texto, '@') || '%'
            or (v_digitos is not null and char_length(v_digitos) >= 4
                and p.telefono_e164 like '%' || v_digitos || '%')
         order by t.tickets desc, p.creado_en desc
         limit least(greatest(coalesce(p_limite, 60), 1), 300)
      ) s
  ), '[]'::jsonb));
end;
$$;

create or replace function public.admin_detalle_participante(
  p_token        uuid,
  p_participante uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin public.administradores := public.fn_admin_de_sesion(p_token);
  v_ficha jsonb;
begin
  if v_admin.id is null then
    return public.fn_error_sesion_admin();
  end if;

  v_ficha := public.fn_admin_ficha_participante(p_participante);
  if v_ficha is null then
    return public.fn_error_onix('participanteInexistente', 'Ese participante no existe.');
  end if;
  return jsonb_build_object('ficha', v_ficha);
end;
$$;

-- Habilita (o quita) el modo «ganador de prueba» de una cuenta: puede
-- reclamar el premio y abrir una caja sin tener 50 tickets. Sus reclamos
-- quedan marcados como prueba en todas partes.
create or replace function public.admin_habilitar_ganador_prueba(
  p_token        uuid,
  p_participante uuid,
  p_habilitar    boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin public.administradores := public.fn_admin_de_sesion(p_token);
  v_total int;
begin
  if v_admin.id is null then
    return public.fn_error_sesion_admin();
  end if;

  update public.participantes
     set ganador_prueba = coalesce(p_habilitar, false)
   where id = p_participante;
  get diagnostics v_total = row_count;

  if v_total = 0 then
    return public.fn_error_onix('participanteInexistente', 'Ese participante no existe.');
  end if;

  insert into public.eventos_auditoria (tipo, participante_id, detalle)
  values ('admin_ganador_prueba', p_participante,
          jsonb_build_object('habilitado', coalesce(p_habilitar, false),
                             'admin', v_admin.usuario));

  return jsonb_build_object('ficha', public.fn_admin_ficha_participante(p_participante));
end;
$$;

-- Descarta un reclamo de PRUEBA para que esa cuenta pueda volver a jugar.
-- Los reclamos reales no se pueden reiniciar (el trigger lo impide).
create or replace function public.admin_reiniciar_reclamo_prueba(
  p_token   uuid,
  p_reclamo uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin   public.administradores := public.fn_admin_de_sesion(p_token);
  v_reclamo public.reclamos_premio;
begin
  if v_admin.id is null then
    return public.fn_error_sesion_admin();
  end if;

  select * into v_reclamo
    from public.reclamos_premio
   where id = p_reclamo
     for update;

  if v_reclamo.id is null or v_reclamo.estado = 'reiniciado' then
    return public.fn_error_onix('reclamoInexistente', 'Ese reclamo ya no está vigente.');
  end if;

  if not v_reclamo.es_prueba then
    return public.fn_error_onix('reclamoReal',
      'Este reclamo es real: no se puede reiniciar. Si hubo trampa, recházalo.');
  end if;

  update public.reclamos_premio
     set estado       = 'reiniciado',
         revisado_en  = now(),
         revisado_por = v_admin.usuario
   where id = v_reclamo.id;

  update public.notificaciones_admin
     set leida_en = now()
   where reclamo_id = v_reclamo.id and leida_en is null;

  insert into public.eventos_auditoria (tipo, participante_id, detalle)
  values ('admin_reinicio_prueba', v_reclamo.participante_id,
          jsonb_build_object('reclamo', v_reclamo.id, 'admin', v_admin.usuario));

  return jsonb_build_object('ficha', public.fn_admin_ficha_participante(v_reclamo.participante_id));
end;
$$;

-- ---------------------------------------------------------------------
-- Permisos
-- ---------------------------------------------------------------------
revoke execute on function public.admin_crear_cuenta(text, text, text)            from public, anon, authenticated;
revoke execute on function public.fn_admin_de_sesion(uuid)                        from public, anon, authenticated;
revoke execute on function public.fn_admin_reclamo_json(public.reclamos_premio)   from public, anon, authenticated;
revoke execute on function public.fn_admin_ficha_participante(uuid)               from public, anon, authenticated;

grant execute on function public.admin_crear_cuenta(text, text, text) to service_role;

-- El panel llama a estas con la clave pública; sin token válido no hacen nada.
grant execute on function public.admin_iniciar_sesion(text, text)                        to anon, authenticated;
grant execute on function public.admin_sesion(uuid)                                      to anon, authenticated;
grant execute on function public.admin_cerrar_sesion(uuid)                               to anon, authenticated;
grant execute on function public.admin_resumen(uuid)                                     to anon, authenticated;
grant execute on function public.admin_notificaciones(uuid, int)                         to anon, authenticated;
grant execute on function public.admin_marcar_notificaciones(uuid, bigint[])             to anon, authenticated;
grant execute on function public.admin_reclamos(uuid, text)                              to anon, authenticated;
grant execute on function public.admin_detalle_reclamo(uuid, uuid)                       to anon, authenticated;
grant execute on function public.admin_buscar_codigo(uuid, text)                         to anon, authenticated;
grant execute on function public.admin_cambiar_estado_reclamo(uuid, uuid, text, text)    to anon, authenticated;
grant execute on function public.admin_participantes(uuid, text, int)                    to anon, authenticated;
grant execute on function public.admin_detalle_participante(uuid, uuid)                  to anon, authenticated;
grant execute on function public.admin_habilitar_ganador_prueba(uuid, uuid, boolean)     to anon, authenticated;
grant execute on function public.admin_reiniciar_reclamo_prueba(uuid, uuid)              to anon, authenticated;
