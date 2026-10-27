import { useState } from "react";
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
import { INSTANCIA_CONNECT } from "./mock";
import { useCargaSimulada } from "./useCargaSimulada";
import { ESQUEMA_SOCIOS } from "./customerProfilesMapping";
export default function App() {
  const carga = useCargaSimulada();
  const [esquema, setEsquema] = useState(ESQUEMA_SOCIOS);
  const ultimaCarga = carga.historial[0];
  const totalPerfiles = carga.resultado ? carga.resultado.filasEscritas : ultimaCarga.filasEscritas;
  return (
    <AppLayout
      navigationHide
      toolsHide
      maxContentWidth={1400}
      content={
        <ContentLayout
          header={
            <SpaceBetween size="m">
              <Header variant="h1" description={`Carga y valida la base de socios que utiliza ${INSTANCIA_CONNECT}.`}>
                Carga de perfiles
              </Header>
              <Alert type="info" header="Entorno de demostración">
                Este prototipo no escribe en Customer Profiles. Los resultados reproducen la base recibida el 20 de
                octubre.
              </Alert>
            </SpaceBetween>
          }
        >
          <SpaceBetween size="l">
            <EstadoBase ultimaCarga={ultimaCarga} totalPerfiles={totalPerfiles} />
            <NuevaCarga
              esquema={esquema}
              fase={carga.fase}
              progreso={carga.progreso}
              archivo={carga.archivo}
              resultado={carga.resultado}
              enCurso={carga.enCurso}
              onArchivo={carga.setArchivo}
              onIniciar={carga.iniciar}
              onConfirmar={carga.confirmarEscritura}
              onCancelar={carga.cancelar}
              onNuevaCarga={carga.reiniciar}
            />
            {carga.resultado && carga.fase === "listo" && <Resultado resultado={carga.resultado} />}
            <MapeoPerfiles esquema={esquema} onSave={setEsquema} />
            <Historial cargas={carga.historial} />
            <Box variant="small" color="text-body-secondary" textAlign="center">
              DFX5 para Diners Club Perú. Mock de la aplicación de carga de perfiles, región us-east-1.
            </Box>
          </SpaceBetween>
        </ContentLayout>
      }
    />
  );
}
