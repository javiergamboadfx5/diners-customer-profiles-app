import { token } from "./auth";
import type { ContextoConnect } from "./connect";
import type { EsquemaDestino } from "./customerProfilesMapping";
import type { Hallazgo } from "./mock";

export type EstadoBackend =
  | "subiendo"
  | "validando"
  | "validada"
  | "escribiendo"
  | "completada"
  | "parcial"
  | "rechazada"
  | "fallida"
  | "cancelada";

export interface CargaApi {
  id: string;
  fecha: string;
  usuario: string;
  archivo: string;
  tamanoBytes: number;
  estado: EstadoBackend;
  filasProcesadas: number;
  filasValidas: number;
  filasEscritas: number;
  fallidasEscritura: number;
  filasRechazadas: number;
  advertencias: number;
  error?: string;
}

export class ErrorApi extends Error {
  constructor(
    public status: number,
    mensaje: string
  ) {
    super(mensaje);
  }
}

let base = "/api";
export const configurarApi = (apiBase: string) => {
  base = apiBase.replace(/\/$/, "");
};

// Contexto de Connect para auditoria. No autoriza: la API decide con el token OIDC.
let cabecerasConnect: Record<string, string> = {};
export const configurarContextoConnect = (c: ContextoConnect) => {
  const ascii = (v?: string) => (v ? encodeURIComponent(v) : "");
  cabecerasConnect = Object.fromEntries(
    [
      ["X-Connect-User-Arn", c.arn],
      ["X-Connect-User-Name", ascii(c.nombre)],
      ["X-Connect-Routing-Profile", ascii(c.perfilEnrutamiento?.nombre)]
    ].filter(([, v]) => Boolean(v)) as [string, string][]
  );
};

async function llamar<T>(metodo: string, ruta: string, cuerpo?: unknown): Promise<T> {
  const r = await fetch(`${base}${ruta}`, {
    method: metodo,
    headers: {
      Authorization: `Bearer ${await token()}`,
      ...cabecerasConnect,
      ...(cuerpo !== undefined ? { "Content-Type": "application/json" } : {})
    },
    body: cuerpo !== undefined ? JSON.stringify(cuerpo) : undefined
  });
  const datos = await r.json().catch(() => ({}));
  if (!r.ok) throw new ErrorApi(r.status, datos.mensaje ?? `Error ${r.status}`);
  return datos as T;
}

export const api = {
  listar: () => llamar<{ cargas: CargaApi[] }>("GET", "/cargas"),
  obtener: (id: string) => llamar<{ carga: CargaApi }>("GET", `/cargas/${id}`),
  crear: (archivo: File) =>
    llamar<{ carga: CargaApi; subida: { url: string; fields: Record<string, string> } }>("POST", "/cargas", {
      archivo: archivo.name,
      tamanoBytes: archivo.size
    }),
  confirmar: (id: string) => llamar<{ carga: CargaApi }>("POST", `/cargas/${id}/confirmar`),
  cancelar: (id: string) => llamar<{ carga: CargaApi }>("POST", `/cargas/${id}/cancelar`),
  urlReporte: (id: string) => llamar<{ url: string }>("GET", `/cargas/${id}/reporte`),
  esquema: () => llamar<{ esquema: EsquemaDestino }>("GET", "/esquema"),
  publicarEsquema: (esquema: EsquemaDestino) => llamar<{ esquema: EsquemaDestino }>("PUT", "/esquema", { esquema }),

  async hallazgos(id: string): Promise<{ total: number; hallazgos: Hallazgo[] }> {
    const { url } = await llamar<{ url: string }>("GET", `/cargas/${id}/hallazgos`);
    const r = await fetch(url);
    if (!r.ok) throw new ErrorApi(r.status, "No se pudo leer el detalle de hallazgos.");
    return r.json();
  },

  /** POST prefirmado directo a S3: el archivo no pasa por la API. */
  async subir(subida: { url: string; fields: Record<string, string> }, archivo: File) {
    const form = new FormData();
    Object.entries(subida.fields).forEach(([k, v]) => form.append(k, v));
    form.append("file", archivo);
    const r = await fetch(subida.url, { method: "POST", body: form });
    if (!r.ok) throw new ErrorApi(r.status, "No se pudo subir el archivo.");
  }
};
