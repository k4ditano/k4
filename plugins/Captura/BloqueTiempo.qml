//  Un bloque de la línea de tiempo, arrastrable y estirable.
//
//  Mientras dura el gesto se edita EN LOCAL, y el modelo se escribe al soltar.
//  No es una preferencia, es obligatorio: estos bloques son delegados de un
//  Repeater sobre un array normal, y escribir el modelo reasigna el array
//  entero —es la única forma de que QML emita el cambio—, lo que destruye y
//  recrea todos los delegados. Destruido el bloque, muerto el MouseArea que
//  tenía el agarre: el arrastre movía un píxel y se cortaba, porque el primer
//  evento ya mataba a quien escuchaba.
//
//  Con el estado local, el bloque que arrastras es siempre el mismo objeto; el
//  modelo se entera una vez, al final, y la recreación ocurre cuando ya nadie
//  tiene nada agarrado.

import QtQuick
import "../../core"

Rectangle {
    id: bloque

    property real t0: 0
    property real t1: 1
    property real total: 1
    property bool elegido: false
    property color tono: Theme.blue

    // El mínimo que puede durar. Por debajo de esto el bloque sería más
    // pequeño que sus propias asas y no habría forma de agarrarlo.
    readonly property real minimo: 0.4

    //  Si además se puede sacar de su fila y llevar a otra.
    //
    //  Solo tiene sentido donde las filas quieren decir algo apilado, o sea en
    //  las capas: mover un zoom «a otra fila» no significa nada, porque el zoom
    //  es uno solo. `pasoFila` es lo que mide una fila con su hueco, que el
    //  bloque no puede saber por sí mismo.
    property bool porFilas: false
    property real pasoFila: 29

    //  Los fotogramas clave de la capa, para pintarlos como rombos y poder
    //  moverlos y quitarlos sin salir de la línea de tiempo. Vacío en los
    //  bloques que no los tienen —clips, momentos— y no pinta nada.
    property var claves: []

    //  Cómo se pega el imán, si es que hay imán.
    //
    //  Una función `(t) -> t` que pone quien usa el bloque: `BloqueTiempo` no
    //  conoce al Editor —importa QtQuick y poco más— y no tiene por qué saber a
    //  qué se alinea nada. Sin ella el bloque se mueve libre, que es lo correcto
    //  donde no hay a qué pegarse.
    property var ajustar: null

    //  Los picos de la pista, si el bloque suena. `null` mientras se calculan.
    property var onda: null

    signal cambiado(real nuevoT0, real nuevoT1)
    signal cambiadoDeFila(int filas)
    signal soltado()
    //  Con `conControl` para que quien escuche pueda distinguir un clic normal
    //  —elige esto y suelta lo demás— de un Ctrl+clic, que suma a lo elegido.
    //  El bloque no sabe qué es una selección; solo cuenta cómo lo pulsaron.
    signal pulsado(bool conControl)
    signal claveMovida(int indice, real t)
    signal claveQuitada(int indice)

    // El estado del gesto en curso. Solo manda mientras `editando`.
    property bool editando: false
    property real vT0: 0
    property real vT1: 0
    property real vY: 0

    readonly property real eT0: editando ? vT0 : t0
    readonly property real eT1: editando ? vT1 : t1

    x: parent.width * (eT0 / Math.max(0.001, total))
    width: Math.max(4, parent.width * ((eT1 - eT0) / Math.max(0.001, total)))
    radius: 4
    color: elegido ? tono : Qt.rgba(tono.r, tono.g, tono.b, 0.35)

    //  Sale de su fila con `transform` y no con `y`: la `y` la pone la pista y
    //  escribirla a mano pelearía con ella. Y con `z` por encima, o al pasar por
    //  encima de la fila vecina se metería debajo y parecería que se ha soltado.
    transform: Translate { y: bloque.vY }
    z: bloque.vY !== 0 ? 20 : 0

    Behavior on color { ColorAnimation { duration: 140 } }

    //  La onda, dentro del bloque.
    //
    //  En un `Canvas` y no con doscientos rectángulos: un Repeater de barras por
    //  cada bloque de audio son cientos de elementos vivos que se recrean con
    //  cada cambio del modelo, y esto se pinta una vez y se olvida.
    //
    //  NORMALIZADA por su propio pico, con un suelo. Una grabación de pantalla
    //  con el micro lejos anda por los −24 dB, o sea 0,06 de amplitud: dibujada
    //  a escala real es una raya plana y no informa de nada, que es justo lo que
    //  se venía a arreglar. El suelo evita que el silencio digital se convierta
    //  en ruido gigante al dividir por casi cero.
    //
    //  Y en la mitad de abajo, espejada desde el centro, como cualquier editor.
    Canvas {
        id: lienzoOnda
        anchors.fill: parent
        anchors.margins: 2
        visible: bloque.onda !== null && bloque.onda.length > 0
        opacity: 0.55
        antialiasing: false

        readonly property color tono: Theme.ink

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            const picos = bloque.onda
            if (!picos || picos.length === 0 || width <= 0)
                return

            let tope = 0
            for (let i = 0; i < picos.length; ++i)
                tope = Math.max(tope, picos[i])
            //  Por debajo de esto es silencio de verdad y se deja plano.
            if (tope < 0.002)
                return
            const escala = Math.max(tope, 0.02)

            const medio = height / 2
            ctx.fillStyle = tono
            //  Una barra por píxel, no una por muestra: con el bloque estrecho
            //  hay más picos que píxeles y dibujarlos todos es pintar el mismo
            //  sitio cien veces.
            const barras = Math.max(1, Math.floor(width))
            for (let x = 0; x < barras; ++x) {
                const desde = Math.floor(x * picos.length / barras)
                const hasta = Math.max(desde + 1,
                    Math.floor((x + 1) * picos.length / barras))
                let p = 0
                for (let k = desde; k < hasta && k < picos.length; ++k)
                    p = Math.max(p, picos[k])
                const h = Math.min(1, p / escala) * medio
                ctx.fillRect(x, medio - h, 1, h * 2)
            }
        }

        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        Connections {
            target: bloque
            function onOndaChanged() { lienzoOnda.requestPaint() }
        }
    }

    //  Cómo se llama, escrito encima.
    //
    //  Separar el audio de un trozo deja DOS bloques amarillos idénticos, y
    //  saber cuál era el micro obligaba a pinchar uno y mirar la ficha. Puestos
    //  a poner un nombre, vale para cualquier bloque que traiga uno.
    //
    //  Se esconde si no cabe en vez de recortarse a tres letras: «Mic…» y
    //  «Sis…» a 3 px de ancho no informan de nada y ensucian la fila. Y no
    //  intercepta el ratón —el bloque entero se arrastra y se estira—, así que
    //  `MouseArea` ninguno.
    property string etiqueta: ""

    Text {
        anchors.left: parent.left
        anchors.leftMargin: 6
        anchors.right: parent.right
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        visible: bloque.etiqueta.length > 0 && bloque.width > implicitWidth + 12
        //  El nombre de la capa, y el de una capa de audio es el de su FICHERO.
        textFormat: Text.PlainText
        text: bloque.etiqueta
        color: bloque.elegido ? Theme.islandBg : Theme.ink
        font.family: Theme.uiFont
        font.pixelSize: 9
        font.weight: Font.DemiBold
        elide: Text.ElideRight
    }

    function px2t(px) { return px / Math.max(1, parent.width) * total }

    //  El instante que hay bajo el ratón, en tiempo de la PISTA.
    //
    //  Aquí estaba el fallo que hacía que arrastrar moviera un píxel y parara:
    //  el `MouseArea` vive dentro del bloque, así que su `ev.x` va en
    //  coordenadas del bloque. Y como el bloque se recoloca en cuanto cambia
    //  `t0`, el puntero se quedaba siempre en el mismo punto relativo y el
    //  desplazamiento se anulaba a sí mismo.
    //
    //  Sumando `x` —lo que el bloque lleva recorrido dentro de la pista— sale
    //  la posición absoluta del puntero, que es la única que no se mueve bajo
    //  los pies.
    function enPista(dentro) { return px2t(x + dentro) }

    function encaja(v, min, max) { return Math.max(min, Math.min(max, v)) }

    // ── mover ─────────────────────────────────────────────────────
    MouseArea {
        id: cuerpo

        //  Sin `anchors.fill`, con ancho y alto: un elemento anclado no se
        //  puede arrastrar. Aquí no arrastramos el elemento, pero la costumbre
        //  se mantiene por si algún día se hace.
        width: bloque.width
        height: bloque.height

        //  La línea de tiempo puede acabar dentro de algo desplazable, y
        //  entonces el ancestro se queda el gesto en cuanto detecta
        //  movimiento. Con esto no.
        preventStealing: true
        drag.filterChildren: true

        cursorShape: Qt.SizeAllCursor
        hoverEnabled: true

        property real anclaT: 0
        property real t0Ini: 0
        property real duracion: 0
        property real yIni: 0
        property bool arrastrando: false

        //  En coordenadas de la VENTANA para el eje vertical, por lo mismo que
        //  `enPista` para el horizontal: el bloque se despega con el propio
        //  arrastre y en sus coordenadas el puntero se queda quieto.
        function fuera(ev) { return mapToItem(null, 0, ev.y).y }

        onPressed: function (ev) {
            bloque.pulsado((ev.modifiers & Qt.ControlModifier) !== 0)
            anclaT = bloque.enPista(ev.x)
            t0Ini = bloque.t0
            duracion = bloque.t1 - bloque.t0
            yIni = fuera(ev)
            bloque.vT0 = bloque.t0
            bloque.vT1 = bloque.t1
            bloque.vY = 0
            bloque.editando = true
            arrastrando = false
        }

        onPositionChanged: function (ev) {
            if (!pressed)
                return
            arrastrando = true
            // El bloque se mueve entero: la duración no cambia al desplazarlo.
            let nuevo = t0Ini + (bloque.enPista(ev.x) - anclaT)
            nuevo = bloque.encaja(nuevo, 0, bloque.total - duracion)
            //  El imán, MIENTRAS arrastras y no al soltar.
            //
            //  Aquí estaba el fallo que dejaba el imán a medias: se aplicaba
            //  solo al escribir el modelo, o sea al final. Durante el gesto el
            //  bloque iba libre y en el último instante pegaba un salto a su
            //  sitio, así que no veías dónde ibas a caer ni por qué acabaste
            //  ahí. Ahora se pega a la vista y la guía sale mientras te mueves,
            //  que es de lo que va un imán.
            //
            //  Se prueban los DOS bordes y gana el que más cerca esté: encadenar
            //  un bloque detrás de otro es alinear el final, no el principio, y
            //  con solo el principio había que calcular la resta a ojo.
            if (bloque.ajustar) {
                const a = bloque.ajustar(nuevo)
                const b = bloque.ajustar(nuevo + duracion) - duracion
                const da = Math.abs(a - nuevo)
                const db = Math.abs(b - nuevo)
                nuevo = bloque.encaja(da <= db ? a : b, 0,
                                      bloque.total - duracion)
            }
            bloque.vT0 = nuevo
            bloque.vT1 = nuevo + duracion
            if (bloque.porFilas)
                bloque.vY = fuera(ev) - yIni
        }

        onReleased: {
            //  Los dos ejes a la vez, y a propósito: en un editor mover algo de
            //  fila y de instante en el mismo gesto es lo normal, y obligar a
            //  hacerlo en dos pasos se nota.
            //
            //  Primero el modelo y luego soltar el estado local: así el binding
            //  ya encuentra el valor nuevo y el bloque no da un salto atrás.
            if (arrastrando) {
                const filas = bloque.porFilas
                    ? Math.round(bloque.vY / Math.max(1, bloque.pasoFila)) : 0
                bloque.cambiado(bloque.vT0, bloque.vT1)
                if (filas !== 0)
                    bloque.cambiadoDeFila(filas)
                bloque.soltado()
            }
            bloque.vY = 0
            bloque.editando = false
        }

        //  Sin `onWheel` a propósito.
        //
        //  Aquí la rueda cambiaba el nivel del zoom. Dejó de tener sentido en
        //  cuanto la línea de tiempo se pudo recorrer: la rueda es para moverse,
        //  y un bloque que se la quedara haría que la línea se atascara cada vez
        //  que el puntero pasara por encima de algo. El nivel se cambia con la
        //  rueda sobre el vídeo, que además es donde se ve el efecto.
    }

    // ── estirar ───────────────────────────────────────────────────
    //
    //  Diez píxeles de asa, no cuatro. Acertar en una franja de cuatro píxeles
    //  arrastrando es pedir una puntería que nadie tiene por qué tener; es la
    //  misma lección del crisol de la mazmorra.
    Component {
        id: asa

        MouseArea {
            property bool esIzquierda: true

            width: 10
            height: bloque.height
            x: esIzquierda ? -3 : bloque.width - 7
            preventStealing: true
            cursorShape: Qt.SizeHorCursor
            hoverEnabled: true

            onPressed: function (ev) {
                bloque.pulsado((ev.modifiers & Qt.ControlModifier) !== 0)
                bloque.vT0 = bloque.t0
                bloque.vT1 = bloque.t1
                bloque.editando = true
            }

            onPositionChanged: function (ev) {
                if (!pressed)
                    return
                // Lo mismo que el cuerpo: en tiempo de la pista, no del bloque.
                const t = bloque.encaja(bloque.enPista(x + ev.x), 0, bloque.total)
                if (esIzquierda)
                    bloque.vT0 = Math.min(t, bloque.vT1 - bloque.minimo)
                else
                    bloque.vT1 = Math.max(t, bloque.vT0 + bloque.minimo)
            }

            onReleased: {
                bloque.cambiado(bloque.vT0, bloque.vT1)
                bloque.soltado()
                bloque.editando = false
            }

            // Marca de agarre, solo cuando el bloque está elegido: en los demás
            // sería ruido.
            Rectangle {
                visible: bloque.elegido
                anchors.centerIn: parent
                width: 2
                height: parent.height * 0.5
                radius: 1
                color: Theme.ink
                opacity: parent.containsMouse ? 1 : 0.55
            }
        }
    }

    Loader { sourceComponent: asa; onLoaded: item.esIzquierda = true }
    Loader { sourceComponent: asa; onLoaded: item.esIzquierda = false }

    // ── los fotogramas clave ──────────────────────────────────────
    //
    //  Rombos DENTRO del bloque, en su instante. Solo en el bloque elegido:
    //  en los demás serían ruido. Se arrastran en horizontal —el gesto se
    //  edita en local y el modelo se escribe al soltar, como el propio
    //  bloque y por el mismo motivo— y el clic derecho los quita.
    Repeater {
        model: bloque.elegido ? bloque.claves : []

        delegate: Item {
            id: clave
            required property var modelData
            required property int index

            property bool moviendo: false
            property real vT: 0

            readonly property real t: moviendo ? vT
                : (Number(modelData.t) || 0)

            width: 14
            height: bloque.height
            x: bloque.width
               * ((t - bloque.eT0) / Math.max(0.001, bloque.eT1 - bloque.eT0))
               - width / 2
            z: 10

            Rectangle {
                anchors.centerIn: parent
                width: 7
                height: 7
                rotation: 45
                radius: 1
                color: claveRaton.containsMouse || clave.moviendo
                    ? Theme.ink : Qt.rgba(1, 1, 1, 0.85)
                border.width: 1
                border.color: Qt.rgba(0, 0, 0, 0.45)
            }

            MouseArea {
                id: claveRaton
                anchors.fill: parent
                hoverEnabled: true
                preventStealing: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.SizeHorCursor

                onPressed: function (ev) {
                    if (ev.button === Qt.RightButton) {
                        bloque.claveQuitada(clave.index)
                        return
                    }
                    clave.vT = clave.t
                    clave.moviendo = true
                }

                onPositionChanged: function (ev) {
                    if (!pressed || !clave.moviendo)
                        return
                    //  En tiempo de la pista, sumando lo que el rombo lleva
                    //  recorrido: la trampa de coordenadas de siempre.
                    const enPista = bloque.px2t(bloque.x + clave.x + ev.x)
                    clave.vT = bloque.encaja(enPista, bloque.eT0, bloque.eT1)
                }

                onReleased: function (ev) {
                    if (!clave.moviendo)
                        return
                    clave.moviendo = false
                    bloque.claveMovida(clave.index, clave.vT)
                }
            }
        }
    }
}
