export const COLUMNAS_SOCIO = [
  "DNI",
  "NOMBRE_SOCIO",
  "SEGMENTO_VALOR",
  "MARCA_RETENER",
  "TELEFONO_1",
  "tiene_oferta",
  "tea",
  "fecha_afiliacion",
  "tipo_producto",
  "correo",
  "fecha_nacimiento"
] as const;
export type ColumnaSocio = (typeof COLUMNAS_SOCIO)[number];
export type FilaSocio = Record<ColumnaSocio, string>;
export type TipoContenido = "STRING" | "NUMBER" | "PHONE_NUMBER" | "EMAIL_ADDRESS" | "NAME";
export type IdentificadorCampo =
  | "NONE"
  | "PROFILE_UNIQUE"
  | "PROFILE"
  | "PROFILE_SECONDARY"
  | "PROFILE_LOOKUP_ONLY"
  | "PROFILE_NEW_ONLY";
export const TIPOS_CONTENIDO: readonly TipoContenido[] = ["STRING", "NUMBER", "PHONE_NUMBER", "EMAIL_ADDRESS", "NAME"];
export const REGLAS_VALIDACION: Record<ColumnaSocio, string> = {
  DNI: "8 dígitos; obligatorio y único",
  NOMBRE_SOCIO: "Texto; obligatorio",
  SEGMENTO_VALOR: "1, 2 o 3; vacío genera advertencia",
  MARCA_RETENER: "1 o 2; obligatorio",
  TELEFONO_1: "11 dígitos con prefijo 51; vacío genera advertencia",
  tiene_oferta: "S o N; obligatorio",
  tea: "Decimal entre 0 y 200",
  fecha_afiliacion: "AAAA-MM-DD; no puede ser futura",
  tipo_producto: "Producto permitido por el esquema",
  correo: "Dirección de correo válida",
  fecha_nacimiento: "AAAA-MM-DD; no puede ser futura. Saludo de cumpleaños"
};
export interface ReglaMapeo {
  sourceColumn: ColumnaSocio;
  fieldName: string;
  target: string;
  destination: "Estándar" | "Atributo personalizado";
  contentType: TipoContenido;
  searchKey?: "_account" | "_phone";
  description: string;
}
export const REGLAS_MAPEO: readonly ReglaMapeo[] = [
  {
    sourceColumn: "DNI",
    fieldName: "dni",
    target: "_profile.AccountNumber",
    destination: "Estándar",
    contentType: "STRING",
    searchKey: "_account",
    description: "Identificador único del socio y clave de búsqueda del perfil."
  },
  {
    sourceColumn: "NOMBRE_SOCIO",
    fieldName: "nombreSocio",
    target: "_profile.FirstName",
    destination: "Estándar",
    contentType: "STRING",
    description: "Nombre completo recibido en una sola columna; se conserva sin dividir."
  },
  {
    sourceColumn: "TELEFONO_1",
    fieldName: "telefono",
    target: "_profile.MobilePhoneNumber",
    destination: "Estándar",
    contentType: "PHONE_NUMBER",
    searchKey: "_phone",
    description: "Celular del socio en formato 51 + nueve dígitos. Clave de búsqueda en voz (no única)."
  },
  {
    sourceColumn: "fecha_nacimiento",
    fieldName: "fechaNacimiento",
    target: "_profile.BirthDate",
    destination: "Estándar",
    contentType: "STRING",
    description: "Fecha de nacimiento AAAA-MM-DD para el saludo de cumpleaños."
  },
  {
    sourceColumn: "correo",
    fieldName: "correo",
    target: "_profile.PersonalEmailAddress",
    destination: "Estándar",
    contentType: "EMAIL_ADDRESS",
    description: "Correo personal para confirmaciones y constancias."
  },
  ...(
    [
      ["SEGMENTO_VALOR", "segmentoValor", "SegmentoValor", "STRING", "Segmento 1, 2 o 3 para decisiones de atención."],
      ["MARCA_RETENER", "marcaRetener", "MarcaRetener", "STRING", "Marca 1 o 2 para la ruta de retención."],
      ["tiene_oferta", "tieneOferta", "TieneOferta", "STRING", "Indica si el socio tiene una oferta vigente."],
      ["tea", "tea", "Tea", "NUMBER", "Tasa efectiva anual asociada a la oferta."],
      [
        "fecha_afiliacion",
        "fechaAfiliacion",
        "FechaAfiliacion",
        "STRING",
        "Fecha de afiliación en formato AAAA-MM-DD."
      ],
      ["tipo_producto", "tipoProducto", "TipoProducto", "STRING", "Producto Diners asociado al socio."]
    ] as const
  ).map(([sourceColumn, fieldName, attribute, contentType, description]) => ({
    sourceColumn,
    fieldName,
    target: `_profile.Attributes.${attribute}`,
    destination: "Atributo personalizado" as const,
    contentType,
    description
  }))
] as const;
export const CUSTOMER_PROFILE_OBJECT_TYPE = {
  Fields: Object.fromEntries(
    REGLAS_MAPEO.map((regla) => [
      regla.fieldName,
      {
        Source: `_source.${regla.sourceColumn}`,
        Target: regla.target,
        ContentType: regla.contentType
      }
    ])
  ),
  Keys: {
    _account: [
      {
        StandardIdentifiers: ["PROFILE", "UNIQUE"],
        FieldNames: ["dni"]
      }
    ],
    _phone: [
      {
        StandardIdentifiers: ["PROFILE"],
        FieldNames: ["telefono"]
      }
    ]
  }
} as const;
export interface PerfilTransformado {
  AccountNumber: string;
  FirstName: string;
  MobilePhoneNumber?: string;
  PersonalEmailAddress: string;
  BirthDate?: string;
  Attributes: Record<string, string>;
}
export function mapearFilaAPerfil(fila: FilaSocio): PerfilTransformado {
  return {
    AccountNumber: fila.DNI,
    FirstName: fila.NOMBRE_SOCIO,
    ...(fila.TELEFONO_1 ? { MobilePhoneNumber: `+${fila.TELEFONO_1}` } : {}),
    PersonalEmailAddress: fila.correo,
    ...(fila.fecha_nacimiento ? { BirthDate: fila.fecha_nacimiento } : {}),
    Attributes: {
      SegmentoValor: fila.SEGMENTO_VALOR,
      MarcaRetener: fila.MARCA_RETENER,
      TieneOferta: fila.tiene_oferta,
      Tea: fila.tea,
      FechaAfiliacion: fila.fecha_afiliacion,
      TipoProducto: fila.tipo_producto
    }
  };
}
export const FILA_EJEMPLO: FilaSocio = {
  DNI: "45678901",
  NOMBRE_SOCIO: "QUISPE ROJAS MARIA FERNANDA",
  SEGMENTO_VALOR: "1",
  MARCA_RETENER: "1",
  TELEFONO_1: "51987654412",
  tiene_oferta: "S",
  tea: "34.5",
  fecha_afiliacion: "2019-03-12",
  tipo_producto: "Miles",
  correo: "mf.quispe@example.com",
  fecha_nacimiento: "1988-07-14"
};
export interface CampoDestino {
  id: string;
  label: string;
  target: string;
  contentType: TipoContenido;
  category: "Atributos estándar" | "Atributos personalizados";
  description: string;
  aliases: readonly string[];
}
export interface CampoEsquema {
  sourceColumn: string;
  destinationId: string;
  contentType: TipoContenido;
  required: boolean;
  identifier: IdentificadorCampo;
  validation: string;
}
export interface EsquemaDestino {
  id: string;
  name: string;
  version: number;
  description: string;
  allowProfileCreation: boolean;
  updatedAt: string;
  updatedBy: string;
  fields: readonly CampoEsquema[];
}
const destinosEstandar: CampoDestino[] = [
  [
    "account-number",
    "AccountNumber",
    "_profile.AccountNumber",
    "STRING",
    "Identificador de cuenta del perfil.",
    ["dni", "documento", "customerid", "accountid"]
  ],
  [
    "first-name",
    "FirstName",
    "_profile.FirstName",
    "STRING",
    "Nombre o nombre completo cuando la fuente no lo separa.",
    ["nombre", "nombres", "nombre_socio", "firstname"]
  ],
  [
    "last-name",
    "LastName",
    "_profile.LastName",
    "STRING",
    "Apellidos del cliente.",
    ["apellido", "apellidos", "lastname"]
  ],
  [
    "phone-number",
    "PhoneNumber",
    "_profile.PhoneNumber",
    "PHONE_NUMBER",
    "Teléfono principal.",
    ["telefono", "telefono_1", "phone", "phonenumber"]
  ],
  [
    "mobile-phone",
    "MobilePhoneNumber",
    "_profile.MobilePhoneNumber",
    "PHONE_NUMBER",
    "Teléfono móvil.",
    ["celular", "movil", "mobile", "mobilephonenumber"]
  ],
  [
    "personal-email",
    "PersonalEmailAddress",
    "_profile.PersonalEmailAddress",
    "EMAIL_ADDRESS",
    "Correo electrónico personal.",
    ["correo", "email", "correo_electronico", "personalemailaddress"]
  ],
  [
    "birth-date",
    "BirthDate",
    "_profile.BirthDate",
    "STRING",
    "Fecha de nacimiento.",
    ["fecha_nacimiento", "birthdate"]
  ],
  [
    "profile-type",
    "ProfileType",
    "_profile.ProfileType",
    "STRING",
    "Tipo de perfil de Customer Profiles.",
    ["profiletype", "tipo_perfil"]
  ]
].map(([id, label, target, contentType, description, aliases]) => ({
  id: id as string,
  label: label as string,
  target: target as string,
  contentType: contentType as TipoContenido,
  category: "Atributos estándar" as const,
  description: description as string,
  aliases: aliases as string[]
}));
const destinosPersonalizados: CampoDestino[] = [
  [
    "segmento-valor",
    "Attributes.SegmentoValor",
    "_profile.Attributes.SegmentoValor",
    "STRING",
    ["segmento_valor", "segmento"]
  ],
  [
    "marca-retener",
    "Attributes.MarcaRetener",
    "_profile.Attributes.MarcaRetener",
    "STRING",
    ["marca_retener", "retener"]
  ],
  ["tiene-oferta", "Attributes.TieneOferta", "_profile.Attributes.TieneOferta", "STRING", ["tiene_oferta", "oferta"]],
  ["tea", "Attributes.Tea", "_profile.Attributes.Tea", "NUMBER", ["tea", "tasa"]],
  [
    "fecha-afiliacion",
    "Attributes.FechaAfiliacion",
    "_profile.Attributes.FechaAfiliacion",
    "STRING",
    ["fecha_afiliacion", "afiliacion"]
  ],
  [
    "tipo-producto",
    "Attributes.TipoProducto",
    "_profile.Attributes.TipoProducto",
    "STRING",
    ["tipo_producto", "producto"]
  ]
].map(([id, label, target, contentType, aliases]) => ({
  id: id as string,
  label: label as string,
  target: target as string,
  contentType: contentType as TipoContenido,
  category: "Atributos personalizados" as const,
  description: "Atributo personalizado definido por Diners.",
  aliases: aliases as string[]
}));
export const CAMPOS_DESTINO: readonly CampoDestino[] = [...destinosEstandar, ...destinosPersonalizados];
const destinoPorTarget = new Map(CAMPOS_DESTINO.map((campo) => [campo.target, campo.id]));
export const ESQUEMA_SOCIOS: EsquemaDestino = {
  id: "diners-socios",
  name: "Perfil de socio Diners",
  version: 3,
  description: "Perfil maestro de socios para identificación y personalización de la atención.",
  allowProfileCreation: true,
  updatedAt: "2026-10-26T15:40:00-05:00",
  updatedBy: "Mary Carmen Vílchez",
  fields: REGLAS_MAPEO.map((regla) => ({
    sourceColumn: regla.sourceColumn,
    destinationId: destinoPorTarget.get(regla.target)!,
    contentType: regla.contentType,
    required: !["TELEFONO_1", "SEGMENTO_VALOR", "tea", "fecha_nacimiento"].includes(regla.sourceColumn),
    identifier:
      regla.searchKey === "_account"
        ? ("PROFILE_UNIQUE" as const)
        : regla.searchKey === "_phone"
          ? ("PROFILE" as const)
          : ("NONE" as const),
    validation: REGLAS_VALIDACION[regla.sourceColumn]
  }))
};
export const ESQUEMAS_DESTINO: readonly EsquemaDestino[] = [ESQUEMA_SOCIOS];
export interface MapeoDetectado {
  rowId: string;
  sourceColumn: string;
  destinationId: string | null;
  contentType: TipoContenido;
  confidence: "exact" | "inferred" | "unmapped";
  required: boolean;
  identifier: IdentificadorCampo;
  validation: string;
}
function normalizarCampo(valor: string) {
  return valor
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]/g, "");
}
export function inferirMapeo(headers: readonly string[], esquema: EsquemaDestino): MapeoDetectado[] {
  return headers.map((header, index) => {
    const normalizado = normalizarCampo(header);
    const exacto = esquema.fields.find((campo) => normalizarCampo(campo.sourceColumn) === normalizado);
    if (exacto) {
      return {
        rowId: `${index}-${normalizado || "campo"}`,
        sourceColumn: header,
        destinationId: exacto.destinationId,
        contentType: exacto.contentType,
        confidence: "exact" as const,
        required: exacto.required,
        identifier: exacto.identifier,
        validation: exacto.validation
      };
    }
    const inferido = CAMPOS_DESTINO.find((campo) =>
      campo.aliases.some((alias) => normalizarCampo(alias) === normalizado)
    );
    return {
      rowId: `${index}-${normalizado || "campo"}`,
      sourceColumn: header,
      destinationId: inferido?.id ?? null,
      contentType: inferido?.contentType ?? "STRING",
      confidence: inferido ? ("inferred" as const) : ("unmapped" as const),
      required: false,
      identifier: "NONE",
      validation: ""
    };
  });
}
const identificadoresAWS: Record<Exclude<IdentificadorCampo, "NONE">, string[]> = {
  PROFILE_UNIQUE: ["PROFILE", "UNIQUE"],
  PROFILE: ["PROFILE"],
  PROFILE_SECONDARY: ["PROFILE", "SECONDARY"],
  PROFILE_LOOKUP_ONLY: ["PROFILE", "LOOKUP_ONLY"],
  PROFILE_NEW_ONLY: ["PROFILE", "NEW_ONLY"]
};
export function generarObjectType(esquema: EsquemaDestino, mapeo: readonly MapeoDetectado[]) {
  const resueltos = mapeo.filter((fila): fila is MapeoDetectado & { destinationId: string } =>
    Boolean(fila.destinationId)
  );
  const fields = Object.fromEntries(
    resueltos.map((fila) => {
      const destino = CAMPOS_DESTINO.find((campo) => campo.id === fila.destinationId)!;
      return [
        fila.sourceColumn,
        {
          Source: `_source.${fila.sourceColumn}`,
          Target: destino.target,
          ContentType: fila.contentType
        }
      ];
    })
  );
  const keys = Object.fromEntries(
    resueltos
      .filter(
        (fila): fila is typeof fila & { identifier: Exclude<IdentificadorCampo, "NONE"> } => fila.identifier !== "NONE"
      )
      .map((fila) => [
        fila.sourceColumn,
        [
          {
            FieldNames: [fila.sourceColumn],
            StandardIdentifiers: identificadoresAWS[fila.identifier]
          }
        ]
      ])
  );
  return {
    AllowProfileCreation: esquema.allowProfileCreation,
    Description: esquema.description,
    Fields: fields,
    Keys: keys
  };
}
export function validarConfiguracionMapeo(esquema: EsquemaDestino, mapeo: readonly MapeoDetectado[]) {
  const errores: string[] = [];
  const nombres = mapeo.map((fila) => fila.sourceColumn.trim());
  if (mapeo.some((fila) => !/^[a-zA-Z0-9_.-]{1,64}$/.test(fila.sourceColumn))) {
    errores.push("Corrige los nombres de columna marcados como inválidos.");
  }
  if (new Set(nombres).size !== nombres.length) {
    errores.push("Cada columna esperada debe tener un nombre diferente.");
  }
  if (mapeo.some((fila) => !fila.destinationId)) {
    errores.push("Asigna un destino a todas las columnas.");
  }
  const principales = mapeo.filter((fila) => fila.identifier === "PROFILE_UNIQUE").length;
  if (esquema.allowProfileCreation && principales !== 1) {
    errores.push("Define exactamente un identificador principal para crear perfiles.");
  } else if (principales > 1) {
    errores.push("AWS admite una sola clave UNIQUE por tipo de objeto.");
  }
  return errores;
}
export type EstadoCarga = "en curso" | "completada" | "parcial" | "rechazada" | "fallida";
export interface Carga {
  id: string;
  fecha: string;
  usuario: string;
  archivo: string;
  estado: EstadoCarga;
  filasProcesadas: number;
  filasEscritas: number;
  filasRechazadas: number;
  advertencias: number;
}
export interface Hallazgo {
  id: string;
  linea: number;
  dni: string;
  columna: string;
  tipo: "rechazo" | "advertencia";
  motivo: string;
}
export const INSTANCIA_CONNECT = "Amazon Connect";
export const DOMINIO_PERFILES = "diners-socios";
export const TOTAL_PERFILES_ACTUALES = 176_865;
export const HISTORIAL_INICIAL: Carga[] = [
  {
    id: "CRG-20261020-001",
    fecha: "2026-10-20T14:36:00-05:00",
    usuario: "Giovanna Montero",
    archivo: "base_socios_2026-10-20.xlsx",
    estado: "completada",
    filasProcesadas: 176_865,
    filasEscritas: 176_474,
    filasRechazadas: 391,
    advertencias: 11_492
  },
  {
    id: "CRG-20261006-001",
    fecha: "2026-10-06T09:18:00-05:00",
    usuario: "Diana Solano",
    archivo: "base_socios_2026-10-06.csv",
    estado: "completada",
    filasProcesadas: 175_902,
    filasEscritas: 175_540,
    filasRechazadas: 362,
    advertencias: 10_884
  }
];
export const HALLAZGOS_MUESTRA: Hallazgo[] = [
  { id: "1", linea: 183, dni: "1234", columna: "DNI", tipo: "rechazo", motivo: "DNI con longitud inválida" },
  { id: "2", linea: 944, dni: "987654321", columna: "DNI", tipo: "rechazo", motivo: "DNI con longitud inválida" },
  { id: "3", linea: 1450, dni: "45678901", columna: "DNI", tipo: "rechazo", motivo: "DNI duplicado en el archivo" },
  {
    id: "4",
    linea: 2218,
    dni: "70214589",
    columna: "TELEFONO_1",
    tipo: "advertencia",
    motivo: "Campo vacío; el perfil se escribió sin teléfono"
  },
  {
    id: "5",
    linea: 3021,
    dni: "10293847",
    columna: "SEGMENTO_VALOR",
    tipo: "advertencia",
    motivo: "Campo vacío; el perfil se escribió sin segmento"
  },
  {
    id: "6",
    linea: 4190,
    dni: "61528374",
    columna: "TELEFONO_1",
    tipo: "rechazo",
    motivo: "Teléfono con formato inválido"
  }
];
export function formatearNumero(numero: number) {
  return new Intl.NumberFormat("es-PE").format(numero);
}
export function formatearFecha(fecha: string) {
  return new Intl.DateTimeFormat("es-PE", {
    dateStyle: "medium",
    timeStyle: "short",
    timeZone: "America/Lima"
  }).format(new Date(fecha));
}
