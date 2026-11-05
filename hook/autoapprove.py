#!/usr/bin/env python3
"""Claude Code PermissionRequest hook: auto-allow when the menu bar toggle is on.

State: ~/.config/claude-autoapprove/state.json  {"enabled": bool, "hook": bool, ...}
Log:   ~/.config/claude-autoapprove/decisions.jsonl
Off / missing state / any error -> print nothing -> normal prompt.
Note: Claude Code still evaluates deny + ask rules after an allow, so those
still prompt; the UI clicker in AutoApprove.app handles what's left.
"""
import json
import os
import sys
import time

DIR = os.environ.get("AUTOAPPROVE_DIR", os.path.expanduser("~/.config/claude-autoapprove"))
STATE = os.path.join(DIR, "state.json")
LOG = os.path.join(DIR, "decisions.jsonl")
# AskUserQuestion needs real answers; ExitPlanMode needs updatedInput -> leave to clicker/human.
SKIP = {"AskUserQuestion", "ExitPlanMode"}
ALLOW = {"hookSpecificOutput": {"hookEventName": "PermissionRequest", "decision": {"behavior": "allow"}}}


HEARTBEAT_MAX_AGE = 10  # app writes status.json every ~3 s


def app_alive(status, now=None):
    """Fail closed: approve only while AutoApprove.app is running (fresh heartbeat)."""
    return now is not None and now - status.get("ts", 0) <= HEARTBEAT_MAX_AGE


def decide(payload, state, status=None, now=None):
    if not (state.get("enabled") and state.get("hook", True)):
        return None
    if not app_alive(status or {}, now):
        return None
    if payload.get("tool_name") in SKIP:
        return None
    return ALLOW


def log(payload, decision):
    try:
        os.makedirs(DIR, exist_ok=True)
        with open(LOG, "a") as f:
            f.write(json.dumps({
                "ts": time.strftime("%Y-%m-%dT%H:%M:%S"),
                "src": "hook",
                "tool": payload.get("tool_name"),
                "input": json.dumps(payload.get("tool_input", {}))[:200],
                "cwd": payload.get("cwd"),
                "decision": "allow" if decision else "pass",
            }) + "\n")
    except OSError:
        pass


def load_json(path):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def main():
    try:
        payload = json.load(sys.stdin)
    except ValueError:
        return
    d = decide(payload, load_json(STATE), load_json(os.path.join(DIR, "status.json")), time.time())
    log(payload, d)
    if d:
        print(json.dumps(d))


def selftest():
    p = {"tool_name": "Bash", "tool_input": {"command": "ls"}}
    live, now = {"ts": 1000}, 1003
    on = {"enabled": True}
    assert decide(p, {"enabled": True, "hook": True}, live, now) == ALLOW
    assert decide(p, on, live, now) == ALLOW
    assert decide(p, {"enabled": False, "hook": True}, live, now) is None
    assert decide(p, {"enabled": True, "hook": False}, live, now) is None
    assert decide(p, {}, live, now) is None
    assert decide({"tool_name": "AskUserQuestion"}, on, live, now) is None
    # Fail closed when the app is gone: stale or missing heartbeat.
    assert decide(p, on, {"ts": 1000}, 1011) is None
    assert decide(p, on, {}, now) is None
    assert decide(p, on, live, None) is None
    print("selftest ok")


if __name__ == "__main__":
    selftest() if "--selftest" in sys.argv else main()
