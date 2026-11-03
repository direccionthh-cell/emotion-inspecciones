-- =====================================================================
-- EMOTION INSPECCIONES — TODO EN UNO
-- Ejecuta este archivo UNA sola vez en Supabase (proyecto emotion-inspecciones):
--   SQL Editor → + → pega TODO → Run
-- Incluye: tablas, seguridad, fotos, fechas mes/año, campañas,
--          las 26 unidades y sus 144 elementos.
-- Se puede repetir sin problema: no duplica ni borra nada.
-- =====================================================================

-- =====================================================================
-- EMOTION INSPECCIONES — Tablas en Supabase
-- Proyecto de Supabase PROPIO (independiente de Emotion Campus).
-- Pega TODO este texto en Supabase → SQL Editor → New query → Run.
-- Se puede ejecutar más de una vez sin dañar nada.
-- =====================================================================

-- 0) PERFILES de los usuarios administradores
create table if not exists public.perfiles (
    id         uuid primary key references auth.users(id) on delete cascade,
    email      text,
    nombre     text,
    rol        text not null default 'colaborador' check (rol in ('colaborador','admin')),
    creado_en  timestamptz not null default now()
);

create or replace function public.crear_perfil()
returns trigger language plpgsql security definer set search_path = public as $$
begin
    insert into public.perfiles (id, email, nombre)
    values (new.id, new.email, coalesce(new.raw_user_meta_data->>'nombre', split_part(new.email, '@', 1)))
    on conflict (id) do nothing;
    return new;
end $$;

drop trigger if exists al_crear_usuario on auth.users;
create trigger al_crear_usuario after insert on auth.users
    for each row execute function public.crear_perfil();

insert into public.perfiles (id, email, nombre)
select id, email, split_part(email, '@', 1) from auth.users
on conflict (id) do nothing;

alter table public.perfiles enable row level security;
drop policy if exists "ver perfil propio" on public.perfiles;
create policy "ver perfil propio" on public.perfiles for select to authenticated using (id = auth.uid());

-- 1) LUGARES: sede, áreas, unidades móviles, vehículos
create table if not exists public.insp_lugares (
    id         bigint generated always as identity primary key,
    nombre     text not null,
    tipo       text not null default 'Sede',   -- Sede, Unidad móvil, Vehículo
    activo     boolean not null default true,
    creado_en  timestamptz not null default now()
);

-- 2) ELEMENTOS: cada botiquín, extintor, kit, etc.
create table if not exists public.insp_elementos (
    id                bigint generated always as identity primary key,
    codigo            text not null,              -- ej. EXT-01
    tipo              text not null,              -- extintor, botiquin, camilla, antiderrame, fichas, senalizacion
    lugar_id          bigint references public.insp_lugares(id) on delete set null,
    ubicacion         text,                       -- detalle: "Pasillo planta, junto a la puerta"
    detalle           text,                       -- ej. "ABC 20 lb"
    fecha_vencimiento date,                       -- recarga del extintor / vencimiento
    activo            boolean not null default true,
    creado_en         timestamptz not null default now()
);

-- 3) INSPECCIONES: cada revisión hecha
create table if not exists public.insp_inspecciones (
    id             bigint generated always as identity primary key,
    elemento_id    bigint not null references public.insp_elementos(id) on delete cascade,
    inspector_id   uuid not null default auth.uid() references auth.users(id),
    inspector      text,
    fecha          timestamptz not null default now(),
    resultado      text not null check (resultado in ('conforme','con_novedades')),
    respuestas     jsonb not null default '[]',   -- [{pregunta, respuesta, nota}]
    observaciones  text
);

create index if not exists insp_insp_elemento_idx on public.insp_inspecciones (elemento_id, fecha desc);

-- 4) ¿El usuario actual es administrador?
create or replace function public.es_admin()
returns boolean language sql stable security definer set search_path = public as $$
    select exists (select 1 from public.perfiles where id = auth.uid() and rol = 'admin');
$$;

-- 5) SEGURIDAD
alter table public.insp_lugares      enable row level security;
alter table public.insp_elementos    enable row level security;
alter table public.insp_inspecciones enable row level security;

-- Todos los usuarios con sesión pueden VER lugares, elementos e inspecciones
drop policy if exists "ver lugares" on public.insp_lugares;
create policy "ver lugares" on public.insp_lugares for select to authenticated using (true);
drop policy if exists "ver elementos" on public.insp_elementos;
create policy "ver elementos" on public.insp_elementos for select to authenticated using (true);
drop policy if exists "ver inspecciones" on public.insp_inspecciones;
create policy "ver inspecciones" on public.insp_inspecciones for select to authenticated using (true);

-- Solo administradores crean, editan o borran lugares y elementos
drop policy if exists "admin lugares" on public.insp_lugares;
create policy "admin lugares" on public.insp_lugares for all to authenticated
    using (public.es_admin()) with check (public.es_admin());
drop policy if exists "admin elementos" on public.insp_elementos;
create policy "admin elementos" on public.insp_elementos for all to authenticated
    using (public.es_admin()) with check (public.es_admin());

-- Cualquier usuario con sesión registra inspecciones a su nombre; solo admin las borra
drop policy if exists "crear inspeccion" on public.insp_inspecciones;
create policy "crear inspeccion" on public.insp_inspecciones for insert to authenticated
    with check (inspector_id = auth.uid());
drop policy if exists "admin borra inspeccion" on public.insp_inspecciones;
create policy "admin borra inspeccion" on public.insp_inspecciones for delete to authenticated
    using (public.es_admin());

-- 6) Datos adicionales y fotos (versión 2)
alter table public.insp_elementos    add column if not exists datos    jsonb not null default '{}';
alter table public.insp_elementos    add column if not exists foto_url text;
alter table public.insp_inspecciones add column if not exists copasst  text;
alter table public.insp_inspecciones add column if not exists fotos    jsonb not null default '[]';

-- 7) Carpeta de fotos (Storage). Las fotos se pueden ver con el enlace;
--    solo usuarios con sesión pueden subirlas y solo administradores borrarlas.
insert into storage.buckets (id, name, public)
values ('inspecciones', 'inspecciones', true)
on conflict (id) do nothing;

drop policy if exists "insp subir fotos" on storage.objects;
create policy "insp subir fotos" on storage.objects for insert to authenticated
    with check (bucket_id = 'inspecciones');
drop policy if exists "insp ver fotos" on storage.objects;
create policy "insp ver fotos" on storage.objects for select
    using (bucket_id = 'inspecciones');
drop policy if exists "insp borrar fotos" on storage.objects;
create policy "insp borrar fotos" on storage.objects for delete to authenticated
    using (bucket_id = 'inspecciones' and public.es_admin());

-- 8) INSPECCIÓN SIN CONTRASEÑA (versión 3)
--    Cualquier persona con el enlace o el QR puede registrar una inspección
--    escribiendo su nombre. El historial completo sigue siendo solo para usuarios.
alter table public.insp_inspecciones alter column inspector_id drop not null;

drop policy if exists "publico ve lugares" on public.insp_lugares;
create policy "publico ve lugares" on public.insp_lugares for select to anon using (activo);
drop policy if exists "publico ve elementos" on public.insp_elementos;
create policy "publico ve elementos" on public.insp_elementos for select to anon using (activo);

drop policy if exists "publico crea inspeccion" on public.insp_inspecciones;
create policy "publico crea inspeccion" on public.insp_inspecciones for insert to anon
    with check (inspector_id is null and length(trim(coalesce(inspector, ''))) between 3 and 100);

-- Solo la fecha y el resultado de la última inspección de cada elemento (para el panel público)
create or replace function public.insp_ultimas()
returns table (elemento_id bigint, fecha timestamptz, resultado text)
language sql stable security definer set search_path = public as $$
    select distinct on (elemento_id) elemento_id, fecha, resultado
    from public.insp_inspecciones
    order by elemento_id, fecha desc;
$$;
grant execute on function public.insp_ultimas() to anon, authenticated;

drop policy if exists "publico sube fotos" on storage.objects;
create policy "publico sube fotos" on storage.objects for insert to anon
    with check (bucket_id = 'inspecciones' and (storage.foldername(name))[1] = 'inspecciones');

alter table public.insp_lugares add column if not exists placa text;

-- 10) FECHAS DE REVISIÓN EN CADA INSPECCIÓN (versión 4)
--     Lo que se registra en la inspección (recarga, mantenimiento, prueba
--     hidrostática) actualiza automáticamente la ficha del elemento.
alter table public.insp_inspecciones add column if not exists datos jsonb not null default '{}';

create or replace function public.insp_actualizar_fechas()
returns trigger language plpgsql security definer set search_path = public as $$
declare
    prox text := new.datos->>'proxima_recarga';
begin
    if new.datos is null or new.datos = '{}'::jsonb then return new; end if;
    update public.insp_elementos
       set datos = datos || (new.datos - 'proxima_recarga'),
           fecha_vencimiento = case when prox ~ '^\d{4}-\d{2}$'
                                    then (to_date(prox || '-01', 'YYYY-MM-DD') + interval '1 month - 1 day')::date
                                    else fecha_vencimiento end
     where id = new.elemento_id;
    return new;
end $$;

drop trigger if exists insp_al_inspeccionar on public.insp_inspecciones;
create trigger insp_al_inspeccionar after insert on public.insp_inspecciones
    for each row execute function public.insp_actualizar_fechas();

-- 11) CAMPAÑAS ITINERANTES (versión 5)
--     La unidad (placa) es fija; el nombre del lugar es la campaña actual.
--     Cada inspección guarda el nombre de la campaña que tenía ese día.
alter table public.insp_inspecciones add column if not exists campana text;

create or replace function public.insp_guardar_campana()
returns trigger language plpgsql security definer set search_path = public as $$
begin
    select l.nombre into new.campana
    from public.insp_elementos e join public.insp_lugares l on l.id = e.lugar_id
    where e.id = new.elemento_id;
    return new;
end $$;

drop trigger if exists insp_campana_al_inspeccionar on public.insp_inspecciones;
create trigger insp_campana_al_inspeccionar before insert on public.insp_inspecciones
    for each row execute function public.insp_guardar_campana();

-- Inspecciones anteriores: se les asigna la campaña actual
update public.insp_inspecciones i set campana = l.nombre
from public.insp_elementos e join public.insp_lugares l on l.id = e.lugar_id
where e.id = i.elemento_id and i.campana is null;

-- 9) Lugares iniciales (solo si la tabla está vacía)
insert into public.insp_lugares (nombre, tipo)
select * from (values ('Sede Cota - Oficinas','Sede'), ('Sede Cota - Planta','Sede'), ('Sede Cota - Bodega','Sede')) v(nombre, tipo)
where not exists (select 1 from public.insp_lugares);

-- =====================================================================
-- DESPUÉS de crear tu usuario en Authentication → Users, hazte
-- administrador cambiando el correo y ejecutando SOLO esta línea:
--
--   update public.perfiles set rol = 'admin' where email = 'tu-correo@emotion-a.com';
-- =====================================================================


-- =====================================================================
-- CARGA DE UNIDADES Y ELEMENTOS
-- =====================================================================
-- 1) Unidades móviles y vehículos (con placa)
alter table public.insp_lugares add column if not exists placa text;

insert into public.insp_lugares (nombre, tipo, placa)
select v.nombre, v.tipo, v.placa
from (values
    ('BANCO DE BOGOTA', 'Unidad móvil', 'RKR633'),
    ('BANCOLOMBIA', 'Unidad móvil', 'GEN090'),
    ('COLSUBSIDIO EMPLEO', 'Unidad móvil', 'IVX646'),
    ('COMFAMA BIBLIOTECA', 'Unidad móvil', 'BSZ008'),
    ('COMFAMA EMPLEO 1', 'Unidad móvil', 'RNS233'),
    ('COMFAMA EMPLEO 2', 'Camioneta', 'ETM550'),
    ('COMFAMA RECREACION', 'Unidad móvil', 'EQY671'),
    ('COMFAMA URBANA', 'Unidad móvil', 'HKL301'),
    ('COMFASUCRE BIBLIOTECA', 'Unidad móvil', 'LRN903'),
    ('COMFASUCRE EMPLEO', 'Unidad móvil', 'NHR577'),
    ('COMPENSAR', 'Unidad móvil', 'MCR904'),
    ('FUNDACION WWB', 'Unidad móvil', 'CVK475'),
    ('PORKCOLOMBIA 2', 'Unidad móvil', 'KTV547'),
    ('SECRETARIA DE LA MUJER RURAL', 'Unidad móvil', 'NWX277'),
    ('SECRETARIA DE LA MUJER URBANA', 'Unidad móvil', 'GES161'),
    ('SECRETARIA DE LA MUJER VAN', 'Microbús', 'NWV837'),
    ('SIEMENS', 'Unidad móvil', 'HKT389'),
    ('UT AULAS AMBIENTALES UM RURAL', 'Unidad móvil', 'LLP358'),
    ('UT AULAS AMBIENTALES UM URBANA', 'Unidad móvil', 'GES160'),
    ('UT CRL CAMIONETA', 'Microbús', 'LLP943'),
    ('UT CRL MOVIL SM', 'Unidad móvil', 'LKN455'),
    ('UT SALUD MOVIL CAMIONETA', 'Microbús', 'NWV735'),
    ('UT SALUD MOVIL SM', 'Unidad móvil', 'NOQ909'),
    ('FURGON COMPRAS', 'Furgón', 'JKV123'),
    ('RANGER', 'Camioneta', 'ETM918'),
    ('VAN', 'Van', 'JKV805')
) as v(nombre, tipo, placa)
where not exists (select 1 from public.insp_lugares l where l.placa = v.placa);


-- 2) Elementos de cada unidad
create unique index if not exists insp_elementos_codigo_key on public.insp_elementos (codigo);

insert into public.insp_elementos (codigo, tipo, lugar_id, ubicacion, datos)
select v.codigo, v.tipo, l.id, v.ubicacion, v.datos
from (values
    ('EXT-RKR633', 'extintor', 'RKR633', 'Cabina', '{"agente": "ABC (Polvo químico seco)", "capacidad": "10 lb"}'::jsonb),
    ('BOT-RKR633', 'botiquin', 'RKR633', 'Cabina', '{"tipo_botiquin": "Maletín", "clase": "Tipo B"}'::jsonb),
    ('EXT-GEN090', 'extintor', 'GEN090', 'Cabina', '{"agente": "ABC (Polvo químico seco)", "capacidad": "10 lb"}'::jsonb),
    ('BOT-GEN090', 'botiquin', 'GEN090', 'Cabina', '{"tipo_botiquin": "Maletín", "clase": "Tipo B"}'::jsonb),
    ('EXT-IVX646', 'extintor', 'IVX646', 'Cabina', '{"agente": "ABC (Polvo químico seco)", "capacidad": "10 lb"}'::jsonb),
    ('BOT-IVX646', 'botiquin', 'IVX646', 'Cabina', '{"tipo_botiquin": "Maletín", "clase": "Tipo B"}'::jsonb),
    ('EXT-BSZ008', 'extintor', 'BSZ008', 'Cabina', '{"agente": "ABC (Polvo químico seco)", "capacidad": "10 lb"}'::jsonb),
    ('BOT-BSZ008', 'botiquin', 'BSZ008', 'Cabina', '{"tipo_botiquin": "Maletín", "clase": "Tipo B"}'::jsonb),
    ('EXT-RNS233', 'extintor', 'RNS233', 'Cabina', '{"agente": "ABC (Polvo químico seco)", "capacidad": "10 lb"}'::jsonb),
    ('BOT-RNS233', 'botiquin', 'RNS233', 'Cabina', '{"tipo_botiquin": "Maletín", "clase": "Tipo B"}'::jsonb),
    ('EXT-ETM550', 'extintor', 'ETM550', 'Cabina', '{"agente": "ABC (Polvo químico seco)", "capacidad": "10 lb"}'::jsonb),
    ('BOT-ETM550', 'botiquin', 'ETM550', 'Cabina', '{"tipo_botiquin": "Maletín", "clase": "Tipo B"}'::jsonb),
    ('EXT-EQY671', 'extintor', 'EQY671', 'Cabina', '{"agente": "ABC (Polvo químico seco)", "capacidad": "10 lb"}'::jsonb),
    ('BOT-EQY671', 'botiquin', 'EQY671', 'Cabina', '{"tipo_botiquin": "Maletín", "clase": "Tipo B"}'::jsonb),
    ('EXT-HKL301', 'extintor', 'HKL301', 'Cabina', '{"agente": "ABC (Polvo químico seco)", "capacidad": "10 lb"}'::jsonb),
    ('BOT-HKL301', 'botiquin', 'HKL301', 'Cabina', '{"tipo_botiquin": "Maletín", "clase": "Tipo B"}'::jsonb),
    ('EXT-LRN903', 'extintor', 'LRN903', 'Cabina', '{"agente": "ABC (Polvo químico seco)", "capacidad": "10 lb"}'::jsonb),
    ('BOT-LRN903', 'botiquin', 'LRN903', 'Cabina', '{"tipo_botiquin": "Maletín", "clase": "Tipo B"}'::jsonb),
    ('EXT-NHR577', 'extintor', 'NHR577', 'Cabina', '{"agente": "ABC (Polvo químico seco)", "capacidad": "10 lb"}'::jsonb),
    ('BOT-NHR577', 'botiquin', 'NHR577', 'Cabina', '{"tipo_botiquin": "Maletín", "clase": "Tipo B"}'::jsonb),
    ('EXT-MCR904', 'extintor', 'MCR904', 'Cabina', '{"agente": "ABC (Polvo químico seco)", "capacidad": "10 lb"}'::jsonb),
    ('BOT-MCR904', 'botiquin', 'MCR904', 'Cabina', '{"tipo_botiquin": "Maletín", "clase": "Tipo B"}'::jsonb),
    ('EXT-CVK475', 'extintor', 'CVK475', 'Cabina', '{"agente": "ABC (Polvo químico seco)", "capacidad": "10 lb"}'::jsonb),
    ('BOT-CVK475', 'botiquin', 'CVK475', 'Cabina', '{"tipo_botiquin": "Maletín", "clase": "Tipo B"}'::jsonb),
    ('EXT-KTV547', 'extintor', 'KTV547', 'Cabina', '{"agente": "ABC (Polvo químico seco)", "capacidad": "10 lb"}'::jsonb),
    ('BOT-KTV547', 'botiquin', 'KTV547', 'Cabina', '{"tipo_botiquin": "Maletín", "clase": "Tipo B"}'::jsonb),
    ('EXT-NWX277', 'extintor', 'NWX277', 'Cabina', '{"agente": "ABC (Polvo químico seco)", "capacidad": "10 lb"}'::jsonb),
    ('BOT-NWX277', 'botiquin', 'NWX277', 'Cabina', '{"tipo_botiquin": "Maletín", "clase": "Tipo B"}'::jsonb),
    ('EXT-GES161', 'extintor', 'GES161', 'Cabina', '{"agente": "ABC (Polvo químico seco)", "capacidad": "10 lb"}'::jsonb),
    ('BOT-GES161', 'botiquin', 'GES161', 'Cabina', '{"tipo_botiquin": "Maletín", "clase": "Tipo B"}'::jsonb),
    ('EXT-NWV837', 'extintor', 'NWV837', 'Cabina', '{"agente": "ABC (Polvo químico seco)", "capacidad": "10 lb"}'::jsonb),
    ('BOT-NWV837', 'botiquin', 'NWV837', 'Cabina', '{"tipo_botiquin": "Maletín", "clase": "Tipo B"}'::jsonb),
    ('EXT-HKT389', 'extintor', 'HKT389', 'Cabina', '{"agente": "ABC (Polvo químico seco)", "capacidad": "10 lb"}'::jsonb),
    ('BOT-HKT389', 'botiquin', 'HKT389', 'Cabina', '{"tipo_botiquin": "Maletín", "clase": "Tipo B"}'::jsonb),
    ('EXT-LLP358', 'extintor', 'LLP358', 'Cabina', '{"agente": "ABC (Polvo químico seco)", "capacidad": "10 lb"}'::jsonb),
    ('BOT-LLP358', 'botiquin', 'LLP358', 'Cabina', '{"tipo_botiquin": "Maletín", "clase": "Tipo B"}'::jsonb),
    ('EXT-GES160', 'extintor', 'GES160', 'Cabina', '{"agente": "ABC (Polvo químico seco)", "capacidad": "10 lb"}'::jsonb),
    ('BOT-GES160', 'botiquin', 'GES160', 'Cabina', '{"tipo_botiquin": "Maletín", "clase": "Tipo B"}'::jsonb),
    ('EXT-LLP943', 'extintor', 'LLP943', 'Cabina', '{"agente": "ABC (Polvo químico seco)", "capacidad": "10 lb"}'::jsonb),
    ('BOT-LLP943', 'botiquin', 'LLP943', 'Cabina', '{"tipo_botiquin": "Maletín", "clase": "Tipo B"}'::jsonb),
    ('EXT-LKN455', 'extintor', 'LKN455', 'Cabina', '{"agente": "ABC (Polvo químico seco)", "capacidad": "20 lb"}'::jsonb),
    ('BOT-LKN455', 'botiquin', 'LKN455', 'Cabina', '{"tipo_botiquin": "Maletín", "clase": "Tipo B"}'::jsonb),
    ('EXT-NWV735', 'extintor', 'NWV735', 'Cabina', '{"agente": "ABC (Polvo químico seco)", "capacidad": "10 lb"}'::jsonb),
    ('BOT-NWV735', 'botiquin', 'NWV735', 'Cabina', '{"tipo_botiquin": "Maletín", "clase": "Tipo B"}'::jsonb),
    ('EXT-NOQ909', 'extintor', 'NOQ909', 'Cabina', '{"agente": "ABC (Polvo químico seco)", "capacidad": "20 lb"}'::jsonb),
    ('BOT-NOQ909', 'botiquin', 'NOQ909', 'Cabina', '{"tipo_botiquin": "Maletín", "clase": "Tipo B"}'::jsonb),
    ('EXT-JKV123', 'extintor', 'JKV123', 'Cabina', '{"agente": "ABC (Polvo químico seco)", "capacidad": "10 lb"}'::jsonb),
    ('BOT-JKV123', 'botiquin', 'JKV123', 'Cabina', '{"tipo_botiquin": "Maletín", "clase": "Tipo B"}'::jsonb),
    ('EXT-ETM918', 'extintor', 'ETM918', 'Cabina', '{"agente": "ABC (Polvo químico seco)", "capacidad": "10 lb"}'::jsonb),
    ('BOT-ETM918', 'botiquin', 'ETM918', 'Cabina', '{"tipo_botiquin": "Maletín", "clase": "Tipo B"}'::jsonb),
    ('EXT-JKV805', 'extintor', 'JKV805', 'Cabina', '{"agente": "ABC (Polvo químico seco)", "capacidad": "10 lb"}'::jsonb),
    ('BOT-JKV805', 'botiquin', 'JKV805', 'Cabina', '{"tipo_botiquin": "Maletín", "clase": "Tipo B"}'::jsonb),
    ('EXT-RKR633-CO2', 'extintor', 'RKR633', 'Zona De Actividad Unidad Movil', '{"agente": "CO2", "capacidad": "5 lb"}'::jsonb),
    ('EXT-GEN090-CO2', 'extintor', 'GEN090', 'Zona De Actividad Unidad Movil', '{"agente": "CO2", "capacidad": "5 lb"}'::jsonb),
    ('EXT-IVX646-CO2', 'extintor', 'IVX646', 'Zona De Actividad Unidad Movil', '{"agente": "CO2", "capacidad": "5 lb"}'::jsonb),
    ('EXT-BSZ008-CO2', 'extintor', 'BSZ008', 'Zona De Actividad Unidad Movil', '{"agente": "CO2", "capacidad": "5 lb"}'::jsonb),
    ('EXT-RNS233-CO2', 'extintor', 'RNS233', 'Zona De Actividad Unidad Movil', '{"agente": "CO2", "capacidad": "5 lb"}'::jsonb),
    ('EXT-ETM550-CO2', 'extintor', 'ETM550', 'Zona De Actividad Unidad Movil', '{"agente": "CO2", "capacidad": "5 lb"}'::jsonb),
    ('EXT-EQY671-CO2', 'extintor', 'EQY671', 'Zona De Actividad Unidad Movil', '{"agente": "CO2", "capacidad": "5 lb"}'::jsonb),
    ('EXT-HKL301-CO2', 'extintor', 'HKL301', 'Zona De Actividad Unidad Movil', '{"agente": "CO2", "capacidad": "5 lb"}'::jsonb),
    ('EXT-LRN903-CO2', 'extintor', 'LRN903', 'Zona De Actividad Unidad Movil', '{"agente": "CO2", "capacidad": "5 lb"}'::jsonb),
    ('EXT-NHR577-CO2', 'extintor', 'NHR577', 'Zona De Actividad Unidad Movil', '{"agente": "CO2", "capacidad": "5 lb"}'::jsonb),
    ('EXT-MCR904-CO2', 'extintor', 'MCR904', 'Zona De Actividad Unidad Movil', '{"agente": "CO2", "capacidad": "5 lb"}'::jsonb),
    ('EXT-CVK475-CO2', 'extintor', 'CVK475', 'Zona De Actividad Unidad Movil', '{"agente": "CO2", "capacidad": "5 lb"}'::jsonb),
    ('EXT-KTV547-CO2', 'extintor', 'KTV547', 'Zona De Actividad Unidad Movil', '{"agente": "CO2", "capacidad": "5 lb"}'::jsonb),
    ('EXT-NWX277-CO2', 'extintor', 'NWX277', 'Zona De Actividad Unidad Movil', '{"agente": "CO2", "capacidad": "5 lb"}'::jsonb),
    ('EXT-GES161-CO2', 'extintor', 'GES161', 'Zona De Actividad Unidad Movil', '{"agente": "CO2", "capacidad": "5 lb"}'::jsonb),
    ('EXT-HKT389-CO2', 'extintor', 'HKT389', 'Zona De Actividad Unidad Movil', '{"agente": "CO2", "capacidad": "5 lb"}'::jsonb),
    ('EXT-LLP358-CO2', 'extintor', 'LLP358', 'Zona De Actividad Unidad Movil', '{"agente": "CO2", "capacidad": "5 lb"}'::jsonb),
    ('EXT-GES160-CO2', 'extintor', 'GES160', 'Zona De Actividad Unidad Movil', '{"agente": "CO2", "capacidad": "5 lb"}'::jsonb),
    ('EXT-LKN455-CO2', 'extintor', 'LKN455', 'Zona De Actividad Unidad Movil', '{"agente": "CO2", "capacidad": "5 lb"}'::jsonb),
    ('EXT-NOQ909-CO2', 'extintor', 'NOQ909', 'Zona De Actividad Unidad Movil', '{"agente": "CO2", "capacidad": "5 lb"}'::jsonb),
    ('EXT-KTV547-SK', 'extintor', 'KTV547', 'Zona De Actividad Unidad Movil', '{"agente": "Solkaflam 123", "capacidad": "10 lb"}'::jsonb),
    ('KAD-BSZ008', 'antiderrame', 'BSZ008', 'Unidad móvil', '{"descripcion": "Kit antiderrame"}'::jsonb),
    ('KAD-CVK475', 'antiderrame', 'CVK475', 'Unidad móvil', '{"descripcion": "Kit antiderrame"}'::jsonb),
    ('KAD-EQY671', 'antiderrame', 'EQY671', 'Unidad móvil', '{"descripcion": "Kit antiderrame"}'::jsonb),
    ('KAD-ETM550', 'antiderrame', 'ETM550', 'Unidad móvil', '{"descripcion": "Kit antiderrame"}'::jsonb),
    ('KAD-ETM918', 'antiderrame', 'ETM918', 'Unidad móvil', '{"descripcion": "Kit antiderrame"}'::jsonb),
    ('KAD-GEN090', 'antiderrame', 'GEN090', 'Unidad móvil', '{"descripcion": "Kit antiderrame"}'::jsonb),
    ('KAD-GES160', 'antiderrame', 'GES160', 'Unidad móvil', '{"descripcion": "Kit antiderrame"}'::jsonb),
    ('KAD-GES161', 'antiderrame', 'GES161', 'Unidad móvil', '{"descripcion": "Kit antiderrame"}'::jsonb),
    ('KAD-HKL301', 'antiderrame', 'HKL301', 'Unidad móvil', '{"descripcion": "Kit antiderrame"}'::jsonb),
    ('KAD-HKT389', 'antiderrame', 'HKT389', 'Unidad móvil', '{"descripcion": "Kit antiderrame"}'::jsonb),
    ('KAD-IVX646', 'antiderrame', 'IVX646', 'Unidad móvil', '{"descripcion": "Kit antiderrame"}'::jsonb),
    ('KAD-JKV123', 'antiderrame', 'JKV123', 'Unidad móvil', '{"descripcion": "Kit antiderrame"}'::jsonb),
    ('KAD-JKV805', 'antiderrame', 'JKV805', 'Unidad móvil', '{"descripcion": "Kit antiderrame"}'::jsonb),
    ('KAD-KTV547', 'antiderrame', 'KTV547', 'Unidad móvil', '{"descripcion": "Kit antiderrame"}'::jsonb),
    ('KAD-LKN455', 'antiderrame', 'LKN455', 'Unidad móvil', '{"descripcion": "Kit antiderrame"}'::jsonb),
    ('KAD-LLP358', 'antiderrame', 'LLP358', 'Unidad móvil', '{"descripcion": "Kit antiderrame"}'::jsonb),
    ('KAD-LLP943', 'antiderrame', 'LLP943', 'Unidad móvil', '{"descripcion": "Kit antiderrame"}'::jsonb),
    ('KAD-LRN903', 'antiderrame', 'LRN903', 'Unidad móvil', '{"descripcion": "Kit antiderrame"}'::jsonb),
    ('KAD-MCR904', 'antiderrame', 'MCR904', 'Unidad móvil', '{"descripcion": "Kit antiderrame"}'::jsonb),
    ('KAD-NHR577', 'antiderrame', 'NHR577', 'Unidad móvil', '{"descripcion": "Kit antiderrame"}'::jsonb),
    ('KAD-NOQ909', 'antiderrame', 'NOQ909', 'Unidad móvil', '{"descripcion": "Kit antiderrame"}'::jsonb),
    ('KAD-NWV735', 'antiderrame', 'NWV735', 'Unidad móvil', '{"descripcion": "Kit antiderrame"}'::jsonb),
    ('KAD-NWV837', 'antiderrame', 'NWV837', 'Unidad móvil', '{"descripcion": "Kit antiderrame"}'::jsonb),
    ('KAD-NWX277', 'antiderrame', 'NWX277', 'Unidad móvil', '{"descripcion": "Kit antiderrame"}'::jsonb),
    ('KAD-RKR633', 'antiderrame', 'RKR633', 'Unidad móvil', '{"descripcion": "Kit antiderrame"}'::jsonb),
    ('KAD-RNS233', 'antiderrame', 'RNS233', 'Unidad móvil', '{"descripcion": "Kit antiderrame"}'::jsonb),
    ('CAM-BSZ008', 'camilla', 'BSZ008', 'Unidad móvil', '{}'::jsonb),
    ('CAM-CVK475', 'camilla', 'CVK475', 'Unidad móvil', '{}'::jsonb),
    ('CAM-EQY671', 'camilla', 'EQY671', 'Unidad móvil', '{}'::jsonb),
    ('CAM-GEN090', 'camilla', 'GEN090', 'Unidad móvil', '{}'::jsonb),
    ('CAM-GES160', 'camilla', 'GES160', 'Unidad móvil', '{}'::jsonb),
    ('CAM-GES161', 'camilla', 'GES161', 'Unidad móvil', '{}'::jsonb),
    ('CAM-HKL301', 'camilla', 'HKL301', 'Unidad móvil', '{}'::jsonb),
    ('CAM-HKT389', 'camilla', 'HKT389', 'Unidad móvil', '{}'::jsonb),
    ('CAM-IVX646', 'camilla', 'IVX646', 'Unidad móvil', '{}'::jsonb),
    ('CAM-KTV547', 'camilla', 'KTV547', 'Unidad móvil', '{}'::jsonb),
    ('CAM-LKN455', 'camilla', 'LKN455', 'Unidad móvil', '{}'::jsonb),
    ('CAM-LLP358', 'camilla', 'LLP358', 'Unidad móvil', '{}'::jsonb),
    ('CAM-LRN903', 'camilla', 'LRN903', 'Unidad móvil', '{}'::jsonb),
    ('CAM-MCR904', 'camilla', 'MCR904', 'Unidad móvil', '{}'::jsonb),
    ('CAM-NHR577', 'camilla', 'NHR577', 'Unidad móvil', '{}'::jsonb),
    ('CAM-NOQ909', 'camilla', 'NOQ909', 'Unidad móvil', '{}'::jsonb),
    ('CAM-NWX277', 'camilla', 'NWX277', 'Unidad móvil', '{}'::jsonb),
    ('CAM-RKR633', 'camilla', 'RKR633', 'Unidad móvil', '{}'::jsonb),
    ('CAM-RNS233', 'camilla', 'RNS233', 'Unidad móvil', '{}'::jsonb),
    ('SEN-BSZ008', 'senalizacion', 'BSZ008', 'Unidad móvil', '{"descripcion": "Unidad BSZ008"}'::jsonb),
    ('SEN-CVK475', 'senalizacion', 'CVK475', 'Unidad móvil', '{"descripcion": "Unidad CVK475"}'::jsonb),
    ('SEN-EQY671', 'senalizacion', 'EQY671', 'Unidad móvil', '{"descripcion": "Unidad EQY671"}'::jsonb),
    ('SEN-ETM550', 'senalizacion', 'ETM550', 'Unidad móvil', '{"descripcion": "Unidad ETM550"}'::jsonb),
    ('SEN-ETM918', 'senalizacion', 'ETM918', 'Unidad móvil', '{"descripcion": "Unidad ETM918"}'::jsonb),
    ('SEN-GEN090', 'senalizacion', 'GEN090', 'Unidad móvil', '{"descripcion": "Unidad GEN090"}'::jsonb),
    ('SEN-GES160', 'senalizacion', 'GES160', 'Unidad móvil', '{"descripcion": "Unidad GES160"}'::jsonb),
    ('SEN-GES161', 'senalizacion', 'GES161', 'Unidad móvil', '{"descripcion": "Unidad GES161"}'::jsonb),
    ('SEN-HKL301', 'senalizacion', 'HKL301', 'Unidad móvil', '{"descripcion": "Unidad HKL301"}'::jsonb),
    ('SEN-HKT389', 'senalizacion', 'HKT389', 'Unidad móvil', '{"descripcion": "Unidad HKT389"}'::jsonb),
    ('SEN-IVX646', 'senalizacion', 'IVX646', 'Unidad móvil', '{"descripcion": "Unidad IVX646"}'::jsonb),
    ('SEN-JKV123', 'senalizacion', 'JKV123', 'Unidad móvil', '{"descripcion": "Unidad JKV123"}'::jsonb),
    ('SEN-JKV805', 'senalizacion', 'JKV805', 'Unidad móvil', '{"descripcion": "Unidad JKV805"}'::jsonb),
    ('SEN-KTV547', 'senalizacion', 'KTV547', 'Unidad móvil', '{"descripcion": "Unidad KTV547"}'::jsonb),
    ('SEN-LKN455', 'senalizacion', 'LKN455', 'Unidad móvil', '{"descripcion": "Unidad LKN455"}'::jsonb),
    ('SEN-LLP358', 'senalizacion', 'LLP358', 'Unidad móvil', '{"descripcion": "Unidad LLP358"}'::jsonb),
    ('SEN-LLP943', 'senalizacion', 'LLP943', 'Unidad móvil', '{"descripcion": "Unidad LLP943"}'::jsonb),
    ('SEN-LRN903', 'senalizacion', 'LRN903', 'Unidad móvil', '{"descripcion": "Unidad LRN903"}'::jsonb),
    ('SEN-MCR904', 'senalizacion', 'MCR904', 'Unidad móvil', '{"descripcion": "Unidad MCR904"}'::jsonb),
    ('SEN-NHR577', 'senalizacion', 'NHR577', 'Unidad móvil', '{"descripcion": "Unidad NHR577"}'::jsonb),
    ('SEN-NOQ909', 'senalizacion', 'NOQ909', 'Unidad móvil', '{"descripcion": "Unidad NOQ909"}'::jsonb),
    ('SEN-NWV735', 'senalizacion', 'NWV735', 'Unidad móvil', '{"descripcion": "Unidad NWV735"}'::jsonb),
    ('SEN-NWV837', 'senalizacion', 'NWV837', 'Unidad móvil', '{"descripcion": "Unidad NWV837"}'::jsonb),
    ('SEN-NWX277', 'senalizacion', 'NWX277', 'Unidad móvil', '{"descripcion": "Unidad NWX277"}'::jsonb),
    ('SEN-RKR633', 'senalizacion', 'RKR633', 'Unidad móvil', '{"descripcion": "Unidad RKR633"}'::jsonb),
    ('SEN-RNS233', 'senalizacion', 'RNS233', 'Unidad móvil', '{"descripcion": "Unidad RNS233"}'::jsonb)
) as v(codigo, tipo, placa, ubicacion, datos)
join public.insp_lugares l on l.placa = v.placa
on conflict (codigo) do update
    set tipo = excluded.tipo, lugar_id = excluded.lugar_id,
        ubicacion = excluded.ubicacion, datos = excluded.datos, activo = true;

select tipo, count(*) as cantidad from public.insp_elementos where activo group by tipo order by tipo;
