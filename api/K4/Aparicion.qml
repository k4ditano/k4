//  Aparece con un fundido en vez de dar un salto. Envuelve lo que quieras
//  que entre suave cuando tu plugin toma la island.

import QtQuick

Item {
    opacity: 0
    Component.onCompleted: opacity = 1
    Behavior on opacity {
        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
    }
}
