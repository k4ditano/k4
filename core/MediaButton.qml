// Botón redondo monocromo de transporte

import QtQuick

Item {
    id: control

    property string glyph
    property int glyphSize: 18
    property color glyphColor: Theme.ink
    property bool enabledAction: true
    signal activated()

    implicitWidth: glyphSize + 16
    implicitHeight: glyphSize + 12
    opacity: enabledAction ? (mouse.containsMouse ? 0.65 : 1) : 0.28

    Behavior on opacity { NumberAnimation { duration: 120 } }

    IconGlyph {
        anchors.centerIn: parent
        text: control.glyph
        color: control.glyphColor
        font.pixelSize: control.glyphSize
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        enabled: control.enabledAction
        onClicked: control.activated()
    }

    scale: mouse.pressed ? 0.88 : 1
    Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
}
