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
