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

            //  Mientras no hay fotograma esto es un cristal: ocupa la pantalla
            //  y se traga los clics, pero no se ve ni se pinta en la foto.
            //  `opacity: 0` y no `visible: false` a propósito —lo invisible no
            //  recibe ratón, y recibir el ratón es justo lo que hace falta.
            readonly property bool activo: Captura.seleccionando
            opacity: activo ? 1 : 0

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

            //  El recuadro se enseña también MIENTRAS se traza, no solo al
            //  soltar: encuadrar a ciegas y descubrir el resultado al final
            //  es lo contrario de encuadrar. `hay` sigue diciendo si la
            //  selección está hecha; esto solo dice si se pinta.
            readonly property bool ensena: hay || trazando

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
                    // Solo las que están delante. Sin esto, una ventana de otro
                    // escritorio —que sigue en la lista de Hyprland, y encima
                    // con `visible: true`— se ofrecía como objetivo y lo que
                    // recortaba era el vacío.
                    if (!Ventanas.seVe(d))
                        continue
                    if (d.size[0] < 2 || d.size[1] < 2)
                        continue
                    salida.push({
                        x: d.at[0] - lienzo.origenX,
                        y: d.at[1] - lienzo.origenY,
                        w: d.size[0],
                        h: d.size[1],
                        titulo: String(d.title || d.class || ""),
                        // 0 es la que tiene el foco, y de ahí para atrás. Es el
                        // orden en que Hyprland las apila de verdad.
                        orden: typeof d.focusHistoryID === "number"
                            ? d.focusHistoryID : 9999
                    })
                }
                return salida
            }

            //  Cuál de las que hay debajo del cursor es la que quieres. El orden
            //  de la lista de Hyprland es el de creación, no el de apilado: dos
            //  ventanas solapadas se resolvían al azar. Gana la más reciente en
            //  el foco, que es la que se ve encima.
            function ventanaEn(x, y) {
                let mejor = -1
                for (let i = 0; i < ventanas.length; ++i) {
                    const v = ventanas[i]
                    if (x < v.x || x > v.x + v.w || y < v.y || y > v.y + v.h)
                        continue
                    if (mejor < 0 || v.orden < ventanas[mejor].orden)
                        mejor = i
                }
                return mejor
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
            //
            //  Con el ratón no se confirma: se dispara. Soltar YA es la
            //  respuesta —esta ventana, este recorte, toda la pantalla— y pedir
            //  además un Intro era hacer preguntar dos veces lo mismo. El Intro
            //  se queda para quien encuadra a flechas, que ahí sí hace falta
            //  decir cuándo has terminado.
            function confirmar() {
                if (!hay || anc < 2 || alt < 2)
                    return
                Captura.confirmarRegion(Math.round(izq) + lienzo.origenX,
                                        Math.round(arr) + lienzo.origenY,
                                        Math.round(anc), Math.round(alt))
            }

            function disparar(x, y, w, h) {
                if (w < 2 || h < 2)
                    return
                rx = x; ry = y; rw = w; rh = h
                hay = true
                Captura.confirmarRegion(Math.round(x) + lienzo.origenX,
                                        Math.round(y) + lienzo.origenY,
                                        Math.round(w), Math.round(h))
            }

            function dispararVentana(i) {
                if (i < 0 || i >= ventanas.length)
                    return false
                const v = ventanas[i]
                disparar(v.x, v.y, v.w, v.h)
                return true
            }

            function dispararPantalla() {
                disparar(0, 0, width, height)
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
                height: raiz.ensena ? Math.max(0, raiz.arr) : parent.height
            }
            Rectangle {
                visible: raiz.ensena
                color: raiz.tono
                anchors.left: parent.left; anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: Math.max(0, parent.height - raiz.arr - raiz.alt)
            }
            Rectangle {
                visible: raiz.ensena
                color: raiz.tono
                anchors.left: parent.left
                y: raiz.arr
                width: Math.max(0, raiz.izq)
                height: raiz.alt
            }
            Rectangle {
                visible: raiz.ensena
                color: raiz.tono
                anchors.right: parent.right
                y: raiz.arr
                width: Math.max(0, parent.width - raiz.izq - raiz.anc)
                height: raiz.alt
            }

            // ── lo que se llevaría un clic, ahora mismo ───────────
            //
            //  Como el clic ya no se puede deshacer con un Intro que no llega,
            //  hay que enseñar de antemano qué va a salir: el recuadro de la
            //  ventana señalada, o el de la pantalla si no hay ninguna debajo.
            Rectangle {
                id: presa
                // Solo en la pantalla donde está el puntero: si no, la otra se
                // quedaba anunciando «toda la pantalla» sin que nadie apuntase.
                visible: !raiz.ensena && raton.containsMouse
                readonly property var v: raiz.ventanaSenalada >= 0
                    ? raiz.ventanas[raiz.ventanaSenalada] : null

                color: Qt.rgba(10 / 255, 132 / 255, 1, 0.14)
                border.width: 1
                border.color: Theme.blue
                x: v ? v.x : 0
                y: v ? v.y : 0
                width: v ? v.w : raiz.width
                height: v ? v.h : raiz.height

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(nombre.implicitWidth + 20, parent.width - 8)
                    height: 26
                    radius: 13
                    color: "#cc000000"

                    IslandLabel {
                        id: nombre
                        anchors.centerIn: parent
                        width: Math.min(implicitWidth, parent.width - 16)
                        elide: Text.ElideRight
                        text: presa.v ? presa.v.titulo
                                      : Idioma.t("toda la pantalla")
                        color: Theme.ink
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }
                }
            }

            // ── el rectángulo ─────────────────────────────────────
            Rectangle {
                id: marco
                visible: raiz.ensena
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
                visible: raiz.ensena
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
                visible: !raiz.ensena
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
                    text: Idioma.t("clic captura lo señalado · arrastra para recortar · tab recorre · esc cancela")
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

                // Al abrir, el puntero ya está donde está: sin esto la primera
                // señalada no aparecía hasta mover el ratón un píxel.
                onEntered: raiz.ventanaSenalada = raiz.ventanaEn(mouseX, mouseY)

                onPositionChanged: function (ev) {
                    if (!raiz.activo)
                        return
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
                    // De cristal: el clic muere aquí y no pasa a nadie.
                    if (!raiz.activo)
                        return
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
                    if (!raiz.activo)
                        return
                    if (raiz.moviendo) {
                        raiz.moviendo = false
                        raiz.confirmar()
                        return
                    }
                    if (!raiz.trazando)
                        return
                    raiz.trazando = false

                    //  Aquí se decide qué querías, y se dispara sin preguntar
                    //  más. Arrastrar es un recorte; un clic seco es «entero»,
                    //  y qué es lo entero depende de dónde hayas pulsado: sobre
                    //  una ventana, esa ventana; sobre el fondo, la pantalla.
                    //
                    //  El umbral de 4 px es para que un temblor de la mano no
                    //  cuente como un arrastre de 1 px y te deje sin nada.
                    if (raiz.anc >= 4 || raiz.alt >= 4) {
                        raiz.hay = true
                        raiz.confirmar()
                        return
                    }

                    raiz.hay = false
                    if (!raiz.dispararVentana(raiz.ventanaEn(ev.x, ev.y)))
                        raiz.dispararPantalla()
                }
            }

            // ── el teclado ────────────────────────────────────────
            //
            //  Que se pueda hacer todo sin ratón no es un adorno de
            //  accesibilidad: es lo único que permite comprobar esta pantalla
            //  desde aquí, porque el compositor no acepta ratón sintético.
            Keys.onPressed: function (ev) {
                // De cristal solo se sale por Escape; lo demás se traga igual
                // que los clics, que si no la tecla acaba en la ventana.
                if (!raiz.activo) {
                    if (ev.key === Qt.Key_Escape)
                        Captura.cancelarRegion()
                    ev.accepted = true
                    return
                }

                const paso = (ev.modifiers & Qt.ControlModifier) ? 10 : 1
                const redimensiona = (ev.modifiers & Qt.ShiftModifier) !== 0

                if (ev.key === Qt.Key_Escape) {
                    Captura.cancelarRegion()
                } else if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter) {
                    raiz.confirmar()
                } else if (ev.key === Qt.Key_Tab || ev.key === Qt.Key_Backtab) {
                    //  Una parada más que ventanas hay: la última es la
                    //  pantalla entera. Así el mismo tabulador recorre los tres
                    //  objetivos y no hay que acordarse de una tecla aparte.
                    const paradas = raiz.ventanas.length + 1
                    const d = ev.key === Qt.Key_Tab ? 1 : -1
                    raiz.ventanaTab = (raiz.ventanaTab + d + paradas) % paradas
                    if (raiz.ventanaTab === raiz.ventanas.length) {
                        raiz.rx = 0; raiz.ry = 0
                        raiz.rw = raiz.width; raiz.rh = raiz.height
                        raiz.hay = true
                    } else {
                        raiz.tomarVentana(raiz.ventanaTab)
                    }
                } else if (ev.key === Qt.Key_Space
                           || (ev.key === Qt.Key_A
                               && (ev.modifiers & Qt.ControlModifier))) {
                    // Sin rodeos: la pantalla entera es una foto, no una
                    // propuesta que haya que aprobar.
                    raiz.dispararPantalla()
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
