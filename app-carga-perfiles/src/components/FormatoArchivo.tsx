import Box from "@cloudscape-design/components/box";
import ExpandableSection from "@cloudscape-design/components/expandable-section";
import Table from "@cloudscape-design/components/table";
import Badge from "@cloudscape-design/components/badge";
import { COLUMNAS_ARCHIVO, ColumnaArchivo } from "../mock";

export default function FormatoArchivo() {
  return (
    <ExpandableSection
      headerText="Formato del archivo"
      headerDescription="Las 10 columnas que debe traer el archivo y la regla que aplica a cada una."
      variant="container"
    >
      <Table<ColumnaArchivo>
        items={COLUMNAS_ARCHIVO}
        variant="embedded"
        contentDensity="compact"
        columnDefinitions={[
          {
            id: "nombre",
            header: "Columna",
            cell: (e) => <Box variant="code">{e.nombre}</Box>
          },
          {
            id: "obligatoria",
            header: "Requerida",
            cell: (e) => (e.obligatoria ? <Badge color="blue">Si</Badge> : <Badge color="grey">Admite vacio</Badge>)
          },
          { id: "regla", header: "Regla de validacion", cell: (e) => e.regla },
          {
            id: "destino",
            header: "Destino en Customer Profiles",
            cell: (e) => e.destino
          }
        ]}
      />
      <Box variant="small" padding={{ top: "s" }}>
        Se admiten archivos .csv y .xlsx. El backend normaliza el delimitador (coma o punto y coma) y la marca de orden
        de bytes que agrega Excel en espanol, asi que no hace falta un procedimiento de exportacion especial.
      </Box>
    </ExpandableSection>
  );
}
