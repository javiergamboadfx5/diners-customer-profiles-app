// Modelo de dominio y datos simulados de la app de carga de perfiles.
// Mock: no escribe en Amazon Connect Customer Profiles.

export const TOTAL_PERFILES_ACTUALES = 176865;
export const DOMINIO_PERFILES = "diners-peru-prod";
export const INSTANCIA_CONNECT = "diners-peru.my.connect.aws";

export type EstadoCarga = "en_curso" | "completada" | "parcial" | "rechazada" | "fallida" | "cancelada";

export type TipoHallazgo = "rechazo" | "advertencia";

export interface ColumnaArchivo {
  nombre: string;
  destino: string;
  regla: string;
  obligatoria: boolean;
}

/** Las 11 columnas del archivo de carga, segun el documento vivo (version 20). */
export const COLUMNAS_ARCHIVO: ColumnaArchivo[] = [
  {
    nombre: "DNI",
    destino: "AccountNumber (clave de busqueda)",
    regla: "8 digitos, sin duplicados en el archivo",
    obligatoria: true
  },
  {
    nombre: "NOMBRE_SOCIO",
    destino: "FirstName y LastName",
    regla: "Apellidos y nombres, para saludar por nombre",
    obligatoria: true
  },
  {
    nombre: "SEGMENTO_VALOR",
    destino: "Atributo segmento_valor",
    regla: "1 alto, 2 medio, 3 bajo. Decide el grupo de ejecutivos",
    obligatoria: false
  },
  {
    nombre: "MARCA_RETENER",
    destino: "Atributo marca_retener",
    regla: "1 retener, 2 no retener. Decide la ruta de anulacion",
    obligatoria: false
  },
  {
    nombre: "TELEFONO_1",
    destino: "PhoneNumber",
    regla: "11 digitos con prefijo 51. Clave de busqueda en voz",
    obligatoria: false
  },
  {
    nombre: "tiene_oferta",
    destino: "Atributo tiene_oferta",
    regla: "SI o NO. Dispara la oferta proactiva de prestamo",
    obligatoria: true
  },
  {
    nombre: "tea",
    destino: "Atributo tea",
    regla: "Decimal entre 0 y 200. El agente simula la cuota con este valor",
    obligatoria: false
  },
  {
    nombre: "fecha_afiliacion",
    destino: "Atributo fecha_afiliacion",
    regla: "AAAA-MM-DD, no posterior a hoy. Alimenta la constancia de socio",
    obligatoria: true
  },
  {
    nombre: "tipo_producto",
    destino: "Atributo tipo_producto",
    regla: "Free, Hiraoka, Club, Miles, Special Edition o Carte Blanche",
    obligatoria: true
  },
  {
    nombre: "correo",
    destino: "EmailAddress",
    regla: "Formato de correo. Por aqui salen las constancias",
    obligatoria: true
  },
  {
    nombre: "fecha_nacimiento",
    destino: "BirthDate",
    regla: "AAAA-MM-DD, no posterior a hoy. Saludo de cumpleaños",
    obligatoria: false
  }
];

export interface Hallazgo {
  id: string;
  linea: number;
  dni: string;
  columna: string;
  motivo: string;
  tipo: TipoHallazgo;
}

export interface Carga {
  id: string;
  fecha: string;
  usuario: string;
  archivo: string;
  tamanoBytes: number;
  filasProcesadas: number;
  filasEscritas: number;
  filasRechazadas: number;
  advertencias: number;
  estado: EstadoCarga;
}

/** Perfil de defectos de la base real recibida de Diners. */
const DEFECTOS = [
  { cantidad: 391, columna: "DNI", motivo: "DNI con longitud invalida", tipo: "rechazo" as TipoHallazgo },
  { cantidad: 14, columna: "DNI", motivo: "DNI duplicado en el archivo", tipo: "rechazo" as TipoHallazgo },
  { cantidad: 17, columna: "TELEFONO_1", motivo: "Telefono con formato invalido", tipo: "rechazo" as TipoHallazgo },
  { cantidad: 9, columna: "correo", motivo: "Correo con formato invalido", tipo: "rechazo" as TipoHallazgo },
  {
    cantidad: 4,
    columna: "fecha_afiliacion",
    motivo: "fecha_afiliacion con formato invalido",
    tipo: "rechazo" as TipoHallazgo
  },
  { cantidad: 2, columna: "tea", motivo: "tea fuera del rango permitido", tipo: "rechazo" as TipoHallazgo },
  {
    cantidad: 8843,
    columna: "TELEFONO_1",
    motivo: "Campo vacio: el socio no recibira llamada de vuelta",
    tipo: "advertencia" as TipoHallazgo
  },
  {
    cantidad: 2653,
    columna: "SEGMENTO_VALOR",
    motivo: "Campo vacio: se enrutara al grupo general",
    tipo: "advertencia" as TipoHallazgo
  },
  {
    cantidad: 612,
    columna: "tea",
    motivo: "Campo vacio con tiene_oferta en SI: el agente no podra simular",
    tipo: "advertencia" as TipoHallazgo
  }
];

export const TOTAL_FILAS_ARCHIVO = TOTAL_PERFILES_ACTUALES;
export const TOTAL_RECHAZOS = DEFECTOS.filter((d) => d.tipo === "rechazo").reduce((a, d) => a + d.cantidad, 0);
export const TOTAL_ADVERTENCIAS = DEFECTOS.filter((d) => d.tipo === "advertencia").reduce((a, d) => a + d.cantidad, 0);
export const TOTAL_ESCRITAS = TOTAL_FILAS_ARCHIVO - TOTAL_RECHAZOS;

/** Generador congruencial simple, para que el mock sea reproducible entre recargas. */
function prng(semilla: number): () => number {
  let s = semilla;
  return () => {
    s = (s * 1103515245 + 12345) % 2147483648;
    return s / 2147483648;
  };
}

function dniFalso(rnd: () => number, digitos: number): string {
  let out = "";
  for (let i = 0; i < digitos; i += 1) {
    out += Math.floor(rnd() * 10).toString();
  }
  return out;
}

/** Construye el detalle del reporte de rechazos y advertencias. */
export function generarHallazgos(): Hallazgo[] {
  const rnd = prng(20261023);
  const out: Hallazgo[] = [];
  let n = 0;
  for (const defecto of DEFECTOS) {
    for (let i = 0; i < defecto.cantidad; i += 1) {
      n += 1;
      const digitos = defecto.motivo.includes("longitud") ? (rnd() > 0.5 ? 9 : 4) : 8;
      out.push({
        id: `h-${n}`,
        linea: 2 + Math.floor(rnd() * TOTAL_FILAS_ARCHIVO),
        dni: dniFalso(rnd, digitos),
        columna: defecto.columna,
        motivo: defecto.motivo,
        tipo: defecto.tipo
      });
    }
  }
  return out.sort((a, b) => a.linea - b.linea);
}

export const HISTORIAL_INICIAL: Carga[] = [
  {
    id: "CRG-2026-0007",
    fecha: "2026-10-20T09:14:00-05:00",
    usuario: "diana.solano@diners.com.pe",
    archivo: "Base_WhatsApp_octubre.xlsx",
    tamanoBytes: 14_882_304,
    filasProcesadas: 176865,
    filasEscritas: 176428,
    filasRechazadas: 437,
    advertencias: 12108,
    estado: "completada"
  },
  {
    id: "CRG-2026-0006",
    fecha: "2026-09-18T15:42:00-05:00",
    usuario: "diana.solano@diners.com.pe",
    archivo: "Base_WhatsApp_setiembre.xlsx",
    tamanoBytes: 14_701_112,
    filasProcesadas: 175204,
    filasEscritas: 168902,
    filasRechazadas: 402,
    advertencias: 11744,
    estado: "parcial"
  },
  {
    id: "CRG-2026-0005",
    fecha: "2026-09-18T11:05:00-05:00",
    usuario: "haida.colet@diners.com.pe",
    archivo: "Base_WhatsApp_setiembre_v1.csv",
    tamanoBytes: 9_220_418,
    filasProcesadas: 0,
    filasEscritas: 0,
    filasRechazadas: 0,
    advertencias: 0,
    estado: "rechazada"
  }
];

export function formatearNumero(n: number): string {
  return n.toLocaleString("es-PE");
}

export function formatearFecha(iso: string): string {
  return new Date(iso).toLocaleString("es-PE", {
    day: "2-digit",
    month: "2-digit",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit"
  });
}

export function formatearTamano(bytes: number): string {
  const mb = bytes / (1024 * 1024);
  return `${mb.toFixed(1)} MB`;
}
