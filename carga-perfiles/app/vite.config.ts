import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    headers: {
      // En produccion esta cabecera la emite CloudFront y restringe el embebido
      // unicamente al sitio de la instancia de Amazon Connect.
      "Content-Security-Policy": "frame-ancestors 'self' https://*.my.connect.aws"
    }
  }
});