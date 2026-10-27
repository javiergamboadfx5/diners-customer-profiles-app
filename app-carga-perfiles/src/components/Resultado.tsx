import { useMemo, useState } from "react";
import Badge from "@cloudscape-design/components/badge";
import Box from "@cloudscape-design/components/box";
import Button from "@cloudscape-design/components/button";
import Container from "@cloudscape-design/components/container";
import Header from "@cloudscape-design/components/header";
import KeyValuePairs from "@cloudscape-design/components/key-value-pairs";
import Pagination from "@cloudscape-design/components/pagination";
import SpaceBetween from "@cloudscape-design/components/space-between";
import Table from "@cloudscape-design/components/table";
import TextFilter from "@cloudscape-design/components/text-filter";
import { formatearNumero, Hallazgo } from "../mock";
import { ResultadoCarga } from "../useCargaSimulada";
const POR_PAGINA = 20;
export default function Resultado({ resultado }: { resultado: ResultadoCarga }) {
  const [filtro, setFiltro] = useState("");
  const [pagina, setPagina] = useState(1);
  const filtrados = useMemo(() => {
    const q = filtro.trim().toLowerCase();
    if (!q) {
      return resultado.hallazgos;
    }
    return resultado.hallazgos.filter(
      (h) => h.dni.includes(q) || h.motivo.toLowerCase().includes(q) || h.columna.toLowerCase().includes(q)
    );
  }, [filtro, resultado.hallazgos]);
  const pagina1 = Math.min(pagina, Math.max(1, Math.ceil(filtrados.length / POR_PAGINA)));
  const visibles = filtrados.slice((pagina1 - 1) * POR_PAGINA, pagina1 * POR_PAGINA);
  return (
    <SpaceBetween size="l">
      <Container header={<Header variant="h2">Resultado de la carga</Header>}>
        <KeyValuePairs
          columns={4}
          items={[
            {
              label: "Filas procesadas",
              value: formatearNumero(resultado.filasProcesadas)
            },
            {
              label: "Perfiles escritos",
              value: formatearNumero(resultado.filasEscritas)
            },
            {
              label: "Filas rechazadas",
              value: formatearNumero(resultado.filasRechazadas)
            },
            {
              label: "Advertencias",
              value: formatearNumero(resultado.advertencias)
            }
          ]}
        />
      </Container>
      <Table<Hallazgo>
        items={visibles}
        variant="container"
        wrapLines
        trackBy="id"
        header={
          <Header
            variant="h2"
            counter={`(${formatearNumero(filtrados.length)})`}
            description="Una entrada por fila rechazada y por advertencia, con el número de línea del archivo."
            actions={<Button iconName="download">Descargar reporte CSV</Button>}
          >
            Reporte de rechazos y advertencias
          </Header>
        }
        filter={
          <TextFilter
            filteringText={filtro}
            filteringPlaceholder="Buscar por DNI, columna o motivo"
            onChange={({ detail }) => {
              setFiltro(detail.filteringText);
              setPagina(1);
            }}
            countText={`${formatearNumero(filtrados.length)} coincidencias`}
          />
        }
        pagination={
          <Pagination
            currentPageIndex={pagina1}
            pagesCount={Math.max(1, Math.ceil(filtrados.length / POR_PAGINA))}
            onChange={({ detail }) => setPagina(detail.currentPageIndex)}
          />
        }
        empty={
          <Box textAlign="center" padding="m">
            <SpaceBetween size="s">
              <Box variant="strong">Sin coincidencias</Box>
              <Box color="text-body-secondary">Prueba otro término o limpia el filtro.</Box>
              {filtro && (
                <Button
                  onClick={() => {
                    setFiltro("");
                    setPagina(1);
                  }}
                >
                  Limpiar filtro
                </Button>
              )}
            </SpaceBetween>
          </Box>
        }
        columnDefinitions={[
          { id: "linea", header: "Línea", cell: (e) => formatearNumero(e.linea) },
          { id: "dni", header: "DNI recibido", cell: (e) => <Box variant="code">{e.dni}</Box> },
          { id: "columna", header: "Columna", cell: (e) => e.columna },
          {
            id: "tipo",
            header: "Tipo",
            cell: (e) =>
              e.tipo === "rechazo" ? (
                <Badge color="red">Rechazo</Badge>
              ) : (
                <Badge color="severity-medium">Advertencia</Badge>
              )
          },
          { id: "motivo", header: "Motivo", cell: (e) => e.motivo }
        ]}
      />
    </SpaceBetween>
  );
}
