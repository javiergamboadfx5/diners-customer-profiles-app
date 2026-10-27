import { useEffect, useMemo, useState } from "react";
import Alert from "@cloudscape-design/components/alert";
import Box from "@cloudscape-design/components/box";
import Button from "@cloudscape-design/components/button";
import Container from "@cloudscape-design/components/container";
import FileUpload from "@cloudscape-design/components/file-upload";
import Header from "@cloudscape-design/components/header";
import KeyValuePairs from "@cloudscape-design/components/key-value-pairs";
import ProgressBar from "@cloudscape-design/components/progress-bar";
import Select from "@cloudscape-design/components/select";
import SpaceBetween from "@cloudscape-design/components/space-between";
import StatusIndicator from "@cloudscape-design/components/status-indicator";
import Table from "@cloudscape-design/components/table";
import { FaseCarga, ResultadoCarga } from "../useCargaSimulada";
import {
  CAMPOS_DESTINO,
  COLUMNAS_SOCIO,
  EsquemaDestino,
  MapeoDetectado,
  inferirMapeo
} from "../customerProfilesMapping";
interface Props {
  esquema: EsquemaDestino;
  fase: FaseCarga;
  progreso: number;
  archivo: File[];
  resultado?: ResultadoCarga;
  enCurso: boolean;
  onArchivo: (archivos: File[]) => void;
  onIniciar: () => void;
  onConfirmar: () => void;
  onCancelar: () => void;
  onNuevaCarga: () => void;
}
export default function NuevaCarga({
  esquema,
  fase,
  progreso,
  archivo,
  resultado,
  enCurso,
  onArchivo,
  onIniciar,
  onConfirmar,
  onCancelar,
  onNuevaCarga
}: Props) {
  const bloqueado = fase !== "inicial";
  const [mapeo, setMapeo] = useState<MapeoDetectado[]>([]);
  const [analizando, setAnalizando] = useState(false);
  const opcionesDestino = useMemo(
    () =>
      ["Atributos estándar", "Atributos personalizados"].map((categoria) => ({
        label: categoria,
        options: CAMPOS_DESTINO.filter((campo) => campo.category === categoria).map((campo) => ({
          value: campo.id,
          label: campo.label,
          description: campo.target,
          filteringTags: campo.aliases as string[]
        }))
      })),
    []
  );
  useEffect(() => {
    const seleccionado = archivo[0];
    if (!seleccionado) {
      setMapeo([]);
      return;
    }
    let vigente = true;
    setAnalizando(true);
    const detectar = async () => {
      let headers: readonly string[] = COLUMNAS_SOCIO;
      if (seleccionado.name.toLowerCase().endsWith(".csv")) {
        const primeraLinea = (await seleccionado.text()).replace(/^\uFEFF/, "").split(/\r?\n/, 1)[0] ?? "";
        const delimitador = primeraLinea.includes(";") ? ";" : ",";
        const detectados = primeraLinea
          .split(delimitador)
          .map((campo) => campo.trim().replace(/^"|"$/g, ""))
          .filter(Boolean);
        if (detectados.length) headers = detectados;
      }
      if (vigente) {
        setMapeo(inferirMapeo(headers, esquema));
        setAnalizando(false);
      }
    };
    void detectar();
    return () => {
      vigente = false;
    };
  }, [archivo, esquema]);
  const noResueltos = mapeo.filter((fila) => !fila.destinationId).length;
  const resueltos = mapeo.length - noResueltos;
  const actualizarDestino = (sourceColumn: string, destinationId: string | null) => {
    setMapeo((actual) =>
      actual.map((fila) =>
        fila.sourceColumn === sourceColumn
          ? { ...fila, destinationId, confidence: destinationId ? "inferred" : "unmapped" }
          : fila
      )
    );
  };
  return (
    <Container
      header={
        <Header
          variant="h2"
          description={
            fase === "listo"
              ? undefined
              : "Selecciona la base completa. Antes de escribir, validaremos cada fila y mostraremos el resultado."
          }
        >
          Nueva carga
        </Header>
      }
    >
      <SpaceBetween size="m">
        {bloqueado && fase !== "listo" ? (
          <Box>
            Archivo seleccionado: <strong>{archivo[0]?.name}</strong>
          </Box>
        ) : fase === "inicial" ? (
          <FileUpload
            value={archivo}
            onChange={({ detail }) => onArchivo(detail.value)}
            accept=".csv,.xlsx"
            i18nStrings={{
              uploadButtonText: (multiple) => (multiple ? "Seleccionar archivos" : "Seleccionar archivo"),
              dropzoneText: (multiple) => (multiple ? "Arrastra archivos aquí" : "Arrastra el archivo aquí"),
              removeFileAriaLabel: (index) => `Quitar archivo ${index + 1}`,
              limitShowFewer: "Ver menos",
              limitShowMore: "Ver más",
              errorIconAriaLabel: "Error"
            }}
            showFileLastModified
            showFileSize
            constraintText="Formatos admitidos: .csv y .xlsx. Tamaño máximo: 100 MB."
          />
        ) : null}
        {archivo.length > 0 && !bloqueado && (
          <SpaceBetween size="m">
            <Alert
              type={analizando ? "info" : noResueltos ? "warning" : "success"}
              header={
                analizando
                  ? "Detectando esquema y destinos"
                  : noResueltos
                    ? `${noResueltos} columnas necesitan revisión`
                    : `Esquema inferido: ${esquema.name}`
              }
            >
              {analizando
                ? "Estamos comparando los encabezados con los esquemas publicados."
                : `${resueltos} de ${mapeo.length} columnas tienen destino. Revisa la propuesta antes de validar el archivo.`}
            </Alert>
            <KeyValuePairs
              columns={2}
              items={[
                { label: "Esquema aplicado", value: `${esquema.name} · v${esquema.version}` },
                {
                  label: "Identificador principal",
                  value:
                    esquema.fields.find((campo) => campo.identifier === "PROFILE_UNIQUE")?.sourceColumn ?? "No definido"
                }
              ]}
            />
            {!analizando && (
              <Table<MapeoDetectado>
                items={mapeo}
                variant="embedded"
                contentDensity="compact"
                trackBy="sourceColumn"
                header={
                  <Header variant="h3" counter={`(${mapeo.length})`}>
                    Revisar mapeo detectado
                  </Header>
                }
                columnDefinitions={[
                  { id: "source", header: "Origen", cell: (e) => <Box variant="code">{e.sourceColumn}</Box> },
                  {
                    id: "destination",
                    header: "Destino",
                    minWidth: 320,
                    cell: (e) => {
                      const seleccionada =
                        opcionesDestino
                          .flatMap((grupo) => grupo.options)
                          .find((opcion) => opcion.value === e.destinationId) ?? null;
                      return (
                        <Select
                          selectedOption={seleccionada}
                          onChange={({ detail }) =>
                            actualizarDestino(e.sourceColumn, detail.selectedOption.value ?? null)
                          }
                          options={opcionesDestino}
                          filteringType="auto"
                          filteringPlaceholder="Buscar atributo de destino"
                          filteringAriaLabel={`Buscar destino para ${e.sourceColumn}`}
                          filteringClearAriaLabel="Limpiar búsqueda"
                          placeholder="Seleccionar destino"
                          noMatch="No hay atributos coincidentes"
                          selectedAriaLabel="Seleccionado"
                        />
                      );
                    }
                  },
                  {
                    id: "contentType",
                    header: "Tipo de contenido",
                    cell: (e) => CAMPOS_DESTINO.find((campo) => campo.id === e.destinationId)?.contentType ?? "—"
                  },
                  {
                    id: "detection",
                    header: "Detección",
                    cell: (e) =>
                      e.confidence === "exact" ? (
                        <StatusIndicator type="success">Coincidencia exacta</StatusIndicator>
                      ) : e.confidence === "inferred" ? (
                        <StatusIndicator type="info">Inferido</StatusIndicator>
                      ) : (
                        <StatusIndicator type="warning">Revisión necesaria</StatusIndicator>
                      )
                  }
                ]}
              />
            )}
          </SpaceBetween>
        )}
        {fase === "validando" && (
          <ProgressBar
            value={progreso}
            status="in-progress"
            label="Validando columnas y filas"
            description="Todavía no se ha escrito ningún perfil."
          />
        )}
        {fase === "escribiendo" && (
          <ProgressBar
            value={progreso}
            status="in-progress"
            label="Escribiendo perfiles válidos"
            description="Los duplicados se evitan mediante el identificador principal."
          />
        )}
        {fase === "confirmacion" && (
          <SpaceBetween size="m">
            <Alert type="warning" header="Revisa el impacto antes de escribir">
              La validación encontró 391 filas rechazadas y 11.492 advertencias. Todavía no se ha escrito ningún perfil.
            </Alert>
            <KeyValuePairs
              columns={4}
              items={[
                { label: "Archivo", value: archivo[0]?.name ?? "—" },
                { label: "Esquema", value: `${esquema.name} · v${esquema.version}` },
                { label: "Perfiles por escribir", value: "176.474" },
                { label: "Filas rechazadas", value: "391" }
              ]}
            />
          </SpaceBetween>
        )}
        {fase === "listo" && resultado && (
          <Alert type="success" header="Carga completada">
            <strong>{archivo[0]?.name ?? "El archivo"}</strong> terminó de procesarse. Consulta el resultado detallado a
            continuación.
          </Alert>
        )}
        <SpaceBetween direction="horizontal" size="xs">
          {fase === "inicial" && (
            <Button variant="primary" disabled={!archivo.length || analizando || noResueltos > 0} onClick={onIniciar}>
              Validar archivo
            </Button>
          )}
          {fase === "confirmacion" && (
            <Button variant="primary" onClick={onConfirmar}>
              Confirmar y escribir perfiles
            </Button>
          )}
          {(enCurso || fase === "confirmacion") && <Button onClick={onCancelar}>Cancelar carga</Button>}
          {fase === "listo" && (
            <Button variant="primary" onClick={onNuevaCarga}>
              Cargar otro archivo
            </Button>
          )}
        </SpaceBetween>
      </SpaceBetween>
    </Container>
  );
}
