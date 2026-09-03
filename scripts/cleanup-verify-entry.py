# -*- coding: utf-8 -*-
"""收尾：删除编码验证条目（ENC-VERIFY）与之前的 TEST 噪声条目，生产数据回到无测试噪声状态。"""
import json, os, sys, io

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
HOME = r"C:/Users/hz0704027/AppData/Local/dsh-desktop-app-data/home"

p = os.path.join(HOME, "dsh-twin/learning-events.json")
with open(p, encoding="utf-8") as f:
    d = json.load(f)
before = len(d["events"])
d["events"] = [e for e in d["events"] if e.get("ref") != "ENC-VERIFY"]
with open(p, "w", encoding="utf-8") as f:
    json.dump(d, f, ensure_ascii=False, indent=2)
print(f"learning-events.json: {before} → {len(d['events'])} 条（删除 ENC-VERIFY 验证条目）")
