import {
  createContext,
  useContext,
  useEffect,
  useRef,
  useSyncExternalStore,
  type ReactNode,
} from "react";
import { DeskEngine, defaultConfig, type EngineSnapshot } from "./engine";
import { sha256Hex } from "./schemas";

const DeskCtx = createContext<DeskEngine | null>(null);

export function DeskProvider({ children }: { children: ReactNode }) {
  const engineRef = useRef<DeskEngine | null>(null);
  if (!engineRef.current) {
    engineRef.current = new DeskEngine(defaultConfig("pending"));
  }
  const engine = engineRef.current;

  useEffect(() => {
    let cancelled = false;
    void (async () => {
      const hash = await sha256Hex(JSON.stringify(engine.config));
      if (cancelled) return;
      engine.config = defaultConfig(hash);
      await engine.boot();
    })();
    const id = window.setInterval(() => {
      if (engine.running && engine.controller.system_state !== "FAULT") {
        engine.step(engine.speed);
      }
    }, 90);
    return () => {
      cancelled = true;
      window.clearInterval(id);
    };
  }, [engine]);

  return <DeskCtx.Provider value={engine}>{children}</DeskCtx.Provider>;
}

export function useDesk(): DeskEngine {
  const ctx = useContext(DeskCtx);
  if (!ctx) throw new Error("DeskProvider missing");
  return ctx;
}

export function useDeskSnapshot(): EngineSnapshot {
  const engine = useDesk();
  return useSyncExternalStore(
    (cb) => engine.subscribe(cb),
    () => engine.snapshot(),
    () => engine.snapshot(),
  );
}
