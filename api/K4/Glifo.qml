//  Un icono de la Nerd Font, que es como la barra dibuja casi todos los suyos.
//
//  El texto es el códice: `text: ""`. Para saber cuál es cuál sin
//  adivinar, `python3 tools/glifos.py <palabra>` busca por nombre — se hizo
//  porque tres códices puestos de memoria salieron mal.

import QtQuick

Text {
    color: Tema.tinta
    font.family: Tema.fuenteIconos
    font.pixelSize: 16
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
}
