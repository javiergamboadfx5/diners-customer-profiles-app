// Contexto del usuario de Amazon Connect via SDK de aplicaciones de terceros.
// Solo aplica cuando la app corre embebida en el sitio de Connect.
//
// IMPORTANTE: estos datos los entrega el navegador y no estan firmados. Sirven para segmentar la
// interfaz (que se muestra y a quien), no para autenticar. La API sigue protegida por el token OIDC.

import { AmazonConnectApp } from "@amazon-connect/app";
import { AgentClient } from "@amazon-connect/contact";

export interface ContextoConnect {
  arn?: string;
  nombre?: string;
  perfilEnrutamiento?: { id: string; nombre: string; arn: string };
  /** Datos que no se pudieron leer (normalmente por falta de permisos en el registro de la app). */
  faltantes: string[];
}

const ESPERA_MS = 4000;
let pendiente: Promise<AmazonConnectApp | null> | undefined;

const enIframe = () => {
  try {
    return window.self !== window.top;
  } catch {
    return true;
  }
};

/** Inicializa el SDK una sola vez. Devuelve null si la app no esta dentro de Connect. */
function proveedor(): Promise<AmazonConnectApp | null> {
  if (pendiente) return pendiente;
  if (!enIframe()) return (pendiente = Promise.resolve(null));
  pendiente = new Promise((resolve) => {
    // Fuera de Connect (por ejemplo, otro iframe) el SDK nunca dispara onCreate.
    const espera = window.setTimeout(() => resolve(null), ESPERA_MS);
    try {
      const { provider } = AmazonConnectApp.init({
        onCreate: async () => {
          window.clearTimeout(espera);
          resolve(provider);
        },
        onDestroy: async () => {
          pendiente = undefined;
        }
      });
    } catch {
      window.clearTimeout(espera);
      resolve(null);
    }
  });
  return pendiente;
}

async function leer<T>(nombre: string, faltantes: string[], fn: () => Promise<T>): Promise<T | undefined> {
  try {
    return await fn();
  } catch {
    faltantes.push(nombre);
    return undefined;
  }
}

/** Lee el contexto del usuario de Connect, o null si la app se abrio fuera de Connect. */
export async function obtenerContextoConnect(): Promise<ContextoConnect | null> {
  const app = await proveedor();
  if (!app) return null;
  const agente = new AgentClient(app);
  const faltantes: string[] = [];
  // User.Details.View
  const arn = await leer("ARN del usuario", faltantes, () => agente.getARN());
  const nombre = await leer("nombre del usuario", faltantes, () => agente.getName());
  // User.Configuration.View
  const perfil = await leer("perfil de enrutamiento", faltantes, () => agente.getRoutingProfile());
  return {
    arn,
    nombre,
    perfilEnrutamiento: perfil
      ? { id: perfil.routingProfileId, nombre: perfil.name, arn: perfil.routingProfileARN }
      : undefined,
    faltantes
  };
}

/**
 * Decide si el perfil de enrutamiento puede usar la app.
 * Lista vacia = sin restriccion. Acepta nombre, ID o ARN del perfil.
 */
export function perfilPermitido(contexto: ContextoConnect, permitidos: readonly string[]): boolean {
  if (!permitidos.length) return true;
  const p = contexto.perfilEnrutamiento;
  if (!p) return false;
  const candidatos = [p.id, p.arn, p.nombre.toLowerCase()];
  return permitidos.some((valor) => candidatos.includes(valor) || candidatos.includes(valor.toLowerCase()));
}
