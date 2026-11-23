// Google Calendar + Tasks agenda widget
// Top: events for the next 7 days, grouped by day (click opens it in Google Calendar).
// Bottom: open Google Tasks (click the circle to complete, + to add a task).
// Data comes from gsync.py next to this file (standard-library Python, OAuth token kept locally).
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
    property real minWidth: 260
    property real minHeight: 240
    property real maxWidth: 800
    property real maxHeight: 1100
    property real minAspect: 0.35
    property real maxAspect: 2.5
    property bool isRound: false

    readonly property string script: Qt.resolvedUrl("gsync.py").toString().replace(/^file:\/\//, "")
    readonly property string home: Quickshell.env("HOME")

    property string state_: "loading"   // loading | ok | no_client | signed_out | offline | error
    property string errorText: ""
    property var events: []
    property var tasks: []
    property double updated: 0
    property var doneIds: ({})          // optimistic: tasks ticked but not yet synced
    property bool addMode: false
    property bool wantsKeyboardFocus: false
    property date now: new Date()

    function ic(cp) { return String.fromCodePoint(cp); }

    // keyboard focus (same approach as the GitHub widget)
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
                if (t.WlrLayershell !== undefined)
                    t.WlrLayershell.keyboardFocus = enable ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None;
                if (enable && typeof t.requestActivate === "function") t.requestActivate();
            }
        } catch (e) {}
    }

    // data
    function applyData(d) {
        if (d.ok) {
            root.events = d.events || [];
            root.tasks = d.tasks || [];
            root.updated = d.updated || Date.now();
            root.state_ = "ok";
            root.errorText = "";
            root.doneIds = ({});
        } else {
            // keep the last data on screen when offline / temporary errors
            root.state_ = (d.state === "offline" || d.state === "error") && root.updated > 0 ? "ok" : (d.state || "error");
            root.errorText = d.state === "offline" ? "Offline, showing last sync" : (d.error || "");
        }
    }

    function refresh() {
        if (root.previewMode || fetcher.running) return;
        fetcher.running = true;
    }

    Process {
        id: fetcher
        running: false
        command: ["python3", root.script, "fetch"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.applyData(JSON.parse(this.text)); }
                catch (e) { root.state_ = "error"; root.errorText = "python3 missing or helper failed"; }
            }
        }
    }

    FileView {   // instant display from the last sync while the first fetch runs
        id: cacheFile
        path: root.home + "/.cache/serpantinum/google/data.json"
        onLoaded: {
            if (root.updated > 0) return;
            try { let d = JSON.parse(text()); if (d.ok) { root.applyData(d); } } catch (e) {}
        }
    }

    // queued actions (complete / add), then refresh
    property var actionQueue: []
    function runAction(args) {
        root.actionQueue = root.actionQueue.concat([args]);
        pumpActions();
    }
    function pumpActions() {
        if (actionProc.running || root.actionQueue.length === 0) return;
        let next = root.actionQueue[0];
        root.actionQueue = root.actionQueue.slice(1);
        actionProc.command = ["python3", root.script].concat(next);
        actionProc.running = true;
    }
    Process {
        id: actionProc
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let d = JSON.parse(this.text);
                    if (!d.ok) root.errorText = d.error || "Action failed";
                } catch (e) {}
            }
        }
        onExited: {
            if (root.actionQueue.length > 0) root.pumpActions();
            else refreshSoon.restart();
        }
    }
    Timer { id: refreshSoon; interval: 800; onTriggered: root.refresh() }

    Timer {   // every 5 min when signed in; every 5 s while waiting for sign-in
        interval: (root.state_ === "signed_out" || root.state_ === "no_client") ? 5000 : 5 * 60 * 1000
        repeat: true
        running: !root.previewMode
        onTriggered: root.refresh()
    }
    Timer { interval: 60 * 1000; repeat: true; running: true; onTriggered: root.now = new Date() }

    Component.onCompleted: Qt.callLater(root.refresh)

    function signIn() {
        Quickshell.execDetached(["kitty", "--title", "Google sign-in", "-e", "bash", "-c",
            'python3 "$1" auth; echo; read -n 1 -s -r -p "[press any key to close]"', "_", root.script]);
    }

    function completeTask(t) {
        let d = Object.assign({}, root.doneIds);
        d[t.id] = true;
        root.doneIds = d;
        runAction(["complete", t.listId, t.id]);
    }

    function addTask(text) {
        let title = text.trim();
        if (title === "") return;
        let due = "";
        let m = title.match(/\s+(today|oggi|tomorrow|domani)$/i);
        if (m) {
            let dd = new Date();
            if (/tomorrow|domani/i.test(m[1])) dd.setDate(dd.getDate() + 1);
            due = Qt.formatDate(dd, "yyyy-MM-dd");
            title = title.substring(0, m.index).trim();
        }
        // optimistic row
        root.tasks = [{ id: "pending-" + Date.now(), listId: "", list: "", title: title, due: due, notes: "", pending: true }].concat(root.tasks);
        runAction(due !== "" ? ["add", title, due] : ["add", title]);
    }

    function closeAdd() {
        root.addMode = false;
        taskInput.clear();
        taskInput.releaseFocus();
        root.setKeyboardFocus(false);
    }

    // helpers for labels
    function dayKey(d) { return Qt.formatDate(d, "yyyy-MM-dd"); }
    function dayLabel(key) {
        let today = new Date(root.now);
        let tomorrow = new Date(root.now); tomorrow.setDate(tomorrow.getDate() + 1);
        if (key === dayKey(today)) return "Today";
        if (key === dayKey(tomorrow)) return "Tomorrow";
        let p = key.split("-");
        return Qt.formatDate(new Date(+p[0], +p[1] - 1, +p[2]), "dddd d MMM");
    }
    function dueInfo(due) {
        if (!due) return { text: "", color: ThemeBackend.subtext0 };
        let today = dayKey(root.now);
        if (due < today) return { text: "Overdue · " + dayLabel(due), color: ThemeBackend.red };
        if (due === today) return { text: "Today", color: ThemeBackend.peach };
        return { text: dayLabel(due), color: ThemeBackend.subtext0 };
    }

    // day model
    readonly property string todayKey: dayKey(root.now)

    // 14 days starting today, for the week strip
    readonly property var stripDays: {
        let out = [];
        for (let i = 0; i < 14; i++) {
            let d = new Date(root.now.getFullYear(), root.now.getMonth(), root.now.getDate() + i);
            out.push({ key: dayKey(d), date: d });
        }
        return out;
    }

    // group events + tasks per day. overdue tasks go under today, undated under "" (No date)
    readonly property var groups: {
        let g = {};
        let add = function(k) { if (!g[k]) g[k] = { events: [], tasks: [] }; return g[k]; };
        add(root.todayKey);
        let nowMs = root.now.getTime();
        for (let i = 0; i < events.length; i++) {
            let e = events[i];
            if (!e.allDay && e.end <= nowMs) continue;
            add(e.day < root.todayKey ? root.todayKey : e.day).events.push(e);
        }
        for (let i = 0; i < tasks.length; i++) {
            let t = tasks[i];
            if (root.doneIds[t.id]) continue;
            let k = !t.due ? "" : (t.due < root.todayKey ? root.todayKey : t.due);
            add(k).tasks.push(t);
        }
        return g;
    }

    readonly property var rows: {
        let keys = Object.keys(groups).filter(function(k) { return k !== ""; }).sort();
        if (groups[""]) keys.push("");
        let out = [];
        for (let i = 0; i < keys.length; i++) {
            let k = keys[i];
            let grp = groups[k];
            out.push({ kind: "day", day: k, title: k === "" ? "No date" : dayLabel(k) });
            for (let j = 0; j < grp.events.length; j++) out.push({ kind: "event", day: k, e: grp.events[j] });
            for (let j = 0; j < grp.tasks.length; j++) out.push({ kind: "task", day: k, t: grp.tasks[j] });
            if (grp.events.length === 0 && grp.tasks.length === 0)
                out.push({ kind: "empty", day: k, title: "Nothing planned" });
        }
        return out;
    }

    // which day is highlighted in the strip: the hovered row's day, else the day at the top of the list
    property string hoverDay: ""
    property string topDay: root.todayKey
    readonly property string activeDay: (listHover.hovered && hoverDay !== "") ? hoverDay
        : (listHover.hovered && hoverDay === "" ? "" : topDay)

    function updateTopDay() {
        let idx = list.indexAt(Scaler.s(10), list.contentY + Scaler.s(4));
        if (idx >= 0 && idx < root.rows.length) root.topDay = root.rows[idx].day;
    }

    onActiveDayChanged: scrollStripTo(activeDay)
    onRowsChanged: Qt.callLater(root.updateTopDay)

    function scrollStripTo(key) {
        let idx = -1;
        for (let i = 0; i < stripDays.length; i++) if (stripDays[i].key === key) { idx = i; break; }
        if (idx < 0) return;
        let cellW = strip.width / 7;
        let firstVisible = strip.contentX / cellW;
        if (idx >= firstVisible - 0.01 && idx <= firstVisible + 6.01) return;   // already visible
        let target = Math.max(0, Math.min(strip.contentWidth - strip.width, (idx - 3) * cellW));
        stripAnim.stop();
        stripAnim.to = target;
        stripAnim.start();
    }

    function jumpListTo(key) {
        for (let i = 0; i < rows.length; i++) {
            if (rows[i].kind === "day" && rows[i].day === key) {
                let from = list.contentY;
                list.positionViewAtIndex(i, ListView.Beginning);
                let to = list.contentY;
                list.contentY = from;
                listAnim.stop();
                listAnim.to = to;
                listAnim.start();
                root.topDay = key;
                return;
            }
        }
    }

    // per-day dots for the strip
    function dotsFor(key) {
        let g = groups[key];
        if (!g) return { colors: [], tasks: 0 };
        let colors = [];
        for (let i = 0; i < g.events.length && colors.length < 3; i++) colors.push(g.events[i].color || ThemeBackend.mauve);
        return { colors: colors, tasks: g.tasks.length };
    }

    // UI
    Rectangle {
        id: bg
        anchors.fill: parent
        color: Qt.alpha(ThemeBackend.surface0, ThemeBackend.elementOpacity)
        radius: ThemeBackend.borderRadius
        clip: true

        WallpaperBlur { z: -1; anchors.fill: parent; radius: parent.radius }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Scaler.s(14)
            spacing: Scaler.s(8)

            // header: month + add task + refresh
            RowLayout {
                Layout.fillWidth: true
                spacing: Scaler.s(10)
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text {
                        font.family: ThemeBackend.fontFamily
                        font.weight: Font.Black
                        font.pixelSize: Scaler.s(17)
                        color: ThemeBackend.text
                        text: Qt.formatDate(root.now, "MMMM")
                    }
                    Text {
                        font.family: ThemeBackend.fontFamily
                        font.weight: Font.Bold
                        font.pixelSize: Scaler.s(10)
                        color: ThemeBackend.mauve
                        text: Qt.formatDate(root.now, "dddd d, yyyy")
                    }
                }
                Text {
                    visible: root.errorText !== "" && root.state_ === "ok"
                    font.family: ThemeBackend.iconFont
                    font.pixelSize: Scaler.s(14)
                    color: ThemeBackend.yellow
                    text: root.ic(0xF0026)
                    HoverHandler { id: warnHover }
                    ToolTipLite { show: warnHover.hovered; label: root.errorText }
                }
                Rectangle {   // + add task
                    visible: root.state_ === "ok"
                    implicitWidth: Scaler.s(28)
                    implicitHeight: Scaler.s(28)
                    radius: ThemeBackend.borderRadius
                    color: addMa.containsMouse ? ThemeBackend.mauve : Qt.alpha(ThemeBackend.surface1, ThemeBackend.elementOpacity)
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Text {
                        anchors.centerIn: parent
                        font.family: ThemeBackend.iconFont
                        font.pixelSize: Scaler.s(16)
                        color: addMa.containsMouse ? ThemeBackend.crust : ThemeBackend.mauve
                        text: root.ic(0xF0415)
                    }
                    MouseArea {
                        id: addMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.addMode = true;
                            root.setKeyboardFocus(true);
                            taskInput.forceInputFocus();
                        }
                    }
                }
                Text {
                    font.family: ThemeBackend.iconFont
                    font.pixelSize: Scaler.s(16)
                    color: fetcher.running ? ThemeBackend.mauve : (refreshMa.containsMouse ? ThemeBackend.text : ThemeBackend.subtext0)
                    text: root.ic(0xF0450)
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

            // week strip (14 days, 7 visible, scrolls to the active day)
            ListView {
                id: strip
                Layout.fillWidth: true
                Layout.preferredHeight: Scaler.s(66)
                visible: root.state_ === "ok"
                orientation: ListView.Horizontal
                clip: true
                interactive: true
                boundsBehavior: Flickable.StopAtBounds
                model: root.stripDays

                NumberAnimation { id: stripAnim; target: strip; property: "contentX"; duration: 280; easing.type: Easing.OutCubic }

                delegate: Item {
                    id: dayCell
                    required property var modelData
                    width: strip.width / 7
                    height: strip.height
                    readonly property bool isToday: modelData.key === root.todayKey
                    readonly property bool isActive: modelData.key === root.activeDay
                    readonly property var dots: root.dotsFor(modelData.key)

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: Scaler.s(2)
                        radius: ThemeBackend.borderRadius
                        color: dayCell.isActive ? ThemeBackend.mauve
                            : (cellMa.containsMouse ? Qt.alpha(ThemeBackend.surface1, 0.8) : "transparent")
                        border.width: dayCell.isToday && !dayCell.isActive ? 1 : 0
                        border.color: ThemeBackend.mauve
                        Behavior on color { ColorAnimation { duration: 160 } }

                        Column {
                            anchors.centerIn: parent
                            spacing: Scaler.s(3)
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                font.family: ThemeBackend.fontFamily
                                font.weight: Font.Bold
                                font.pixelSize: Scaler.s(9)
                                color: dayCell.isActive ? ThemeBackend.crust : ThemeBackend.subtext0
                                text: Qt.formatDate(dayCell.modelData.date, "ddd").toUpperCase()
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                font.family: ThemeBackend.fontFamily
                                font.weight: Font.Black
                                font.pixelSize: Scaler.s(15)
                                color: dayCell.isActive ? ThemeBackend.crust : (dayCell.isToday ? ThemeBackend.mauve : ThemeBackend.text)
                                text: dayCell.modelData.date.getDate()
                            }
                            Row {
                                anchors.horizontalCenter: parent.horizontalCenter
                                spacing: Scaler.s(2)
                                height: Scaler.s(5)
                                Repeater {
                                    model: dayCell.dots.colors
                                    Rectangle {
                                        required property var modelData
                                        width: Scaler.s(5); height: Scaler.s(5); radius: width / 2
                                        color: dayCell.isActive ? ThemeBackend.crust : modelData
                                    }
                                }
                                Rectangle {   // tasks due: small square
                                    visible: dayCell.dots.tasks > 0
                                    width: Scaler.s(5); height: Scaler.s(5); radius: Scaler.s(1)
                                    color: dayCell.isActive ? ThemeBackend.crust : ThemeBackend.peach
                                }
                            }
                        }
                    }
                    MouseArea {
                        id: cellMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.jumpListTo(dayCell.modelData.key)
                    }
                }
            }

            // add-task input
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: Scaler.s(34)
                visible: root.addMode
                Input {
                    id: taskInput
                    anchors.fill: parent
                    fontPixelSize: Scaler.s(11)
                    horizontalPadding: Scaler.s(8)
                    cornerRadius: ThemeBackend.borderRadius
                    baseColor: ThemeBackend.surface1
                    bgOpacity: ThemeBackend.elementOpacity
                    textColor: ThemeBackend.text
                    subTextColor: ThemeBackend.subtext0
                    accentColor: ThemeBackend.mauve
                    leadingIcon: root.ic(0xF0415)
                    placeholderText: "New task… (end with “today” or “tomorrow” for a due date)"
                    onAccepted: function(t) { root.addTask(t !== undefined ? t : taskInput.text); root.closeAdd(); }
                    Keys.onEscapePressed: root.closeAdd()
                }
            }

            // not signed in / setup states
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.state_ !== "ok"
                spacing: Scaler.s(10)
                Item { Layout.fillHeight: true }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    font.family: ThemeBackend.iconFont
                    font.pixelSize: Scaler.s(34)
                    color: root.state_ === "error" ? ThemeBackend.red : ThemeBackend.mauve
                    text: root.state_ === "error" ? root.ic(0xF0026) : root.ic(0xF02AD)
                }
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: Scaler.s(11)
                    color: ThemeBackend.subtext0
                    text: {
                        if (root.state_ === "loading") return "Loading…";
                        if (root.state_ === "no_client") return "Setup needed: save your Google OAuth client file as\n~/.config/serpantinum/google/client_secret.json";
                        if (root.state_ === "signed_out") return "Connect your Google account to see your calendar and tasks.";
                        return root.errorText || "Something went wrong";
                    }
                }
                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    visible: root.state_ === "signed_out" || root.state_ === "error"
                    implicitWidth: signRow.implicitWidth + Scaler.s(28)
                    implicitHeight: Scaler.s(36)
                    radius: ThemeBackend.borderRadius
                    color: signMa.containsMouse ? Qt.lighter(ThemeBackend.mauve, 1.1) : ThemeBackend.mauve
                    RowLayout {
                        id: signRow
                        anchors.centerIn: parent
                        spacing: Scaler.s(8)
                        Text { font.family: ThemeBackend.iconFont; font.pixelSize: Scaler.s(15); color: ThemeBackend.crust; text: root.ic(0xF02AD) }
                        Text { font.family: ThemeBackend.fontFamily; font.weight: Font.Bold; font.pixelSize: Scaler.s(12); color: ThemeBackend.crust; text: "Sign in with Google" }
                    }
                    MouseArea { id: signMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.signIn() }
                }
                Item { Layout.fillHeight: true }
            }

            // events + tasks grouped by day
            ListView {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.state_ === "ok"
                clip: true
                spacing: Scaler.s(2)
                boundsBehavior: Flickable.StopAtBounds
                model: root.rows
                onContentYChanged: root.updateTopDay()

                NumberAnimation { id: listAnim; target: list; property: "contentY"; duration: 320; easing.type: Easing.OutCubic }

                HoverHandler { id: listHover }

                delegate: Item {
                    id: rowItem
                    required property var modelData
                    width: list.width
                    height: {
                        let k = modelData.kind;
                        if (k === "day") return Scaler.s(28);
                        if (k === "empty") return Scaler.s(26);
                        if (k === "event") return Scaler.s(modelData.e.location ? 44 : 36);
                        return Scaler.s((modelData.t.due && modelData.t.due < root.todayKey) || (modelData.t.list && modelData.t.list !== "My Tasks") ? 42 : 34);
                    }
                    readonly property bool inActiveDay: rowItem.modelData.day === root.activeDay

                    HoverHandler {
                        onHoveredChanged: if (hovered) root.hoverDay = rowItem.modelData.day
                    }

                    // day header
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Scaler.s(2)
                        visible: rowItem.modelData.kind === "day"
                        spacing: Scaler.s(6)
                        Rectangle {
                            Layout.alignment: Qt.AlignBottom
                            Layout.bottomMargin: Scaler.s(4)
                            Layout.preferredWidth: Scaler.s(6)
                            Layout.preferredHeight: Scaler.s(6)
                            radius: width / 2
                            color: rowItem.inActiveDay ? ThemeBackend.mauve : ThemeBackend.surface2
                            Behavior on color { ColorAnimation { duration: 160 } }
                        }
                        Text {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignBottom
                            font.family: ThemeBackend.fontFamily
                            font.weight: Font.Bold
                            font.pixelSize: Scaler.s(10)
                            color: rowItem.inActiveDay ? ThemeBackend.mauve : ThemeBackend.subtext0
                            text: String(rowItem.modelData.title || "").toUpperCase()
                            Behavior on color { ColorAnimation { duration: 160 } }
                        }
                    }

                    // empty line
                    Text {
                        anchors.fill: parent
                        anchors.leftMargin: Scaler.s(14)
                        visible: rowItem.modelData.kind === "empty"
                        verticalAlignment: Text.AlignVCenter
                        font.family: ThemeBackend.fontFamily
                        font.italic: true
                        font.pixelSize: Scaler.s(11)
                        color: ThemeBackend.overlay1
                        text: rowItem.modelData.title || ""
                    }

                    // event row
                    Rectangle {
                        id: evRow
                        anchors.fill: parent
                        visible: rowItem.modelData.kind === "event"
                        radius: ThemeBackend.borderRadius * 0.6
                        color: evMa.containsMouse ? Qt.alpha(ThemeBackend.surface1, 0.8) : "transparent"
                        readonly property var e: rowItem.modelData.e || ({})
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Scaler.s(6)
                            anchors.rightMargin: Scaler.s(8)
                            spacing: Scaler.s(10)
                            Rectangle {
                                Layout.preferredWidth: Scaler.s(4)
                                Layout.fillHeight: true
                                Layout.topMargin: Scaler.s(6)
                                Layout.bottomMargin: Scaler.s(6)
                                radius: width / 2
                                color: evRow.e.color || ThemeBackend.mauve
                            }
                            Text {
                                Layout.preferredWidth: Scaler.s(44)
                                font.family: ThemeBackend.fontFamily
                                font.weight: Font.Bold
                                font.pixelSize: Scaler.s(11)
                                color: ThemeBackend.subtext1
                                text: evRow.e.allDay ? "all day" : Qt.formatTime(new Date(evRow.e.start || 0), "HH:mm")
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
                                    text: evRow.e.title || ""
                                }
                                Text {
                                    Layout.fillWidth: true
                                    visible: !!evRow.e.location
                                    elide: Text.ElideRight
                                    font.family: ThemeBackend.fontFamily
                                    font.pixelSize: Scaler.s(10)
                                    color: ThemeBackend.subtext0
                                    text: root.ic(0xF034E) + " " + (evRow.e.location || "")
                                }
                            }
                        }
                        MouseArea {
                            id: evMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (evRow.e.link) Quickshell.execDetached(["xdg-open", evRow.e.link])
                        }
                    }

                    // task row
                    Rectangle {
                        id: taskRow
                        anchors.fill: parent
                        visible: rowItem.modelData.kind === "task"
                        radius: ThemeBackend.borderRadius * 0.6
                        color: taskMa.containsMouse ? Qt.alpha(ThemeBackend.surface1, 0.8) : "transparent"
                        readonly property var t: rowItem.modelData.t || ({})
                        opacity: t.pending ? 0.6 : 1.0
                        MouseArea {   // hover highlight only; completing is on the circle
                            id: taskMa
                            anchors.fill: parent
                            hoverEnabled: true
                        }
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Scaler.s(6)
                            anchors.rightMargin: Scaler.s(8)
                            spacing: Scaler.s(10)
                            Text {
                                font.family: ThemeBackend.iconFont
                                font.pixelSize: Scaler.s(18)
                                color: checkMa.containsMouse ? ThemeBackend.green : ThemeBackend.overlay1
                                text: checkMa.containsMouse ? root.ic(0xF05E0) : root.ic(0xF0766)
                                MouseArea {
                                    id: checkMa
                                    anchors.fill: parent
                                    anchors.margins: -Scaler.s(6)
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    enabled: !taskRow.t.pending
                                    onClicked: root.completeTask(taskRow.t)
                                }
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
                                    text: taskRow.t.title || ""
                                }
                                Text {
                                    Layout.fillWidth: true
                                    readonly property var info: root.dueInfo(taskRow.t.due)
                                    visible: text !== ""
                                    elide: Text.ElideRight
                                    font.family: ThemeBackend.fontFamily
                                    font.pixelSize: Scaler.s(10)
                                    color: info.color
                                    text: {
                                        let bits = [];
                                        if (info.text && taskRow.t.due < root.todayKey) bits.push(info.text);   // only flag overdue; the day header shows the date
                                        if (taskRow.t.list && taskRow.t.list !== "My Tasks") bits.push(taskRow.t.list);
                                        return bits.join("  ·  ");
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // tiny tooltip used for the sync warning
    component ToolTipLite: Rectangle {
        property bool show: false
        property string label: ""
        visible: show && label !== ""
        z: 100
        anchors.top: parent.bottom
        anchors.right: parent.right
        anchors.topMargin: Scaler.s(4)
        width: Math.min(Scaler.s(220), tipText.implicitWidth + Scaler.s(16))
        height: tipText.implicitHeight + Scaler.s(10)
        radius: ThemeBackend.borderRadius * 0.6
        color: ThemeBackend.crust
        Text {
            id: tipText
            anchors.centerIn: parent
            width: Math.min(Scaler.s(204), implicitWidth)
            wrapMode: Text.WordWrap
            font.family: ThemeBackend.fontFamily
            font.pixelSize: Scaler.s(10)
            color: ThemeBackend.text
            text: parent.label
        }
    }
}
