# -*- coding: utf-8 -*-
"""扫描生产数据中的乱码（GBK 字节被误解码后固化的字符），评估可恢复性。"""
import json, os, sys, io

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

HOME = r"C:/Users/hz0704027/AppData/Local/dsh-desktop-app-data/home"
FILES = [
    "dsh-twin/learning-events.json",
    "dsh-twin/learning-candidates.json",
    "dsh-twin/exemplar-drafts.json",
    "dsh-twin/cards.json",
    "dsh-twin/cards-history.json",
    "dsh-twin/twin-config.json",
    "dsh-regression/shadow.json",
    "dsh-actors/registry.json",
]

def looks_garbled(s: str) -> bool:
    if "\ufffd" in s:
        return True
    # GBK 字节按 CP1252/Latin-1 误读的典型签名：西里尔/带变音符的拉丁字符密集出现
    bad_chars = set("ͻҪʱֱӴӦһֱӷظٵȵں˾׼ÿ佫ѽѡȡԱۺϺעⱸ¼Ϣʾƥ䲻ɵС")
    hits = sum(1 for c in s if c in bad_chars)
    return hits >= 3

def try_recover(s: str):
    """latin-1/cp1252 回编 → GBK 解码；成功返回恢复文本，失败返回 None。"""
    for enc in ("cp1252", "latin-1"):
        try:
            raw = s.encode(enc)
        except UnicodeEncodeError:
            continue
        try:
            rec = raw.decode("gbk")
        except UnicodeDecodeError:
            continue
        if "\ufffd" not in rec and rec != s:
            return rec
    return None

def walk(node, path, out):
    if isinstance(node, dict):
        for k, v in node.items():
            walk(v, f"{path}.{k}", out)
    elif isinstance(node, list):
        for i, v in enumerate(node):
            walk(v, f"{path}[{i}]", out)
    elif isinstance(node, str):
        if looks_garbled(node):
            out.append((path, node, try_recover(node)))

total_bad = 0
for rel in FILES:
    p = os.path.join(HOME, rel)
    if not os.path.exists(p):
        print(f"── {rel}: (不存在)")
        continue
    with open(p, encoding="utf-8") as f:
        try:
            data = json.load(f)
        except Exception as e:
            print(f"── {rel}: JSON 解析失败 {e}")
            continue
    found = []
    walk(data, "$", found)
    print(f"── {rel}: {len(found)} 处乱码")
    for path, bad, rec in found[:12]:
        mark = "可恢复" if rec else "不可恢复"
        print(f"   [{mark}] {path}")
        print(f"      原文: {bad[:60]}")
        if rec:
            print(f"      恢复: {rec[:60]}")
    if len(found) > 12:
        print(f"   ...另有 {len(found)-12} 处")
    total_bad += len(found)

print(f"\n总计乱码字段: {total_bad}")
