// Arch updates desktop widget
// Face: update icon + number of pending updates (repo + AUR).
// Left click: dropdown with "Update all" and a list of packages you can tick
// and update individually. Updates run inside the widget: it asks for the sudo
// password in the face, then shows a progress bar, and the dropdown shows the log.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../../reusables"
import "../../../"

Item {
    id: root
    anchors.fill: parent

    property bool previewMode: false

    property real minWidth: 140
    property real minHeight: 60
    property real maxWidth: 420
    property real maxHeight: 160
    property real minAspect: 1.4
    property real maxAspect: 5.0
    property bool isRound: false

    readonly property string scriptPath: Qt.resolvedUrl("updates.sh").toString().replace(/^file:\/\//, "")
    readonly property string runnerPath: Qt.resolvedUrl("run-update.sh").toString().replace(/^file:\/\//, "")

    property string helper: ""          // yay / paru / "" (no AUR helper)
    property string errorText: ""
    property bool checking: false
    property bool hasChecked: false
    property double lastCheck: 0
    property string lastLogStamp: ""
    property bool popupOpen: false
    property bool wantsKeyboardFocus: false

    readonly property int updateCount: pkgModel.count
    property int aurCount: 0
    property int selectedCount: 0
    property int selectedRepoCount: 0
    readonly property real rowH: Scaler.s(44)

    // update run: idle -> auth (password in the face) -> running -> done / failed
    property string runState: "idle"
    readonly property bool busy: runState === "auth" || runState === "running"
    property var pendingArgs: []
    property int pendingTotal: 0
    property int pendingAur: 0
    property bool authError: false
    property string _pw: ""
    property real progress: 0
    property string phase: ""
    property string lastLine: ""
    property int exitCode: 0
    // progress parser state
    property bool _aurStage: false
    property int _aurIdx: 0
    property int _dl: 0
    property string _section: ""

    function ic(cp) { return String.fromCodePoint(cp); }

    readonly property bool isError: errorText !== "" && updateCount === 0
    readonly property color statusColor: isError ? ThemeBackend.red
        : (updateCount > 0 ? ThemeBackend.peach : ThemeBackend.green)
    readonly property string statusIcon: isError ? ic(0xF0026)          // alert
        : (updateCount > 0 ? ic(0xF06B0) : ic(0xF05E0))                    // update / check-circle

    ListModel { id: pkgModel }   // name, oldVer, newVer, aur, checked
    ListModel { id: logModel }   // line

    // ---------- keyboard focus (same approach as the Obsidian widget) ----------
    function setKeyboardFocus(enable) {
        if (root.previewMode) return;
        root.wantsKeyboardFocus = enable;
        try {
            let win = root.Window ? root.Window.window : null;
            let targets = [];
            if (win) targets.push(win);
            let cur = root;
            while (cur) { targets.push(cur); if (!cur.parent) break; cur = cur.parent; }
            for (let i = 0; i < targets.length; i++) {
                let t = targets[i];
                if (!t) continue;
                if (t.wantsKeyboardFocus !== undefined) t.wantsKeyboardFocus = enable;
                if (t.focusable !== undefined) t.focusable = enable;
                if (t.WlrLayershell !== undefined) {
                    t.WlrLayershell.keyboardFocus = enable ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None;
                }
                if (enable && typeof t.requestActivate === "function") t.requestActivate();
            }
        } catch (e) {}
    }

    // ---------- data ----------
    function refresh() {
        if (root.previewMode || checker.running || root.runState === "running") return;
        root.checking = true;
        checker.running = true;
    }

    Process {
        id: checker
        running: false
        command: ["bash", root.scriptPath]
        onExited: root.checking = false
        stdout: StdioCollector {
            onStreamFinished: {
                root.checking = false;
                root.hasChecked = true;
                root.lastCheck = Date.now();
                try {
                    let d = JSON.parse(this.text);
                    root.helper = d.helper || "";
                    root.errorText = d.error || "";
                    let keep = {};
                    for (let i = 0; i < pkgModel.count; i++) {
                        let it = pkgModel.get(i);
                        if (it.checked) keep[it.name] = true;
                    }
                    let list = d.packages || [];
                    list.sort(function(a, b) {
                        if (a.aur !== b.aur) return a.aur ? 1 : -1;
                        return a.name.localeCompare(b.name);
                    });
                    pkgModel.clear();
                    let aur = 0;
                    for (let i = 0; i < list.length; i++) {
                        let p = list[i];
                        if (p.aur) aur++;
                        pkgModel.append({ name: p.name, oldVer: p.old, newVer: p.new, aur: !!p.aur, checked: !!keep[p.name] });
                    }
                    root.aurCount = aur;
                } catch (e) {
                    root.errorText = "Could not read the update list";
                }
                root.recountSelection();
            }
        }
    }

    // Re-check after pacman finishes (watches /var/log/pacman.log, also catches manual updates)
    Process {
        id: logStat
        running: false
        command: ["stat", "-c", "%Y", "/var/log/pacman.log"]
        stdout: StdioCollector {
            onStreamFinished: {
                let v = this.text.trim();
                if (v !== "" && root.lastLogStamp !== "" && v !== root.lastLogStamp && root.runState !== "running") postUpdateTimer.restart();
                if (v !== "") root.lastLogStamp = v;
            }
        }
    }
    Timer {
        interval: 10000; repeat: true; running: !root.previewMode
        onTriggered: if (!logStat.running) logStat.running = true
    }
    Timer { id: postUpdateTimer; interval: 4000; onTriggered: root.refresh() }
    Timer {   // periodic check every 30 min
        interval: 30 * 60 * 1000; repeat: true; running: !root.previewMode
        onTriggered: root.refresh()
    }

    Component.onCompleted: Qt.callLater(function() {
        root.refresh();
        if (!root.previewMode) logStat.running = true;
    })

    // ---------- selection ----------
    function recountSelection() {
        let n = 0, r = 0;
        for (let i = 0; i < pkgModel.count; i++) {
            let it = pkgModel.get(i);
            if (it.checked) { n++; if (!it.aur) r++; }
        }
        root.selectedCount = n;
        root.selectedRepoCount = r;
    }

    function toggleIndex(i) {
        pkgModel.setProperty(i, "checked", !pkgModel.get(i).checked);
        recountSelection();
    }

    // ---------- running updates ----------
    function askPassword(args, total, aur) {
        if (root.busy) return;
        root.pendingArgs = args;
        root.pendingTotal = Math.max(1, total);
        root.pendingAur = aur;
        root.authError = false;
        root.popupOpen = false;
        root.runState = "auth";
        root.setKeyboardFocus(true);
        focusTimer.restart();
    }

    Timer { id: focusTimer; interval: 60; onTriggered: pwInput.forceInputFocus() }

    function updateAll() {
        askPassword(["all"], root.updateCount, root.aurCount);
    }

    function updateSelected() {
        let repo = [], aur = [];
        for (let i = 0; i < pkgModel.count; i++) {
            let it = pkgModel.get(i);
            if (!it.checked) continue;
            (it.aur ? aur : repo).push(it.name);
        }
        if (repo.length + aur.length === 0) return;
        askPassword(["some"].concat(repo, ["--"], aur), repo.length + aur.length, aur.length);
    }

    function cancelAuth() {
        pwInput.clear();
        root.runState = "idle";
        root.setKeyboardFocus(false);
    }

    function startRun(pw) {
        if (pw === "" || runner.running) return;
        root._pw = pw;
        pwInput.clear();
        root.setKeyboardFocus(false);
        logModel.clear();
        root.progress = 0;
        root.phase = "Checking password…";
        root.lastLine = "";
        root._aurStage = false;
        root._aurIdx = 0;
        root._dl = 0;
        root._section = "";
        root.runState = "running";
        runner.command = ["bash", root.runnerPath].concat(root.pendingArgs);
        runner.running = true;
    }

    function finishRun(code) {
        root._pw = "";
        root.exitCode = code;
        if (code === 3) {               // wrong password: back to the field
            root.authError = true;
            root.runState = "auth";
            root.setKeyboardFocus(true);
            focusTimer.restart();
            return;
        }
        root.runState = code === 0 ? "done" : "failed";
        if (code === 0) { root.progress = 1; root.phase = "Updated"; }
        else root.phase = "Update failed (exit " + code + ")";
        postUpdateTimer.restart();
        if (code === 0) resetTimer.restart();
    }

    Timer { id: resetTimer; interval: 5 * 60 * 1000; onTriggered: if (root.runState === "done") root.runState = "idle" }

    function dismissResult() {
        root.runState = "idle";
        root.popupOpen = false;
    }

    function setProgress(p) {
        root.progress = Math.max(root.progress, Math.min(0.99, p));
    }

    // Turn pacman/yay output into a progress value and a short phase label.
    // The repo transaction fills the first part of the bar, AUR builds the rest.
    function parseLine(line) {
        let t = line.trim();
        if (t === "") return;
        let total = root.pendingTotal;
        let wRepo = total > 0 ? (total - root.pendingAur) / total : 1;
        if (root.pendingAur > 0 && wRepo > 0.95) wRepo = 0.95;
        function slice(f) {
            if (!root._aurStage) return wRepo * f;
            let n = Math.max(1, root.pendingAur);
            let i = Math.max(0, root._aurIdx - 1);
            return wRepo + (1 - wRepo) * (i + f) / n;
        }
        let m;
        if (t.indexOf("==> Making package:") === 0) {
            root._aurStage = true;
            root._aurIdx++;
            root.phase = "Building " + t.substring(20).trim().split(" ")[0] + " (AUR)";
            setProgress(slice(0.1));
        } else if (t.indexOf(":: Synchronizing package databases") === 0) {
            root.phase = "Syncing databases";
            setProgress(slice(0.03));
        } else if (t.indexOf(":: Retrieving packages") === 0) {
            root._section = "dl";
            root._dl = 0;
            root.phase = "Downloading";
            setProgress(slice(0.05));
        } else if (root._section === "dl" && / downloading\.\.\.$/.test(t)) {
            root._dl++;
            root.phase = "Downloading " + root._dl + "/" + total;
            setProgress(slice(0.05 + 0.40 * Math.min(1, root._dl / total)));
        } else if ((m = t.match(/^\((\d+)\/(\d+)\) (checking|loading)/))) {
            root._section = "check";
            root.phase = "Checking packages";
            setProgress(slice(0.47 + 0.06 * (+m[1] / +m[2])));
        } else if ((m = t.match(/^\((\d+)\/(\d+)\) (upgrading|installing|reinstalling|downgrading|removing) (\S+)/))) {
            root._section = "install";
            root.phase = m[3].charAt(0).toUpperCase() + m[3].substring(1) + " " + m[4] + "  " + m[1] + "/" + m[2];
            setProgress(slice(0.55 + 0.35 * (+m[1] / +m[2])));
        } else if (t.indexOf(":: Running post-transaction hooks") === 0) {
            root._section = "hooks";
            root.phase = "Running hooks";
            setProgress(slice(0.91));
        } else if (root._section === "hooks" && (m = t.match(/^\((\d+)\/(\d+)\)/))) {
            setProgress(slice(0.91 + 0.08 * (+m[1] / +m[2])));
        } else if (t.indexOf("there is nothing to do") >= 0) {
            root.phase = "Nothing to do";
        }
    }

    Process {
        id: runner
        running: false
        stdinEnabled: true
        onStarted: {
            runner.write(root._pw + "\n");
            root._pw = "";
        }
        stdout: SplitParser {
            onRead: data => {
                let line = String(data).replace(/\r/g, "");
                if (line.indexOf("@@") === 0) {
                    if (line === "@@AUTH ok") root.phase = "Starting…";
                    return;
                }
                logModel.append({ line: line });
                if (logModel.count > 400) logModel.remove(0, logModel.count - 400);
                if (line.trim() !== "") root.lastLine = line.trim();
                root.parseLine(line);
            }
        }
        onExited: (code, status) => root.finishRun(code)
    }

    function togglePopup() {
        root.popupOpen = !root.popupOpen;
        if (root.popupOpen && root.runState === "idle" && Date.now() - root.lastCheck > 2 * 60 * 1000) root.refresh();
    }

    // ---------- face ----------
    Rectangle {
        id: bg
        anchors.fill: parent
        color: Qt.alpha(ThemeBackend.surface0, ThemeBackend.elementOpacity)
        radius: ThemeBackend.borderRadius
        clip: true
        border.width: root.popupOpen || root.runState === "auth" ? 1 : 0
        border.color: Qt.alpha(root.authError ? ThemeBackend.red : ThemeBackend.mauve, 0.6)

        WallpaperBlur {
            z: -1
            anchors.fill: parent
            radius: parent.radius
        }

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: ThemeBackend.text
            opacity: faceMa.containsMouse && root.runState !== "auth" ? 0.05 : 0.0
            Behavior on opacity { NumberAnimation { duration: 150 } }
        }

        // idle: icon + count
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Scaler.s(16)
            anchors.rightMargin: Scaler.s(16)
            spacing: Scaler.s(14)
            visible: root.runState === "idle"

            Text {
                font.family: ThemeBackend.iconFont
                font.pixelSize: Math.max(Scaler.s(22), Math.min(Scaler.s(36), root.height * 0.36))
                color: root.statusColor
                text: root.statusIcon
                opacity: root.checking && !root.hasChecked ? 0.5 : 1.0
                Layout.alignment: Qt.AlignVCenter
                Behavior on color { ColorAnimation { duration: 250 } }
            }

            ColumnLayout {
                spacing: Scaler.s(2)
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter

                Text {
                    font.family: ThemeBackend.fontFamily
                    font.weight: Font.Black
                    font.pixelSize: Math.max(Scaler.s(14), Math.min(Scaler.s(24), root.height * 0.26))
                    color: ThemeBackend.text
                    text: !root.hasChecked ? "…"
                        : (root.updateCount > 0 ? String(root.updateCount)
                        : (root.isError ? "Error" : "Up to date"))
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                Text {
                    font.family: ThemeBackend.fontFamily
                    font.weight: Font.Bold
                    font.pixelSize: Math.max(Scaler.s(9), Math.min(Scaler.s(12), root.height * 0.13))
                    color: root.isError ? ThemeBackend.red : ThemeBackend.subtext0
                    text: {
                        if (root.checking) return "Checking…";
                        if (root.isError) return root.errorText;
                        if (root.updateCount > 0) {
                            let s = root.updateCount === 1 ? "update available" : "updates available";
                            return root.aurCount > 0 ? s + " · " + root.aurCount + " AUR" : s;
                        }
                        return root.hasChecked ? "Checked " + Qt.formatTime(new Date(root.lastCheck), "hh:mm") : "";
                    }
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }
        }

        // running / done / failed: phase + progress bar + last log line
        ColumnLayout {
            anchors.fill: parent
            anchors.leftMargin: Scaler.s(14)
            anchors.rightMargin: Scaler.s(14)
            spacing: Scaler.s(6)
            visible: root.runState === "running" || root.runState === "done" || root.runState === "failed"

            Item { Layout.fillHeight: true }

            RowLayout {
                Layout.fillWidth: true
                spacing: Scaler.s(8)
                Text {
                    id: runIcon
                    font.family: ThemeBackend.iconFont
                    font.pixelSize: Scaler.s(18)
                    color: root.runState === "failed" ? ThemeBackend.red
                        : (root.runState === "done" ? ThemeBackend.green : ThemeBackend.mauve)
                    text: root.runState === "failed" ? root.ic(0xF0026)
                        : (root.runState === "done" ? root.ic(0xF05E0) : root.ic(0xF0450))
                    RotationAnimation on rotation {
                        running: root.runState === "running"
                        from: 0; to: 360; duration: 1200; loops: Animation.Infinite
                        onStopped: runIcon.rotation = 0
                    }
                }
                Text {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    font.family: ThemeBackend.fontFamily
                    font.weight: Font.Bold
                    font.pixelSize: Scaler.s(12)
                    color: ThemeBackend.text
                    text: root.phase
                }
                Text {
                    font.family: ThemeBackend.fontFamily
                    font.weight: Font.Black
                    font.pixelSize: Scaler.s(12)
                    color: ThemeBackend.subtext0
                    text: Math.round(root.progress * 100) + "%"
                }
            }

            Rectangle {   // progress bar
                Layout.fillWidth: true
                Layout.preferredHeight: Scaler.s(6)
                radius: height / 2
                color: Qt.alpha(ThemeBackend.surface2, 0.6)
                Rectangle {
                    height: parent.height
                    radius: parent.radius
                    width: parent.width * root.progress
                    color: root.runState === "failed" ? ThemeBackend.red
                        : (root.runState === "done" ? ThemeBackend.green : ThemeBackend.mauve)
                    Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                }
            }

            Text {
                Layout.fillWidth: true
                elide: Text.ElideRight
                font.family: "monospace"
                font.pixelSize: Scaler.s(9)
                color: ThemeBackend.subtext0
                text: root.runState === "running" ? root.lastLine : "Click for the log"
            }

            Item { Layout.fillHeight: true }
        }

        MouseArea {
            id: faceMa
            anchors.fill: parent
            visible: root.runState !== "auth"
            acceptedButtons: Qt.LeftButton
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.togglePopup()
        }

        // auth: password field inside the widget
        ColumnLayout {
            anchors.fill: parent
            anchors.leftMargin: Scaler.s(12)
            anchors.rightMargin: Scaler.s(12)
            spacing: Scaler.s(6)
            visible: root.runState === "auth"

            Item { Layout.fillHeight: true }

            RowLayout {
                Layout.fillWidth: true
                spacing: Scaler.s(6)
                Text {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    font.family: ThemeBackend.fontFamily
                    font.weight: Font.Bold
                    font.pixelSize: Scaler.s(11)
                    color: root.authError ? ThemeBackend.red : ThemeBackend.text
                    text: root.authError ? "Wrong password, try again"
                        : "Update " + root.pendingTotal + (root.pendingTotal === 1 ? " package" : " packages")
                }
                Text {
                    font.family: ThemeBackend.iconFont
                    font.pixelSize: Scaler.s(14)
                    color: cancelMa.containsMouse ? ThemeBackend.red : ThemeBackend.subtext0
                    text: root.ic(0xF0156)   // close
                    MouseArea {
                        id: cancelMa
                        anchors.fill: parent
                        anchors.margins: -Scaler.s(6)
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.cancelAuth()
                    }
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: Scaler.s(32)

                Input {
                    id: pwInput
                    anchors.fill: parent
                    masked: true
                    fontPixelSize: Scaler.s(11)
                    horizontalPadding: Scaler.s(8)
                    cornerRadius: ThemeBackend.borderRadius
                    baseColor: ThemeBackend.surface1
                    bgOpacity: ThemeBackend.elementOpacity
                    textColor: ThemeBackend.text
                    subTextColor: ThemeBackend.subtext0
                    accentColor: ThemeBackend.mauve
                    hasError: root.authError
                    leadingIcon: root.ic(0xF033E)   // lock
                    placeholderText: "sudo password, Enter to start"
                    unfocusOnOutsideClick: false
                    onTextEdited: function(t) { if (root.authError) root.authError = false; }
                    onAccepted: function(t) { root.startRun(t); }
                    Keys.onEscapePressed: root.cancelAuth()
                }

                // if focus was lost, a click grabs it again
                MouseArea {
                    anchors.fill: parent
                    visible: !root.wantsKeyboardFocus
                    cursorShape: Qt.IBeamCursor
                    onClicked: {
                        root.setKeyboardFocus(true);
                        pwInput.forceInputFocus();
                    }
                }
            }

            Item { Layout.fillHeight: true }
        }
    }

    // ---------- dropdown ----------
    Timer { id: closeTimer; interval: 900; onTriggered: root.popupOpen = false }

    PopupWindow {
        id: popup
        visible: root.popupOpen && root.visible && !root.previewMode
        color: "transparent"
        anchor.item: bg
        anchor.rect.x: 0
        anchor.rect.y: bg.height + Scaler.s(8)
        anchor.rect.width: 1
        anchor.rect.height: 1
        implicitWidth: Math.max(Scaler.s(340), bg.width)
        implicitHeight: card.implicitHeight

        Rectangle {
            id: card
            width: popup.implicitWidth
            implicitHeight: col.implicitHeight + Scaler.s(24)
            color: ThemeBackend.base
            radius: ThemeBackend.borderRadius
            border.width: 1
            border.color: Qt.alpha(ThemeBackend.surface2, 0.6)

            HoverHandler {
                id: popupHover
                onHoveredChanged: hovered ? closeTimer.stop() : closeTimer.restart()
            }

            ColumnLayout {
                id: col
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Scaler.s(12)
                spacing: Scaler.s(8)

                // header
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Scaler.s(8)
                    Text {
                        font.family: ThemeBackend.iconFont
                        font.pixelSize: Scaler.s(16)
                        color: ThemeBackend.mauve
                        text: root.ic(0xF08C7)   // arch logo
                    }
                    Text {
                        Layout.fillWidth: true
                        font.family: ThemeBackend.fontFamily
                        font.weight: Font.Bold
                        font.pixelSize: Scaler.s(13)
                        color: ThemeBackend.text
                        text: root.runState === "idle" ? "Arch updates" : root.phase
                        elide: Text.ElideRight
                    }
                    Text {
                        visible: root.runState === "idle"
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: Scaler.s(10)
                        color: ThemeBackend.subtext0
                        text: root.checking ? "checking…"
                            : (root.hasChecked ? Qt.formatTime(new Date(root.lastCheck), "hh:mm") : "")
                    }
                    Text {
                        visible: root.runState === "idle"
                        font.family: ThemeBackend.iconFont
                        font.pixelSize: Scaler.s(15)
                        color: refreshMa.containsMouse ? ThemeBackend.mauve : ThemeBackend.subtext0
                        text: root.ic(0xF0450)   // refresh
                        MouseArea {
                            id: refreshMa
                            anchors.fill: parent
                            anchors.margins: -Scaler.s(6)
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.refresh()
                        }
                    }
                }

                // ----- log (while running and after) -----
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Scaler.s(220)
                    visible: root.runState === "running" || root.runState === "done" || root.runState === "failed"
                    radius: ThemeBackend.borderRadius * 0.6
                    color: ThemeBackend.crust

                    ListView {
                        id: logView
                        anchors.fill: parent
                        anchors.margins: Scaler.s(8)
                        clip: true
                        model: logModel
                        boundsBehavior: Flickable.StopAtBounds
                        onCountChanged: Qt.callLater(function() { logView.positionViewAtEnd(); })
                        delegate: Text {
                            width: logView.width
                            wrapMode: Text.WrapAnywhere
                            font.family: "monospace"
                            font.pixelSize: Scaler.s(9)
                            color: /error|failed|conflict/i.test(model.line) ? ThemeBackend.red
                                : (/^(::|==>)/.test(model.line.trim()) ? ThemeBackend.mauve
                                : (/warning/i.test(model.line) ? ThemeBackend.yellow : ThemeBackend.subtext1))
                            text: model.line
                        }
                    }
                }

                Rectangle {   // close the finished run
                    Layout.fillWidth: true
                    Layout.preferredHeight: Scaler.s(34)
                    visible: root.runState === "done" || root.runState === "failed"
                    radius: ThemeBackend.borderRadius
                    color: dismissMa.containsMouse ? ThemeBackend.surface2 : ThemeBackend.surface1
                    Text {
                        anchors.centerIn: parent
                        font.family: ThemeBackend.fontFamily
                        font.weight: Font.Bold
                        font.pixelSize: Scaler.s(11)
                        color: ThemeBackend.text
                        text: "Close"
                    }
                    MouseArea {
                        id: dismissMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.dismissResult()
                    }
                }

                // ----- package list (idle) -----
                Rectangle {   // Update all
                    Layout.fillWidth: true
                    Layout.preferredHeight: Scaler.s(38)
                    visible: root.runState === "idle" && root.updateCount > 0
                    radius: ThemeBackend.borderRadius
                    color: allMa.containsMouse ? Qt.lighter(ThemeBackend.mauve, 1.1) : ThemeBackend.mauve
                    Behavior on color { ColorAnimation { duration: 120 } }
                    RowLayout {
                        anchors.centerIn: parent
                        spacing: Scaler.s(8)
                        Text {
                            font.family: ThemeBackend.iconFont
                            font.pixelSize: Scaler.s(16)
                            color: ThemeBackend.crust
                            text: root.ic(0xF06B0)   // update
                        }
                        Text {
                            font.family: ThemeBackend.fontFamily
                            font.weight: Font.Bold
                            font.pixelSize: Scaler.s(12)
                            color: ThemeBackend.crust
                            text: "Update all (" + root.updateCount + ")"
                        }
                    }
                    MouseArea {
                        id: allMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.updateAll()
                    }
                }

                // empty / error state
                RowLayout {
                    Layout.fillWidth: true
                    visible: root.runState === "idle" && root.updateCount === 0
                    spacing: Scaler.s(8)
                    Text {
                        font.family: ThemeBackend.iconFont
                        font.pixelSize: Scaler.s(16)
                        color: root.statusColor
                        text: root.statusIcon
                    }
                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: Scaler.s(11)
                        color: ThemeBackend.subtext0
                        text: root.isError ? root.errorText
                            : (root.checking ? "Checking for updates…" : "Everything is up to date")
                    }
                }

                ListView {
                    id: list
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(count, 8) * root.rowH + Math.max(0, Math.min(count, 8) - 1) * spacing
                    visible: root.runState === "idle" && count > 0
                    clip: true
                    model: pkgModel
                    spacing: Scaler.s(2)
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: Rectangle {
                        width: list.width
                        height: root.rowH
                        radius: ThemeBackend.borderRadius * 0.6
                        color: rowMa.containsMouse ? Qt.alpha(ThemeBackend.surface1, 0.8)
                            : (model.checked ? Qt.alpha(ThemeBackend.mauve, 0.12) : "transparent")
                        Behavior on color { ColorAnimation { duration: 120 } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Scaler.s(8)
                            anchors.rightMargin: Scaler.s(10)
                            spacing: Scaler.s(10)

                            Text {   // checkbox
                                font.family: ThemeBackend.iconFont
                                font.pixelSize: Scaler.s(17)
                                color: model.checked ? ThemeBackend.mauve : ThemeBackend.overlay1
                                text: model.checked ? root.ic(0xF0132) : root.ic(0xF0131)
                            }
                            Text {   // package / AUR icon
                                font.family: ThemeBackend.iconFont
                                font.pixelSize: Scaler.s(16)
                                color: model.aur ? ThemeBackend.blue : ThemeBackend.subtext0
                                text: model.aur ? root.ic(0xF08C7) : root.ic(0xF03D6)
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                Text {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    font.family: ThemeBackend.fontFamily
                                    font.weight: Font.Bold
                                    font.pixelSize: Scaler.s(12)
                                    color: ThemeBackend.text
                                    text: model.name
                                }
                                Text {
                                    Layout.fillWidth: true
                                    elide: Text.ElideMiddle
                                    font.family: ThemeBackend.fontFamily
                                    font.pixelSize: Scaler.s(10)
                                    color: ThemeBackend.subtext0
                                    text: model.oldVer + "  →  " + model.newVer
                                }
                            }
                            Rectangle {   // AUR badge
                                visible: model.aur
                                implicitWidth: aurLabel.implicitWidth + Scaler.s(12)
                                implicitHeight: Scaler.s(18)
                                radius: height / 2
                                color: Qt.alpha(ThemeBackend.blue, 0.18)
                                Text {
                                    id: aurLabel
                                    anchors.centerIn: parent
                                    font.family: ThemeBackend.fontFamily
                                    font.weight: Font.Bold
                                    font.pixelSize: Scaler.s(9)
                                    color: ThemeBackend.blue
                                    text: "AUR"
                                }
                            }
                        }

                        MouseArea {
                            id: rowMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.toggleIndex(index)
                        }
                    }
                }

                // partial-upgrade warning
                RowLayout {
                    Layout.fillWidth: true
                    visible: root.runState === "idle" && root.selectedRepoCount > 0
                    spacing: Scaler.s(8)
                    Text {
                        Layout.alignment: Qt.AlignTop
                        font.family: ThemeBackend.iconFont
                        font.pixelSize: Scaler.s(14)
                        color: ThemeBackend.yellow
                        text: root.ic(0xF0026)
                    }
                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: Scaler.s(10)
                        color: ThemeBackend.yellow
                        text: "Updating only some repo packages is a partial upgrade and can break dependencies. Update all is the safe option."
                    }
                }

                Rectangle {   // Update selected
                    Layout.fillWidth: true
                    Layout.preferredHeight: Scaler.s(34)
                    visible: root.runState === "idle" && root.updateCount > 0
                    radius: ThemeBackend.borderRadius
                    readonly property bool active: root.selectedCount > 0
                    color: !active ? Qt.alpha(ThemeBackend.surface1, 0.4)
                        : (selMa.containsMouse ? ThemeBackend.surface2 : ThemeBackend.surface1)
                    Behavior on color { ColorAnimation { duration: 120 } }
                    RowLayout {
                        anchors.centerIn: parent
                        spacing: Scaler.s(8)
                        Text {
                            font.family: ThemeBackend.iconFont
                            font.pixelSize: Scaler.s(15)
                            color: parent.parent.active ? ThemeBackend.text : ThemeBackend.overlay1
                            text: root.ic(0xF01DA)   // download
                        }
                        Text {
                            font.family: ThemeBackend.fontFamily
                            font.weight: Font.Bold
                            font.pixelSize: Scaler.s(11)
                            color: parent.parent.active ? ThemeBackend.text : ThemeBackend.overlay1
                            text: parent.parent.active ? "Update selected (" + root.selectedCount + ")" : "Tick packages to update them"
                        }
                    }
                    MouseArea {
                        id: selMa
                        anchors.fill: parent
                        enabled: parent.active
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.updateSelected()
                    }
                }
            }
        }
    }
}
