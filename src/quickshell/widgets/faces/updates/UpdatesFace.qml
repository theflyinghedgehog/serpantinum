// Arch updates desktop widget
// Face: update icon + number of pending updates (repo + AUR).
// Left click: dropdown with "Update all" and a list of packages you can tick
// and update individually. Updates run in kitty so you can see pacman's output.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
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
    readonly property string terminal: "kitty"

    property string helper: ""          // yay / paru / "" (no AUR helper)
    property string errorText: ""
    property bool checking: false
    property bool hasChecked: false
    property double lastCheck: 0
    property string lastLogStamp: ""
    property bool popupOpen: false

    readonly property int updateCount: pkgModel.count
    property int aurCount: 0
    property int selectedCount: 0
    property int selectedRepoCount: 0
    readonly property real rowH: Scaler.s(44)

    function ic(cp) { return String.fromCodePoint(cp); }

    readonly property bool isError: errorText !== "" && updateCount === 0
    readonly property color statusColor: isError ? ThemeBackend.red
        : (updateCount > 0 ? ThemeBackend.peach : ThemeBackend.green)
    readonly property string statusIcon: isError ? ic(0xF0026)          // alert
        : (updateCount > 0 ? ic(0xF06B0) : ic(0xF05E0))                    // update / check-circle

    ListModel { id: pkgModel }   // name, oldVer, newVer, aur, checked

    // data
    function refresh() {
        if (root.previewMode || checker.running) return;
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
                if (v !== "" && root.lastLogStamp !== "" && v !== root.lastLogStamp) postUpdateTimer.restart();
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

    // selection / actions
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

    function shq(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'"; }

    function runInTerminal(cmd) {
        let wrapped = cmd + '; echo; read -n 1 -s -r -p "[done, press any key to close]"';
        Quickshell.execDetached([root.terminal, "--title", "Arch updates", "-e", "bash", "-c", wrapped]);
        root.popupOpen = false;
    }

    function updateAll() {
        runInTerminal(root.helper !== "" ? (root.helper + " -Syu") : "sudo pacman -Syu");
    }

    function updateSelected() {
        let repo = [], aur = [];
        for (let i = 0; i < pkgModel.count; i++) {
            let it = pkgModel.get(i);
            if (!it.checked) continue;
            (it.aur ? aur : repo).push(shq(it.name));
        }
        let parts = [];
        if (repo.length > 0) {
            parts.push('echo "Partial upgrade: if anything breaks, run a full update (-Syu)."; echo; sudo pacman -Sy --needed ' + repo.join(" "));
        }
        if (aur.length > 0) {
            parts.push((root.helper !== "" ? root.helper : "yay") + " -S --needed " + aur.join(" "));
        }
        if (parts.length > 0) runInTerminal(parts.join(" && "));
    }

    function togglePopup() {
        root.popupOpen = !root.popupOpen;
        if (root.popupOpen && Date.now() - root.lastCheck > 2 * 60 * 1000) root.refresh();
    }

    // face
    Rectangle {
        id: bg
        anchors.fill: parent
        color: Qt.alpha(ThemeBackend.surface0, ThemeBackend.elementOpacity)
        radius: ThemeBackend.borderRadius
        clip: true
        border.width: root.popupOpen ? 1 : 0
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
            opacity: faceMa.containsMouse ? 0.05 : 0.0
            Behavior on opacity { NumberAnimation { duration: 150 } }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Scaler.s(16)
            anchors.rightMargin: Scaler.s(16)
            spacing: Scaler.s(14)

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

        MouseArea {
            id: faceMa
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.togglePopup()
        }
    }

    // dropdown
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
                        text: "Arch updates"
                    }
                    Text {
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: Scaler.s(10)
                        color: ThemeBackend.subtext0
                        text: root.checking ? "checking…"
                            : (root.hasChecked ? Qt.formatTime(new Date(root.lastCheck), "hh:mm") : "")
                    }
                    Text {
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

                // Update all
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Scaler.s(38)
                    visible: root.updateCount > 0
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
                    visible: root.updateCount === 0
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

                // package list
                ListView {
                    id: list
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(count, 8) * root.rowH + Math.max(0, Math.min(count, 8) - 1) * spacing
                    visible: count > 0
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
                    visible: root.selectedRepoCount > 0
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

                // Update selected
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Scaler.s(34)
                    visible: root.updateCount > 0
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
