#!/usr/bin/env python3
"""Claude Code PermissionRequest hook: auto-allow when the menu bar toggle is on.

State: ~/.config/claude-autoapprove/state.json
  {"enabled": bool, "hook": bool, "until": epoch|null, "askRisky": bool, "askPatterns": [regex]|absent}
Log:   ~/.config/claude-autoapprove/decisions.jsonl
Off / expired timer / risky match / bad state / any error -> print nothing -> normal prompt.
Note: Claude Code still evaluates deny + ask rules after an allow, so those
still prompt; the UI clicker in AutoApprove.app handles what's left.
"""
import json
import os
import re
import sys
import time

DIR = os.environ.get("AUTOAPPROVE_DIR", os.path.expanduser("~/.config/claude-autoapprove"))
STATE = os.path.join(DIR, "state.json")
LOG = os.path.join(DIR, "decisions.jsonl")
# Written when a risky command is passed to the user: the app's clicker holds off
# until you press Resume in the menu.
HOLD = os.path.join(DIR, "hold.json")
# AskUserQuestion needs real answers; ExitPlanMode needs updatedInput -> leave to clicker/human.
SKIP = {"AskUserQuestion", "ExitPlanMode"}
ALLOW = {"hookSpecificOutput": {"hookEventName": "PermissionRequest", "decision": {"behavior": "allow"}}}
# Used when state.json has no askPatterns, so improved defaults reach existing installs.
# Broad on purpose: a false match only costs you one click. Not a sandbox.
DEFAULT_PATTERNS = [
    r"(?is)\bgit\b.*\bpush\b.*(\s-[a-z]*f|--force|\s\+\S)",       # force push, incl. -uf and +refspec
    r"(?is)\bgit\b.*\bpush\b.*\b(main|master)\b",                  # push to main/master
    r"(?is)\brm\b(?=.*\s(-\w*r|--recursive))(?=.*\s(-\w*f|--force))",  # rm -rf, -Rf, -r -f, --recursive --force
    r"(?i)\bsudo\b",
]
HEARTBEAT_MAX_AGE = 10  # app writes status.json every ~3 s
MAX_TIMER = 24 * 3600   # an `until` further out than this is a typo (ms?) -> fail closed


def app_alive(status, now=None):
    """Fail closed: approve only while AutoApprove.app is running (fresh heartbeat)."""
    ts = status.get("ts", 0)
    return now is not None and isinstance(ts, (int, float)) and now - ts <= HEARTBEAT_MAX_AGE


def risky(payload, state):
    """Pattern that sends this Bash command back to the user, or None. Bad pattern = risky."""
    if state.get("askRisky") is not True or payload.get("tool_name") != "Bash":
        return None
    cmd = str((payload.get("tool_input") or {}).get("command", ""))
    # Quotes and backslashes don't change what runs: rm "-rf", git push '--force', s\udo.
    cmd = re.sub(r"[\"'\\]", "", cmd)
    pats = state.get("askPatterns")
    if pats is None:
        pats = DEFAULT_PATTERNS
    if not isinstance(pats, list):
        return "askPatterns is not a list"
    for p in pats:
        try:
            if re.search(p, cmd):
                return p
        except (re.error, TypeError):
            return str(p)  # fail closed
    return None


def decide(payload, state, status=None, now=None):
    """(decision, why). decision is ALLOW or None (normal prompt)."""
    # First, regardless of on/off/heartbeat/hook switch: a risky prompt left waiting
    # must keep the clicker away even if auto-approve is turned on later.
    p = risky(payload, state)
    if p:
        return None, p
    if state.get("enabled") is not True or not app_alive(status or {}, now):
        return None, None
    until = state.get("until")
    if until is not None and not (isinstance(until, (int, float)) and now <= until <= now + MAX_TIMER):
        return None, "timer"
    if state.get("hook", True) is not True or payload.get("tool_name") in SKIP:
        return None, None
    return ALLOW, None


def summary(payload):
    """Short human line for the menu's Recent list."""
    tool = str(payload.get("tool_name") or "?")
    inp = payload.get("tool_input")
    inp = inp if isinstance(inp, dict) else {}
    if tool == "Bash":
        return str(inp.get("command", ""))[:80]
    path = inp.get("file_path") or inp.get("notebook_path")
    return os.path.basename(str(path)) if path else tool


def private_open(path, flags):
    """Files under DIR hold command text: owner-only (0600)."""
    return os.open(path, flags, 0o600)


def log(payload, decision, why):
    try:
        os.makedirs(DIR, mode=0o700, exist_ok=True)
        entry = {
            "ts": time.strftime("%Y-%m-%dT%H:%M:%S"),
            "src": "hook",
            "tool": payload.get("tool_name"),
            "summary": summary(payload),
            "input": json.dumps(payload.get("tool_input", {}))[:200],
            "cwd": payload.get("cwd"),
            "decision": "allow" if decision else ("ask" if why and why != "timer" else "pass"),
        }
        if why:
            entry["why"] = why
        with open(LOG, "a", opener=private_open) as f:
            f.write(json.dumps(entry) + "\n")
    except (OSError, TypeError, ValueError):
        pass


def hold(now):
    """Atomic write, so the app never reads a half-written file."""
    try:
        os.makedirs(DIR, mode=0o700, exist_ok=True)
        tmp = HOLD + ".%d.tmp" % os.getpid()
        with open(tmp, "w", opener=private_open) as f:
            json.dump({"ts": now}, f)
        os.replace(tmp, HOLD)
    except OSError:
        pass


def load_json(path):
    try:
        with open(path) as f:
            d = json.load(f)
            return d if isinstance(d, dict) else {}
    except (OSError, ValueError):
        return {}


def main():
    try:
        payload = json.load(sys.stdin)
    except ValueError:
        return
    if not isinstance(payload, dict):
        return
    now = time.time()
    state = load_json(STATE)
    try:
        d, why = decide(payload, state, load_json(os.path.join(DIR, "status.json")), now)
    except Exception:  # noqa: BLE001 - any surprise = normal prompt, and hold the clicker
        d, why = None, "error"
    if why and why != "timer" and state.get("askRisky") is True:
        hold(now)
    log(payload, d, why)
    if d:
        print(json.dumps(d))


def selftest():
    p = {"tool_name": "Bash", "tool_input": {"command": "ls"}}
    live, now = {"ts": 1000}, 1003
    on = {"enabled": True}
    assert decide(p, {"enabled": True, "hook": True}, live, now)[0] == ALLOW
    assert decide(p, on, live, now)[0] == ALLOW
    assert decide(p, {"enabled": False, "hook": True}, live, now)[0] is None
    assert decide(p, {"enabled": True, "hook": False}, live, now)[0] is None
    assert decide(p, {}, live, now)[0] is None
    assert decide(p, {"enabled": "false"}, live, now)[0] is None  # strings are not booleans
    assert decide({"tool_name": "AskUserQuestion"}, on, live, now)[0] is None
    # Fail closed when the app is gone: stale or missing heartbeat.
    assert decide(p, on, {"ts": 1000}, 1011)[0] is None
    assert decide(p, on, {}, now)[0] is None
    assert decide(p, on, live, None)[0] is None
    # Timer: future = allow, past, junk or absurdly far = normal prompt.
    assert decide(p, {"enabled": True, "until": 2000}, live, now)[0] == ALLOW
    assert decide(p, {"enabled": True, "until": 1002}, live, now) == (None, "timer")
    assert decide(p, {"enabled": True, "until": "soon"}, live, now)[0] is None
    assert decide(p, {"enabled": True, "until": now * 1000}, live, now)[0] is None  # milliseconds typo
    # Still-ask patterns: only when askRisky is on, only for Bash.
    force = {"tool_name": "Bash", "tool_input": {"command": "git push --force origin x"}}
    risky_on = {"enabled": True, "askRisky": True}
    assert decide(force, on, live, now)[0] == ALLOW
    assert decide(force, risky_on, live, now)[0] is None
    for c in ["git push -f", "git push -uf origin x", "git -C repo push --force", "git push origin +feature",
              "git push \\\n    --force", "git push origin main", "git -c a=b push origin master",
              "rm -rf build", "rm -fr /", 'rm "-rf" x', "git push '--force'", "s\\udo ls", "SUDO ls", "rm -Rf x", "rm -r -f x", "rm --recursive --force x", "sudo ls"]:
        assert decide({"tool_name": "Bash", "tool_input": {"command": c}}, risky_on, live, now)[0] is None, c
    for c in ["git push origin feature", "git push -u origin feature", "git push --follow-tags",
              "rm -r build", "rm -f x", "ls -la", "git pushd", "git status"]:
        assert decide({"tool_name": "Bash", "tool_input": {"command": c}}, risky_on, live, now)[0] == ALLOW, c
    assert decide({"tool_name": "Write", "tool_input": {"file_path": "/x/sudo"}}, risky_on, live, now)[0] == ALLOW
    assert decide(p, {**risky_on, "askPatterns": ["("]}, live, now)[0] is None  # bad regex: fail closed
    assert decide(p, {**risky_on, "askPatterns": "sudo"}, live, now)[0] is None  # not a list: fail closed
    assert decide(force, {**risky_on, "askPatterns": None}, live, now)[0] is None  # null = defaults
    assert decide(force, {**risky_on, "askPatterns": []}, live, now)[0] == ALLOW
    assert decide(force, {**risky_on, "hook": False}, live, now)[1]  # hook off: still flags it (clicker hold)
    assert decide(force, {"askRisky": True}, {}, now)[1]  # app off/dead: still flags it
    assert summary(force) == "git push --force origin x"
    assert summary({"tool_name": "Edit", "tool_input": {"file_path": "/a/b/c.py"}}) == "c.py"
    assert summary({"tool_name": "Bash", "tool_input": "x"}) == ""
    print("selftest ok")


if __name__ == "__main__":
    selftest() if "--selftest" in sys.argv else main()
