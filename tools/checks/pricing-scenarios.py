"""Deterministic planning scenarios, not provider calls or a billing ledger."""
import json
from decimal import Decimal as D

plans = [("light", 480, 300), ("pro", 1480, 800), ("unlimited", 2980, 1500), ("team", 3480, 1500)]
rows = []
for name, yen, credits in plans:
    for annual in (False, True):
        months = 12 if annual else 1
        gross = D(yen) * (10 if annual else 1)
        ai_dollars = D(credits) * D("0.005") * months
        for fee in (D("0.15"), D("0.30")):
            net = gross / D("1.10") * (1 - fee)
            row = dict(plan=name, annual=annual, appStoreFee=float(fee), grossYen=float(gross),
                       aiCapUSD=float(ai_dollars), netBeforeOperatingYen=round(float(net), 2),
                       breakEvenUSDJPYBeforeOperating=round(float(net / ai_dollars), 2), margins=[])
            for fx in (160, 200):
                row["margins"].append(dict(USDJPY=fx, AIOnlyRemainingYen=round(float(net - ai_dollars * fx), 2)))
            rows.append(row)
# The discount makes the annual Light plan fragile, not universally profitable.
annual_light = next(r for r in rows if r["plan"] == "light" and r["annual"] and r["appStoreFee"] == 0.30)
assert annual_light["breakEvenUSDJPYBeforeOperating"] == 169.70
assert annual_light["margins"][1]["AIOnlyRemainingYen"] < 0
assert D(12000) * D("0.30") / 1_000_000 + D(800) * D("1.20") / 1_000_000 == D("0.00456")
print(json.dumps({"checkedAt": "2026-10-27", "assumptions": "JPY tax 10%; FX scenarios, not live FX; excludes infrastructure, refunds, labor and abuse", "scenarios": rows}, ensure_ascii=False, indent=2))
