import React from "react";
import ReactDOM from "react-dom/client";
import "@cloudscape-design/global-styles/index.css";
import App from "./App";
import { configurarApi } from "./api";
import { iniciarAuth, procesarRetorno } from "./auth";
import { cargarConfig } from "./config";

async function arrancar() {
  const config = await cargarConfig();
  if (config.modo === "api") {
    configurarApi(config.apiBase);
    iniciarAuth(config);
    // Si esta ventana es el popup de login, entrega el resultado al iframe y se cierra.
    if (await procesarRetorno()) return;
  }
  ReactDOM.createRoot(document.getElementById("root") as HTMLElement).render(
    <React.StrictMode>
      <App config={config} />
    </React.StrictMode>
  );
}

void arrancar();
