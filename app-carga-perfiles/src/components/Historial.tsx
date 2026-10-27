import Box from "@cloudscape-design/components/box";
import Button from "@cloudscape-design/components/button";
import Header from "@cloudscape-design/components/header";
import StatusIndicator from "@cloudscape-design/components/status-indicator";
import Table from "@cloudscape-design/components/table";
import { Carga, formatearFecha, formatearNumero } from "../mock";
const tipoEstado = (estado: Carga["estado"]) => {
  if (estado === "completada") return "success" as const;
  if (estado === "en_curso") return "in-progress" as const;
  if (estado === "parcial") return "warning" as const;
  if (estado === "cancelada") return "stopped" as const;
  return "error" as const;
};
const etiquetaEstado: Record<Carga["estado"], string> = {
  en_curso: "En curso",
  completada: "Completada",
  parcial: "Parcial",
  rechazada: "Rechazada",
  fallida: "Fallida",
  cancelada: "Cancelada"
};
interface Props {
  cargas: Carga[];
  onDescargar?: (cargaId: string) => void;
}
export default function Historial({ cargas, onDescargar }: Props) {
  return (
    <Table<Carga>
      items={cargas}
      empty={
        <Box textAlign="center" color="text-body-secondary">
          Todavía no hay cargas registradas.
        </Box>
      }
      variant="container"
      wrapLines
      trackBy="id"
      header={
        <Header
          variant="h2"
          counter={`(${cargas.length})`}
          description="Auditoría de cargas, de la más reciente a la más antigua."
        >
          Historial de cargas
        </Header>
      }
      columnDefinitions={[
        { id: "id", header: "Carga", cell: (e) => <Box variant="code">{e.id}</Box> },
        {
          id: "fecha",
          header: "Fecha y responsable",
          cell: (e) => (
            <>
              {formatearFecha(e.fecha)}
              <br />
              <Box variant="small" color="text-body-secondary">
                {e.usuario}
              </Box>
            </>
          )
        },
        { id: "archivo", header: "Archivo", cell: (e) => e.archivo },
        {
          id: "resultado",
          header: "Resultado",
          cell: (e) => (
            <>
              <StatusIndicator type={tipoEstado(e.estado)}>{etiquetaEstado[e.estado]}</StatusIndicator>
              <Box variant="small" color="text-body-secondary">
                {formatearNumero(e.filasEscritas)} escritas · {formatearNumero(e.filasRechazadas)} rechazadas ·{" "}
                {formatearNumero(e.advertencias)} advertencias
              </Box>
            </>
          )
        },
        {
          id: "reporte",
          header: "Reporte",
          cell: (e) =>
            e.estado === "en_curso" || e.estado === "cancelada" ? (
              "—"
            ) : (
              <Button
                variant="inline-link"
                iconName="download"
                disabled={!onDescargar}
                ariaLabel={`Descargar reporte de ${e.id}`}
                onClick={() => onDescargar?.(e.id)}
              >
                CSV
              </Button>
            )
        }
      ]}
    />
  );
}
