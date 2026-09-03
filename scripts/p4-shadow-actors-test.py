# -*- coding: utf-8 -*-
"""
P4 影子对 + 注册表实质测试：
影子：添加→查重(409)→待判→判定(主人/分身)→统计。
注册表：provision 新建即 stranger（不推断身份）→ 幂等 → 角色变更需主人凭据（fail-closed）→ 多渠道 bind → 实体 merge。
结束还原 registry.json + shadow.json。
"""
import json, urllib.request, sys, io, os, shutil, time

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
BASE = "http://127.0.0.1:26965"
HOME = r"C:/Users/hz0704027/AppData/Local/dsh-desktop-app-data/home"
REG = os.path.join(HOME, "dsh-actors", "registry.json")
SHADOW = os.path.join(HOME, "dsh-regression", "shadow.json")

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

BAK = {}
for p in (REG, SHADOW):
    BAK[p] = json.load(open(p, encoding="utf-8")) if os.path.exists(p) else None
json.dump({"pairs": []}, open(SHADOW, "w", encoding="utf-8"), ensure_ascii=False)
print("快照完成，影子对已归零（统计断言从零起算）\n")

# 注入 master 实体（claimMaster 无 HTTP 路由，直接按存储结构注入）
now_iso = time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime())
reg = BAK[REG] if BAK[REG] is not None else {"entities": []}
reg["entities"] = [e for e in reg.get("entities", []) if e.get("role") != "master"]
reg["entities"].append({
    "id": "ent-master-memtest", "createdAt": now_iso, "role": "master",
    "bindings": [{"channel": "wecom", "userId": "user-MASTER-MEMTEST", "boundAt": now_iso}],
    "displayName": "主人测试",
})
json.dump(reg, open(REG, "w", encoding="utf-8"), ensure_ascii=False, indent=2)

print("═══ S1 影子对：添加 → 查重 → 待判 ═══")
st, r = call("POST", "/dsh-regression/shadow/add", {
    "visitorInput": "MEMTEST 什么时候能交付？",
    "masterReply": "周五前给初稿，先出范围确认单",
    "twinReply": "周五前给初稿，先和您对齐范围",
    "ref": "MEMTEST-P4",
})
check("add 影子对", st == 200 and r.get("ok") is True, r.get("error", "")[:30])
pid = r.get("pair", {}).get("id", "")
st, r = call("POST", "/dsh-regression/shadow/add", {
    "visitorInput": "MEMTEST 什么时候能交付？",
    "masterReply": "周五前给初稿，先出范围确认单",
    "twinReply": "周五前给初稿，先和您对齐范围", "ref": "MEMTEST-P4-dup",
})
check("重复指纹 add → 409 查重拦截", st == 409 and r.get("duplicate") is True, f"http {st}")
st, r = call("GET", "/dsh-regression/shadow/pending")
pend = r.get("pairs", r.get("pending", []))
check("待判列表包含新对", any(p.get("id") == pid for p in pend) if isinstance(pend, list) else False, f"待判 {len(pend) if isinstance(pend, list) else '?'} 条")

print("═══ S2 影子判定与统计 ═══")
st, r = call("POST", "/dsh-regression/shadow/judge", {"pairId": pid, "judged": "主人"})
check("判定「主人」（分身答对）", st == 200 and r.get("ok") is True, r.get("error", "")[:30])
st, r2 = call("POST", "/dsh-regression/shadow/add", {
    "visitorInput": "MEMTEST 可以无条件退款吗？",
    "masterReply": "退款需要走审批，7 天内未拆封可退",
    "twinReply": "可以随时全额退款", "ref": "MEMTEST-P4b",
})
pid2 = r2.get("pair", {}).get("id", "")
call("POST", "/dsh-regression/shadow/judge", {"pairId": pid2, "judged": "分身"})
st, r = call("GET", "/dsh-regression/shadow/stats")
s = r.get("stats", {})
check(f"统计 samples={s.get('samples')} confusionRate={s.get('confusionRate')}",
      s.get("samples") == 2 and s.get("breakdown", {}).get("主人") == 1 and s.get("breakdown", {}).get("分身") == 1,
      json.dumps(s, ensure_ascii=False)[:80])

print("═══ A1 provision：新建一律 stranger（不推断身份）═══")
st, r = call("POST", "/dsh-actors/provision", {"channel": "wecom", "userId": "user-MEMTEST-A", "displayName": "测试客户"})
ent = r.get("entity", {})
check("provision 新建 → stranger", st == 200 and r.get("created") is True and ent.get("role") == "stranger")
eid = ent.get("id", "")
st, r = call("POST", "/dsh-actors/provision", {"channel": "wecom", "userId": "user-MEMTEST-A"})
check("重复 provision 幂等（不新建）", st == 200 and r.get("created") is False and r.get("entity", {}).get("id") == eid)

print("═══ A2 角色变更 fail-closed ═══")
st, r = call("POST", "/dsh-actors/role", {"entityId": eid, "role": "customer"})
check("无凭据 → 403", st == 403, r.get("error", "")[:20])
st, r = call("POST", "/dsh-actors/role", {"entityId": eid, "role": "customer", "masterChannel": "wecom", "masterUserId": "user-NOTMASTER"})
check("冒充主人 → 403", st == 403, r.get("error", "")[:20])
st, r = call("POST", "/dsh-actors/role", {"entityId": eid, "role": "customer", "masterChannel": "wecom", "masterUserId": "user-MASTER-MEMTEST"})
check("真实主人凭据 → 改为 customer", st == 200 and r.get("ok") is True)

print("═══ A3 多渠道 bind + merge ═══")
st, r = call("POST", "/dsh-actors/bind", {"entityId": eid, "channel": "feishu", "userId": "fs-MEMTEST-A"})
check("绑定第二渠道", st == 200 and r.get("ok") is True)
st, r = call("POST", "/dsh-actors/provision", {"channel": "feishu", "userId": "fs-MEMTEST-A"})
check("第二渠道解析回同一实体", st == 200 and r.get("entity", {}).get("id") == eid and r.get("created") is False)
st, r = call("POST", "/dsh-actors/provision", {"channel": "wecom", "userId": "user-MEMTEST-B"})
eid2 = r.get("entity", {}).get("id", "")
st, r = call("POST", "/dsh-actors/merge", {"sourceId": eid2, "targetId": eid})
check("merge 实体", st == 200 and r.get("ok") is True, r.get("error", "")[:30])
st, r = call("POST", "/dsh-actors/provision", {"channel": "wecom", "userId": "user-MEMTEST-B"})
check("被并实体解析指向存活实体", r.get("entity", {}).get("id") == eid)

print("═══ A4 列表与还原 ═══")
st, r = call("GET", "/dsh-actors/entities")
ents = r.get("entities", [])
check("entities 列表非空且含 master", any(e.get("role") == "master" for e in ents), f"共 {len(ents)} 实体")
json.dump(BAK[REG], open(REG, "w", encoding="utf-8"), ensure_ascii=False, indent=2) if BAK[REG] is not None else os.remove(REG)
if BAK[SHADOW] is not None:
    json.dump(BAK[SHADOW], open(SHADOW, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
print("registry + shadow 已还原")

print(f"\n═══ P4 结果: {len(PASS)} 过 / {len(FAIL)} 败 ═══")
if FAIL:
    print("失败项:", FAIL)
    sys.exit(1)
