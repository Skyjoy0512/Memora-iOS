-- Private accounting core for SQLite/D1. No HTTP route, provider key or live
-- price catalog is installed by this migration. Amounts are integer micro-USD.
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS global_budgets (
  period TEXT PRIMARY KEY,
  closes_at INTEGER NOT NULL,
  enabled INTEGER NOT NULL DEFAULT 0 CHECK(enabled IN (0,1)),
  cost_cap INTEGER NOT NULL CHECK(cost_cap BETWEEN 0 AND 1000000000000),
  used_cost INTEGER NOT NULL DEFAULT 0 CHECK(used_cost >= 0),
  reserved_cost INTEGER NOT NULL DEFAULT 0 CHECK(reserved_cost >= 0),
  request_cap INTEGER NOT NULL CHECK(request_cap BETWEEN 0 AND 10000000),
  requests INTEGER NOT NULL DEFAULT 0 CHECK(requests >= 0 AND requests <= request_cap),
  parallel_cap INTEGER NOT NULL DEFAULT 8 CHECK(parallel_cap BETWEEN 1 AND 100),
  running INTEGER NOT NULL DEFAULT 0 CHECK(running >= 0 AND running <= parallel_cap),
  CHECK(used_cost + reserved_cost <= cost_cap)
) STRICT;

CREATE TABLE IF NOT EXISTS accounts (
  subject TEXT NOT NULL,
  period TEXT NOT NULL REFERENCES global_budgets(period),
  verified_until INTEGER NOT NULL,
  entitlement_revision TEXT NOT NULL,
  cost_cap INTEGER NOT NULL CHECK(cost_cap BETWEEN 0 AND 1000000000),
  ai_cap INTEGER NOT NULL CHECK(ai_cap BETWEEN 0 AND cost_cap),
  stt_cap INTEGER NOT NULL CHECK(stt_cap BETWEEN 0 AND 2592000),
  used_cost INTEGER NOT NULL DEFAULT 0 CHECK(used_cost >= 0),
  reserved_cost INTEGER NOT NULL DEFAULT 0 CHECK(reserved_cost >= 0),
  used_ai INTEGER NOT NULL DEFAULT 0 CHECK(used_ai >= 0),
  reserved_ai INTEGER NOT NULL DEFAULT 0 CHECK(reserved_ai >= 0),
  used_stt INTEGER NOT NULL DEFAULT 0 CHECK(used_stt >= 0),
  reserved_stt INTEGER NOT NULL DEFAULT 0 CHECK(reserved_stt >= 0),
  request_cap INTEGER NOT NULL CHECK(request_cap BETWEEN 0 AND 100000),
  requests INTEGER NOT NULL DEFAULT 0 CHECK(requests >= 0 AND requests <= request_cap),
  running INTEGER NOT NULL DEFAULT 0 CHECK(running BETWEEN 0 AND 1),
  PRIMARY KEY(subject, period),
  CHECK(used_cost + reserved_cost <= cost_cap),
  CHECK(used_ai + reserved_ai <= ai_cap),
  CHECK(used_stt + reserved_stt <= stt_cap)
) STRICT;

CREATE TABLE IF NOT EXISTS prices (
  revision TEXT PRIMARY KEY,
  provider_model TEXT NOT NULL,
  enabled INTEGER NOT NULL DEFAULT 0 CHECK(enabled IN (0,1)),
  valid_until INTEGER NOT NULL,
  kind TEXT NOT NULL CHECK(kind IN ('stt','llm','tool')),
  audio_hour INTEGER NOT NULL DEFAULT 0 CHECK(audio_hour BETWEEN 0 AND 100000000),
  input_million INTEGER NOT NULL DEFAULT 0 CHECK(input_million BETWEEN 0 AND 100000000),
  output_million INTEGER NOT NULL DEFAULT 0 CHECK(output_million BETWEEN 0 AND 100000000),
  per_tool INTEGER NOT NULL DEFAULT 0 CHECK(per_tool BETWEEN 0 AND 100000000)
) STRICT;

CREATE TABLE IF NOT EXISTS reservations (
  id TEXT PRIMARY KEY,
  subject TEXT NOT NULL,
  period TEXT NOT NULL,
  idempotency TEXT NOT NULL,
  request_hash TEXT NOT NULL,
  price_revision TEXT NOT NULL REFERENCES prices(revision),
  entitlement_revision TEXT NOT NULL,
  expires_at INTEGER NOT NULL,
  state TEXT NOT NULL DEFAULT 'reserved' CHECK(state IN ('reserved','running','settled','released','uncertain')),
  max_cost INTEGER NOT NULL CHECK(max_cost BETWEEN 1 AND 100000000),
  stt_seconds INTEGER NOT NULL DEFAULT 0 CHECK(stt_seconds BETWEEN 0 AND 900),
  input_tokens INTEGER NOT NULL DEFAULT 0 CHECK(input_tokens BETWEEN 0 AND 120000),
  output_tokens INTEGER NOT NULL DEFAULT 0 CHECK(output_tokens BETWEEN 0 AND 16000),
  tool_calls INTEGER NOT NULL DEFAULT 0 CHECK(tool_calls BETWEEN 0 AND 1),
  actual_cost INTEGER CHECK(actual_cost >= 0 AND actual_cost <= max_cost),
  actual_stt INTEGER CHECK(actual_stt >= 0 AND actual_stt <= stt_seconds),
  billing_evidence TEXT,
  FOREIGN KEY(subject, period) REFERENCES accounts(subject, period),
  UNIQUE(subject, period, idempotency)
) STRICT;

CREATE INDEX IF NOT EXISTS open_reservations ON reservations(subject, period, state);
CREATE INDEX IF NOT EXISTS expired_reservations ON reservations(state, expires_at);
CREATE TABLE IF NOT EXISTS ledger_events (
  sequence INTEGER PRIMARY KEY,
  reservation_id TEXT NOT NULL REFERENCES reservations(id),
  state TEXT NOT NULL,
  cost INTEGER NOT NULL,
  at INTEGER NOT NULL DEFAULT (unixepoch())
) STRICT;

CREATE TRIGGER IF NOT EXISTS reserve_before BEFORE INSERT ON reservations BEGIN
  SELECT CASE WHEN NEW.state != 'reserved' OR NEW.actual_cost IS NOT NULL OR NEW.actual_stt IS NOT NULL
    OR NEW.billing_evidence IS NOT NULL OR NEW.expires_at <= unixepoch()
    OR NEW.expires_at > unixepoch() + 3600 THEN RAISE(ABORT, 'invalid reservation') END;
  SELECT CASE WHEN NOT EXISTS (
    SELECT 1 FROM accounts a JOIN global_budgets g USING(period)
    WHERE a.subject=NEW.subject AND a.period=NEW.period AND a.verified_until > unixepoch()
      AND a.entitlement_revision=NEW.entitlement_revision AND g.enabled=1 AND g.closes_at > unixepoch()
  ) THEN RAISE(ABORT, 'entitlement or service unavailable') END;
  SELECT CASE WHEN NOT EXISTS (
    SELECT 1 FROM prices p WHERE p.revision=NEW.price_revision AND p.enabled=1 AND p.valid_until > unixepoch()
    AND ((p.kind='stt' AND NEW.stt_seconds>0 AND NEW.input_tokens=0 AND NEW.output_tokens=0 AND NEW.tool_calls=0 AND p.audio_hour>0)
      OR (p.kind='llm' AND NEW.stt_seconds=0 AND NEW.input_tokens>0 AND NEW.output_tokens>0 AND NEW.tool_calls=0
        AND p.input_million>0 AND p.output_million>0)
      OR (p.kind='tool' AND NEW.stt_seconds=0 AND NEW.input_tokens=0 AND NEW.output_tokens=0 AND NEW.tool_calls=1 AND p.per_tool>0))
    AND NEW.max_cost >= (NEW.stt_seconds*p.audio_hour+3599)/3600
      + (NEW.input_tokens*p.input_million+999999)/1000000
      + (NEW.output_tokens*p.output_million+999999)/1000000 + NEW.tool_calls*p.per_tool
  ) THEN RAISE(ABORT, 'unknown price or insufficient reservation') END;
  SELECT CASE WHEN (SELECT count(*) FROM reservations WHERE subject=NEW.subject AND period=NEW.period
    AND state IN ('reserved','running')) >= 4 THEN RAISE(ABORT, 'too many pending requests') END;
END;

-- CHECK constraints abort the entire statement, including both budget updates,
-- if either user or fleet limits would be exceeded by concurrent reservations.
CREATE TRIGGER IF NOT EXISTS reserve_after AFTER INSERT ON reservations BEGIN
  UPDATE accounts SET reserved_cost=reserved_cost+NEW.max_cost,
    reserved_ai=reserved_ai+CASE WHEN NEW.stt_seconds=0 THEN NEW.max_cost ELSE 0 END,
    reserved_stt=reserved_stt+NEW.stt_seconds, requests=requests+1
    WHERE subject=NEW.subject AND period=NEW.period;
  UPDATE global_budgets SET reserved_cost=reserved_cost+NEW.max_cost, requests=requests+1 WHERE period=NEW.period;
  INSERT INTO ledger_events(reservation_id,state,cost) VALUES(NEW.id,'reserved',NEW.max_cost);
END;

CREATE TRIGGER IF NOT EXISTS transition_before BEFORE UPDATE ON reservations BEGIN
  SELECT CASE WHEN NEW.id!=OLD.id OR NEW.subject!=OLD.subject OR NEW.period!=OLD.period
    OR NEW.idempotency!=OLD.idempotency OR NEW.request_hash!=OLD.request_hash
    OR NEW.price_revision!=OLD.price_revision OR NEW.entitlement_revision!=OLD.entitlement_revision
    OR NEW.max_cost!=OLD.max_cost OR NEW.stt_seconds!=OLD.stt_seconds
    OR NEW.input_tokens!=OLD.input_tokens OR NEW.output_tokens!=OLD.output_tokens OR NEW.tool_calls!=OLD.tool_calls
    OR NEW.expires_at!=OLD.expires_at THEN RAISE(ABORT, 'immutable reservation') END;
  SELECT CASE WHEN NOT ((OLD.state='reserved' AND NEW.state IN ('running','released'))
    OR (OLD.state='running' AND NEW.state IN ('settled','uncertain')))
    THEN RAISE(ABORT, 'invalid transition') END;
  SELECT CASE WHEN NEW.state='running' AND (NEW.expires_at<=unixepoch()
    OR NEW.actual_cost IS NOT NULL OR NEW.actual_stt IS NOT NULL OR NEW.billing_evidence IS NOT NULL
    OR NOT EXISTS (SELECT 1 FROM accounts a JOIN global_budgets g USING(period) JOIN prices p ON p.revision=NEW.price_revision
      WHERE a.subject=NEW.subject AND a.period=NEW.period AND a.verified_until>unixepoch()
      AND a.entitlement_revision=NEW.entitlement_revision AND g.enabled=1 AND g.closes_at>unixepoch()
      AND p.enabled=1 AND p.valid_until>unixepoch())) THEN RAISE(ABORT, 'execution revoked') END;
  SELECT CASE WHEN NEW.state IN ('settled','uncertain','released') AND
    (NEW.actual_cost IS NULL OR NEW.actual_stt IS NULL OR NEW.billing_evidence IS NULL OR length(NEW.billing_evidence)=0)
    THEN RAISE(ABORT, 'missing settlement evidence') END;
  SELECT CASE WHEN NEW.state='released' AND (NEW.actual_cost!=0 OR NEW.actual_stt!=0)
    THEN RAISE(ABORT, 'unsent release only') END;
  SELECT CASE WHEN NEW.state='uncertain' AND (NEW.actual_cost!=NEW.max_cost OR NEW.actual_stt!=NEW.stt_seconds)
    THEN RAISE(ABORT, 'uncertain usage keeps full ceiling') END;
END;

CREATE TRIGGER IF NOT EXISTS start_after AFTER UPDATE ON reservations WHEN NEW.state='running' BEGIN
  UPDATE accounts SET running=running+1 WHERE subject=NEW.subject AND period=NEW.period;
  UPDATE global_budgets SET running=running+1 WHERE period=NEW.period;
  INSERT INTO ledger_events(reservation_id,state,cost) VALUES(NEW.id,'running',NEW.max_cost);
END;

CREATE TRIGGER IF NOT EXISTS settle_after AFTER UPDATE ON reservations WHEN NEW.state IN ('settled','uncertain','released') BEGIN
  UPDATE accounts SET reserved_cost=reserved_cost-NEW.max_cost, used_cost=used_cost+NEW.actual_cost,
    reserved_ai=reserved_ai-CASE WHEN NEW.stt_seconds=0 THEN NEW.max_cost ELSE 0 END,
    used_ai=used_ai+CASE WHEN NEW.stt_seconds=0 THEN NEW.actual_cost ELSE 0 END,
    reserved_stt=reserved_stt-NEW.stt_seconds, used_stt=used_stt+NEW.actual_stt,
    running=running-CASE WHEN OLD.state='running' THEN 1 ELSE 0 END
    WHERE subject=NEW.subject AND period=NEW.period;
  UPDATE global_budgets SET reserved_cost=reserved_cost-NEW.max_cost, used_cost=used_cost+NEW.actual_cost,
    running=running-CASE WHEN OLD.state='running' THEN 1 ELSE 0 END WHERE period=NEW.period;
  INSERT INTO ledger_events(reservation_id,state,cost) VALUES(NEW.id,NEW.state,NEW.actual_cost);
END;

CREATE TRIGGER IF NOT EXISTS reservation_no_delete BEFORE DELETE ON reservations BEGIN
  SELECT RAISE(ABORT, 'ledger retention required');
END;
CREATE TRIGGER IF NOT EXISTS events_no_update BEFORE UPDATE ON ledger_events BEGIN
  SELECT RAISE(ABORT, 'append only ledger');
END;
CREATE TRIGGER IF NOT EXISTS events_no_delete BEFORE DELETE ON ledger_events BEGIN
  SELECT RAISE(ABORT, 'append only ledger');
END;
CREATE TRIGGER IF NOT EXISTS price_revision_immutable BEFORE UPDATE ON prices BEGIN
  SELECT CASE WHEN NEW.revision!=OLD.revision OR NEW.provider_model!=OLD.provider_model
    OR NEW.valid_until!=OLD.valid_until OR NEW.kind!=OLD.kind OR NEW.audio_hour!=OLD.audio_hour
    OR NEW.input_million!=OLD.input_million OR NEW.output_million!=OLD.output_million
    OR NEW.per_tool!=OLD.per_tool THEN RAISE(ABORT, 'new price requires new revision') END;
END;
