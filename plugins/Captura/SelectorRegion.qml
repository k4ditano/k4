//  Elegir una región de la pantalla.
//
//  Se encuadra sobre un fotograma CONGELADO, no sobre el escritorio vivo, y eso
//  arregla de raíz el problema de slurp: si lo que quieres recortar es un menú
//  desplegado, o un vídeo, o cualquier cosa que se mueva, se te va mientras lo
//  encuadras. Aquí lo que ves es lo que se guarda, literalmente el mismo
//  fotograma.
//
//  Lo demás que aporta frente a slurp: se pega a los bordes de las ventanas,
//  dice cuántos píxeles llevas, trae lupa para el píxel exacto, y se puede
//  hacer entero con el teclado.
//
//  Nota de coordenadas: el congelado es una foto de TODO el espacio de
//  Hyprland, así que las coordenadas de la imagen son las globales. Las de este
//  Item son locales a la pantalla; de ahí las sumas y restas con `screen.x`.
//  Con un solo monitor es lo mismo y no se nota, con dos importa.

import QtQuick
import K4 as K4
import "../../core"
import "../../services"

K4.PorPantalla {
    delegate: K4.Ventana {
        id: lienzo

        required property var modelData
        screen: modelData

        // Por encima de todo, la island incluida: mientras encuadras no debe
        // haber nada que puedas pulsar sin querer, y el teclado es nuestro.
        nombre: "k4-selector"
        conTeclado: true

        readonly property int origenX: screen ? screen.x : 0
        readonly property int origenY: screen ? screen.y : 0

        Item {
            id: raiz
            anchors.fill: parent
            focus: true

            // ── la selección, en coordenadas de esta pantalla ─────
            property bool hay: false
            property real rx: 0
            property real ry: 0
            property real rw: 0
            property real rh: 0

            property bool trazando: false
            property bool moviendo: false
            property real anclaX: 0
            property real anclaY: 0

            // Qué ventana está señalada, para poder tomarla entera de un clic.
            property int ventanaSenalada: -1
            property int ventanaTab: -1

            readonly property real izq: Math.min(rx, rx + rw)
            readonly property real arr: Math.min(ry, ry + rh)
            readonly property real anc: Math.abs(rw)
            readonly property real alt: Math.abs(rh)

            Component.onCompleted: forceActiveFocus()

            // ── las ventanas a las que engancharse ────────────────
            //
            //  Solo las que se ven: una ventana de otro escritorio sigue en la
            //  lista de Hyprland, pero no está en el fotograma, así que
            //  engancharse a ella sería recortar el vacío.
            readonly property var ventanas: {
                const salida = []
                const todas = Ventanas.lista
                for (let i = 0; i < todas.length; ++i) {
                    const d = todas[i].lastIpcObject
                    if (!d || !d.at || !d.size)
                        continue
                    if (d.hidden === true || d.mapped === false)
                        continue
                    if (d.size[0] < 2 || d.size[1] < 2)
                        continue
                    salida.push({
                        x: d.at[0] - lienzo.origenX,
                        y: d.at[1] - lienzo.origenY,
                        w: d.size[0],
                        h: d.size[1],
                        titulo: String(d.title || d.class || "")
                    })
                }
                return salida
            }

            function ventanaEn(x, y) {
                // De la última a la primera: las de encima ganan, que es el
                // orden en que Hyprland las apila.
                for (let i = ventanas.length - 1; i >= 0; --i) {
                    const v = ventanas[i]
                    if (x >= v.x && x <= v.x + v.w && y >= v.y && y <= v.y + v.h)
                        return i
                }
                return -1
            }

            function tomarVentana(i) {
                if (i < 0 || i >= ventanas.length)
                    return
                const v = ventanas[i]
                rx = v.x; ry = v.y; rw = v.w; rh = v.h
                hay = true
            }

            // ── imán a los bordes ─────────────────────────────────
            //
            //  12 px: lo justo para que enganche cuando lo buscas y no cuando
            //  no. Con menos hay que apuntar, con más se pega solo y estorba.
            readonly property int iman: 12

            function pegar(v, candidatos) {
                for (let i = 0; i < candidatos.length; ++i) {
                    if (Math.abs(v - candidatos[i]) <= iman)
                        return candidatos[i]
                }
                return v
            }

            function bordesX() {
                const b = [0, width]
                for (let i = 0; i < ventanas.length; ++i)
                    b.push(ventanas[i].x, ventanas[i].x + ventanas[i].w)
                return b
            }

            function bordesY() {
                const b = [0, height]
                for (let i = 0; i < ventanas.length; ++i)
                    b.push(ventanas[i].y, ventanas[i].y + ventanas[i].h)
                return b
            }

            // ── salir ─────────────────────────────────────────────
            function confirmar() {
                if (!hay || anc < 2 || alt < 2)
                    return
                Captura.confirmarRegion(Math.round(izq) + lienzo.origenX,
                                        Math.round(arr) + lienzo.origenY,
                                        Math.round(anc), Math.round(alt))
            }

            // ── el fotograma congelado ────────────────────────────
            Image {
                id: fondo
                anchors.fill: parent
                source: Captura.congelado.length > 0
                    ? "file://" + Captura.congelado : ""
                // El congelado abarca todo el espacio; esta pantalla es un
                // trozo de él.
                sourceClipRect: Qt.rect(lienzo.origenX, lienzo.origenY,
                                        raiz.width, raiz.height)
                fillMode: Image.Pad
                asynchronous: false
                cache: false
            }

            // ── el velo, con el hueco de la selección ─────────────
            //
            //  Cuatro rectángulos alrededor en vez de una máscara: cuesta
            //  muchísimo menos y se ve igual.
            readonly property color tono: Qt.rgba(0, 0, 0, 0.45)

            Rectangle {
                color: raiz.tono
                anchors.left: parent.left; anchors.right: parent.right
                anchors.top: parent.top
                height: raiz.hay ? Math.max(0, raiz.arr) : parent.height
            }
            Rectangle {
                visible: raiz.hay
                color: raiz.tono
                anchors.left: parent.left; anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: Math.max(0, parent.height - raiz.arr - raiz.alt)
            }
            Rectangle {
                visible: raiz.hay
                color: raiz.tono
                anchors.left: parent.left
                y: raiz.arr
                width: Math.max(0, raiz.izq)
                height: raiz.alt
            }
            Rectangle {
                visible: raiz.hay
                color: raiz.tono
                anchors.right: parent.right
                y: raiz.arr
                width: Math.max(0, parent.width - raiz.izq - raiz.anc)
                height: raiz.alt
            }

            // ── la ventana señalada, antes de haber selección ─────
            Rectangle {
                visible: !raiz.hay && raiz.ventanaSenalada >= 0
                color: Qt.rgba(10 / 255, 132 / 255, 1, 0.14)
                border.width: 1
                border.color: Theme.blue
                x: visible ? raiz.ventanas[raiz.ventanaSenalada].x : 0
                y: visible ? raiz.ventanas[raiz.ventanaSenalada].y : 0
                width: visible ? raiz.ventanas[raiz.ventanaSenalada].w : 0
                height: visible ? raiz.ventanas[raiz.ventanaSenalada].h : 0
            }

            // ── el rectángulo ─────────────────────────────────────
            Rectangle {
                id: marco
                visible: raiz.hay
                x: raiz.izq
                y: raiz.arr
                width: raiz.anc
                height: raiz.alt
                color: "transparent"
                border.width: 1
                border.color: Theme.blue

                // Los ocho tiradores. No son pulsables —redimensionar va por
                // teclado— pero dicen a la vista que eso se puede agarrar.
                Repeater {
                    model: [[0, 0], [0.5, 0], [1, 0],
                            [0, 0.5],          [1, 0.5],
                            [0, 1], [0.5, 1], [1, 1]]

                    delegate: Rectangle {
                        required property var modelData
                        width: 7; height: 7; radius: 1.5
                        color: Theme.blue
                        x: marco.width * modelData[0] - 3.5
                        y: marco.height * modelData[1] - 3.5
                    }
                }
            }

            // ── cuánto llevas ─────────────────────────────────────
            Rectangle {
                visible: raiz.hay
                radius: 4
                color: "#cc000000"
                width: medida.implicitWidth + 12
                height: 20
                x: Math.min(Math.max(0, raiz.izq), raiz.width - width)
                // Encima del rectángulo si cabe; si no, dentro. Que no se salga
                // por arriba al recortar algo pegado al borde superior.
                y: raiz.arr > 24 ? raiz.arr - 24 : raiz.arr + 4

                IslandLabel {
                    id: medida
                    anchors.centerIn: parent
                    text: Math.round(raiz.anc) + " × " + Math.round(raiz.alt)
                    color: Theme.ink
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }
            }

            // ── la lupa ───────────────────────────────────────────
            //
            //  Ampliación entera y sin suavizado: la gracia es ver el píxel,
            //  y un filtro bilineal lo que hace es esconderlo.
            Item {
                id: lupa
                visible: !raiz.hay || raiz.trazando
                width: 164
                height: 104
                clip: true

                readonly property int aumento: 6

                // En la esquina contraria al cursor, para no tapar justo lo que
                // estás mirando.
                x: raton.mouseX < raiz.width / 2 ? raiz.width - width - 24 : 24
                y: raton.mouseY < raiz.height / 2 ? raiz.height - height - 24 : 24

                Rectangle {
                    anchors.fill: parent
                    color: "#dd000000"
                    radius: 8
                }

                Item {
                    id: cristal
                    anchors.fill: parent
                    anchors.margins: 2
                    clip: true

                    //  Ampliar con `scale` y origen arriba-izquierda, no con
                    //  una lista de `transform`: con la lista el orden en que
                    //  se componen no es el que uno escribe, y la lupa salía
                    //  vacía sin una sola queja en el log. Con scale y una
                    //  posición calculada la cuenta se ve y se puede seguir.
                    //
                    //  El fotograma se queda a tamaño natural; lo que se
                    //  agranda es cómo se pinta, que además es gratis. Darle a
                    //  la imagen un ancho de 11520 px tampoco dibujaba nada.
                    Item {
                        width: raiz.width
                        height: raiz.height
                        transformOrigin: Item.TopLeft
                        scale: lupa.aumento
                        x: cristal.width / 2 - raton.mouseX * lupa.aumento
                        y: cristal.height / 2 - raton.mouseY * lupa.aumento

                        Image {
                            anchors.fill: parent
                            source: fondo.source
                            sourceClipRect: fondo.sourceClipRect
                            fillMode: Image.Pad
                            cache: false
                            smooth: false
                        }
                    }

                    // La retícula, en el píxel exacto bajo el cursor.
                    Rectangle {
                        width: lupa.aumento; height: lupa.aumento
                        x: parent.width / 2 - lupa.aumento / 2
                        y: parent.height / 2 - lupa.aumento / 2
                        color: "transparent"
                        border.width: 1
                        border.color: Theme.blue
                    }
                }

                IslandLabel {
                    anchors.bottom: parent.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottomMargin: 3
                    text: Math.round(raton.mouseX) + ", " + Math.round(raton.mouseY)
                    color: Theme.muted
                    font.pixelSize: 9
                }
            }

            // ── la chuleta ────────────────────────────────────────
            Rectangle {
                visible: !raiz.hay
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 60
                width: ayuda.implicitWidth + 24
                height: 30
                radius: 15
                color: "#cc000000"

                IslandLabel {
                    id: ayuda
                    anchors.centerIn: parent
                    text: Idioma.t("arrastra · clic toma la ventana · tab la cambia · esc cancela")
                    color: Theme.muted
                    font.pixelSize: 11
                }
            }

            Rectangle {
                visible: raiz.hay
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 40
                width: ayuda2.implicitWidth + 24
                height: 30
                radius: 15
                color: "#cc000000"

                IslandLabel {
                    id: ayuda2
                    anchors.centerIn: parent
                    text: Idioma.t("intro captura · flechas mueven · mayús+flechas redimensionan · esc cancela")
                    color: Theme.muted
                    font.pixelSize: 11
                }
            }

            // ── el ratón ──────────────────────────────────────────
            MouseArea {
                id: raton
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.CrossCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton

                onPositionChanged: function (ev) {
                    if (!raiz.hay)
                        raiz.ventanaSenalada = raiz.ventanaEn(ev.x, ev.y)

                    if (raiz.trazando) {
                        raiz.rw = raiz.pegar(ev.x, raiz.bordesX()) - raiz.rx
                        raiz.rh = raiz.pegar(ev.y, raiz.bordesY()) - raiz.ry
                    } else if (raiz.moviendo) {
                        raiz.rx = ev.x - raiz.anclaX
                        raiz.ry = ev.y - raiz.anclaY
                    }
                }

                onPressed: function (ev) {
                    if (ev.button === Qt.RightButton) {
                        Captura.cancelarRegion()
                        return
                    }

                    // Dentro de la selección se mueve; fuera se traza una nueva.
                    if (raiz.hay && ev.x >= raiz.izq && ev.x <= raiz.izq + raiz.anc
                        && ev.y >= raiz.arr && ev.y <= raiz.arr + raiz.alt) {
                        raiz.moviendo = true
                        raiz.anclaX = ev.x - raiz.izq
                        raiz.anclaY = ev.y - raiz.arr
                        raiz.rx = raiz.izq; raiz.ry = raiz.arr
                        raiz.rw = raiz.anc; raiz.rh = raiz.alt
                        return
                    }

                    raiz.anclaX = ev.x
                    raiz.anclaY = ev.y
                    raiz.rx = raiz.pegar(ev.x, raiz.bordesX())
                    raiz.ry = raiz.pegar(ev.y, raiz.bordesY())
                    raiz.rw = 0
                    raiz.rh = 0
                    raiz.trazando = true
                }

                onReleased: function (ev) {
                    if (raiz.moviendo) {
                        raiz.moviendo = false
                        return
                    }
                    if (!raiz.trazando)
                        return
                    raiz.trazando = false

                    // Un clic sin arrastre es «dame esta ventana entera». El
                    // umbral de 4 px es para que un temblor de la mano no
                    // cuente como arrastre de 1 px y te deje sin selección.
                    if (raiz.anc < 4 && raiz.alt < 4) {
                        raiz.hay = false
                        raiz.tomarVentana(raiz.ventanaEn(ev.x, ev.y))
                    } else {
                        raiz.hay = true
                    }
                }
            }

            // ── el teclado ────────────────────────────────────────
            //
            //  Que se pueda hacer todo sin ratón no es un adorno de
            //  accesibilidad: es lo único que permite comprobar esta pantalla
            //  desde aquí, porque el compositor no acepta ratón sintético.
            Keys.onPressed: function (ev) {
                const paso = (ev.modifiers & Qt.ControlModifier) ? 10 : 1
                const redimensiona = (ev.modifiers & Qt.ShiftModifier) !== 0

                if (ev.key === Qt.Key_Escape) {
                    Captura.cancelarRegion()
                } else if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter) {
                    raiz.confirmar()
                } else if (ev.key === Qt.Key_Tab || ev.key === Qt.Key_Backtab) {
                    if (raiz.ventanas.length > 0) {
                        const d = ev.key === Qt.Key_Tab ? 1 : -1
                        raiz.ventanaTab = (raiz.ventanaTab + d + raiz.ventanas.length)
                            % raiz.ventanas.length
                        raiz.tomarVentana(raiz.ventanaTab)
                    }
                } else if (ev.key === Qt.Key_A
                           && (ev.modifiers & Qt.ControlModifier)) {
                    raiz.rx = 0; raiz.ry = 0
                    raiz.rw = raiz.width; raiz.rh = raiz.height
                    raiz.hay = true
                } else if (ev.key === Qt.Key_Left) {
                    if (redimensiona) raiz.rw = Math.max(1, raiz.anc - paso)
                    else raiz.rx = raiz.izq - paso
                } else if (ev.key === Qt.Key_Right) {
                    if (redimensiona) raiz.rw = raiz.anc + paso
                    else raiz.rx = raiz.izq + paso
                } else if (ev.key === Qt.Key_Up) {
                    if (redimensiona) raiz.rh = Math.max(1, raiz.alt - paso)
                    else raiz.ry = raiz.arr - paso
                } else if (ev.key === Qt.Key_Down) {
                    if (redimensiona) raiz.rh = raiz.alt + paso
                    else raiz.ry = raiz.arr + paso
                } else {
                    return
                }

                // Normalizar tras tocar por teclado: si no, un ancho negativo
                // heredado del arrastre hace que las flechas vayan al revés.
                if (ev.key === Qt.Key_Left || ev.key === Qt.Key_Right
                    || ev.key === Qt.Key_Up || ev.key === Qt.Key_Down) {
                    raiz.rx = raiz.izq; raiz.ry = raiz.arr
                    raiz.rw = raiz.anc; raiz.rh = raiz.alt
                    raiz.hay = true
                }
                ev.accepted = true
            }
        }
    }
}
