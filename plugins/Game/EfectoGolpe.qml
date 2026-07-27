//  El golpe de un héroe, dibujado.
//
//  Antes todos los ataques eran el mismo número flotante: daba igual que
//  pegara la arquera o el bárbaro. Cada clase declara su forma y su color en
//  el servicio, y aquí se traduce a algo que se ve:
//
//    · proyectil — una esfera que viaja y revienta (magia)
//    · flecha    — una línea rápida y fina (tiro)
//    · tajo      — dos cortes cruzados en el blanco (cuerpo a cuerpo)
//    · destello  — un anillo que se abre en el blanco (sagrado)
//
//  Se crea uno por golpe y se destruye solo al acabar: nada que limpiar.

import QtQuick

Item {
    id: efecto

    property string forma: "tajo"
    property color tono: "#ffffff"
    property real desdeX: 0
    property real desdeY: 0
    property real hastaX: 0
    property real hastaY: 0

    anchors.fill: parent

    function arrancar() {
        if (forma === "proyectil" || forma === "flecha")
            viaje.start()
        else if (forma === "destello")
            anillo.start()
        else
            corte.start()
    }

    // ── lo que viaja ──────────────────────────────────────────────
    Rectangle {
        id: bala
        visible: efecto.forma === "proyectil" || efecto.forma === "flecha"
        width: efecto.forma === "flecha" ? 15 : 8
        height: efecto.forma === "flecha" ? 2 : 8
        radius: efecto.forma === "flecha" ? 1 : 4
        color: efecto.tono
        opacity: 0
        x: efecto.desdeX
        y: efecto.desdeY

        // un halo tenue detrás, que es lo que hace que se lea como magia
        Rectangle {
            anchors.centerIn: parent
            width: parent.width * 2.4
            height: parent.height * 2.4
            radius: width / 2
            color: efecto.tono
            opacity: 0.28
            visible: efecto.forma === "proyectil"
        }
    }

    SequentialAnimation {
        id: viaje

        ParallelAnimation {
            NumberAnimation {
                target: bala; property: "x"
                from: efecto.desdeX; to: efecto.hastaX
                duration: efecto.forma === "flecha" ? 260 : 430
                easing.type: efecto.forma === "flecha" ? Easing.Linear : Easing.InQuad
            }
            NumberAnimation {
                target: bala; property: "y"
                from: efecto.desdeY; to: efecto.hastaY
                duration: efecto.forma === "flecha" ? 260 : 430
            }
            NumberAnimation {
                target: bala; property: "opacity"
                from: 0; to: 1; duration: 60
            }
        }

        // reventón corto al llegar
        ParallelAnimation {
            NumberAnimation {
                target: bala; property: "scale"
                from: 1; to: 2.8; duration: 190
            }
            NumberAnimation {
                target: bala; property: "opacity"
                to: 0; duration: 190
            }
        }

        ScriptAction { script: efecto.destroy() }
    }

    // ── el corte ──────────────────────────────────────────────────
    Item {
        id: tajo
        visible: efecto.forma === "tajo"
        width: 34
        height: 34
        x: efecto.hastaX - 17
        y: efecto.hastaY - 17
        opacity: 0
        scale: 0.55

        Repeater {
            model: 2

            delegate: Rectangle {
                required property int index
                anchors.centerIn: parent
                width: 30
                height: 2.5
                radius: 1.25
                color: efecto.tono
                rotation: index === 0 ? -38 : 24
            }
        }
    }

    SequentialAnimation {
        id: corte

        ParallelAnimation {
            NumberAnimation {
                target: tajo; property: "opacity"
                from: 0; to: 1; duration: 70
            }
            NumberAnimation {
                target: tajo; property: "scale"
                from: 0.55; to: 1.3; duration: 230
                easing.type: Easing.OutQuad
            }
        }

        NumberAnimation {
            target: tajo; property: "opacity"
            to: 0; duration: 200
        }

        ScriptAction { script: efecto.destroy() }
    }

    // ── el anillo ─────────────────────────────────────────────────
    Rectangle {
        id: aro
        visible: efecto.forma === "destello"
        width: 8
        height: 8
        radius: width / 2
        x: efecto.hastaX - width / 2
        y: efecto.hastaY - height / 2
        color: "transparent"
        border.width: 2
        border.color: efecto.tono
        opacity: 0
    }

    SequentialAnimation {
        id: anillo

        ParallelAnimation {
            NumberAnimation {
                target: aro; property: "width"
                from: 8; to: 46; duration: 400
                easing.type: Easing.OutQuad
            }
            NumberAnimation {
                target: aro; property: "height"
                from: 8; to: 46; duration: 400
                easing.type: Easing.OutQuad
            }
            SequentialAnimation {
                NumberAnimation {
                    target: aro; property: "opacity"
                    from: 0; to: 1; duration: 80
                }
                NumberAnimation {
                    target: aro; property: "opacity"
                    to: 0; duration: 300
                }
            }
        }

        ScriptAction { script: efecto.destroy() }
    }
}
