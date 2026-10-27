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
  return "error" as const;
};
export default function Historial({ cargas }: { cargas: Carga[] }) {
  return (
    <Table<Carga>
      items={cargas}
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
              <StatusIndicator type={tipoEstado(e.estado)}>{e.estado}</StatusIndicator>
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
          cell: () => (
            <Button variant="inline-link" iconName="download">
              CSV
            </Button>
          )
        }
      ]}
    />
  );
}
