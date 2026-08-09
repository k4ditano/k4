//  El combate: una decisión por choque, no un botón que aporrear.
//
//  El emulador resuelve todo por temporizador y no te pide nada; aporrear
//  tampoco valía, porque aporrear es esfuerzo y no decisión. Así que sus
//  cuatro fases —atacar, preparar defensa, defender, colisión— se convierten
//  en las tres cosas que puedes elegir, una por choque:
//
//      A  atacar    gana a  cargar
//      B  defender  gana a  atacar
//      C  cargar    gana a  defender
//
//  Cargar no hace daño: acumula, y multiplica tu siguiente ataque. Por eso
//  es una apuesta —si te pillan cargando, duele el doble— y por eso el
//  combate es leer al rival en vez de machacar.
//
//  Y encima de eso, tres capas más que hacen que el bicho que has criado se
//  note dentro de la pelea:
//
//  · **Con qué pegas.** Cada técnica tiene forma —simple, ráfaga, columna— y
//    si tienes más de una, atacar pasa a ser elegir cuál. La columna es
//    lenta: si el rival ataca a la vez, no sale.
//  · **Estados.** Veneno, parálisis y debilidad, según el arquetipo del que
//    pega. Se ven en la barra de cada uno.
//  · **El aliado.** La llamada ya no multiplica tu golpe: saca de la
//    guardería al mejor que hayas criado, que pega una vez y se va.

import QtQuick
import K4 as K4
import "../../services"

Item {
    id: self

    required property string enemigo
    signal terminado(bool gane)

    //  Quién pelea de mi lado. Por defecto el que llevas encima; el PVP lo
    //  cambia en cada asalto, porque ahí pelea el equipo entero y no siempre
    //  el mismo bicho. Sin esto el duelo habrían sido tres veces el mismo.
    property string mio: Digivice.especie
    property var entrenosMios: null
    property var entrenosSuyos: null
    property bool pvp: false

    property var zumbador: null
    function _pitar(n) { if (zumbador) zumbador.sonar(n) }

    readonly property var dMio: Digivice.datoDe(mio)
    readonly property var dSuyo: Digivice.datoDe(enemigo)
    readonly property var statsMios: entrenosMios
            ? Digivice.statsDe(mio, entrenosMios) : Digivice.statsDe(mio)
    readonly property var statsSuyos: Digivice.statsDe(enemigo, entrenosSuyos || 0)

    property real vidaMia: statsMios.vida
    property real vidaSuya: statsSuyos.vida
    property int carga: 0
    property int ronda: 0

    //  Los estados alterados de cada lado. Listas de {tipo, turnos}: se
    //  reemplazan enteras en vez de tocarse por dentro, porque mutarlas no
    //  dispara los enlaces y los distintivos se quedarían congelados.
    property var estadosMios: []
    property var estadosSuyos: []

    //  Las técnicas con forma que tienes abiertas, y cuál llevas armada. El
    //  índice se recuerda entre choques: cambiar de golpe es una decisión, y
    //  obligarte a repetirla cada vez sería un peaje, no una elección.
    readonly property var tecnicas: entrenosMios
            ? Digivice.tecnicasFormasDe(mio, entrenosMios) : Digivice.tecnicasFormas
    property int iTecnica: 0
    readonly property var tecnicaArmada: tecnicas.length > 0
            ? tecnicas[Math.min(iTecnica, tecnicas.length - 1)] : null

    //  En un duelo no hay aliado: tu guardería ya está peleando, y sacarla
    //  otra vez sería contar dos veces los mismos bichos.
    readonly property var aliado: self.pvp ? null : Digivice.aliado
    property bool aliadoUsado: false

    //  vs · eligiendo · resolviendo · fin
    //
    //  «eligiendo» ya no espera a que decidas: el bicho pelea SOLO y tú
    //  intervienes. El original no pedía nada —sus cuatro fases van por
    //  `Alarm` y `Step`, ni una tecla— y su tesis era que lo que decide es
    //  cómo lo has criado. Yo me desvié a una decisión por choque, y con las
    //  expediciones eso se volvió una tarea: 19 intercambios con una decisión
    //  en cada uno, y ahora la carretera te da combates a todas horas.
    //
    //  El arreglo no es quitar las decisiones: es bajar su DENSIDAD. Pocas,
    //  caras y decisivas, encima de una pelea que corre sola.
    property string fase: "vs"
    property string cartel: ""
    property string miGesto: ""
    property string suGesto: ""
    property bool gane: false

    //  Lo que entra en la pantalla cuando el aliado sale a pegar.
    property string aliadoEnEscena: ""

    //  Lo que has pedido para el PRÓXIMO choque. Vacío quiere decir «pelea
    //  como sabes». Se consume al usarse: una intervención vale para un
    //  intercambio, no para el resto del combate.
    property string intervencion: ""

    //  El espectáculo: quién pega, dónde va el golpe y qué pasó.
    property string _quienPega: ""      // "mio" · "suyo"
    property bool _proyectil: false
    property bool _impacto: false
    property bool _esquiva: false
    property int _daño: 0
    property string _tecnicaVista: ""
    //  Lo que retrocede el que recibe el golpe. Positivo = hacia la derecha.
    property real _retroceso: 0

    //  Con qué se ha pegado ESTE intercambio, para dibujarlo. La forma decide
    //  el patrón —uno, tres o una columna— y la carga, el tamaño y el halo.
    property string _formaVista: "simple"
    property int _cargaVista: 0
    //  De quién es la firma del golpe que vuela. No siempre es «el que pega»:
    //  cuando entra el aliado, el golpe es SUYO.
    property string _firmaDe: ""
    readonly property var _firma: self._firmaDe !== ""
            ? Digivice.golpeVistaDe(self._firmaDe) : null

    //  El reloj del combate. Aquí está la diferencia con lo de antes: nadie
    //  espera a que pulses.
    //
    //  1200 ms es lo que sale de medirlo: la media son 19 intercambios, así
    //  que a 1500 ms un combate eran 30 s de mirar sin tocar nada y se hacía
    //  largo. A 1200 son ~24 s, que es lo que dura una pelea del aparato
    //  original, y siguen sobrando 550 ms entre el final del golpe y el
    //  siguiente: la ventana para intervenir no se estrecha tanto como para
    //  volverse un juego de reflejos.
    Timer {
        id: reloj
        interval: 1200
        repeat: true
        running: self.fase === "eligiendo"
        onTriggered: self._choque()
    }

    Timer {
        id: arranque
        interval: 1600
        running: true
        onTriggered: {
            self.fase = "eligiendo"
            //  Que la pelea va SOLA hay que decirlo una vez, al empezar. Sin
            //  esto el aparato parece que espera algo y no lo parece: espera
            //  a su reloj, no a ti.
            self.cartel = Idioma.t("Pelea solo · A B C para meter mano")
            avisoAuto.restart()
        }
    }

    Timer {
        id: avisoAuto
        interval: 2200
        onTriggered: if (self.fase === "eligiendo") self.cartel = ""
    }

    // ── elegir ────────────────────────────────────────────────────
    //
    function siguienteTecnica() {
        if (tecnicas.length === 0)
            return
        iTecnica = (iTecnica + 1) % tecnicas.length
        _pitar("boton")
    }

    function _choque() {
        if (fase !== "eligiendo")
            return
        fase = "resolviendo"

        //  Lo que hace el bicho: lo que le pediste, o lo que haría él solo.
        //  Sin intervención juega con el MISMO criterio que el rival, que es
        //  como se midió el equilibrio (46-53 % a igualdad de etapa).
        const accion = intervencion !== "" ? intervencion
                     : Digivice.eligeAccion(mio, entrenosMios)
        intervencion = ""

        //  Y con qué pega: la forma que mejor le venga al rival, salvo que
        //  hayas armado otra.
        const forma = accion === "atacar" && tecnicaArmada
                    ? tecnicaArmada.forma : "simple"
        //  Se apunta ANTES de resolver: la carga se pone a cero dentro y
        //  luego no habría manera de saber con cuánta se pegó.
        _formaVista = forma
        _cargaVista = accion === "atacar" ? carga : 0
        const r = Digivice.choque(enemigo, accion, carga, forma,
                                  estadosMios, estadosSuyos, ronda,
                                  { mio: self.mio, entrenosMios: self.entrenosMios,
                                    entrenosSuyos: self.entrenosSuyos,
                                    pvp: self.pvp })
        if (!r) { terminar(false); return }

        miGesto = r.paralizado ? "nada" : r.mia
        suGesto = r.suya
        ronda += 1

        //  Primero el daño, que no depende de cómo se cuente; después el
        //  cartel. Mezclarlo llevaba a enseñar «Técnica −0» cuando el golpe
        //  se había esquivado: el daño estaba bien y el texto mentía.
        if (r.aQuien === "ambos") {
            vidaSuya = Math.max(0, vidaSuya - r.daño)
            vidaMia = Math.max(0, vidaMia - r.dañoSuyo)
            carga = 0
        } else if (r.aQuien === "suyo") {
            vidaSuya = Math.max(0, vidaSuya - r.daño)
            carga = 0
        } else if (r.aQuien === "mio") {
            vidaMia = Math.max(0, vidaMia - r.daño)
            carga = 0
        } else if (r.cargaGanada > 0) {
            carga = Math.min(3, carga + r.cargaGanada)
        }

        //  Una columna que no llega a salir tiene que DECIRLO: si no, el
        //  turno parece que no ha pasado y la apuesta no se entiende nunca.
        const miColumnaLenta = forma === "columna" && r.fallo
                            && accion === "atacar" && !r.paralizado

        if (r.paralizado) {
            cartel = Idioma.t("¡Paralizado! Pierdes el turno")
            _pitar("recibido")
            K4.Isla.efecto("digivice", "empujon", 0.6)
        } else if (miColumnaLenta) {
            cartel = Idioma.t("¡Demasiado lento!")
                   + (r.aQuien === "mio" && r.daño > 0 ? "  −" + r.daño : "")
            _pitar("atras")
            if (r.daño > 0)
                K4.Isla.efecto("digivice", "empujon", 0.7)
        } else if (r.aQuien === "ambos") {
            cartel = Idioma.t("¡Chocan los dos!")
            _pitar("golpe")
            K4.Isla.efecto("digivice", "sacudida", 0.6)
        } else if (r.aQuien !== "" && r.daño === 0) {
            //  Alguien tiró el golpe y no entró: es una esquiva, y se dice.
            cartel = r.aQuien === "mio" ? Idioma.t("¡Lo esquivas!")
                                        : Idioma.t("¡Lo esquiva!")
            _pitar("atras")
        } else if (r.aQuien === "suyo") {
            cartel = _cartelGolpe(r, false)
            _pitar("golpe")
            K4.Isla.efecto("digivice", "sacudida",
                           forma === "columna" ? 0.9 : 0.5)
        } else if (r.aQuien === "mio") {
            cartel = _cartelGolpe(r, true)
            _pitar("recibido")
            K4.Isla.efecto("digivice", "empujon", 0.6)
        } else if (r.cargaGanada > 0) {
            cartel = Idioma.t("Cargando…") + "  ×" + (1 + 0.5 * carga).toFixed(1)
            _pitar("elegir")
        } else {
            cartel = Idioma.t("Los dos se cubren")
            _pitar("atras")
        }

        //  El estado que haya dejado el golpe.
        if (r.estado) {
            if (r.estadoA === "mio")
                estadosMios = Digivice.aplicarEstado(estadosMios, r.estado)
            else
                estadosSuyos = Digivice.aplicarEstado(estadosSuyos, r.estado)
            cartel += "  ·  " + Idioma.t(Digivice.textoEstado(r.estado))
            _pitar("estado")
        }

        //  El espectáculo: quién pega, si sale proyectil, si entra o se
        //  esquiva. Antes el combate eran dos sprites quietos y una línea de
        //  texto; el original ya enseñaba el golpe cruzando la pantalla.
        _quienPega = r.aQuien === "mio" ? "suyo"
                   : (r.aQuien === "suyo" || r.aQuien === "ambos") ? "mio" : ""
        //  La firma es del que PEGA. Si pega el rival, el golpe lleva su
        //  forma y su halo, no los tuyos: es lo que hace que se lea de quién
        //  viene sin mirar de qué lado sale.
        _firmaDe = _quienPega === "mio" ? mio
                 : _quienPega === "suyo" ? enemigo : ""
        //  Y si el que pega es él, la forma vista es la SUYA. El rival rota
        //  sus formas por turno, así que ponerle «simple» a mano le dibujaba
        //  un golpe suelto cuando estaba tirando una ráfaga de tres: el
        //  patrón mentía justo cuando más importa leerlo.
        if (_quienPega === "suyo") {
            _formaVista = r.forma || "simple"
            _cargaVista = 0
        }
        _tecnicaVista = r.tecnica || ""
        _daño = r.daño
        _esquiva = r.aQuien !== "" && r.daño === 0
        if (_quienPega !== "") {
            _proyectil = true
            vuela.restart()
        } else {
            _impacto = false
        }

        _cobrarVeneno()
        siguiente.restart()
    }

    //  El golpe cruzando y el impacto. Va por tiempo y no por fotogramas: el
    //  sprite es de uno solo y el movimiento es todo lo que hay.
    SequentialAnimation {
        id: vuela
        NumberAnimation { target: self; property: "_avanceGolpe"
                          from: 0; to: 1; duration: 380
                          easing.type: Easing.InQuad }
        ScriptAction { script: {
            self._proyectil = false
            self._impacto = !self._esquiva
            self._avanceGolpe = 0
        } }
        PauseAnimation { duration: 260 }
        ScriptAction { script: self._impacto = false }
    }

    property real _avanceGolpe: 0

    //  El veneno cobra al cerrar el intercambio, y puede rematar: un combate
    //  ganado por envenenamiento es una victoria como cualquier otra.
    function _cobrarVeneno() {
        const tm = Digivice.tickEstados(estadosMios, statsMios.vida)
        const ts = Digivice.tickEstados(estadosSuyos, statsSuyos.vida)
        estadosMios = tm.estados
        estadosSuyos = ts.estados
        if (tm.quema > 0) vidaMia = Math.max(0, vidaMia - tm.quema)
        if (ts.quema > 0) vidaSuya = Math.max(0, vidaSuya - ts.quema)
    }

    //  Qué se dice de un golpe que entra.
    //
    //  Decía solo el nombre de la técnica, y eso no distingue lo que hay que
    //  distinguir: si ha sido un golpe normal, una técnica con forma, o uno
    //  cargado. Los tres se veían igual y por eso no se entendía qué hacían
    //  los botones. Ahora el cartel lo dice con las mismas palabras que la
    //  leyenda: «normal», el nombre de la técnica con su forma, y el ×N si
    //  iba cargado.
    function _cartelGolpe(r, contraMi) {
        let t = r.tecnica || (contraMi ? Idioma.t("Te alcanza") : Idioma.t("Impacto"))
        if (!r.tecnica && !contraMi)
            t = Idioma.t("Golpe normal")
        if (r.forma === "rafaga")
            t += "  " + Idioma.t("ráfaga") + (r.impactos > 0 ? " ×" + r.impactos : "")
        else if (r.forma === "columna")
            t += "  " + Idioma.t("columna")
        if (!contraMi && self._cargaVista > 0)
            t = "×" + (1 + 0.5 * self._cargaVista).toFixed(1) + "  " + t
        return t + "  −" + r.daño
    }

    Timer {
        id: siguiente
        interval: 1150
        onTriggered: {
            if (self.vidaSuya <= 0) self.terminar(true)
            else if (self.vidaMia <= 0) self.terminar(false)
            else { self.fase = "eligiendo"; self.cartel = "" }
        }
    }

    function terminar(g) {
        gane = g
        fase = "fin"
        cartel = g ? Idioma.t("¡Victoria!") : Idioma.t("Derrota")
        _pitar(g ? "victoria" : "derrota")
        K4.Tema.tintar("digivice", g ? K4.Tema.verde : K4.Tema.rojo, 0.3, 1200)
        cierre.restart()
    }

    Timer {
        id: cierre
        interval: 1500
        onTriggered: { K4.Tema.destintar("digivice"); self.terminado(self.gane) }
    }

    signal huido()

    function escapar() {
        if (fase !== "eligiendo")
            return
        //  En un duelo no se huye: es un asalto de tres y escaparse sería
        //  ganar el duelo sin pelearlo.
        if (pvp) { cartel = Idioma.t("De un duelo no se huye"); _pitar("atras"); return }
        if (!Digivice.huir()) { _pitar("atras"); return }
        fase = "fin"
        cartel = Idioma.t("¡Escapas!")
        _pitar("atras")
        cierreHuida.restart()
    }

    Timer {
        id: cierreHuida
        interval: 1100
        onTriggered: self.huido()
    }

    //  Los tres botones del aparato, ahora como INTERVENCIONES.
    //
    //  Ya no eliges cada choque: pides algo para el SIGUIENTE. A arma la
    //  técnica con la que quieres que pegue, B le manda cubrirse y C, cargar.
    //  Pocas, y cada una vale para un intercambio.
    //
    //  A pide atacar SIEMPRE, y de paso rota la técnica si hay más de una.
    //  Estaba partido: con dos técnicas abiertas, A solo cambiaba de arma y
    //  no llegaba a pedir el ataque nunca, así que la única intervención que
    //  no se podía dar era justo la de pegar —y cuantas más técnicas tienes,
    //  menos mandas—. Pulsar A es «pega, y con esta».
    function atacar() {
        if (fase === "fin") return
        intervencion = "atacar"
        if (tecnicas.length > 1) {
            siguienteTecnica()
            cartel = Idioma.t("Con ") + (tecnicaArmada ? tecnicaArmada.nombre : "")
            return
        }
        cartel = Idioma.t("¡Ataca!")
        _pitar("boton")
    }

    function defender() {
        if (fase === "fin") return
        intervencion = "defender"
        cartel = Idioma.t("¡Cúbrete!")
        _pitar("boton")
    }

    function cargar() {
        if (fase === "fin") return
        intervencion = "cargar"
        cartel = Idioma.t("¡Carga!")
        _pitar("boton")
    }

    function llamar() {
        if (fase !== "eligiendo")
            return
        if (aliado && aliadoUsado) {
            cartel = Idioma.t("Ya ha ayudado en este combate")
            _pitar("atras")
            return
        }
        if (!Digivice.gastarLlamada()) {
            cartel = Idioma.t("Sin energía")
            _pitar("atras")
            return
        }
        if (!aliado) {
            //  Sin nadie en la guardería, la llamada es un arreón: carga al
            //  máximo y ataca ya.
            //
            //  Aquí había una llamada a `elegir("atacar")`, que es una función
            //  que dejó de existir cuando el combate pasó a automático: el
            //  botón gastaba la energía y luego reventaba sin pegar. O sea que
            //  para quien no tiene guardería —todo el mundo al principio— la
            //  llamada estaba rota del todo.
            carga = 3
            intervencion = "atacar"
            _pitar("invocar")
            _choque()
            return
        }

        const g = Digivice.golpeDelAliado(enemigo)
        if (!g) { cartel = Idioma.t("No puede venir"); return }

        fase = "resolviendo"
        aliadoUsado = true
        aliadoEnEscena = g.especie
        vidaSuya = Math.max(0, vidaSuya - g.daño)
        cartel = g.nombre + "  " + (g.tecnica || Idioma.t("ayuda")) + "  −" + g.daño
        if (g.estado)
            estadosSuyos = Digivice.aplicarEstado(estadosSuyos, g.estado)

        //  El aliado pega CON LO SUYO: su forma y su halo, no los tuyos. Es
        //  medio premio de la guardería —el otro medio es ver su cara— y
        //  antes su golpe era exactamente igual que el de tu bicho.
        _quienPega = "mio"
        _firmaDe = g.especie
        _formaVista = "columna"
        _cargaVista = 3
        _tecnicaVista = g.tecnica || ""
        _daño = g.daño
        _esquiva = false
        _proyectil = true
        vuela.restart()
        _pitar("invocar")
        K4.Isla.efecto("digivice", "sacudida", 0.9)
        K4.Tema.tintar("digivice", K4.Tema.amarillo, 0.22, 700)
        _cobrarVeneno()
        saleAliado.restart()
    }

    Timer {
        id: saleAliado
        interval: 1300
        onTriggered: {
            K4.Tema.destintar("digivice")
            self.aliadoEnEscena = ""
            if (self.vidaSuya <= 0) self.terminar(true)
            else { self.fase = "eligiendo"; self.cartel = "" }
        }
    }

    //  ── el VS ─────────────────────────────────────────────────────
    //
    //  Antes el combate empezaba sin más. Un encuentro merece que te digan
    //  contra QUIÉN peleas: los dos retratos entrando de sus lados, los
    //  nombres y la etapa. Segundo y medio, ni uno más.
    Rectangle {
        anchors.fill: parent
        visible: self.fase === "vs"
        color: "#0a1008"
        z: 20

        Item {
            anchors.fill: parent

            Column {
                x: 8 + (self.fase === "vs" ? 0 : -80)
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Behavior on x { NumberAnimation { duration: 380
                                                  easing.type: Easing.OutBack } }

                Retrato { especie: self.mio; lado: 54 }
                K4.Etiqueta {
                    width: 76
                    horizontalAlignment: Text.AlignHCenter
                    text: self.dMio ? self.dMio.n : ""
                    font.pixelSize: 11
                    font.weight: Font.Bold
                    color: "#9fe8ac"
                    elide: Text.ElideRight
                }
                K4.Etiqueta {
                    width: 76
                    horizontalAlignment: Text.AlignHCenter
                    text: self.dMio ? self.dMio.l : ""
                    font.pixelSize: 10
                    color: "#5f8f6c"
                }
            }

            K4.Etiqueta {
                anchors.centerIn: parent
                text: "VS"
                font.pixelSize: 26
                font.weight: Font.Bold
                color: "#e8b45a"

                SequentialAnimation on scale {
                    running: self.fase === "vs"
                    NumberAnimation { from: 3.0; to: 1.0; duration: 320
                                      easing.type: Easing.OutBack }
                }
            }

            Column {
                x: parent.width - 84 + (self.fase === "vs" ? 0 : 80)
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Behavior on x { NumberAnimation { duration: 380
                                                  easing.type: Easing.OutBack } }

                Retrato { especie: self.enemigo; lado: 54 }
                K4.Etiqueta {
                    width: 76
                    horizontalAlignment: Text.AlignHCenter
                    text: self.dSuyo ? self.dSuyo.n : ""
                    font.pixelSize: 11
                    font.weight: Font.Bold
                    color: "#e0806b"
                    elide: Text.ElideRight
                }
                K4.Etiqueta {
                    width: 76
                    horizontalAlignment: Text.AlignHCenter
                    text: (self.dSuyo ? self.dSuyo.l : "")
                        + (Digivice.jefePendiente ? "  ★" : "")
                    font.pixelSize: 10
                    color: Digivice.jefePendiente ? "#e8b45a" : "#5f8f6c"
                }
            }
        }
    }

    // ── lo que se ve ──────────────────────────────────────────────
    Paisaje {
        anchors.fill: parent
        tono: self.pvp ? "#101828"
            : Digivice.jefePendiente ? "#2a1010" : "#1d1410"
        semilla: self.pvp ? 7 : Digivice.indiceZona
        avance: 0
        opacity: 0.4
    }

    Column {
        anchors.fill: parent
        anchors.margins: 4
        spacing: 3

        //  Las dos vidas.
        Row {
            width: parent.width
            spacing: 4

            Repeater {
                model: [
                    { v: self.vidaMia, max: self.statsMios.vida, mio: true },
                    { v: self.vidaSuya, max: self.statsSuyos.vida, mio: false }
                ]

                Rectangle {
                    //  Con id explícito: el `modelData` de dentro se resolvía
                    //  por el padre, que es justo el atajo que ya ha roto tres
                    //  cosas en este plugin.
                    id: barra
                    required property var modelData
                    width: (parent.width - 4) / 2
                    height: 6
                    radius: 2
                    color: "#1a0f0a"

                    Rectangle {
                        height: parent.height
                        radius: 2
                        width: barra.width * Math.max(
                                   0, barra.modelData.v / Math.max(1, barra.modelData.max))
                        x: barra.modelData.mio ? 0 : barra.width - width
                        color: barra.modelData.mio ? "#7de08a" : "#e0806b"
                        Behavior on width { NumberAnimation { duration: 220 } }
                    }
                }
            }
        }

        //  Debajo de cada barra: DE QUIÉN es y cuánta vida le queda, más los
        //  estados que arrastra.
        //
        //  Dos barras iguales y sin nombre no son dos barras: son una barra
        //  del enemigo y otra que no se sabe de quién es. Tal cual lo dijo
        //  quien lo jugó —«veo la energía del enemigo pero no la mía»—, y
        //  tenía razón: el color no basta para decir «tú», y menos si el
        //  bicho de la izquierda es de cualquier color. Con «TÚ» y las cifras
        //  se acaba la duda, y va aquí porque esta fila estaba casi siempre
        //  vacía: no cuesta ni un píxel de alto.
        //
        //  Un estado que no se ve es además un castigo secreto: el jugador
        //  nota que pega menos y no sabe por qué.
        Row {
            width: parent.width
            height: 13

            Repeater {
                model: [
                    { lista: self.estadosMios, mio: true },
                    { lista: self.estadosSuyos, mio: false }
                ]

                Item {
                    id: lado
                    required property var modelData
                    width: (parent.width - 4) / 2
                    height: 13

                    Row {
                        spacing: 3
                        anchors.right: lado.modelData.mio ? undefined : parent.right
                        anchors.left: lado.modelData.mio ? parent.left : undefined

                        //  El rótulo va SIEMPRE en el borde de fuera, pegado
                        //  al extremo por el que se vacía su barra.
                        K4.Etiqueta {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: lado.modelData.mio
                            text: Idioma.t("TÚ") + "  " + self.vidaMia
                                + "/" + self.statsMios.vida
                            font.pixelSize: 10
                            font.weight: Font.Bold
                            color: "#7de08a"
                        }

                        Repeater {
                            model: lado.modelData.lista

                            K4.Glifo {
                                required property var modelData
                                text: Digivice.glifoEstado(modelData.tipo)
                                font.pixelSize: 12
                                color: modelData.tipo === "veneno" ? "#9fe07a"
                                     : modelData.tipo === "paralisis" ? "#e8d05a"
                                     : "#c98ae0"

                                SequentialAnimation on opacity {
                                    running: true
                                    loops: Animation.Infinite
                                    NumberAnimation { to: 0.45; duration: 620 }
                                    NumberAnimation { to: 1.0; duration: 620 }
                                }
                            }
                        }

                        K4.Etiqueta {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !lado.modelData.mio
                            text: self.vidaSuya + "/" + self.statsSuyos.vida
                            font.pixelSize: 10
                            color: "#e0806b"
                        }
                    }
                }
            }
        }

        //  La carga acumulada: es TU apuesta, así que va en TU lado.
        //
        //  Estaba centrada, en tres rayitas de 12×4 que no eran de nadie, y
        //  por eso cargar «no se sentía»: el multiplicador solo salía en el
        //  cartel de abajo, un instante, y desaparecía. Ahora se queda
        //  puesta mientras dure, a la izquierda, con el ×N al lado y un
        //  latido cada vez que sube —y el bicho se enciende, ver más abajo—.
        Row {
            spacing: 3

            Repeater {
                model: 3

                Rectangle {
                    id: pilaCarga
                    required property int index
                    width: 15; height: 6; radius: 3
                    color: pilaCarga.index < self.carga ? "#e8b45a" : "#3a2a18"
                    border.width: pilaCarga.index < self.carga ? 0 : 1
                    border.color: "#4a3a20"

                    SequentialAnimation on scale {
                        running: pilaCarga.index === self.carga - 1
                        loops: Animation.Infinite
                        NumberAnimation { to: 1.25; duration: 420 }
                        NumberAnimation { to: 1.0; duration: 420 }
                    }
                }
            }

            K4.Etiqueta {
                anchors.verticalCenter: parent.verticalCenter
                visible: self.carga > 0
                text: "×" + (1 + self.carga * 0.5).toFixed(1)
                font.pixelSize: 11
                font.weight: Font.Bold
                color: "#e8b45a"
            }
        }

        //  Los dos bichos y lo que ha elegido cada uno.
        Item {
            width: parent.width
            height: parent.height - 100

            //  El aura de la carga, DETRÁS de tu bicho. Las rayitas de arriba
            //  dicen cuánta llevas; esto dice que la lleva ÉL. Cargar dejaba
            //  de sentirse porque el turno pasaba y el bicho seguía igual:
            //  ahora se enciende más cuanto más acumula y late más deprisa,
            //  y se apaga de golpe en cuanto suelta el golpe.
            Rectangle {
                visible: self.carga > 0
                width: 40 + self.carga * 12
                height: width
                radius: width / 2
                x: 31 - width / 2
                y: parent.height / 2 - width / 2
                color: "transparent"
                border.width: 3
                border.color: "#e8b45a"
                //  A 0.27 el anillo se perdía contra el paisaje: en un LCD de
                //  puntos, un dorado al 27 % sobre marrón no es un aura, es
                //  suciedad. Empieza visible y se acerca al lleno con la
                //  tercera carga.
                opacity: 0.4 + self.carga * 0.18
                Behavior on width { NumberAnimation { duration: 220 } }

                SequentialAnimation on scale {
                    running: self.carga > 0
                    loops: Animation.Infinite
                    NumberAnimation { to: 1.12; duration: 620 - self.carga * 120 }
                    NumberAnimation { to: 0.96; duration: 620 - self.carga * 120 }
                }
            }

            Criatura {
                especie: self.mio
                lado: 54
                quieto: true
                mirandoDerecha: true
                width: 62; height: parent.height
                x: self._quienPega === "suyo" ? self._retroceso : 0
                opacity: self.aliadoEnEscena !== "" ? 0.35 : 1
                Behavior on opacity { NumberAnimation { duration: 200 } }
            }

            Criatura {
                especie: self.enemigo
                lado: 54
                quieto: true
                mirandoDerecha: false
                width: 62; height: parent.height
                x: parent.width - 62
                  + (self._quienPega === "mio" ? self._retroceso : 0)
            }

            //  El aliado entra por la izquierda, pega y se va. Que se vea
            //  QUIÉN es —su retrato, no un destello— es la mitad del premio:
            //  es el bicho que criaste y guardaste.
            Retrato {
                id: ayudante
                visible: self.aliadoEnEscena !== ""
                especie: self.aliadoEnEscena
                lado: 48
                y: parent.height / 2 - 24
                x: visible ? 46 : -50
                z: 5
                Behavior on x { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }
            }

            //  El aliado esperando, abajo a la izquierda: su cara, lo que
            //  cuesta, y se pulsa. La llamada vivía SOLO en la tecla `L`, y
            //  este aparato se juega con tres botones y el ratón: la mitad de
            //  la mecánica estaba escondida detrás de un teclado que el
            //  compositor ni siquiera cede si no pinchas la superficie.
            Rectangle {
                id: chapa
                //  Se ve SIEMPRE, con o sin guardería.
                //
                //  Estaba condicionada a tener aliado, así que quien empieza
                //  —o sea, todo el mundo el primer día— no veía la chapa
                //  nunca y no había manera de enterarse de que la llamada
                //  existe. Sin aliado la llamada sigue haciendo algo: carga
                //  al máximo y ataca. Eso también hay que poder verlo.
                visible: self.fase !== "fin" && self.aliadoEnEscena === ""
                x: 2
                y: parent.height - height - 2
                width: 62
                height: 20
                radius: 10
                z: 6
                color: "#122018"
                border.width: 1
                border.color: self.aliadoUsado ? "#2f4a38"
                            : Digivice.puedeLlamar ? "#e8b45a" : "#4a3a20"
                opacity: self.aliadoUsado ? 0.4 : 1

                Row {
                    anchors.centerIn: parent
                    spacing: 3

                    Retrato {
                        visible: self.aliado !== null
                        especie: self.aliado ? self.aliado.especie : ""
                        lado: 15
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    //  Sin nadie a quien llamar, el icono del arreón.
                    K4.Glifo {
                        visible: self.aliado === null
                        anchors.verticalCenter: parent.verticalCenter
                        text: "\u{F0241}"
                        font.pixelSize: 13
                        color: Digivice.puedeLlamar ? "#e8b45a" : "#8a7550"
                    }

                    //  Y aquí lo que faltaba: DECIR en qué estado está.
                    //
                    //  Era una cara y «3⚡», y con eso no hay manera de saber
                    //  si el aliado entra solo, si hay que llamarlo, si se
                    //  puede ya o si se gastó. La pregunta era literalmente
                    //  «¿cuándo puedes invocar a un compañero, y si es
                    //  automático, en qué momento?». No lo es: entra cuando
                    //  lo llamas, una vez por combate, y cuesta energía.
                    K4.Etiqueta {
                        anchors.verticalCenter: parent.verticalCenter
                        text: self.aliadoUsado ? Idioma.t("ya vino")
                            : !Digivice.puedeLlamar ? Idioma.t("sin ⚡")
                            : "L · " + Digivice.costeLlamada + "⚡"
                        font.pixelSize: 10
                        font.weight: Digivice.puedeLlamar && !self.aliadoUsado
                                   ? Font.Bold : Font.Normal
                        color: self.aliadoUsado ? "#6a7a6e"
                             : Digivice.puedeLlamar ? "#e8b45a" : "#8a7550"
                    }
                }

                //  Sin `enabled: false` cuando no se puede: pulsarlo tiene
                //  que decir POR QUÉ no se puede, y un botón muerto no dice
                //  nada. El silencio ante una acción imposible ya nos costó
                //  una ronda de «los botones no funcionan».
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: self.llamar()
                }

                SequentialAnimation on scale {
                    running: chapa.visible && !self.aliadoUsado
                             && Digivice.puedeLlamar && self.fase === "eligiendo"
                    loops: Animation.Infinite
                    NumberAnimation { to: 1.08; duration: 700 }
                    NumberAnimation { to: 1.0; duration: 700 }
                }
            }

            //  Huir. La otra cosa que hace la energía, y tapa un hueco de
            //  verdad: no se podía salir de una pelea, así que un jefe que te
            //  superase te obligaba a perder. A la derecha para no confundirse
            //  con la chapa del aliado, que está a la izquierda.
            Rectangle {
                id: chapaHuir
                visible: self.fase !== "fin" && self.aliadoEnEscena === ""
                x: parent.width - width - 2
                y: parent.height - height - 2
                width: 40
                height: 20
                radius: 10
                z: 6
                color: "#201212"
                border.width: 1
                border.color: Digivice.puedeHuir ? "#c98a6b" : "#4a3020"
                opacity: Digivice.puedeHuir ? 1 : 0.45

                Row {
                    anchors.centerIn: parent
                    spacing: 2

                    K4.Glifo {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "\u{F004D}"
                        font.pixelSize: 11
                        color: Digivice.puedeHuir ? "#e0a08b" : "#8a7550"
                    }

                    K4.Etiqueta {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Digivice.costeHuida + "⚡"
                        font.pixelSize: 9
                        color: Digivice.puedeHuir ? "#e0a08b" : "#8a7550"
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: self.escapar()
                }
            }

            //  EL GOLPE cruzando la pantalla, con la PINTA del que lo tira.
            //
            //  Era un punto de color igual para todos. Ahora la forma sale del
            //  arquetipo y el halo del atributo (`Reglas.golpeVistaDe`), y el
            //  PATRÓN sale de la forma de ataque, que es lo que faltaba para
            //  distinguir un golpe normal de una técnica sin leer el cartel:
            //
            //      simple   un golpe
            //      ráfaga   tres seguidos, escalonados
            //      columna  una fila apretada que cruza como un haz
            //
            //  Y la carga lo hace más grande y le enciende el halo. Un golpe
            //  cargado no es otro dibujo: es el mismo, crecido, para que se
            //  siga reconociendo de quién viene.
            Repeater {
                model: self._formaVista === "rafaga" ? 3
                     : self._formaVista === "columna" ? 5 : 1

                Golpe {
                    id: bala
                    required property int index
                    readonly property int _n: self._formaVista === "rafaga" ? 3
                                            : self._formaVista === "columna" ? 5 : 1
                    //  La ráfaga se escalona en el tiempo —son tres golpes— y
                    //  la columna en el espacio, porque es UN golpe largo.
                    readonly property real _retraso:
                        self._formaVista === "rafaga" ? bala.index * 0.18 : 0
                    readonly property real _hueco:
                        self._formaVista === "columna" ? bala.index * 11 : 0
                    readonly property real _avance:
                        Math.max(0, Math.min(1, self._avanceGolpe - bala._retraso))

                    visible: self._proyectil && bala._avance > 0
                    z: 4
                    forma: self._firma ? self._firma.forma : "chispa"
                    color: self._firma ? self._firma.color : "#e8dcc8"
                    aura: self._firma ? self._firma.aura : "#d8d8d8"
                    carga: self._cargaVista
                    haciaDerecha: self._quienPega === "mio"
                    lado: self._formaVista === "columna" ? 9 : 12

                    x: {
                        const dcha = self._quienPega === "mio"
                        const a = dcha ? 56 : parent.width - 56
                        const b = dcha ? parent.width - 62 : 56
                        const p = a + (b - a) * bala._avance
                        return p - width / 2 - (dcha ? bala._hueco : -bala._hueco)
                    }
                    y: parent.height / 2 - height / 2
                }
            }

            //  El impacto: un fogonazo sobre el que lo recibe.
            //
            //  Dos piezas y no una. El disco solo se veía como una pegatina
            //  blanca puesta encima del bicho; lo que lo convierte en un
            //  golpe es que el disco se APAGUE deprisa mientras un anillo
            //  sale despedido hacia fuera. Es el mismo truco de dos tiempos
            //  del fogonazo del huevo.
            Item {
                id: fogonazo
                visible: self._impacto
                width: 34; height: 34
                z: 5
                x: (self._quienPega === "mio" ? parent.width - 62 : 46) - 17
                y: parent.height / 2 - 17

                Rectangle {
                    id: nucleo
                    anchors.centerIn: parent
                    width: 26; height: 26; radius: 13
                    color: "#fff3d0"
                }

                Rectangle {
                    id: onda
                    anchors.centerIn: parent
                    width: 30; height: 30; radius: 15
                    color: "transparent"
                    border.width: 2
                    border.color: self._quienPega === "mio" ? "#9fe8ac" : "#e0806b"
                }

                ParallelAnimation {
                    running: fogonazo.visible
                    NumberAnimation { target: nucleo; property: "scale"
                                      from: 0.25; to: 1.15; duration: 110
                                      easing.type: Easing.OutQuad }
                    NumberAnimation { target: nucleo; property: "opacity"
                                      from: 1; to: 0; duration: 260 }
                    NumberAnimation { target: onda; property: "scale"
                                      from: 0.4; to: 1.9; duration: 300
                                      easing.type: Easing.OutQuad }
                    NumberAnimation { target: onda; property: "opacity"
                                      from: 0.9; to: 0; duration: 300 }
                }

                //  Y el que la recibe acusa el golpe: retrocede un poco. Sin
                //  esto el impacto le pasa por encima sin tocarle.
                NumberAnimation {
                    running: fogonazo.visible
                    target: self; property: "_retroceso"
                    from: self._quienPega === "mio" ? 7 : -7
                    to: 0; duration: 280; easing.type: Easing.OutBack
                }
            }

            //  El número del daño, subiendo desde quien lo recibe.
            K4.Etiqueta {
                id: cifra
                visible: self._impacto && self._daño > 0
                text: "−" + self._daño
                font.pixelSize: 15
                font.weight: Font.Bold
                color: self._quienPega === "mio" ? "#9fe8ac" : "#e07a63"
                z: 6
                x: (self._quienPega === "mio" ? parent.width - 62 : 46) - width / 2
                y: parent.height / 2 - 26

                onVisibleChanged: if (visible) sube.restart()
                NumberAnimation {
                    id: sube
                    target: cifra; property: "y"
                    from: self.height / 2 - 20; to: self.height / 2 - 44
                    duration: 520; easing.type: Easing.OutQuad
                }
            }

            //  Y la esquiva, que también tiene que verse.
            K4.Etiqueta {
                visible: self._esquiva && self.fase === "resolviendo"
                text: Idioma.t("¡Esquiva!")
                font.pixelSize: 13
                font.weight: Font.Bold
                color: "#bcd4f0"
                z: 6
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height / 2 - 30
            }

            //  ── ESCUDO Y CARGA, en el bicho ───────────────────────
            //
            //  Atacar ya se veía —el golpe cruza la pantalla—, pero las otras
            //  dos acciones no tenían cuerpo: cubrirse y cargar eran un icono
            //  de 16 px sobre la cabeza y nada más. Con la pelea automática
            //  eso deja dos de cada tres intercambios sin nada que mirar, y
            //  encima son las dos que hay que aprender a leer para intervenir
            //  bien.
            //
            //  Van sobre el bicho que las hace, dentro de la misma ventana de
            //  «resolviendo» que el golpe, así que las tres acciones se leen
            //  a la vez y se compara lo que hizo cada uno.
            Repeater {
                model: [
                    { g: self.miGesto, mio: true },
                    { g: self.suGesto, mio: false }
                ]

                Item {
                    id: accion
                    required property var modelData
                    readonly property bool mio: accion.modelData.mio
                    readonly property real cx: accion.mio ? 31 : parent.width - 31
                    //  Hacia dónde mira: por delante de él es hacia el rival.
                    readonly property real frente: accion.mio ? 20 : -20
                    visible: self.fase === "resolviendo"
                             && self.aliadoEnEscena === ""
                    x: 0; y: 0
                    width: parent.width
                    height: parent.height
                    z: 3

                    //  EL ESCUDO. Un arco por delante, del lado por el que le
                    //  viene el golpe: se planta de golpe y se queda temblando.
                    Rectangle {
                        id: escudo
                        visible: accion.modelData.g === "defender"
                        x: accion.cx + (accion.mio ? 22 : -22) - width / 2
                        y: parent.height / 2 - height / 2
                        width: 13
                        height: 46
                        radius: 6
                        color: "#8ab4e0"
                        opacity: 0.22
                        border.width: 2
                        border.color: "#bcd4f0"

                        onVisibleChanged: if (visible) plantar.restart()
                        SequentialAnimation {
                            id: plantar
                            ParallelAnimation {
                                NumberAnimation { target: escudo; property: "scale"
                                                  from: 0.3; to: 1.15; duration: 130
                                                  easing.type: Easing.OutBack }
                                NumberAnimation { target: escudo; property: "opacity"
                                                  from: 0.9; to: 0.4; duration: 130 }
                            }
                            NumberAnimation { target: escudo; property: "scale"
                                              to: 1.0; duration: 180
                                              easing.type: Easing.OutBounce }
                        }
                    }

                    //  LA CARGA. Cuatro motas que caen hacia el bicho desde
                    //  fuera y se le meten dentro: cargar es RECOGER energía,
                    //  y el anillo que ya había solo decía «tiene» energía,
                    //  no «la está juntando».
                    Repeater {
                        model: accion.modelData.g === "cargar" ? 4 : 0

                        Rectangle {
                            id: mota
                            required property int index
                            property real avance: 0
                            readonly property real ang: mota.index * (Math.PI / 2)
                                                      + (accion.mio ? 0 : Math.PI / 4)
                            width: 5; height: 5; radius: 2.5
                            color: "#e8b45a"
                            opacity: mota.avance
                            //  Convergen al PUNTO DE CARGA, que está delante
                            //  del bicho y no en su centro: puesto en el
                            //  centro, el destello se veía como una moneda
                            //  pegada en la barriga del sprite.
                            x: accion.cx + accion.frente
                               + Math.cos(mota.ang) * 34 * (1 - mota.avance) - 2.5
                            y: parent.height / 2 - 12
                               + Math.sin(mota.ang) * 34 * (1 - mota.avance) - 2.5

                            NumberAnimation on avance {
                                running: true
                                loops: Animation.Infinite
                                from: 0; to: 1
                                duration: 780
                                easing.type: Easing.InQuad
                            }
                        }
                    }

                    //  Y un destello en el sitio donde se juntan.
                    Rectangle {
                        visible: accion.modelData.g === "cargar"
                        x: accion.cx + accion.frente - 6
                        y: parent.height / 2 - 18
                        width: 12; height: 12; radius: 6
                        color: "#e8b45a"

                        SequentialAnimation on opacity {
                            running: parent.visible
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.9; duration: 300 }
                            NumberAnimation { to: 0.25; duration: 300 }
                        }
                    }
                }
            }

            //  Los gestos elegidos, cada uno SOBRE SU BICHO.
            //
            //  Estaban los dos juntos en el centro, que es exactamente por
            //  donde vuela el golpe: el proyectil salía por detrás de los
            //  iconos y el fogonazo se comía la lectura. Un gesto dice «esto
            //  hizo ESTE», así que su sitio es encima de quien lo hace, fuera
            //  de la línea de tiro.
            Repeater {
                model: [
                    { g: self.miGesto, mio: true },
                    { g: self.suGesto, mio: false }
                ]

                K4.Glifo {
                    id: gesto
                    required property var modelData
                    visible: self.fase === "resolviendo" && self.miGesto !== ""
                           && self.aliadoEnEscena === ""
                    text: modelData.g === "atacar" ? "\u{F04E5}"
                        : modelData.g === "defender" ? "\u{F0498}"
                        : "\u{F0241}"
                    font.pixelSize: 16
                    color: modelData.mio ? "#9fe8ac" : "#e0806b"
                    z: 6
                    x: modelData.mio ? 31 - width / 2
                                     : parent.width - 31 - width / 2
                    y: parent.height / 2 - 44

                    //  Aparece de golpe y se va apagando mientras el golpe
                    //  cruza: cuando llega el impacto ya casi no está y no
                    //  compite con él.
                    onVisibleChanged: if (visible) asoma.restart()
                    SequentialAnimation {
                        id: asoma
                        NumberAnimation { target: gesto; property: "opacity"
                                          from: 0; to: 1; duration: 110 }
                        PauseAnimation { duration: 420 }
                        NumberAnimation { target: gesto; property: "opacity"
                                          to: 0.25; duration: 260 }
                    }
                }
            }
        }

        //  El selector de técnica: solo cuando lo has abierto y solo si hay
        //  algo que elegir.
        Column {
            width: parent.width
            spacing: 1
            visible: self.fase === "tecnica"

            K4.Etiqueta {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: self.tecnicaArmada ? self.tecnicaArmada.nombre : ""
                font.pixelSize: 13
                font.weight: Font.Bold
                color: "#e8b45a"
                elide: Text.ElideRight
            }

            K4.Etiqueta {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: {
                    if (!self.tecnicaArmada) return ""
                    const f = self.tecnicaArmada.forma
                    return f === "rafaga" ? Idioma.t("Ráfaga · 3 golpes, pasa la defensa")
                         : f === "columna" ? Idioma.t("Columna · el doble, pero lenta")
                         : Idioma.t("Simple · fiable")
                }
                font.pixelSize: 11
                color: "#8fbf9c"
                elide: Text.ElideRight
            }
        }

        //  El cartel: qué elegir, o qué ha pasado.
        K4.Etiqueta {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            visible: self.fase !== "tecnica"
            //  La leyenda dice QUÉ va a pasar si pulsas, con nombre y todo.
            //
            //  Ponía «A técnica · B cubrir · C cargar», que no dice con qué
            //  técnica, ni que la pelea va sola, ni que lo pulsado vale para
            //  el choque siguiente. Con el combate automático eso es justo lo
            //  que hay que decir: no estás eligiendo el turno, estás
            //  METIENDO MANO en el próximo.
            text: self.cartel !== "" ? self.cartel
                : self.fase === "eligiendo"
                  ? (self.intervencion !== ""
                     ? Idioma.f(Idioma.t("Le has pedido: %1"),
                                self.intervencion === "atacar"
                                  ? (self.tecnicaArmada
                                     ? self.tecnicaArmada.nombre
                                     : Idioma.t("atacar"))
                                : self.intervencion === "defender"
                                  ? Idioma.t("cubrirse") : Idioma.t("cargar"))
                     : (self.tecnicaArmada
                        ? Idioma.f(Idioma.t("A %1 · B cubrir · C cargar"),
                                   self.tecnicaArmada.nombre)
                        : Idioma.t("A atacar · B cubrir · C cargar")))
                : ""
            font.pixelSize: self.fase === "fin" ? 14 : 11
            font.weight: Font.DemiBold
            color: self.fase === "fin"
                 ? (self.gane ? "#9fe8ac" : "#e07a63") : "#e8dcc8"
            elide: Text.ElideRight
        }

        //  La leyenda del selector, en su sitio para que no baile el cartel.
        K4.Etiqueta {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            visible: self.fase === "tecnica"
            text: Idioma.f(Idioma.t("A pasa · B lanza · C vuelve  (%1/%2)"),
                           self.iTecnica + 1, self.tecnicas.length)
            font.pixelSize: 11
            color: "#5f8f6c"
        }
    }
}
