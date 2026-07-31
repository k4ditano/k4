pragma Singleton

//  El historial del portapapeles.
//
//  Aquí la lectura NO es libre: el portapapeles lleva contraseñas, tokens y
//  lo último que copiaste de tu gestor de claves. Leerlo ya es el acto
//  delicado, así que hasta mirar pide el permiso `portapapeles` — al revés
//  que el audio o los medios, donde lo que se vigila es escribir.
//
//  Los textos llegan recortados por la propia barra; para el contenido entero
//  de una entrada, `copiar(id)` la pone en el portapapeles y ya está en manos
//  de quien la pegue.

import QtQuick

QtObject {
    id: api

    readonly property var _p: Puente.portapapeles

    //  ── todo esto requiere el permiso `portapapeles` ──────────────
    readonly property var entradas: _p ? _p.entradas : []
    readonly property int cuantas: _p ? _p.count : 0

    function titulo(entrada) { return _p ? _p.titulo(entrada) : "" }
    function filtrar(texto) { return _p ? _p.filtrar(texto) : [] }
    function copiar(id) { if (_p) _p.copiar(id) }

    signal cambio()

    property Connections _puente: Connections {
        target: api._p
        function onCambio() { api.cambio() }
    }
}
