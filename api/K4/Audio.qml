pragma Singleton

//  El sonido del sistema: leerlo es libre, cambiarlo pide permiso.
//
//  La lectura no hace daño a nadie —un visualizador o un indicador solo
//  quieren saber por dónde va el volumen— así que no se pide nada. Subirlo o
//  silenciarlo sí se nota, y por eso `ponerVolumen` y `alternarSilencio`
//  exigen declarar el permiso `audio` en el manifiesto.
//
//      K4.Etiqueta { text: K4.Audio.volumen + "%" }

import QtQuick

QtObject {
    readonly property var _a: Puente.audio

    //  De 0 a 100.
    readonly property int volumen: _a ? _a.volume : 0
    readonly property bool silenciado: _a ? _a.muted : false
    readonly property bool listo: _a ? _a.initialized : false

    //  ── requieren el permiso `audio` ──────────────────────────────
    function ponerVolumen(porciento) {
        if (_a)
            _a.setVolume(porciento)
    }

    function alternarSilencio() {
        if (_a)
            _a.toggleMute()
    }
}
