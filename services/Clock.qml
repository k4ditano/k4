pragma Singleton

// Un único reloj para toda la barra: dos SystemClock sondean dos veces.

import QtQuick
import Quickshell

Singleton {
    readonly property date date: clock.date

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }
}
