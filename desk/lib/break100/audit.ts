import type { AuditEvent, AuditKind } from "./schemas";
import { AUDIT_SCHEMA_VERSION, sha256Hex } from "./schemas";

export async function appendAudit(
  prev: AuditEvent | null,
  kind: AuditKind,
  reason_code: string,
  payload: Record<string, unknown>,
  utc = new Date().toISOString(),
): Promise<AuditEvent> {
  const prev_hash = prev?.hash ?? "genesis";
  const id = `${kind}-${utc}-${Math.random().toString(16).slice(2, 10)}`;
  const body = JSON.stringify({
    schema: AUDIT_SCHEMA_VERSION,
    id,
    utc,
    kind,
    reason_code,
    payload,
    prev_hash,
  });
  const hash = await sha256Hex(body);
  return {
    schema: AUDIT_SCHEMA_VERSION,
    id,
    utc,
    kind,
    reason_code,
    payload,
    prev_hash,
    hash,
  };
}

export function verifyChain(events: readonly AuditEvent[]): {
  ok: boolean;
  broken_at: number | null;
} {
  for (let i = 0; i < events.length; i++) {
    const expectedPrev = i === 0 ? "genesis" : events[i - 1].hash;
    if (events[i].prev_hash !== expectedPrev) {
      return { ok: false, broken_at: i };
    }
  }
  return { ok: true, broken_at: null };
}
