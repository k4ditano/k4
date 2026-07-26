import QtQuick

Item {
    opacity: 0
    Component.onCompleted: opacity = 1
    Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
}
