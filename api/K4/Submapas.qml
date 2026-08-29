pragma Singleton

//  En qué submapa está Hyprland ahora mismo.
//
//  Un submapa es el teclado hablando otro idioma un rato: las teclas de la
//  captura, las de redimensionar ventanas, lo que hayas declarado tú. Un
//  plugin no puede asomarse al socket de eventos de Hyprland por su cuenta
//  —lo de plataforma baja a un servicio, que es la regla de la casa que vigila
//  tools/api.py—, así que escucha la barra y el estado se publica aquí: "" si
//  no hay submapa, y su id crudo si lo hay.
//
//  Para cualquier cosa que deba pasar mientras un modo está puesto. La
//  extensión de la píldora es el primer cliente, pero un plugin puede
//  atenuarse, avisar o cambiar de comportamiento igual de bien.

import QtQuick

QtObject {
    readonly property string actual: Puente.submapas ? Puente.submapas.actual : ""
}
