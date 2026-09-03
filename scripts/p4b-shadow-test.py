# -*- coding: utf-8 -*-
"""P4b 影子对测试（修正：完整三元组查重、pid 取自 pair.id、stats 按 samples/confusionRate 断言）。"""
import json, urllib.request, sys, io, os, shutil

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
BASE = "http://127.0.0.1:26965"
SHADOW = r"C:/Users/hz0704027/AppData/Local/dsh-desktop-app-data/home/dsh-regression/shadow.json"

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
        with urllib.request.urlopen(req, data=data, timeout=15) as r:
            return r.status, json.loads(r.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read().decode("utf-8"))

BAK = json.load(open(SHADOW, encoding="utf-8")) if os.path.exists(SHADOW) else {"pairs": []}
json.dump({"pairs": []}, open(SHADOW, "w", encoding="utf-8"), ensure_ascii=False)
print("影子对已归零（快照留待还原）\n")

print("═══ S1 添加 → 查重 → 待判 ═══")
TRI = {"visitorInput": "MEMTEST 什么时候能交付？", "masterReply": "周五前给初稿，先出范围确认单", "twinReply": "周五前给初稿，先和您对齐范围", "ref": "MEMTEST-P4"}
st, r = call("POST", "/dsh-regression/shadow/add", TRI)
pid = r.get("pair", {}).get("id", "")
check("add 完整盲测对", st == 200 and r.get("ok") is True and pid != "")
st, r = call("POST", "/dsh-regression/shadow/add", TRI)
check("同指纹完整三元组 → 409 查重拦截", st == 409 and r.get("duplicate") is True, f"http {st}")
st, r = call("GET", "/dsh-regression/shadow/pending")
pend = r.get("pairs", r.get("pending", []))
check("待判列表包含新对", any(p.get("id") == pid for p in pend), f"待判 {len(pend)} 条")

print("═══ S2 判定：主人答对 1 + 分身答错 1 → confusionRate=0.5 ═══")
st, r = call("POST", "/dsh-regression/shadow/judge", {"pairId": pid, "judged": "主人"})
check("判定「主人」（盲选选中原稿）", st == 200 and r.get("pair", {}).get("judged") == "主人")
st, r2 = call("POST", "/dsh-regression/shadow/add", {
    "visitorInput": "MEMTEST 可以无条件退款吗？",
    "masterReply": "退款需走审批，7 天内未拆封可退",
    "twinReply": "可以随时全额退款", "ref": "MEMTEST-P4b",
})
pid2 = r2.get("pair", {}).get("id", "")
st, r = call("POST", "/dsh-regression/shadow/judge", {"pairId": pid2, "judged": "分身"})
check("判定「分身」（盲选选中分身=分辨不出）", st == 200 and r.get("pair", {}).get("judged") == "分身")
st, r = call("POST", "/dsh-regression/shadow/judge", {"pairId": pid, "judged": "弃权"})
check("判定后不可改（防事后美化指标）", r.get("pair", {}).get("judged") == "主人", str(r.get("error", ""))[:20])
st, r = call("GET", "/dsh-regression/shadow/stats")
s = r.get("stats", {})
check(f"统计 samples={s.get('samples')} confusionRate={s.get('confusionRate')}",
      s.get("samples") == 2 and s.get("confusionRate") == 0.5 and s.get("breakdown", {}).get("主人") == 1 and s.get("breakdown", {}).get("分身") == 1)

json.dump(BAK, open(SHADOW, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
print("\n影子对已还原快照")
print(f"\n═══ P4b 结果: {len(PASS)} 过 / {len(FAIL)} 败 ═══")
if FAIL:
    print("失败项:", FAIL)
    sys.exit(1)
