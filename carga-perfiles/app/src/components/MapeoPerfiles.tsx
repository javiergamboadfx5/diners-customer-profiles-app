import { useEffect, useMemo, useState } from "react";
import Alert from "@cloudscape-design/components/alert";
import Box from "@cloudscape-design/components/box";
import Button from "@cloudscape-design/components/button";
import ButtonDropdown from "@cloudscape-design/components/button-dropdown";
import Checkbox from "@cloudscape-design/components/checkbox";
import ColumnLayout from "@cloudscape-design/components/column-layout";
import Container from "@cloudscape-design/components/container";
import ExpandableSection from "@cloudscape-design/components/expandable-section";
import FormField from "@cloudscape-design/components/form-field";
import Header from "@cloudscape-design/components/header";
import Input from "@cloudscape-design/components/input";
import KeyValuePairs from "@cloudscape-design/components/key-value-pairs";
import Modal from "@cloudscape-design/components/modal";
import Select from "@cloudscape-design/components/select";
import SpaceBetween from "@cloudscape-design/components/space-between";
import StatusIndicator from "@cloudscape-design/components/status-indicator";
import Table from "@cloudscape-design/components/table";
import Textarea from "@cloudscape-design/components/textarea";
import {
  CAMPOS_DESTINO,
  EsquemaDestino,
  IdentificadorCampo,
  MapeoDetectado,
  TIPOS_CONTENIDO,
  PREFIJO_PERSONALIZADO,
  TipoContenido,
  buscarDestino,
  esDestinoPersonalizado,
  generarObjectType,
  inferirMapeo,
  normalizarCampo,
  validarConfiguracionMapeo,
  validarNombreAtributo
} from "../customerProfilesMapping";

const NUEVO_DESTINO = "__nuevo__";

type AccionProtegida = "edit" | "delete" | "discard" | null;

interface Props {
  esquema: EsquemaDestino;
  onSave: (esquema: EsquemaDestino) => void;
}

const opcionesDestino = ["Atributos estándar", "Atributos personalizados"].map((categoria) => ({
  label: categoria,
  options: CAMPOS_DESTINO.filter((campo) => campo.category === categoria).map((campo) => ({
    value: campo.id,
    label: campo.label,
    description: campo.target,
    filteringTags: campo.aliases as string[]
  }))
}));

const etiquetasTipo: Record<TipoContenido, string> = {
  STRING: "Texto",
  NUMBER: "Número",
  PHONE_NUMBER: "Teléfono",
  EMAIL_ADDRESS: "Correo electrónico",
  NAME: "Nombre"
};

const opcionesTipo = TIPOS_CONTENIDO.map((tipo) => ({
  value: tipo,
  label: etiquetasTipo[tipo],
  description: tipo
}));

const datosIdentificador: Record<IdentificadorCampo, { label: string; token?: string; description: string }> = {
  NONE: { label: "Sin identificador", description: "Este campo no participa en la búsqueda del perfil." },
  PROFILE_UNIQUE: {
    label: "Identificador principal",
    token: "PROFILE + UNIQUE",
    description: "Encuentra un único perfil y evita duplicados. Solo puede existir uno."
  },
  PROFILE: {
    label: "Identificador de perfil",
    token: "PROFILE",
    description: "Vincula el objeto con un perfil existente."
  },
  PROFILE_SECONDARY: {
    label: "Identificador secundario",
    token: "PROFILE + SECONDARY",
    description: "Se intenta después de los otros identificadores de perfil."
  },
  PROFILE_LOOKUP_ONLY: {
    label: "Solo para coincidencia",
    token: "PROFILE + LOOKUP_ONLY",
    description: "Se usa al importar, pero no queda disponible para búsquedas posteriores."
  },
  PROFILE_NEW_ONLY: {
    label: "Solo para perfiles nuevos",
    token: "PROFILE + NEW_ONLY",
    description: "Solo se aplica cuando todavía no existe un perfil."
  }
};

const opcionesIdentificador = (
  Object.entries(datosIdentificador) as [IdentificadorCampo, (typeof datosIdentificador)[IdentificadorCampo]][]
).map(([value, dato]) => ({
  value,
  label: dato.label,
  description: dato.token ? `${dato.description} · ${dato.token}` : dato.description
}));

function obtenerDestino(destinationId: string | null, contentType?: TipoContenido) {
  return buscarDestino(destinationId, contentType);
}

/** Opciones del selector: las fijas, los personalizados que ya usa el borrador y "nuevo atributo". */
function construirOpcionesDestino(mapeo: readonly MapeoDetectado[]) {
  const personalizados = [
    ...new Set(mapeo.map((fila) => fila.destinationId).filter((id): id is string => esDestinoPersonalizado(id)))
  ].map((id) => {
    const destino = buscarDestino(id)!;
    return { value: id, label: destino.label, description: destino.target, filteringTags: [] as string[] };
  });
  return [
    opcionesDestino[0],
    { ...opcionesDestino[1], options: [...opcionesDestino[1].options, ...personalizados] },
    {
      label: "Crear",
      options: [
        {
          value: NUEVO_DESTINO,
          label: "Nuevo atributo personalizado…",
          description: "_profile.Attributes.<Nombre>",
          filteringTags: ["nuevo", "crear", "personalizado"]
        }
      ]
    }
  ];
}

function filaVacia(): MapeoDetectado {
  return {
    rowId: `nuevo-${Date.now()}`,
    sourceColumn: "",
    destinationId: null,
    contentType: "STRING",
    confidence: "unmapped",
    required: false,
    identifier: "NONE",
    validation: ""
  };
}

function obtenerMapeo(esquema: EsquemaDestino) {
  return inferirMapeo(
    esquema.fields.map((campo) => campo.sourceColumn),
    esquema
  );
}

function datosComparables(fila: MapeoDetectado) {
  const { rowId: _rowId, confidence: _confidence, ...datos } = fila;
  return datos;
}

/**
 * Efecto de un cambio sobre los perfiles que ya estan en Customer Profiles.
 * Las cargas actualizan y agregan, pero no borran: lo anterior queda hasta recargar o expirar.
 */
function impactoEnPerfiles(actual: MapeoDetectado, anterior: MapeoDetectado): string[] {
  const impactos: string[] = [];
  if (actual.destinationId !== anterior.destinationId) {
    const antes = obtenerDestino(anterior.destinationId)?.label ?? "sin destino";
    const despues = obtenerDestino(actual.destinationId)?.label ?? "sin destino";
    impactos.push(
      `${actual.sourceColumn}: los perfiles existentes conservan el valor anterior en ${antes}. Las próximas cargas escribirán en ${despues}; recarga la base completa para que todos los socios queden igual.`
    );
  }
  if (anterior.required && !actual.required) {
    impactos.push(
      `${actual.sourceColumn}: deja de ser obligatoria. Si una fila llega vacía, el perfil conserva el valor que tenía, aunque esté desactualizado.`
    );
  }
  if (actual.identifier !== anterior.identifier) {
    impactos.push(
      `${actual.sourceColumn}: las claves de búsqueda de Customer Profiles las define Terraform. Este cambio no modifica cómo el agente encuentra a los socios.`
    );
  }
  return impactos;
}

function describirCambios(actual: MapeoDetectado, anterior: MapeoDetectado) {
  const cambios: string[] = [];
  if (actual.sourceColumn !== anterior.sourceColumn) cambios.push("columna");
  if (actual.destinationId !== anterior.destinationId) cambios.push("destino");
  if (actual.contentType !== anterior.contentType) cambios.push("tipo");
  if (actual.required !== anterior.required) cambios.push("obligatoriedad");
  if (actual.validation !== anterior.validation) cambios.push("validación");
  if (actual.identifier !== anterior.identifier) cambios.push("identificador");
  return cambios.join(", ");
}

export default function MapeoPerfiles({ esquema, onSave }: Props) {
  const [inicial] = useState(() => obtenerMapeo(esquema));
  const [baseMapeo, setBaseMapeo] = useState<MapeoDetectado[]>(inicial);
  const [mapeo, setMapeo] = useState<MapeoDetectado[]>(inicial);
  const [administrando, setAdministrando] = useState(false);
  const [editando, setEditando] = useState(false);
  const [filaEditada, setFilaEditada] = useState<MapeoDetectado | null>(null);
  const [accion, setAccion] = useState<AccionProtegida>(null);
  const [confirmado, setConfirmado] = useState(false);
  const [revisando, setRevisando] = useState(false);
  const [aceptaImpacto, setAceptaImpacto] = useState(false);
  const [eliminado, setEliminado] = useState(false);
  const [guardado, setGuardado] = useState(false);
  const [mostrarTecnico, setMostrarTecnico] = useState(false);

  const errores = validarConfiguracionMapeo(esquema, mapeo);
  const principal = mapeo.find((fila) => fila.identifier === "PROFILE_UNIQUE");
  const definicion = useMemo(() => generarObjectType(esquema, mapeo), [esquema, mapeo]);
  const cambios = mapeo
    .map((fila) => ({ fila, anterior: baseMapeo.find((base) => base.rowId === fila.rowId) }))
    .filter((item): item is { fila: MapeoDetectado; anterior: MapeoDetectado } =>
      Boolean(
        item.anterior &&
          JSON.stringify(datosComparables(item.fila)) !== JSON.stringify(datosComparables(item.anterior!))
      )
    );
  const agregados = mapeo.filter((fila) => !baseMapeo.some((base) => base.rowId === fila.rowId));
  const eliminados = baseMapeo.filter((base) => !mapeo.some((fila) => fila.rowId === base.rowId));
  const totalCambios = cambios.length + agregados.length + eliminados.length;
  const impactos = [
    ...cambios.flatMap(({ fila, anterior }) => impactoEnPerfiles(fila, anterior)),
    ...agregados
      .filter((fila) => esDestinoPersonalizado(fila.destinationId))
      .map(
        (fila) =>
          `${fila.sourceColumn}: se creará ${obtenerDestino(fila.destinationId)?.target} en Customer Profiles. Los perfiles existentes no lo tendrán hasta la próxima carga.`
      ),
    ...eliminados.map(
      (fila) =>
        `${fila.sourceColumn}: deja de cargarse. Los perfiles existentes conservan el valor en ${obtenerDestino(fila.destinationId, fila.contentType)?.label ?? "su destino"}, y el campo sigue en Customer Profiles.`
    )
  ];
  const resumenCambios = [
    ...agregados.map((fila) => ({ id: fila.rowId, atributo: fila.sourceColumn, cambio: "Agregado" })),
    ...eliminados.map((fila) => ({ id: fila.rowId, atributo: fila.sourceColumn, cambio: "Eliminado" })),
    ...cambios.map(({ fila, anterior }) => ({
      id: fila.rowId,
      atributo: fila.sourceColumn,
      cambio: describirCambios(fila, anterior)
    }))
  ];
  const opcionesDestinoBorrador = useMemo(() => construirOpcionesDestino(mapeo), [mapeo]);
  const [creandoDestino, setCreandoDestino] = useState(false);
  const [nombreNuevo, setNombreNuevo] = useState("");
  const errorNombreNuevo =
    creandoDestino && filaEditada
      ? validarNombreAtributo(
          nombreNuevo,
          mapeo.filter((fila) => fila.rowId !== filaEditada.rowId).map((fila) => fila.destinationId)
        )
      : undefined;
  const esNuevaFila = Boolean(filaEditada && !mapeo.some((fila) => fila.rowId === filaEditada.rowId));

  const abrirFila = (fila: MapeoDetectado) => {
    setCreandoDestino(false);
    setNombreNuevo("");
    setFilaEditada({ ...fila });
  };

  const eliminarFila = (rowId: string) => setMapeo((actual) => actual.filter((fila) => fila.rowId !== rowId));

  useEffect(() => {
    if (!editando || totalCambios === 0) return;
    const prevenirSalida = (evento: BeforeUnloadEvent) => {
      evento.preventDefault();
      evento.returnValue = "";
    };
    window.addEventListener("beforeunload", prevenirSalida);
    return () => window.removeEventListener("beforeunload", prevenirSalida);
  }, [editando, totalCambios]);

  const cerrarAccion = () => {
    setAccion(null);
    setConfirmado(false);
  };

  const confirmarAccion = () => {
    if (accion === "edit") {
      setEditando(true);
      setAdministrando(true);
      setGuardado(false);
    } else if (accion === "delete") {
      setEliminado(true);
      setEditando(false);
    } else if (accion === "discard") {
      setMapeo(baseMapeo.map((fila) => ({ ...fila })));
      setEditando(false);
      setFilaEditada(null);
    }
    cerrarAccion();
  };

  const guardarFila = () => {
    if (!filaEditada) return;
    const final: MapeoDetectado = creandoDestino
      ? { ...filaEditada, destinationId: `${PREFIJO_PERSONALIZADO}${nombreNuevo}` }
      : filaEditada;
    setMapeo((actual) => {
      const ajustado = actual.map((fila) => {
        if (fila.rowId === final.rowId) return final;
        if (final.identifier === "PROFILE_UNIQUE" && fila.identifier === "PROFILE_UNIQUE") {
          return { ...fila, identifier: "NONE" as const };
        }
        return fila;
      });
      return ajustado.some((fila) => fila.rowId === final.rowId) ? ajustado : [...ajustado, final];
    });
    setCreandoDestino(false);
    setNombreNuevo("");
    setFilaEditada(null);
  };

  const publicar = () => {
    const siguiente: EsquemaDestino = {
      ...esquema,
      version: esquema.version + 1,
      updatedAt: new Date().toISOString(),
      fields: mapeo.map((fila) => ({
        sourceColumn: fila.sourceColumn,
        destinationId: fila.destinationId!,
        contentType: fila.contentType,
        required: fila.required,
        identifier: fila.identifier,
        validation: fila.validation
      }))
    };
    const publicado = obtenerMapeo(siguiente);
    setMapeo(publicado);
    setBaseMapeo(publicado);
    onSave(siguiente);
    setRevisando(false);
    setEditando(false);
    setGuardado(true);
  };

  const descargarDefinicion = () => {
    const contenido = JSON.stringify(definicion, null, 2);
    const url = URL.createObjectURL(new Blob([contenido], { type: "application/json" }));
    const enlace = document.createElement("a");
    enlace.href = url;
    enlace.download = "diners-socios-object-type-mapping.json";
    enlace.click();
    URL.revokeObjectURL(url);
  };

  const filaInvalida = filaEditada
    ? !/^[a-zA-Z0-9_.-]{1,64}$/.test(filaEditada.sourceColumn) ||
      mapeo.some(
        (fila) =>
          fila.rowId !== filaEditada.rowId &&
          normalizarCampo(fila.sourceColumn) === normalizarCampo(filaEditada.sourceColumn)
      ) ||
      (creandoDestino ? Boolean(errorNombreNuevo) : !filaEditada.destinationId)
    : false;

  if (eliminado) {
    return (
      <Container header={<Header variant="h2">Esquema de destino</Header>}>
        <Alert
          type="warning"
          header="El esquema se eliminó en este prototipo"
          action={<Button onClick={() => setEliminado(false)}>Restaurar esquema</Button>}
        >
          En producción, esta acción requiere autorización del backend y queda registrada en auditoría.
        </Alert>
      </Container>
    );
  }

  return (
    <>
      <Container
        header={
          <Header
            variant="h2"
            description="Configuración publicada que se aplicará automáticamente a las próximas cargas."
            actions={
              <SpaceBetween direction="horizontal" size="xs">
                <Button onClick={() => setAdministrando((valor) => !valor)}>
                  {administrando ? "Ocultar administración" : "Administrar esquema"}
                </Button>
                <Button iconName="download" onClick={descargarDefinicion}>
                  Descargar JSON
                </Button>
              </SpaceBetween>
            }
          >
            Esquema de destino
          </Header>
        }
      >
        <SpaceBetween size="m">
          {guardado && (
            <Alert type="success" dismissible onDismiss={() => setGuardado(false)}>
              Versión {esquema.version} publicada. Las próximas cargas usarán esta configuración.
            </Alert>
          )}

          <KeyValuePairs
            columns={4}
            items={[
              { label: "Esquema publicado", value: esquema.name },
              { label: "Versión", value: `v${esquema.version}` },
              {
                label: "Identificador principal",
                value: principal ? (
                  `${principal.sourceColumn} → ${obtenerDestino(principal.destinationId)?.label ?? "Sin destino"}`
                ) : (
                  <StatusIndicator type="warning">No definido</StatusIndicator>
                )
              },
              {
                label: "Estado",
                value: (
                  <StatusIndicator type={editando ? "in-progress" : "success"}>
                    {editando ? "Borrador en edición" : "Publicado"}
                  </StatusIndicator>
                )
              }
            ]}
          />

          {administrando && (
            <SpaceBetween size="m">
              {editando && (
                <Alert
                  type={errores.length ? "warning" : "info"}
                  header={
                    errores.length
                      ? "El borrador necesita atención"
                      : totalCambios
                        ? "Borrador listo para revisar"
                        : "Borrador sin cambios"
                  }
                >
                  {errores.length
                    ? errores.join(" ")
                    : totalCambios
                      ? "Los cambios no afectarán las cargas hasta que publiques una nueva versión."
                      : "Abre un atributo para editarlo. La versión publicada continuará activa hasta que revises y publiques cambios."}
                </Alert>
              )}

              <Table<MapeoDetectado>
                items={mapeo}
                variant="embedded"
                wrapLines
                trackBy="rowId"
                header={
                  <Header
                    variant="h3"
                    counter={`(${mapeo.length})`}
                    description={
                      editando
                        ? "Abre un atributo para modificarlo. Solo una fila se edita a la vez."
                        : "Vista resumida de los atributos publicados."
                    }
                    actions={
                      editando ? (
                        <SpaceBetween direction="horizontal" size="xs">
                          <Button
                            variant="primary"
                            disabled={errores.length > 0 || totalCambios === 0}
                            onClick={() => {
                              setAceptaImpacto(false);
                              setRevisando(true);
                            }}
                          >
                            Revisar{" "}
                            {totalCambios ? `${totalCambios} ${totalCambios === 1 ? "cambio" : "cambios"}` : "cambios"}
                          </Button>
                          <Button iconName="add-plus" onClick={() => abrirFila(filaVacia())}>
                            Agregar atributo
                          </Button>
                          <Button onClick={() => (totalCambios ? setAccion("discard") : setEditando(false))}>
                            Descartar borrador
                          </Button>
                        </SpaceBetween>
                      ) : (
                        <SpaceBetween direction="horizontal" size="xs">
                          <Button variant="primary" onClick={() => setAccion("edit")}>
                            Editar esquema
                          </Button>
                          <ButtonDropdown
                            items={[{ id: "delete", text: "Eliminar esquema" }]}
                            onItemClick={({ detail }) => detail.id === "delete" && setAccion("delete")}
                          >
                            Más acciones
                          </ButtonDropdown>
                        </SpaceBetween>
                      )
                    }
                  >
                    Atributos
                  </Header>
                }
                columnDefinitions={[
                  {
                    id: "source",
                    header: "Columna de origen",
                    minWidth: 180,
                    cell: (fila) => (
                      <SpaceBetween size="xxs">
                        <Box variant="code">{fila.sourceColumn}</Box>
                        <Box variant="small" color="text-body-secondary">
                          {fila.required ? "Obligatoria" : "Opcional"}
                        </Box>
                      </SpaceBetween>
                    )
                  },
                  {
                    id: "target",
                    header: "Destino",
                    minWidth: 250,
                    cell: (fila) => {
                      const destino = obtenerDestino(fila.destinationId, fila.contentType);
                      return destino ? (
                        <SpaceBetween size="xxs">
                          <strong>{destino.label}</strong>
                          <Box variant="small" color="text-body-secondary">
                            {destino.target}
                          </Box>
                        </SpaceBetween>
                      ) : (
                        <StatusIndicator type="warning">Sin destino</StatusIndicator>
                      );
                    }
                  },
                  {
                    id: "type",
                    header: "Tipo",
                    minWidth: 145,
                    cell: (fila) => (
                      <SpaceBetween size="xxs">
                        <span>{etiquetasTipo[fila.contentType]}</span>
                        <Box variant="small" color="text-body-secondary">
                          {fila.contentType}
                        </Box>
                      </SpaceBetween>
                    )
                  },
                  {
                    id: "identifier",
                    header: "Identificador",
                    minWidth: 210,
                    cell: (fila) => {
                      const dato = datosIdentificador[fila.identifier];
                      return (
                        <SpaceBetween size="xxs">
                          {fila.identifier === "PROFILE_UNIQUE" ? (
                            <StatusIndicator type="success">{dato.label}</StatusIndicator>
                          ) : (
                            <span>{dato.label}</span>
                          )}
                          {dato.token && (
                            <Box variant="small" color="text-body-secondary">
                              {dato.token}
                            </Box>
                          )}
                        </SpaceBetween>
                      );
                    }
                  },
                  {
                    id: "action",
                    header: "Acción",
                    minWidth: 150,
                    cell: (fila) =>
                      editando ? (
                        <SpaceBetween direction="horizontal" size="xs">
                          <Button variant="inline-link" onClick={() => abrirFila(fila)}>
                            Editar
                          </Button>
                          {fila.identifier === "PROFILE_UNIQUE" ? (
                            <Box variant="small" color="text-body-secondary">
                              No se puede eliminar
                            </Box>
                          ) : (
                            <Button
                              variant="inline-link"
                              ariaLabel={`Eliminar ${fila.sourceColumn}`}
                              onClick={() => eliminarFila(fila.rowId)}
                            >
                              Eliminar
                            </Button>
                          )}
                        </SpaceBetween>
                      ) : (
                        <Button variant="inline-link" onClick={() => abrirFila(fila)}>
                          Ver
                        </Button>
                      )
                  }
                ]}
              />

              <ExpandableSection headerText="Ayuda sobre identificadores">
                <ColumnLayout columns={2} variant="text-grid">
                  {(
                    Object.entries(datosIdentificador) as [
                      IdentificadorCampo,
                      (typeof datosIdentificador)[IdentificadorCampo]
                    ][]
                  )
                    .filter(([id]) => id !== "NONE")
                    .map(([id, dato]) => (
                      <Box key={id}>
                        <strong>{dato.label}</strong>
                        <br />
                        <Box variant="small" color="text-body-secondary">
                          {dato.description} {dato.token && `(${dato.token})`}
                        </Box>
                      </Box>
                    ))}
                </ColumnLayout>
              </ExpandableSection>

              <ExpandableSection
                headerText="Ver definición técnica"
                expanded={mostrarTecnico}
                onChange={({ detail }) => setMostrarTecnico(detail.expanded)}
              >
                <Textarea
                  value={JSON.stringify(definicion, null, 2)}
                  readOnly
                  rows={18}
                  ariaLabel="Definición JSON del esquema"
                />
              </ExpandableSection>
            </SpaceBetween>
          )}
        </SpaceBetween>
      </Container>

      <Modal
        visible={Boolean(filaEditada)}
        onDismiss={() => setFilaEditada(null)}
        closeAriaLabel="Cerrar detalle del atributo"
        size="large"
        header={
          editando
            ? esNuevaFila
              ? "Agregar atributo"
              : `Editar ${filaEditada?.sourceColumn ?? "atributo"}`
            : `Detalle de ${filaEditada?.sourceColumn ?? "atributo"}`
        }
        footer={
          editando ? (
            <Box float="right">
              <SpaceBetween direction="horizontal" size="xs">
                <Button variant="link" onClick={() => setFilaEditada(null)}>
                  Cancelar
                </Button>
                <Button variant="primary" disabled={filaInvalida} onClick={guardarFila}>
                  Aplicar al borrador
                </Button>
              </SpaceBetween>
            </Box>
          ) : undefined
        }
      >
        {filaEditada &&
          (editando ? (
            <SpaceBetween size="l">
              <ColumnLayout columns={2} borders="vertical">
                <SpaceBetween size="m">
                  <FormField
                    label="Columna de origen"
                    description="Debe coincidir con el encabezado del archivo."
                    constraintText="Letras, números, punto, guion o guion bajo; máximo 64 caracteres."
                    errorText={
                      !/^[a-zA-Z0-9_.-]{1,64}$/.test(filaEditada.sourceColumn)
                        ? "Usa un nombre válido de hasta 64 caracteres."
                        : mapeo.some(
                              (fila) =>
                                fila.rowId !== filaEditada.rowId &&
                                normalizarCampo(fila.sourceColumn) === normalizarCampo(filaEditada.sourceColumn)
                            )
                          ? "Ya existe otra columna con este nombre."
                          : undefined
                    }
                  >
                    <Input
                      value={filaEditada.sourceColumn}
                      onChange={({ detail }) => setFilaEditada({ ...filaEditada, sourceColumn: detail.value })}
                    />
                  </FormField>
                  <FormField
                    label="Destino"
                    description="Atributo que recibirá el valor en Customer Profiles"
                    errorText={!creandoDestino && !filaEditada.destinationId ? "Selecciona un destino." : undefined}
                  >
                    <Select
                      expandToViewport
                      selectedOption={
                        opcionesDestinoBorrador
                          .flatMap((grupo) => grupo.options)
                          .find(
                            (opcion) => opcion.value === (creandoDestino ? NUEVO_DESTINO : filaEditada.destinationId)
                          ) ?? null
                      }
                      onChange={({ detail }) => {
                        const destinationId = detail.selectedOption.value ?? null;
                        if (destinationId === NUEVO_DESTINO) {
                          setCreandoDestino(true);
                          setFilaEditada({ ...filaEditada, destinationId: null, contentType: "STRING" });
                          return;
                        }
                        setCreandoDestino(false);
                        const destino = obtenerDestino(destinationId);
                        setFilaEditada({
                          ...filaEditada,
                          destinationId,
                          contentType: esDestinoPersonalizado(destinationId)
                            ? filaEditada.contentType
                            : (destino?.contentType ?? filaEditada.contentType)
                        });
                      }}
                      options={opcionesDestinoBorrador}
                      filteringType="auto"
                      filteringPlaceholder="Buscar destino"
                      filteringAriaLabel="Buscar atributo de destino"
                      filteringClearAriaLabel="Limpiar búsqueda"
                      placeholder="Seleccionar destino"
                      noMatch="No hay destinos coincidentes"
                    />
                  </FormField>
                  {creandoDestino && (
                    <FormField
                      label="Nombre del nuevo atributo"
                      description={`Se creará _profile.Attributes.${nombreNuevo || "<Nombre>"} al publicar.`}
                      constraintText="Empieza con mayúscula; solo letras y números. Ejemplo: MontoCuota."
                      errorText={nombreNuevo ? errorNombreNuevo : undefined}
                    >
                      <Input value={nombreNuevo} onChange={({ detail }) => setNombreNuevo(detail.value.trim())} />
                    </FormField>
                  )}
                  <FormField
                    label="Tipo de contenido"
                    description="AWS utiliza este tipo para comparar valores durante las búsquedas."
                  >
                    <Select
                      expandToViewport
                      selectedOption={opcionesTipo.find((opcion) => opcion.value === filaEditada.contentType) ?? null}
                      onChange={({ detail }) =>
                        setFilaEditada({ ...filaEditada, contentType: detail.selectedOption.value as TipoContenido })
                      }
                      options={opcionesTipo}
                    />
                  </FormField>
                </SpaceBetween>
                <SpaceBetween size="m">
                  <FormField
                    label="Identificador"
                    description="Determina cómo este campo encuentra o vincula perfiles."
                  >
                    <Select
                      expandToViewport
                      selectedOption={
                        opcionesIdentificador.find((opcion) => opcion.value === filaEditada.identifier) ?? null
                      }
                      onChange={({ detail }) =>
                        setFilaEditada({
                          ...filaEditada,
                          identifier: detail.selectedOption.value as IdentificadorCampo
                        })
                      }
                      options={opcionesIdentificador}
                    />
                  </FormField>
                  <FormField
                    label="Regla de la aplicación"
                    description="Comentario para explicar cómo validar este dato. No se envía a AWS."
                  >
                    <Textarea
                      value={filaEditada.validation}
                      onChange={({ detail }) => setFilaEditada({ ...filaEditada, validation: detail.value })}
                      placeholder="Ejemplo: 8 dígitos, obligatorio y único"
                      rows={4}
                    />
                  </FormField>
                  <Checkbox
                    checked={filaEditada.required}
                    onChange={({ detail }) => setFilaEditada({ ...filaEditada, required: detail.checked })}
                  >
                    Exigir esta columna en cada archivo
                  </Checkbox>
                  {filaEditada.identifier === "PROFILE_UNIQUE" &&
                    mapeo.some((fila) => fila.rowId !== filaEditada.rowId && fila.identifier === "PROFILE_UNIQUE") && (
                      <Alert type="info">
                        Al aplicar, este atributo reemplazará al identificador principal actual.
                      </Alert>
                    )}
                </SpaceBetween>
              </ColumnLayout>
            </SpaceBetween>
          ) : (
            <KeyValuePairs
              columns={2}
              items={[
                { label: "Columna", value: filaEditada.sourceColumn },
                {
                  label: "Destino",
                  value: obtenerDestino(filaEditada.destinationId, filaEditada.contentType)?.label ?? "Sin destino"
                },
                { label: "Tipo", value: `${etiquetasTipo[filaEditada.contentType]} (${filaEditada.contentType})` },
                { label: "Obligatoria", value: filaEditada.required ? "Sí" : "No" },
                { label: "Identificador", value: datosIdentificador[filaEditada.identifier].label },
                { label: "Validación", value: filaEditada.validation || "Sin regla adicional" }
              ]}
            />
          ))}
      </Modal>

      <Modal
        visible={revisando}
        onDismiss={() => setRevisando(false)}
        closeAriaLabel="Cerrar revisión"
        size="large"
        header={`Revisar versión ${esquema.version + 1}`}
        footer={
          <Box float="right">
            <SpaceBetween direction="horizontal" size="xs">
              <Button variant="link" onClick={() => setRevisando(false)}>
                Volver al borrador
              </Button>
              <Button
                variant="primary"
                disabled={errores.length > 0 || (impactos.length > 0 && !aceptaImpacto)}
                onClick={publicar}
              >
                Publicar nueva versión
              </Button>
            </SpaceBetween>
          </Box>
        }
      >
        <SpaceBetween size="m">
          <Alert type="warning" header="La publicación afectará las próximas cargas">
            Las cargas ya procesadas no se modificarán. Revisa cada cambio antes de publicar.
          </Alert>
          {impactos.length > 0 && (
            <Alert type="error" header="Impacto en los perfiles que ya están en Customer Profiles">
              <SpaceBetween size="s">
                <ul style={{ margin: 0, paddingLeft: 18 }}>
                  {impactos.map((texto) => (
                    <li key={texto}>{texto}</li>
                  ))}
                </ul>
                <Checkbox checked={aceptaImpacto} onChange={({ detail }) => setAceptaImpacto(detail.checked)}>
                  Entiendo que los perfiles existentes no cambian hasta la próxima carga completa.
                </Checkbox>
              </SpaceBetween>
            </Alert>
          )}
          <KeyValuePairs
            columns={3}
            items={[
              { label: "Versión actual", value: `v${esquema.version}` },
              { label: "Nueva versión", value: `v${esquema.version + 1}` },
              { label: "Cambios", value: totalCambios.toString() }
            ]}
          />
          <Table
            items={resumenCambios}
            trackBy="id"
            variant="embedded"
            wrapLines
            header={<Header variant="h3">Resumen de cambios</Header>}
            columnDefinitions={[
              { id: "atributo", header: "Atributo", cell: (item) => item.atributo },
              { id: "cambio", header: "Propiedades modificadas", cell: (item) => item.cambio }
            ]}
          />
        </SpaceBetween>
      </Modal>

      <Modal
        visible={Boolean(accion)}
        onDismiss={cerrarAccion}
        closeAriaLabel="Cerrar confirmación"
        header={
          accion === "delete"
            ? "Confirmar eliminación del esquema"
            : accion === "discard"
              ? "Descartar el borrador"
              : "Confirmar edición del esquema"
        }
        footer={
          <Box float="right">
            <SpaceBetween direction="horizontal" size="xs">
              <Button variant="link" onClick={cerrarAccion}>
                Cancelar
              </Button>
              <Button variant="primary" disabled={accion !== "discard" && !confirmado} onClick={confirmarAccion}>
                {accion === "delete"
                  ? "Eliminar esquema"
                  : accion === "discard"
                    ? "Descartar cambios"
                    : "Habilitar edición"}
              </Button>
            </SpaceBetween>
          </Box>
        }
      >
        <SpaceBetween size="m">
          <Alert type={accion === "delete" ? "error" : "warning"}>
            {accion === "delete"
              ? "Eliminar el tipo de objeto puede eliminar también sus objetos asociados. Esta acción debe quedar auditada."
              : accion === "discard"
                ? `Se perderán ${totalCambios} cambios del borrador. La versión publicada continuará activa.`
                : "Los cambios se guardarán primero en un borrador y requerirán una revisión antes de publicarse."}
          </Alert>
          {accion !== "discard" && (
            <Checkbox checked={confirmado} onChange={({ detail }) => setConfirmado(detail.checked)}>
              Revisé el impacto y confirmo que quiero continuar con{" "}
              {accion === "delete" ? "la eliminación" : "la edición"}.
            </Checkbox>
          )}
        </SpaceBetween>
      </Modal>
    </>
  );
}
