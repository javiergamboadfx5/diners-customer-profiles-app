import Container from "@cloudscape-design/components/container";
import ExpandableSection from "@cloudscape-design/components/expandable-section";
import Header from "@cloudscape-design/components/header";
import KeyValuePairs from "@cloudscape-design/components/key-value-pairs";
import StatusIndicator from "@cloudscape-design/components/status-indicator";
import SpaceBetween from "@cloudscape-design/components/space-between";
import { Carga, DOMINIO_PERFILES, formatearFecha, formatearNumero, TOTAL_PERFILES_ACTUALES } from "../mock";
interface Props {
  ultimaCarga?: Carga;
  totalPerfiles: number;
  dominio?: { nombre: string; diasExpiracion: number };
}
export default function EstadoBase({ ultimaCarga, totalPerfiles, dominio }: Props) {
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
              label: "Perfiles escritos en la última carga",
              value: formatearNumero(totalPerfiles),
              info: totalPerfiles !== TOTAL_PERFILES_ACTUALES ? "Actualizado por la última carga" : undefined
            },
            {
              label: "Última carga",
              value: ultimaCarga ? formatearFecha(ultimaCarga.fecha) : "Sin cargas"
            },
            {
              label: "Ejecutada por",
              value: ultimaCarga?.usuario ?? "—"
            },
            {
              label: "Resultado",
              value: ultimaCarga ? (
                <StatusIndicator type={ultimaCarga.estado === "completada" ? "success" : "warning"}>
                  {ultimaCarga.estado === "completada" ? "Completada" : "Parcial"}
                </StatusIndicator>
              ) : (
                "—"
              )
            }
          ]}
        />
        <ExpandableSection headerText="Ver configuración del dominio">
          <KeyValuePairs
            columns={4}
            items={[
              { label: "Dominio", value: dominio?.nombre ?? DOMINIO_PERFILES },
              { label: "Claves de búsqueda", value: "DNI → AccountNumber · Teléfono → PhoneNumber" },
              {
                label: "Resolución de identidad",
                value: <StatusIndicator type="stopped">Desactivada</StatusIndicator>
              },
              {
                label: "Caducidad del perfil",
                value: `${formatearNumero(dominio?.diasExpiracion ?? 1000)} días sin actualizarse`
              }
            ]}
          />
        </ExpandableSection>
      </SpaceBetween>
    </Container>
  );
}
