import re
import sys

sys.stdout.reconfigure(encoding="utf-8")

with open("src/events/civilization_event_db.gd", "r", encoding="utf-8") as f:
    text = f.read()

all_consequence_keys = set()
events_with_special_consequences = []
consequences_matches = re.finditer(r'"title":\s*"([^"]+)".*?"consequences":\s*(\{[^}]+\})', text, re.DOTALL)

for cm in consequences_matches:
    ch_text = cm.group(1)
    cons_str = cm.group(2)
    keys = re.findall(r'"([^"]+)":', cons_str)
    all_consequence_keys.update(keys)
    special = [k for k in keys if any(s in k.lower() for s in ["unlock", "tame", "seed", "build", "practice", "upgrade", "role", "deer", "wolf"])]
    if special:
        events_with_special_consequences.append(("", "", ch_text, cons_str))

print("=== ALL UNIQUE CONSEQUENCE KEYS ===")
for k in sorted(all_consequence_keys):
    print(" ", k)

print(f"\n=== EVENTS WITH UNLOCK/SPECIAL CONSEQUENCES ({len(events_with_special_consequences)}) ===")
for ev_id, ev_title, ch_text, cons_str in events_with_special_consequences:
    print(f"[{ev_id}] {ev_title}")
    print(f"   Выбор: {ch_text}")
    print(f"   Последствия: {cons_str}\n")
