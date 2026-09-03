# -*- coding: utf-8 -*-
"""
P2 学习闭环实质测试 v2（按实际设计校正断言）：
候选 situation=信号/say 留空（确认式学习由主人补全措辞）；confirm 不需报告；apply 硬性要求回归报告（fail-closed）。
"""
import json, urllib.request, sys, io, os, shutil, time

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
BASE = "http://127.0.0.1:26965"
HOME = r"C:/Users/hz0704027/AppData/Local/dsh-desktop-app-data/home"
BACKUP = os.path.join(os.path.dirname(os.path.abspath(__file__)), "backup-p2b-" + time.strftime("%Y%m%d-%H%M%S"))

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

os.makedirs(BACKUP, exist_ok=True)
SNAP = {}
for rel in ["dsh-twin/learning-events.json", "dsh-twin/learning-candidates.json", "dsh-twin/cards.json"]:
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
pay = cand.get("payload", {})
check("候选 situation=信号原文", pay.get("situation") == SIG)
check("候选 say 留空待主人补全（确认式学习）", pay.get("say") == "")

print("═══ L2 门禁负例 A：未 confirm 直接 apply ═══")
st, r = call("POST", "/dsh-twin/learning/apply", {"candidateId": cand.get("id", ""), "regressionReportId": ""})
check("未确认候选 apply 被拒 (400 提示先 confirm)", st == 400, r.get("error", "")[:30])

print("═══ L3 门禁负例 B：confirm 后缺回归报告 apply ═══")
st, r = call("POST", "/dsh-twin/learning/confirm", {"candidateId": cand.get("id", ""), "by": "主人"})
check("confirm 通过（设计上不要求报告）", st == 200 and r.get("ok") is True, str(r.get("candidate", {}).get("status")))
st, r = call("POST", "/dsh-twin/learning/apply", {"candidateId": cand.get("id", ""), "regressionReportId": ""})
check("缺回归报告 apply 被 fail-closed 拒绝", st >= 400, f"http {st}（注：报错文案为「{str(r.get('error',''))[:12]}」，语义待改进）")
evs = load("dsh-twin/learning-events.json")["events"]
check("拒绝后事件未被误升级", all(e.get("status") != "已入卡" for e in evs))

print("═══ L4 scripted 回归 → 报告 ═══")
st, r = call("POST", "/dsh-regression/run", {"runner": "scripted"})
report = r.get("report", {})
rid = report.get("id", "")
check(f"回归报告 {rid}: {report.get('passed')}/{report.get('total')} 通过", st == 200 and rid != "" and report.get("passed") == report.get("total"))

print("═══ L5 带报告 + 主人补全措辞 → apply 入卡 ═══")
st, r = call("POST", "/dsh-twin/learning/apply", {
    "candidateId": cand.get("id", ""), "regressionReportId": rid,
    "exemplar": {"situation": "客人催问交付时间", "say": "我先和主人确认当前排期与范围，再给您确定时间", "avoidSay": "不确认范围就直接承诺具体日期"},
})
check("apply 入卡 merged=true", st == 200 and r.get("ok") and r.get("merged") is True, str(r.get("candidate", {}).get("status")))
cards = load("dsh-twin/cards.json")
items = cards["current"]["exemplars"]["items"]
check("cards.json 样例卡落地", len(items) == 1 and "排期" in items[0].get("say", ""), items[0].get("id", "") if items else "")
evs = load("dsh-twin/learning-events.json")["events"]
check("3 条同类事件全部升级「已入卡」", len(evs) == 3 and all(e.get("status") == "已入卡" for e in evs))

print("═══ L6 reject 流程：第二信号 ×3 → 驳回 ═══")
SIG2 = "主人名字写错时要立刻更正并道歉"
cand2 = None
for i in range(3):
    st, r = call("POST", "/dsh-twin/learning/enqueue", {"kind": "纠正", "target": "样例卡", "signal": SIG2, "by": "主人", "ref": f"MEMTEST-P2R-{i+1}"})
    if r.get("promoted"):
        cand2 = r.get("candidate")
check("第二信号晋升候选", cand2 is not None)
if cand2:
    st, r = call("POST", "/dsh-twin/learning/reject", {"candidateId": cand2.get("id", ""), "reason": "测试驳回"})
    check("reject 通过，候选「已驳回」", st == 200 and r.get("candidate", {}).get("status") == "已驳回")
    evs = load("dsh-twin/learning-events.json")["events"]
    sig2evs = [e for e in evs if e.get("ref", "").startswith("MEMTEST-P2R")]
    check("相关 3 条事件全部「已驳回」", len(sig2evs) == 3 and all(e.get("status") == "已驳回" for e in sig2evs))

print("═══ L7 清理还原 ═══")
save("dsh-twin/learning-events.json", {"events": []})
save("dsh-twin/learning-candidates.json", {"candidates": []})
save("dsh-twin/cards.json", SNAP["dsh-twin/cards.json"])
check("学习数据+样例卡还原", load("dsh-twin/cards.json") == SNAP["dsh-twin/cards.json"])

print(f"\n═══ P2 结果: {len(PASS)} 过 / {len(FAIL)} 败 ═══")
if FAIL:
    print("失败项:", FAIL)
    sys.exit(1)
