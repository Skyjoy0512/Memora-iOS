// Internal D1 adapter. Deliberately has no fetch handler and cannot contact a
// provider. Authentication, purchase verification and authoritative audio/token
// sizing must precede callers of this adapter; none is accepted from iOS.
export class UsageLedger {
  constructor(database) { this.database = database; }

  async reserve(request) {
    const { id, subject, period, idempotency, requestHash, priceRevision,
      entitlementRevision, expiresAt, maxCost, sttSeconds = 0,
      inputTokens = 0, outputTokens = 0, toolCalls = 0 } = request;
    const existing = await this.find(subject, period, idempotency);
    if (existing) return this.match(existing, request);
    try {
      await this.database.prepare(`INSERT INTO reservations
        (id,subject,period,idempotency,request_hash,price_revision,entitlement_revision,
         expires_at,max_cost,stt_seconds,input_tokens,output_tokens,tool_calls)
        VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)`).bind(id, subject, period, idempotency, requestHash,
        priceRevision, entitlementRevision, expiresAt, maxCost, sttSeconds,
        inputTokens, outputTokens, toolCalls).run();
    } catch (error) {
      // A concurrent identical insert is idempotent; a limit failure stays a
      // failure. INSERT OR REPLACE would refund/re-reserve and is forbidden.
      const winner = await this.find(subject, period, idempotency);
      if (!winner) throw error;
      return this.match(winner, request);
    }
    return this.find(subject, period, idempotency);
  }

  find(subject, period, idempotency) {
    return this.database.prepare(`SELECT * FROM reservations
      WHERE subject=? AND period=? AND idempotency=?`).bind(subject, period, idempotency).first();
  }

  match(row, request) {
    // requestHash is server-computed over the complete canonical operation,
    // including original hash, consent revision, price, model and all ceilings.
    if (row.request_hash !== request.requestHash || row.price_revision !== request.priceRevision ||
        row.entitlement_revision !== request.entitlementRevision) {
      throw new Error("Idempotency conflict");
    }
    return row;
  }

  // Only the caller receiving a row may dispatch. A replay receives null, so
  // queue redelivery and server restart never send the same paid operation twice.
  claim(id, subject, period) {
    return this.database.prepare(`UPDATE reservations SET state='running'
      WHERE id=? AND subject=? AND period=? AND state='reserved' RETURNING *`)
      .bind(id, subject, period).first();
  }

  async settle(id, subject, period, actualCost, actualSTT, billingEvidence) {
    return this.database.prepare(`UPDATE reservations SET state='settled',
      actual_cost=?,actual_stt=?,billing_evidence=?
      WHERE id=? AND subject=? AND period=? AND state='running' RETURNING *`)
      .bind(actualCost, actualSTT, billingEvidence, id, subject, period).first();
  }

  // If the provider may have charged, retain the full budget. Cancellation,
  // timeout, missing usage and worker death are never assumed to be free.
  reconcileUnknown(id, subject, period, billingEvidence) {
    return this.database.prepare(`UPDATE reservations SET state='uncertain',
      actual_cost=max_cost,actual_stt=stt_seconds,billing_evidence=?
      WHERE id=? AND subject=? AND period=? AND state='running' RETURNING *`)
      .bind(billingEvidence, id, subject, period).first();
  }

  releaseUnsent(id, subject, period) {
    return this.database.prepare(`UPDATE reservations SET state='released',
      actual_cost=0,actual_stt=0,billing_evidence='not-dispatched'
      WHERE id=? AND subject=? AND period=? AND state='reserved' RETURNING *`)
      .bind(id, subject, period).first();
  }
}
