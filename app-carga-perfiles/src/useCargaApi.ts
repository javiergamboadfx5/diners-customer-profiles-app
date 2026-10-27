import { useCallback, useEffect, useRef, useState } from "react";
import { api, CargaApi, EstadoBackend } from "./api";
import { nombreUsuario, obtenerUsuario } from "./auth";
import { ESQUEMA_SOCIOS, EsquemaDestino } from "./customerProfilesMapping";
import type { Carga, EstadoCarga } from "./mock";
import type { ControladorCarga, FaseCarga, ResultadoCarga } from "./useCargaSimulada";

const EN_CURSO: EstadoBackend[] = ["subiendo", "validando", "validada", "escribiendo"];
const INTERVALO_MS = 2500;

const estadoHistorial = (e: EstadoBackend): EstadoCarga => (EN_CURSO.includes(e) ? "en_curso" : (e as EstadoCarga));

const aHistorial = (c: CargaApi): Carga => ({
  id: c.id,
  fecha: c.fecha,
  usuario: c.usuario,
  archivo: c.archivo,
  tamanoBytes: c.tamanoBytes,
  estado: estadoHistorial(c.estado),
  filasProcesadas: c.filasProcesadas,
  filasEscritas: c.filasEscritas,
  filasRechazadas: c.filasRechazadas + c.fallidasEscritura,
  advertencias: c.advertencias
});

function faseDe(c: CargaApi): FaseCarga {
  if (c.estado === "subiendo" || c.estado === "validando") return "validando";
  if (c.estado === "validada") return "confirmacion";
  if (c.estado === "escribiendo") return "escribiendo";
  return "listo";
}

function progresoDe(c: CargaApi): number {
  if (c.estado === "subiendo") return 15;
  if (c.estado === "validando") return 55;
  if (c.estado === "escribiendo" && c.filasValidas > 0) {
    return Math.min(99, Math.round(((c.filasEscritas + c.fallidasEscritura) / c.filasValidas) * 100));
  }
  return 100;
}

const mensaje = (e: unknown) => (e instanceof Error ? e.message : "Ocurrió un error inesperado.");

export function useCargaApi(): ControladorCarga {
  const [archivo, setArchivo] = useState<File[]>([]);
  const [actual, setActual] = useState<CargaApi>();
  const [resultado, setResultado] = useState<ResultadoCarga>();
  const [historial, setHistorial] = useState<Carga[]>([]);
  const [esquema, setEsquema] = useState<EsquemaDestino>(ESQUEMA_SOCIOS);
  const [usuario, setUsuario] = useState<string>();
  const [error, setError] = useState<string>();
  const [ocupado, setOcupado] = useState(false);
  const hallazgosDe = useRef<string>();

  const refrescarHistorial = useCallback(async () => {
    const { cargas } = await api.listar();
    setHistorial(cargas.map(aHistorial));
    return cargas;
  }, []);

  // Carga inicial: usuario, esquema publicado, historial y carga en curso (si alguien dejó una abierta).
  useEffect(() => {
    void (async () => {
      try {
        setUsuario(nombreUsuario(await obtenerUsuario()));
        const [{ esquema: publicado }, cargas] = await Promise.all([api.esquema(), refrescarHistorial()]);
        setEsquema(publicado);
        const abierta = cargas.find((c) => EN_CURSO.includes(c.estado));
        if (abierta) setActual(abierta);
      } catch (e) {
        setError(mensaje(e));
      }
    })();
  }, [refrescarHistorial]);

  // Resultado y detalle de hallazgos cuando la validación terminó.
  useEffect(() => {
    if (!actual || actual.estado === "subiendo" || actual.estado === "validando") return;
    const base: Omit<ResultadoCarga, "hallazgos"> = {
      id: actual.id,
      estado: EN_CURSO.includes(actual.estado) ? undefined : estadoHistorial(actual.estado),
      filasProcesadas: actual.filasProcesadas,
      filasValidas: actual.filasValidas,
      filasEscritas: actual.filasEscritas,
      filasRechazadas: actual.filasRechazadas + actual.fallidasEscritura,
      advertencias: actual.advertencias,
      mensaje: actual.error || undefined
    };
    setResultado((previo) => ({ hallazgos: [], ...previo, ...base }));
    if (hallazgosDe.current === actual.id) return;
    hallazgosDe.current = actual.id;
    api
      .hallazgos(actual.id)
      .then(({ total, hallazgos }) => setResultado((r) => (r ? { ...r, hallazgos, totalHallazgos: total } : r)))
      .catch(() => undefined); // si la carga fallo antes de generar el reporte, no hay detalle
  }, [actual]);

  // Seguimiento mientras la carga avanza en el backend.
  useEffect(() => {
    if (!actual || !EN_CURSO.includes(actual.estado) || actual.estado === "validada") return;
    const id = window.setInterval(async () => {
      try {
        const { carga } = await api.obtener(actual.id);
        setActual(carga);
        if (!EN_CURSO.includes(carga.estado)) void refrescarHistorial();
      } catch (e) {
        setError(mensaje(e));
      }
    }, INTERVALO_MS);
    return () => window.clearInterval(id);
  }, [actual, refrescarHistorial]);

  const ejecutar = async (accion: () => Promise<void>) => {
    setOcupado(true);
    setError(undefined);
    try {
      await accion();
    } catch (e) {
      setError(mensaje(e));
    } finally {
      setOcupado(false);
    }
  };

  const iniciar = () =>
    ejecutar(async () => {
      const seleccionado = archivo[0];
      if (!seleccionado) return;
      if (!seleccionado.name.toLowerCase().endsWith(".csv")) {
        throw new Error("Por ahora el backend acepta solo .csv (UTF-8, separado por coma o punto y coma).");
      }
      setResultado(undefined);
      hallazgosDe.current = undefined;
      const { carga, subida } = await api.crear(seleccionado);
      setActual(carga);
      await api.subir(subida, seleccionado);
      void refrescarHistorial();
    });

  const confirmarEscritura = () =>
    ejecutar(async () => {
      if (!actual) return;
      setActual((await api.confirmar(actual.id)).carga);
    });

  const reiniciar = () => {
    setActual(undefined);
    setResultado(undefined);
    setArchivo([]);
    hallazgosDe.current = undefined;
  };

  const cancelar = () =>
    ejecutar(async () => {
      if (actual && EN_CURSO.includes(actual.estado)) await api.cancelar(actual.id);
      reiniciar();
      await refrescarHistorial();
    });

  const publicarEsquema = (nuevo: EsquemaDestino) =>
    void ejecutar(async () => {
      setEsquema((await api.publicarEsquema(nuevo)).esquema);
    });

  const descargarReporte = (cargaId: string) =>
    void ejecutar(async () => {
      const { url } = await api.urlReporte(cargaId);
      window.location.assign(url);
    });

  return {
    modo: "api",
    fase: actual ? faseDe(actual) : "inicial",
    archivo,
    nombreArchivo: actual?.archivo ?? archivo[0]?.name,
    progreso: actual ? progresoDe(actual) : 0,
    resultado,
    historial,
    enCurso: Boolean(actual && EN_CURSO.includes(actual.estado) && actual.estado !== "validada"),
    ocupado,
    error,
    usuario,
    esquema,
    setArchivo,
    iniciar: () => void iniciar(),
    confirmarEscritura: () => void confirmarEscritura(),
    cancelar: () => void cancelar(),
    reiniciar,
    publicarEsquema,
    descargarReporte,
    limpiarError: () => setError(undefined)
  };
}
