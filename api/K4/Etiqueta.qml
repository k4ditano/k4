//  Texto con los defaults de la barra: blanco, Adwaita, 12px.
//
//  El equivalente público del IslandLabel de core/, escrito aparte y no
//  reexportado: un fichero de este módulo no puede importar core/ por ruta
//  relativa — ver Puente.qml para el porqué, que costó una tarde.

import QtQuick

Text {
    //  Literal, y aquí con más motivo: esto es lo que usan los plugins de
    //  fuera, que pintan lo que les llegue. Ver core/IslandLabel.
    textFormat: Text.PlainText
    color: Tema.tinta
    font.family: Tema.fuente
    font.pixelSize: 12
}
