/*
 * TIPOS DE ELEMENTOS Y LISTAS DE CHEQUEO — Emotion Inspecciones
 * ------------------------------------------------------------------
 * Basado en los formatos del SIG de E-MOTION GLOBAL S.A.S.:
 *  - Registro de inspección de extintores
 *  - Registro de inspección de botiquines y elementos de emergencia
 *
 * Cada tipo tiene:
 *   campos     -> datos fijos del elemento (los registra el administrador)
 *   secciones  -> lo que se revisa en cada inspección
 *      modo "check"      -> cada punto se marca Cumple / No cumple / N/A
 *      modo "inventario" -> cada elemento con cantidad requerida (Tipo A / Tipo B),
 *                           cantidad encontrada y fecha de vencimiento
 *   frecuenciaDias -> cada cuántos días debe inspeccionarse
 */

// ---------- Señalización obligatoria (sin opción N/A) ----------
// Vehículos pequeños donde la señalización del extintor y del botiquín puede marcarse N/A
const PLACAS_SENAL_OPCIONAL = ["NWV837", "LLP943", "NWV735", "JKV123", "ETM918", "JKV805"];

function senalObligatoria(el) {
    return !PLACAS_SENAL_OPCIONAL.includes(el.lugar?.placa || "");
}

// ¿El lugar del elemento tiene un elemento de este tipo? (ej. si la unidad tiene camilla)
function tieneElemento(el, tipo) {
    return typeof ELEMENTOS !== "undefined" && ELEMENTOS.some(e => e.lugar_id === el.lugar_id && e.tipo === tipo);
}

const AGENTES_EXTINTOR = ["ABC (Polvo químico seco)", "BC (Polvo químico seco)", "CO2", "Solkaflam 123", "Agua", "Otro"];

const TIPOS = {
    extintor: {
        nombre: "Extintor",
        titulo: "Registro de inspección de extintores",
        icono: "🧯",
        color: "#EF4444",
        prefijo: "EXT",
        frecuenciaDias: 30,
        usaVencimiento: true,
        vencimientoMes: true,               // la próxima recarga se registra por mes/año
        etiquetaVencimiento: "Próxima recarga",
        // Fechas de revisión: se confirman o actualizan en cada inspección (mes/año)
        fechasRevision: [
            { id: "ultima_recarga", label: "Última fecha de recarga" },
            { id: "proxima_recarga", label: "Próxima fecha de recarga" },
            { id: "ultimo_mantenimiento", label: "Última fecha de mantenimiento" },
            { id: "prueba_hidrostatica", label: "Fecha de prueba hidrostática" }
        ],
        campos: [
            { id: "agente", label: "Tipo de agente extintor", tipo: "select", opciones: AGENTES_EXTINTOR },
            { id: "capacidad", label: "Capacidad (libras o gramos)", tipo: "text", placeholder: "Ej: 20 lb" },
            { id: "ultima_recarga", label: "Última fecha de recarga", tipo: "month" },
            { id: "ultimo_mantenimiento", label: "Última fecha de mantenimiento", tipo: "month" },
            { id: "prueba_hidrostatica", label: "Fecha de prueba hidrostática", tipo: "month" }
        ],
        secciones: [
            {
                titulo: "Instalación del extintor",
                modo: "check",
                items: [
                    "Peso ≤ a 40 lb – instalado a máximo 1,53 m sobre el suelo",
                    "Peso > a 40 lb – instalado hasta 1,07 m sobre el suelo",
                    "Espacio libre entre la base del extintor y el piso ≥ a 10,2 cm",
                    "Extintor visible y accesible",
                    { t: "Señalización", obligatorio: senalObligatoria },
                    "Demarcación"
                ]
            },
            {
                titulo: "Estado del extintor",
                modo: "check",
                items: [
                    "Estado físico del cilindro (pintura, daños, corrosión)",
                    "Etiqueta de instrucciones de manejo (visible)",
                    "Manija de transporte",
                    "Palanca de descarga",
                    "Manómetro (aguja en zona normal: ni sobrecargado ni descargado)",
                    "Boquilla o corneta",
                    "Manguera",
                    "Collar de servicio",
                    "Estado del pasador (pin de seguridad)",
                    "Soporte del extintor",
                    "Estado del soporte"
                ]
            }
        ]
    },

    botiquin: {
        nombre: "Botiquín",
        titulo: "Registro de inspección de botiquines y elementos de emergencia",
        icono: "🩹",
        color: "#34C759",
        prefijo: "BOT",
        frecuenciaDias: 30,
        usaVencimiento: false,
        campos: [
            { id: "tipo_botiquin", label: "Tipo de botiquín", tipo: "select", opciones: ["Maletín", "Morral", "Pared (empotrable)", "Canguro"] },
            { id: "clase", label: "Clase de botiquín", tipo: "select", opciones: ["Tipo A", "Tipo B"] }
        ],
        secciones: [
            {
                titulo: "Elementos del botiquín y emergencia",
                modo: "inventario",
                items: [
                    { nombre: "Morral (Tipo A: 30x15x12 cm – Tipo B: 50x32x10 cm)", unidad: "Unidad", A: 1, B: 1 },
                    { nombre: "Gasas limpias", unidad: "Paquete", A: 20, B: 100 },
                    { nombre: "Gasas estériles paquete x 3", unidad: "Unidad", A: 20, B: 20 },
                    { nombre: "Esparadrapo de tela", unidad: "Rollo", A: 1, B: 2 },
                    { nombre: "Apósito o compresa no estéril", unidad: "Unidad", A: 2, B: 4 },
                    { nombre: "Tijera universal para trauma", unidad: "Unidad", A: 1, B: 1 },
                    { nombre: "Bajalenguas paquete x 20", unidad: "Unidad", A: 1, B: 2 },
                    { nombre: "Guantes de látex para examen", unidad: "Unidad", A: 1, B: 1 },
                    { nombre: "Venda elástica 2x5 yardas", unidad: "Unidad", A: 1, B: 2 },
                    { nombre: "Venda elástica 3x5 yardas", unidad: "Unidad", A: 1, B: 2 },
                    { nombre: "Venda elástica 5x5 yardas", unidad: "Unidad", A: 1, B: 2 },
                    { nombre: "Venda de algodón 3x5 yardas", unidad: "Unidad", A: 1, B: 2 },
                    { nombre: "Venda de algodón 5x5 yardas", unidad: "Unidad", A: 1, B: 2 },
                    { nombre: "Yodopovidona 120 ml", unidad: "Frasco", A: 1, B: 2 },
                    { nombre: "Solución salina 500 cc", unidad: "Frasco", A: 1, B: 2 },
                    { nombre: "Vasos desechables", unidad: "Paquete", A: 1, B: 1 },
                    { nombre: "Botella de agua", unidad: "Botella", A: 1, B: 1 },
                    { nombre: "Tensiómetro", unidad: "Unidad", A: 1, B: 1 },
                    { nombre: "Fonendoscopio", unidad: "Unidad", A: 1, B: 1 },
                    { nombre: "Termómetro de mercurio o digital", unidad: "Unidad", A: 1, B: 1 },
                    { nombre: "Máscara para RCP", unidad: "Unidad", A: 1, B: 2 },
                    { nombre: "Alcohol antiséptico 300 ml", unidad: "Frasco", A: 1, B: 1 },
                    { nombre: "Gel antibacterial 250 ml", unidad: "Frasco", A: 1, B: 1 },
                    { nombre: "Tapabocas quirúrgico", unidad: "Unidad", A: 10, B: 10 },
                    { nombre: "Linterna", unidad: "Unidad", A: 1, B: 1 },
                    { nombre: "Manual de primeros auxilios", unidad: "Unidad", A: 1, B: 1 },
                    { nombre: "Tabla espinal larga (camilla con arnés)", unidad: "Unidad", A: 0, B: 1 },
                    { nombre: "Collar cervical adulto", unidad: "Unidad", A: 0, B: 1 },
                    { nombre: "Inmovilizadores o férula miembros superiores", unidad: "Unidad", A: 0, B: 1 },
                    { nombre: "Inmovilizadores o férula miembros inferiores", unidad: "Unidad", A: 0, B: 1 }
                ]
            },
            {
                titulo: "Estado general de botiquines y elementos de emergencia",
                modo: "check",
                items: [
                    "a. ¿El botiquín se encuentra en un lugar despejado y de fácil acceso?",
                    { t: "b. ¿El botiquín se encuentra señalizado?", obligatorio: senalObligatoria },
                    "c. ¿El botiquín se encuentra en buenas condiciones de limpieza?",
                    "d. ¿La camilla se encuentra en un lugar despejado y de fácil acceso?",
                    "e. ¿La camilla se encuentra en buenas condiciones de limpieza?",
                    "f. ¿Alarma de emergencia en buen estado?",
                    { t: "g. ¿El botiquín y los elementos de emergencia están señalizados?", obligatorio: senalObligatoria },
                    "h. ¿El área inspeccionada cuenta con señalización de evacuación?",
                    "i. ¿En el área inspeccionada se evidencian planos de evacuación?",
                    "j. ¿En el área inspeccionada se evidencian números de atención de emergencias?"
                ]
            }
        ]
    },

    camilla: {
        nombre: "Camilla",
        icono: "🛏️",
        color: "#16A34A",
        prefijo: "CAM",
        frecuenciaDias: 30,
        campos: [{ id: "descripcion", label: "Descripción", tipo: "text", placeholder: "Ej: Tabla espinal larga con arnés" }],
        secciones: [{
            titulo: "Estado de la camilla", modo: "check",
            items: [
                "La estructura no tiene fisuras, golpes ni deformaciones",
                "Tiene sus correas o arnés completos y en buen estado",
                "Tiene inmovilizador de cabeza (laterales) completo",
                "Tiene collar cervical",
                "Está limpia y lista para usar",
                "Está en un lugar despejado y de fácil acceso"
            ]
        }]
    },

    antiderrame: {
        nombre: "Kit antiderrame",
        icono: "🛢️",
        color: "#0F9F6E",
        prefijo: "KAD",
        frecuenciaDias: 30,
        campos: [{ id: "descripcion", label: "Descripción", tipo: "text", placeholder: "Ej: Kit para hidrocarburos 20 galones" }],
        secciones: [{
            titulo: "Contenido y estado del kit", modo: "check",
            items: [
                "Paños o almohadillas absorbentes completos",
                "Barreras o salchichas absorbentes",
                "Material absorbente granulado (si aplica)",
                "Bolsas para residuos peligrosos",
                "Guantes de nitrilo",
                "Gafas de seguridad",
                "Pala o recogedor antichispa",
                "Instructivo de uso visible",
                "El contenedor está cerrado, limpio y en buen estado",
                "Está cerca del área de químicos o combustibles y de fácil acceso"
            ]
        }]
    },

    fichas: {
        nombre: "Fichas de seguridad",
        icono: "📋",
        color: "#0EA5E9",
        prefijo: "FDS",
        frecuenciaDias: 90,
        campos: [{ id: "descripcion", label: "Descripción", tipo: "text", placeholder: "Ej: Carpeta de químicos de la planta" }],
        secciones: [{
            titulo: "Fichas de datos de seguridad (FDS)", modo: "check",
            items: [
                "Hay ficha de datos de seguridad para cada sustancia química del área",
                "Las fichas están en español",
                "Las fichas tienen las 16 secciones",
                "Las fichas están actualizadas (no tienen más de 5 años)",
                "Las fichas están disponibles y accesibles en el lugar de uso",
                "Los recipientes están rotulados con etiqueta SGA (pictogramas)",
                "Existe la matriz de compatibilidad de sustancias",
                "Los trabajadores del área saben dónde están las fichas",
                "La ubicación de las fichas está señalizada"
            ]
        }]
    },

    senalizacion: {
        nombre: "Señalización",
        icono: "🚨",
        color: "#F38B33",
        prefijo: "SEN",
        frecuenciaDias: 30,
        campos: [{ id: "descripcion", label: "Área o unidad", tipo: "text", placeholder: "Ej: Unidad móvil / Planta – primer piso" }],
        secciones: [
            {
                titulo: "Señalización de los elementos de emergencia", modo: "check",
                items: [
                    { t: "Señal del extintor visible y en buen estado", obligatorio: senalObligatoria },
                    { t: "Señal del botiquín visible y en buen estado", obligatorio: senalObligatoria },
                    { t: "Señal de la camilla visible y en buen estado", obligatorio: el => tieneElemento(el, "camilla") },
                    "Señal del kit antiderrame visible y en buen estado",
                    "Las señales son legibles, sin decoloración ni daños"
                ]
            },
            {
                titulo: "Escaleras, cambios de nivel y riesgo eléctrico", modo: "check",
                items: [
                    "Escaleras señalizadas",
                    "Cinta antideslizante en los escalones, completa y en buen estado",
                    "Señal de precaución por cambio de nivel",
                    "Tomacorrientes señalizados (voltaje 110 V / 220 V)",
                    "Señalización de riesgo eléctrico en tableros y plantas"
                ]
            },
            {
                titulo: "Señalización de evacuación y emergencia", modo: "check",
                items: [
                    "Salidas de emergencia señalizadas y libres",
                    "Rutas de evacuación señalizadas",
                    "Números de atención de emergencias visibles",
                    "Señal de prohibido fumar",
                    "Punto de encuentro señalizado (si aplica)",
                    "Luces de emergencia funcionan (si aplica)",
                    "Alarma de emergencia funciona (si aplica)",
                    "Plano de evacuación publicado (si aplica)"
                ]
            }
        ]
    },

    alturas: {
        nombre: "Equipo para alturas",
        icono: "🪢",
        color: "#7C3AED",
        prefijo: "ALT",
        frecuenciaDias: 30,
        usaVencimiento: true,
        etiquetaVencimiento: "Vida útil hasta",
        campos: [{ id: "descripcion", label: "Descripción", tipo: "text", placeholder: "Ej: Arnés cuerpo completo + eslinga con absorbedor" }],
        secciones: [{
            titulo: "Estado del equipo", modo: "check",
            items: [
                "Las reatas y costuras no tienen cortes, quemaduras ni desgaste",
                "Las argollas (anillos D) y hebillas no tienen deformaciones ni corrosión",
                "La eslinga o línea de vida está en buen estado",
                "El absorbedor de energía no se ha activado",
                "Los mosquetones abren, cierran y aseguran correctamente",
                "La etiqueta del fabricante es legible",
                "Está dentro de su vida útil",
                "Se guarda limpio, colgado y lejos del sol y los químicos"
            ]
        }]
    },

    lavaojos: {
        nombre: "Lavaojos / ducha",
        icono: "🚿",
        color: "#06B6D4",
        prefijo: "LAV",
        frecuenciaDias: 30,
        usaVencimiento: true,
        etiquetaVencimiento: "Cambio de solución",
        campos: [{ id: "descripcion", label: "Descripción", tipo: "text", placeholder: "Ej: Lavaojos portátil" }],
        secciones: [{
            titulo: "Estado del lavaojos o ducha", modo: "check",
            items: [
                "Sale agua o solución al activarlo",
                "El agua o la solución está limpia",
                "Las tapas protectoras de las boquillas están puestas",
                "La solución está vigente (si es portátil)",
                "El acceso está libre",
                "Está cerca del área donde se manejan químicos"
            ]
        }]
    }
};

// Camilla, kit antiderrame, alturas y lavaojos revisan al final su señalización
// (y demarcación, excepto la camilla). Extintor, botiquín y señalización ya lo traen en su formato.
["camilla", "antiderrame", "alturas", "lavaojos"].forEach(t => TIPOS[t].secciones.push({
    titulo: "Señalización y demarcación",
    modo: "check",
    items: [
        // La señalización de la camilla es obligatoria siempre (sin N/A)
        { t: "Cuenta con señalización (aviso visible que identifica el elemento)", obligatorio: t === "camilla" },
        { t: "La señalización está en buen estado y legible", obligatorio: t === "camilla" },
        // La camilla no requiere demarcación, solo señalización
        ...(t === "camilla" ? [] : ["Demarcación del área (si aplica)"])
    ]
}));

const ORDEN_TIPOS = ["extintor", "botiquin", "camilla", "antiderrame", "fichas", "senalizacion", "alturas", "lavaojos"];
const TIPOS_LUGAR = ["Sede", "Unidad móvil", "Camioneta", "Microbús", "Furgón", "Van", "Vehículo"];

// Color de cada elemento: extintor ABC amarillo; CO2, Solkaflam y demás extintores rojos
function colorElemento(e) {
    const T = TIPOS[e.tipo] || { color: "#999" };
    if (e.tipo === "extintor" && /^ABC/i.test((e.datos || {}).agente || "")) return "#EAB308";
    return T.color;
}

// Texto corto con los datos del elemento (ej. "ABC (Polvo químico seco) · 20 lb")
function resumenDatos(el) {
    const T = TIPOS[el.tipo]; const d = el.datos || {};
    if (!T) return "";
    return T.campos.filter(c => c.tipo !== "date" && c.tipo !== "month" && d[c.id]).map(c => d[c.id]).join(" · ");
}
