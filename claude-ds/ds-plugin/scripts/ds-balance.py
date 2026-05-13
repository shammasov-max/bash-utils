#!/usr/bin/env python3
"""Check DeepSeek API balance."""

import os, json, urllib.request, urllib.error

ENV = os.path.expanduser("~/.config/free-claude-code/.env")
API  = "https://api.deepseek.com/user/balance"

def load_key():
    for line in open(ENV):
        if line.startswith("DEEPSEEK_API_KEY="):
            return line.split("=", 1)[1].strip().strip('"')
    raise SystemExit(f"DEEPSEEK_API_KEY not found in {ENV}")

def fetch(key):
    req = urllib.request.Request(API, headers={"Authorization": f"Bearer {key}"})
    with urllib.request.urlopen(req) as r:
        return json.loads(r.read())

def fmt(data):
    if not data.get("is_available"):
        return "⛔ DeepSeek account unavailable"
    lines = ["💰 DeepSeek Balance", "━━━━━━━━━━━━━━━━━━━",
             f"{'Status:':12} ✅ Available"]
    for b in data.get("balance_infos", []):
        c = b.get("currency", "?")
        lines += [
            f"{'Currency:':12} {c}",
            f"{'Total:':12} ${b.get('total_balance', '?')}",
            f"{'Topped up:':12} ${b.get('topped_up_balance', '?')}",
            f"{'Granted:':12} ${b.get('granted_balance', '?')}",
        ]
    lines.append("━━━━━━━━━━━━━━━━━━━")
    return "\n".join(lines)

if __name__ == "__main__":
    try:
        data = fetch(load_key())
        print(fmt(data))
    except urllib.error.HTTPError as e:
        print(f"⚠️ API error (HTTP {e.code})\n{e.read().decode()}")
    except Exception as e:
        print(f"⚠️ Error: {e}")
