// Git repos desktop widget
// Face: git icon + number of repos that have something to commit or push.
// Left click: dropdown listing those repos (changes, commits ahead/behind,
// unpublished branches, stashes). Tick repos and "Commit & push": the face asks
// for a commit message, then commits everything (git add -A) and pushes, with
// a progress bar in the face and the git output in the dropdown.
// Folders scanned: ~/.config/serpantinum/gitrepos.conf (one per line, "!path"
// hides a repo), default ~/Code.
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

    readonly property string scriptPath: Qt.resolvedUrl("gitrepos.py").toString().replace(/^file:\/\//, "")
    readonly property string terminal: "kitty"

    property bool scanning: false
    property bool hasScanned: false
    property double lastScan: 0
    property double lastFetch: 0
    property string errorText: ""
    property bool popupOpen: false
    property bool wantsKeyboardFocus: false

    readonly property int attentionCount: repoModel.count
    property int cleanCount: 0
    property int dirtyCount: 0
    property int pushCount: 0
    property int behindCount: 0
    property int selectedCount: 0
    property int selectedDirty: 0
    readonly property real rowH: Scaler.s(48)

    // run: idle -> message (commit message in the face) -> running -> done / failed
    property string runState: "idle"
    property var pendingPaths: []
    property real progress: 0
    property string phase: ""
    property string lastLine: ""

    function ic(cp) { return String.fromCodePoint(cp); }

    readonly property color statusColor: errorText !== "" ? ThemeBackend.red
        : (attentionCount > 0 ? ThemeBackend.peach : ThemeBackend.green)

    // path, name, rel, branch, upstream, ahead, behind, unpublished, changes,
    // staged, modified, untracked, conflicts, stashes, hasRemote, filesText, checked, expanded
    ListModel { id: repoModel }
    ListModel { id: logModel }

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
    function needsAttention(r) {
        return r.changes > 0 || r.conflicts > 0 || r.ahead > 0 || (r.hasRemote && r.unpublished > 0);
    }

    function scan(fetch) {
        if (root.previewMode || scanner.running || root.runState === "running") return;
        root.scanning = true;
        scanner.command = ["python3", root.scriptPath, "scan"].concat(fetch ? ["--fetch"] : []);
        if (fetch) root.lastFetch = Date.now();
        scanner.running = true;
    }

    Process {
        id: scanner
        running: false
        onExited: root.scanning = false
        stdout: StdioCollector {
            onStreamFinished: {
                root.scanning = false;
                root.hasScanned = true;
                root.lastScan = Date.now();
                try {
                    let d = JSON.parse(this.text);
                    root.errorText = "";
                    let keep = {}, open = {};
                    for (let i = 0; i < repoModel.count; i++) {
                        let it = repoModel.get(i);
                        if (it.checked) keep[it.path] = true;
                        if (it.expanded) open[it.path] = true;
                    }
                    let list = d.repos || [];
                    let need = [], clean = 0, dirty = 0, push = 0, behind = 0;
                    for (let i = 0; i < list.length; i++) {
                        let r = list[i];
                        if (r.behind > 0) behind++;
                        if (root.needsAttention(r)) need.push(r); else clean++;
                    }
                    // most urgent first: dirty, then unpushed
                    need.sort(function(a, b) {
                        if ((a.changes > 0) !== (b.changes > 0)) return a.changes > 0 ? -1 : 1;
                        return a.name.localeCompare(b.name);
                    });
                    repoModel.clear();
                    for (let i = 0; i < need.length; i++) {
                        let r = need[i];
                        if (r.changes > 0) dirty++;
                        if (r.ahead > 0 || (r.hasRemote && r.unpublished > 0)) push++;
                        let lines = [];
                        for (let j = 0; j < r.files.length; j++) lines.push(r.files[j].st + "  " + r.files[j].path);
                        if (r.changes > r.files.length) lines.push("… " + (r.changes - r.files.length) + " more");
                        repoModel.append({
                            path: r.path, name: r.name, rel: r.rel, branch: r.branch, upstream: r.upstream,
                            ahead: r.ahead, behind: r.behind, unpublished: r.unpublished, changes: r.changes,
                            staged: r.staged, modified: r.modified, untracked: r.untracked,
                            conflicts: r.conflicts, stashes: r.stashes, hasRemote: r.hasRemote,
                            filesText: lines.join("\n"),
                            checked: !!keep[r.path], expanded: !!open[r.path]
                        });
                    }
                    root.cleanCount = clean;
                    root.dirtyCount = dirty;
                    root.pushCount = push;
                    root.behindCount = behind;
                } catch (e) {
                    root.errorText = "Could not read the repo list";
                }
                root.recountSelection();
            }
        }
    }

    Timer {   // local state every 2 min (cheap, no network)
        interval: 2 * 60 * 1000; repeat: true; running: !root.previewMode
        onTriggered: root.scan(Date.now() - root.lastFetch > 30 * 60 * 1000)
    }

    Component.onCompleted: Qt.callLater(function() { root.scan(true); })

    // ---------- selection ----------
    function recountSelection() {
        let n = 0, d = 0;
        for (let i = 0; i < repoModel.count; i++) {
            let it = repoModel.get(i);
            if (it.checked) { n++; if (it.changes > 0) d++; }
        }
        root.selectedCount = n;
        root.selectedDirty = d;
    }

    function toggleIndex(i) {
        repoModel.setProperty(i, "checked", !repoModel.get(i).checked);
        recountSelection();
    }

    function shortStatus(m) {
        let parts = [];
        if (m.conflicts > 0) parts.push(m.conflicts + " conflicts");
        if (m.changes > 0) parts.push(m.changes + (m.changes === 1 ? " change" : " changes"));
        if (m.ahead > 0) parts.push("↑" + m.ahead);
        if (m.behind > 0) parts.push("↓" + m.behind);
        if (!m.upstream && m.hasRemote && m.unpublished > 0) parts.push("not pushed (" + m.unpublished + ")");
        if (!m.hasRemote) parts.push("no remote");
        if (m.stashes > 0) parts.push(m.stashes + " stashed");
        return parts.join(" · ");
    }

    // ---------- commit & push ----------
    function begin(paths, dirty) {
        if (paths.length === 0 || root.runState === "running" || root.runState === "message") return;
        root.pendingPaths = paths;
        root.popupOpen = false;
        if (dirty > 0) {
            root.runState = "message";
            root.setKeyboardFocus(true);
            focusTimer.restart();
        } else {
            startRun("");
        }
    }

    Timer { id: focusTimer; interval: 60; onTriggered: msgInput.forceInputFocus() }

    function commitAll() {
        let p = [], d = 0;
        for (let i = 0; i < repoModel.count; i++) {
            let it = repoModel.get(i);
            p.push(it.path);
            if (it.changes > 0) d++;
        }
        begin(p, d);
    }

    function commitSelected() {
        let p = [];
        for (let i = 0; i < repoModel.count; i++) if (repoModel.get(i).checked) p.push(repoModel.get(i).path);
        begin(p, root.selectedDirty);
    }

    function cancelMessage() {
        msgInput.clear();
        root.runState = "idle";
        root.setKeyboardFocus(false);
    }

    function startRun(msg) {
        if (runner.running) return;
        msgInput.clear();
        root.setKeyboardFocus(false);
        logModel.clear();
        root.progress = 0;
        root.lastLine = "";
        root.phase = "Starting…";
        root.runState = "running";
        runner.command = ["python3", root.scriptPath, "run", msg].concat(root.pendingPaths);
        runner.running = true;
    }

    Process {
        id: runner
        running: false
        stdout: SplitParser {
            onRead: data => {
                let line = String(data);
                let m = line.match(/^@@REPO (\d+)\/(\d+) (.*)$/);
                if (m) {
                    root.phase = m[3] + "  " + m[1] + "/" + m[2];
                    root.progress = (+m[1] - 0.5) / +m[2];
                    return;
                }
                if (line.indexOf("@@") === 0) return;
                logModel.append({ line: line });
                if (line.trim() !== "") root.lastLine = line.trim();
            }
        }
        stderr: SplitParser {
            onRead: data => logModel.append({ line: String(data) })
        }
        onExited: (code, status) => {
            root.progress = 1;
            root.runState = code === 0 ? "done" : "failed";
            root.phase = code === 0 ? "Committed and pushed" : "Some repos failed";
            for (let i = 0; i < repoModel.count; i++) repoModel.setProperty(i, "checked", false);
            root.recountSelection();
            rescanTimer.restart();
            if (code === 0) resetTimer.restart();
        }
    }

    Timer { id: rescanTimer; interval: 500; onTriggered: root.scan(false) }
    Timer { id: resetTimer; interval: 60 * 1000; onTriggered: if (root.runState === "done") root.runState = "idle" }

    function dismissResult() {
        root.runState = "idle";
        root.popupOpen = false;
    }

    function openTerminal(path) {
        Quickshell.execDetached([root.terminal, "--directory", path]);
        root.popupOpen = false;
    }

    function togglePopup() {
        root.popupOpen = !root.popupOpen;
        if (root.popupOpen && root.runState === "idle" && Date.now() - root.lastScan > 30 * 1000) root.scan(false);
    }

    // ---------- face ----------
    Rectangle {
        id: bg
        anchors.fill: parent
        color: Qt.alpha(ThemeBackend.surface0, ThemeBackend.elementOpacity)
        radius: ThemeBackend.borderRadius
        clip: true
        border.width: root.popupOpen || root.runState === "message" ? 1 : 0
        border.color: Qt.alpha(ThemeBackend.mauve, 0.6)

        WallpaperBlur {
            z: -1
            anchors.fill: parent
            radius: parent.radius
        }

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: ThemeBackend.text
            opacity: faceMa.containsMouse && root.runState !== "message" ? 0.05 : 0.0
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
                text: root.ic(0xF02A2)   // git
                opacity: root.scanning && !root.hasScanned ? 0.5 : 1.0
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
                    text: !root.hasScanned ? "…"
                        : (root.attentionCount > 0 ? String(root.attentionCount)
                        : (root.errorText !== "" ? "Error" : "All clean"))
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                Text {
                    font.family: ThemeBackend.fontFamily
                    font.weight: Font.Bold
                    font.pixelSize: Math.max(Scaler.s(9), Math.min(Scaler.s(12), root.height * 0.13))
                    color: root.errorText !== "" ? ThemeBackend.red : ThemeBackend.subtext0
                    text: {
                        if (root.scanning && !root.hasScanned) return "Scanning…";
                        if (root.errorText !== "") return root.errorText;
                        if (root.attentionCount > 0) {
                            let p = [];
                            if (root.dirtyCount > 0) p.push(root.dirtyCount + " to commit");
                            if (root.pushCount > 0) p.push(root.pushCount + " to push");
                            return p.join(" · ");
                        }
                        let s = root.cleanCount + (root.cleanCount === 1 ? " repo" : " repos");
                        return root.behindCount > 0 ? s + " · " + root.behindCount + " behind" : s;
                    }
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }
        }

        // running / done / failed
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
            }

            Rectangle {
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
            visible: root.runState !== "message"
            acceptedButtons: Qt.LeftButton
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.togglePopup()
        }

        // message: commit message inside the widget
        ColumnLayout {
            anchors.fill: parent
            anchors.leftMargin: Scaler.s(12)
            anchors.rightMargin: Scaler.s(12)
            spacing: Scaler.s(6)
            visible: root.runState === "message"

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
                    color: ThemeBackend.text
                    text: "Commit & push " + root.pendingPaths.length + (root.pendingPaths.length === 1 ? " repo" : " repos")
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
                        onClicked: root.cancelMessage()
                    }
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: Scaler.s(32)

                Input {
                    id: msgInput
                    anchors.fill: parent
                    fontPixelSize: Scaler.s(11)
                    horizontalPadding: Scaler.s(8)
                    cornerRadius: ThemeBackend.borderRadius
                    baseColor: ThemeBackend.surface1
                    bgOpacity: ThemeBackend.elementOpacity
                    textColor: ThemeBackend.text
                    subTextColor: ThemeBackend.subtext0
                    accentColor: ThemeBackend.mauve
                    leadingIcon: root.ic(0xF0718)   // source-commit
                    placeholderText: "Commit message, Enter to push"
                    unfocusOnOutsideClick: false
                    onAccepted: function(t) { if (t.trim() !== "") root.startRun(t.trim()); }
                    Keys.onEscapePressed: root.cancelMessage()
                }

                MouseArea {
                    anchors.fill: parent
                    visible: !root.wantsKeyboardFocus
                    cursorShape: Qt.IBeamCursor
                    onClicked: {
                        root.setKeyboardFocus(true);
                        msgInput.forceInputFocus();
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
        implicitWidth: Math.max(Scaler.s(360), bg.width)
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
                        text: root.ic(0xF02A2)   // git
                    }
                    Text {
                        Layout.fillWidth: true
                        font.family: ThemeBackend.fontFamily
                        font.weight: Font.Bold
                        font.pixelSize: Scaler.s(13)
                        color: ThemeBackend.text
                        text: root.runState === "idle" ? "Git repos" : root.phase
                        elide: Text.ElideRight
                    }
                    Text {
                        visible: root.runState === "idle"
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: Scaler.s(10)
                        color: ThemeBackend.subtext0
                        text: root.scanning ? "scanning…"
                            : (root.hasScanned ? Qt.formatTime(new Date(root.lastScan), "hh:mm") : "")
                    }
                    Text {
                        visible: root.runState === "idle"
                        font.family: ThemeBackend.iconFont
                        font.pixelSize: Scaler.s(15)
                        color: refreshMa.containsMouse ? ThemeBackend.mauve : ThemeBackend.subtext0
                        text: root.ic(0xF0450)   // refresh (also fetches)
                        MouseArea {
                            id: refreshMa
                            anchors.fill: parent
                            anchors.margins: -Scaler.s(6)
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.scan(true)
                        }
                    }
                }

                // ----- log -----
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Scaler.s(200)
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
                            color: /error|fatal|failed|rejected/i.test(model.line) ? ThemeBackend.red
                                : (/^==>/.test(model.line) ? ThemeBackend.mauve : ThemeBackend.subtext1)
                            text: model.line
                        }
                    }
                }

                Rectangle {
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

                // ----- repo list (idle) -----
                Rectangle {   // Commit & push all
                    Layout.fillWidth: true
                    Layout.preferredHeight: Scaler.s(38)
                    visible: root.runState === "idle" && root.attentionCount > 0
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
                            text: root.ic(0xF0552)   // upload
                        }
                        Text {
                            font.family: ThemeBackend.fontFamily
                            font.weight: Font.Bold
                            font.pixelSize: Scaler.s(12)
                            color: ThemeBackend.crust
                            text: (root.dirtyCount > 0 ? "Commit & push all (" : "Push all (") + root.attentionCount + ")"
                        }
                    }
                    MouseArea {
                        id: allMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.commitAll()
                    }
                }

                RowLayout {   // empty state
                    Layout.fillWidth: true
                    visible: root.runState === "idle" && root.attentionCount === 0
                    spacing: Scaler.s(8)
                    Text {
                        font.family: ThemeBackend.iconFont
                        font.pixelSize: Scaler.s(16)
                        color: root.statusColor
                        text: root.errorText !== "" ? root.ic(0xF0026) : root.ic(0xF05E0)
                    }
                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: Scaler.s(11)
                        color: ThemeBackend.subtext0
                        text: root.errorText !== "" ? root.errorText
                            : (root.scanning ? "Scanning repos…" : "Everything is committed and pushed")
                    }
                }

                ListView {
                    id: list
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(contentHeight, Scaler.s(380))
                    visible: root.runState === "idle" && count > 0
                    clip: true
                    model: repoModel
                    spacing: Scaler.s(2)
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: Rectangle {
                        id: rowItem
                        width: list.width
                        height: root.rowH + (model.expanded ? filesText.implicitHeight + Scaler.s(8) : 0)
                        radius: ThemeBackend.borderRadius * 0.6
                        color: rowMa.containsMouse ? Qt.alpha(ThemeBackend.surface1, 0.8)
                            : (model.checked ? Qt.alpha(ThemeBackend.mauve, 0.12) : "transparent")
                        Behavior on color { ColorAnimation { duration: 120 } }

                        MouseArea {
                            id: rowMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.toggleIndex(index)
                        }

                        RowLayout {
                            id: rowTop
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            height: root.rowH
                            anchors.leftMargin: Scaler.s(8)
                            anchors.rightMargin: Scaler.s(8)
                            spacing: Scaler.s(10)

                            Text {   // checkbox
                                font.family: ThemeBackend.iconFont
                                font.pixelSize: Scaler.s(17)
                                color: model.checked ? ThemeBackend.mauve : ThemeBackend.overlay1
                                text: model.checked ? root.ic(0xF0132) : root.ic(0xF0131)
                            }
                            Text {   // state icon: pencil = changes, arrow = to push
                                font.family: ThemeBackend.iconFont
                                font.pixelSize: Scaler.s(16)
                                color: model.conflicts > 0 ? ThemeBackend.red
                                    : (model.changes > 0 ? ThemeBackend.peach : ThemeBackend.blue)
                                text: model.changes > 0 || model.conflicts > 0 ? root.ic(0xF03EB) : root.ic(0xF0552)
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Scaler.s(6)
                                    Text {
                                        font.family: ThemeBackend.fontFamily
                                        font.weight: Font.Bold
                                        font.pixelSize: Scaler.s(12)
                                        color: ThemeBackend.text
                                        text: model.name
                                        elide: Text.ElideRight
                                        Layout.maximumWidth: rowTop.width * 0.5
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                        font.family: ThemeBackend.fontFamily
                                        font.pixelSize: Scaler.s(10)
                                        color: ThemeBackend.overlay1
                                        text: model.branch
                                    }
                                }
                                Text {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    font.family: ThemeBackend.fontFamily
                                    font.pixelSize: Scaler.s(10)
                                    color: ThemeBackend.subtext0
                                    text: root.shortStatus(model)
                                }
                            }
                            Text {   // expand file list
                                visible: model.changes > 0
                                font.family: ThemeBackend.iconFont
                                font.pixelSize: Scaler.s(16)
                                color: expMa.containsMouse ? ThemeBackend.mauve : ThemeBackend.subtext0
                                text: model.expanded ? root.ic(0xF0143) : root.ic(0xF0140)   // chevron up/down
                                MouseArea {
                                    id: expMa
                                    anchors.fill: parent
                                    anchors.margins: -Scaler.s(5)
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: repoModel.setProperty(index, "expanded", !model.expanded)
                                }
                            }
                            Text {   // open a terminal in the repo
                                font.family: ThemeBackend.iconFont
                                font.pixelSize: Scaler.s(15)
                                color: termMa.containsMouse ? ThemeBackend.mauve : ThemeBackend.subtext0
                                text: root.ic(0xF018D)   // console
                                MouseArea {
                                    id: termMa
                                    anchors.fill: parent
                                    anchors.margins: -Scaler.s(5)
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.openTerminal(model.path)
                                }
                            }
                        }

                        Text {
                            id: filesText
                            visible: model.expanded
                            anchors.top: rowTop.bottom
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: Scaler.s(44)
                            anchors.rightMargin: Scaler.s(8)
                            font.family: "monospace"
                            font.pixelSize: Scaler.s(9)
                            color: ThemeBackend.subtext1
                            elide: Text.ElideMiddle
                            text: model.filesText
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    visible: root.runState === "idle" && root.attentionCount > 0 && root.cleanCount > 0
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: Scaler.s(10)
                    color: ThemeBackend.overlay1
                    text: root.cleanCount + (root.cleanCount === 1 ? " other repo is clean" : " other repos are clean")
                        + (root.behindCount > 0 ? " · " + root.behindCount + " behind their remote" : "")
                }

                Rectangle {   // Commit & push selected
                    Layout.fillWidth: true
                    Layout.preferredHeight: Scaler.s(34)
                    visible: root.runState === "idle" && root.attentionCount > 0
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
                            text: root.ic(0xF0718)   // source-commit
                        }
                        Text {
                            font.family: ThemeBackend.fontFamily
                            font.weight: Font.Bold
                            font.pixelSize: Scaler.s(11)
                            color: parent.parent.active ? ThemeBackend.text : ThemeBackend.overlay1
                            text: !parent.parent.active ? "Tick repos to commit and push them"
                                : ((root.selectedDirty > 0 ? "Commit & push selected (" : "Push selected (") + root.selectedCount + ")")
                        }
                    }
                    MouseArea {
                        id: selMa
                        anchors.fill: parent
                        enabled: parent.active
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.commitSelected()
                    }
                }
            }
        }
    }
}
