// Configuracion en tiempo de ejecucion. Terraform publica /config.json junto al build;
// si no existe (desarrollo local), la app corre en modo simulado.

export interface ConfigApi {
  modo: "api";
  apiBase: string;
  instancia: string;
  ambiente: string;
  oidc: { authority: string; clientId: string; scope: string };
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
