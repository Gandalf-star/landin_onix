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
--     ese mismo celular con su contraseña, sin SMS.
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
set search_path = public
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
set search_path = public
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
set search_path = public
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
