// SDDM login screen that looks like the Serpantinum lock screen.
//
// Idle it shows the blurred wallpaper and the lock clock. Press a key or click and the
// dashboard opens the same way the lock screen does: weather, system stats, avatar,
// password, keyboard + battery, notifications and music, power menu bottom right.
//
// install.sh fills in layout.js (your lock layout), snapshot.js and theme.conf (colours,
// font, blur). The live stats read /proc and /sys, so the greeter needs
// QML_XHR_ALLOW_FILE_READ=1; install.sh sets that up. Without it you get the values
// from the moment you ran the installer.

import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import "layout.js" as LockLayout
import "snapshot.js" as Snap

FocusScope {
    id: root
    width: 1920
    height: 1080
    focus: true

    // config
    function cfg(key, def) {
        let v = (typeof config !== "undefined" && config) ? config[key] : undefined;
        return (v === undefined || v === null || String(v) === "") ? def : v;
    }
    function cfgNum(key, def) { let n = Number(cfg(key, def)); return isNaN(n) ? def : n; }
    function cfgBool(key, def) { let v = String(cfg(key, def)).toLowerCase(); return v === "true" || v === "1"; }

    readonly property bool liquid: cfgBool("liquidGlass", false)
    readonly property bool blurBackground: cfgBool("blurBackground", false)
    readonly property real elementOpacity: cfgNum("elementOpacity", 1.0)
    readonly property real panelOpacity: cfgNum("panelOpacity", 1.0)
    readonly property bool glassActive: blurBackground && elementOpacity < 0.999

    readonly property color base:     cfg("base", "#1e1e2e")
    readonly property color mantle:   cfg("mantle", "#181825")
    readonly property color crust:    cfg("crust", "#11111b")
    readonly property color surface0: cfg("surface0", "#313244")
    readonly property color surface1: cfg("surface1", "#45475a")
    readonly property color surface2: cfg("surface2", "#585b70")
    readonly property color overlay0: cfg("overlay0", "#6c7086")
    readonly property color overlay2: cfg("overlay2", "#9399b2")
    readonly property color textCol:  liquid ? "#ffffff" : cfg("text", "#cdd6f4")
    readonly property color subtext0: liquid ? "#ffffff" : cfg("subtext0", "#a6adc8")
    readonly property color subtext1: liquid ? "#ffffff" : cfg("subtext1", "#bac2de")
    readonly property color mauve:    cfg("mauve", "#cba6f7")
    readonly property color blue:     cfg("blue", "#89b4fa")
    readonly property color red:      cfg("red", "#f38ba8")
    readonly property color peach:    cfg("peach", "#fab387")
    readonly property color green:    cfg("green", "#a6e3a1")

    readonly property real radiusBase: cfgNum("borderRadius", 8)
    readonly property real clampedRadius: Math.floor(radiusBase <= 24 ? radiusBase : 24 + Math.pow(radiusBase - 24, 0.55))
    readonly property string timeFormat: cfg("timeFormat", "HH:mm:ss")
    readonly property bool is12h: timeFormat.indexOf("h") !== -1 || timeFormat.toLowerCase().indexOf("ap") !== -1
    readonly property bool dnd: cfgBool("dnd", false)
    readonly property bool showEmptyGraphic: cfgBool("showEmptyGraphic", true)

    FontLoader { id: mainFont; source: Qt.resolvedUrl("fonts/main.ttf") }
    FontLoader { id: boldFont; source: Qt.resolvedUrl("fonts/bold.ttf") }
    FontLoader { id: iconFontLoader; source: Qt.resolvedUrl("fonts/icons.ttf") }
    readonly property string fontFamily: mainFont.status === FontLoader.Ready ? mainFont.name : cfg("fontFamily", "monospace")
    readonly property string iconFont: iconFontLoader.status === FontLoader.Ready ? iconFontLoader.name : fontFamily

    // layout (same model as LockLayoutStore)
    readonly property var lay: LockLayout.data ? LockLayout.data : ({})
    readonly property real refW: (lay.ref && lay.ref.w > 0) ? lay.ref.w : 1920
    readonly property real refH: (lay.ref && lay.ref.h > 0) ? lay.ref.h : 1080
    readonly property real fit: Math.min(width / refW, height / refH)
    readonly property real panelW: (lay.panel && lay.panel.w > 0) ? lay.panel.w : 1280
    readonly property real panelH: (lay.panel && lay.panel.h > 0) ? lay.panel.h : 566
    readonly property real panelLeft: (lay.panel && lay.panel.x >= 0) ? lay.panel.x : (refW - panelW) / 2
    readonly property real panelTop: (lay.panel && lay.panel.y >= 0) ? lay.panel.y : (refH - panelH) / 2
    readonly property real coreWidth: Math.min(panelW, 440)
    readonly property real shellWidth: coreWidth + wingsReveal * (panelW - coreWidth)

    function entry(t, v, x, y, w, h) { return { itype: t, ivariant: v, ix: x, iy: y, iw: w, ih: h, iopacity: 1 }; }
    readonly property var panelItems: (lay.items && lay.items.length) ? lay.items : [
        entry("widget:weather", "full", 20, 20, 380, 190),
        entry("widget:cpu", "default", 20, 218, 186, 160),
        entry("widget:ram", "default", 214, 218, 186, 160),
        entry("widget:temp", "default", 20, 386, 186, 160),
        entry("widget:disk", "default", 214, 386, 186, 160),
        entry("avatar", "round", 540, 89, 200, 200),
        entry("user", "filled", 450, 305, 185, 44),
        entry("lockstatus", "filled", 645, 305, 185, 44),
        entry("password", "filled", 450, 357, 380, 44),
        entry("keyboard", "button", 600, 433, 0, 0),
        entry("battery", "button", 685, 433, 0, 0),
        entry("notifications", "card", 860, 20, 400, 422),
        entry("widget:music", "full", 860, 450, 400, 96)
    ]
    readonly property var screenItems: (lay.screen && lay.screen.length) ? lay.screen : [
        entry("clock", "lockscreen", refW * 0.5 - 210, refH * 0.36 - 100, 420, 200)
    ]

    // users / sessions / keyboard
    property var users: []
    property int userIndex: 0
    property int sessionIndex: (typeof sessionModel !== "undefined" && sessionModel && sessionModel.lastIndex >= 0) ? sessionModel.lastIndex : 0
    property var sessions: []
    readonly property var currentUser: users.length > 0 ? users[Math.max(0, Math.min(userIndex, users.length - 1))] : ({ name: "", realName: "", icon: "" })
    readonly property string sessionName: sessions.length > 0 ? sessions[Math.max(0, Math.min(sessionIndex, sessions.length - 1))] : "Session"

    Repeater {
        id: userCollector
        model: typeof userModel !== "undefined" ? userModel : null
        onItemAdded: root.collectUsers()
        onItemRemoved: root.collectUsers()
        delegate: Item {
            required property var model
            visible: false
            property string uName: model.name || ""
            property string uReal: model.realName || ""
            property string uIcon: model.icon ? String(model.icon) : ""
        }
    }
    Repeater {
        id: sessionCollector
        model: typeof sessionModel !== "undefined" ? sessionModel : null
        onItemAdded: root.collectSessions()
        onItemRemoved: root.collectSessions()
        delegate: Item {
            required property var model
            visible: false
            property string sName: model.name || ""
        }
    }
    function collectUsers() {
        let list = [];
        for (let i = 0; i < userCollector.count; i++) {
            let it = userCollector.itemAt(i);
            if (it) list.push({ name: it.uName, realName: it.uReal, icon: it.uIcon });
        }
        users = list;
        let last = (typeof userModel !== "undefined" && userModel) ? userModel.lastUser : "";
        for (let j = 0; j < list.length; j++) if (list[j].name === last) { userIndex = j; break; }
    }
    function collectSessions() {
        let list = [];
        for (let i = 0; i < sessionCollector.count; i++) {
            let it = sessionCollector.itemAt(i);
            if (it) list.push(it.sName);
        }
        sessions = list;
    }

    readonly property bool hasKeyboard: typeof keyboard !== "undefined" && keyboard && keyboard.layouts && keyboard.layouts.length > 0
    readonly property string kbLayout: {
        if (hasKeyboard) {
            let l = keyboard.layouts[Math.max(0, keyboard.currentLayout)];
            if (l && l.shortName) return String(l.shortName).toUpperCase();
        }
        return String(Snap.data && Snap.data.kbLayout ? Snap.data.kbLayout : "EN");
    }
    function switchLayout() {
        if (!hasKeyboard || keyboard.layouts.length < 2) return;
        keyboard.currentLayout = (keyboard.currentLayout + 1) % keyboard.layouts.length;
    }

    // state + animations (LockScreen.qml)
    property bool inputActive: false
    property bool powerMenuOpen: false
    property bool authenticating: false
    property bool failed: false
    property bool unlocking: false
    property string statusText: "Locked"
    property real contentReveal: 0.0
    property real centerReveal: 0.0
    property real wingsReveal: 0.0
    property real foldScale: 1.0
    property real mainOpacity: 1.0
    property var now: new Date()

    Timer { interval: 1000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.now = new Date() }
    NumberAnimation on contentReveal { from: 0; to: 1; duration: 600; easing.type: Easing.OutCubic; running: true }

    onInputActiveChanged: {
        if (unlocking) return;
        if (inputActive) {
            closeAnim.stop(); openAnim.restart();
            pwdFocus();
        } else {
            openAnim.stop(); closeAnim.restart();
            powerMenuOpen = false;
            root.forceActiveFocus();
        }
    }
    SequentialAnimation {
        id: openAnim
        NumberAnimation { target: root; property: "centerReveal"; to: 1; duration: 150; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
        NumberAnimation { target: root; property: "wingsReveal"; to: 1; duration: 250; easing.type: Easing.OutBack; easing.overshoot: 1.12 }
    }
    ParallelAnimation {
        id: closeAnim
        NumberAnimation { target: root; property: "wingsReveal"; to: 0; duration: 110; easing.type: Easing.InQuad }
        NumberAnimation { target: root; property: "centerReveal"; to: 0; duration: 100; easing.type: Easing.InQuad }
    }
    SequentialAnimation {
        id: unlockAnim
        NumberAnimation { target: root; property: "wingsReveal"; to: 0; duration: 130; easing.type: Easing.InQuad }
        ParallelAnimation {
            NumberAnimation { target: root; property: "foldScale"; to: 0; duration: 250; easing.type: Easing.InBack; easing.overshoot: 1.3 }
            NumberAnimation { target: root; property: "mainOpacity"; to: 0; duration: 250; easing.type: Easing.InQuad }
        }
    }

    Timer {
        id: idleTimer
        interval: 15000
        running: root.inputActive && root.pwdText.length === 0 && !root.authenticating
        onTriggered: root.inputActive = false
    }

    // The password TextInput lives inside the layout; these route to it.
    property var pwdField: null
    readonly property string pwdText: pwdField ? pwdField.text : ""
    function pwdFocus() { if (pwdField) pwdField.forceActiveFocus(); }
    function pwdClear() { if (pwdField) pwdField.text = ""; }

    signal shakeRequested()

    function activate(ch) {
        if (unlocking) return;
        if (!inputActive) inputActive = true;
        pwdFocus();
        if (ch && ch.length > 0 && pwdField) pwdField.insert(pwdField.cursorPosition, ch);
    }
    function submit() {
        if (authenticating || unlocking || currentUser.name === "") return;
        authenticating = true;
        failed = false;
        statusText = "Authenticating...";
        sddm.login(currentUser.name, pwdText, sessionIndex);
    }

    Connections {
        target: typeof sddm !== "undefined" ? sddm : null
        function onLoginFailed() {
            root.authenticating = false;
            root.failed = true;
            root.statusText = "Access denied";
            root.pwdClear();
            root.shakeRequested();
            root.pwdFocus();
        }
        function onLoginSucceeded() {
            root.authenticating = false;
            root.unlocking = true;
            unlockAnim.start();
        }
    }

    Keys.onPressed: (event) => {
        if (unlocking) return;
        let printable = event.text.length > 0 && event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter
            && event.key !== Qt.Key_Tab && event.key !== Qt.Key_Backspace && event.key !== Qt.Key_Escape;
        if (!inputActive) {
            if (event.key !== Qt.Key_Escape) activate(printable ? event.text : "");
            event.accepted = true;
            return;
        }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) submit();
        else if (event.key === Qt.Key_Escape) { if (powerMenuOpen) powerMenuOpen = false; else { inputActive = false; pwdClear(); } }
        else if (event.key === Qt.Key_Backspace) { if (pwdField && pwdText.length > 0) pwdField.remove(pwdText.length - 1, pwdText.length); pwdFocus(); }
        else if (printable) activate(event.text);
        event.accepted = true;
    }

    // live data (SysData / UPower / Weather)
    readonly property var snap: Snap.data ? Snap.data : ({})
    property real cpu: snap.cpu !== undefined ? snap.cpu : 0
    property real ramPercent: snap.ramPercent !== undefined ? snap.ramPercent : 0
    property real ramGb: snap.ramGb !== undefined ? snap.ramGb : 0
    property real tempC: snap.temp !== undefined ? snap.temp : 0
    readonly property real diskPercent: snap.diskPercent !== undefined ? snap.diskPercent : 0
    readonly property real diskGb: snap.diskGb !== undefined ? snap.diskGb : 0
    readonly property real diskTotalGb: snap.diskTotalGb !== undefined ? snap.diskTotalGb : 0
    readonly property var batPaths: snap.batteries ? snap.batteries : []
    readonly property bool hasBattery: batPaths.length > 0
    property real batCap: snap.batCap !== undefined ? snap.batCap : 0
    property bool batCharging: false
    property var batCaps: snap.batCaps ? snap.batCaps : []   // per battery, BAT0 (internal) first
    property var cpuPrev: null

    function readFile(path) {
        try {
            let x = new XMLHttpRequest();
            x.open("GET", "file://" + path, false);
            x.send(null);
            return x.responseText || "";
        } catch (e) {
            return "";
        }
    }

    function pollSys() {
        let st = readFile("/proc/stat");
        if (st) {
            let f = st.split("\n")[0].trim().split(/\s+/).slice(1).map(Number);
            let idle = f[3] + (f[4] || 0);
            let total = 0;
            for (let i = 0; i < Math.min(f.length, 8); i++) total += f[i];
            if (cpuPrev && total > cpuPrev.total) cpu = Math.max(0, Math.min(100, 100 * (1 - (idle - cpuPrev.idle) / (total - cpuPrev.total))));
            cpuPrev = { idle: idle, total: total };
        }
        let mi = readFile("/proc/meminfo");
        if (mi) {
            let tot = Number((mi.match(/MemTotal:\s+(\d+)/) || [0, 0])[1]);
            let av = Number((mi.match(/MemAvailable:\s+(\d+)/) || [0, 0])[1]);
            if (tot > 0) { ramGb = (tot - av) / 1048576; ramPercent = 100 * (tot - av) / tot; }
        }
        let tp = snap.tempPaths || [];
        for (let i = 0; i < tp.length; i++) {
            let t = Number(readFile(tp[i]).trim());
            if (t > 0) { tempC = t / 1000; break; }
        }
        if (hasBattery) {
            let now_ = 0, full = 0, charging = false, caps = [];
            for (let i = 0; i < batPaths.length; i++) {
                let p = batPaths[i];
                let n = Number(readFile(p + "/energy_now").trim()) || Number(readFile(p + "/charge_now").trim());
                let fl = Number(readFile(p + "/energy_full").trim()) || Number(readFile(p + "/charge_full").trim());
                if (fl > 0) { now_ += n; full += fl; caps.push(Math.round(100 * n / fl)); }
                let s = readFile(p + "/status").trim();
                if (s === "Charging" || s === "Full") charging = charging || s === "Charging";
            }
            if (full > 0) batCap = Math.round(100 * now_ / full);
            if (caps.length > 0) batCaps = caps;
            batCharging = charging;
        }
    }
    Timer { interval: 2000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.pollSys() }

    // Weather: same open-meteo source and icon mapping as scripts/weather.sh.
    property var wx: null
    function wmo(code, isDay) {
        if (code === 0) return isDay ? { icon: "", hex: "#f9e2af", desc: "Sunny" } : { icon: "", hex: "#cba6f7", desc: "Clear" };
        if (code >= 1 && code <= 3) return { icon: "", hex: "#bac2de", desc: "Cloudy" };
        if (code === 45 || code === 48) return { icon: "\u{f0591}", hex: "#84afdb", desc: "Mist" };
        if ((code >= 51 && code <= 57) || (code >= 61 && code <= 67) || (code >= 80 && code <= 82)) return { icon: "\u{f0597}", hex: "#74c7ec", desc: "Rainy" };
        if ((code >= 71 && code <= 77) || code === 85 || code === 86) return { icon: "", hex: "#cdd6f4", desc: "Snow" };
        if (code === 95 || code === 96 || code === 99) return { icon: "", hex: "#f9e2af", desc: "Storm" };
        return { icon: "", hex: "#cdd6f4", desc: "Unknown" };
    }
    function pickSlots(slots) {
        // LockScreen.updateForecastData: first slot at/after the current hour, then the next three.
        if (!slots || slots.length === 0) return [];
        let ch = new Date().getHours();
        let best = 0, minDiff = 999;
        for (let i = 0; i < slots.length; i++) {
            let h = parseInt(String(slots[i].time).split(":")[0], 10);
            let d = h - ch;
            if (d >= 0 && d < minDiff) { minDiff = d; best = i; }
        }
        if (minDiff === 999) {
            for (let i = 0; i < slots.length; i++) {
                let h = parseInt(String(slots[i].time).split(":")[0], 10);
                let d = Math.abs(h - ch);
                if (d < minDiff) { minDiff = d; best = i; }
            }
        }
        return slots.slice(best, best + 4);
    }
    function fromSnapshot() {
        let w = snap.weather;
        if (!w || !w.forecast || !w.forecast.length) return;
        let slots = [];
        for (let d = 0; d < w.forecast.length; d++) slots = slots.concat(w.forecast[d].hourly || []);
        wx = {
            temp: w.current_temp !== undefined ? Math.round(parseFloat(w.current_temp)) : null,
            icon: w.current_icon || w.forecast[0].icon, hex: w.current_hex || w.forecast[0].hex,
            desc: w.forecast[0].desc || "", feels: Math.round(parseFloat(w.forecast[0].feels_like)),
            slots: pickSlots(slots).map(s => ({ time: s.time, temp: Math.round(parseFloat(s.temp)), icon: s.icon, hex: s.hex }))
        };
    }
    function fetchWeather() {
        let loc = snap.location;
        if (!loc || loc.latitude === undefined) { fromSnapshot(); return; }
        let unit = snap.weatherUnit === "imperial" ? "&temperature_unit=fahrenheit" : "";
        let url = "https://api.open-meteo.com/v1/forecast?latitude=" + loc.latitude + "&longitude=" + loc.longitude
            + "&timezone=" + encodeURIComponent(loc.timezone || "auto")
            + "&current=temperature_2m,weather_code,is_day&hourly=temperature_2m,apparent_temperature,weather_code&forecast_days=2" + unit;
        let x = new XMLHttpRequest();
        x.onreadystatechange = function() {
            if (x.readyState !== XMLHttpRequest.DONE) return;
            try {
                if (x.status !== 200) throw "http " + x.status;
                let r = JSON.parse(x.responseText);
                let kelvin = snap.weatherUnit === "standard";
                let tv = t => Math.round(kelvin ? t + 273.15 : t);
                let today = String(r.current.time).split("T")[0];
                let cm = wmo(r.current.weather_code, r.current.is_day === 1);
                let slots = [], feels = -1e9, dayCode = null, dayCodeFirst = null;
                for (let i = 0; i < r.hourly.time.length; i++) {
                    let parts = String(r.hourly.time[i]).split("T");
                    let h = parseInt(parts[1].split(":")[0], 10);
                    if (parts[0] === today) {
                        feels = Math.max(feels, r.hourly.apparent_temperature[i]);
                        if (dayCodeFirst === null) dayCodeFirst = r.hourly.weather_code[i];
                        if (h === 12) dayCode = r.hourly.weather_code[i];
                    }
                    if (h % 3 === 0) {
                        let m = wmo(r.hourly.weather_code[i], h >= 6 && h <= 18);
                        slots.push({ time: parts[1], temp: tv(r.hourly.temperature_2m[i]), icon: m.icon, hex: m.hex });
                    }
                }
                wx = {
                    temp: tv(r.current.temperature_2m), icon: cm.icon, hex: cm.hex,
                    desc: wmo(dayCode !== null ? dayCode : dayCodeFirst, true).desc,
                    feels: tv(feels), slots: pickSlots(slots)
                };
            } catch (e) {
                if (!wx) fromSnapshot();
            }
        };
        x.open("GET", url);
        x.send();
    }
    Timer { id: weatherTimer; interval: 15 * 60 * 1000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.fetchWeather() }
    Timer { interval: 8000; running: root.wx === null; repeat: true; onTriggered: root.fetchWeather() }  // retry while network comes up

    function fmtHour(t) {
        let h = parseInt(String(t).split(":")[0], 10);
        if (isNaN(h)) return String(t);
        if (is12h) { let p = h >= 12 ? "PM" : "AM"; let h12 = h % 12; return (h12 === 0 ? 12 : h12) + p; }
        return (h < 10 ? "0" + h : h) + ":00";
    }

    // backdrop (LockBackdrop.qml)
    Rectangle { anchors.fill: parent; color: root.crust }

    Image {
        id: wallpaper
        anchors.fill: parent
        source: Qt.resolvedUrl(root.cfg("background", "background.png"))
        fillMode: Image.PreserveAspectCrop
        cache: true
        sourceSize: Qt.size(root.width, root.height)
        visible: false
    }
    MultiEffect {
        anchors.fill: parent
        source: wallpaper
        autoPaddingEnabled: false
        blurEnabled: true
        blurMax: 64
        saturation: 0.25
        contrast: 0.06
        brightness: 0.02
        blur: root.inputActive ? 1.0 : 0.72
        Behavior on blur { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
    }
    Rectangle {
        anchors.fill: parent
        color: root.crust
        opacity: root.inputActive ? 0.14 : 0.38
        Behavior on opacity { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
    }

    // Source for the frosted panels (WallpaperBlur.qml): the plain wallpaper at 1/4 size, blurred.
    Image {
        id: wallSmall
        width: root.width
        height: root.height
        source: wallpaper.source
        fillMode: Image.PreserveAspectCrop
        sourceSize: Qt.size(Math.max(1, Math.round(root.width / 4)), Math.max(1, Math.round(root.height / 4)))
        visible: false
    }
    MultiEffect {
        id: blurWall
        width: root.width
        height: root.height
        source: wallSmall
        autoPaddingEnabled: false
        blurEnabled: true
        blurMax: 64
        blur: 1.0
        visible: false
        layer.enabled: true
    }

    // reusable pieces
    component T: Text {
        font.family: root.fontFamily
        color: root.textCol
    }

    component ShadowText: Text {
        font.family: root.fontFamily
        font.weight: Font.Bold
        Text {
            anchors.fill: parent
            anchors.topMargin: 3
            anchors.bottomMargin: -3
            font: parent.font
            color: Qt.rgba(0, 0, 0, 0.32)
            text: parent.text
            z: -1
        }
    }

    // Frosted wallpaper behind a surface (WallpaperBlur, regular "blur" style).
    component Frost: Item {
        id: fr
        property real r: root.radiusBase
        property rect area: Qt.rect(0, 0, 1, 1)
        visible: root.glassActive
        function refresh() {
            let a = fr.mapToItem(root, 0, 0);
            let b = fr.mapToItem(root, fr.width, fr.height);
            let n = Qt.rect(Math.min(a.x, b.x), Math.min(a.y, b.y), Math.abs(b.x - a.x), Math.abs(b.y - a.y));
            if (n.x !== area.x || n.y !== area.y || n.width !== area.width || n.height !== area.height) area = n;
        }
        FrameAnimation { running: fr.visible && root.contentReveal > 0; onTriggered: fr.refresh() }
        ShaderEffectSource {
            id: crop
            anchors.fill: parent
            sourceItem: fr.visible ? blurWall : null
            sourceRect: fr.area
            visible: false
        }
        Rectangle { id: frMask; anchors.fill: parent; radius: fr.r; visible: false; layer.enabled: true }
        MultiEffect {
            anchors.fill: parent
            source: crop
            maskEnabled: true
            maskSource: frMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
            opacity: Math.min(0.98, root.elementOpacity)
        }
    }

    // ClickButton look: solid pill, icon + text centred.
    component Pill: Rectangle {
        id: pill
        property string icon: ""
        property string label: ""
        property color fg: root.textCol
        property color accent: Qt.lighter(root.surface0, 1.28)
        property real pad: 16
        property real iconSize: 15
        property real textSize: 13
        property bool interactive: false
        signal clicked()
        readonly property real pLabelWidth: pLabel.implicitWidth
        readonly property real contentWidth: (icon !== "" ? pIcon.implicitWidth : 0) + (icon !== "" && label !== "" ? 8 : 0) + (label !== "" ? pLabel.implicitWidth : 0)
        implicitWidth: contentWidth + pad * 2
        implicitHeight: 44
        radius: root.radiusBase
        color: ma.pressed && interactive ? Qt.darker(accent, 1.28) : (ma.containsMouse && interactive ? Qt.darker(accent, 1.14) : accent)
        Behavior on color { ColorAnimation { duration: 150 } }
        Row {
            id: row
            anchors.centerIn: parent
            spacing: 8
            Text {
                id: pIcon
                visible: pill.icon !== ""
                text: pill.icon
                font.family: root.iconFont
                font.pixelSize: pill.iconSize
                color: pill.fg
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                id: pLabel
                visible: pill.label !== ""
                text: pill.label
                font.family: root.fontFamily
                font.pixelSize: pill.textSize
                font.weight: Font.DemiBold
                color: pill.fg
                elide: Text.ElideRight
                width: Math.min(implicitWidth, Math.max(0, pill.width - pill.pad * 2 - (pill.icon !== "" ? pIcon.implicitWidth + 8 : 0)))
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        MouseArea {
            id: ma
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: pill.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: { pill.clicked(); root.pwdFocus(); }
        }
    }

    // IconButton look (used in usage cards and the music widget).
    component IconBox: Item {
        id: ib
        property string icon: ""
        property color accent: root.surface1
        property real bgOpacity: 1
        property color fg: root.subtext0
        property real iconSize: 16
        property real r: root.radiusBase
        Rectangle { anchors.fill: parent; radius: ib.r; color: ib.accent; opacity: ib.bgOpacity }
        Text {
            anchors.centerIn: parent
            text: ib.icon
            font.family: root.iconFont
            font.pixelSize: ib.iconSize
            color: ib.fg
        }
    }

    // SystemUsageCard.qml (CPU / RAM / Temp / Disk faces).
    component UsageCard: Item {
        id: uc
        property real value: 0
        property color colorFill: root.mauve
        property string icon: ""
        property string title: ""
        property string valueText: ""
        property string subText: ""
        property real wavePhase: 0.8
        readonly property real cardRadius: root.clampedRadius
        readonly property real m: 12
        readonly property real fillRatio: Math.max(0, Math.min(1, value))
        readonly property real waveAmp: (fillRatio < 0.99 && fillRatio > 0.01) ? 5 * Math.sin(fillRatio * Math.PI) : 0
        readonly property real waveCenterOffset: waveAmp > 0 ? 0.375 * waveAmp * (Math.sin(wavePhase) - Math.cos(wavePhase)) : 0
        readonly property color filledText: root.liquid ? root.textCol : root.crust

        Behavior on value { NumberAnimation { duration: 800; easing.type: Easing.OutQuint } }
        onValueChanged: { if (fillRatio > 0.001 && fillRatio < 0.999) { if (!waveAnim.running) waveAnim.start(); settle.restart(); } }
        NumberAnimation { id: waveAnim; target: uc; property: "wavePhase"; from: 0; to: Math.PI * 2; loops: Animation.Infinite; duration: 1800 }
        Timer { id: settle; interval: 1600; onTriggered: waveAnim.stop() }

        Rectangle {
            anchors.fill: parent
            radius: uc.cardRadius
            color: Qt.alpha(root.surface0, root.elementOpacity)
            Frost { z: -1; anchors.fill: parent; r: uc.cardRadius }
        }
        ShaderEffect {
            anchors.fill: parent
            visible: uc.fillRatio > 0.001
            property real radius: uc.cardRadius
            property real fillLevel: uc.fillRatio
            property real waveAmp: uc.waveAmp
            property vector2d itemSize: Qt.vector2d(width, height)
            property real phase: uc.wavePhase
            property real vertical: 1.0
            property color color1: Qt.lighter(uc.colorFill, 1.18)
            property color color2: uc.colorFill
            property vector4d params: Qt.vector4d(0.94, 0, 0, 0)
            opacity: root.liquid ? 0.6 : 1.0
            fragmentShader: Qt.resolvedUrl("shaders/fluid_wave.frag.qsb")
        }

        CardFace { uc: uc; anchors.fill: parent; anchors.margins: uc.m }
        Item {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: Math.min(parent.height, Math.max(0, parent.height * uc.fillRatio - uc.waveCenterOffset))
            clip: true
            visible: uc.value > 0
            CardFace {
                uc: uc
                filled: true
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: uc.m
                height: uc.height - uc.m * 2
            }
        }
    }

component CardFace: Item {
        id: cf
        property bool filled: false
        property var uc: null
        IconBox {
            id: cfIcon
            width: 28; height: 28
            r: Math.min(14, root.radiusBase)
            icon: cf.uc.icon
            iconSize: 16
            accent: cf.filled ? Qt.rgba(root.crust.r, root.crust.g, root.crust.b, 0.15) : Qt.rgba(root.surface1.r, root.surface1.g, root.surface1.b, 0.6)
            bgOpacity: cf.filled ? 1 : root.elementOpacity
            fg: cf.filled ? cf.uc.filledText : root.subtext0
        }
        T {
            anchors.verticalCenter: cfIcon.verticalCenter
            anchors.right: parent.right
            text: cf.uc.title
            font.weight: Font.DemiBold
            font.pixelSize: 13
            color: cf.filled ? Qt.alpha(cf.uc.filledText, 0.85) : root.subtext0
        }
        T {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.bottomMargin: 1
            visible: cf.uc.subText !== ""
            text: cf.uc.subText
            font.weight: Font.DemiBold
            font.pixelSize: 15
            color: cf.filled ? cf.uc.filledText : root.subtext0
        }
        T {
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            text: cf.uc.valueText
            font.weight: Font.Black
            font.pixelSize: 24
            color: cf.filled ? cf.uc.filledText : root.textCol
        }
    }

    // Hold-to-confirm button (FillButton, 1.2 s).
    component HoldButton: Rectangle {
        id: hb
        property string icon: ""
        property string label: ""
        property color accent: root.mauve
        property real fill: 0
        property bool fired: false
        signal triggered()
        height: 44
        radius: root.radiusBase
        color: ma2.containsMouse ? root.surface1 : root.surface0
        clip: true
        Rectangle { width: parent.width * hb.fill; height: parent.height; radius: hb.radius; color: hb.accent }
        Row {
            anchors.centerIn: parent
            spacing: 10
            Text { text: hb.icon; font.family: root.iconFont; font.pixelSize: 16; anchors.verticalCenter: parent.verticalCenter
                   color: hb.fill > 0.5 ? root.crust : hb.accent }
            Text { text: hb.label; font.family: root.fontFamily; font.pixelSize: 13; anchors.verticalCenter: parent.verticalCenter
                   color: hb.fill > 0.5 ? root.crust : root.textCol }
        }
        NumberAnimation { id: fillUp; target: hb; property: "fill"; to: 1; duration: 1200 * (1 - hb.fill); easing.type: Easing.Linear
                          onFinished: if (hb.fill >= 0.999 && !hb.fired) { hb.fired = true; hb.triggered(); } }
        NumberAnimation { id: fillDown; target: hb; property: "fill"; to: 0; duration: 250; easing.type: Easing.OutCubic }
        MouseArea {
            id: ma2
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onPressed: { fillDown.stop(); fillUp.restart(); }
            onReleased: if (!hb.fired) { fillUp.stop(); fillDown.restart(); }
            onCanceled: if (!hb.fired) { fillUp.stop(); fillDown.restart(); }
        }
    }

    // element faces
    Component {
        id: weatherFace
        Item {
            id: wf
            clip: true
            readonly property real baseRef: Math.min(height, width * 0.6)
            readonly property real dynMargin: Math.max(12, baseRef * 0.09)
            readonly property real dynSpacing: Math.max(8, baseRef * 0.05)
            readonly property real innerHeight: Math.max(0, height - dynMargin * 2)
            readonly property real iconTop: Math.max(28, Math.min(78, innerHeight * 0.36))
            readonly property real tempHuge: Math.max(24, Math.min(64, innerHeight * 0.3))
            readonly property real textCity: Math.max(13, Math.min(20, innerHeight * 0.105))
            readonly property real textDesc: Math.max(11, Math.min(16, innerHeight * 0.085))
            readonly property real textFeels: Math.max(10, Math.min(14, innerHeight * 0.085))
            readonly property real forecastTemp: Math.max(11, Math.min(18, innerHeight * 0.085))
            readonly property real forecastIcon: Math.max(20, Math.min(32, innerHeight * 0.15))
            readonly property real forecastTime: Math.max(9, Math.min(13, innerHeight * 0.065))
            readonly property int forecastCount: width >= 360 ? 4 : 3
            readonly property var w: root.wx
            readonly property color accentColor: (w && w.hex) ? w.hex : root.mauve

            Rectangle {
                anchors.fill: parent
                color: Qt.alpha(root.surface0, root.elementOpacity)
                radius: root.clampedRadius
                Frost { z: -1; anchors.fill: parent; r: parent.radius }
            }
            T {
                anchors.centerIn: parent
                visible: !wf.w
                text: "\u{f0599}"
                font.family: root.iconFont
                font.pixelSize: 32
                color: root.subtext0
                opacity: 0.6
            }
            RowLayout {
                anchors.fill: parent
                anchors.margins: wf.dynMargin
                spacing: wf.dynSpacing
                visible: !!wf.w
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: 1
                    spacing: 0
                    T {
                        text: wf.w ? wf.w.icon : ""
                        font.family: root.iconFont
                        font.pixelSize: wf.iconTop
                        color: wf.accentColor
                        Layout.alignment: Qt.AlignTop | Qt.AlignLeft
                    }
                    Item { Layout.fillHeight: true }
                    ColumnLayout {
                        Layout.alignment: Qt.AlignBottom | Qt.AlignLeft
                        spacing: 2
                        T {
                            text: wf.w && wf.w.temp !== null ? wf.w.temp + "°" : "--°"
                            font.pixelSize: wf.tempHuge
                            font.weight: Font.Black
                        }
                        T {
                            text: "Feels " + (wf.w && !isNaN(wf.w.feels) ? wf.w.feels + "°" : "--°")
                            font.pixelSize: wf.textFeels
                            font.weight: Font.Medium
                            color: root.subtext0
                        }
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: 1.3
                    spacing: 0
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignTop | Qt.AlignRight
                        spacing: 2
                        T {
                            text: root.snap.location && root.snap.location.city ? root.snap.location.city : "Unknown"
                            font.pixelSize: wf.textCity
                            font.weight: Font.Bold
                            horizontalAlignment: Text.AlignRight
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                        T {
                            text: wf.w ? wf.w.desc : ""
                            font.pixelSize: wf.textDesc
                            font.weight: Font.Medium
                            color: root.subtext0
                            horizontalAlignment: Text.AlignRight
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                    }
                    Item { Layout.fillHeight: true }
                    RowLayout {
                        Layout.alignment: Qt.AlignBottom | Qt.AlignRight
                        spacing: Math.max(6, wf.dynSpacing * 0.9)
                        Repeater {
                            model: wf.w ? wf.w.slots.slice(0, wf.forecastCount) : []
                            delegate: ColumnLayout {
                                required property var modelData
                                Layout.alignment: Qt.AlignHCenter | Qt.AlignBottom
                                spacing: 4
                                T {
                                    text: modelData.temp + "°"
                                    color: root.subtext0
                                    font.pixelSize: wf.forecastTemp
                                    font.weight: Font.Medium
                                    Layout.alignment: Qt.AlignHCenter
                                    transform: Translate { x: 2 }
                                }
                                T {
                                    text: modelData.icon
                                    color: modelData.hex ? modelData.hex : wf.accentColor
                                    font.family: root.iconFont
                                    font.pixelSize: wf.forecastIcon
                                    Layout.alignment: Qt.AlignHCenter
                                    transform: Translate { x: -2 }
                                }
                                T {
                                    text: root.fmtHour(modelData.time)
                                    color: root.subtext0
                                    font.pixelSize: wf.forecastTime
                                    Layout.alignment: Qt.AlignHCenter
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Component { id: cpuFace; UsageCard {
        value: root.cpu / 100; colorFill: Qt.lighter(root.mauve, 1.35); icon: "\u{f035b}"; title: "CPU"
        valueText: Math.round(root.cpu) + "%"
    } }
    Component { id: ramFace; UsageCard {
        value: root.ramPercent / 100; colorFill: Qt.lighter(root.mauve, 1.15); icon: "\u{f035c}"; title: "RAM"
        valueText: root.ramGb.toFixed(1) + "G"
    } }
    Component { id: tempFace; UsageCard {
        value: Math.max(0, Math.min(1, root.tempC / 100)); colorFill: root.mauve; icon: "\u{f050f}"; title: "Temp"
        valueText: Math.round(root.tempC) + "°"
    } }
    Component { id: diskFace; UsageCard {
        value: root.diskPercent / 100; colorFill: Qt.darker(root.mauve, 1.15); icon: "\u{f02ca}"
        title: root.diskTotalGb > 0 ? root.diskTotalGb.toFixed(1) + "G" : ""
        subText: root.diskGb > 0 ? root.diskGb.toFixed(1) + "G" : "..."
        valueText: Math.round(root.diskPercent) + "%"
    } }

    Component {
        id: avatarFace
        Item {
            id: av
            property string variant: "round"
            readonly property real side: Math.min(width, height)
            readonly property real r: variant === "rounded" ? Math.round(root.radiusBase * 1.5) : side / 2
            Rectangle {
                anchors.centerIn: parent
                width: av.side; height: av.side
                radius: av.r
                color: root.surface1
                visible: avImg.status !== Image.Ready
                Text {
                    anchors.centerIn: parent
                    text: "\u{f0009}"
                    font.family: root.iconFont
                    font.pixelSize: av.side / 2
                    color: root.textCol
                }
            }
            Image {
                id: avImg
                anchors.centerIn: parent
                width: av.side; height: av.side
                visible: false
                fillMode: Image.PreserveAspectCrop
                sourceSize: Qt.size(400, 400)
                property int attempt: 0
                source: root.currentUser.name !== "" ? Qt.resolvedUrl("avatars/" + root.currentUser.name + ".png") : ""
                onStatusChanged: {
                    if (status === Image.Error && attempt === 0 && root.currentUser.icon !== "") {
                        attempt = 1;
                        source = root.currentUser.icon.indexOf("/") === 0 ? "file://" + root.currentUser.icon : root.currentUser.icon;
                    }
                }
            }
            Rectangle { id: avMask; anchors.fill: avImg; radius: av.r; visible: false; layer.enabled: true }
            MultiEffect {
                anchors.fill: avImg
                source: avImg
                maskEnabled: true
                maskSource: avMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
                visible: avImg.status === Image.Ready
            }
        }
    }

    Component {
        id: userFace
        Pill {
            property string variant: "filled"
            icon: "\u{f0009}"
            label: root.currentUser.name
            accent: variant === "plain" ? "transparent" : Qt.lighter(root.surface0, 1.28)
            interactive: root.users.length > 1
            onClicked: if (root.users.length > 1) root.userIndex = (root.userIndex + 1) % root.users.length
        }
    }

    Component {
        id: statusFace
        Pill {
            property string variant: "filled"
            icon: "\u{f033e}"
            label: root.statusText
            fg: root.failed ? root.red : root.textCol
            accent: variant === "plain" ? "transparent" : Qt.lighter(root.surface0, 1.28)
        }
    }

    Component {
        id: passwordFace
        Rectangle {
            id: field
            property string variant: "filled"
            radius: root.radiusBase
            color: variant === "glass" ? Qt.alpha(Qt.lighter(root.surface0, 1.28), 0.45) : Qt.lighter(root.surface0, 1.28)
            readonly property color signal_: root.failed ? root.red : (root.authenticating ? root.peach : root.mauve)
            readonly property real boxSize: height - 8

            Connections {
                target: root
                function onShakeRequested() { shake.restart(); }
            }
            transform: Translate { id: shakeT; x: 0 }
            SequentialAnimation {
                id: shake
                NumberAnimation { target: shakeT; property: "x"; to: -10; duration: 50 }
                NumberAnimation { target: shakeT; property: "x"; to: 10; duration: 70 }
                NumberAnimation { target: shakeT; property: "x"; to: -6; duration: 60 }
                NumberAnimation { target: shakeT; property: "x"; to: 6; duration: 60 }
                NumberAnimation { target: shakeT; property: "x"; to: 0; duration: 50 }
            }

            Rectangle {
                id: lockBox
                x: 4
                anchors.verticalCenter: parent.verticalCenter
                width: field.boxSize; height: field.boxSize
                radius: Math.max(4, root.radiusBase - 4)
                color: root.failed ? Qt.alpha(root.red, 0.16) : (root.authenticating ? Qt.alpha(root.peach, 0.16) : Qt.lighter(root.surface0, 1.55))
                Text {
                    id: lockIcon
                    anchors.centerIn: parent
                    text: "\u{f033e}"
                    font.family: root.iconFont
                    font.pixelSize: 20
                    color: root.failed ? root.red : (root.authenticating ? root.peach : root.subtext0)
                    RotationAnimation on rotation {
                        running: root.authenticating; from: 0; to: 360; duration: 1000; loops: Animation.Infinite
                        onRunningChanged: if (!running) lockIcon.rotation = 0
                    }
                }
            }
            Rectangle {
                id: submitBtn
                x: parent.width - width - 4
                anchors.verticalCenter: parent.verticalCenter
                width: field.boxSize; height: field.boxSize
                radius: Math.max(4, root.radiusBase - 4)
                color: submitMa.containsMouse ? Qt.lighter(field.signal_, 1.12) : field.signal_
                Behavior on color { ColorAnimation { duration: 150 } }
                Text {
                    anchors.centerIn: parent
                    text: "\u{f0142}"
                    font.family: root.iconFont
                    font.pixelSize: 20
                    color: root.crust
                }
                MouseArea {
                    id: submitMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.submit()
                }
            }
            Item {
                id: dotArea
                anchors.left: lockBox.right
                anchors.right: submitBtn.left
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                clip: true
                T {
                    anchors.centerIn: parent
                    visible: pwd.text.length === 0
                    text: "Enter PIN"
                    font.pixelSize: 14
                    color: root.subtext0
                }
                Row {
                    id: dots
                    spacing: 2
                    anchors.verticalCenter: parent.verticalCenter
                    x: implicitWidth <= dotArea.width ? (dotArea.width - implicitWidth) / 2 : dotArea.width - implicitWidth
                    Repeater {
                        model: pwd.text.length
                        delegate: Rectangle {
                            width: 16; height: 16
                            radius: Math.round(width * 0.24)
                            color: root.textCol
                            scale: 0
                            Component.onCompleted: scale = 1
                            Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                        }
                    }
                    Rectangle {
                        width: 2; height: 20
                        radius: 1
                        color: field.signal_
                        visible: pwd.activeFocus && pwd.text.length > 0
                        SequentialAnimation on opacity {
                            loops: Animation.Infinite
                            running: true
                            NumberAnimation { to: 0; duration: 500 }
                            NumberAnimation { to: 1; duration: 500 }
                        }
                    }
                }
                TextInput {
                    id: pwd
                    anchors.fill: parent
                    opacity: 0
                    echoMode: TextInput.Password
                    passwordMaskDelay: 0
                    enabled: !root.authenticating && !root.unlocking
                    Component.onCompleted: root.pwdField = pwd
                    onTextEdited: {
                        idleTimer.restart();
                        if (!root.inputActive && text.length > 0) root.inputActive = true;
                        if (text.length > 0) { root.failed = false; root.statusText = "Enter PIN"; }
                        else if (!root.failed) root.statusText = "Locked";
                    }
                    Keys.onPressed: (event) => {
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            root.submit(); event.accepted = true;
                        } else if (event.key === Qt.Key_Escape) {
                            if (root.powerMenuOpen) root.powerMenuOpen = false;
                            else root.inputActive = false;
                            pwd.text = "";
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
                            event.accepted = true;
                        }
                    }
                }
            }
        }
    }

    Component {
        id: keyboardFace
        Pill {
            property string variant: "button"
            implicitHeight: 36
            implicitWidth: Math.max(52, Math.min(100, contentWidth + pad * 2))
            pad: 12
            icon: "\u{f030c}"
            label: root.kbLayout
            textSize: 12
            interactive: root.hasKeyboard && keyboard.layouts.length > 1
            onClicked: root.switchLayout()
        }
    }

    Component {
        id: batteryFace
        Pill {
            property string variant: "button"
            visible: root.hasBattery
            implicitHeight: 36
            pad: 12
            icon: root.batCharging ? "\u{f0084}" : (root.batCap > 20 ? "\u{f0079}" : "\u{f0083}")
            label: root.batCaps.length > 1 ? root.batCaps.map(c => c + "%").join(" · ") : root.batCap + "%"
            TextMetrics { id: tmTot; font.family: root.fontFamily; font.pixelSize: 12; font.weight: Font.DemiBold; text: root.batCap + "%" }
            readonly property real extraWidth: Math.max(0, pLabelWidth - tmTot.advanceWidth)
            textSize: 12
            fg: root.batCharging ? root.green : (root.batCap <= 15 ? root.red : (root.batCap <= 25 ? root.peach : root.textCol))
        }
    }

    Component {
        id: notificationsFace
        Item {
            id: nf
            property string variant: "card"
            readonly property bool plain: variant === "plain"
            readonly property real emptyGraphicSize: Math.min(110, height * 0.4)
            Rectangle {
                anchors.fill: parent
                anchors.topMargin: 2
                anchors.bottomMargin: -2
                radius: 16
                color: Qt.rgba(0, 0, 0, 0.14)
                visible: !nf.plain && !root.glassActive
            }
            Rectangle {
                anchors.fill: parent
                radius: 16
                clip: true
                color: nf.plain ? "transparent" : Qt.alpha(Qt.lighter(root.surface0, 1.28), root.elementOpacity)
                border.width: nf.plain ? 0 : 1
                border.color: Qt.rgba(root.textCol.r, root.textCol.g, root.textCol.b, 0.06)
                Frost { z: -1; anchors.fill: parent; r: 16; visible: root.glassActive && !nf.plain }
            }
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 8
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    T {
                        Layout.alignment: Qt.AlignVCenter
                        Layout.leftMargin: 4
                        text: "Notifications"
                        font.weight: Font.Bold
                        font.pixelSize: 12
                        color: root.liquid ? root.textCol : root.subtext0
                    }
                    Item { Layout.fillWidth: true }
                    Pill {
                        Layout.preferredWidth: 86
                        Layout.preferredHeight: 32
                        radius: 10
                        pad: 10
                        icon: root.dnd ? "\u{f009b}" : "\u{f009a}"
                        iconSize: 14
                        label: root.dnd ? "Silent" : "Mute"
                        textSize: 11
                        accent: root.dnd ? root.blue : root.surface1
                        fg: root.dnd ? root.crust : root.textCol
                    }
                }
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 8
                        Item {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredWidth: root.showEmptyGraphic ? nf.emptyGraphicSize : 48
                            Layout.preferredHeight: root.showEmptyGraphic ? nf.emptyGraphicSize : 48
                            AnimatedImage {
                                anchors.fill: parent
                                visible: root.showEmptyGraphic
                                source: Qt.resolvedUrl("pushy.gif")
                                fillMode: Image.PreserveAspectFit
                                playing: visible
                            }
                            Text {
                                anchors.centerIn: parent
                                visible: !root.showEmptyGraphic
                                text: "\u{f009a}"
                                font.family: root.iconFont
                                font.pixelSize: 40
                                color: root.surface2
                            }
                        }
                        T {
                            Layout.alignment: Qt.AlignHCenter
                            text: "You're all caught up."
                            font.weight: Font.Medium
                            font.pixelSize: 12
                            color: root.liquid ? root.textCol : root.overlay0
                        }
                    }
                }
            }
        }
    }

    Component {
        id: musicFace
        Item {
            id: mf
            readonly property real dynMargin: Math.max(6, Math.min(24, height * 0.12))
            readonly property real dynSpacing: Math.max(4, Math.min(20, height * 0.08))
            readonly property real btnSize: Math.max(18, Math.min(56, height * 0.24))
            readonly property real iconSize: Math.round(btnSize * 0.3)
            readonly property real titleSize: Math.max(10, Math.min(24, height * 0.14))
            readonly property bool showArt: height >= 65 && width >= 180
            Rectangle {
                anchors.fill: parent
                radius: root.radiusBase
                color: Qt.alpha(root.surface0, root.elementOpacity)
                Frost { z: -1; anchors.fill: parent; r: parent.radius }
            }
            Item {
                anchors.fill: parent
                anchors.margins: mf.dynMargin
                Rectangle {
                    id: art
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: mf.showArt ? Math.min(200, mf.height - mf.dynMargin * 2) : 0
                    height: width
                    radius: root.radiusBase
                    color: Qt.alpha(root.surface1, root.elementOpacity)
                    visible: mf.showArt
                    Text {
                        anchors.centerIn: parent
                        text: "\u{f0388}"
                        font.family: root.iconFont
                        font.pixelSize: parent.width * 0.35
                        color: root.subtext0
                    }
                }
                Item {
                    anchors.left: mf.showArt ? art.right : parent.left
                    anchors.leftMargin: mf.showArt ? mf.dynSpacing : 0
                    anchors.right: parent.right
                    anchors.top: mf.showArt ? art.top : parent.top
                    anchors.bottom: mf.showArt ? art.bottom : parent.bottom
                    T {
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        text: "Nothing is playing"
                        font.weight: Font.Black
                        font.pixelSize: mf.titleSize
                        elide: Text.ElideRight
                    }
                    Row {
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        spacing: Math.max(2, mf.dynSpacing * 0.5)
                        Repeater {
                            model: [["\u{f04ae}", root.overlay2], ["\u{f040a}", root.textCol], ["\u{f04ad}", root.overlay2]]
                            delegate: IconBox {
                                required property var modelData
                                width: mf.btnSize; height: mf.btnSize
                                r: Math.max(4, mf.btnSize * 0.2)
                                icon: modelData[0]
                                iconSize: mf.iconSize
                                accent: root.surface1
                                bgOpacity: root.liquid ? 1.0 : root.elementOpacity
                                fg: modelData[1]
                            }
                        }
                    }
                }
            }
        }
    }

    Component {
        id: clockFace
        Item {
            id: ck
            readonly property bool isStacked: (width / height) < 1.25
            readonly property string hourFmt: root.is12h ? (root.timeFormat.indexOf("hh") !== -1 ? "hh" : "h") : (root.timeFormat.indexOf("H") !== -1 && root.timeFormat.indexOf("HH") === -1 ? "H" : "HH")
            readonly property string hoursText: Qt.formatDateTime(root.now, hourFmt)
            readonly property string minutesText: Qt.formatDateTime(root.now, "mm")
            readonly property string meridiem: root.is12h ? Qt.formatDateTime(root.now, "AP") : ""
            readonly property string dateText: Qt.formatDateTime(root.now, "dddd, d MMMM").toUpperCase()
            Column {
                visible: ck.isStacked
                anchors.centerIn: parent
                spacing: 8
                scale: Math.min(ck.width / Math.max(1, implicitWidth), ck.height / Math.max(1, implicitHeight))
                ShadowText { anchors.horizontalCenter: parent.horizontalCenter; text: ck.hoursText; color: root.mauve; font.pixelSize: 150; height: implicitHeight - 28 }
                ShadowText { anchors.horizontalCenter: parent.horizontalCenter; text: ck.minutesText; color: root.textCol; font.pixelSize: 150 }
                ShadowText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: ck.meridiem !== "" ? ck.meridiem + "  ·  " + ck.dateText : ck.dateText
                    color: root.subtext0; font.pixelSize: 16; font.weight: Font.Medium; font.letterSpacing: 1.4
                }
            }
            Column {
                visible: !ck.isStacked
                anchors.centerIn: parent
                spacing: 8
                scale: Math.min(ck.width / Math.max(1, implicitWidth), ck.height / Math.max(1, implicitHeight))
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 4
                    ShadowText { text: ck.hoursText; color: root.mauve; font.pixelSize: 120 }
                    ShadowText { text: ":"; color: root.subtext0; font.pixelSize: 80; anchors.verticalCenter: parent.verticalCenter }
                    ShadowText { text: ck.minutesText; color: root.textCol; font.pixelSize: 120 }
                    ShadowText {
                        visible: text !== ""
                        text: ck.meridiem
                        color: root.subtext0
                        font.pixelSize: 28
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 24
                    }
                }
                ShadowText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: ck.dateText
                    color: root.subtext0; font.pixelSize: 16; font.weight: Font.Medium; font.letterSpacing: 1.4
                }
            }
        }
    }

    function faceFor(type) {
        switch (type) {
        case "widget:weather": return weatherFace;
        case "widget:cpu": return cpuFace;
        case "widget:ram": return ramFace;
        case "widget:temp": return tempFace;
        case "widget:disk": return diskFace;
        case "widget:music": return musicFace;
        case "avatar": return avatarFace;
        case "user": return userFace;
        case "lockstatus": return statusFace;
        case "password": return passwordFace;
        case "keyboard": return keyboardFace;
        case "battery": return batteryFace;
        case "notifications": return notificationsFace;
        case "clock": return clockFace;
        }
        return null;  // fingerprint and anything SDDM can't do
    }

    // One positioned element (LockLayoutView delegate).
    component Slot: Item {
        id: slot
        property var e: ({})
        property real coreLeft: -1e9
        property real coreRight: 1e9
        property real reveal: 1
        readonly property bool auto: !(e.iw > 0 && e.ih > 0)
        readonly property real extra: (auto && loader.item && loader.item.extraWidth) ? loader.item.extraWidth : 0
        readonly property real bw: auto ? (loader.item ? loader.item.implicitWidth - extra : 0) : e.iw
        readonly property real bh: auto ? (loader.item ? loader.item.implicitHeight : 0) : e.ih
        readonly property real rot: e.irotation || 0
        readonly property bool rot90: Math.abs(Math.round(rot)) % 180 !== 0
        readonly property bool inCore: x + width / 2 >= coreLeft && x + width / 2 <= coreRight
        x: auto ? e.ix - bw / 2 : e.ix
        y: auto ? e.iy - bh / 2 : e.iy
        width: rot90 ? bh : bw
        height: rot90 ? bw : bh
        opacity: inCore ? 1.0 : reveal
        visible: loader.sourceComponent !== null
        Loader {
            id: loader
            width: slot.bw + slot.extra
            height: slot.bh
            x: (slot.width - slot.bw) / 2
            anchors.verticalCenter: parent.verticalCenter
            rotation: slot.rot
            opacity: slot.e.iopacity !== undefined ? slot.e.iopacity : 1
            sourceComponent: root.faceFor(slot.e.itype)
            onLoaded: if (item.variant !== undefined && slot.e.ivariant) item.variant = slot.e.ivariant
        }
    }

    // content
    Item {
        id: content
        anchors.fill: parent
        opacity: root.contentReveal * root.mainOpacity
        transform: Translate { y: 20 * (1 - root.contentReveal) }

        MouseArea {
            anchors.fill: parent
            onClicked: {
                if (root.powerMenuOpen) root.powerMenuOpen = false;
                root.activate("");
            }
        }

        // Reference canvas (your logical screen size from Serpantinum), scaled to this screen.
        Item {
            id: stage
            width: root.refW
            height: root.refH
            anchors.centerIn: parent
            scale: root.fit

            // Screen elements (LockClock.qml): hidden while the panel is open.
            Item {
                anchors.fill: parent
                readonly property bool concealed: root.inputActive || root.centerReveal > 0.02
                opacity: concealed ? 0 : 1
                scale: concealed ? 0.92 : 1
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                Repeater {
                    model: root.screenItems
                    delegate: Slot { required property var modelData; e: modelData }
                }
            }

            // Dashboard panel (LockDashboard.qml).
            Rectangle {
                id: shellShadow
                x: shell.x; y: shell.y + 1.5
                width: shell.width; height: shell.height
                radius: shell.radius
                color: Qt.rgba(0, 0, 0, 0.14 * root.panelOpacity)
                opacity: shell.opacity
                scale: shell.scale
                visible: shell.visible
            }
            Rectangle {
                id: shell
                x: root.panelLeft + (root.panelW - root.shellWidth) / 2
                y: root.panelTop + (root.inputActive ? 0 : 90)
                width: root.shellWidth
                height: root.panelH
                radius: root.radiusBase * 1.5
                color: Qt.alpha(root.surface0, root.elementOpacity * root.panelOpacity)
                clip: true
                opacity: root.centerReveal
                scale: (0.92 + root.centerReveal * 0.08) * root.foldScale
                visible: opacity > 0.01
                Behavior on y { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

                Frost { z: -1; anchors.fill: parent; r: shell.radius; opacity: root.panelOpacity }

                Item {
                    x: (shell.width - root.panelW) / 2
                    width: root.panelW
                    height: root.panelH
                    Repeater {
                        model: root.panelItems
                        delegate: Slot {
                            required property var modelData
                            e: modelData
                            reveal: root.wingsReveal
                            coreLeft: (root.panelW - root.coreWidth) / 2
                            coreRight: (root.panelW + root.coreWidth) / 2
                        }
                    }
                }
            }
        }

        // bottom tray: session (only if there's a choice) + power (LockPowerControls.qml)
        Pill {
            id: sessionPill
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.leftMargin: 20 * root.fit
            anchors.bottomMargin: 16 * root.fit
            visible: root.sessions.length > 1 && opacity > 0.01
            opacity: root.inputActive ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
            implicitHeight: 48
            pad: 16
            icon: "\u{f0379}"
            label: root.sessionName
            interactive: true
            scale: root.fit
            transformOrigin: Item.BottomLeft
            onClicked: root.sessionIndex = (root.sessionIndex + 1) % Math.max(1, root.sessions.length)
        }

        Item {
            id: tray
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 16 * root.fit
            anchors.rightMargin: 20 * root.fit
            width: 48; height: 48
            scale: root.fit
            transformOrigin: Item.BottomRight
            opacity: root.inputActive ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }

            Rectangle {
                anchors.fill: parent
                radius: root.radiusBase
                color: root.powerMenuOpen ? root.surface2 : (pma.containsMouse ? Qt.lighter(root.surface0, 1.45) : Qt.lighter(root.surface0, 1.28))
                Behavior on color { ColorAnimation { duration: 150 } }
                Text {
                    anchors.centerIn: parent
                    text: root.powerMenuOpen ? "\u{f0156}" : "\u{f0425}"
                    font.family: root.iconFont
                    font.pixelSize: 20
                    color: root.powerMenuOpen ? root.textCol : root.red
                }
                MouseArea {
                    id: pma
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.powerMenuOpen = !root.powerMenuOpen
                }
            }

            Rectangle {
                id: powerMenu
                anchors.bottom: parent.top
                anchors.bottomMargin: 16
                anchors.right: parent.right
                width: 320
                height: root.powerMenuOpen ? menuCol.implicitHeight + 24 : 0
                radius: root.radiusBase
                clip: true
                visible: height > 0
                opacity: root.powerMenuOpen ? 1 : 0
                color: Qt.rgba(root.surface0.r, root.surface0.g, root.surface0.b, 0.45 * root.elementOpacity)
                Frost { z: -1; anchors.fill: parent; r: parent.radius }
                Behavior on height { NumberAnimation { duration: 340; easing.type: Easing.OutBack; easing.overshoot: 1.15 } }
                Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

                Column {
                    id: menuCol
                    anchors.top: parent.top
                    anchors.topMargin: 12
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 8
                    HoldButton {
                        width: parent.width
                        visible: typeof sddm === "undefined" || !sddm || sddm.canSuspend
                        icon: "\u{f04b2}"; label: "Suspend"; accent: root.mauve
                        onTriggered: { root.powerMenuOpen = false; sddm.suspend(); fired = false; fill = 0; }
                    }
                    HoldButton {
                        width: parent.width
                        visible: typeof sddm === "undefined" || !sddm || sddm.canReboot
                        icon: "\u{f0453}"; label: "Reboot"; accent: root.blue
                        onTriggered: sddm.reboot()
                    }
                    HoldButton {
                        width: parent.width
                        visible: typeof sddm === "undefined" || !sddm || sddm.canPowerOff
                        icon: "\u{f0425}"; label: "Power off"; accent: root.red
                        onTriggered: sddm.powerOff()
                    }
                }
            }
        }
    }

    Component.onCompleted: root.forceActiveFocus()
}
