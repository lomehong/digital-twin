# -*- coding: utf-8 -*-
"""删除生产数据中的乱码条目（先备份 → 按 id 删 → 复扫验证）。"""
import json, os, sys, io, shutil, time

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
HOME = r"C:/Users/hz0704027/AppData/Local/dsh-desktop-app-data/home"
BACKUP = os.path.join(os.path.dirname(os.path.abspath(__file__)), "backup-prod-" + time.strftime("%Y%m%d-%H%M%S"))

def has_bad(s):
    s = str(s)
    if "\ufffd" in s: return True
    bad = set("ͻҪʱֱӴӦʲôܸ׼˵Ե")
    return sum(1 for c in s if c in bad) >= 3

def entry_bad(e):
    return any(has_bad(v) for v in e.values() if isinstance(v, str))

# 1) 备份
os.makedirs(BACKUP, exist_ok=True)
targets = [
    ("dsh-twin/learning-events.json", "events"),
    ("dsh-twin/learning-candidates.json", "candidates"),
    ("dsh-regression/shadow.json", "pairs"),
]
for rel, key in targets:
    shutil.copy2(os.path.join(HOME, rel), os.path.join(BACKUP, os.path.basename(rel)))
print(f"备份完成 → {BACKUP}")

# 2) 删除乱码条目
removed = {}
for rel, key in targets:
    p = os.path.join(HOME, rel)
    with open(p, encoding="utf-8") as f:
        data = json.load(f)
    before = len(data[key])
    dropped = [e.get("id") for e in data[key] if entry_bad(e)]
    data[key] = [e for e in data[key] if not entry_bad(e)]
    with open(p, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    removed[rel] = (before, len(data[key]), dropped)
    print(f"{rel}: {before} → {len(data[key])} 条，删除 id: {dropped}")

# 3) 复扫验证
import subprocess
r = subprocess.run([sys.executable, os.path.join(os.path.dirname(os.path.abspath(__file__)), "scan-mojibake.py")],
                   capture_output=True, text=True, encoding="utf-8")
print("── 复扫结果 ──")
print(r.stdout.strip().splitlines()[-1] if r.stdout.strip() else "(无输出)")
print("PASS" if "总计乱码字段: 0" in r.stdout else "FAIL")
