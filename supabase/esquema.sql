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
