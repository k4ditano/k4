pragma Singleton

//  API pública para que un plugin aporte un indicador pequeño a la píldora
//  sin tocar IdleView ni shell.qml. Habla con la barra a través del Puente
//  —un fichero de este módulo no puede importar services/ por ruta relativa,
//  ver Puente.qml— y sin barra delante simplemente no hace nada.

import QtQuick

QtObject {
    id: api

    function registrar(id, texto, glifo, color, orden, visible) {
        if (Puente.indicadores)
            Puente.indicadores.registrar(id, texto, glifo, color, orden, visible)
    }
    function actualizar(id, campos) {
        if (Puente.indicadores)
            Puente.indicadores.actualizar(id, campos)
    }
    function quitar(id) {
        if (Puente.indicadores)
            Puente.indicadores.quitar(id)
    }
    function quitarDe(owner) {
        if (Puente.indicadores)
            Puente.indicadores.quitarDe(owner)
    }

    signal invocado(string id)

    property Connections conexion: Connections {
        target: Puente.indicadores
        function onInvocado(id) { api.invocado(id) }
    }
}
