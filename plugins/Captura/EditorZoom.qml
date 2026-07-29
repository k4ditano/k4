//  El editor del zoom: se ve el vídeo, con el zoom aplicado, mientras corre.
//
//  Lo que se reproduce es el fichero ORIGINAL, sin tocar. El zoom se aplica
//  aquí, con una transformación sobre la imagen, siguiendo la trayectoria que
//  ha calculado tools/zoom.py. Y son exactamente los mismos puntos que se
//  convierten en la expresión de ffmpeg —entre ellos se interpola en recta,
//  igual que hace el filtro—, así que lo que ves aquí es lo que va a salir en
//  el fichero. Sin renderizar nada y sin dos implementaciones que se separen.
//
//  De ahí que se pueda mover un momento y ver el efecto al instante: solo hay
//  que rehacer la trayectoria, que es aritmética.

import QtQuick
import QtQuick.Layouts
import QtMultimedia
import "../../core"
import "../../services"

FadeIn {
    id: view

    required property var plugin

    focus: true

    property int elegido: 0

    readonly property var momento: Captura.momentos.length > 0
        ? Captura.momentos[Math.min(elegido, Captura.momentos.length - 1)] : null

    readonly property real segundos: reproductor.position / 1000
    readonly property real total: Math.max(0.001, Captura.duracionVideo)

    Component.onCompleted: forceActiveFocus()

    // ── dónde está la cámara ahora ────────────────────────────────
    //
    //  Búsqueda binaria sobre los puntos y recta entre los dos vecinos. Con
    //  ciento y pico puntos daría igual recorrerlos, pero esto se evalúa en
    //  cada fotograma y no cuesta nada hacerlo bien.
    function camaraEn(t) {
        const c = Captura.camara
        if (!c || c.length === 0)
            return [1, 0, 0]
        if (t <= c[0][0])
            return [c[0][1], c[0][2], c[0][3]]
        if (t >= c[c.length - 1][0]) {
            const u = c[c.length - 1]
            return [u[1], u[2], u[3]]
        }
        let lo = 0, hi = c.length - 1
        while (hi - lo > 1) {
            const m = (lo + hi) >> 1
            if (c[m][0] <= t) lo = m; else hi = m
        }
        const a = c[lo], b = c[hi]
        const d = b[0] - a[0]
        const f = d > 0 ? (t - a[0]) / d : 0
        return [a[1] + (b[1] - a[1]) * f,
                a[2] + (b[2] - a[2]) * f,
                a[3] + (b[3] - a[3]) * f]
    }

    //  Mientras arrastras el encuadre manda esto, y al soltar se vuelve a la
    //  trayectoria que calcula python. Es lo que separa un arrastre que
    //  responde de uno que va a saltos.
    property var camaraForzada: null

    // El recorte que corresponde a un centro dado, con el zoom de ahora.
    function encuadreEn(cx, cy) {
        const z = estadoCamara ? estadoCamara[0] : 1
        const w = Captura.anchoVideo / z
        const h = Captura.altoVideo / z
        return [z,
                Math.max(0, Math.min(Captura.anchoVideo - w, cx - w / 2)),
                Math.max(0, Math.min(Captura.altoVideo - h, cy - h / 2))]
    }

    readonly property var estadoCamara: camaraForzada
        ? camaraForzada : camaraEn(segundos)
    readonly property bool conZoom: estadoCamara[0] > 1.001

    function irA(t) {
        reproductor.position = Math.max(0, Math.min(total, t)) * 1000
    }

    Keys.onPressed: function (ev) {
        if (ev.key === Qt.Key_Space) {
            reproductor.playbackState === MediaPlayer.PlayingState
                ? reproductor.pause() : reproductor.play()
        } else if (ev.key === Qt.Key_Left) {
            if ((ev.modifiers & Qt.ShiftModifier) && view.momento)
                Captura.moverMomento(view.momento.id, -0.2)
            else
                view.irA(view.segundos - 1)
        } else if (ev.key === Qt.Key_Right) {
            if ((ev.modifiers & Qt.ShiftModifier) && view.momento)
                Captura.moverMomento(view.momento.id, 0.2)
            else
                view.irA(view.segundos + 1)
        } else if (ev.key === Qt.Key_Down || ev.key === Qt.Key_Tab) {
            if (Captura.momentos.length > 0) {
                view.elegido = (view.elegido + 1) % Captura.momentos.length
                view.irA(view.momento.t0)
            }
        } else if (ev.key === Qt.Key_Up || ev.key === Qt.Key_Backtab) {
            if (Captura.momentos.length > 0) {
                view.elegido = (view.elegido - 1 + Captura.momentos.length)
                    % Captura.momentos.length
                view.irA(view.momento.t0)
            }
        } else if (ev.key === Qt.Key_Plus || ev.key === Qt.Key_Equal) {
            if (view.momento) Captura.ajustarNivel(view.momento.id, 0.2)
        } else if (ev.key === Qt.Key_Minus) {
            if (view.momento) Captura.ajustarNivel(view.momento.id, -0.2)
        } else if (ev.key === Qt.Key_Delete || ev.key === Qt.Key_Backspace) {
            if (view.momento) Captura.quitarMomento(view.momento.id)
        } else if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter) {
            Captura.renderizar()
        } else {
            return
        }
        ev.accepted = true
    }

    //  Con sonido.
    //
    //  Estaba en `audioOutput: null` «para no asustar», y el efecto real era
    //  peor: grabas, se abre el editor, no oyes nada y concluyes que la
    //  grabación salió muda. Revisar un vídeo es también oírlo. El botón de
    //  silencio está en el pie para quien no lo quiera.
    property AudioOutput altavoz: AudioOutput {
        muted: view.silenciado
    }

    property bool silenciado: false

    MediaPlayer {
        id: reproductor
        source: Captura.rutaVideo.length > 0 ? "file://" + Captura.rutaVideo : ""
        videoOutput: salida
        audioOutput: altavoz
        Component.onCompleted: play()
        onMediaStatusChanged: {
            if (mediaStatus === MediaPlayer.EndOfMedia) {
                position = 0
                play()
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 8

        // ── cabecera ──────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            IconGlyph {
                text: String.fromCodePoint(0xF1276)      // md-magnify_scan
                color: Theme.blue
                font.pixelSize: 16
            }

            IslandLabel {
                text: Idioma.f(Idioma.t("%1 momentos de zoom"),
                               String(Captura.momentos.length))
                color: Theme.ink
                font.pixelSize: 13
                font.weight: Font.DemiBold
            }

            IslandLabel {
                text: Captura.rutaVideo.split("/").pop()
                color: Theme.dim
                font.pixelSize: 10
                elide: Text.ElideMiddle
                Layout.fillWidth: true
            }

            // Apartar: sigue ahí, en la píldora, para retomarlo luego.
            MediaButton {
                glyph: String.fromCodePoint(0xF0374)     // md-minus
                glyphSize: 13
                glyphColor: Theme.muted
                onActivated: view.plugin.close()
            }

            // Descartar: se tira el plan. El vídeo sin tocar sigue guardado.
            MediaButton {
                glyph: Theme.ico.close
                glyphSize: 13
                glyphColor: Theme.muted
                onActivated: view.plugin.descartar()
            }
        }

        // ── el vídeo, con el zoom puesto ──────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 12

            Rectangle {
                id: marco
                Layout.preferredWidth: 640
                Layout.fillHeight: true
                radius: 8
                color: "black"
                clip: true

                //  La imagen llena el marco, y encima va la transformación que
                //  hace el zoom. Escalar y desplazar sobre lo ya pintado es
                //  justo lo que hace `zoompan` con su recorte, solo que aquí
                //  sale gratis.
                Item {
                    id: lente

                    //  Sin `anchors.fill`, y no es un capricho: **un elemento
                    //  anclado no se puede mover con x e y**. El ancla manda, y
                    //  con ella puestas el `scale` sí se aplicaba pero el
                    //  desplazamiento no, así que el zoom salía siempre pegado
                    //  a la esquina superior izquierda pasara lo que pasara con
                    //  el encuadre.
                    //
                    //  Es exactamente la misma trampa que costó el arrastre de
                    //  la mazmorra, documentada en CeldaObjeto.qml. Volver a
                    //  caer en ella dice bastante de lo bien que se esconde.
                    width: marco.width
                    height: marco.height

                    readonly property real escala: view.estadoCamara[0]
                    // de píxeles del vídeo a píxeles de este marco
                    readonly property real factor: marco.width / Math.max(1, Captura.anchoVideo)

                    transformOrigin: Item.TopLeft
                    scale: escala
                    x: -view.estadoCamara[1] * factor * escala
                    y: -view.estadoCamara[2] * factor * escala

                    VideoOutput {
                        id: salida
                        anchors.fill: parent
                        fillMode: VideoOutput.Stretch
                    }
                }

                //  Arrastrar el encuadre.
                //
                //  Va POR ENCIMA de `lente` y no dentro, porque dentro la
                //  escala del zoom se aplicaría también a las coordenadas del
                //  ratón y el encuadre se movería más deprisa cuanto más
                //  ampliado estuviera.
                //
                //  Se agarra el contenido, no la cámara: llevas la imagen
                //  hacia donde quieres mirar, que es como funciona un mapa.
                MouseArea {
                    anchors.fill: parent
                    enabled: view.momento !== null
                        && view.segundos >= view.momento.t0
                        && view.segundos <= view.momento.t1
                    cursorShape: enabled
                        ? (pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor)
                        : Qt.ArrowCursor

                    property real xIni: 0
                    property real yIni: 0
                    property real cxIni: 0
                    property real cyIni: 0

                    onPressed: function (ev) {
                        xIni = ev.x; yIni = ev.y
                        cxIni = view.momento.cx
                        cyIni = view.momento.cy
                    }

                    onPositionChanged: function (ev) {
                        if (!pressed || !view.momento)
                            return
                        const f = lente.factor * lente.escala
                        const cx = cxIni - (ev.x - xIni) / f
                        const cy = cyIni - (ev.y - yIni) / f
                        // Se pinta ya, sin esperar a que python rehaga la
                        // trayectoria: si no, el arrastre se sentiría a cuatro
                        // fotogramas por segundo.
                        view.camaraForzada = view.encuadreEn(cx, cy)
                        Captura.moverCentro(view.momento.id, cx, cy)
                    }

                    onReleased: view.camaraForzada = null

                    //  La rueda cambia el nivel del momento que esté sonando.
                    //  En el propio MouseArea: un WheelHandler hijo no recibe
                    //  el evento, se lo queda el área.
                    onWheel: function (ev) {
                        if (view.momento)
                            Captura.ajustarNivel(view.momento.id,
                                                 ev.angleDelta.y > 0 ? 0.1 : -0.1)
                        ev.accepted = true
                    }
                }

                // Que lo que ves lleva zoom, para no confundirlo con el vídeo
                // tal cual.
                Rectangle {
                    visible: view.conZoom
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: 6
                    width: marcaZoom.implicitWidth + 12
                    height: 18
                    radius: 9
                    color: "#cc0a84ff"

                    IslandLabel {
                        id: marcaZoom
                        anchors.centerIn: parent
                        text: "×" + view.estadoCamara[0].toFixed(2)
                        color: Theme.ink
                        font.pixelSize: 9
                        font.weight: Font.DemiBold
                    }
                }
            }

            // ── la ficha del momento ──────────────────────────────
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 6

                IslandLabel {
                    text: view.momento
                        ? Idioma.t("Momento ") + view.momento.id
                        : Idioma.t("Sin momentos")
                    color: Theme.ink
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }

                IslandLabel {
                    visible: view.momento !== null
                    text: view.momento
                        ? view.momento.t0.toFixed(1) + " – " + view.momento.t1.toFixed(1) + " s"
                          + "   ·   ×" + view.momento.z.toFixed(1)
                        : ""
                    color: Theme.muted
                    font.pixelSize: 11
                }

                Item { Layout.fillHeight: true }

                GridLayout {
                    columns: 2
                    columnSpacing: 6
                    rowSpacing: 6
                    Layout.fillWidth: true

                    Repeater {
                        model: [
                            { texto: Idioma.t("Antes"),   icono: 0xF0141, accion: "antes" },
                            { texto: Idioma.t("Después"), icono: 0xF0142, accion: "despues" },
                            { texto: Idioma.t("Menos"),   icono: 0xF034A, accion: "menos" },
                            { texto: Idioma.t("Más"),     icono: 0xF034B, accion: "mas" }
                        ]

                        delegate: Rectangle {
                            id: boton
                            required property var modelData

                            Layout.fillWidth: true
                            Layout.preferredHeight: 26
                            radius: 13
                            color: botonRaton.containsMouse ? Theme.surfaceHi : Theme.surface
                            opacity: view.momento ? 1 : 0.4

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 5

                                IconGlyph {
                                    text: String.fromCodePoint(boton.modelData.icono)
                                    color: Theme.muted
                                    font.pixelSize: 12
                                }

                                IslandLabel {
                                    text: boton.modelData.texto
                                    font.pixelSize: 10
                                }
                            }

                            MouseArea {
                                id: botonRaton
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: view.momento !== null
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    const a = boton.modelData.accion
                                    if (a === "antes")        Captura.moverMomento(view.momento.id, -0.2)
                                    else if (a === "despues") Captura.moverMomento(view.momento.id, 0.2)
                                    else if (a === "menos")   Captura.ajustarNivel(view.momento.id, -0.2)
                                    else if (a === "mas")     Captura.ajustarNivel(view.momento.id, 0.2)
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 26
                    radius: 13
                    color: quitarRaton.containsMouse ? "#3a1416" : Theme.surface
                    border.width: 1
                    border.color: Qt.rgba(1, 0.27, 0.23, 0.3)
                    opacity: view.momento ? 1 : 0.4

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 5

                        IconGlyph {
                            text: String.fromCodePoint(0xF01B4)     // md-delete
                            color: Theme.red
                            font.pixelSize: 12
                        }

                        IslandLabel {
                            text: Idioma.t("Quitar")
                            font.pixelSize: 10
                        }
                    }

                    MouseArea {
                        id: quitarRaton
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: view.momento !== null
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Captura.quitarMomento(view.momento.id)
                    }
                }
            }
        }

        // ── la línea de tiempo ────────────────────────────────────
        Pista {
            Layout.fillWidth: true
            Layout.preferredHeight: 36

            modelo: Captura.momentos
            total: view.total
            cabezal: view.segundos
            elegido: view.elegido

            onSaltar: function (t) { view.irA(t) }
            onElegir: function (i) { view.elegido = i }
            onEditar: function (id, a, b) {
                Captura.fijarMomento(id, { t0: a, t1: b })
            }
            onCrear: function (a, b) {
                view.elegido = Captura.momentos.length
                Captura.crearMomento(a, b)
            }
            onNivel: function (id, d) {
                Captura.ajustarNivel(id, d > 0 ? 0.1 : -0.1)
            }
        }

        // ── pie ───────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            MediaButton {
                glyph: reproductor.playbackState === MediaPlayer.PlayingState
                    ? Theme.ico.pause : Theme.ico.play
                glyphSize: 16
                glyphColor: Theme.ink
                onActivated: reproductor.playbackState === MediaPlayer.PlayingState
                    ? reproductor.pause() : reproductor.play()
            }

            MediaButton {
                glyph: String.fromCodePoint(view.silenciado ? 0xF0581 : 0xF057E)
                glyphSize: 15
                glyphColor: view.silenciado ? Theme.dim : Theme.ink
                onActivated: view.silenciado = !view.silenciado
            }

            IslandLabel {
                text: view.segundos.toFixed(1) + " / " + view.total.toFixed(1) + " s"
                color: Theme.muted
                font.pixelSize: 10
            }

            IslandLabel {
                visible: Captura.estado !== "renderizando"
                text: Idioma.t("espacio reproduce · ←→ salta · ↑↓ momento · mayús+←→ lo mueve · +− nivel")
                color: Theme.dim
                font.pixelSize: 9
                Layout.leftMargin: 6
            }

            Rectangle {
                visible: Captura.estado === "renderizando"
                Layout.fillWidth: true
                Layout.preferredHeight: 6
                radius: 3
                color: Theme.track

                Rectangle {
                    width: parent.width * Captura.progreso
                    height: parent.height
                    radius: parent.radius
                    color: Theme.blue
                    Behavior on width { NumberAnimation { duration: 200 } }
                }
            }

            IslandLabel {
                visible: Captura.estado === "renderizando"
                text: Math.round(Captura.progreso * 100) + " %"
                color: Theme.muted
                font.pixelSize: 10
            }

            Item { Layout.fillWidth: true; visible: Captura.estado !== "renderizando" }

            Rectangle {
                visible: Captura.estado !== "renderizando"
                Layout.preferredWidth: renderTexto.implicitWidth + 24
                Layout.preferredHeight: 26
                radius: 13
                color: Captura.momentos.length === 0 ? Theme.surface
                    : (renderRaton.containsMouse ? Qt.lighter(Theme.blue, 1.15) : Theme.blue)
                opacity: Captura.momentos.length === 0 ? 0.4 : 1

                IslandLabel {
                    id: renderTexto
                    anchors.centerIn: parent
                    text: Idioma.t("Renderizar")
                    color: Theme.ink
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }

                MouseArea {
                    id: renderRaton
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: Captura.momentos.length > 0
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Captura.renderizar()
                }
            }
        }
    }
}
