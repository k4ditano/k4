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
        return (v === "abajo" || v === "izquierda" || v === "derecha")
            ? v : "arriba"
    }
    readonly property bool deCanto: donde === "izquierda" || donde === "derecha"

    readonly property int alineacion: {
        if (previo.alineacionArrastre >= 0)
            return previo.alineacionArrastre
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
    //  Lo sabe `Fondos`, el servicio: cuál está puesto, dónde vive su fotograma
    //  si es un vídeo, y cuántos huecos tiene Hyprland. Antes esto era una orden
    //  de shell con `md5sum` porque esa información vivía dentro del plugin del
    //  tema y no había forma de preguntársela. Ahora es una property: cero
    //  procesos, y se entera sola cuando cambias de fondo.
    readonly property string poster: {
        const r = Fondos.actualDe("")
        if (r.length === 0)
            return ""
        return "file://" + (Fondos.esQuieto(r) ? r : Fondos.posterDe(r))
    }

    //  Los huecos de Hyprland. La ventana de mentira los respeta, y no es un
    //  adorno: tu escritorio tiene huecos, así que una ventana que llegara a los
    //  bordes estaría enseñando algo que no pasa — y de paso taparía el fondo
    //  entero, que es justo lo que se ha venido a ver.
    readonly property int huecos: Fondos.huecos

    readonly property bool hayDock: !!Settings.valor("plugin_dual")
    readonly property bool dockAparta: {
        const v = Settings.valor("ext_dual_reservaDock")
        return v === "reserva" || v === "completa"
    }

    //  ── y se puede señalar, no solo mirar ────────────────────────
    //
    //  La alineación era tres botones —izquierda, centro, derecha; quince,
    //  cincuenta, ochenta y cinco— y un cuarto, un tercio o el filo mismo no
    //  eran ninguno de los tres. Una colocación es un PUNTO, y los puntos se
    //  eligen señalando: se arrastra sobre el croquis y la barra va detrás.
    //
    //  Mientras se arrastra manda este valor y no el guardado, y el guardado
    //  no se toca hasta soltar: `Settings.poner` escribe el fichero, y hacerlo
    //  en cada píxel del recorrido serían cien escrituras para un gesto. La
    //  barra de verdad llega al soltar, con su muelle de siempre.
    property int alineacionArrastre: -1

    //  Y el dock tiene la suya, que es OTRA: son dos sitios distintos de la
    //  pantalla y no tienen por qué compartir gusto. Vive en el plugin `dual`,
    //  así que se lee y se escribe con el prefijo de los de fuera.
    readonly property int alineacionDock: {
        if (previo.dockArrastre >= 0)
            return previo.dockArrastre
        const v = parseInt(Settings.valor("ext_dual_alineacionDock"), 10)
        return isNaN(v) ? 50 : v
    }
    property int dockArrastre: -1

    //  Qué se está arrastrando: se decide al APRETAR, por la mitad de la
    //  pantalla en la que se apriete. La barra vive en su borde y el dock en el
    //  contrario, así que coges lo que estás señalando y no hace falta apuntar
    //  a una tira de cuatro píxeles.
    property string cogido: ""

    //  Con imán en los tres de antes. Sin él, clavar el centro exacto pide un
    //  pulso que nadie tiene, y el centro es lo que quiere casi todo el mundo.
    function conIman(v) {
        const puntos = [15, 50, 85]
        for (let i = 0; i < puntos.length; ++i)
            if (Math.abs(v - puntos[i]) <= 3)
                return puntos[i]
        return v
    }

    // ── la pantalla ───────────────────────────────────────────────
    Rectangle {
        id: pantalla
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

            //  Se aparta por el borde en el que esté la barra: de canto, el
            //  hueco se lo quita al ancho y no al alto.
            x: margen + (previo.donde === "izquierda" ? hueco : 0)
            width: parent.width - margen * 2
                   - (previo.deCanto ? hueco : 0)
            y: margen + (previo.donde === "arriba" ? hueco : 0)
            height: parent.height - margen * 2
                    - (previo.deCanto ? 0 : hueco)
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

            //  De canto se cambian los papeles, igual que en la barra de
            //  verdad: lo que mide la island a lo largo pasa al alto.
            readonly property real largo: Math.max(24, anchoReal * escala)
            readonly property real hondo: previo.escondida ? 3
                : Math.max(4, Theme.baseHeight * escala)

            width: previo.deCanto ? hondo : largo
            height: previo.deCanto ? largo : hondo

            x: previo.deCanto
                ? (previo.donde === "derecha" ? parent.width - width : 0)
                : Math.round((parent.width - width) * previo.alineacion / 100)
            y: previo.deCanto
                ? Math.round((parent.height - height) * previo.alineacion / 100)
                : (previo.donde === "arriba" ? 0 : parent.height - height)

            //  Sin animación mientras se arrastra: la barra tiene que ir
            //  pegada al dedo. Con los 220 ms puestos va a remolque y parece
            //  que el croquis no te hace caso.
            Behavior on x {
                enabled: previo.alineacionArrastre < 0
                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
            }
            Behavior on width { NumberAnimation { duration: 200 } }
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
                lado: previo.donde
            }

            //  El filo, para la opción escondida.
            Rectangle {
                anchors.fill: parent
                visible: previo.escondida
                radius: height / 2
                color: Qt.rgba(1, 1, 1, 0.30)
            }
        }

        //  Quien recoge el gesto. Va DESPUÉS de la barra a propósito, para
        //  quedar por encima de ella: si no, arrastrar empezando justo sobre
        //  la barra —que es lo que hace todo el mundo— no cogería el ratón.
        //
        //  Se apunta al CENTRO de la barra, no a su borde izquierdo: se
        //  arrastra la barra, y una barra que se coloca por su esquina se
        //  siente descolgada de la mano.
        MouseArea {
            id: gesto
            anchors.fill: parent
            cursorShape: Qt.SizeHorCursor
            preventStealing: true

            //  Un porcentaje a partir de una x, para algo de ancho `w`: el
            //  centro de la pieza sigue al puntero, que es como se coge una
            //  cosa con la mano.
            //  De canto se arrastra por el otro eje: la barra corre a lo
            //  largo de SU borde, así que lo que manda es la `y`.
            function fraccion(v, medida) {
                const libre = (previo.deCanto ? pantalla.height : pantalla.width) - medida
                if (libre <= 0)
                    return -1
                return previo.conIman(
                    Math.round(Math.max(0, Math.min(1, (v - medida / 2) / libre)) * 100))
            }

            function colocar(x, y) {
                if (previo.cogido === "dock") {
                    //  El dock vive abajo pase lo que pase, así que su
                    //  arrastre es siempre horizontal.
                    const f = fraccion(x, muellecito.width)
                    if (f >= 0)
                        previo.dockArrastre = f
                } else {
                    const v = previo.deCanto ? y : x
                    const m = previo.deCanto ? barrita.height : barrita.width
                    const f = fraccion(v, m)
                    if (f >= 0)
                        previo.alineacionArrastre = f
                }
            }

            //  Quién se coge: la barra si aprietas en su mitad, el dock si
            //  aprietas en la contraria y hay dock. Sin dock siempre la barra,
            //  que si no media pantalla no haría nada.
            //
            //  Con la barra de canto no comparten eje —ella en un lateral, el
            //  dock abajo— así que lo que decide es la franja de abajo.
            function quienEn(y) {
                if (!previo.hayDock)
                    return "barra"
                if (previo.deCanto)
                    return y > pantalla.height * 0.75 ? "dock" : "barra"
                const arribaBarra = previo.donde === "arriba"
                const enMitadDeArriba = y < pantalla.height / 2
                return enMitadDeArriba === arribaBarra ? "barra" : "dock"
            }

            function soltar() {
                if (previo.alineacionArrastre >= 0)
                    Settings.poner("alineacionBarra", previo.alineacionArrastre)
                if (previo.dockArrastre >= 0)
                    Settings.poner("ext_dual_alineacionDock", previo.dockArrastre)
                previo.alineacionArrastre = -1
                previo.dockArrastre = -1
                previo.cogido = ""
            }

            onPressed: function (ev) {
                previo.cogido = quienEn(ev.y)
                colocar(ev.x, ev.y)
            }
            onPositionChanged: function (ev) { if (pressed) colocar(ev.x, ev.y) }
            onReleased: soltar()
            //  Un gesto que se va de la ventana sin soltar no deja el croquis
            //  mintiendo: se guarda igual que si hubiera soltado dentro.
            onCanceled: soltar()
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

            //  Por su alineación, la misma cuenta que la barra.
            x: Math.round((parent.width - width) * previo.alineacionDock / 100)
            //  El dock vive SIEMPRE en el borde de abajo: eso es el modo dual.
            //  La regla de «al lado contrario de la barra» solo tenía sentido
            //  cuando los bordes eran dos, y con la barra de canto ponía el
            //  dock arriba, donde no está.
            y: previo.donde === "abajo"
                ? Math.round(4 * barrita.escala * 4)
                : parent.height - height - Math.round(4 * barrita.escala * 4)

            Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            //  Pegado al dedo mientras se arrastra, igual que la barra.
            Behavior on x {
                enabled: previo.dockArrastre < 0
                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
            }

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
        text: Idioma.t("El dock también se arrastra aquí; sus demás ajustes están en Plugins, dentro de «Modo dual».")
        color: Theme.dim
        font.pixelSize: 10
        wrapMode: Text.WordWrap
    }
}
