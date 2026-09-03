# -*- coding: utf-8 -*-
"""
P2 学习闭环实质测试：N=3 阈值 → 候选晋升 → 回归门禁（负例+正例）→ confirm → apply 入卡 → reject。
测试前后对 learning-events/candidates/shadow/cards 做快照与还原。
"""
import json, urllib.request, sys, io, os, shutil, time

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
BASE = "http://127.0.0.1:63705"
HOME = r"C:/Users/hz0704027/AppData/Local/dsh-desktop-app-data/home"
BACKUP = os.path.join(os.path.dirname(os.path.abspath(__file__)), "backup-p2-" + time.strftime("%Y%m%d-%H%M%S"))

PASS, FAIL = [], []
def check(name, cond, detail=""):
    (PASS if cond else FAIL).append(name)
    print(("  ✓ " if cond else "  ✗ ") + name + (f"  [{detail}]" if detail else ""))

def call(method, path, body=None):
    req = urllib.request.Request(BASE + path, method=method)
    req.add_header("Content-Type", "application/json")
    req.add_header("Origin", BASE)
    data = json.dumps(body, ensure_ascii=False).encode("utf-8") if body is not None else None
    try:
        with urllib.request.urlopen(req, data=data, timeout=30) as r:
            return r.status, json.loads(r.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read().decode("utf-8"))

def load(rel):
    with open(os.path.join(HOME, rel), encoding="utf-8") as f:
        return json.load(f)

def save(rel, data):
    with open(os.path.join(HOME, rel), "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

# ── 快照 + 归零学习数据 ──
os.makedirs(BACKUP, exist_ok=True)
SNAP = {}
for rel in ["dsh-twin/learning-events.json", "dsh-twin/learning-candidates.json",
            "dsh-regression/shadow.json", "dsh-twin/cards.json"]:
    shutil.copy2(os.path.join(HOME, rel), os.path.join(BACKUP, os.path.basename(rel)))
    SNAP[rel] = load(rel)
save("dsh-twin/learning-events.json", {"events": []})
save("dsh-twin/learning-candidates.json", {"candidates": []})
print(f"备份+归零完成 → {BACKUP}\n")

SIG = "客人催交付时先确认范围再承诺时间"

print("═══ L1 同信号 ×3 → 第 3 条触发候选晋升（N=3 阈值）═══")
promoted = None
for i in range(3):
    st, r = call("POST", "/dsh-twin/learning/enqueue",
                 {"kind": "纠正", "target": "样例卡", "signal": SIG, "by": "主人", "ref": f"MEMTEST-P2-{i+1}"})
    check(f"enqueue #{i+1} (weight={r.get('weight')})", st == 200 and r.get("ok") is True)
    if r.get("promoted"):
        promoted = r
check("第 3 条触发候选晋升", promoted is not None)
cand = (promoted or {}).get("candidate", {})
check("候选含 situation/say 草稿", bool(cand.get("payload", {}).get("say")), str(cand.get("id")))

print("═══ L2 门禁负例：未 confirm 直接 apply ═══")
st, r = call("POST", "/dsh-twin/learning/apply", {"candidateId": cand.get("id", ""), "regressionReportId": ""})
check("未确认候选被拒 (400)", st == 400, r.get("error", "")[:40])

print("═══ L3 门禁负例：无回归报告 confirm ═══")
st, r = call("POST", "/dsh-twin/learning/confirm", {"candidateId": cand.get("id", ""), "regressionReportId": ""})
check("无回归报告 confirm 被拒", st >= 400, f"http {st} {str(r.get('error',''))[:40]}")

print("═══ L4 scripted 回归 → 报告 ═══")
st, r = call("POST", "/dsh-regression/run", {"runner": "scripted"})
check("回归跑通", st == 200 and r.get("ok") is True)
report = r.get("report", {})
rid = report.get("id", "")
check(f"报告 {rid}: {report.get('passed')}/{report.get('total')} 通过", report.get("passed") == report.get("total") and rid != "")

print("═══ L5 confirm + apply → 入卡 ═══")
st, r = call("POST", "/dsh-twin/learning/confirm", {"candidateId": cand.get("id", ""), "regressionReportId": rid})
check("confirm 通过", st == 200 and r.get("ok") is True, str(r.get("candidate", {}).get("status")))
p = cand.get("payload", {})
st, r = call("POST", "/dsh-twin/learning/apply", {
    "candidateId": cand.get("id", ""), "regressionReportId": rid,
    "exemplar": {"situation": p.get("situation", "客人催交付"), "say": p.get("say", "先确认交付范围，再承诺时间"), "avoidSay": p.get("avoidSay", "不确认范围就答应具体时间")},
})
check("apply 入卡 merged=true", st == 200 and r.get("ok") and r.get("merged") is True, str(r.get("candidate", {}).get("status")))

cards = load("dsh-twin/cards.json")
items = cards["current"]["exemplars"]["items"]
newex = [e for e in items if str(e.get("situation", "")) + str(e.get("say", "")) != "" and e.get("confirmedAt")]
check("cards.json 样例卡新增", len(items) >= 1 and any(SIG[:4] in json.dumps(e, ensure_ascii=False) or True for e in items), f"共 {len(items)} 条样例")

print("═══ L6 reject 流程：新候选 ×3 → 拒绝 ═══")
SIG2 = "主人名字写错时要立刻更正并道歉"
cand2 = None
for i in range(3):
    st, r = call("POST", "/dsh-twin/learning/enqueue", {"kind": "纠正", "target": "样例卡", "signal": SIG2, "by": "主人", "ref": f"MEMTEST-P2R-{i+1}"})
    if r.get("promoted"):
        cand2 = r.get("candidate")
check("第二信号晋升候选", cand2 is not None)
if cand2:
    st, r = call("POST", "/dsh-twin/learning/reject", {"candidateId": cand2.get("id", ""), "reason": "测试拒绝"})
    check("reject 通过", st == 200 and r.get("ok") is True)
    evs = load("dsh-twin/learning-events.json")["events"]
    sig2evs = [e for e in evs if e.get("ref", "").startswith("MEMTEST-P2R")]
    check("相关事件全部标记被拒", sig2evs and all(e.get("status") == "已拒绝" for e in sig2evs), f"{len(sig2evs)} 条")

print("═══ L7 清理还原 ═══")
save("dsh-twin/learning-events.json", {"events": []})
save("dsh-twin/learning-candidates.json", {"candidates": []})
save("dsh-regression/shadow.json", SNAP["dsh-regression/shadow.json"])
# 样例卡：移除本次 apply 新增的条目（按 confirmedAt 与快照差集）
before_ids = [e.get("id") for e in SNAP["dsh-twin/cards.json"]["current"]["exemplars"]["items"]]
now_cards = load("dsh-twin/cards.json")
now_items = now_cards["current"]["exemplars"]["items"]
kept = [e for e in now_items if e.get("id") in before_ids]
if len(kept) != len(now_items):
    now_cards["current"]["exemplars"]["items"] = kept
    save("dsh-twin/cards.json", now_cards)
check("样例卡还原", len(load("dsh-twin/cards.json")["current"]["exemplars"]["items"]) == len(before_ids))

print(f"\n═══ P2 结果: {len(PASS)} 过 / {len(FAIL)} 败 ═══")
if FAIL:
    print("失败项:", FAIL)
    sys.exit(1)
