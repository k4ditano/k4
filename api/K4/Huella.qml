pragma Singleton

//  Datos personales del usuario, agregados y con doble llave.
//
//  Requiere el permiso `datos-personales` en tu manifiesto Y que el usuario
//  haya encendido cada fuente en Ajustes → «Datos personales» (todo viene
//  apagado de fábrica). Sin las dos llaves recibes objetos vacíos y
//  `activa()` contesta false — tu plugin no rompe, pero no ve.
//
//      if (K4.Huella.activa("steam"))
//          minutos = K4.Huella.steam.minutos || 0
//
//  Fuentes de hoy: `steam` ({ juegos, minutos, titulos }) y `paquetes`
//  ({ total, ultimaActualizacion }). Siempre AGREGADOS: la condensación
//  pasa en python antes de tocar QML, y «Olvidar mi huella» lo borra todo.

import QtQuick

QtObject {
    readonly property var _h: Puente.huella

    function activa(fuente) {
        return _h ? _h.activa(fuente) : false
    }

    readonly property var steam: _h ? _h.steam : ({})
    readonly property var paquetes: _h ? _h.paquetes : ({})
}
