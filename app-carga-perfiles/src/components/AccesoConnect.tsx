import Alert from "@cloudscape-design/components/alert";
import Box from "@cloudscape-design/components/box";
import KeyValuePairs from "@cloudscape-design/components/key-value-pairs";
import SpaceBetween from "@cloudscape-design/components/space-between";
import StatusIndicator from "@cloudscape-design/components/status-indicator";
import type { ContextoConnect } from "../connect";

/** Franja con el usuario de Connect detectado por el SDK. */
export function UsuarioConnect({ contexto }: { contexto: ContextoConnect }) {
  return (
    <SpaceBetween size="xs">
      <KeyValuePairs
        columns={3}
        items={[
          { label: "Usuario de Connect", value: contexto.nombre ?? "—" },
          { label: "Perfil de enrutamiento", value: contexto.perfilEnrutamiento?.nombre ?? "—" },
          {
            label: "Acceso",
            value: <StatusIndicator type="success">Permitido por perfil de enrutamiento</StatusIndicator>
          }
        ]}
      />
      {contexto.faltantes.length > 0 && (
        <Alert type="warning" header="Connect no entregó todos los datos del usuario">
          Faltan: {contexto.faltantes.join(", ")}. Revisa que la aplicación tenga los permisos User.Details.View y
          User.Configuration.View en su registro de Connect.
        </Alert>
      )}
    </SpaceBetween>
  );
}

/** Pantalla cuando el perfil de enrutamiento no esta autorizado. */
export function AccesoDenegado({ contexto }: { contexto: ContextoConnect }) {
  const sinPerfil = !contexto.perfilEnrutamiento;
  return (
    <Box padding="xxl">
      <Alert type="error" header="No tienes acceso a la carga de perfiles">
        <SpaceBetween size="s">
          <span>
            {sinPerfil
              ? "Connect no entregó tu perfil de enrutamiento, así que no podemos confirmar tu acceso."
              : `Tu perfil de enrutamiento (${contexto.perfilEnrutamiento!.nombre}) no está habilitado para esta aplicación.`}
          </span>
          <span>
            Si necesitas cargar la base de socios, pide a un administrador de Amazon Connect que te asigne el perfil
            correspondiente.
          </span>
          {contexto.nombre && (
            <Box variant="small" color="text-body-secondary">
              Usuario: {contexto.nombre}
            </Box>
          )}
        </SpaceBetween>
      </Alert>
    </Box>
  );
}
