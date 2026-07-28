//  La pelea: el grupo contra la oleada, y la tienda de la partida.

import QtQuick
import QtQuick.Layouts
import "../../core"
import "../../services"

ColumnLayout {
    id: panel

    property var plugin: null

    // anuncio del megajefe
    property string megaNombre: ""
    property int megaFase: -1
    property real anuncioOpacidad: 0
    property real anuncioEscala: 1
    property real faseOpacidad: 0

    SequentialAnimation {
        id: anuncio

        ParallelAnimation {
            NumberAnimation {
                target: panel; property: "anuncioOpacidad"
                from: 0; to: 1; duration: 220
            }
            NumberAnimation {
                target: panel; property: "anuncioEscala"
                from: 1.8; to: 1; duration: 420; easing.type: Easing.OutBack
            }
        }
        PauseAnimation { duration: 1500 }
        NumberAnimation {
            target: panel; property: "anuncioOpacidad"
            to: 0; duration: 400
        }
    }

    SequentialAnimation {
        id: fogonazo
        NumberAnimation {
            target: panel; property: "faseOpacidad"
            from: 0; to: 0.55; duration: 90
        }
        NumberAnimation {
            target: panel; property: "faseOpacidad"
            to: 0; duration: 380
        }
    }

    spacing: 8

    // desplazamiento y opacidad de los enemigos al aparecer
    property real entradaX: 0
    property real entradaOpacidad: 1

    ParallelAnimation {
        id: entrada
        NumberAnimation {
            target: panel; property: "entradaX"
            from: 90; to: 0; duration: 900; easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: panel; property: "entradaOpacidad"
            from: 0; to: 1; duration: 700
        }
    }

    // ── reacciones a la simulación ────────────────────────────────
    Connections {
        target: Game

        function onImpacto(indice, daño) {
            const celda = filaEnemigos.itemAt(indice)
            if (celda) celda.golpear(Game.cifra(daño))
        }

        function onHeroeHerido(indice, daño) {
            const celda = filaHeroes.itemAt(indice)
            if (celda) celda.golpear("-" + Game.cifra(daño))
        }

        function onCurado(indice, cantidad) {
            const celda = filaHeroes.itemAt(indice)
            if (celda) celda.curar("+" + Game.cifra(cantidad))
        }

        function onHabilidadLanzada(indice) {
            const celda = filaHeroes.itemAt(indice)
            if (celda) celda.destellar()
        }

        function onGolpea(heroe, enemigo) { panel.dibujarGolpe(heroe, enemigo) }

        function onEfectoHabilidad(heroe, efecto) { panel.dibujarHabilidad(heroe, efecto) }

        function onHabilidadEnemiga(indice, forma, nombre) {
            panel.dibujarEnemiga(indice, forma, nombre)
        }

        function onRasgoActuo(enemigo, heroe, rasgo) {
            panel.dibujarRasgo(enemigo, heroe, rasgo)
        }

        function onMegaEntra(nombre) {
            panel.megaNombre = nombre
            panel.megaFase = -1
            anuncio.restart()
        }

        function onMegaFase(fase) {
            panel.megaFase = fase
            fogonazo.restart()
        }

        function onCrisolSoltado() {
            panel.megaNombre = Idioma.t("¡Ha soltado la mejora del crisol!")
            panel.megaFase = -2
            anuncio.restart()
        }

        function onOleadaSuperada(numero) {
            escenario.caminar()
            entrada.restart()
        }
    }

    // Un efecto por golpe, creado y destruido al vuelo. Con tres héroes
    // pegando una vez por segundo son tres objetos por segundo: no compensa
    // mantener una reserva.
    Component { id: compGolpe; EfectoGolpe {} }

    function dibujarGolpe(heroe, enemigo) {
        const origen = filaHeroes.itemAt(heroe)
        const destino = filaEnemigos.itemAt(enemigo)
        if (!origen || !destino)
            return

        const datos = Game.grupo[heroe]
        const v = datos ? Game.claseDe(datos.clase).visual : null
        if (!v)
            return

        const a = origen.mapToItem(campo, origen.width * 0.62, origen.height * 0.5)
        const b = destino.mapToItem(campo, destino.width * 0.4, destino.height * 0.5)

        const obj = compGolpe.createObject(campo, {
            forma: v.forma, tono: v.color,
            desdeX: a.x, desdeY: a.y, hastaX: b.x, hastaY: b.y
        })
        if (obj)
            obj.arrancar()
    }

    Component { id: compHabilidad; EfectoHabilidad {} }

    // Cada efecto del servicio se dibuja de una manera, y el color lo pone la
    // clase que lo lanza: la misma cura se ve verde en la clériga y dorada en
    // el paladín. Los que no cambian el campo —provocar, invulnerable— salen
    // como aura sobre quien la lanza.
    readonly property var formaPorEfecto: ({
        area:        { forma: "onda",   sobre: "enemigos" },
        cadena:      { forma: "cadena", sobre: "enemigos" },
        golpeUnico:  { forma: "onda",   sobre: "enemigos" },
        remate:      { forma: "onda",   sobre: "enemigos" },
        veneno:      { forma: "nube",   sobre: "enemigos" },
        sangrar:     { forma: "nube",   sobre: "enemigos" },
        robarVida:   { forma: "cadena", sobre: "enemigos" },
        aturdir:     { forma: "cadena", sobre: "enemigos" },
        curaGrupo:   { forma: "motas",  sobre: "grupo" },
        regenerar:   { forma: "motas",  sobre: "grupo" },
        revivir:     { forma: "motas",  sobre: "grupo" },
        escudoGrupo: { forma: "aura",   sobre: "grupo" },
        escudoUno:   { forma: "aura",   sobre: "quien" },
        provocar:    { forma: "aura",   sobre: "quien" },
        invulnerable:{ forma: "aura",   sobre: "quien" },
        reflejo:     { forma: "aura",   sobre: "quien" }
    })

    function zonaDe(fila, cuantos) {
        const primero = fila.itemAt(0)
        const ultimo = fila.itemAt(Math.max(0, cuantos - 1))
        if (!primero || !ultimo)
            return null

        const a = primero.mapToItem(campo, 0, 0)
        const b = ultimo.mapToItem(campo, ultimo.width, ultimo.height)
        return { x: a.x, y: a.y, ancho: Math.max(20, b.x - a.x), alto: Math.max(20, b.y - a.y) }
    }

    function dibujarHabilidad(heroe, efecto) {
        const def = panel.formaPorEfecto[efecto]
        if (!def)
            return

        let zona = null
        if (def.sobre === "enemigos")
            zona = zonaDe(filaEnemigos, Game.enemigos.length)
        else if (def.sobre === "grupo")
            zona = zonaDe(filaHeroes, Game.grupo.length)
        else {
            const uno = filaHeroes.itemAt(heroe)
            if (uno) {
                const a = uno.mapToItem(campo, 0, 0)
                zona = { x: a.x, y: a.y, ancho: uno.width, alto: uno.height }
            }
        }
        if (!zona)
            return

        const datos = Game.grupo[heroe]
        const v = datos ? Game.claseDe(datos.clase).visual : null

        const obj = compHabilidad.createObject(campo, {
            forma: def.forma,
            tono: v ? v.color : "#ffffff",
            zonaX: zona.x, zonaY: zona.y,
            zonaAncho: zona.ancho, zonaAlto: zona.alto
        })
        if (obj)
            obj.arrancar()
    }

    // Las suyas caen sobre el grupo, salvo las que se hace a sí mismo
    // —envalentonarse, curarse—, que van sobre el propio bicho. El nombre sale
    // flotando encima: si te acaban de quitar media barra conviene saber qué
    // ha sido.
    function dibujarEnemiga(indice, forma, nombre) {
        const propia = forma === "aura" || forma === "motas"
        let zona = null

        if (propia) {
            const uno = filaEnemigos.itemAt(indice)
            if (uno) {
                const a = uno.mapToItem(campo, 0, 0)
                zona = { x: a.x, y: a.y, ancho: uno.width, alto: uno.height }
            }
        } else {
            zona = zonaDe(filaHeroes, Game.grupo.length)
        }
        if (!zona)
            return

        const obj = compHabilidad.createObject(campo, {
            forma: forma,
            tono: forma === "aura" ? "#ff9f0a" : (forma === "motas" ? "#32d74b" : "#ff453a"),
            zonaX: zona.x, zonaY: zona.y,
            zonaAncho: zona.ancho, zonaAlto: zona.alto
        })
        if (obj)
            obj.arrancar()

        const celda = filaEnemigos.itemAt(indice)
        if (celda)
            celda.golpear(nombre)
    }

    // Cada rasgo que cambia algo tiene su gesto: el escudo que se parte en
    // astillas, la ponzoña que cae encima, la vida que se va al ladrón, el
    // golpe que salpica a los de atrás.
    function centroDe(fila, indice) {
        const celda = fila.itemAt(indice)
        if (!celda)
            return null
        const a = celda.mapToItem(campo, celda.width / 2, celda.height * 0.5)
        return { x: a.x, y: a.y, ancho: celda.width, alto: celda.height,
                 izq: celda.mapToItem(campo, 0, 0).x }
    }

    function dibujarRasgo(enemigo, heroe, rasgo) {
        const eno = centroDe(filaEnemigos, enemigo)
        const her = centroDe(filaHeroes, heroe)
        if (!eno || !her)
            return

        if (rasgo === "drenaje") {
            const obj = compGolpe.createObject(campo, {
                forma: "robo", tono: "#bf5af2",
                desdeX: her.x, desdeY: her.y, hastaX: eno.x, hastaY: eno.y
            })
            if (obj) obj.arrancar()

        } else if (rasgo === "ruptura" || rasgo === "eco") {
            const obj = compGolpe.createObject(campo, {
                forma: "rotura",
                tono: rasgo === "ruptura" ? "#ffd60a" : "#0a84ff",
                desdeX: her.x, desdeY: her.y, hastaX: her.x, hastaY: her.y
            })
            if (obj) obj.arrancar()

        } else if (rasgo === "ponzona") {
            const obj = compHabilidad.createObject(campo, {
                forma: "nube", tono: "#32d74b",
                zonaX: her.izq, zonaY: her.y - her.alto * 0.35,
                zonaAncho: her.ancho, zonaAlto: her.alto * 0.7
            })
            if (obj) obj.arrancar()
        }
    }

    // ── campo de batalla ──────────────────────────────────────────
    Rectangle {
        id: campo
        Layout.fillWidth: true
        Layout.preferredHeight: 122
        radius: 12
        color: Theme.islandBg
        clip: true

        Fondo {
            id: escenario
            anchors.fill: parent
        }

        RowLayout {
            anchors.fill: parent
            anchors.margins: 9
            spacing: 6

            // El modelo es la CANTIDAD, no el array: el servicio reasigna
            // grupo y enemigos en cada tic, y un Repeater con modelo de array
            // JS destruye y recrea todos los delegados cada segundo —de ahí
            // que las barras parpadearan—. Con un entero estable los delegados
            // viven, y solo se rehacen si cambia el número de combatientes.
            Repeater {
                id: filaHeroes
                model: Game.grupo.length

                delegate: Combatiente {
                    required property int index
                    readonly property var datos: Game.grupo[index] || ({ clase: "tanque", vida: 0 })

                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    sprite: "assets/heroes/" + Game.claseDe(datos.clase).sprite + ".png"
                    vida: datos.vida
                    vidaMax: Game.vidaMaxDe(datos)
                    colorVida: Theme.green
                    mirandoDerecha: true

                    nivel: datos.nivel || 1
                    exp: datos.exp || 0
                    expNecesaria: Game.expParaNivel(datos.nivel || 1)
                    escudo: datos.escudo || 0
                    habilidades: Game.habilidadesDe(datos)
                    recargas: datos.recargas || ({})
                    heroe: index
                    envenenado: (datos.veneno || 0) > 0

                    // pulsar a los tuyos lleva a su ficha, que es donde se ve
                    // el equipo, las habilidades y lo que falta para el nivel
                    onPulsado: if (panel.plugin) panel.plugin.verHeroe(datos.clase)
                    onLanzar: function (id) { Game.lanzar(index, id) }
                }
            }

            IslandLabel {
                text: "vs"
                color: Theme.dim
                font.pixelSize: 11
                Layout.alignment: Qt.AlignVCenter
            }

            // la oleada entra deslizándose mientras el grupo camina
            Repeater {
                id: filaEnemigos
                model: Game.enemigos.length

                delegate: Combatiente {
                    required property int index
                    readonly property var datos: Game.enemigos[index]
                        || ({ vida: 0, vidaMax: 1, sprite: "m00", jefe: false })

                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    sprite: (datos.jefe || datos.mega
                        ? "assets/jefes/" : "assets/monstruos/") + datos.sprite + ".png"
                    vida: datos.vida
                    vidaMax: datos.vidaMax
                    colorVida: datos.jefe ? Theme.red : "#ff9f0a"
                    mirandoDerecha: false
                    // el megajefe ocupa el doble: es medio campo él solo, que
                    // es parte de lo que lo hace imponer
                    escala: datos.mega ? 2.1
                        : (datos.jefe ? 1.15 : (datos.elite ? 1.08 : 1))
                    nombre: datos.nombre || ""
                    destacado: datos.jefe || datos.elite || false
                    furioso: (datos.envalentonado || 0) > 0
                    rasgos: (datos.rasgos || []).map(function (r) {
                        return Game.rasgoDe(r)
                    }).filter(function (r) { return r !== null })

                    // Translate y no `x`: animar la x de un hijo de RowLayout
                    // pelea con el propio layout, y al acabar la animación los
                    // enemigos se quedaban clavados en el borde izquierdo,
                    // encima de los héroes.
                    transform: Translate { x: panel.entradaX }
                    opacity: panel.entradaOpacidad
                }
            }
        }

        // ── fin de partida
        Rectangle {
            anchors.fill: parent
            color: "#e6000000"
            visible: !Game.viva && Game.finalizada.length > 0

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 5

                IslandLabel {
                    text: Game.finalizada
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                    color: Theme.red
                    Layout.alignment: Qt.AlignHCenter
                }

                IslandLabel {
                    text: Idioma.t("récord: oleada ") + Game.mejorOleada + " · "
                        + Game.partidas + (Game.partidas === 1 ? Idioma.t(" partida") : Idioma.t(" partidas"))
                    color: Theme.muted
                    font.pixelSize: 10
                    Layout.alignment: Qt.AlignHCenter
                }

                IslandLabel {
                    text: Idioma.t("el equipo se conserva; el oro y las mejoras, no")
                    color: Theme.dim
                    font.pixelSize: 9
                    Layout.alignment: Qt.AlignHCenter
                }

                // ── dónde empezar la siguiente
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 2
                    spacing: 5
                    visible: Game.iniciosDisponibles.length > 1

                    IslandLabel {
                        text: Idioma.t("empezar en:")
                        color: Theme.dim
                        font.pixelSize: 9
                    }

                    Repeater {
                        model: Game.iniciosDisponibles

                        delegate: Rectangle {
                            id: punto
                            required property var modelData
                            readonly property bool elegido: Game.inicioElegido === modelData

                            Layout.preferredWidth: etiquetaPunto.implicitWidth + 14
                            Layout.preferredHeight: 18
                            radius: 9
                            color: elegido ? Theme.blue
                                : (puntoMouse.containsMouse ? Theme.surfaceHi : Theme.surface)

                            Behavior on color { ColorAnimation { duration: 120 } }

                            IslandLabel {
                                id: etiquetaPunto
                                anchors.centerIn: parent
                                text: punto.modelData
                                font.pixelSize: 9
                                font.weight: punto.elegido ? Font.DemiBold : Font.Normal
                            }

                            MouseArea {
                                id: puntoMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Game.elegirInicio(punto.modelData)
                            }
                        }
                    }
                }

                IslandLabel {
                    visible: Game.relevoRestante > 0
                    text: Idioma.t("siguiente partida en ") + Game.relevoRestante + " s"
                    color: "#ffd60a"
                    font.pixelSize: 10
                    Layout.alignment: Qt.AlignHCenter
                }

                Rectangle {
                    Layout.preferredWidth: reiniciar.implicitWidth + 28
                    Layout.preferredHeight: 24
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 2
                    radius: 12
                    color: reinicioMouse.containsMouse ? Theme.blue : Theme.surfaceHi

                    Behavior on color { ColorAnimation { duration: 120 } }

                    IslandLabel {
                        id: reiniciar
                        anchors.centerIn: parent
                        text: Game.relevoRestante > 0 ? Idioma.t("Empezar ya") : Idioma.t("Nueva partida")
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }

                    MouseArea {
                        id: reinicioMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Game.nuevaPartida()
                    }
                }
            }
        }

        // ── entra el megajefe
        //  Un jefe que empieza igual que los demás no impone nada. El nombre
        //  cruzando la pantalla es la mitad del trabajo.
        Rectangle {
            anchors.centerIn: parent
            width: parent.width
            height: 44
            color: "#cc000000"
            opacity: panel.anuncioOpacidad
            visible: opacity > 0.01

            IslandLabel {
                anchors.centerIn: parent
                text: panel.megaNombre
                color: panel.megaFase === -2 ? "#ffd60a" : Theme.red
                font.pixelSize: 20
                font.weight: Font.Bold
                scale: panel.anuncioEscala
            }
        }

        // ── fogonazo al cambiar de fase
        Rectangle {
            anchors.fill: parent
            color: "#ffffff"
            opacity: panel.faseOpacidad
            visible: opacity > 0.01
        }

        // ── depósito vacío
        //  En modo vibecoding esto no es un error, es la mecánica: el grupo
        //  espera a que vuelvas a picar. Conviene que se entienda a la
        //  primera, así que se dice qué falta y no solo que está parado.
        Rectangle {
            anchors.fill: parent
            color: "#d9000000"
            visible: Settings.juegoPorTokens && !Tokens.hay
                && Game.viva && !Game.pausada

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 3

                IconGlyph {
                    text: String.fromCodePoint(0xF0241)
                    color: Theme.dim
                    font.pixelSize: 22
                    Layout.alignment: Qt.AlignHCenter
                }

                IslandLabel {
                    text: Idioma.t("El grupo espera")
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    Layout.alignment: Qt.AlignHCenter
                }

                IslandLabel {
                    text: Idioma.t("gasta tokens en Claude o Codex y seguirán peleando")
                    color: Theme.muted
                    font.pixelSize: 10
                    Layout.alignment: Qt.AlignHCenter
                }

                IslandLabel {
                    visible: Tokens.totalChispa > 0
                    text: Tokens.cifra(Tokens.totalChispa) + Idioma.t(" de chispa quemada en total")
                    color: Theme.dim
                    font.pixelSize: 9
                    Layout.alignment: Qt.AlignHCenter
                }
            }
        }
    }

    // ── tienda de cofres ──────────────────────────────────────────
    // El oro ya no sube estadísticas: eso lo hace la experiencia. Aquí se
    // decide qué botín te llevas, que sí es una decisión.
    RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: false
        Layout.preferredHeight: 38
        spacing: 8

        Repeater {
            model: Game.tiendaDef

            delegate: IslandTile {
                id: oferta
                required property var modelData
                readonly property int precio: Game.costeCofre(modelData.tipo)
                readonly property bool asequible: Game.oro >= precio

                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 10
                activa: asequible
                colorActiva: Theme.surface
                onPulsada: Game.comprarCofre(oferta.modelData.tipo)

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 7

                    IconGlyph {
                        text: String.fromCodePoint(oferta.modelData.glifo)
                        color: oferta.asequible ? Theme.ink : Theme.dim
                        font.pixelSize: 14
                        Layout.alignment: Qt.AlignVCenter
                    }

                    IslandLabel {
                        text: oferta.modelData.nombre
                        color: oferta.asequible ? Theme.ink : Theme.dim
                        font.pixelSize: 10
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                    }

                    IconGlyph {
                        text: String.fromCodePoint(0xF0114)
                        color: oferta.asequible ? "#ffd60a" : Theme.dim
                        font.pixelSize: 10
                        Layout.alignment: Qt.AlignVCenter
                    }

                    IslandLabel {
                        text: Game.cifra(oferta.precio)
                        color: oferta.asequible ? "#ffd60a" : Theme.dim
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        Layout.alignment: Qt.AlignVCenter
                    }
                }
            }
        }
    }
}
