-- =====================================================================
-- EMOTION INSPECCIONES — Actualización: campañas itinerantes
-- Pega TODO en Supabase (proyecto emotion-inspecciones) → SQL Editor → + → Run
-- =====================================================================

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
