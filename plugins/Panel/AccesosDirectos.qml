//  La franja de accesos directos del centro de control, reordenable.
//
//  No usa RowLayout sino posiciones calculadas, y es por el arrastre: un
//  Layout coloca a sus hijos él, así que mientras arrastras uno el Layout te
//  lo devuelve a su sitio y no se puede mover. Con `x` calculada y un
//  Behavior, el que arrastras sigue al ratón y los demás se apartan solos con
//  una animación — que además es lo que hace entender que se están
//  reordenando y no simplemente moviendo.
//
//  El clic y el arrastre comparten un solo MouseArea: si al soltar no hubo
//  movimiento real, era un clic y se abre. Con dos áreas separadas —una para
//  pulsar y otra para arrastrar— siempre gana una y la otra parece rota.

import QtQuick
import K4 as K4
import "../../core"
import "../../services"

Item {
    id: franja

    //  Qué hacer al abrir uno: lo pone el panel, que es quien sabe cerrarse.
    signal abrir(string id)

    readonly property int esp: 10
    readonly property int altura: 40

    //  Los que se pintan: los guardados que además existen y están
    //  encendidos. Esta lista no cambia mientras se arrastra: el orden nuevo
    //  se dibuja con ranuras y solo se guarda al soltar.
    readonly property var disponibles: {
        const apps = PluginManager.aplicaciones
        const salida = []
        const ids = Settings.accesosDirectos || []
        for (let i = 0; i < ids.length; ++i) {
            for (let j = 0; j < apps.length; ++j) {
                if (apps[j].id === ids[i] && apps[j].habilitado) {
                    salida.push(apps[j])
                    break
                }
            }
        }
        return salida
    }

    //  Durante el arrastre el MODELO NO SE TOCA.
    //
    //  Lo intenté al revés —reordenar la lista en cada movimiento— y el
    //  arrastre se moría a la primera: al cambiar el modelo, el Repeater
    //  destruye y recrea sus celdas, y la que se estaba arrastrando se
    //  llevaba consigo el agarre del ratón. Se soltaba sola y el clic acababa
    //  abriendo otra cosa.
    //
    //  Así que durante el arrastre solo hay dos números —de dónde salió y
    //  dónde va— y cada celda calcula qué RANURA le toca. Es puro dibujo. El
    //  modelo se reordena una sola vez, al soltar.
    property int arrastrando: -1
    property int destino: -1

    readonly property var lista: disponibles

    //  Uno más que los accesos: el botón que abre el cajón entero.
    readonly property int anchoCelda:
        lista.length > 0
            ? (width - esp * lista.length) / (lista.length + 1)
            : width

    function posicion(i) { return i * (anchoCelda + esp) }

    //  Qué ranura ocupa cada celda mientras se arrastra: la arrastrada va a
    //  la de destino y las que quedan en medio se corren un sitio, que es lo
    //  que hace ver que se está reordenando y no solo moviendo.
    function ranuraDe(i) {
        if (arrastrando < 0 || destino < 0 || arrastrando === destino)
            return i
        if (i === arrastrando)
            return destino
        if (arrastrando < destino && i > arrastrando && i <= destino)
            return i - 1
        if (arrastrando > destino && i >= destino && i < arrastrando)
            return i + 1
        return i
    }

    //  Y aquí sí: una sola vez, al soltar.
    //
    //  Recibe de dónde y a dónde en vez de leerlos de `arrastrando`, porque
    //  quien llama tiene que haberlos puesto ya a -1: si no, el modelo cambia
    //  con el arrastre todavía «vivo», las ranuras se calculan sobre la lista
    //  NUEVA con el desplazamiento VIEJO, y la franja queda con un hueco y una
    //  celda de menos. Se veía.
    function aplicar(de, a) {
        if (de < 0 || a < 0 || de === a)
            return
        const ids = disponibles.map(function (x) { return x.id })
        ids.splice(a, 0, ids.splice(de, 1)[0])
        //  Los guardados que ahora no se pintan —un plugin apagado— se
        //  conservan al final: apagar algo no debe borrar que lo tenías
        //  anclado.
        const resto = (Settings.accesosDirectos || []).filter(function (id) {
            return ids.indexOf(id) < 0
        })
        Settings.accesosDirectos = ids.concat(resto)
        Settings.guardar()
    }

    Repeater {
        model: franja.lista

        delegate: K4.Baldosa {
            id: celda
            required property var modelData
            required property int index

            //  Los visuales los lleva el MouseArea de abajo: la baldosa no
            //  escucha para no pelearse con el arrastre.
            pulsable: false
            activa: raton.containsMouse || franja.arrastrando === index

            width: franja.anchoCelda
            height: franja.altura
            y: 0
            radius: 12
            z: franja.arrastrando === index ? 2 : 1

            //  La x SIEMPRE es un enlace, nunca una asignación. Asignarla a
            //  mano rompe el enlace para siempre, y como la fila todavía no
            //  tiene ancho cuando se crean las celdas, todas se quedaban
            //  apiladas en el cero — se veía una sola.
            //
            //  Así que hay dos fuentes y manda la de arrastrar mientras dure:
            //  al soltar, `arrastrando` vuelve a -1, el enlace recupera su
            //  sitio y el Behavior lo lleva hasta él con una animación.
            property real desplazado: 0

            x: franja.arrastrando === index
                ? desplazado
                : franja.posicion(franja.ranuraDe(index))

            //  El que se arrastra NO anima —tiene que ir pegado al ratón—;
            //  los que se apartan, sí.
            Behavior on x {
                enabled: franja.arrastrando !== celda.index
                NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
            }

            Row {
                anchors.centerIn: parent
                spacing: 7

                K4.IconoPlugin {
                    imagen: celda.modelData.imagen
                    glifo: celda.modelData.glifo
                    tamano: 15
                    anchors.verticalCenter: parent.verticalCenter
                }

                IslandLabel {
                    text: celda.modelData.nombre
                    font.pixelSize: 11
                    font.weight: Font.Medium
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            MouseArea {
                id: raton
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor

                property real cogidoEn: 0
                property bool movido: false

                onPressed: function (ev) {
                    cogidoEn = ev.x
                    movido = false
                    celda.desplazado = celda.x
                    franja.arrastrando = celda.index
                    franja.destino = celda.index
                }

                onPositionChanged: function (ev) {
                    if (franja.arrastrando !== celda.index)
                        return
                    //  Un umbral corto: sin él, el temblor de la mano al
                    //  hacer clic ya cuenta como arrastre y el acceso no se
                    //  abre nunca.
                    if (!movido && Math.abs(ev.x - cogidoEn) < 6)
                        return
                    movido = true

                    celda.desplazado = Math.max(0,
                        Math.min(franja.width - celda.width,
                                 celda.desplazado + ev.x - cogidoEn))

                    const d = Math.round(
                        celda.desplazado / (franja.anchoCelda + franja.esp))
                    if (d >= 0 && d < franja.lista.length)
                        franja.destino = d
                }

                onReleased: {
                    //  Todo a mano ANTES de tocar nada: al reordenar, esta
                    //  misma celda se destruye y recrea, así que leerla
                    //  después es leer un cadáver.
                    const hubo = movido
                    const de = franja.arrastrando
                    const a = franja.destino
                    const cual = celda.modelData.id

                    franja.arrastrando = -1
                    franja.destino = -1

                    if (hubo)
                        franja.aplicar(de, a)
                    else
                        franja.abrir(cual)
                }
            }
        }
    }

    //  El cajón entero, siempre el último y quieto: no se reordena porque no
    //  es un acceso directo, es la salida a todos los demás.
    K4.Baldosa {
        x: franja.posicion(franja.lista.length)
        width: franja.anchoCelda
        height: franja.altura
        radius: 12

        Behavior on x {
            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
        }

        Row {
            anchors.centerIn: parent
            spacing: 7

            K4.Glifo {
                text: String.fromCodePoint(0xF02C1)     // md-grid
                color: Theme.muted
                font.pixelSize: 15
                anchors.verticalCenter: parent.verticalCenter
            }

            IslandLabel {
                text: Idioma.t("Todas")
                font.pixelSize: 11
                font.weight: Font.Medium
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        onPulsada: franja.abrir("apps")
    }
}
