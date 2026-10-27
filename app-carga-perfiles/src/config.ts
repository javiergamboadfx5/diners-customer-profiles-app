// Configuracion en tiempo de ejecucion. Terraform publica /config.json junto al build;
// si no existe (desarrollo local), la app corre en modo simulado.

export interface ConfigApi {
  modo: "api";
  apiBase: string;
  instancia: string;
  ambiente: string;
  oidc: { authority: string; clientId: string; scope: string };
  /** Perfiles de enrutamiento (nombre, ID o ARN) que pueden usar la app dentro de Connect. Vacio = todos. */
  perfilesPermitidos?: string[];
  /** Configuracion del dominio de Customer Profiles, para la tarjeta "Base de socios". */
  dominio?: { nombre: string; diasExpiracion: number };
}

export type ConfigApp = ConfigApi | { modo: "mock" };

export async function cargarConfig(): Promise<ConfigApp> {
  try {
    const r = await fetch("/config.json", { cache: "no-store" });
    if (!r.ok || !(r.headers.get("content-type") ?? "").includes("json")) return { modo: "mock" };
    const config = (await r.json()) as ConfigApp;
    return config.modo === "api" ? config : { modo: "mock" };
  } catch {
    return { modo: "mock" };
  }
}
