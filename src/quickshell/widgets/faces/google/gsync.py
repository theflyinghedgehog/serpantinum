#!/usr/bin/env python3
"""Google Calendar + Tasks helper for the Serpantinum agenda widget.

Standard library only. Usage:
  gsync.py auth                    sign in (opens the browser), saves a refresh token
  gsync.py fetch                   print events (next 7 days) + open tasks as JSON
  gsync.py complete LIST_ID TASK_ID
  gsync.py add "Title" [YYYY-MM-DD]
  gsync.py signout

Files:
  ~/.config/serpantinum/google/client_secret.json   OAuth "Desktop app" client from Google Cloud
  ~/.config/serpantinum/google/token.json           refresh token (chmod 600)
  ~/.cache/serpantinum/google/data.json             last successful fetch
"""
import base64, datetime as dt, hashlib, http.server, json, os, secrets, socket
import sys, threading, urllib.error, urllib.parse, urllib.request, webbrowser

CONF_DIR = os.path.expanduser("~/.config/serpantinum/google")
CACHE_DIR = os.path.expanduser("~/.cache/serpantinum/google")
CLIENT_FILE = os.path.join(CONF_DIR, "client_secret.json")
TOKEN_FILE = os.path.join(CONF_DIR, "token.json")
CACHE_FILE = os.path.join(CACHE_DIR, "data.json")
SCOPES = "https://www.googleapis.com/auth/calendar.readonly https://www.googleapis.com/auth/tasks"
AUTH_URL = "https://accounts.google.com/o/oauth2/v2/auth"
TOKEN_URL = "https://oauth2.googleapis.com/token"
CAL = "https://www.googleapis.com/calendar/v3"
TASKS = "https://tasks.googleapis.com/tasks/v1"
DAYS_AHEAD = 14


class SignedOut(Exception):
    pass


def out(obj):
    print(json.dumps(obj, ensure_ascii=False))


def load_client():
    if not os.path.exists(CLIENT_FILE):
        return None
    with open(CLIENT_FILE) as f:
        data = json.load(f)
    return data.get("installed") or data.get("web")


def save_json(path, obj, private=False):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(obj, f, ensure_ascii=False)
    if private:
        os.chmod(tmp, 0o600)
    os.replace(tmp, path)


def post_form(url, fields):
    req = urllib.request.Request(url, data=urllib.parse.urlencode(fields).encode(),
                                 headers={"Content-Type": "application/x-www-form-urlencoded"})
    with urllib.request.urlopen(req, timeout=20) as r:
        return json.load(r)


# auth
def cmd_auth():
    client = load_client()
    if not client:
        print("Missing " + CLIENT_FILE)
        print("Download your OAuth 'Desktop app' client JSON from Google Cloud and save it there.")
        return 1
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        port = s.getsockname()[1]
    redirect = "http://127.0.0.1:%d" % port
    verifier = secrets.token_urlsafe(64)
    challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).rstrip(b"=").decode()
    state = secrets.token_urlsafe(16)
    url = AUTH_URL + "?" + urllib.parse.urlencode({
        "client_id": client["client_id"], "redirect_uri": redirect, "response_type": "code",
        "scope": SCOPES, "access_type": "offline", "prompt": "consent",
        "code_challenge": challenge, "code_challenge_method": "S256", "state": state,
    })
    result = {}

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
            if "code" not in q and "error" not in q:
                self.send_response(404); self.end_headers(); return
            result.update({k: v[0] for k, v in q.items()})
            ok = "code" in q and q.get("state", [""])[0] == state
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.end_headers()
            msg = "Signed in. You can close this tab." if ok else "Sign-in failed. Check the terminal."
            self.wfile.write(("<html><body style='font-family:sans-serif;padding:3em'><h2>%s</h2></body></html>" % msg).encode())
            threading.Thread(target=self.server.shutdown, daemon=True).start()

        def log_message(self, *a):
            pass

    server = http.server.HTTPServer(("127.0.0.1", port), Handler)
    print("Opening Google sign-in in your browser.")
    print("If nothing opens, paste this link into the browser:\n\n" + url + "\n")
    webbrowser.open(url)
    timer = threading.Timer(300, server.shutdown)
    timer.start()
    server.serve_forever()
    timer.cancel()

    if result.get("state") != state or "code" not in result:
        print("Sign-in failed or timed out: " + result.get("error", "no response"))
        return 1
    tok = post_form(TOKEN_URL, {
        "code": result["code"], "client_id": client["client_id"],
        "client_secret": client.get("client_secret", ""), "redirect_uri": redirect,
        "grant_type": "authorization_code", "code_verifier": verifier,
    })
    if "refresh_token" not in tok:
        print("Google did not return a refresh token. Remove the app's access at "
              "https://myaccount.google.com/permissions and run sign-in again.")
        return 1
    tok["expires_at"] = dt.datetime.now().timestamp() + tok.get("expires_in", 3600) - 60
    save_json(TOKEN_FILE, tok, private=True)
    print("Done! The widget will refresh within a few seconds.")
    return 0


def access_token():
    client = load_client()
    if not client:
        raise SignedOut("no_client")
    if not os.path.exists(TOKEN_FILE):
        raise SignedOut("signed_out")
    with open(TOKEN_FILE) as f:
        tok = json.load(f)
    if tok.get("access_token") and tok.get("expires_at", 0) > dt.datetime.now().timestamp():
        return tok["access_token"]
    try:
        new = post_form(TOKEN_URL, {
            "client_id": client["client_id"], "client_secret": client.get("client_secret", ""),
            "refresh_token": tok["refresh_token"], "grant_type": "refresh_token",
        })
    except urllib.error.HTTPError as e:
        if e.code in (400, 401):   # invalid_grant: revoked or expired
            os.remove(TOKEN_FILE)
            raise SignedOut("signed_out")
        raise
    tok["access_token"] = new["access_token"]
    tok["expires_at"] = dt.datetime.now().timestamp() + new.get("expires_in", 3600) - 60
    save_json(TOKEN_FILE, tok, private=True)
    return tok["access_token"]


def api(method, url, params=None, body=None):
    if params:
        url += "?" + urllib.parse.urlencode(params)
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method, headers={
        "Authorization": "Bearer " + access_token(), "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=20) as r:
        raw = r.read()
        return json.loads(raw) if raw else {}


# fetch
def parse_time(obj):
    """-> (local datetime, all_day)"""
    if "dateTime" in obj:
        s = obj["dateTime"].replace("Z", "+00:00")
        return dt.datetime.fromisoformat(s).astimezone(), False
    d = dt.date.fromisoformat(obj["date"])
    return dt.datetime(d.year, d.month, d.day).astimezone(), True


def cmd_fetch():
    now = dt.datetime.now().astimezone()
    today = now.date()
    t_min = now.replace(hour=0, minute=0, second=0, microsecond=0)
    t_max = t_min + dt.timedelta(days=DAYS_AHEAD)

    events = []
    cals = api("GET", CAL + "/users/me/calendarList", {"minAccessRole": "reader"}).get("items", [])
    for c in cals:
        if not c.get("selected") and not c.get("primary"):
            continue
        items = api("GET", CAL + "/calendars/" + urllib.parse.quote(c["id"], safe="") + "/events", {
            "timeMin": t_min.isoformat(), "timeMax": t_max.isoformat(),
            "singleEvents": "true", "orderBy": "startTime", "maxResults": 100,
        }).get("items", [])
        for e in items:
            if e.get("status") == "cancelled" or "start" not in e:
                continue
            start, all_day = parse_time(e["start"])
            end, _ = parse_time(e.get("end", e["start"]))
            if end <= now and not all_day:
                continue                      # already finished today
            if all_day and end.date() <= today:
                continue
            day = max(start.date(), today)    # ongoing / multi-day events show on today
            events.append({
                "id": e.get("id", ""), "title": e.get("summary") or "(no title)",
                "calendar": c.get("summaryOverride") or c.get("summary", ""),
                "color": c.get("backgroundColor", "#888888"),
                "allDay": all_day, "day": day.isoformat(),
                "start": int(start.timestamp() * 1000), "end": int(end.timestamp() * 1000),
                "location": e.get("location", ""), "link": e.get("htmlLink", ""),
            })
    events.sort(key=lambda x: (x["day"], not x["allDay"], x["start"]))

    tasks = []
    lists = api("GET", TASKS + "/users/@me/lists", {"maxResults": 100}).get("items", [])
    for lst in lists:
        items = api("GET", TASKS + "/lists/" + lst["id"] + "/tasks", {
            "showCompleted": "false", "showHidden": "false", "maxResults": 100}).get("items", [])
        for t in items:
            if not t.get("title", "").strip() or t.get("parent"):
                continue                      # skip empty rows and subtasks
            tasks.append({
                "id": t["id"], "listId": lst["id"], "list": lst.get("title", ""),
                "title": t["title"], "due": (t.get("due") or "")[:10],
                "notes": t.get("notes", ""), "position": t.get("position", ""),
            })
    tasks.sort(key=lambda x: (x["due"] == "", x["due"], x["list"], x["position"]))

    data = {"ok": True, "state": "ok", "events": events, "tasks": tasks,
            "lists": [{"id": l["id"], "title": l.get("title", "")} for l in lists],
            "updated": int(now.timestamp() * 1000)}
    save_json(CACHE_FILE, data)
    out(data)
    return 0


def cmd_complete(list_id, task_id):
    api("PATCH", TASKS + "/lists/" + list_id + "/tasks/" + task_id, body={"status": "completed"})
    out({"ok": True})
    return 0


def cmd_add(title, due=""):
    body = {"title": title}
    if due:
        body["due"] = due + "T00:00:00.000Z"
    api("POST", TASKS + "/lists/@default/tasks", body=body)
    out({"ok": True})
    return 0


def cmd_signout():
    if os.path.exists(TOKEN_FILE):
        os.remove(TOKEN_FILE)
    out({"ok": True})
    return 0


def main(argv):
    cmd = argv[1] if len(argv) > 1 else "fetch"
    try:
        if cmd == "auth":
            return cmd_auth()
        if cmd == "fetch":
            return cmd_fetch()
        if cmd == "complete" and len(argv) >= 4:
            return cmd_complete(argv[2], argv[3])
        if cmd == "add" and len(argv) >= 3:
            return cmd_add(argv[2], argv[3] if len(argv) > 3 else "")
        if cmd == "signout":
            return cmd_signout()
        out({"ok": False, "state": "error", "error": "unknown command"})
        return 2
    except SignedOut as e:
        out({"ok": False, "state": str(e)})
    except urllib.error.HTTPError as e:
        detail = e.read().decode(errors="replace")[:300]
        out({"ok": False, "state": "error", "error": "HTTP %d: %s" % (e.code, detail)})
    except (urllib.error.URLError, socket.timeout, TimeoutError) as e:
        out({"ok": False, "state": "offline", "error": str(e)})
    except Exception as e:
        out({"ok": False, "state": "error", "error": repr(e)})
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
