# -*- coding: utf-8 -*-
"""
P3 账本实质测试（HTTP 层状态机）：
注入工具闸产物（L2 阻断记录+待批准审批）→ approve 发授权 → 幂等 → result 回填 → reject → 过期 fail-closed → stats。
结束恢复空账本。
"""
import json, urllib.request, sys, io, os, shutil, time

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
BASE = "http://127.0.0.1:26965"
LEDGER = r"C:/Users/hz0704027/AppData/Local/dsh-desktop-app-data/home/dsh-ledger/ledger.json"
BACKUP = LEDGER + ".p3bak"

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

def inject_blocked(rid, pid, action, scope, expires_in_sec=180):
    """按 check() 的产物结构注入「已阻断记录 + 待批准审批」，模拟工具闸对 L2 操作的裁决。"""
    now_iso = time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime())
    store = json.load(open(LEDGER, encoding="utf-8"))
    store["records"].append({
        "id": rid, "actionType": action, "level": "L2",
        "target": {"scope": scope}, "status": "已阻断", "history": [{"at": now_iso, "status": "已阻断", "via": "工具执行闸"}],
        "createdAt": now_iso,
    })
    store["approvals"].append({
        "id": pid, "recordId": rid, "actionType": action, "targetScope": scope,
        "state": "待批准", "createdAt": now_iso,
        "expiresAt": time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime(time.time() + expires_in_sec)),
    })
    json.dump(store, open(LEDGER, "w", encoding="utf-8"), ensure_ascii=False, indent=2)

if not os.path.exists(LEDGER):
    os.makedirs(os.path.dirname(LEDGER), exist_ok=True)
    json.dump({"records": [], "grants": [], "approvals": []}, open(LEDGER, "w", encoding="utf-8"))
    print("ledger.json 不存在（账本从未落盘），已初始化空账本")
shutil.copy2(LEDGER, BACKUP)
print(f"备份 → {BACKUP}\n")

print("═══ G1 授权审批 → 发授权 ═══")
inject_blocked("A-MEMTEST-1", "P-MEMTEST-1", "发送邮件", "外部:alice@example.com")
st, r = call("POST", "/dsh-ledger/approve", {"approvalId": "P-MEMTEST-1", "via": "web", "expiresInDays": 7})
check("approve 成功", st == 200 and r.get("ok") is True, r.get("error", "")[:40])
grant = r.get("grant", {})
check("授权 grant 生成（7 天有效期）", bool(grant.get("id")) and grant.get("fromRecordId") == "A-MEMTEST-1" and bool(grant.get("expiresAt")))
store = json.load(open(LEDGER, encoding="utf-8"))
rec = next((x for x in store["records"] if x["id"] == "A-MEMTEST-1"), {})
check("记录状态 → 已放行", rec.get("status") == "已放行")

print("═══ G2 幂等：重复 approve 同一令牌 ═══")
st, r2 = call("POST", "/dsh-ledger/approve", {"approvalId": "P-MEMTEST-1", "via": "web"})
check("重复 approve 返回同一授权", st == 200 and r2.get("grant", {}).get("id") == grant.get("id"))
store = json.load(open(LEDGER, encoding="utf-8"))
check("无双授权记录（幂等键去重）", len([g for g in store["grants"] if g.get("fromRecordId") == "A-MEMTEST-1"]) == 1)

print("═══ G3 结果回填 ═══")
st, r = call("POST", "/dsh-ledger/result", {"recordId": "A-MEMTEST-1", "summary": "邮件已发送，客户确认收到"})
check("result 回填成功", st == 200 and r.get("ok") is True, r.get("error", "")[:40])
store = json.load(open(LEDGER, encoding="utf-8"))
rec = next((x for x in store["records"] if x["id"] == "A-MEMTEST-1"), {})
check("记录状态 → 已回填", rec.get("status") == "已回填")

print("═══ G4 驳回路径 ═══")
inject_blocked("A-MEMTEST-2", "P-MEMTEST-2", "删除文件", "外部:重要目录")
st, r = call("POST", "/dsh-ledger/reject", {"approvalId": "P-MEMTEST-2", "by": {"by": "主人", "via": "web"}})
check("reject 成功", st == 200 and r.get("ok") is True, r.get("error", "")[:40])
store = json.load(open(LEDGER, encoding="utf-8"))
rec = next((x for x in store["records"] if x["id"] == "A-MEMTEST-2"), {})
check("记录状态 → 已拒绝", rec.get("status") == "已拒绝")
check("未产生授权", not any(g.get("recordId") == "A-MEMTEST-2" for g in store["grants"]))

print("═══ G5 过期令牌 fail-closed ═══")
inject_blocked("A-MEMTEST-3", "P-MEMTEST-3", "发送邮件", "外部:bob@example.com", expires_in_sec=-10)
st, r = call("POST", "/dsh-ledger/approve", {"approvalId": "P-MEMTEST-3", "via": "web"})
check("过期审批被拒 (400)", st == 400, str(r.get("error", ""))[:40])
store = json.load(open(LEDGER, encoding="utf-8"))
rec = next((x for x in store["records"] if x["id"] == "A-MEMTEST-3"), {})
check("超时记录 fail-closed → 已拒绝", rec.get("status") == "已拒绝", rec.get("status", ""))

print("═══ G6 stats 终态 ═══")
st, r = call("GET", "/dsh-ledger/stats")
s = r.get("stats", {})
check(f"统计: 总 {s.get('total')} / 回填 {s.get('byStatus',{}).get('已回填')} / 拒绝 {s.get('byStatus',{}).get('已拒绝')}",
      s.get("total") == 3 and s.get("byStatus", {}).get("已回填") == 1 and s.get("byStatus", {}).get("已拒绝") == 2,
      "放行是中间态，回填后终态=已回填")
check("gate 挂载健康", r.get("health", {}).get("gateAttached") is True)

shutil.copy2(BACKUP, LEDGER)
print("\n账本已恢复空态")
print(f"\n═══ P3 结果: {len(PASS)} 过 / {len(FAIL)} 败 ═══")
if FAIL:
    print("失败项:", FAIL)
    sys.exit(1)
