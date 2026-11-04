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
import { formatearNumero } from "../mock";
import { FaseCarga, ResultadoCarga } from "../useCargaSimulada";
import Resultado from "./Resultado";
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
  nombreArchivo?: string;
  resultado?: ResultadoCarga;
  enCurso: boolean;
  ocupado?: boolean;
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
  nombreArchivo,
  resultado,
  enCurso,
  ocupado = false,
  onArchivo,
  onIniciar,
  onConfirmar,
  onCancelar,
  onNuevaCarga
}: Props) {
  const bloqueado = fase !== "inicial";
  const nombre = nombreArchivo ?? archivo[0]?.name;
  const n = (valor?: number) => formatearNumero(valor ?? 0);
  const final = resultado?.estado;
  const alertaFinal =
    final === "completada"
      ? { type: "success" as const, header: "Carga completada" }
      : final === "parcial"
        ? { type: "warning" as const, header: "Carga completada con errores de escritura" }
        : final === "rechazada"
          ? { type: "error" as const, header: "El archivo fue rechazado" }
          : final === "cancelada"
            ? { type: "info" as const, header: "Carga cancelada" }
            : { type: "error" as const, header: "La carga falló: no se escribió ningún perfil" };
  // Texto de respaldo si el backend no envió el motivo (cargas antiguas o errores no clasificados).
  const detalleFinal =
    final === "completada"
      ? `Se escribieron ${n(resultado?.filasEscritas)} perfiles. Consulta el resultado detallado a continuación.`
      : final === "parcial"
        ? `Se escribieron ${n(resultado?.filasEscritas)} de ${n(resultado?.filasValidas)} perfiles válidos. Descarga el reporte para ver el detalle.`
        : final === "rechazada"
          ? "Ninguna fila pasó la validación. Revisa el reporte de rechazos."
          : final === "cancelada"
            ? `La carga se detuvo. Se escribieron ${n(resultado?.filasEscritas)} perfiles antes de cancelar; no se deshacen.`
            : `No se escribió ninguno de los ${n(resultado?.filasValidas)} perfiles válidos. Contacta al administrador con el código de carga ${resultado?.id ?? ""}.`;
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
            Archivo seleccionado: <strong>{nombre}</strong>
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
            constraintText="Formatos admitidos: Excel (.xlsx, primera hoja) o CSV (UTF-8, separado por coma o punto y coma). Tamaño máximo: 100 MB."
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
                          expandToViewport
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
              La validación encontró {n(resultado?.filasRechazadas)} filas rechazadas y {n(resultado?.advertencias)}{" "}
              advertencias. Todavía no se ha escrito ningún perfil.
            </Alert>
            <KeyValuePairs
              columns={4}
              items={[
                { label: "Archivo", value: nombre ?? "—" },
                { label: "Esquema", value: `${esquema.name} · v${esquema.version}` },
                { label: "Perfiles por escribir", value: n(resultado?.filasValidas) },
                { label: "Filas rechazadas", value: n(resultado?.filasRechazadas) }
              ]}
            />
            {resultado && resultado.hallazgos.length > 0 && <Resultado resultado={resultado} soloReporte />}
          </SpaceBetween>
        )}
        {fase === "listo" && resultado && (
          <Alert type={alertaFinal.type} header={alertaFinal.header}>
            <SpaceBetween size="xxs">
              <span>
                <strong>{nombre ?? "El archivo"}</strong>
                {resultado.id ? ` · ${resultado.id}` : ""}
              </span>
              <span>{resultado.mensaje || detalleFinal}</span>
            </SpaceBetween>
          </Alert>
        )}
        <SpaceBetween direction="horizontal" size="xs">
          {fase === "inicial" && (
            <Button
              variant="primary"
              loading={ocupado}
              disabled={!archivo.length || analizando || noResueltos > 0}
              onClick={onIniciar}
            >
              Validar archivo
            </Button>
          )}
          {fase === "confirmacion" && (
            <Button variant="primary" loading={ocupado} disabled={!resultado?.filasValidas} onClick={onConfirmar}>
              Confirmar y escribir perfiles
            </Button>
          )}
          {(enCurso || fase === "confirmacion") && (
            <Button disabled={ocupado} onClick={onCancelar}>
              Cancelar carga
            </Button>
          )}
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
