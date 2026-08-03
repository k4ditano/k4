//  El aspecto de una capa, en la previa.
//
//  Es el espejo QML de `filtros_aspecto()` de `tools/editar.py`: mismo campo
//  del plan, misma forma en pantalla. Vive aparte porque lo usan la imagen y el
//  vídeo incrustado, y porque tener la traducción de colores en UN sitio es lo
//  que evita que la previa y el fichero acaben diciendo cosas distintas.
//
//  Los colores son una aproximación honesta: el render usa una matriz de
//  canales y esto tiñe, así que el sepia de la previa no es el sepia exacto del
//  mp4. Lo que sí coincide al píxel —y es lo que se mira mientras colocas— son
//  la máscara y el encuadre.

import QtQuick
import QtQuick.Effects

MultiEffect {
    id: aspecto

    //  La capa de la que se saca todo, y la textura con la forma recortada.
    required property var capaDe
    required property var molde

    readonly property string filtro: capaDe ? capaDe.filtro : ""

    saturation: filtro === "gris" || filtro === "sepia" ? -1.0
              : filtro === "vivo" ? 0.35 : 0.0
    contrast: filtro === "vivo" ? 0.06 : 0.0

    colorization: filtro === "sepia" ? 0.5
                : filtro === "frio" || filtro === "calido" ? 0.18 : 0.0
    colorizationColor: filtro === "sepia" ? "#a97b4a"
                     : filtro === "frio" ? "#5aa9ff" : "#ffb066"

    maskEnabled: capaDe && capaDe.mascara.length > 0
    maskSource: molde

    //  La sombra, con la misma cuenta que python: difuminado y caída
    //  proporcionales al ancho de la capa, para que la misma sombra valga
    //  igual en un logo pequeño que en una cámara grande.
    readonly property real fuerza: capaDe && capaDe.sombra ? capaDe.sombra : 0
    readonly property real sigma: Math.max(2, 0.045 * (capaDe ? capaDe.width : 0))

    //  Sin máscara. Con ella, la sombra la pinta el lienzo con la forma del
    //  molde: al encender las dos a la vez, el relleno que MultiEffect añade
    //  para que quepa la sombra estira también el molde, y el círculo salía
    //  como un cuadrado de esquinas romas.
    shadowEnabled: fuerza > 0.001 && !maskEnabled
    shadowColor: Qt.rgba(0, 0, 0, 0.7 * fuerza)
    shadowBlur: Math.min(1, sigma / 32)
    shadowHorizontalOffset: sigma * (0.5 + fuerza)
    shadowVerticalOffset: sigma * (0.5 + fuerza)
}
