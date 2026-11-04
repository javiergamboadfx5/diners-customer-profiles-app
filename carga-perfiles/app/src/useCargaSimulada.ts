import { useEffect, useRef, useState } from "react";
import { ESQUEMA_SOCIOS, EsquemaDestino } from "./customerProfilesMapping";
import {
  Carga,
  EstadoCarga,
  Hallazgo,
  HISTORIAL_INICIAL,
  TOTAL_ADVERTENCIAS,
  TOTAL_ESCRITAS,
  TOTAL_FILAS_ARCHIVO,
  TOTAL_RECHAZOS,
  generarHallazgos
} from "./mock";

export type FaseCarga = "inicial" | "validando" | "confirmacion" | "escribiendo" | "listo";

export interface ResultadoCarga {
  id?: string;
  estado?: EstadoCarga;
  filasProcesadas: number;
  filasValidas?: number;
  filasEscritas: number;
  filasRechazadas: number;
  advertencias: number;
  hallazgos: Hallazgo[];
  /** Total real de hallazgos; el detalle puede venir truncado. */
  totalHallazgos?: number;
  mensaje?: string;
}

/** Contrato comun del modo simulado y del modo conectado a la API. */
export interface ControladorCarga {
  modo: "mock" | "api";
  fase: FaseCarga;
  archivo: File[];
  nombreArchivo?: string;
  progreso: number;
  resultado?: ResultadoCarga;
  historial: Carga[];
  enCurso: boolean;
  ocupado: boolean;
  error?: string;
  usuario?: string;
  esquema: EsquemaDestino;
  setArchivo: (archivos: File[]) => void;
  iniciar: () => void;
  confirmarEscritura: () => void;
  cancelar: () => void;
  reiniciar: () => void;
  publicarEsquema: (esquema: EsquemaDestino) => void;
  descargarReporte?: (cargaId: string) => void;
  limpiarError: () => void;
}

const RESULTADO: ResultadoCarga = {
  estado: "completada",
  filasProcesadas: TOTAL_FILAS_ARCHIVO,
  filasValidas: TOTAL_ESCRITAS,
  filasEscritas: TOTAL_ESCRITAS,
  filasRechazadas: TOTAL_RECHAZOS,
  advertencias: TOTAL_ADVERTENCIAS,
  hallazgos: generarHallazgos()
};

export function useCargaSimulada(): ControladorCarga {
  const [fase, setFase] = useState<FaseCarga>("inicial");
  const [archivo, setArchivo] = useState<File[]>([]);
  const [progreso, setProgreso] = useState(0);
  const [resultado, setResultado] = useState<ResultadoCarga>();
  const [historial, setHistorial] = useState<Carga[]>(HISTORIAL_INICIAL);
  const [esquema, setEsquema] = useState<EsquemaDestino>(ESQUEMA_SOCIOS);
  const timers = useRef<number[]>([]);
  const limpiarTimers = () => {
    timers.current.forEach(window.clearTimeout);
    timers.current = [];
  };
  useEffect(() => limpiarTimers, []);

  const iniciar = () => {
    if (!archivo.length) return;
    limpiarTimers();
    setResultado(undefined);
    setProgreso(12);
    setFase("validando");
    timers.current.push(
      window.setTimeout(() => {
        setProgreso(100);
        setResultado({ ...RESULTADO, filasEscritas: 0, estado: undefined });
        setFase("confirmacion");
      }, 900)
    );
  };

  const confirmarEscritura = () => {
    setFase("escribiendo");
    setProgreso(18);
    [42, 68, 91, 100].forEach((valor, indice) => {
      timers.current.push(
        window.setTimeout(
          () => {
            setProgreso(valor);
            if (valor === 100) {
              const carga: Carga = {
                id: "CRG-20261026-001",
                fecha: new Date().toISOString(),
                usuario: "Giovanna Montero",
                archivo: archivo[0]?.name ?? "base_socios.xlsx",
                tamanoBytes: archivo[0]?.size ?? 0,
                estado: "completada",
                filasProcesadas: RESULTADO.filasProcesadas,
                filasEscritas: RESULTADO.filasEscritas,
                filasRechazadas: RESULTADO.filasRechazadas,
                advertencias: RESULTADO.advertencias
              };
              setResultado(RESULTADO);
              setHistorial((actual) => [carga, ...actual]);
              setFase("listo");
            }
          },
          500 * (indice + 1)
        )
      );
    });
  };

  const cancelar = () => {
    limpiarTimers();
    setFase("inicial");
    setProgreso(0);
    setResultado(undefined);
  };

  const reiniciar = () => {
    cancelar();
    setArchivo([]);
  };

  return {
    modo: "mock",
    fase,
    archivo,
    progreso,
    resultado,
    historial,
    enCurso: fase === "validando" || fase === "escribiendo",
    ocupado: false,
    esquema,
    setArchivo,
    iniciar,
    confirmarEscritura,
    cancelar,
    reiniciar,
    publicarEsquema: setEsquema,
    limpiarError: () => undefined
  };
}
