// Brightness bar module (cloned from VolFace.qml)
import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.SystemTray
import "../../../reusables"
import "../../../"
import "../../"

BarFaceBase {
    id: root

    property string briStyle: {
        if (widget && widget !== root && widget.briStyle !== undefined) return widget.briStyle;
        if (module && module.briStyle !== undefined) return module.briStyle;
        let dummy = configRevision;
        if (typeof Config !== "undefined" && Config.rawSettings && Config.rawSettings.bar) {
            let bs = Config.rawSettings.bar;
            if (bs.briStyle) return bs.briStyle;
            if (bs.bri && bs.bri.style) return bs.bri.style;
        }
        return "button";
    }

    property bool showIcon: {
        if (widget && widget !== root && widget.briShowIcon !== undefined) return widget.briShowIcon;
        if (widget && widget !== root && widget.showIcon !== undefined) return widget.showIcon;
        if (module && module.briShowIcon !== undefined) return module.briShowIcon;
        if (module && module.showIcon !== undefined) return module.showIcon;
        let dummy = configRevision;
        if (typeof Config !== "undefined" && Config.rawSettings && Config.rawSettings.bar) {
            let bs = Config.rawSettings.bar;
            if (bs.briShowIcon !== undefined) return Boolean(bs.briShowIcon);
            if (bs.bri && bs.bri.showIcon !== undefined) return Boolean(bs.bri.showIcon);
        }
        return true;
    }

    property bool showPercent: {
        if (widget && widget !== root && widget.briShowPercent !== undefined) return widget.briShowPercent;
        if (widget && widget !== root && widget.showPercent !== undefined) return widget.showPercent;
        if (module && module.briShowPercent !== undefined) return module.briShowPercent;
        if (module && module.showPercent !== undefined) return module.showPercent;
        let dummy = configRevision;
        if (typeof Config !== "undefined" && Config.rawSettings && Config.rawSettings.bar) {
            let bs = Config.rawSettings.bar;
            if (bs.briShowPercent !== undefined) return Boolean(bs.briShowPercent);
            if (bs.bri && bs.bri.showPercent !== undefined) return Boolean(bs.bri.showPercent);
        }
        return true;
    }

    // brightness module: value comes live from OsdController's `serpantinum-core watch brightness`
    property real sysBri: isPreview ? 70 : OsdController.sysBrightness
    property int pendingBri: -1          // target while scrolling, so fast scrolls don't lag behind the watcher
    property string briPercent: Math.round(pendingBri >= 0 ? pendingBri : sysBri) + "%"
    property string briIcon: {
        let v = pendingBri >= 0 ? pendingBri : sysBri;
        return v > 66 ? "󰃠" : (v > 33 ? "󰃟" : "󰃞");
    }
    property bool isSoundActive: true    // keeps the pill accent-coloured like volume

    Timer { id: pendingReset; interval: 700; onTriggered: root.pendingBri = -1 }

    function stepBrightness(steps) {
        let base = root.pendingBri >= 0 ? root.pendingBri : root.sysBri;
        let target = Math.max(1, Math.min(100, Math.round(base + steps * 5)));
        root.pendingBri = target;
        pendingReset.restart();
        Quickshell.execDetached(["serpantinum-core", "brightness", "set", target.toString()]);
    }

    function openPanel() {
        Quickshell.execDetached(["quickshell", "-p", Caching.serpantinumDir + "/quickshell/Shell.qml", "ipc", "call", "main", "handleCommand", "toggle", "system", ""]);
    }

    property bool showLayout: (!barWindow || isPreview) ? true : (isVertical ? ((!module || module.moduleActive) && barWindow.isStartupReady && barWindow.isDataReady) : false)
    readonly property var briPill: pillLoader.item

    readonly property real pillLength: pillLoader.item ? (isVertical ? pillLoader.item.height : pillLoader.item.width) : 0
    readonly property real textLength: isVertical ? textLayout.implicitHeight : textLayout.implicitWidth

    property real targetLength: {
        if (module && !module.moduleActive) return 0;
        if (root.briStyle === "text") {
            return (textLength > 0) ? (textLength + s(root.isCompact ? (isVertical ? 14 : 12) : 16)) : 0;
        }
        return (pillLength > 0) ? (pillLength + s(root.isCompact ? 8 : 10)) : 0;
    }
    property bool isFaceVisible: showLayout && targetLength > 0

    function syncImplicitSize() {
        let cross = module ? module.thickness : (parent ? (isVertical ? parent.width : parent.height) : 0);
        implicitWidth = isVertical ? cross : targetLength;
        implicitHeight = isVertical ? targetLength : cross;
    }

    onTargetLengthChanged: syncImplicitSize()
    onIsVerticalChanged: syncImplicitSize()
    onModuleChanged: syncImplicitSize()
    onParentChanged: syncImplicitSize()

    Timer {
        running: true
        interval: 0
        onTriggered: root.syncImplicitSize()
    }

    Timer {
        running: !root.isVertical && !root.isPreview && (!module || module.moduleActive) && barWindow && barWindow.isStartupReady && barWindow.isDataReady
        interval: 100
        onTriggered: root.showLayout = true
    }

    transform: Translate {
        x: (root.isVertical || root.showLayout) ? 0 : s(60)
        Behavior on x { NumberAnimation { duration: 800; easing.type: Easing.OutQuint } }
    }

    MouseArea {
        id: textMouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        enabled: root.briStyle === "text" && !root.isPreview
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: mouse => {
            if (mouse.button !== Qt.RightButton) root.openPanel()
        }

        property real wheelAccumulator: 0
        Timer {
            id: textWheelTimer
            interval: 200
            onTriggered: textMouseArea.wheelAccumulator = 0
        }

        onWheel: wheel => {
            textWheelTimer.restart()
            textMouseArea.wheelAccumulator += wheel.angleDelta.y
            const threshold = 120
            if (Math.abs(textMouseArea.wheelAccumulator) >= threshold) {
                let steps = Math.trunc(textMouseArea.wheelAccumulator / threshold)
                textMouseArea.wheelAccumulator = textMouseArea.wheelAccumulator % threshold
                if (steps !== 0 && !root.isPreview) root.stepBrightness(steps)
            }
        }
    }

    AxisFlow {
        id: textLayout
        vertical: root.isVertical
        horizontalItemAlignment: Grid.AlignHCenter
        verticalItemAlignment: Grid.AlignVCenter
        visible: root.briStyle === "text"
        anchors.centerIn: parent
        spacing: root.isVertical ? s(root.isCompact ? 2 : 3) : s(root.isCompact ? 5 : 6)
        opacity: root.showLayout ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }

        Item {
            visible: root.showIcon
            width: root.isVertical ? textIcon.implicitWidth : s(root.isCompact ? 18 : 20)
            height: root.isVertical ? textIcon.implicitHeight : width

            Text {
                id: textIcon
                anchors.centerIn: parent
                text: root.briIcon
                font.family: ThemeBackend.iconFont
                font.pixelSize: s(root.isCompact ? 14 : 15)
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                color: textMouseArea.containsMouse ? Qt.lighter(ThemeBackend.peach, 1.15) : (root.isSoundActive ? ThemeBackend.peach : ThemeBackend.subtext0)
                Behavior on color { ColorAnimation { duration: 150 } }
            }
        }

        Text {
            visible: root.showPercent
            text: root.briPercent
            font.family: ThemeBackend.fontFamily
            font.pixelSize: root.isVertical ? s(root.isCompact ? 9 : 10) : s(root.isCompact ? 11 : 12)
            font.bold: true
            color: textMouseArea.containsMouse ? Qt.lighter(ThemeBackend.text, 1.15) : ThemeBackend.text
            Behavior on color { ColorAnimation { duration: 150 } }
        }
    }

    Loader {
        id: pillLoader
        visible: root.briStyle !== "text"
        anchors.centerIn: parent
        sourceComponent: root.isVertical ? sideButtonComponent : topButtonComponent
    }

    Component {
        id: topButtonComponent

        ClickButton {
            id: briPill
            property bool initAnimTrigger: root.isPreview
            property bool isActive: root.isSoundActive

            height: s(root.isCompact ? 28 : 30)
            maxWidth: s(root.isCompact ? 96 : 100)
            cornerRadius: Math.max(0, ThemeBackend.borderRadius - s(2))
            horizontalPadding: s(root.isCompact ? 10 : 12)
            buttonIcon: root.showIcon ? root.briIcon : ""
            iconFontSize: s(root.isCompact ? 14 : 15)
            buttonText: root.showPercent ? root.briPercent : ""
            textFontSize: s(root.isCompact ? 11 : 12)
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            accentColor: isActive ? (root.isCompact ? Qt.lighter(ThemeBackend.peach, 1.08) : ThemeBackend.peach) : (root.isCompact ? Qt.lighter(ThemeBackend.surface1, 1.12) : ThemeBackend.surface1)
            textColor: isActive ? ThemeBackend.base : (root.isCompact ? ThemeBackend.text : ThemeBackend.subtext0)

            property real targetWidth: (root.showIcon || root.showPercent) ? implicitWidth : 0
            width: targetWidth
            Behavior on width { NumberAnimation { duration: 480; easing.type: Easing.OutQuint } }

            Timer { running: !root.isPreview && (!module || module.moduleActive) && root.showLayout && !briPill.initAnimTrigger; interval: 250; onTriggered: briPill.initAnimTrigger = true }
            opacity: initAnimTrigger ? 1.0 : 0.0
            transform: Translate { y: briPill.initAnimTrigger ? 0 : s(15); Behavior on y { NumberAnimation { duration: 620; easing.type: Easing.OutQuint } } }
            Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }

            onClicked: if (!root.isPreview) root.openPanel()

            property real wheelAccumulator: 0
            Timer {
                id: briWheelTimer
                interval: 200
                onTriggered: briPill.wheelAccumulator = 0
            }

            onWheel: wheel => {
                if (root.isPreview) return;
                briWheelTimer.restart()
                briPill.wheelAccumulator += wheel.angleDelta.y
                const threshold = 120
                if (Math.abs(briPill.wheelAccumulator) >= threshold) {
                    let steps = Math.trunc(briPill.wheelAccumulator / threshold)
                    briPill.wheelAccumulator = briPill.wheelAccumulator % threshold
                    if (steps !== 0) root.stepBrightness(steps)
                }
            }
        }
    }

    Component {
        id: sideButtonComponent

        IconButton {
            width: s(root.isCompact ? 28 : 30)
            height: (root.showIcon || root.showPercent) ? s(root.isCompact ? 28 : 30) : 0
            cornerRadius: Math.max(0, ThemeBackend.borderRadius - s(2))
            buttonIcon: root.showIcon ? root.briIcon : ""
            iconFontSize: s(root.isCompact ? 14 : 15)
            accentColor: root.isSoundActive ? (root.isCompact ? Qt.lighter(ThemeBackend.peach, 1.08) : ThemeBackend.peach) : (root.isCompact ? Qt.lighter(ThemeBackend.surface1, 1.12) : ThemeBackend.surface1)
            textColor: root.isSoundActive ? ThemeBackend.base : (root.isCompact ? ThemeBackend.text : ThemeBackend.subtext0)
            onClicked: if (!root.isPreview) root.openPanel()
        }
    }
}
