//  El estado persistente de un plugin: un JSON con nombre, en su directorio.
//
//  Es el andamiaje de partidas guardadas, récords y ajustes propios. Cada
//  plugin escribe en SU directorio —~/.local/state/k4/plugins/<id>/— y no en
//  el común, donde dos ficheros con el mismo nombre se pisarían.
//
//      K4.Guardado {
//          id: guardado
//          plugin: "snake"                 // el id del manifiesto
//          onCargado: function (d) { record = d.record || 0 }
//      }
//      ...
//      guardado.guardar({ record: record })
//
//  `cargado` llega una vez, al arrancar, con {} si no había nada. `guardar`
//  escribe entero lo que se le pasa: es un estado pequeño, no una base de
//  datos, y lo simple aquí es lo que evita estados a medio escribir.

import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: self

    required property string plugin
    //  Por si un plugin quiere varios ficheros: partida.json y ajustes.json.
    property string nombre: "estado"

    signal cargado(var datos)

    readonly property string _dir: Paths.estadoDe(plugin)
    readonly property string _ruta: _dir + "/" + nombre + ".json"

    function guardar(datos) {
        _fichero.setText(JSON.stringify(datos, null, 1))
    }

    //  El directorio primero y la lectura después: leer de un directorio que
    //  no existe no es un fallo —es la primera vez— pero escribir sí lo sería.
    property var _mkdir: Process {
        command: ["mkdir", "-p", self._dir]
        running: true
        onExited: self._leer()
    }

    function _leer() {
        let d = {}
        try {
            const bruto = _fichero.text()
            if (bruto && bruto.length > 0)
                d = JSON.parse(bruto)
        } catch (e) {
            //  Un estado roto no puede impedir arrancar: se empieza de cero.
            //  El fichero malo se queda en disco por si hay algo que rescatar.
        }
        cargado(d)
    }

    property var _fichero: FileView {
        path: self._ruta
        blockLoading: true
    }
}
