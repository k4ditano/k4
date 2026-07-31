pragma Singleton

//  Las notificaciones que recibe la barra.
//
//  Leerlas es libre —un registro, un contador, un filtro que solo mira— y
//  descartarlas pide el permiso `notificaciones`: borrarle a alguien un aviso
//  que no ha leído es una pérdida de verdad.
//
//      Connections {
//          target: K4.Notificaciones
//          function onLlego() { console.log(K4.Notificaciones.ultima.summary) }
//      }

import QtQuick

QtObject {
    id: api

    readonly property var _n: Puente.notificaciones

    readonly property int cuantas: _n ? _n.count : 0
    readonly property var ultima: _n ? _n.latest : null
    //  Las recientes, ya recortadas por la barra.
    readonly property var recientes: _n ? _n.recent : []

    signal llego()

    //  ── requiere el permiso `notificaciones` ──────────────────────
    function limpiar() { if (_n) _n.clear() }

    property Connections _puente: Connections {
        target: api._n
        function onNotified() { api.llego() }
    }
}
