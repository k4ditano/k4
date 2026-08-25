//  Una pantalla de mentira que enseña cómo va a quedar.
//
//  Las tres opciones de arriba —dónde vive, cómo se alinea y cómo ocupa el
//  sitio— se explican mal con palabras. «Reservar sitio» y «Encima» suenan
//  parecido y hacen cosas muy distintas con tus ventanas, y la única forma de
//  saber cuál querías era aplicarlo, mirar el escritorio y deshacerlo.
//
//  Aquí se ve antes: la barra donde va a estar, con su alineación, y una
//  ventana de mentira que se aparta o no según lo que elijas. Se actualiza al
//  tocar cualquiera de las tres.
//
//  Dibuja también el dock si lo tienes puesto, porque comparte la pantalla con
//  la barra y una previsualización que lo omitiera estaría mintiendo por
//  omisión. Sus opciones no están aquí —viven en Plugins, dentro de «Modo
//  dual»— y por eso lo dice abajo.

import QtQuick
import QtQuick.Layouts
import K4 as K4
import "../../core"
import "../../services"

ColumnLayout {
    id: previo

    spacing: 8

    //  Lo que se está mirando. Sin valor guardado se usa lo mismo que usa la
    //  barra de fábrica, o la previsualización mentiría en un arranque limpio.
    readonly property string donde: {
        const v = Settings.valor("posicionBarra")
        return v === "abajo" ? "abajo" : "arriba"
    }

    readonly property int alineacion: {
        const v = parseInt(Settings.valor("alineacionBarra"), 10)
        return isNaN(v) ? 50 : v
    }

    readonly property string sitio: {
        const v = Settings.valor("reservaIsla")
        return typeof v === "string" && v.length > 0 ? v : "reserva"
    }

    //  ¿Aparta las ventanas? «Reserva» siempre; «completa» sí salvo cuando algo
    //  está a pantalla completa, y eso en un dibujo quieto no se distingue, así
    //  que se dibuja como que sí y se cuenta debajo.
    readonly property bool aparta: previo.sitio === "reserva"
                                   || previo.sitio === "completa"
    readonly property bool escondida: previo.sitio === "escondida"

    //  El dock, si está. Sus ajustes son del plugin `dual`, así que se leen por
    //  su id con prefijo: los de fuera viven en otro cajón.
    //  El alto del monitor donde estás, para que la escala del croquis sea la
    //  tuya y no una inventada.
    readonly property real altoPantalla: Island.altoPantalla

    // ── tu fondo de escritorio, de verdad ─────────────────────────
    //
    //  El croquis con un gris inventado enseña la forma pero no cómo QUEDA.
    //  Con el fondo real deja de ser un diagrama.
    //
    //  Cuál es lo sabe el plugin de temas, que lo guarda en su estado; y si es
    //  un vídeo, el fotograma ya está cacheado en `~/.cache/k4/fondos/` con el
    //  md5 de la ruta por nombre —lo escribe ese mismo plugin al preparar el
    //  fondo—. Todo eso se resuelve en UNA orden de shell en vez de en un
    //  servicio nuevo: un singleton nuevo en `services/` obliga a reiniciar la
    //  barra entera, y esto no lo merece.
    property string poster: ""

    //  Los huecos de Hyprland. La ventana de mentira los respeta, y no es un
    //  adorno: tu escritorio tiene huecos, así que una ventana que llegara a
    //  los bordes estaría enseñando algo que no pasa — y de paso taparía el
    //  fondo entero, que es justo lo que se ha venido a ver.
    property int huecos: 8

    K4.Process {
        id: buscaFondo
        running: true
        command: ["sh", "-c",
              "e=\"$HOME/.local/state/k4/hyprtheme.json\"\n"
            + "[ -f \"$e\" ] || exit 0\n"
            + "d=$(python3 -c \"import json,sys\n"
            + "d=json.load(open(sys.argv[1]))\n"
            + "f=d.get('fondos') or {}\n"
            + "print(next(iter(f.values()),'') or d.get('wallpaper',''))\n"
            + "print(d.get('gapsOut',8))\" \"$e\") || exit 0\n"
            + "p=$(printf '%s' \"$d\" | head -1)\n"
            + "g=$(printf '%s' \"$d\" | tail -1)\n"
            + "[ -n \"$p\" ] || exit 0\n"
            + "case \"$p\" in\n"
            + "  *.png|*.jpg|*.jpeg|*.webp|*.PNG|*.JPG) f=\"$p\" ;;\n"
            + "  *) f=\"$HOME/.cache/k4/fondos/$(printf %s \"$p\" | md5sum | cut -d' ' -f1).png\" ;;\n"
            + "esac\n"
            + "printf '%s|%s' \"$f\" \"$g\"\n"]

        onSalida: function (texto) {
            //  «ruta|huecos», que es una orden en vez de dos.
            const partes = String(texto).trim().split("|")
            const r = String(partes[0] || "").trim()
            if (r.length > 0)
                previo.poster = "file://" + r
            const g = parseInt(partes[1], 10)
            if (!isNaN(g))
                previo.huecos = g
        }
    }

    readonly property bool hayDock: !!Settings.valor("plugin_dual")
    readonly property bool dockAparta: {
        const v = Settings.valor("ext_dual_reservaDock")
        return v === "reserva" || v === "completa"
    }

    // ── la pantalla ───────────────────────────────────────────────
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: Math.round(width * 9 / 16)
        Layout.maximumHeight: 360
        radius: 10
        color: "#0d1117"
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.07)
        clip: true

        //  Un escritorio de mentira, y CLARO a propósito.
        //
        //  La island es negra —`Theme.islandBg` es #000000 con el tinte del
        //  tema— así que sobre un fondo oscuro no se vería: en tu pantalla se
        //  ve porque está encima del fondo de escritorio. Un croquis en el que
        //  la barra es invisible no enseña nada, así que aquí el suelo es un
        //  gris azulado que hace de fondo de pantalla.
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0; color: "#4a5a6e" }
                GradientStop { position: 0.55; color: "#33404f" }
                GradientStop { position: 1; color: "#232c37" }
            }
        }

        //  Y encima, tu fondo, si se ha podido resolver. El degradado de arriba
        //  se queda debajo como red: si el fichero no está —fondo recién
        //  cambiado, caché aún sin hacer— esto no carga y no se ve un hueco
        //  negro, se ve el degradado.
        Image {
            anchors.fill: parent
            visible: status === Image.Ready
            source: previo.poster
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            //  Se pinta pequeño; pedirle a Qt que lo baje al vuelo ahorra
            //  tener una textura de 1920 de ancho para ocupar 700.
            sourceSize.width: 900
        }

        //  La ventana de mentira. Es la que enseña de verdad la diferencia
        //  entre reservar sitio y ponerse encima: aquí se aparta o no.
        Rectangle {
            id: ventanita

            //  Lo que la barra le quita, a la misma escala que todo: si
            //  reserva, son sus 34 px de verdad llevados al croquis.
            readonly property int hueco: previo.aparta && !previo.escondida
                ? Math.round(Theme.baseHeight * barrita.escala) : 0

            readonly property real margen: Math.max(1, previo.huecos * barrita.escala)

            x: margen
            width: parent.width - margen * 2
            y: (previo.donde === "arriba" ? hueco : 0) + margen
            height: parent.height - hueco - margen * 2
            radius: Math.max(2, 8 * barrita.escala)
            color: Qt.rgba(0.09, 0.11, 0.14, 0.88)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.10)

            Behavior on y { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

            IslandLabel {
                anchors.centerIn: parent
                text: Idioma.t("una ventana")
                color: Qt.rgba(1, 1, 1, 0.30)
                font.pixelSize: 10
            }
        }

        //  La barra. Y es LA barra: la misma `SiluetaIsla` que dibuja la de
        //  verdad, con su ala y su radio, no un rectángulo redondeado que se
        //  le parezca. Lo único que cambia es la escala.
        //
        //  Escondida se dibuja como el filo que asoma, que es exactamente lo
        //  que se ve en esa opción hasta que acercas el ratón al borde.
        Item {
            id: barrita

            //  A escala de verdad: lo que mide la island ahora mismo, llevado
            //  a lo que mide este croquis respecto a la pantalla. Así la
            //  proporción no es una estimación, es la de tu monitor.
            readonly property real escala: parent.height / previo.altoPantalla
            readonly property real anchoReal: Math.max(160, Island.rect.ancho || 380)

            width: Math.max(24, anchoReal * escala)
            height: previo.escondida ? 3 : Math.max(4, Theme.baseHeight * escala)

            x: Math.round((parent.width - width) * previo.alineacion / 100)
            y: previo.donde === "arriba"
                ? 0 : parent.height - height

            Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            Behavior on height { NumberAnimation { duration: 200 } }

            SiluetaIsla {
                anchors.fill: parent
                visible: !previo.escondida
                //  El ala y el radio, a la misma escala que todo lo demás: si
                //  se dejaran en su tamaño de siempre, a este tamaño el
                //  trazado se cruza y sale un champiñón.
                ala: Math.max(1, Theme.wing * barrita.escala)
                cuerpoRadio: Math.max(1, 20 * barrita.escala)
                relleno: Theme.islandBg
                reflejada: previo.donde === "abajo"
            }

            //  El filo, para la opción escondida.
            Rectangle {
                anchors.fill: parent
                visible: previo.escondida
                radius: height / 2
                color: Qt.rgba(1, 1, 1, 0.30)
            }
        }

        //  Y el dock, al lado contrario de la barra: es donde vive.
        //
        //  A su alto de verdad —el mismo que la island, `Theme.baseHeight`— y
        //  con su forma. Los iconos son puntos: el dock real son mil quinientas
        //  líneas atadas a tus aplicaciones abiertas y a sus ventanas, y montar
        //  un segundo dock funcionando para mirarlo de reojo no sale a cuenta.
        //  Lo que aquí importa es cuánto ocupa y dónde se pone.
        Rectangle {
            id: muellecito

            visible: previo.hayDock
            height: Math.max(4, Theme.baseHeight * barrita.escala)
            width: Math.max(40, height * 7)
            radius: height / 2.6
            color: Qt.rgba(0, 0, 0, 0.55)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.12)

            x: Math.round((parent.width - width) / 2)
            y: previo.donde === "arriba"
                ? parent.height - height - Math.round(4 * barrita.escala * 4)
                : Math.round(4 * barrita.escala * 4)

            Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

            Row {
                anchors.centerIn: parent
                spacing: Math.max(2, muellecito.height * 0.22)

                Repeater {
                    model: 5
                    delegate: Rectangle {
                        width: Math.max(2, muellecito.height * 0.5)
                        height: width
                        radius: width / 4
                        color: Qt.rgba(1, 1, 1, 0.55)
                    }
                }
            }
        }
    }

    // ── lo que el dibujo no puede decir ───────────────────────────
    IslandLabel {
        Layout.fillWidth: true
        text: {
            if (previo.sitio === "reserva")
                return Idioma.t("Las ventanas empiezan donde acaba la barra.")
            if (previo.sitio === "completa")
                return Idioma.t("Aparta las ventanas, salvo cuando una está a pantalla completa: entonces se quita de en medio.")
            if (previo.sitio === "encima")
                return Idioma.t("Las ventanas ocupan la pantalla entera y la barra flota encima.")
            return Idioma.t("No se ve hasta que llevas el ratón al borde.")
        }
        color: Theme.dim
        font.pixelSize: 10
        wrapMode: Text.WordWrap
    }

    IslandLabel {
        Layout.fillWidth: true
        visible: previo.hayDock
        text: Idioma.t("El dock sale en el croquis, pero sus ajustes están en Plugins, dentro de «Modo dual».")
        color: Theme.dim
        font.pixelSize: 10
        wrapMode: Text.WordWrap
    }
}
