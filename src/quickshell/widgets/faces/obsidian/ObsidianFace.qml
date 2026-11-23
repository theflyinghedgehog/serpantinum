// Obsidian desktop widget
// - search box: finds notes/folders in the vault (Enter opens the top hit)
// - buttons: New note (uses the search text as the name if you typed one), Open vault
// - list: your Obsidian bookmarks (.obsidian/bookmarks.json), live-synced with Obsidian
// Folders open inside the widget; notes open in Obsidian via obsidian:// links.
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
    property real minHeight: 260
    property real maxWidth: 800
    property real maxHeight: 1000
    property real minAspect: 0.35
    property real maxAspect: 2.5
    property bool isRound: false

    // Leave empty to auto-detect the vault Obsidian last had open.
    property string vaultPathOverride: ""

    property string vaultPath: ""
    readonly property string vaultName: vaultPath === "" ? "" : vaultPath.replace(/\/+$/, "").split("/").pop()
    property var allEntries: []        // [{ dir: bool, path: "Folder/Note.md" }]
    property var bookmarks: []         // [{ dir: bool, path, title }]
    property string query: ""
    property string currentFolder: ""  // "" = favourites view
    property bool wantsKeyboardFocus: false

    function ic(cp) { return String.fromCodePoint(cp); }
    function baseName(p) { return p.split("/").pop(); }
    function displayName(p) { return baseName(p).replace(/\.md$/i, ""); }
    function parentOf(p) { let i = p.lastIndexOf("/"); return i < 0 ? "" : p.substring(0, i); }

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
                if (t.WlrLayershell !== undefined) {
                    t.WlrLayershell.keyboardFocus = enable ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None;
                }
                if (enable && typeof t.requestActivate === "function") t.requestActivate();
            }
        } catch (e) {}
    }

    // vault detection
    Process {
        id: vaultFinder
        running: false
        command: ["bash", "-c",
            "cat \"$HOME/.config/obsidian/obsidian.json\" 2>/dev/null || cat \"$HOME/.var/app/md.obsidian.Obsidian/config/obsidian/obsidian.json\" 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.vaultPathOverride !== "") { root.vaultPath = root.vaultPathOverride; return; }
                try {
                    let vaults = JSON.parse(this.text).vaults || {};
                    let best = null;
                    for (let id in vaults) {
                        let v = vaults[id];
                        if (!best || (v.open && !best.open) || ((!!v.open === !!best.open) && (v.ts || 0) > (best.ts || 0))) best = v;
                    }
                    if (best && best.path) root.vaultPath = best.path;
                } catch (e) {}
            }
        }
    }

    onVaultPathChanged: {
        root.currentFolder = "";
        root.refreshIndex();
    }

    // file index
    function refreshIndex() {
        if (root.vaultPath === "" || indexer.running) return;
        indexer.command = ["find", root.vaultPath, "-mindepth", "1",
            "(", "-name", ".*", "-prune", ")", "-o",
            "(", "-type", "d", "-o", "-name", "*.md", "-o", "-name", "*.canvas", ")",
            "-printf", "%y\t%P\n"];
        indexer.running = true;
    }

    Process {
        id: indexer
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                let out = [];
                let lines = this.text.split("\n");
                for (let i = 0; i < lines.length; i++) {
                    let tab = lines[i].indexOf("\t");
                    if (tab < 0) continue;
                    let path = lines[i].substring(tab + 1);
                    if (path === "") continue;
                    out.push({ dir: lines[i].substring(0, tab) === "d", path: path });
                }
                out.sort(function(a, b) { return a.path.localeCompare(b.path); });
                root.allEntries = out;
            }
        }
    }

    Timer { interval: 5 * 60 * 1000; repeat: true; running: !root.previewMode; onTriggered: root.refreshIndex() }

    // bookmarks
    FileView {
        id: bookmarksFile
        path: root.vaultPath !== "" ? root.vaultPath + "/.obsidian/bookmarks.json" : ""
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            let out = [];
            let walk = function(items) {
                for (let i = 0; i < (items || []).length; i++) {
                    let it = items[i];
                    if (it.type === "group") { walk(it.items); continue; }
                    if (!it.path) continue;
                    out.push({ dir: it.type === "folder", path: it.path, title: it.title || "" });
                }
            };
            try { walk(JSON.parse(text()).items); } catch (e) {}
            root.bookmarks = out;
        }
        onLoadFailed: root.bookmarks = []
    }

    Component.onCompleted: Qt.callLater(function() {
        if (root.previewMode) return;
        if (root.vaultPathOverride !== "") root.vaultPath = root.vaultPathOverride;
        else vaultFinder.running = true;
    })

    // rows shown in the list
    readonly property var rows: {
        let q = root.query.trim().toLowerCase();
        let out = [];
        if (q !== "") {
            let scored = [];
            for (let i = 0; i < allEntries.length; i++) {
                let e = allEntries[i];
                let name = displayName(e.path).toLowerCase();
                let path = e.path.toLowerCase();
                let s = name === q ? 4 : name.startsWith(q) ? 3 : name.includes(q) ? 2 : path.includes(q) ? 1 : 0;
                if (s > 0) scored.push({ s: s, e: e });
            }
            scored.sort(function(a, b) { return b.s - a.s || a.e.path.length - b.e.path.length; });
            for (let i = 0; i < Math.min(40, scored.length); i++) {
                let e = scored[i].e;
                out.push({ kind: e.dir ? "folder" : "file", path: e.path, title: displayName(e.path), sub: parentOf(e.path) });
            }
            return out;
        }
        if (currentFolder !== "") {
            out.push({ kind: "back", path: parentOf(currentFolder), title: currentFolder, sub: "" });
            let prefix = currentFolder + "/";
            let dirs = [], files = [];
            for (let i = 0; i < allEntries.length; i++) {
                let e = allEntries[i];
                if (!e.path.startsWith(prefix)) continue;
                if (e.path.substring(prefix.length).indexOf("/") >= 0) continue;
                (e.dir ? dirs : files).push({ kind: e.dir ? "folder" : "file", path: e.path, title: displayName(e.path), sub: "" });
            }
            return out.concat(dirs, files);
        }
        for (let i = 0; i < bookmarks.length; i++) {
            let b = bookmarks[i];
            out.push({ kind: b.dir ? "folder" : "file", path: b.path, title: b.title || displayName(b.path), sub: parentOf(b.path) });
        }
        return out;
    }

    // actions
    function openUri(action, params) {
        let parts = ["vault=" + encodeURIComponent(root.vaultName)];
        for (let k in params) parts.push(k + "=" + encodeURIComponent(params[k]));
        Quickshell.execDetached(["xdg-open", "obsidian://" + action + "?" + parts.join("&")]);
    }

    function activateRow(r) {
        if (!r) return;
        if (r.kind === "file") {
            openUri("open", { file: r.path });
            leaveSearch();
        } else if (r.kind === "folder") {
            root.currentFolder = r.path;
            leaveSearch();
        } else if (r.kind === "back") {
            root.currentFolder = r.path;
        }
    }

    function newNote() {
        let name = root.query.trim();
        if (name === "") name = "Untitled " + Qt.formatDateTime(new Date(), "yyyy-MM-dd HHmm");
        if (root.currentFolder !== "" && name.indexOf("/") < 0) {
            openUri("new", { file: root.currentFolder + "/" + name });
        } else {
            openUri("new", { name: name });
        }
        leaveSearch();
    }

    function leaveSearch() {
        searchInput.clear();
        root.query = "";
        searchInput.releaseFocus();
        root.setKeyboardFocus(false);
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
            anchors.margins: Scaler.s(12)
            spacing: Scaler.s(8)

            // header
            RowLayout {
                Layout.fillWidth: true
                spacing: Scaler.s(8)
                Text {
                    font.family: ThemeBackend.iconFont
                    font.pixelSize: Scaler.s(18)
                    color: ThemeBackend.mauve
                    text: root.ic(0xF082E)   // notebook
                }
                Text {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    font.family: ThemeBackend.fontFamily
                    font.weight: Font.Black
                    font.pixelSize: Scaler.s(14)
                    color: ThemeBackend.text
                    text: root.vaultName !== "" ? root.vaultName : "Obsidian"
                }
                Text {
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: Scaler.s(10)
                    color: ThemeBackend.subtext0
                    text: root.allEntries.length > 0 ? root.allEntries.filter(function(e) { return !e.dir; }).length + " notes" : ""
                }
            }

            // search
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: Scaler.s(34)

                Input {
                    id: searchInput
                    anchors.fill: parent
                    fontPixelSize: Scaler.s(11)
                    horizontalPadding: Scaler.s(8)
                    cornerRadius: ThemeBackend.borderRadius
                    baseColor: ThemeBackend.surface1
                    bgOpacity: ThemeBackend.elementOpacity
                    textColor: ThemeBackend.text
                    subTextColor: ThemeBackend.subtext0
                    accentColor: ThemeBackend.mauve
                    leadingIcon: root.ic(0xF0349)   // magnify
                    showClearButton: true
                    placeholderText: "Search notes and folders…"

                    onTextEdited: function(t) { root.query = t; }
                    onCleared: root.query = ""
                    onAccepted: function(t) {
                        if (root.rows.length > 0) root.activateRow(root.rows[0]);
                        else if (root.query.trim() !== "") root.newNote();
                    }
                    Keys.onEscapePressed: root.leaveSearch()
                }

                // first click grabs keyboard focus for the desktop widget, then focuses the field
                MouseArea {
                    anchors.fill: parent
                    visible: !root.wantsKeyboardFocus
                    cursorShape: Qt.IBeamCursor
                    onClicked: {
                        root.setKeyboardFocus(true);
                        searchInput.forceInputFocus();
                        if (!indexer.running) root.refreshIndex();
                    }
                }
            }

            // buttons
            RowLayout {
                Layout.fillWidth: true
                spacing: Scaler.s(6)

                component ActionButton: Rectangle {
                    id: btn
                    property string icon: ""
                    property string label: ""
                    property bool primary: false
                    signal clicked()
                    Layout.fillWidth: true
                    Layout.preferredHeight: Scaler.s(32)
                    radius: ThemeBackend.borderRadius
                    color: primary ? (btnMa.containsMouse ? Qt.lighter(ThemeBackend.mauve, 1.1) : ThemeBackend.mauve)
                        : (btnMa.containsMouse ? ThemeBackend.surface2 : Qt.alpha(ThemeBackend.surface1, ThemeBackend.elementOpacity))
                    Behavior on color { ColorAnimation { duration: 120 } }
                    RowLayout {
                        anchors.centerIn: parent
                        spacing: Scaler.s(6)
                        Text {
                            font.family: ThemeBackend.iconFont
                            font.pixelSize: Scaler.s(15)
                            color: btn.primary ? ThemeBackend.crust : ThemeBackend.mauve
                            text: btn.icon
                        }
                        Text {
                            font.family: ThemeBackend.fontFamily
                            font.weight: Font.Bold
                            font.pixelSize: Scaler.s(11)
                            color: btn.primary ? ThemeBackend.crust : ThemeBackend.text
                            text: btn.label
                        }
                    }
                    MouseArea {
                        id: btnMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: btn.clicked()
                    }
                }

                ActionButton {
                    primary: true
                    icon: root.ic(0xF0415)   // plus
                    label: root.query.trim() !== "" ? "New \"" + root.query.trim() + "\"" : "New note"
                    onClicked: root.newNote()
                }
                ActionButton {
                    icon: root.ic(0xF03CC)   // open-in-new
                    label: "Open vault"
                    onClicked: { root.openUri("open", {}); root.leaveSearch(); }
                }
            }

            // section label
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Scaler.s(2)
                spacing: Scaler.s(6)
                Text {
                    font.family: ThemeBackend.iconFont
                    font.pixelSize: Scaler.s(12)
                    color: ThemeBackend.subtext0
                    text: root.query.trim() !== "" ? root.ic(0xF0349)
                        : (root.currentFolder !== "" ? root.ic(0xF0256) : root.ic(0xF00C0))
                }
                Text {
                    Layout.fillWidth: true
                    elide: Text.ElideMiddle
                    font.family: ThemeBackend.fontFamily
                    font.weight: Font.Bold
                    font.pixelSize: Scaler.s(10)
                    color: ThemeBackend.subtext0
                    text: root.query.trim() !== "" ? "RESULTS"
                        : (root.currentFolder !== "" ? root.currentFolder.toUpperCase() : "FAVOURITES")
                }
            }

            // list
            ListView {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: Scaler.s(2)
                boundsBehavior: Flickable.StopAtBounds
                model: root.rows

                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    width: list.width
                    height: Scaler.s(modelData.sub !== "" ? 42 : 34)
                    radius: ThemeBackend.borderRadius * 0.6
                    color: rowMa.containsMouse ? Qt.alpha(ThemeBackend.surface1, 0.8)
                        : (index === 0 && root.query.trim() !== "" ? Qt.alpha(ThemeBackend.mauve, 0.12) : "transparent")
                    Behavior on color { ColorAnimation { duration: 120 } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Scaler.s(8)
                        anchors.rightMargin: Scaler.s(8)
                        spacing: Scaler.s(10)

                        Text {
                            font.family: ThemeBackend.iconFont
                            font.pixelSize: Scaler.s(16)
                            color: modelData.kind === "folder" ? ThemeBackend.yellow
                                : (modelData.kind === "back" ? ThemeBackend.subtext0 : ThemeBackend.mauve)
                            text: modelData.kind === "back" ? root.ic(0xF004D)        // arrow-left
                                : (modelData.kind === "folder" ? root.ic(0xF024B)     // folder
                                : (modelData.path.endsWith(".canvas") ? root.ic(0xF0389) : root.ic(0xF0219)))  // canvas / file-document
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
                                text: modelData.kind === "back" ? "Back" : modelData.title
                            }
                            Text {
                                Layout.fillWidth: true
                                visible: modelData.sub !== ""
                                elide: Text.ElideMiddle
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: Scaler.s(10)
                                color: ThemeBackend.subtext0
                                text: modelData.sub
                            }
                        }
                        Text {
                            visible: modelData.kind === "folder"
                            font.family: ThemeBackend.iconFont
                            font.pixelSize: Scaler.s(14)
                            color: ThemeBackend.overlay1
                            text: root.ic(0xF0142)   // chevron-right
                        }
                    }

                    MouseArea {
                        id: rowMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.activateRow(modelData)
                    }
                }

                // empty states
                Text {
                    anchors.centerIn: parent
                    width: parent.width - Scaler.s(20)
                    visible: list.count === 0
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: Scaler.s(11)
                    color: ThemeBackend.subtext0
                    text: root.vaultPath === "" ? "No Obsidian vault found. Open a vault in Obsidian once, then reload."
                        : (root.query.trim() !== "" ? "No matches. Press Enter to create \"" + root.query.trim() + "\"."
                        : (root.currentFolder !== "" ? "Empty folder"
                        : "No favourites yet. Bookmark notes or folders in Obsidian (right-click → Bookmark) and they show up here."))
                }
            }
        }
    }
}
