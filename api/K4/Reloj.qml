pragma Singleton

//  La hora, del mismo reloj que usa toda la barra.
//
//  Existe para no tener cinco `SystemClock` sondeando por su cuenta: uno solo
//  y todos miran ahí. Cambia una vez por minuto, que es lo que necesita un
//  reloj de barra; si tu plugin necesita segundos, pon tu propio Timer.

import QtQuick

QtObject {
    readonly property var _r: Puente.reloj

    readonly property date ahora: _r ? _r.date : new Date()
}
