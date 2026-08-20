import { createServerFn } from "@tanstack/react-start";
import { authMiddleware } from "@/lib/auth/middleware";
import { getSql } from "@/lib/db";
import type { AuditEvent } from "./schemas";

export const saveAuditBatch = createServerFn({ method: "POST" })
  .middleware([authMiddleware])
  .validator((events: AuditEvent[]) => events.slice(-40))
  .handler(async ({ context, data }) => {
    const sql = await getSql();
    for (const ev of data) {
      await sql`
        insert into break100_audit (id, user_id, utc, kind, reason_code, payload, prev_hash, hash)
        values (
          ${ev.id},
          ${context.userId},
          ${ev.utc},
          ${ev.kind},
          ${ev.reason_code},
          ${JSON.stringify(ev.payload)}::jsonb,
          ${ev.prev_hash},
          ${ev.hash}
        )
        on conflict (id) do nothing
      `;
    }
    return { saved: data.length };
  });

export const listSavedAudit = createServerFn({ method: "GET" })
  .middleware([authMiddleware])
  .handler(async ({ context }) => {
    const sql = await getSql();
    return sql<{
      id: string;
      utc: string;
      kind: string;
      reason_code: string;
      hash: string;
    }>`
      select id, utc, kind, reason_code, hash
      from break100_audit
      where user_id = ${context.userId}
      order by utc desc
      limit 40
    `;
  });

export const saveReplayBookmark = createServerFn({ method: "POST" })
  .middleware([authMiddleware])
  .validator((input: { seed: number; symbol: string; config_hash: string }) => input)
  .handler(async ({ context, data }) => {
    const sql = await getSql();
    const id = `${context.userId}-${data.seed}-${data.symbol}`;
    await sql`
      insert into break100_sessions (id, user_id, seed, symbol, config_hash)
      values (${id}, ${context.userId}, ${data.seed}, ${data.symbol}, ${data.config_hash})
      on conflict (id) do update set config_hash = excluded.config_hash
    `;
    return { id };
  });

export const listReplayBookmarks = createServerFn({ method: "GET" })
  .middleware([authMiddleware])
  .handler(async ({ context }) => {
    const sql = await getSql();
    return sql<{
      id: string;
      seed: number;
      symbol: string;
      config_hash: string;
      created_at: string;
    }>`
      select id, seed, symbol, config_hash, created_at
      from break100_sessions
      where user_id = ${context.userId}
      order by created_at desc
      limit 12
    `;
  });
