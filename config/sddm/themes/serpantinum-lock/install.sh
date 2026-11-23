#!/usr/bin/env bash
# Builds the serpantinum-lock SDDM theme from your current Serpantinum setup
# (wallpaper, colours, font, avatar, lock layout) and installs it.
#
#   ./install.sh            install to /usr/share/sddm/themes/serpantinum and set it as SDDM's theme
#   ./install.sh --preview  build into ~/.cache and open a test window, installs nothing
#
# Run it as your normal user, it asks for sudo itself.
# Run it again after changing the wallpaper, theme, avatar or lock layout.
set -euo pipefail

if [ "${EUID}" -eq 0 ]; then
    echo "Run this as your normal user, not with sudo. It asks for sudo when it needs it." >&2
    exit 1
fi

HERE="$(dirname "$(realpath "$0")")"
SRC="$HERE"
DEST=/usr/share/sddm/themes/serpantinum
SERP_DIR="${SERPANTINUM_DIR:-$HOME/.local/share/serpantinum/src}"
MODE="install"
[ "${1:-}" = "--preview" ] && MODE="preview"

if [ "$MODE" = "preview" ]; then
    BUILD="$HOME/.cache/serpantinum/sddm-preview"
    rm -rf "$BUILD"
    mkdir -p "$BUILD"
else
    BUILD="$(mktemp -d)"
    trap 'rm -rf "$BUILD"' EXIT
fi

cp -r "$SRC"/. "$BUILD/"
rm -f "$BUILD/install.sh"
mkdir -p "$BUILD/fonts" "$BUILD/avatars" "$BUILD/shaders"

# Hyprland's logical screen size = the canvas Serpantinum lays the lock screen out on.
HYPR_MON="$(hyprctl monitors -j 2>/dev/null || echo '[]')"

python3 - "$BUILD" "$SERP_DIR" "$USER" "$HYPR_MON" <<'PY'
import json, os, shutil, subprocess, sys, glob, time

build, serp_dir, user, hypr_mon = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
home = os.path.expanduser("~")
state = os.environ.get("QS_STATE_DIR", f"{home}/.local/state/serpantinum")
cache = os.environ.get("QS_CACHE_DIR", f"{home}/.cache/serpantinum")
settings_path = os.environ.get("QS_SETTINGS", f"{home}/.config/serpantinum/settings.json")

def load(path):
    try:
        with open(path) as f:
            return json.load(f)
    except Exception:
        return {}

def obj(d, k):
    v = d.get(k) if isinstance(d, dict) else None
    return v if isinstance(v, dict) else {}

settings = load(settings_path)
theme = obj(settings, "theme")
general = obj(settings, "general")
notif = obj(settings, "notifications")

# colours: same source choice as ThemeBackend.qml
if "matugen" in theme:
    matugen = theme.get("matugen") is True
else:
    matugen = theme.get("activePreset", "Matugen") == "Matugen"
files = [f"{state}/qs_matugen_colors.json", f"{state}/qs_colors.json"] if matugen \
        else [f"{state}/qs_colors.json", f"{state}/qs_matugen_colors.json"]
colors = {}
for p in files:
    c = load(p)
    c = c.get("colors", c) if isinstance(c, dict) else {}
    if c:
        colors = c
        print(f"colours:    {p}")
        break
custom = theme.get("colors") or theme.get("palette")
if not matugen and isinstance(custom, dict):
    colors = {**colors, **custom}

def hexof(v):
    if isinstance(v, str): return v
    if isinstance(v, dict):
        return v.get("hex") or v.get("color") or (v.get("default") or {}).get("hex")
    return None

blur_bg = bool(theme.get("blurBackground", False))
liquid = blur_bg and theme.get("blurStyle") == "liquid"
conf = {
    "background": "background.png",
    "fontFamily": theme.get("fontFamily", "Adwaita Mono"),
    "borderRadius": theme.get("borderRadius", 8),
    "elementOpacity": 1.0,
    "panelOpacity": 1.0,
    "blurBackground": str(blur_bg).lower(),
    "liquidGlass": str(liquid).lower(),
    "dnd": str(bool(notif.get("dnd", False))).lower(),
    "showEmptyGraphic": str(bool(notif.get("showEmptyGraphic", True))).lower(),
    "timeFormat": "HH:mm:ss",
}
try:
    pct = float(theme.get("elementOpacity", 100))
    conf["elementOpacity"] = 0.1 if liquid else max(0.0, min(1.0, pct / 100.0))
except Exception:
    pass
try:
    conf["timeFormat"] = settings["bar"]["time"]["format"]
except Exception:
    pass

# lock layout (LockLayoutStore)
FP_SHIFT = 69  # SDDM has no fingerprint unlock, so Serpantinum's "no fingerprint" layout applies
DEFAULTS_FP = [("widget:weather", 20, 20), ("widget:cpu", 20, 218), ("widget:ram", 214, 218), ("widget:temp", 20, 386),
               ("widget:disk", 214, 386), ("avatar", 540, 20), ("user", 450, 236), ("lockstatus", 645, 236),
               ("password", 450, 288), ("keyboard", 600, 364), ("battery", 685, 364), ("fingerprint", 640, 450),
               ("notifications", 860, 20), ("widget:music", 860, 450)]
layout = load(f"{state}/lockscreen/layout.json")
lay = {"version": 3, "ref": None, "panel": None, "screen": [], "items": []}
if isinstance(layout, dict) and layout.get("version") == 3:
    lay["panel"] = layout.get("panel")
    lay["ref"] = layout.get("ref")
    items = [i for i in layout.get("items", []) if isinstance(i, dict)]
    sig = [(i.get("itype"), round(float(i.get("ix", 0))), round(float(i.get("iy", 0)))) for i in items]
    p = layout.get("panel") or {}
    legacy = p.get("w") == 1280 and p.get("h") == 580
    if sig == DEFAULTS_FP or legacy:
        print("layout:     Serpantinum default layout")
    else:
        lay["items"] = [i for i in items if i.get("itype") != "fingerprint"]
        print(f"layout:     {state}/lockscreen/layout.json ({len(lay['items'])} elements)")
    lay["screen"] = [i for i in layout.get("screen", []) if isinstance(i, dict) and i.get("itype") == "clock"]
    if isinstance(lay["panel"], dict) and "opacity" in lay["panel"]:
        conf["panelOpacity"] = lay["panel"]["opacity"]
else:
    print("layout:     none saved, using Serpantinum's default layout")
if not lay["ref"]:
    try:
        mons = json.loads(hypr_mon) or []
        m = next((x for x in mons if x.get("focused")), mons[0])
        sc = float(m.get("scale", 1)) or 1
        w, h = m["width"] / sc, m["height"] / sc
        if m.get("transform", 0) % 2 == 1: w, h = h, w
        lay["ref"] = {"w": round(w), "h": round(h)}
    except Exception:
        lay["ref"] = {"w": 1920, "h": 1080}
print(f"canvas:     {lay['ref']['w']}x{lay['ref']['h']} (logical)")
with open(f"{build}/layout.js", "w") as f:
    f.write("// Generated by install.sh from your Serpantinum lock layout.\nvar data = ")
    json.dump(lay, f, ensure_ascii=False)
    f.write(";\n")

for k in ["base", "mantle", "crust", "surface0", "surface1", "surface2", "overlay0", "overlay2",
          "text", "subtext0", "subtext1", "mauve", "blue", "red", "peach", "green"]:
    h = hexof(colors.get(k))
    if h: conf[k] = h
with open(f"{build}/theme.conf", "w") as f:
    f.write("[General]\n# Generated by install.sh from your Serpantinum settings.\n")
    for k, v in conf.items():
        f.write(f"{k}={v}\n")

# system snapshot (start values; the greeter keeps them live)
snap = {}
def read(p):
    try:
        with open(p) as f: return f.read()
    except Exception: return ""
def cpu_times():
    v = [int(x) for x in read("/proc/stat").split("\n")[0].split()[1:9]]
    return v[3] + v[4], sum(v)
try:
    i1, t1 = cpu_times(); time.sleep(0.4); i2, t2 = cpu_times()
    snap["cpu"] = round(100 * (1 - (i2 - i1) / max(1, t2 - t1)), 1)
except Exception: pass
mi = {l.split(":")[0]: int(l.split()[1]) for l in read("/proc/meminfo").splitlines() if l.split()[1:2] and l.split()[1].isdigit()}
if mi.get("MemTotal"):
    used = mi["MemTotal"] - mi.get("MemAvailable", 0)
    snap["ramGb"] = round(used / 1048576, 2)
    snap["ramPercent"] = round(100 * used / mi["MemTotal"], 1)
du = shutil.disk_usage("/")
snap["diskGb"] = round(du.used / 2**30, 1)
snap["diskTotalGb"] = round(du.total / 2**30, 1)
snap["diskPercent"] = round(100 * du.used / du.total)
zones = sorted(glob.glob("/sys/class/thermal/thermal_zone*"))
pref = [z for z in zones if read(z + "/type").strip() == "x86_pkg_temp"] + \
       [z for z in zones if read(z + "/type").strip() in ("TCPU", "cpu-thermal", "k10temp", "acpitz")]
snap["tempPaths"] = [z + "/temp" for z in pref + [z for z in zones if z not in pref]]
for p in snap["tempPaths"]:
    t = read(p).strip()
    if t.isdigit() and int(t) > 0:
        snap["temp"] = int(t) / 1000
        break
bats = sorted(b for b in glob.glob("/sys/class/power_supply/BAT*") if read(b + "/type").strip() == "Battery")
snap["batteries"] = bats
now_ = full = 0
snap["batCaps"] = []
for b in bats:
    n = read(b + "/energy_now").strip() or read(b + "/charge_now").strip()
    fl = read(b + "/energy_full").strip() or read(b + "/charge_full").strip()
    if n.isdigit() and fl.isdigit() and int(fl) > 0:
        now_ += int(n); full += int(fl)
        snap["batCaps"].append(round(100 * int(n) / int(fl)))
if full: snap["batCap"] = round(100 * now_ / full)

wjson = load(f"{cache}/weather/weather.json")
loc = obj(general, "location")
if not loc and wjson.get("latitude") is not None:
    loc = {"latitude": wjson.get("latitude"), "longitude": wjson.get("longitude")}
if loc:
    snap["location"] = {k: loc.get(k) for k in ("city", "latitude", "longitude", "timezone") if loc.get(k) is not None}
snap["weatherUnit"] = general.get("weatherUnit") or wjson.get("unit") or "metric"
if wjson.get("forecast"):
    snap["weather"] = {
        "current_temp": wjson.get("current_temp"), "current_icon": wjson.get("current_icon"), "current_hex": wjson.get("current_hex"),
        "forecast": [{"desc": d.get("desc"), "feels_like": d.get("feels_like"), "icon": d.get("icon"), "hex": d.get("hex"),
                      "hourly": [{k: s.get(k) for k in ("time", "temp", "icon", "hex")} for s in d.get("hourly", [])]}
                     for d in wjson["forecast"][:2]],
    }
print(f"weather:    {snap.get('location', {}).get('city', 'NO LOCATION (weather card will stay empty)')}")
print(f"battery:    {', '.join(os.path.basename(b) for b in bats) or 'none'}   temp sensor: {snap['tempPaths'][0] if snap['tempPaths'] else 'NOT FOUND'}")
with open(f"{build}/snapshot.js", "w") as f:
    f.write("// Generated by install.sh (start values; the greeter refreshes them).\nvar data = ")
    json.dump(snap, f, ensure_ascii=False)
    f.write(";\n")

# wallpaper (lock screen custom background if it's an image, else desktop wallpaper)
lock = obj(settings, "lockscreen")
candidates = []
cb = str(lock.get("customBackground") or "")
if lock.get("backgroundMode") == "custom" and cb and not cb.lower().endswith((".mp4", ".mkv", ".mov", ".webm")):
    candidates.append(cb)
candidates.append(f"{cache}/wallpaper/current_wallpaper.png")
candidates += sorted(glob.glob(f"{cache}/wallpaper/current_wallpaper_*.png"))
for p in candidates:
    if os.path.isfile(p):
        shutil.copyfile(p, f"{build}/background.png")
        print(f"wallpaper:  {p}")
        break
else:
    print("wallpaper:  NOT FOUND (plain background will be used)")

# fonts
family = conf["fontFamily"]
font_file = None
for line in open(f"{state}/fonts_cache.txt") if os.path.isfile(f"{state}/fonts_cache.txt") else []:
    name, _, path = line.rstrip("\n").partition("|")
    if name.lower() == family.lower() and os.path.isfile(path):
        font_file = path
        break
def fcmatch(pattern):
    try:
        r = subprocess.run(["fc-match", "-f", "%{family[0]}|%{file}", pattern], capture_output=True, text=True)
        fam, _, path = r.stdout.strip().partition("|")
        # fc-match always returns *something*; only accept it if the family really matches
        if r.returncode == 0 and os.path.isfile(path) and fam.replace(" ", "").lower().startswith(family.replace(" ", "").lower()):
            return path
    except Exception:
        pass
    return None
if not font_file:
    font_file = fcmatch(family)
if font_file:
    shutil.copyfile(font_file, f"{build}/fonts/main.ttf")
    print(f"font:       {family} -> {font_file}")
else:
    print(f"font:       WARNING '{family}' not found, SDDM will use a fallback font")
bold = fcmatch(f"{family}:bold")
if bold and bold != font_file:
    shutil.copyfile(bold, f"{build}/fonts/bold.ttf")
assets = os.path.join(serp_dir, "assets")
for src, dst in [("fonts/SymbolsNerdFontMono-Regular.ttf", "fonts/icons.ttf"),
                 ("shaders/fluid/fluid_wave.frag.qsb", "shaders/fluid_wave.frag.qsb"),
                 ("pushy.gif", "pushy.gif")]:
    if os.path.isfile(os.path.join(assets, src)):
        shutil.copyfile(os.path.join(assets, src), os.path.join(build, dst))
    else:
        print(f"asset:      WARNING {src} not found in {assets}")

# avatar
for p in [f"{cache}/avatar/avatar_cropped.png", str(general.get("avatarPath") or ""),
          f"{home}/.face", f"{home}/.face.icon", f"/var/lib/AccountsService/icons/{user}"]:
    if p and os.path.isfile(p):
        shutil.copyfile(p, f"{build}/avatars/{user}.png")
        print(f"avatar:     {p}")
        break
else:
    print("avatar:     none found (placeholder icon will be shown)")
PY

GREETER="$(command -v sddm-greeter-qt6 || command -v sddm-greeter || true)"

if [ "$MODE" = "preview" ]; then
    [ -z "$GREETER" ] && { echo "sddm-greeter-qt6 not found. Is sddm installed?" >&2; exit 1; }
    echo "Opening preview (password check is fake in test mode; close the window to exit)..."
    QML_XHR_ALLOW_FILE_READ=1 exec "$GREETER" --test-mode --theme "$BUILD"
fi

echo "Installing to $DEST (needs sudo)..."
sudo rm -rf "$DEST"
sudo mkdir -p "$DEST"
sudo cp -r "$BUILD"/. "$DEST/"
sudo chown -R root:root "$DEST"
sudo chmod -R u=rwX,go=rX "$DEST"

# SDDM config: select the theme, and let the greeter read /proc and /sys for the live stats.
# Keep any GreeterEnvironment another config already sets (e.g. Wayland greeter settings).
ENV_KEEP="$(cat /usr/lib/sddm/sddm.conf.d/*.conf /etc/sddm.conf.d/*.conf 2>/dev/null \
    | grep -E '^\s*GreeterEnvironment\s*=' | tail -n1 | cut -d= -f2- | tr ',' '\n' \
    | grep -v '^\s*QML_XHR_ALLOW_FILE_READ' | sed '/^\s*$/d' | paste -sd, - || true)"
GREETER_ENV="QML_XHR_ALLOW_FILE_READ=1${ENV_KEEP:+,$ENV_KEEP}"
sudo mkdir -p /etc/sddm.conf.d
sudo rm -f /etc/sddm.conf.d/10-serpantinum-theme.conf
printf '[Theme]\nCurrent=serpantinum\n\n[General]\nGreeterEnvironment=%s\n' "$GREETER_ENV" \
    | sudo tee /etc/sddm.conf.d/99-serpantinum.conf >/dev/null

if [ -f /etc/sddm.conf ] && grep -qE '^\s*(Current|GreeterEnvironment)\s*=' /etc/sddm.conf; then
    echo
    echo "WARNING: /etc/sddm.conf sets Current= or GreeterEnvironment=, and it wins over sddm.conf.d."
    echo "Remove those lines:  sudo nano /etc/sddm.conf"
fi
if ! systemctl is-enabled sddm >/dev/null 2>&1; then
    echo
    echo "Note: sddm.service isn't enabled. To use SDDM as your login manager:"
    echo "  sudo systemctl disable <current-dm>; sudo systemctl enable sddm"
fi
echo
echo "Done. Preview anytime with:  QML_XHR_ALLOW_FILE_READ=1 sddm-greeter-qt6 --test-mode --theme $DEST"
