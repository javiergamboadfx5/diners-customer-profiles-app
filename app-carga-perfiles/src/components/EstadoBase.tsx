import Container from "@cloudscape-design/components/container";
import ExpandableSection from "@cloudscape-design/components/expandable-section";
import Header from "@cloudscape-design/components/header";
import KeyValuePairs from "@cloudscape-design/components/key-value-pairs";
import StatusIndicator from "@cloudscape-design/components/status-indicator";
import SpaceBetween from "@cloudscape-design/components/space-between";
import { Carga, DOMINIO_PERFILES, formatearFecha, formatearNumero, TOTAL_PERFILES_ACTUALES } from "../mock";
interface Props {
  ultimaCarga: Carga;
  totalPerfiles: number;
}
export default function EstadoBase({ ultimaCarga, totalPerfiles }: Props) {
  return (
    <Container
      header={
        <Header
          variant="h2"
          description="Estado del dominio de Customer Profiles que usa el agente de IA para reconocer al socio."
        >
          Base de socios
        </Header>
      }
    >
      <SpaceBetween size="m">
        <KeyValuePairs
          columns={4}
          items={[
            {
              label: "Perfiles en Customer Profiles",
              value: formatearNumero(totalPerfiles),
              info: totalPerfiles !== TOTAL_PERFILES_ACTUALES ? "Actualizado por la última carga" : undefined
            },
            {
              label: "Última carga",
              value: formatearFecha(ultimaCarga.fecha)
            },
            {
              label: "Ejecutada por",
              value: ultimaCarga.usuario
            },
            {
              label: "Resultado",
              value: (
                <StatusIndicator type={ultimaCarga.estado === "completada" ? "success" : "warning"}>
                  {ultimaCarga.estado === "completada" ? "Completada" : "Parcial"}
                </StatusIndicator>
              )
            }
          ]}
        />
        <ExpandableSection headerText="Ver configuración del dominio">
          <KeyValuePairs
            columns={4}
            items={[
              { label: "Dominio", value: DOMINIO_PERFILES },
              { label: "Clave de búsqueda", value: "DNI → AccountNumber" },
              {
                label: "Resolución de identidad",
                value: <StatusIndicator type="stopped">Desactivada</StatusIndicator>
              },
              { label: "Caducidad del perfil", value: "366 días sin actualizarse" }
            ]}
          />
        </ExpandableSection>
      </SpaceBetween>
    </Container>
  );
}
