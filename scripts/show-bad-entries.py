# -*- coding: utf-8 -*-
"""打印待删除的坏条目完整内容，确认删除边界。"""
import json, os, sys, io

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
HOME = r"C:/Users/hz0704027/AppData/Local/dsh-desktop-app-data/home"

def show(rel, pick):
    p = os.path.join(HOME, rel)
    with open(p, encoding="utf-8") as f:
        data = json.load(f)
    print(f"═══ {rel} ═══")
    for item in pick(data):
        print(json.dumps(item, ensure_ascii=False, indent=1)[:500])
    print()

def has_bad(s):
    if "\ufffd" in s: return True
    bad = set("ͻҪʱֱӴӦʲôܸ׼˵Ե")
    return sum(1 for c in s if c in bad) >= 3

show("dsh-twin/learning-events.json", lambda d: [
    {"id": e["id"], "sig": e["sig"], "kind": e["kind"], "status": e["status"], "by": e.get("by"), "at": e.get("at")}
    for e in d["events"] if has_bad(e.get("sig","")) or has_bad(e.get("target","")) or has_bad(e.get("by",""))
])
show("dsh-twin/learning-candidates.json", lambda d: [
    {"id": c["id"], "kind": c.get("kind"), "sig": c.get("sig"), "status": c.get("status")}
    for c in d["candidates"] if has_bad(str(c.get("kind",""))) or has_bad(str(c.get("sig","")))
])
show("dsh-regression/shadow.json", lambda d: [
    {"id": p["id"], "visitorInput": p["visitorInput"], "masterReply": p["masterReply"], "verdict": p.get("verdict")}
    for p in d["pairs"] if has_bad(p.get("visitorInput","")) or has_bad(p.get("masterReply",""))
])
# 全量条目数，评估删除占比
for rel, key in [("dsh-twin/learning-events.json","events"),("dsh-twin/learning-candidates.json","candidates"),("dsh-regression/shadow.json","pairs")]:
    with open(os.path.join(HOME, rel), encoding="utf-8") as f:
        d = json.load(f)
    print(f"{rel}: 共 {len(d[key])} 条")
