import QtQuick
import "../../../"

Item {
    id: el

    property string variant: "button"
    property var ctx: null

    visible: !el.ctx || !el.ctx.root.isDesktop
    // dual battery: the wider split pill grows to the right so it does not cover the keyboard pill
    implicitWidth: faceLoader.item ? faceLoader.item.implicitWidth - (faceLoader.item.splitExtra || 0) : 0
    implicitHeight: faceLoader.item ? faceLoader.item.implicitHeight : 0

    QtObject {
        id: host

        property string batStyle: el.variant
        property bool batShowPercent: true
        property bool batShowIcon: true
        property bool isCompact: false
        property bool lockLook: true
        property bool isPreview: false
        property bool moduleActive: true
        property string orientation: "horizontal"
        property real thickness: Math.round(Scaler.s(34))
        property var barWindow: null
    }

    Loader {
        id: faceLoader
        x: 0
        anchors.verticalCenter: parent.verticalCenter
        source: Qt.resolvedUrl("../../../bar/faces/bat/BatFace.qml")
        onLoaded: item.module = host
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
    }
}
