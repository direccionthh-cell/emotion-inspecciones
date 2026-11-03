-- =====================================================================
-- EMOTION INSPECCIONES — Actualización: fechas de extintores por mes/año
-- Pega TODO en Supabase (proyecto emotion-inspecciones) → SQL Editor → + → Run
-- =====================================================================

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
