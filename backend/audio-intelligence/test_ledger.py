"""Real SQLite transaction/race tests for the private accounting schema, not D1 E2E."""
import concurrent.futures
import pathlib
import sqlite3
import tempfile
import time
import unittest

SCHEMA = pathlib.Path(__file__).with_name("ledger.sql").read_text()


class LedgerChecks(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory(prefix="memora-ledger-")
        self.path = pathlib.Path(self.folder.name) / "ledger.sqlite"
        self.db = sqlite3.connect(self.path, timeout=10)
        self.db.executescript(SCHEMA)
        future = int(time.time()) + 7200
        self.db.execute("INSERT INTO global_budgets(period,closes_at,enabled,cost_cap,request_cap) VALUES('month',?,1,10000,1000)", (future,))
        for name in ("alice", "bob"):
            self.db.execute("""INSERT INTO accounts(subject,period,verified_until,entitlement_revision,
                cost_cap,ai_cap,stt_cap,request_cap) VALUES(?,'month',?,'verified-purchase-v1',5000,3000,1800,100)""", (name, future))
        self.db.execute("""INSERT INTO prices(revision,provider_model,enabled,valid_until,kind,audio_hour)
            VALUES('reviewed-stt','fixture',1,?,'stt',40000)""", (future,))
        self.db.execute("""INSERT INTO prices(revision,provider_model,enabled,valid_until,kind,input_million,output_million)
            VALUES('reviewed-llm','fixture',1,?,'llm',300000,1200000)""", (future,))
        self.db.commit()

    def tearDown(self):
        self.db.close()
        self.folder.cleanup()

    def reserve(self, identifier="first", subject="alice", db=None, price="reviewed-stt", cost=1000,
                seconds=60, inputs=0, outputs=0):
        connection = db or self.db
        with connection:
            connection.execute("""INSERT INTO reservations(id,subject,period,idempotency,request_hash,
                price_revision,entitlement_revision,expires_at,max_cost,stt_seconds,input_tokens,output_tokens)
                VALUES(?,?,'month',?,'server-hash',?,'verified-purchase-v1',?,?,?,?,?)""",
                (identifier, subject, identifier, price, int(time.time()) + 600, cost, seconds, inputs, outputs))

    def start(self, identifier="first"):
        with self.db:
            self.db.execute("UPDATE reservations SET state='running' WHERE id=? AND state='reserved'", (identifier,))

    def state(self, subject="alice"):
        return self.db.execute("SELECT used_cost,reserved_cost,used_stt,reserved_stt,running FROM accounts WHERE subject=?", (subject,)).fetchone()

    def test_settle_and_duplicate(self):
        self.reserve()
        self.start()
        with self.db:
            self.db.execute("UPDATE reservations SET state='settled',actual_cost=700,actual_stt=60,billing_evidence='provider-receipt' WHERE id='first'")
        self.assertEqual(self.state(), (700, 0, 60, 0, 0))
        with self.assertRaises(sqlite3.IntegrityError):
            self.reserve()
        with self.assertRaises(sqlite3.IntegrityError), self.db:
            self.db.execute("UPDATE reservations SET state='settled',actual_cost=700 WHERE id='first'")
        self.assertEqual(self.state(), (700, 0, 60, 0, 0))

    def test_unknown_usage_never_refunds(self):
        self.reserve()
        self.start()
        with self.assertRaises(sqlite3.IntegrityError), self.db:
            self.db.execute("UPDATE reservations SET state='released',actual_cost=0,actual_stt=0,billing_evidence='timeout' WHERE id='first'")
        with self.db:
            self.db.execute("UPDATE reservations SET state='uncertain',actual_cost=max_cost,actual_stt=stt_seconds,billing_evidence='timeout-unknown' WHERE id='first'")
        self.assertEqual(self.state(), (1000, 0, 60, 0, 0))

    def test_unsent_release(self):
        self.reserve()
        with self.db:
            self.db.execute("UPDATE reservations SET state='released',actual_cost=0,actual_stt=0,billing_evidence='not-sent' WHERE id='first'")
        self.assertEqual(self.state(), (0, 0, 0, 0, 0))

    def test_unknown_and_underpriced_models(self):
        for price, cost in (("unknown", 1000), ("reviewed-stt", 1)):
            with self.assertRaises(sqlite3.IntegrityError):
                self.reserve(price=price, cost=cost)
        self.assertEqual(self.state(), (0, 0, 0, 0, 0))

    def test_entitlement_and_price_revocation(self):
        self.reserve()
        for sql in ("UPDATE accounts SET verified_until=0 WHERE subject='alice'",
                    "UPDATE prices SET enabled=0 WHERE revision='reviewed-stt'"):
            with self.db:
                self.db.execute(sql)
            with self.assertRaises(sqlite3.IntegrityError):
                self.start()
        self.assertEqual(self.state(), (0, 1000, 0, 60, 0))

    def test_global_rollback_and_concurrency(self):
        with self.db:
            self.db.execute("UPDATE global_budgets SET cost_cap=1000")

        def attempt(subject):
            db = sqlite3.connect(self.path, timeout=10)
            db.execute("PRAGMA foreign_keys=ON")
            try:
                self.reserve(identifier=subject, subject=subject, db=db)
                return True
            except sqlite3.IntegrityError:
                return False
            finally:
                db.close()

        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(attempt, ("alice", "bob")))
        self.assertEqual(sum(results), 1)
        self.assertEqual(self.db.execute("SELECT sum(reserved_cost) FROM accounts").fetchone()[0], 1000)
        self.assertEqual(self.db.execute("SELECT reserved_cost FROM global_budgets").fetchone()[0], 1000)

    def test_parallel_and_user_limits(self):
        self.reserve("first")
        self.reserve("second")
        self.start("first")
        with self.assertRaises(sqlite3.IntegrityError):
            self.start("second")
        with self.assertRaises(sqlite3.IntegrityError):
            self.reserve("large", cost=4000)
        self.assertEqual(self.state(), (0, 2000, 0, 120, 1))

    def test_stt_and_ai_have_independent_caps(self):
        with self.db:
            self.db.execute("UPDATE accounts SET stt_cap=0 WHERE subject='alice'")
        with self.assertRaises(sqlite3.IntegrityError):
            self.reserve()
        self.reserve(price="reviewed-llm", cost=1300, seconds=0, inputs=1000, outputs=800)
        self.assertEqual(self.db.execute("SELECT reserved_ai,reserved_stt FROM accounts WHERE subject='alice'").fetchone(), (1300, 0))

    def test_expiry_and_immutable_audit(self):
        self.reserve()
        for sql in ("UPDATE reservations SET expires_at=0", "DELETE FROM reservations",
                    "UPDATE ledger_events SET cost=0", "UPDATE prices SET audio_hour=0 WHERE revision='reviewed-stt'"):
            with self.assertRaises(sqlite3.IntegrityError), self.db:
                self.db.execute(sql)

    def test_expired_reservation_cannot_dispatch(self):
        self.reserve()
        later = int(time.time()) + 601
        self.db.create_function("unixepoch", 0, lambda: later)
        with self.assertRaises(sqlite3.IntegrityError):
            self.start()
        self.assertEqual(self.state(), (0, 1000, 0, 60, 0))
        with self.db:
            self.db.execute("UPDATE reservations SET state='released',actual_cost=0,actual_stt=0,billing_evidence='expired-unsent'")
        self.assertEqual(self.state(), (0, 0, 0, 0, 0))

    def test_global_parallel_cap_rolls_back_user_claim(self):
        with self.db:
            self.db.execute("UPDATE global_budgets SET parallel_cap=1")
        self.reserve("alice-run", subject="alice")
        self.reserve("bob-run", subject="bob")
        self.start("alice-run")
        with self.assertRaises(sqlite3.IntegrityError):
            self.start("bob-run")
        self.assertEqual(self.state("bob"), (0, 1000, 0, 60, 0))
        self.assertEqual(self.db.execute("SELECT state FROM reservations WHERE id='bob-run'").fetchone()[0], "reserved")


if __name__ == "__main__":
    unittest.main(verbosity=2)
