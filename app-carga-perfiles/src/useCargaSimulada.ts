import { useEffect, useRef, useState } from "react";
import {
  Carga,
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
  filasProcesadas: number;
  filasEscritas: number;
  filasRechazadas: number;
  advertencias: number;
  hallazgos: Hallazgo[];
}
const RESULTADO: ResultadoCarga = {
  filasProcesadas: TOTAL_FILAS_ARCHIVO,
  filasEscritas: TOTAL_ESCRITAS,
  filasRechazadas: TOTAL_RECHAZOS,
  advertencias: TOTAL_ADVERTENCIAS,
  hallazgos: generarHallazgos()
};
export function useCargaSimulada() {
  const [fase, setFase] = useState<FaseCarga>("inicial");
  const [archivo, setArchivo] = useState<File[]>([]);
  const [progreso, setProgreso] = useState(0);
  const [resultado, setResultado] = useState<ResultadoCarga>();
  const [historial, setHistorial] = useState<Carga[]>(HISTORIAL_INICIAL);
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
  };
  const reiniciar = () => {
    limpiarTimers();
    setFase("inicial");
    setProgreso(0);
    setResultado(undefined);
    setArchivo([]);
  };
  return {
    fase,
    archivo,
    progreso,
    resultado,
    historial,
    enCurso: fase === "validando" || fase === "escribiendo",
    setArchivo,
    iniciar,
    confirmarEscritura,
    cancelar,
    reiniciar
  };
}
