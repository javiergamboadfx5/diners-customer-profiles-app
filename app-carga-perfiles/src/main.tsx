import React from "react";
import ReactDOM from "react-dom/client";
import "@cloudscape-design/global-styles/index.css";
import App from "./App";
import { configurarApi, configurarContextoConnect } from "./api";
import { iniciarAuth, procesarRetorno } from "./auth";
import { AccesoDenegado } from "./components/AccesoConnect";
import { cargarConfig } from "./config";
import { obtenerContextoConnect, perfilPermitido } from "./connect";

async function arrancar() {
  const config = await cargarConfig();
  if (config.modo === "api") {
    configurarApi(config.apiBase);
    iniciarAuth(config);
    // Si esta ventana es el popup de login, entrega el resultado al iframe y se cierra.
    if (await procesarRetorno()) return;
  }

  // Dentro de Connect: identidad y perfil de enrutamiento via SDK. Fuera de Connect: null.
  const connect = await obtenerContextoConnect();
  const raiz = ReactDOM.createRoot(document.getElementById("root") as HTMLElement);
  const permitidos = config.modo === "api" ? (config.perfilesPermitidos ?? []) : [];

  if (connect && !perfilPermitido(connect, permitidos)) {
    raiz.render(<AccesoDenegado contexto={connect} />);
    return;
  }
  if (connect) configurarContextoConnect(connect);

  raiz.render(
    <React.StrictMode>
      <App config={config} connect={connect} />
    </React.StrictMode>
  );
}

void arrancar();
