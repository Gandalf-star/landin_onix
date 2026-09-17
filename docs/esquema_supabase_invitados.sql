-- =====================================================================
--  Reto 50 Onix · Links de invitación y canje sin cuenta
--
--  Cómo funciona
--  -------------
--  1. Quien invita (tiene cuenta) pulsa «Compartir link por WhatsApp». La
--     landing pide su link con `sesion_mi_enlace` y abre WhatsApp, donde
--     puede elegir a muchos contactos a la vez. WhatsApp manda el MISMO
--     mensaje a todos, así que el mensaje no lleva un código: lleva el link.
--  2. Cada persona que abre el link en su celular recibe al instante SU
--     PROPIO código (`invitado_obtener_codigo`), distinto para cada
--     dispositivo y atado a ese dispositivo.
--  3. Esa persona escribe su celular y valida (`invitado_validar_codigo`).
--     No crea cuenta ni recibe SMS: el código queda anclado a su teléfono y
--     a su dispositivo, y quien invitó suma el ticket.
--
--  El SMS de Twilio queda sólo para crear cuentas (quien invita).
--
--  Reglas (se aplican en la base, en una sola transacción)
--  -------------------------------------------------------
--  - El código existe, no se usó, no venció y su dueño está activo.
--  - Un código entregado por un link sólo se valida desde el dispositivo
--    que abrió el link.
--  - El teléfono es un móvil válido y creíble, no es el de quien invita y
--    nunca aceptó otra invitación (índice único).
--  - El dispositivo nunca aceptó otra invitación (índice único) y no es uno
--    desde el que quien invita se registró o inició sesión.
--  - Quien borra los datos del navegador o usa incógnito obtiene otra
--    huella, pero su firma y su conexión se repiten: el link le devuelve el
--    mismo código y no puede validar dos invitaciones de la misma persona.
--  - Sin cadenas circulares, freno a quien prueba códigos al azar y topes
--    por link y por conexión.
--
--  Requiere haber ejecutado antes docs/esquema_supabase.sql y
--  docs/esquema_supabase_cuentas.sql
-- =====================================================================

-- Una version anterior de este archivo validaba el canje con SMS.
drop function if exists public.invitado_preparar_canje(text, text, text, text, jsonb);
drop function if exists public.invitado_anular_envio(uuid);
drop function if exists public.invitado_preparar_reenvio(uuid);
drop function if exists public.invitado_canje_para_verificar(uuid);
drop function if exists public.invitado_registrar_fallo(uuid);
drop function if exists public.invitado_completar_canje(uuid);
drop function if exists public.fn_revisar_canje(text, text, text);
drop function if exists public.sesion_generar_invitaciones(uuid, jsonb, int);
drop table if exists public.canjes_pendientes cascade;

-- ---------------------------------------------------------------------
-- Links de invitación
-- ---------------------------------------------------------------------
create table if not exists public.enlaces_invitacion (
  id            uuid primary key default gen_random_uuid(),
  invitador_id  uuid not null references public.participantes (id) on delete cascade,
  -- 10 caracteres del mismo alfabeto que los códigos.
  token         text not null unique,
  creado_en     timestamptz not null default now(),
  expira_en     timestamptz not null default now() + interval '7 days',
  -- Cuántos códigos puede entregar este link antes de pedir uno nuevo.
  max_codigos   int not null default 50,

  constraint formato_token_enlace check (token ~ '^[2-9A-HJKMNP-Z]{10}$'),
  constraint max_codigos_razonable check (max_codigos between 1 and 200)
);

create index if not exists idx_enlaces_invitador
  on public.enlaces_invitacion (invitador_id, creado_en desc);

-- Códigos entregados por un link: a qué link pertenecen y a qué
-- dispositivo se entregaron.
alter table public.invitaciones
  add column if not exists enlace_id uuid
  references public.enlaces_invitacion (id) on delete set null;
alter table public.invitaciones
  add column if not exists huella_asignada text;
alter table public.invitaciones
  add column if not exists firma_asignada text;
alter table public.invitaciones
  add column if not exists ip_asignada inet;
alter table public.invitaciones
  add column if not exists asignada_en timestamptz;

create index if not exists idx_invitaciones_enlace
  on public.invitaciones (enlace_id, huella_asignada)
  where enlace_id is not null;
create index if not exists idx_invitaciones_firma_ip_asignada
  on public.invitaciones (firma_asignada, ip_asignada)
  where firma_asignada is not null;

-- Un mismo dispositivo recibe un único código por link.
create unique index if not exists idx_invitaciones_enlace_huella
  on public.invitaciones (enlace_id, huella_asignada)
  where enlace_id is not null and huella_asignada is not null;

-- Links inexistentes y códigos que no sirven, para frenar a quien prueba
-- al azar desde la landing.
create table if not exists public.intentos_canje (
  id         bigserial primary key,
  codigo     text,
  motivo     text not null,
  huella     text,
  ip         inet,
  creado_en  timestamptz not null default now()
);

create index if not exists idx_intentos_canje_huella
  on public.intentos_canje (huella, creado_en desc);
create index if not exists idx_intentos_canje_ip
  on public.intentos_canje (ip, creado_en desc);

alter table public.enlaces_invitacion enable row level security;
alter table public.intentos_canje     enable row level security;
revoke all on table public.enlaces_invitacion, public.intentos_canje
  from anon, authenticated;

-- ---------------------------------------------------------------------
-- Utilidades
-- ---------------------------------------------------------------------

-- Frenos al envío de SMS del registro ("SMS pumping").
create or replace function public.fn_limites_sms(
  p_telefono text,
  p_ip       inet,
  p_huella   text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_ultimo timestamptz;
  v_conteo int;
  c_max_sms_por_telefono constant int := 5;   -- por hora
  c_max_sms_por_ip       constant int := 10;  -- por hora
  c_max_sms_por_huella   constant int := 6;   -- por hora
begin
  select max(enviado_en), coalesce(sum(envios), 0)
    into v_ultimo, v_conteo
    from public.registros_pendientes
   where telefono_e164 = p_telefono
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

  if p_ip is not null then
    select count(*) into v_conteo
      from public.registros_pendientes
     where ip = p_ip and estado <> 'cancelado'
       and creado_en > now() - interval '1 hour';
    if v_conteo >= c_max_sms_por_ip then
      return public.fn_error_onix('demasiadosIntentos',
        'Hay demasiadas solicitudes desde tu conexión. Intenta de nuevo en una hora.');
    end if;
  end if;

  if p_huella is not null then
    select count(*) into v_conteo
      from public.registros_pendientes
     where huella = p_huella and estado <> 'cancelado'
       and creado_en > now() - interval '1 hour';
    if v_conteo >= c_max_sms_por_huella then
      return public.fn_error_onix('demasiadosIntentos',
        'Hay demasiadas solicitudes desde este dispositivo. Intenta de nuevo en una hora.');
    end if;
  end if;

  return null;
end;
$$;

-- IP de quien llama desde el navegador. PostgREST deja las cabeceras de la
-- petición en `request.headers`; fuera de una petición HTTP devuelve null.
create or replace function public.fn_ip_peticion()
returns inet
language plpgsql
stable
set search_path = public
as $$
declare
  v_texto text;
begin
  v_texto := trim(split_part(
    coalesce(current_setting('request.headers', true), '{}')::json
      ->> 'x-forwarded-for', ',', 1));
  return nullif(v_texto, '')::inet;
exception when others then
  return null;
end;
$$;

-- Números obviamente inventados (mismas reglas que `pareceSospechoso` en
-- Dart). Sin SMS, esta es la primera barrera contra números al azar.
create or replace function public.fn_telefono_sospechoso(p_telefono text)
returns boolean
language sql
immutable
set search_path = public
as $$
  select p_telefono ~ '^\+569([0-9])\1{7}$'
      or p_telefono ~ '^\+58(412|414|416|424|426)([0-9])\2{6}$'
      or p_telefono in ('+56912345678', '+56987654321',
                        '+584121234567', '+584141234567');
$$;

-- ¿Este teléfono ya aceptó una invitación? Cuenta los canjes sin cuenta y
-- los antiguos, hechos al registrarse con un código.
create or replace function public.fn_telefono_ya_invitado(p_telefono text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from public.invitaciones
                  where telefono_invitado = p_telefono)
      or exists (select 1 from public.referidos
                  where telefono_invitado = p_telefono)
      or exists (select 1 from public.participantes
                  where telefono_e164 = p_telefono
                    and codigo_invitador is not null);
$$;

-- ¿Es un dispositivo desde el que esta persona se registró o entró?
create or replace function public.fn_dispositivo_de(
  p_participante uuid,
  p_huella       text
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from public.participantes
                  where id = p_participante and huella_dispositivo = p_huella)
      or exists (select 1 from public.sesiones
                  where participante_id = p_participante and huella = p_huella)
      or exists (select 1 from public.intentos_ingreso i
                   join public.participantes p on p.telefono_e164 = i.telefono_e164
                  where p.id = p_participante and i.exito and i.huella = p_huella);
$$;

-- ¿Validar este código crearía un ciclo? Sube por la cadena de quien
-- invita (quién lo invitó a él, y así) buscando el teléfono que canjea.
create or replace function public.fn_canje_circular(
  p_invitador uuid,
  p_telefono  text
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_actual   uuid := p_invitador;
  v_telefono text;
  v_padre    uuid;
  v_saltos   int := 0;
begin
  while v_actual is not null and v_saltos < 50 loop
    select telefono_e164 into v_telefono
      from public.participantes where id = v_actual;
    if v_telefono is null then
      return false;
    end if;

    -- Quién invitó a esta persona: por su cuenta (canje antiguo) o por su
    -- teléfono (canje sin cuenta).
    select r.invitador_id into v_padre
      from public.referidos r
     where r.invitado_id = v_actual
        or r.telefono_invitado = v_telefono
     limit 1;

    if v_padre is null then
      return false;
    end if;

    select telefono_e164 into v_telefono
      from public.participantes where id = v_padre;
    if v_telefono = p_telefono then
      return true;
    end if;

    v_actual := v_padre;
    v_saltos := v_saltos + 1;
  end loop;
  return false;
end;
$$;

-- Normaliza lo que escribe la persona: `onx-7k4q-2p9m` -> `7K4Q2P9M`.
create or replace function public.fn_normalizar_codigo(p_codigo text)
returns text
language sql
immutable
set search_path = public
as $$
  select case
    when v like 'ONX%' and char_length(v) > 8 then substr(v, 4)
    else v
  end
  from (select regexp_replace(upper(coalesce(p_codigo, '')), '[^A-Z0-9]', '', 'g') as v) s;
$$;

create or replace function public.fn_generar_token_enlace()
returns text
language plpgsql
set search_path = public, extensions
as $$
declare
  alfabeto  constant text := '23456789ABCDEFGHJKMNPQRSTUVWXYZ';
  bytes     bytea;
  candidato text;
begin
  loop
    bytes := gen_random_bytes(10);
    candidato := '';
    for i in 0..9 loop
      candidato := candidato || substr(alfabeto, 1 + get_byte(bytes, i) % 31, 1);
    end loop;
    exit when not exists (
      select 1 from public.enlaces_invitacion where token = candidato
    );
  end loop;
  return candidato;
end;
$$;

-- Freno a quien prueba links o códigos al azar.
create or replace function public.fn_frenar_adivinanzas(p_huella text, p_ip inet)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_fallos int;
  c_max_fallos_huella constant int := 8;    -- por hora
  c_max_fallos_ip     constant int := 20;
begin
  if p_huella is not null then
    select count(*) into v_fallos
      from public.intentos_canje
     where huella = p_huella and creado_en > now() - interval '1 hour';
    if v_fallos >= c_max_fallos_huella then
      return public.fn_error_onix('demasiadosIntentos',
        'Probaste demasiados códigos que no sirven. Intenta de nuevo en una hora.');
    end if;
  end if;

  if p_ip is not null then
    select count(*) into v_fallos
      from public.intentos_canje
     where ip = p_ip and creado_en > now() - interval '1 hour';
    if v_fallos >= c_max_fallos_ip then
      return public.fn_error_onix('demasiadosIntentos',
        'Hay demasiados códigos inválidos desde tu conexión. Intenta de nuevo en una hora.');
    end if;
  end if;
  return null;
end;
$$;

-- Todas las reglas del canje. Devuelve null si el código se puede validar
-- con este teléfono desde este dispositivo, o el error para el cliente.
create or replace function public.fn_revisar_canje(
  p_codigo   text,
  p_telefono text,
  p_huella   text,
  p_firma    text,
  p_ip       inet
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_error      jsonb;
  v_invitacion public.invitaciones;
  v_invitador  public.participantes;
begin
  -- Código vigente, sin autorreferido y anclaje del dispositivo (la misma
  -- regla que usa el registro).
  v_error := public.fn_revisar_invitacion(p_codigo, p_telefono, p_huella);
  if v_error is not null then
    return v_error;
  end if;

  select * into v_invitacion from public.invitaciones where codigo = p_codigo;
  select * into v_invitador from public.participantes where id = v_invitacion.invitador_id;

  -- Un código entregado por un link sólo se valida en el dispositivo que
  -- abrió el link.
  if v_invitacion.huella_asignada is not null
     and v_invitacion.huella_asignada <> p_huella then
    return public.fn_error_onix('dispositivoNoIdentificado',
      'Este código se entregó a otro dispositivo. Abre el link de invitación desde tu propio celular.');
  end if;

  -- Misma firma de navegador y misma conexión que un invitado ya validado
  -- de esta persona: es el mismo celular con los datos borrados.
  if p_firma is not null and p_ip is not null and exists (
       select 1 from public.invitaciones
        where invitador_id = v_invitacion.invitador_id
          and usada_en is not null
          and firma_invitado = p_firma
          and ip_invitado = p_ip) then
    return public.fn_error_onix('dispositivoYaAnclado',
      'Este dispositivo ya se usó para aceptar una invitación de esta persona.');
  end if;

  -- Misma firma y misma conexión con las que se registró quien invita.
  if p_firma is not null and p_ip is not null
     and v_invitador.firma_dispositivo = p_firma
     and v_invitador.ip_registro = p_ip then
    return public.fn_error_onix('dispositivoDelInvitador',
      'Este código no se puede usar desde el dispositivo de quien te invitó. Valídalo desde tu propio celular.');
  end if;

  -- Anclaje del teléfono: un número acepta una sola invitación.
  if public.fn_telefono_ya_invitado(p_telefono) then
    return public.fn_error_onix('yaTieneInvitador',
      'Este número ya validó una invitación. Cada persona puede ser invitada una sola vez.');
  end if;

  if public.fn_canje_circular(v_invitacion.invitador_id, p_telefono) then
    return public.fn_error_onix('referidoCircular',
      'No puedes validar el código de alguien a quien tú invitaste.');
  end if;

  return null;
end;
$$;

-- =====================================================================
--  QUIEN INVITA · con su token de sesión
-- =====================================================================

-- Link vigente de la persona. Si no tiene uno con cupo, se crea.
create or replace function public.sesion_mi_enlace(p_token uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_persona public.participantes := public.fn_participante_de_sesion(p_token);
  v_enlace  public.enlaces_invitacion;
  v_usados  int;
begin
  if v_persona.id is null then
    return public.fn_error_onix('noRegistrado',
      'Tu sesión expiró. Vuelve a ingresar.');
  end if;

  -- El vigente más nuevo que todavía tenga cupo (con un día de margen para
  -- que un link recién compartido no venza enseguida).
  select e.* into v_enlace
    from public.enlaces_invitacion e
   where e.invitador_id = v_persona.id
     and e.expira_en > now() + interval '1 day'
     and (select count(*) from public.invitaciones i where i.enlace_id = e.id)
         < e.max_codigos
   order by e.creado_en desc
   limit 1;

  if v_enlace.id is null then
    insert into public.enlaces_invitacion (invitador_id, token)
    values (v_persona.id, public.fn_generar_token_enlace())
    returning * into v_enlace;
  end if;

  select count(*) into v_usados
    from public.invitaciones where enlace_id = v_enlace.id;

  return jsonb_build_object(
    'token',               v_enlace.token,
    'expira_en',           v_enlace.expira_en,
    'codigos_entregados',  v_usados,
    'max_codigos',         v_enlace.max_codigos
  );
end;
$$;

-- =====================================================================
--  QUIEN FUE INVITADO · público (anon), sin cuenta ni SMS
-- =====================================================================

-- ---------------------------------------------------------------------
-- Abrir el link: este dispositivo recibe su propio código
-- ---------------------------------------------------------------------
create or replace function public.invitado_obtener_codigo(
  p_enlace      text,
  p_huella      text,
  p_dispositivo jsonb default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_token       text := regexp_replace(upper(coalesce(p_enlace, '')), '[^A-Z0-9]', '', 'g');
  v_huella      text := left(nullif(trim(coalesce(p_huella, '')), ''), 120);
  v_dispositivo jsonb := public.fn_dispositivo_limpio(p_dispositivo);
  v_firma       text := v_dispositivo->>'firma';
  v_ip          inet := public.fn_ip_peticion();
  v_error       jsonb;
  v_enlace      public.enlaces_invitacion;
  v_invitador   public.participantes;
  v_invitacion  public.invitaciones;
  v_conteo      int;
  c_max_por_ip  constant int := 30;   -- códigos entregados por conexión, por hora
begin
  if v_huella is null then
    return public.fn_error_onix('dispositivoNoIdentificado',
      'No pudimos identificar tu dispositivo. Permite que el sitio guarde datos en tu navegador (sin modo incógnito) y vuelve a abrir el link.');
  end if;

  v_error := public.fn_frenar_adivinanzas(v_huella, v_ip);
  if v_error is not null then
    return v_error;
  end if;

  select * into v_enlace from public.enlaces_invitacion where token = v_token;
  if v_enlace.id is null then
    insert into public.intentos_canje (codigo, motivo, huella, ip)
    values (left(v_token, 20), 'enlaceInexistente', v_huella, v_ip);
    return public.fn_error_onix('codigoInexistente',
      'Este link de invitación no existe. Revisa que lo hayas abierto completo.');
  end if;

  select * into v_invitador from public.participantes where id = v_enlace.invitador_id;
  if v_invitador.id is null or v_invitador.estado <> 'activo' then
    return public.fn_error_onix('codigoInexistente',
      'Este link de invitación ya no está disponible.');
  end if;

  -- Quien invita abriendo su propio link.
  if public.fn_dispositivo_de(v_invitador.id, v_huella) then
    return public.fn_error_onix('dispositivoDelInvitador',
      'Este es tu propio link de invitación: compártelo por WhatsApp para que cada contacto reciba su código.');
  end if;

  -- ¿Este dispositivo ya tiene su código de este link? Se le devuelve el
  -- mismo. Lo mismo si la firma y la conexión coinciden con un dispositivo
  -- que ya lo abrió (datos del navegador borrados o modo incógnito).
  select * into v_invitacion
    from public.invitaciones
   where enlace_id = v_enlace.id
     and (huella_asignada = v_huella
          or (v_firma is not null and v_ip is not null
              and firma_asignada = v_firma and ip_asignada = v_ip))
   order by (huella_asignada = v_huella) desc, asignada_en
   limit 1;

  if v_invitacion.id is null then
    if v_enlace.expira_en < now() then
      return public.fn_error_onix('codigoExpirado',
        'Este link de invitación venció. Pide uno nuevo a quien te invitó.');
    end if;

    select count(*) into v_conteo
      from public.invitaciones where enlace_id = v_enlace.id;
    if v_conteo >= v_enlace.max_codigos then
      return public.fn_error_onix('demasiadosIntentos',
        'Este link ya entregó todos sus códigos. Pide uno nuevo a quien te invitó.');
    end if;

    if v_ip is not null then
      select count(*) into v_conteo
        from public.invitaciones
       where ip_asignada = v_ip and asignada_en > now() - interval '1 hour';
      if v_conteo >= c_max_por_ip then
        return public.fn_error_onix('demasiadosIntentos',
          'Se pidieron demasiados códigos desde tu conexión. Intenta de nuevo en una hora.');
      end if;
    end if;

    insert into public.invitaciones (
      invitador_id, codigo, expira_en, enlace_id,
      huella_asignada, firma_asignada, ip_asignada, asignada_en
    ) values (
      v_enlace.invitador_id, public.fn_generar_codigo_invitacion(),
      now() + interval '7 days', v_enlace.id,
      v_huella, v_firma, v_ip, now()
    )
    returning * into v_invitacion;
  end if;

  return jsonb_build_object(
    'codigo',           v_invitacion.codigo,
    'expira_en',        v_invitacion.expira_en,
    'usado',            v_invitacion.usada_en is not null,
    -- Quien abre el link ya sabe quién se lo mandó.
    'nombre_invitador', split_part(trim(v_invitador.nombre), ' ', 1)
  );
end;
$$;

-- ---------------------------------------------------------------------
-- Validar: el código queda anclado al teléfono y al dispositivo
-- ---------------------------------------------------------------------
create or replace function public.invitado_validar_codigo(
  p_codigo      text,
  p_telefono    text,
  p_huella      text,
  p_dispositivo jsonb default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_codigo      text := public.fn_normalizar_codigo(p_codigo);
  v_telefono    text := trim(coalesce(p_telefono, ''));
  v_huella      text := left(nullif(trim(coalesce(p_huella, '')), ''), 120);
  v_dispositivo jsonb := public.fn_dispositivo_limpio(p_dispositivo);
  v_firma       text := v_dispositivo->>'firma';
  v_ip          inet := public.fn_ip_peticion();
  v_error       jsonb;
  v_invitacion  public.invitaciones;
  v_invitador   public.participantes;
  v_restriccion text;
begin
  v_error := public.fn_frenar_adivinanzas(v_huella, v_ip);
  if v_error is not null then
    return v_error;
  end if;

  if v_codigo !~ '^[2-9A-HJKMNP-Z]{8}$' then
    return public.fn_error_onix('codigoMalFormado',
      'Ese código de invitación no es válido. Revisa que esté completo.');
  end if;

  if v_telefono !~ '^\+569[0-9]{8}$' and
     v_telefono !~ '^\+58(412|414|416|424|426)[0-9]{7}$' then
    return public.fn_error_onix('telefonoInvalido',
      'Necesitamos un número móvil chileno o venezolano válido.');
  end if;

  if public.fn_telefono_sospechoso(v_telefono) then
    return public.fn_error_onix('numeroSospechoso',
      'Ese número no parece real. Usa tu número personal.');
  end if;

  -- Bloquea la invitación: dos personas no pueden canjearla a la vez.
  select * into v_invitacion
    from public.invitaciones
   where codigo = v_codigo
     for update;

  v_error := public.fn_revisar_canje(v_codigo, v_telefono, v_huella, v_firma, v_ip);
  if v_error is not null then
    if v_error->'error'->>'motivo' in
         ('codigoInexistente', 'codigoYaUsado', 'codigoExpirado') then
      insert into public.intentos_canje (codigo, motivo, huella, ip)
      values (v_codigo, v_error->'error'->>'motivo', v_huella, v_ip);
    end if;
    insert into public.eventos_auditoria (tipo, detalle, ip)
    values ('canje_rechazado',
            jsonb_build_object('codigo', v_codigo,
                               'motivo', v_error->'error'->>'motivo',
                               'huella', v_huella),
            v_ip);
    return v_error;
  end if;

  -- El cierre de la invitación y el alta del referido van juntos: si el
  -- teléfono o el dispositivo se anclaron en paralelo, un índice único
  -- salta y se deshacen las dos cosas.
  begin
    update public.invitaciones
       set usada_en             = now(),
           telefono_invitado    = v_telefono,
           huella_invitado      = v_huella,
           firma_invitado       = v_firma,
           dispositivo_invitado = v_dispositivo,
           ip_invitado          = v_ip
     where id = v_invitacion.id;

    insert into public.referidos (
      invitador_id, invitado_id, invitacion_id, telefono_invitado,
      estado, validado_en, madura_en
    ) values (
      v_invitacion.invitador_id, null, v_invitacion.id, v_telefono,
      'valido', now(), now() + interval '72 hours'
    );
  exception when unique_violation then
    get stacked diagnostics v_restriccion = constraint_name;
    if v_restriccion = 'idx_invitaciones_huella_invitado' then
      return public.fn_error_onix('dispositivoYaAnclado',
        'Este dispositivo ya se usó para aceptar una invitación. Cada invitado debe validar su código desde su propio celular.');
    end if;
    return public.fn_error_onix('yaTieneInvitador',
      'Este número ya validó una invitación. Cada persona puede ser invitada una sola vez.');
  end;

  insert into public.eventos_auditoria (tipo, participante_id, detalle, ip)
  values ('canje_invitacion', v_invitacion.invitador_id,
          jsonb_build_object('codigo', v_invitacion.codigo,
                             'invitacion', v_invitacion.id,
                             'por_enlace', v_invitacion.enlace_id is not null,
                             'verificacion', 'sin_sms',
                             'huella', v_huella),
          v_ip);

  select * into v_invitador
    from public.participantes where id = v_invitacion.invitador_id;

  return jsonb_build_object(
    'codigo',           v_invitacion.codigo,
    'telefono_e164',    v_telefono,
    'validado_en',      now(),
    'nombre_invitador', split_part(trim(v_invitador.nombre), ' ', 1)
  );
end;
$$;

-- ---------------------------------------------------------------------
-- Permisos
-- ---------------------------------------------------------------------
revoke execute on function public.fn_limites_sms(text, inet, text)               from public, anon, authenticated;
revoke execute on function public.fn_telefono_ya_invitado(text)                  from public, anon, authenticated;
revoke execute on function public.fn_dispositivo_de(uuid, text)                  from public, anon, authenticated;
revoke execute on function public.fn_canje_circular(uuid, text)                  from public, anon, authenticated;
revoke execute on function public.fn_generar_token_enlace()                      from public, anon, authenticated;
revoke execute on function public.fn_frenar_adivinanzas(text, inet)              from public, anon, authenticated;
revoke execute on function public.fn_revisar_canje(text, text, text, text, inet) from public, anon, authenticated;
revoke execute on function public.sesion_mi_enlace(uuid)                         from public;
revoke execute on function public.invitado_obtener_codigo(text, text, jsonb)     from public;
revoke execute on function public.invitado_validar_codigo(text, text, text, jsonb) from public;

-- La landing: quien invita con su token; quien fue invitado, sin cuenta.
grant execute on function public.sesion_mi_enlace(uuid)                          to anon, authenticated;
grant execute on function public.invitado_obtener_codigo(text, text, jsonb)      to anon, authenticated;
grant execute on function public.invitado_validar_codigo(text, text, text, jsonb) to anon, authenticated;
