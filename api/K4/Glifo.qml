//  Un icono de la Nerd Font, que es como la barra dibuja casi todos los suyos.
//
//  El texto es el códice: `text: ""`. Para saber cuál es cuál sin
//  adivinar, `python3 tools/glifos.py <palabra>` busca por nombre — se hizo
//  porque tres códices puestos de memoria salieron mal.

import QtQuick

Text {
    //  Un glifo es un punto de código, nunca marcado. Se dice igualmente: el
    //  día que alguien pase por aquí un nombre en vez de un icono, no se
    //  convierte en un agujero.
    textFormat: Text.PlainText
    color: Tema.tinta
    font.family: Tema.fuenteIconos
    font.pixelSize: 16
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
}
