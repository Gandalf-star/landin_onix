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
