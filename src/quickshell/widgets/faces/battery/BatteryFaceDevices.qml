// "Batteries" widget: laptop + Bluetooth / UPower peripherals.
// Small sizes show rings (iOS small/medium widget); wide+tall sizes show a list (iOS large).
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Services.UPower
import Quickshell.Bluetooth
import "../../../reusables"
import "../../../"

Item {
    id: root
    anchors.fill: parent
    clip: true

    property bool previewMode: false

    property real minWidth: 90
    property real minHeight: 90
    property real maxWidth: 700
    property real maxHeight: 700
    property real minAspect: 0.4
    property real maxAspect: 6.0
    property bool isRound: false

    // Show connected BT devices that don't report a battery (dim ring, "-")
    property bool showNoBattery: true

    property var devices: []

    // glyphs (Symbols Nerd Font)
    readonly property string gLaptop:   String.fromCodePoint(0xF0322)
    readonly property string gHead:     String.fromCodePoint(0xF02CB)
    readonly property string gMouse:    String.fromCodePoint(0xF037D)
    readonly property string gKeyboard: String.fromCodePoint(0xF030C)
    readonly property string gPhone:    String.fromCodePoint(0xF03F2)
    readonly property string gPad:      String.fromCodePoint(0xF02B4)
    readonly property string gSpeaker:  String.fromCodePoint(0xF04C3)
    readonly property string gWatch:    String.fromCodePoint(0xF0589)
    readonly property string gTablet:   String.fromCodePoint(0xF04F6)
    readonly property string gPen:      String.fromCodePoint(0xF03EA)
    readonly property string gBt:       String.fromCodePoint(0xF00AF)
    readonly property string gBolt:     String.fromCodePoint(0xF140B)

    function guessIcon(kind, name) {
        let t = (kind || "").toLowerCase();
        let n = (name || "").toLowerCase();
        let has = (s, w) => s.indexOf(w) !== -1;
        if (has(t, "headset") || has(t, "headphone") || has(n, "headphone") || has(n, "buds") || has(n, "pods") || has(n, "wh-") || has(n, "wf-")) return gHead;
        if (has(t, "mouse") || has(n, "mouse") || has(n, "mx ")) return gMouse;
        if (has(t, "keyboard") || has(n, "keyboard") || has(n, "keys")) return gKeyboard;
        if (has(t, "phone") || has(n, "phone") || has(n, "pixel") || has(n, "galaxy")) return gPhone;
        if (has(t, "gaming") || has(t, "joystick") || has(t, "controller") || has(n, "controller") || has(n, "dualsense") || has(n, "xbox")) return gPad;
        if (has(t, "speaker") || has(t, "audio") || has(n, "speaker")) return gSpeaker;
        if (has(t, "watch") || has(n, "watch") || has(n, "band")) return gWatch;
        if (has(t, "tablet") || has(n, "tab ") || has(n, "ipad")) return gTablet;
        if (has(t, "pen") || has(t, "stylus")) return gPen;
        return gBt;
    }

    function upowerKind(dev) {
        // Map UPowerDeviceType to a keyword guessIcon understands
        let ty = dev.type;
        if (ty === UPowerDeviceType.Mouse) return "mouse";
        if (ty === UPowerDeviceType.Keyboard) return "keyboard";
        if (ty === UPowerDeviceType.Headset || ty === UPowerDeviceType.Headphones) return "headset";
        if (ty === UPowerDeviceType.Phone) return "phone";
        if (ty === UPowerDeviceType.GamingInput) return "gaming";
        if (ty === UPowerDeviceType.Speakers) return "speaker";
        if (ty === UPowerDeviceType.Tablet) return "tablet";
        if (ty === UPowerDeviceType.Pen) return "pen";
        if (ty === UPowerDeviceType.Wearable) return "watch";
        return "";
    }

    function listOf(model) {
        if (!model) return [];
        let vals = model.values !== undefined ? model.values : model;
        let out = [];
        let count = vals.length !== undefined ? vals.length : (vals.count !== undefined ? vals.count : 0);
        for (let i = 0; i < count; i++) {
            let d = vals[i] !== undefined ? vals[i] : (vals.get ? vals.get(i) : null);
            if (d) out.push(d);
        }
        return out;
    }

    function rebuild() {
        let out = [];
        let dbg = [];

        // 1. This laptop
        try {
            let dd = UPower.displayDevice;
            let laptopHas = dd.ready ? dd.isLaptopBattery : !SystemInfo.isDesktop;
            // T470 dual battery: one ring per laptop battery (BAT0 internal, BAT1 external)
            let lbats = listOf(UPower.devices).filter(u => u && u.isLaptopBattery)
                .sort((a, b) => String(a.nativePath || "").localeCompare(String(b.nativePath || "")));
            if (laptopHas && lbats.length > 1) {
                for (let i = 0; i < lbats.length; i++) {
                    let b = lbats[i];
                    out.push({
                        key: "laptop" + i,
                        name: lbats.length === 2 ? (i === 0 ? "Internal" : "External") : ("Battery " + (i + 1)),
                        icon: gLaptop,
                        num: i + 1,
                        pct: Math.round(b.percentage * 100),
                        charging: b.state === UPowerDeviceState.Charging || b.state === UPowerDeviceState.FullyCharged
                    });
                }
            } else if (laptopHas) {
                out.push({
                    key: "laptop",
                    name: "ThinkPad",
                    icon: gLaptop,
                    pct: dd.ready ? Math.round(dd.percentage * 100) : -1,
                    charging: dd.ready && (dd.state === UPowerDeviceState.Charging || dd.state === UPowerDeviceState.FullyCharged)
                });
            }
        } catch (e) { dbg.push("laptop err: " + e); }

        // 2. UPower peripherals (hidpp mice, bluez batteries, controllers…)
        //    Kept in a list so Bluetooth devices can claim them by MAC or by name.
        let peri = [];
        try {
            let ups = listOf(UPower.devices);
            dbg.push("upower devices: " + ups.length);
            for (let u of ups) {
                if (!u) continue;
                dbg.push("  up " + u.nativePath + " model=" + u.model + " ps=" + u.powerSupply + " pct=" + u.percentage);
                if (u.powerSupply || u.isLaptopBattery) continue;
                if (u.type === UPowerDeviceType.LinePower) continue;
                let np = (u.nativePath || "").toUpperCase().replace(/_/g, ":");
                let m = np.match(/([0-9A-F]{2}(:[0-9A-F]{2}){5})/);
                peri.push({ u: u, addr: m ? m[1] : "", name: (u.model || "").toLowerCase(), used: false });
            }
        } catch (e) { dbg.push("upower err: " + e); }

        function periFor(addr, name) {
            let n = (name || "").toLowerCase();
            for (let p of peri) if (!p.used && p.addr && p.addr === addr) return p;
            for (let p of peri) if (!p.used && p.name && n && (p.name === n || n.indexOf(p.name) !== -1 || p.name.indexOf(n) !== -1)) return p;
            return null;
        }

        // 3. Connected Bluetooth devices (battery from BlueZ, else from matching UPower entry)
        try {
            let bts = listOf(Bluetooth.defaultAdapter ? Bluetooth.defaultAdapter.devices : null);
            dbg.push("bt devices: " + bts.length);
            for (let d of bts) {
                if (!d || !d.connected) continue;
                let addr = (d.address || "").toUpperCase();
                let nm = d.name || d.deviceName || addr;
                let p = periFor(addr, nm);
                if (p) p.used = true;
                let pct = -1, chg = false;
                if (d.batteryAvailable) pct = Math.round(d.battery * 100);
                else if (p) { pct = Math.round(p.u.percentage * 100); chg = p.u.state === UPowerDeviceState.Charging; }
                dbg.push("  bt " + nm + " " + addr + " pct=" + pct + " match=" + (p ? p.u.nativePath : "none"));
                if (pct < 0 && !root.showNoBattery) continue;
                out.push({ key: "bt:" + addr, name: nm, icon: guessIcon(d.icon || (p ? upowerKind(p.u) : ""), nm), pct: pct, charging: chg });
            }
        } catch (e) { dbg.push("bt err: " + e); }

        // 4. Remaining UPower peripherals (receiver-connected, other adapters…)
        for (let p of peri) {
            if (p.used) continue;
            try {
                let u = p.u;
                if (u.percentage <= 0 && !u.isPresent) continue;
                let nm = u.model || "Device";
                out.push({ key: "up:" + (u.nativePath || nm), name: nm, icon: guessIcon(upowerKind(u), nm), pct: Math.round(u.percentage * 100), charging: u.state === UPowerDeviceState.Charging });
            } catch (e) { dbg.push("peri err: " + e); }
        }

        // Only replace the model if something changed (avoids ring re-animations)
        let js = JSON.stringify(out);
        if (js !== JSON.stringify(root.devices)) {
            root.devices = out;
        }
    }

    Timer {
        interval: 4000
        repeat: true
        running: root.visible
        triggeredOnStart: true
        onTriggered: root.rebuild()
    }
    Connections {
        target: UPower.displayDevice
        ignoreUnknownSignals: true
        function onPercentageChanged() { root.rebuild(); }
        function onStateChanged() { root.rebuild(); }
    }
    Component.onCompleted: rebuild()

    function ringColor(pct, charging) {
        if (pct < 0) return ThemeBackend.overlay0;
        if (charging) return ThemeBackend.green;
        if (pct <= 10) return ThemeBackend.red;
        if (pct <= 20) return ThemeBackend.yellow;
        return ThemeBackend.green;
    }

    // layout choice
    readonly property real pad: Scaler.s(12)
    readonly property int count: devices.length
    readonly property real listRowH: Scaler.s(44)
    readonly property bool listMode: width >= Scaler.s(240) && (height - pad * 2) >= Math.max(2, count) * listRowH

    // Ring grid: pick the column count that gives the biggest rings
    readonly property var gridFit: {
        let n = Math.max(1, count);
        let w = width - pad * 2, h = height - pad * 2;
        let best = { cols: 1, rows: n, cell: 0 };
        for (let c = 1; c <= n; c++) {
            let r = Math.ceil(n / c);
            let cell = Math.min(w / c, h / r / 1.22);   // 1.22: room for % under the ring
            if (cell > best.cell) best = { cols: c, rows: r, cell: cell };
        }
        return best;
    }

    // reusable ring
    component Ring : Item {
        id: ring
        property real pct: -1
        property bool charging: false
        property string glyph: ""
        property int num: 0   // >0: battery outline with this number inside (T470 BAT0/BAT1)
        property real thickness: Math.max(Scaler.s(3), width * 0.09)
        property color accent: root.ringColor(pct, charging)

        property real anim: 0
        Behavior on anim { NumberAnimation { duration: 900; easing.type: Easing.OutQuint } }
        Component.onCompleted: anim = Math.max(0, pct)
        onPctChanged: anim = Math.max(0, pct)

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: "transparent"
                strokeColor: Qt.alpha(ring.accent, 0.22)
                strokeWidth: ring.thickness
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: ring.width / 2; centerY: ring.height / 2
                    radiusX: (ring.width - ring.thickness) / 2; radiusY: radiusX
                    startAngle: 0; sweepAngle: 360
                }
            }
            ShapePath {
                fillColor: "transparent"
                strokeColor: ring.accent
                strokeWidth: ring.thickness
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: ring.width / 2; centerY: ring.height / 2
                    radiusX: (ring.width - ring.thickness) / 2; radiusY: radiusX
                    startAngle: -90; sweepAngle: 360 * ring.anim / 100
                }
            }
        }

        Text {
            anchors.centerIn: parent
            font.family: ThemeBackend.iconFont
            font.pixelSize: ring.width * 0.40
            color: ring.pct < 0 ? ThemeBackend.subtext0 : ThemeBackend.text
            text: ring.num > 0 ? String.fromCodePoint(0xF008E) : ring.glyph
        }
        Text {
            visible: ring.num > 0
            anchors.centerIn: parent
            anchors.verticalCenterOffset: ring.width * 0.40 * 0.07
            font.family: ThemeBackend.fontFamily
            font.bold: true
            font.pixelSize: ring.width * 0.40 * 0.42
            color: ThemeBackend.text
            text: ring.num
        }

        // charging badge
        Rectangle {
            visible: ring.charging
            width: ring.width * 0.34; height: width; radius: width / 2
            anchors.right: parent.right; anchors.top: parent.top
            anchors.rightMargin: -width * 0.1; anchors.topMargin: -width * 0.1
            color: ThemeBackend.green
            border.width: Scaler.s(2)
            border.color: ThemeBackend.surface0
            Text {
                anchors.centerIn: parent
                font.family: ThemeBackend.iconFont
                font.pixelSize: parent.width * 0.62
                color: ThemeBackend.crust
                text: root.gBolt
            }
        }
    }

    Rectangle {
        id: bg
        anchors.fill: parent
        color: Qt.alpha(ThemeBackend.surface0, ThemeBackend.elementOpacity)
        radius: ThemeBackend.borderRadius
        clip: true

        WallpaperBlur { z: -1; anchors.fill: parent; radius: parent.radius }

        // click anywhere -> open Serpantinum's Bluetooth panel
        MouseArea {
            anchors.fill: parent
            enabled: !root.previewMode
            cursorShape: Qt.PointingHandCursor
            onClicked: Quickshell.execDetached(["sh", "-c", 'mkdir -p "$1" && printf %s "$2" > "$1/mode"; exec quickshell -p "$3" ipc call main handleCommand toggle network "$2"', "sh", Caching.getCacheDir("network"), "bt", Caching.serpantinumDir + "/quickshell/Shell.qml"])
        }

        Text {
            anchors.centerIn: parent
            visible: root.count === 0
            font.family: ThemeBackend.fontFamily
            font.weight: Font.Bold
            font.pixelSize: Scaler.s(12)
            color: ThemeBackend.subtext0
            text: "No devices"
        }

        // ring grid (iOS small / medium)
        Grid {
            visible: !root.listMode && root.count > 0
            anchors.centerIn: parent
            columns: root.gridFit.cols
            Repeater {
                model: root.listMode ? [] : root.devices
                Item {
                    width: root.gridFit.cell
                    height: root.gridFit.cell * 1.22
                    Ring {
                        id: r
                        width: parent.width * 0.74; height: width
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: parent.width * 0.08
                        pct: modelData.pct
                        charging: modelData.charging
                        glyph: modelData.icon
                        num: modelData.num || 0
                    }
                    Text {
                        anchors.top: r.bottom
                        anchors.topMargin: parent.width * 0.04
                        anchors.horizontalCenter: parent.horizontalCenter
                        font.family: ThemeBackend.fontFamily
                        font.weight: Font.Bold
                        font.pixelSize: Math.max(Scaler.s(9), parent.width * 0.17)
                        color: ThemeBackend.text
                        text: modelData.pct < 0 ? "—" : modelData.pct + "%"
                    }
                }
            }
        }

        // list (iOS large)
        Column {
            visible: root.listMode
            anchors.fill: parent
            anchors.margins: root.pad
            spacing: 0
            Repeater {
                model: root.listMode ? root.devices : []
                Item {
                    width: parent.width
                    height: root.listRowH
                    RowLayout {
                        anchors.fill: parent
                        spacing: Scaler.s(12)
                        Ring {
                            Layout.preferredWidth: root.listRowH * 0.8
                            Layout.preferredHeight: root.listRowH * 0.8
                            Layout.alignment: Qt.AlignVCenter
                            pct: modelData.pct
                            charging: modelData.charging
                            glyph: modelData.icon
                        num: modelData.num || 0
                        }
                        Text {
                            Layout.fillWidth: true
                            font.family: ThemeBackend.fontFamily
                            font.weight: Font.Bold
                            font.pixelSize: Scaler.s(13)
                            color: ThemeBackend.text
                            elide: Text.ElideRight
                            text: modelData.name
                        }
                        Text {
                            font.family: ThemeBackend.fontFamily
                            font.weight: Font.Black
                            font.pixelSize: Scaler.s(17)
                            color: modelData.pct < 0 ? ThemeBackend.subtext0 : ThemeBackend.text
                            text: modelData.pct < 0 ? "—" : modelData.pct + "%"
                        }
                    }
                }
            }
        }
    }
}
