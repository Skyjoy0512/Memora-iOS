#!/usr/bin/env python3
"""Offline planning calculator. No provider calls, purchases or entitlement changes."""
import argparse
import itertools
import json
from decimal import Decimal as D

CHECKED = "2026-11-02"
# USD per transmitted audio minute. Model-page prices; not a signed price lock.
RATES = {
    "cloudflare-whisper": D("0.000453"),
    "cloudflare-turbo": D("0.000513"),
    "groq-turbo": D("0.04") / 60,
    "groq-large-v3": D("0.111") / 60,
    "openai-whisper": D("0.006"),
    "openai-mini-estimate": D("0.003"),
    "deepgram-nova3-multilingual-conservative": D("0.0092"),
    "deepgram-nova3-with-keyterm": D("0.0105"),
}
# name, monthly JPY, cloud minutes, cost credits, retained GB-month (hard-budget proposal)
EXISTING = [("light", 480, 0, 300, 0), ("pro", 1480, 0, 800, 0),
            ("unlimited", 2980, 0, 1500, 0), ("team", 3480, 0, 1500, 5)]
CANDIDATES = [("light", 480, 30, 80, D("0.25")), ("pro", 1480, 300, 300, 1),
              ("unlimited", 2980, 900, 700, 2), ("team", 3480, 900, 900, 5),
              ("cloud-plus", 2480, 1200, 300, 1), ("cloud-max", 7980, 6000, 700, 2)]


def plan_cost(plan, fx, inflation, retry):
    _, _, minutes, credits, gb_month = plan
    # Reserve at the more expensive Groq fallback rate, not only Cloudflare.
    components = dict(stt=D(minutes) * RATES["groq-turbo"],
                      summary_ask_tools=D(credits) * D("0.005"),
                      audio_preprocessing=D(0),  # local; GPU is disabled
                      storage=D(gb_month) * D("0.015"), transfer=D(0),  # R2 Standard egress
                      db_api_queue=D("0.02"), monitoring=D("0.025"))
    subtotal = sum(components.values())
    # Deliberately not a measured bill: enforce service caps before selling it.
    return subtotal * inflation * retry * D("1.10") * fx, components


def scenarios():
    audio = []
    for hours, ratio, provider, fx, inflation, retry in itertools.product(
            (10, 30, 100, 300, 720), (D("0.10"), D("0.25"), D("0.50"), D(1)),
            RATES, (160, 200), (D(1), D("1.5")), (D(1), D("1.25"))):
        minutes = D(hours) * 60 * ratio
        audio.append(dict(hours=hours, transmittedRatio=float(ratio), provider=provider, fx=fx,
                          inflation=float(inflation), retry=float(retry),
                          sttYen=float(minutes * RATES[provider] * fx * inflation * retry)))
    plans = []
    for source, catalog in (("existing-unreleased", EXISTING), ("candidate-unreleased", CANDIDATES)):
        for plan, fee, fx, annual_months, users, inflation, retry in itertools.product(
                catalog, (D("0.15"), D("0.30")), (D(160), D(200)), (0, 10, 11, 12),
                (1, 10, 100, 1000, 10000), (D(1), D("1.5")), (D(1), D("1.25"))):
            cost, components = plan_cost(plan, fx, inflation, retry)
            gross_month = D(plan[1]) * (D(annual_months) / 12 if annual_months else 1)
            net = gross_month / D("1.10") * (1 - fee)
            fixed = D(5) * fx / users  # Workers paid base, ignores free inference grants
            profit = net - cost - fixed
            plans.append(dict(catalog=source, plan=plan[0], monthlyPrice=plan[1],
                              cloudMinutes=plan[2], credits=plan[3], annualPriceMonths=annual_months,
                              fee=float(fee), fx=int(fx), users=users, inflation=float(inflation), retry=float(retry),
                              netYen=float(net), variableCostYen=float(cost), allocatedFixedYen=float(fixed),
                              worstProfitYen=float(profit), margin=float(profit / net),
                              componentsUSD={k: float(v) for k, v in components.items()}))
    return dict(checkedAt=CHECKED, audio=audio, plans=plans)


def markdown(data):
    lines = ["# Audio Intelligence — 原価シナリオ（生成表）", "",
             "`python3 tools/checks/audio-cost-scenarios.py --markdown` で再生成。", "",
             "公式価格の出典・未確定条件は [運用設計](AUDIO_CLOUD_OPERATIONS.md)。", "",
             "## 月720時間を全量クラウドへ送る場合", "",
             "STTのみ、FX200円、再試行・値上げなし。VAD比率は実送信長の仮定で、実測ではない。", "",
             "| API | 10%送信 | 25%送信 | 50%送信 | 100%送信 |", "| --- | ---: | ---: | ---: | ---: |"]
    for provider, rate in RATES.items():
        cells = [f"{D(720) * 60 * r * rate * 200:,.2f}円" for r in (D(".1"), D(".25"), D(".5"), D(1))]
        lines.append("| " + provider + " | " + " | ".join(cells) + " |")
    lines += ["", "## 未提供の候補枠を毎月使い切る場合", "",
              "FX200・手数料30%・税込10%・価格1.5倍・retry1.25倍・追加安全余裕10%。", "",
              "最大変動原価はSTT/要約/Ask AI/ツール/保存/DB/API/queue/監視を含む予算。", 
              "GPU=0（未提供）、R2転送=0、決済手数料は純収入から控除。返金/濫用は10%に含める仮定。",
              "人件費・税務確定・独自ドメイン・追加認証/SMS・有料監視は含まない。", "",
              "| 候補 | 月額 | STT分 | AI credit | 最大変動原価 | 純収入 | 100人時利益 | 利益率 | 1人時利益 |", 
              "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |"]
    for plan in CANDIDATES:
        row = next(r for r in data["plans"] if r["catalog"] == "candidate-unreleased" and r["plan"] == plan[0]
                   and r["fee"] == .30 and r["fx"] == 200 and r["annualPriceMonths"] == 0 and r["users"] == 100
                   and r["inflation"] == 1.5 and r["retry"] == 1.25)
        single_profit = row["worstProfitYen"] - 990
        lines.append(f"| {plan[0]} | {plan[1]:,}円 | {plan[2]:,} | {plan[3]:,} | {row['variableCostYen']:,.2f}円 | {row['netYen']:,.2f}円 | {row['worstProfitYen']:,.2f}円 | {row['margin']:.1%} | {single_profit:,.2f}円 |")
    lines += ["", "無料はcloud枠0、AI credit0。cloudを提供しなくても固定費は運営側の負担。", "",
              "## 固定費と同時利用", "",
              "| 人数 | Workers固定費合計（FX160 / 200） | 1人への配賦（FX200） | 15分jobが全員から来る時の最低wave数（同時8） |", 
              "| --- | ---: | ---: | ---: |"]
    for users in (1, 10, 100, 1000, 10000):
        lines.append(f"| {users:,} | 800円 / 1,000円 | {D(1000) / users:,.2f}円 | {(users + 7) // 8:,} |")
    lines += ["", "各wave所要時間は実測待ち。待機中は端末の原本を保持し、容量/金額/queue長の上限で受付を止める。", "",
              "## 年額の安全性（100人、同じstress条件、月額換算利益）", "",
              "| 候補 | 10か月価格/年 | 11か月価格/年 | 12か月価格/年 |", "| --- | ---: | ---: | ---: |"]
    for plan in CANDIDATES:
        profits = []
        for months in (10, 11, 12):
            row = next(r for r in data["plans"] if r["catalog"] == "candidate-unreleased" and r["plan"] == plan[0]
                       and r["fee"] == .30 and r["fx"] == 200 and r["annualPriceMonths"] == months and r["users"] == 100
                       and r["inflation"] == 1.5 and r["retry"] == 1.25)
            profits.append(f"{row['worstProfitYen']:,.2f}円")
        lines.append("| " + plan[0] + " | " + " | ".join(profits) + " |")
    lines += ["", "候補は既存プランの変更ではない。1人では多くが固定費で赤字。100人表の黒字だけで販売しない。", 
              "低価格tierの全費用を含む黒字保証には、実際の有料人数・固定費・予算ゲートの確認が必要。", 
              "年額は当初12か月価格を候補とし、値引きは枠/固定費/返金の実測後に再判断する。", "",
              f"全組合せ: audio {len(data['audio']):,}件、plan {len(data['plans']):,}件。通常実行でJSON出力。", ""]
    return "\n".join(lines)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--markdown", action="store_true")
    args = parser.parse_args()
    data = scenarios()
    assert len(data["audio"]) == 1280 and len(data["plans"]) == 3200
    assert D(720) * 60 * RATES["cloudflare-turbo"] * 200 == D("4432.320000")
    assert any(r["worstProfitYen"] < 0 for r in data["plans"] if r["users"] == 1)
    assert any(r["worstProfitYen"] < 0 for r in data["plans"] if r["catalog"] == "existing-unreleased")
    if args.check:
        print(f"Audio cost scenarios: PASS ({len(data['audio'])} audio / {len(data['plans'])} plan cases; losses preserved; planning only)")
    elif args.markdown:
        print(markdown(data))
    else:
        print(json.dumps(data, ensure_ascii=False, indent=2))
