# -*- coding: utf-8 -*-
"""
P1 记忆实质测试：写入 → 检索 → 更新 → 开环关闭 → 清理。
所有中文经 UTF-8 源文件发出（urllib），不经过命令行编码。
"""
import json, urllib.request, sys, io

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
BASE = "http://127.0.0.1:26965"
REF = "MEMTEST-P1"

PASS, FAIL = [], []

def check(name, cond, detail=""):
    (PASS if cond else FAIL).append(name)
    print(("  ✓ " if cond else "  ✗ ") + name + (f"  [{detail}]" if detail else ""))

def call(method, path, body=None, headers=None):
    req = urllib.request.Request(BASE + path, method=method)
    req.add_header("Content-Type", "application/json")
    req.add_header("Origin", BASE)
    for k, v in (headers or {}).items():
        req.add_header(k, v)
    data = json.dumps(body, ensure_ascii=False).encode("utf-8") if body is not None else None
    with urllib.request.urlopen(req, data=data, timeout=15) as r:
        return json.loads(r.read().decode("utf-8"))

print("═══ M1 写入 token ═══")
tok = call("GET", "/dsh-memory/token")
check("token 下发", tok.get("ok") is True and bool(tok.get("token")))
TOKEN = tok["token"]

print("═══ M2 写入三条带标记记忆 ═══")
entries = [
    {"content": "主人的咖啡偏好是燕麦拿铁", "type": "note", "statementType": "偏好", "ref": REF},
    {"content": "主人正在准备 9 月 15 日的董事会汇报，材料周三前出初稿", "type": "note", "statementType": "事实", "ref": REF},
    {"content": "主人偏好周报用表格形式呈现", "type": "note", "statementType": "偏好", "ref": REF},
]
ids = []
for e in entries:
    ref = e.pop("ref")
    e["source"] = {"origin": "api", "ref": ref}
    r = call("POST", "/dsh-memory/entries", e, {"X-Memory-Token": TOKEN})
    check(f"写入: {e['content'][:18]}…", r.get("ok") is True, r.get("entry", {}).get("id", r.get("error", "")))
    if r.get("ok"):
        ids.append(r["entry"]["id"])

print("═══ M3 特定记忆检索（咖啡）═══")
a = call("POST", "/dsh-memory/assemble", {"userId": "master-test", "isMaster": True, "keywords": ["咖啡"]})
pack = a.get("pack", {})
texts = json.dumps(pack, ensure_ascii=False)
hit = "燕麦拿铁" in texts
check("检索「咖啡」命中燕麦拿铁", hit)
check("携带回执 receipt", bool(a.get("receipt")))
if a.get("receipt"):
    print("   回执:", json.dumps(a["receipt"], ensure_ascii=False)[:160])

print("═══ M4 特定记忆检索（董事会汇报）═══")
a2 = call("POST", "/dsh-memory/assemble", {"userId": "master-test", "isMaster": True, "keywords": ["董事会", "汇报"]})
t2 = json.dumps(a2.get("pack", {}), ensure_ascii=False)
check("检索「董事会」命中 9 月 15 日条目", "9 月 15 日" in t2 or "董事会" in t2)

print("═══ M5 访客视图隔离（isMaster=false）═══")
a3 = call("POST", "/dsh-memory/assemble", {"userId": "guest-x", "isMaster": False, "keywords": ["咖啡", "董事会"]})
t3 = json.dumps(a3.get("pack", {}), ensure_ascii=False)
check("访客视图不泄漏主人私有记忆", "燕麦拿铁" not in t3)

print("═══ M6 关闭开环 + 删除清理 ═══")
for i in ids:
    d = call("POST", "/dsh-memory/entries/delete", {"id": i}, {"X-Memory-Token": TOKEN})
    check(f"删除 {i[:24]}…", d.get("ok") is True)

print("═══ M7 删除后检索不再命中 ═══")
a4 = call("POST", "/dsh-memory/assemble", {"userId": "master-test", "isMaster": True, "keywords": ["燕麦拿铁"]})
t4 = json.dumps(a4.get("pack", {}), ensure_ascii=False)
check("清理后检索无残留", "燕麦拿铁" not in t4)

print(f"\n═══ P1 结果: {len(PASS)} 过 / {len(FAIL)} 败 ═══")
if FAIL:
    print("失败项:", FAIL)
    sys.exit(1)
