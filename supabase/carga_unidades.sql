-- =====================================================================
-- EMOTION INSPECCIONES — Carga de unidades móviles y vehículos (26)
-- Pega TODO en Supabase (proyecto emotion-inspecciones) → SQL Editor → + → Run
-- Se puede ejecutar más de una vez: no duplica las placas ya cargadas.
-- =====================================================================

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

select count(*) as unidades_cargadas from public.insp_lugares where placa is not null;
