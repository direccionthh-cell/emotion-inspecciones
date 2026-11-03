/*
 * BASE — Emotion Inspecciones
 * Sesión, menú lateral, carga de datos y cálculo del estado de cada elemento.
 * Cada página espera los datos con:  listo.then(() => { ... })
 */

if (SUPABASE_URL.startsWith("PEGA_AQUI")) {
    document.addEventListener("DOMContentLoaded", () => document.body.innerHTML =
        '<div class="aviso" style="margin:30px">Falta configurar la conexión: pega los datos de Supabase en <strong>js/config.js</strong>.</div>');
    throw new Error("Falta configurar js/config.js");
}
const supa = supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

let USUARIO = null;     // { id, email, nombre, rol }
let LUGARES = [];       // [{ id, nombre, tipo }]
let ELEMENTOS = [];     // elementos con: lugar, ultima (última inspección) y estado

// Páginas que exigen iniciar sesión: <body data-requiere-login>
const listo = (async () => {
    const { data: { session } } = await supa.auth.getSession();
    if (session) {
        const u = session.user;
        const { data: perfil } = await supa.from("perfiles").select("*").eq("id", u.id).maybeSingle();
        USUARIO = { id: u.id, email: u.email, nombre: perfil?.nombre || u.email.split("@")[0], rol: perfil?.rol || "colaborador" };
    } else if (document.body.hasAttribute("data-requiere-login")) {
        window.location.href = "ingresar.html?next=" + encodeURIComponent(location.pathname.split("/").pop() + location.search);
        return new Promise(() => {});
    }
    dibujarSidebar();
    await cargarDatos();
})();

const esAdmin = () => USUARIO?.rol === "admin";

async function cargarDatos() {
    const [l, e, i] = await Promise.all([
        supa.from("insp_lugares").select("*").eq("activo", true).order("nombre"),
        supa.from("insp_elementos").select("*").eq("activo", true).order("codigo"),
        supa.rpc("insp_ultimas")
    ]);
    const error = l.error || e.error || i.error;
    if (error) {
        mostrarAviso("No se pudieron cargar los datos: " + error.message + ". ¿Ya ejecutaste supabase/esquema.sql?");
        return;
    }
    LUGARES = l.data;
    const ultimas = {};
    (i.data || []).forEach(r => { ultimas[r.elemento_id] = r; });
    ELEMENTOS = e.data.map(el => {
        const x = { ...el, lugar: LUGARES.find(p => p.id === el.lugar_id), ultima: ultimas[el.id] || null };
        x.estado = calcularEstado(x);
        return x;
    });
}

// ---------- Estado de un elemento ----------
const ESTADOS = {
    vencido:   { texto: "Vencido",          clase: "rojo",     orden: 0 },
    novedad:   { texto: "Con novedades",    clase: "rojo",     orden: 1 },
    pendiente: { texto: "Por inspeccionar", clase: "naranja",  orden: 2 },
    porVencer: { texto: "Por vencer",       clase: "naranja",  orden: 3 },
    ok:        { texto: "Al día",           clase: "verde",    orden: 4 }
};

function hoy() { const d = new Date(); d.setHours(0, 0, 0, 0); return d; }
function diasEntre(a, b) { return Math.round((b - a) / 86400000); }
function fechaLocal(iso) { const [y, m, d] = iso.slice(0, 10).split("-"); return new Date(+y, m - 1, +d); }

function calcularEstado(el) {
    const tipo = TIPOS[el.tipo] || { frecuenciaDias: 30 };
    if (el.fecha_vencimiento && fechaLocal(el.fecha_vencimiento) < hoy()) return "vencido";
    if (el.ultima && el.ultima.resultado === "con_novedades") return "novedad";
    if (!el.ultima || diasEntre(new Date(el.ultima.fecha), new Date()) > tipo.frecuenciaDias) return "pendiente";
    if (el.fecha_vencimiento && diasEntre(hoy(), fechaLocal(el.fecha_vencimiento)) <= 30) return "porVencer";
    return "ok";
}

function etiquetaEstado(estado) {
    const e = ESTADOS[estado];
    return `<span class="chip chip-${e.clase}">${e.texto}</span>`;
}

function proximaInspeccion(el) {
    if (!el.ultima) return "Ahora";
    const d = new Date(el.ultima.fecha);
    d.setDate(d.getDate() + (TIPOS[el.tipo]?.frecuenciaDias || 30));
    return formatoFecha(d.toISOString());
}

// ---------- Utilidades ----------
function formatoFecha(iso) {
    if (!iso) return "—";
    const [a, m, d] = String(iso).slice(0, 10).split("-");
    return d ? `${d}/${m}/${a}` : `${m}/${a}`;      // "AAAA-MM" se muestra como MM/AAAA
}

// Mes/año: "2026-11" o "2026-11-30" → "11/2026"
function formatoMes(v) {
    if (!v) return "—";
    const [a, m] = String(v).split("-");
    return `${m}/${a}`;
}

// "2026-11" → "2026-11-30" (último día del mes, para calcular vencimientos)
function finDeMes(mes) {
    if (!mes) return null;
    const [a, m] = mes.split("-").map(Number);
    const d = new Date(a, m, 0).getDate();
    return `${a}-${String(m).padStart(2, "0")}-${String(d).padStart(2, "0")}`;
}

// Texto de la fecha de vencimiento según el tipo (mes/año para extintores)
function textoVence(el) {
    if (!el.fecha_vencimiento) return "—";
    return TIPOS[el.tipo]?.vencimientoMes ? formatoMes(el.fecha_vencimiento) : formatoFecha(el.fecha_vencimiento);
}

function formatoFechaHora(iso) {
    if (!iso) return "—";
    return new Date(iso).toLocaleString("es-CO", { dateStyle: "short", timeStyle: "short" });
}

function esc(t) {
    return String(t ?? "").replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
}

function nombreLugar(el) { return el.lugar ? etiquetaLugar(el.lugar) : "Sin lugar"; }
function etiquetaLugar(l) { return l.placa ? `${l.nombre} · ${l.placa}` : l.nombre; }

function mostrarAviso(texto) {
    const main = document.querySelector(".main-content");
    if (!main) return alert(texto);
    const div = document.createElement("div");
    div.className = "aviso";
    div.textContent = texto;
    main.prepend(div);
}

// ---------- Menú ----------
function dibujarSidebar() {
    const aside = document.getElementById("sidebar");
    if (!aside) return;
    const menu = [
        { id: "panel",        texto: "📊 Panel",        href: "panel.html" },
        { id: "inspeccionar", texto: "✅ Inspeccionar", href: "inspeccionar.html" },
        { id: "elementos",    texto: "🧯 Elementos",    href: "elementos.html" }
    ];
    if (USUARIO) menu.push(
        { id: "historial", texto: "🗂️ Historial",   href: "historial.html" },
        { id: "qr",        texto: "🔳 Códigos QR",  href: "qr.html" });
    const activo = aside.dataset.activo;
    aside.className = "sidebar";
    aside.innerHTML = `
        <div class="sidebar-logo">
            <img src="assets/images/logo-emotion.jpeg" alt="Emotion">
            <span>e-motion<small>Inspecciones</small></span>
        </div>
        <ul class="sidebar-menu">
            ${menu.map(m => `<li><a href="${m.href}" class="${m.id === activo ? "active" : ""}">${m.texto}</a></li>`).join("")}
        </ul>
        ${USUARIO
            ? `<div class="sidebar-user"><strong>${esc(USUARIO.nombre)}</strong><br>${esc(USUARIO.email)}${USUARIO.rol === "admin" ? "<br>Administrador" : ""}</div>
               <button class="btn-emotion-outline" id="btnLogout">Cerrar sesión</button>`
            : `<div class="sidebar-user">Historial y administración</div>
               <a class="btn-emotion-outline btn-ingresar" href="ingresar.html">🔐 Ingresar</a>`}
    `;
    if (!USUARIO) return;
    document.getElementById("btnLogout").addEventListener("click", async () => {
        await supa.auth.signOut();
        window.location.href = "index.html";
    });
}

// Exporta filas a un CSV que Excel abre directamente
function descargarCSV(nombre, filas) {
    const limpiar = v => `"${String(v ?? "").replace(/"/g, '""')}"`;
    const csv = "﻿" + filas.map(f => f.map(limpiar).join(";")).join("\r\n");
    const a = document.createElement("a");
    a.href = URL.createObjectURL(new Blob([csv], { type: "text/csv;charset=utf-8" }));
    a.download = nombre;
    a.click();
}

// Fila de un elemento (enlaza a su inspección)
function filaElemento(e, sufijo = "") {
    const T = TIPOS[e.tipo] || { icono: "❔", nombre: e.tipo, color: "#999" };
    const datos = resumenDatos(e);
    let extra = e.ultima ? `Última: ${formatoFecha(e.ultima.fecha)}` : "Nunca inspeccionado";
    if (e.fecha_vencimiento) extra += ` · ${T.etiquetaVencimiento || "Vence"}: ${textoVence(e)}`;
    return `<a class="fila-elemento" href="inspeccionar.html?id=${e.id}${sufijo}">
        ${miniatura(e, T)}
        <div class="fila-info"><strong>${esc(e.codigo)} · ${T.nombre}</strong>${sufijo.includes("lugar") && !e.ubicacion ? "" : `<small>📍 ${sufijo.includes("lugar") ? esc(e.ubicacion) : esc(nombreLugar(e)) + (e.ubicacion ? " – " + esc(e.ubicacion) : "")}</small>`}${datos ? `<small>${esc(datos)}</small>` : ""}<small>${extra}</small></div>
        ${etiquetaEstado(e.estado)}
    </a>`;
}


// Foto del elemento o, si no tiene, su ícono
function miniatura(e, T) {
    T = T || TIPOS[e.tipo] || { icono: "❔", color: "#999" };
    return e.foto_url
        ? `<img class="miniatura" src="${esc(e.foto_url)}" alt="">`
        : `<div class="course-icon" style="background:${colorElemento(e)}">${T.icono}</div>`;
}

// ---------- Fotos ----------
// Reduce la foto (máx. 1280 px) para que suba rápido y ocupe poco espacio
function comprimirFoto(file, max = 1280, calidad = 0.75) {
    return new Promise((resolve, reject) => {
        const img = new Image();
        img.onload = () => {
            const k = Math.min(1, max / Math.max(img.width, img.height));
            const c = document.createElement("canvas");
            c.width = Math.round(img.width * k); c.height = Math.round(img.height * k);
            c.getContext("2d").drawImage(img, 0, 0, c.width, c.height);
            c.toBlob(b => b ? resolve(b) : reject(new Error("No se pudo procesar la foto")), "image/jpeg", calidad);
            URL.revokeObjectURL(img.src);
        };
        img.onerror = () => reject(new Error("El archivo no es una imagen válida"));
        img.src = URL.createObjectURL(file);
    });
}

async function subirFoto(file, carpeta) {
    const blob = await comprimirFoto(file);
    const ruta = `${carpeta}/${Date.now()}-${Math.random().toString(36).slice(2, 8)}.jpg`;
    const { error } = await supa.storage.from("inspecciones").upload(ruta, blob, { contentType: "image/jpeg" });
    if (error) throw error;
    return supa.storage.from("inspecciones").getPublicUrl(ruta).data.publicUrl;
}

// ---------- QR ----------
function urlElemento(id) {
    const base = (typeof URL_PUBLICA === "string" && URL_PUBLICA) ? URL_PUBLICA : location.href.replace(/[^/]*$/, "");
    return base.replace(/\/?$/, "/") + "inspeccionar.html?id=" + id;
}

function urlLugar(id) {
    return urlElemento("").replace(/\?id=$/, "?lugar=" + id);
}

// ¿La última inspección fue hoy?
function inspeccionadoHoy(e) {
    return !!e.ultima && new Date(e.ultima.fecha).toDateString() === new Date().toDateString();
}

function qrSVG(texto) {
    const qr = qrcode(0, "M");
    qr.addData(texto); qr.make();
    return qr.createSvgTag({ cellSize: 4, margin: 2, scalable: true });
}

// Visor de fotos ampliadas
function verFoto(url) {
    let v = document.getElementById("visorFoto");
    if (!v) {
        v = document.createElement("div"); v.id = "visorFoto"; v.className = "visor";
        v.onclick = () => v.classList.remove("abierto");
        document.body.appendChild(v);
    }
    v.innerHTML = `<img src="${esc(url)}" alt="">`;
    v.classList.add("abierto");
}
