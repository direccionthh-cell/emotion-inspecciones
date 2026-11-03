/**
 * EMOTION INSPECCIONES — Copia automática en Google Drive
 * ---------------------------------------------------------------
 * Cada inspección guardada en la plataforma se copia aquí:
 *   • Una fila en la hoja "Inspecciones" de esta hoja de cálculo.
 *   • Un PDF con el formato del SIG, en la carpeta de Drive
 *     "Emotion Inspecciones - PDF", organizado por unidad.
 *   • Las fotos, en la carpeta "Emotion Inspecciones - Fotos", por unidad.
 *
 * Instalación: Extensiones → Apps Script → pegar este código → Guardar →
 *   Implementar → Nueva implementación → Tipo: Aplicación web →
 *   Ejecutar como: Yo · Quién tiene acceso: Cualquier persona → Implementar.
 *   Copiar la URL de la aplicación web y enviarla a quien configura la plataforma.
 */

const HOJA = "Inspecciones";
const CARPETA_FOTOS = "Emotion Inspecciones - Fotos";
const CARPETA_PDF = "Emotion Inspecciones - PDF";
const LOGO = "https://direccionthh-cell.github.io/emotion-inspecciones/assets/images/logo-emotion.jpeg";

const ENCABEZADOS = [
  "Fecha", "Unidad / lugar", "Placa", "Código", "Elemento", "Ubicación",
  "Responsable", "Integrante COPASST", "Resultado", "Puntos que no cumplen",
  "Observaciones", "Fechas de revisión", "PDF", "Fotos (Drive)", "Detalle completo"
];

function doPost(e) {
  try {
    const d = JSON.parse(e.postData.contents);
    const hoja = obtenerHoja_();
    const fotos = guardarFotos_(d);          // [{url, blob}]
    const pdf = crearPDF_(d, fotos);
    hoja.appendRow([
      new Date(d.fecha || Date.now()),
      d.lugar || "", d.placa || "", d.codigo || "", d.tipo || "", d.ubicacion || "",
      d.inspector || "", d.copasst || "",
      d.resultado === "conforme" ? "Conforme" : "Con novedades",
      (d.respuestas || []).filter(r => r.respuesta === "No cumple")
        .map(r => r.pregunta + (r.nota ? " (" + r.nota + ")" : "")).join(" | "),
      d.observaciones || "",
      Object.entries(d.datos || {}).map(([k, v]) => k.replace(/_/g, " ") + ": " + v).join(" | "),
      pdf,
      fotos.map(f => f.url).join("\n"),
      (d.respuestas || []).map(r => (r.respuesta === "Cumple" ? "C" : r.respuesta === "No cumple" ? "NC" : "NA") + " · " + r.pregunta).join("\n")
    ]);
    return ContentService.createTextOutput("ok");
  } catch (err) {
    return ContentService.createTextOutput("error: " + err);
  }
}

function obtenerHoja_() {
  const libro = SpreadsheetApp.getActiveSpreadsheet();
  let hoja = libro.getSheetByName(HOJA);
  if (!hoja) {
    hoja = libro.insertSheet(HOJA);
    hoja.appendRow(ENCABEZADOS);
    hoja.getRange(1, 1, 1, ENCABEZADOS.length).setFontWeight("bold").setBackground("#5D2F8A").setFontColor("#FFFFFF");
    hoja.setFrozenRows(1);
  }
  return hoja;
}

// Descarga cada foto desde la plataforma y la guarda en Drive, en una carpeta por unidad
function guardarFotos_(d) {
  const urls = [...(d.fotos || []), ...(d.respuestas || []).map(r => r.foto).filter(Boolean)];
  if (!urls.length) return [];
  const raiz = carpeta_(DriveApp.getRootFolder(), CARPETA_FOTOS);
  const sub = carpeta_(raiz, ((d.lugar || "Sin lugar") + (d.placa ? " - " + d.placa : "")).replace(/[\\/]/g, "-"));
  const fecha = Utilities.formatDate(new Date(d.fecha || Date.now()), "America/Bogota", "yyyy-MM-dd HHmm");
  return urls.map((u, i) => {
    try {
      const blob = UrlFetchApp.fetch(u).getBlob().setName(`${fecha} ${d.codigo || ""} (${i + 1}).jpg`);
      return { url: sub.createFile(blob).getUrl(), blob };
    } catch (e) { return { url: u, blob: null }; }
  });
}

// PDF con el formato del Registro de inspección del SIG
function crearPDF_(d, fotos) {
  try {
    const esc = t => String(t == null ? "" : t).replace(/&/g, "&amp;").replace(/</g, "&lt;");
    const img64 = b => "data:" + b.getContentType() + ";base64," + Utilities.base64Encode(b.getBytes());
    let logo = "";
    try { logo = `<img src="${img64(UrlFetchApp.fetch(LOGO).getBlob())}" style="height:48px">`; } catch (e) {}
    const fecha = Utilities.formatDate(new Date(d.fecha || Date.now()), "America/Bogota", "dd/MM/yyyy hh:mm a");
    const titulo = d.tipo === "Extintor" ? "REGISTRO DE INSPECCIÓN DE EXTINTORES"
      : d.tipo === "Botiquín" ? "REGISTRO DE INSPECCIÓN DE BOTIQUINES Y ELEMENTOS DE EMERGENCIA"
      : "REGISTRO DE INSPECCIÓN – " + String(d.tipo || "").toUpperCase();
    let sec = "", filas = "";
    (d.respuestas || []).forEach(r => {
      if (r.seccion && r.seccion !== sec) { sec = r.seccion; filas += `<tr><th colspan="2" class="s">${esc(sec)}</th></tr>`; }
      const c = r.respuesta === "Cumple" ? "C" : r.respuesta === "No cumple" ? "NC" : "NA";
      const inv = r.requerida ? `<br><small>Requerido: ${r.requerida} · Encontrado: ${esc(r.cantidad)}${r.vence ? " · Vence: " + esc(r.vence) : ""}</small>` : "";
      filas += `<tr><td>${esc(r.pregunta)}${inv}${r.nota ? `<br><small class="nc">${esc(r.nota)}</small>` : ""}</td><td class="r ${c === "NC" ? "nc" : ""}">${c}</td></tr>`;
    });
    const fechas = Object.entries(d.datos || {}).map(([k, v]) => `${esc(k.replace(/_/g, " "))}: <b>${esc(v)}</b>`).join(" · ");
    const imgs = fotos.filter(f => f.blob).map(f => `<img src="${img64(f.blob)}" class="foto">`).join("");
    const html = `<html><head><meta charset="utf-8"><style>
      body{font-family:Arial,sans-serif;font-size:11px;color:#222}
      .enc{display:flex;align-items:center;gap:12px;border:1px solid #999;padding:8px}
      .enc div{flex:1} h1{font-size:13px;margin:0} .sub{color:#666;font-size:10px}
      table{width:100%;border-collapse:collapse;margin-top:10px} td,th{border:1px solid #bbb;padding:5px;vertical-align:top}
      th.s{background:#EDE3F7;color:#5D2F8A;text-align:left;font-size:10px}
      .r{width:40px;text-align:center;font-weight:bold;color:#1f8a3c} .nc{color:#c62828}
      .datos td{border:none;padding:2px 0} .foto{width:160px;margin:4px;border:1px solid #ccc}
      .firmas{display:flex;gap:40px;margin-top:50px} .firmas div{flex:1;border-top:1px solid #333;text-align:center;padding-top:4px}
    </style></head><body>
      <div class="enc">${logo}<div><h1>${titulo}</h1><div class="sub">Sistema Integrado de Gestión (SIG) · E-MOTION GLOBAL S.A.S.</div></div></div>
      <table class="datos">
        <tr><td><b>Fecha de inspección:</b> ${fecha}</td><td><b>Lugar:</b> ${esc(d.lugar)}${d.placa ? " · Placa " + esc(d.placa) : ""}</td></tr>
        <tr><td><b>Elemento:</b> ${esc(d.codigo)} · ${esc(d.tipo)}</td><td><b>Ubicación:</b> ${esc(d.ubicacion)}</td></tr>
        <tr><td><b>Responsable:</b> ${esc(d.inspector)}</td><td><b>Integrante del COPASST:</b> ${esc(d.copasst)}</td></tr>
        ${fechas ? `<tr><td colspan="2">${fechas}</td></tr>` : ""}
        <tr><td colspan="2"><b>Resultado:</b> <span class="${d.resultado === "conforme" ? "" : "nc"}">${d.resultado === "conforme" ? "CONFORME" : "CON NOVEDADES"}</span></td></tr>
      </table>
      <table>${filas}</table>
      <p class="sub">C: Cumple · NC: No cumple · NA: No aplica</p>
      ${d.observaciones ? `<p><b>Observaciones generales:</b> ${esc(d.observaciones)}</p>` : ""}
      ${imgs ? `<p><b>Fotos:</b></p>${imgs}` : ""}
      <div class="firmas"><div>Firma del responsable de la inspección</div><div>Firma del integrante del COPASST</div></div>
    </body></html>`;
    const nombre = Utilities.formatDate(new Date(d.fecha || Date.now()), "America/Bogota", "yyyy-MM-dd HHmm") + " " + (d.codigo || "") + ".pdf";
    const pdf = HtmlService.createHtmlOutput(html).getBlob().getAs("application/pdf").setName(nombre);
    const raiz = carpeta_(DriveApp.getRootFolder(), CARPETA_PDF);
    const sub = carpeta_(raiz, ((d.lugar || "Sin lugar") + (d.placa ? " - " + d.placa : "")).replace(/[\\/]/g, "-"));
    return sub.createFile(pdf).getUrl();
  } catch (e) {
    return "No se pudo crear el PDF: " + e;
  }
}

function carpeta_(padre, nombre) {
  const it = padre.getFoldersByName(nombre);
  return it.hasNext() ? it.next() : padre.createFolder(nombre);
}

// Para probar desde el editor: Ejecutar → probar
function probar() {
  doPost({ postData: { contents: JSON.stringify({
    fecha: new Date().toISOString(), lugar: "PRUEBA", placa: "ABC123", codigo: "EXT-PRUEBA",
    tipo: "Extintor", inspector: "Prueba", resultado: "conforme",
    respuestas: [{ pregunta: "Manómetro", respuesta: "Cumple" }]
  }) } });
}
