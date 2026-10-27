import Alert from "@cloudscape-design/components/alert";
import AppLayout from "@cloudscape-design/components/app-layout";
import Box from "@cloudscape-design/components/box";
import ContentLayout from "@cloudscape-design/components/content-layout";
import Header from "@cloudscape-design/components/header";
import SpaceBetween from "@cloudscape-design/components/space-between";
import EstadoBase from "./components/EstadoBase";
import Historial from "./components/Historial";
import MapeoPerfiles from "./components/MapeoPerfiles";
import NuevaCarga from "./components/NuevaCarga";
import Resultado from "./components/Resultado";
import type { ConfigApp } from "./config";
import { INSTANCIA_CONNECT } from "./mock";
import { useCargaApi } from "./useCargaApi";
import { ControladorCarga, useCargaSimulada } from "./useCargaSimulada";

function Vista({ carga, instancia }: { carga: ControladorCarga; instancia: string }) {
  const ultimaCarga = carga.historial.find((c) => c.estado === "completada" || c.estado === "parcial");
  const totalPerfiles = ultimaCarga?.filasEscritas ?? 0;
  return (
    <AppLayout
      navigationHide
      toolsHide
      maxContentWidth={1400}
      content={
        <ContentLayout
          header={
            <SpaceBetween size="m">
              <Header
                variant="h1"
                description={`Carga y valida la base de socios que utiliza ${instancia}.`}
                info={carga.usuario ? <Box color="text-body-secondary">{carga.usuario}</Box> : undefined}
              >
                Carga de perfiles
              </Header>
              {carga.modo === "mock" && (
                <Alert type="info" header="Entorno de demostración">
                  Este prototipo no escribe en Customer Profiles. Los resultados reproducen la base recibida el 20 de
                  octubre.
                </Alert>
              )}
              {carga.error && (
                <Alert type="error" dismissible onDismiss={carga.limpiarError} header="No se pudo completar la acción">
                  {carga.error}
                </Alert>
              )}
            </SpaceBetween>
          }
        >
          <SpaceBetween size="l">
            <EstadoBase ultimaCarga={ultimaCarga} totalPerfiles={totalPerfiles} />
            <NuevaCarga
              esquema={carga.esquema}
              fase={carga.fase}
              progreso={carga.progreso}
              archivo={carga.archivo}
              nombreArchivo={carga.nombreArchivo}
              resultado={carga.resultado}
              enCurso={carga.enCurso}
              ocupado={carga.ocupado}
              soloCsv={carga.modo === "api"}
              onArchivo={carga.setArchivo}
              onIniciar={carga.iniciar}
              onConfirmar={carga.confirmarEscritura}
              onCancelar={carga.cancelar}
              onNuevaCarga={carga.reiniciar}
            />
            {carga.resultado && carga.fase === "listo" && (
              <Resultado resultado={carga.resultado} onDescargar={carga.descargarReporte} />
            )}
            <MapeoPerfiles key={carga.esquema.version} esquema={carga.esquema} onSave={carga.publicarEsquema} />
            <Historial cargas={carga.historial} onDescargar={carga.descargarReporte} />
            <Box variant="small" color="text-body-secondary" textAlign="center">
              DFX5 para Diners Club Perú. Aplicación de carga de perfiles, región us-east-1.
            </Box>
          </SpaceBetween>
        </ContentLayout>
      }
    />
  );
}

function AppMock() {
  return <Vista carga={useCargaSimulada()} instancia={INSTANCIA_CONNECT} />;
}

function AppApi({ instancia }: { instancia: string }) {
  return <Vista carga={useCargaApi()} instancia={instancia} />;
}

export default function App({ config }: { config: ConfigApp }) {
  return config.modo === "api" ? <AppApi instancia={config.instancia} /> : <AppMock />;
}
