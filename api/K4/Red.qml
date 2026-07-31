pragma Singleton

//  Wi‑Fi y Bluetooth, para saber a qué está conectado esto.
//
//  Solo lectura: conectarse a una red o emparejar un aparato no se abre a los
//  plugins, ni con permiso. Es la única puerta que dejo cerrada a propósito —
//  el precio de equivocarse ahí es quedarse sin red o entregarle el portátil a
//  un dispositivo ajeno, y ninguna idea bonita de plugin lo compensa. Si te
//  hace falta, `k4 wifi` y `k4 bluetooth` abren los paneles de la barra y ahí
//  decide la persona.

import QtQuick

QtObject {
    readonly property var _w: Puente.wifi
    readonly property var _b: Puente.bluetooth

    // ── Wi‑Fi ─────────────────────────────────────────────────────
    readonly property bool wifiActiva: _w ? _w.activada : false
    readonly property string wifiNombre: _w ? _w.name : ""
    readonly property bool buscando: _w ? _w.scanning : false
    //  Las redes a la vista, cada una tal cual la da NetworkManager.
    readonly property var redes: _w ? _w.networks : []

    // ── Bluetooth ─────────────────────────────────────────────────
    readonly property bool bluetoothActivo:
        (_b && _b.adapter) ? _b.adapter.enabled : false
    readonly property var aparatos: _b ? _b.devices : []
}
