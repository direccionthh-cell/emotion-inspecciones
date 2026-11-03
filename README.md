# Emotion Inspecciones

Plataforma de e-motion para inspeccionar los elementos de seguridad y emergencia: extintores, botiquines, camillas, kits antiderrame, fichas de seguridad, señalización, equipos para alturas y lavaojos.

Tiene **su propio proyecto de Supabase**, independiente de Emotion Campus. La conexión se configura en `js/config.js`.

## Páginas

| Archivo | Para qué sirve |
|---|---|
| `index.html` | Entrada: lleva al panel |
| `ingresar.html` | Inicio de sesión (solo administración e historial) |
| `panel.html` | Estado general, elementos por tipo y lo que requiere atención |
| `inspeccionar.html` | Elegir un elemento y llenar su lista de chequeo (funciona en celular) |
| `elementos.html` | Inventario. Los administradores agregan, editan y dan de baja elementos y lugares |
| `qr.html` | Etiquetas con código QR para imprimir y pegar en cada elemento |
| `historial.html` | Todas las inspecciones, con detalle (formato SIG con firmas), fotos, impresión y exportación a Excel |
| `js/tipos.js` | **Tipos de elementos y sus listas de chequeo** (aquí se editan las preguntas) |
| `js/base.js` | Sesión, menú, carga de datos y cálculo de estados |
| `supabase/esquema.sql` | Tablas y reglas de seguridad |

## Estados de un elemento

- **Vencido**: pasó su fecha de vencimiento o recarga.
- **Con novedades**: la última inspección tuvo puntos que no cumplen.
- **Por inspeccionar**: nunca se ha inspeccionado o ya pasó su frecuencia (30 días; fichas y señalización, 90 días).
- **Por vencer**: vence en los próximos 30 días.
- **Al día**: todo en orden.

Cuando se corrige una novedad, se hace una nueva inspección. Cuando se recarga un extintor, un administrador actualiza la fecha en *Elementos → Editar*.

## Formatos del SIG

Las listas de chequeo de extintores y de botiquines siguen los formatos *Registro de inspección de extintores* y *Registro de inspección de botiquines y elementos de emergencia* (Resolución 0705 de 2007) de E-MOTION GLOBAL S.A.S.

## Fotos

Las fotos se guardan en Supabase Storage, en la carpeta `inspecciones`. Se reducen automáticamente (máx. 1280 px) antes de subirse.

## Códigos QR

Los QR apuntan a la dirección definida en `URL_PUBLICA` (`js/config.js`). Funcionan cuando la plataforma está publicada en esa dirección (GitHub Pages). Al escanear, si la persona no ha iniciado sesión, primero se le pide entrar y luego se abre la inspección del elemento.

## Inspección sin contraseña

Cualquier persona con el enlace o el QR puede ver el panel, el inventario y registrar inspecciones escribiendo su nombre (se recuerda en su celular). El **historial**, la **edición de elementos y lugares** y la **impresión de QR** requieren iniciar sesión.
