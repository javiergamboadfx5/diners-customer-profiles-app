// OIDC con PKCE (Entra ID u otro proveedor). Sin client secret.
// Dentro del iframe de Connect el login va en popup: Entra ID no se deja embeber.

import { User, UserManager, WebStorageStateStore } from "oidc-client-ts";
import type { ConfigApi } from "./config";

let gestor: UserManager | undefined;

const enIframe = () => {
  try {
    return window.self !== window.top;
  } catch {
    return true;
  }
};

export function iniciarAuth(config: ConfigApi) {
  gestor = new UserManager({
    authority: config.oidc.authority,
    client_id: config.oidc.clientId,
    redirect_uri: `${window.location.origin}/`,
    popup_redirect_uri: `${window.location.origin}/`,
    post_logout_redirect_uri: `${window.location.origin}/`,
    response_type: "code",
    scope: config.oidc.scope,
    automaticSilentRenew: true,
    // sessionStorage: el token no sobrevive al cierre de la pestaña.
    userStore: new WebStorageStateStore({ store: window.sessionStorage })
  });
  return gestor;
}

/** Procesa el retorno del proveedor. Devuelve true si esta ventana era el popup y debe cerrarse. */
export async function procesarRetorno(): Promise<boolean> {
  if (!gestor) return false;
  const params = new URLSearchParams(window.location.search);
  if (!params.has("code") && !params.has("error")) return false;
  if (window.opener && window.opener !== window) {
    await gestor.signinPopupCallback();
    return true;
  }
  await gestor.signinRedirectCallback();
  window.history.replaceState({}, document.title, "/");
  return false;
}

export async function obtenerUsuario(): Promise<User> {
  if (!gestor) throw new Error("Autenticación no inicializada");
  const actual = await gestor.getUser();
  if (actual && !actual.expired) return actual;
  try {
    const renovado = await gestor.signinSilent();
    if (renovado) return renovado;
  } catch {
    // Sin sesión: se pide login interactivo.
  }
  if (enIframe()) return gestor.signinPopup();
  await gestor.signinRedirect();
  return new Promise<User>(() => undefined); // la página navega al proveedor
}

export async function token(): Promise<string> {
  return (await obtenerUsuario()).access_token;
}

export function nombreUsuario(usuario: User): string {
  const p = usuario.profile;
  return String(p.name ?? p.preferred_username ?? p.email ?? p.sub);
}
