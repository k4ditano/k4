pragma Singleton

// API pública para que un plugin pueda aportar un indicador pequeño a la
// píldora sin tocar IdleView ni shell.qml.

import QtQuick
import "../../services" as Servicios

QtObject {
    id: api
    function registrar(id, texto, glifo, color, orden, visible) {
        Servicios.Indicadores.registrar(id, texto, glifo, color, orden, visible)
    }
    function actualizar(id, campos) { Servicios.Indicadores.actualizar(id, campos) }
    function quitar(id) { Servicios.Indicadores.quitar(id) }
    function quitarDe(owner) { Servicios.Indicadores.quitarDe(owner) }
    signal invocado(string id)

    property Connections conexion: Connections {
        target: Servicios.Indicadores
        function onInvocado(id) { api.invocado(id) }
    }
}
