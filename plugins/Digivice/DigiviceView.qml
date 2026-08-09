//  La vista: la island ENTERA es el aparato.
//
//  No hay pestañas ni cabecera de escritorio. Todo pasa en la pantalla, de
//  una cosa cada vez, y se navega con los tres botones: A recorre los iconos
//  del borde, B elige el que parpadea, C vuelve. Es la interfaz del aparato
//  de verdad, y por eso se lee sin que nadie la explique.
//
//  No guarda estado de juego: lee del servicio y le manda gestos. Lo suyo es
//  qué se está mirando y contra quién se pelea.

import QtQuick
import K4 as K4
import "../../services"

Item {
    id: raiz
    required property var plugin

    //  Qué hay en la pantalla: bicho · estado · mapa · lista · combate · entreno
    property string escena: "bicho"
    property string combate: ""
    property bool entrenando: false
    //  Cazando: la cacería se apodera de la pantalla y de los tres botones,
    //  igual que un entrenamiento o un combate.
    property bool cazando: false
    //  Qué estadística se está entrenando ahora mismo. Cada una tiene su
    //  minijuego, y el minijuego encaja con lo que entrena: puntería para el
    //  ataque, pelota para la velocidad, aguante para la vida y bloqueo para
    //  la defensa.
    property string statEntreno: "atq"

    //  El menú del borde. El orden es el del aparato: primero cuidar, luego
    //  mirar. La salida va la última porque es lo que menos se usa.
    //  Los códigos están COMPROBADOS uno a uno con `tools/digivice_glifos.py`,
    //  que dice qué dibuja cada uno según el nombre real en la fuente. Hacía
    //  falta porque los de antes existían todos —así que nada fallaba— pero
    //  dibujaban cualquier cosa: «Comer» era un picture-in-picture, «Huevos»
    //  un pingüino, «Guardería» un md-barley_off y «Limpiar», un podio.
    //  «Casa» va primero y su pantalla es el bicho. Sin él, el aparato abría
    //  con el cursor sobre «Bolsa» pero enseñando la criatura: `pulsarB` mira
    //  la ESCENA y no el cursor, así que B no hacía absolutamente nada, y A te
    //  alejaba de la Bolsa — solo se llegaba dando la vuelta entera al menú.
    //  Con «Casa» el arranque está en sincronía y la Bolsa queda a una
    //  pulsación.
    readonly property var menu: [
        { glifo: 0xF02DC, accion: "casa",      nombre: Idioma.t("Casa") },
        { glifo: 0xF0D2E, accion: "bolsa",     nombre: Idioma.t("Bolsa") },
        { glifo: 0xF10F1, accion: "mimar",     nombre: Idioma.t("Mimar") },
        { glifo: 0xF01E6, accion: "entreno",   nombre: Idioma.t("Entrenar") },
        { glifo: 0xF06EF, accion: "curar",     nombre: Idioma.t("Curar") },
        { glifo: 0xF00E2, accion: "limpiar",   nombre: Idioma.t("Limpiar") },
        { glifo: 0xF0684, accion: "evolucion", nombre: Idioma.t("Evolución") },
        { glifo: 0xF014D, accion: "estado",    nombre: Idioma.t("Estado") },
        { glifo: 0xF034D, accion: "mapa",      nombre: Idioma.t("Mapa") },
        { glifo: 0xF0AAF, accion: "huevos",    nombre: Idioma.t("Huevos") },
        { glifo: 0xF0827, accion: "banco",     nombre: Idioma.t("Guardería") },
        { glifo: 0xF05DA, accion: "lista",     nombre: Idioma.t("Vistos") },
        { glifo: 0xF0538, accion: "objetivos", nombre: Idioma.t("Objetivos") },
        { glifo: 0xF04DC, accion: "mercado",   nombre: Idioma.t("Mercado") },
        { glifo: 0xF0787, accion: "pvp",       nombre: Idioma.t("Duelo") },
        { glifo: 0xF0156, accion: "salir",     nombre: Idioma.t("Salir") }
    ]
    property int seleccion: 0

    //  ¿Estás recorriendo el menú o ya has ENTRADO en una pantalla?
    //
    //  Sin esta distinción el aparato se quedaba atrapado: las pantallas de
    //  lista se abren al señalarlas, y A pasaba a recorrer la lista en cuanto
    //  el menú tocaba una. O sea que llegabas a «Entrenar» —el cuarto icono—
    //  y ya no podías seguir: los once iconos siguientes eran inalcanzables.
    //
    //  Ahora A recorre SIEMPRE el menú mientras miras, B entra, y dentro es
    //  cuando A pasa fichas. C te saca de la pantalla y te devuelve al menú,
    //  que es lo que se espera de un botón de volver.
    property bool dentro: false

    //  Las pantallas que se recorren por dentro. Las demás son acciones o
    //  cosas que solo se miran.
    readonly property var conLista: ["lista", "banco", "huevos", "entreno",
                                     "evolucion", "bolsa", "objetivos",
                                     "mercado", "pvp"]
    function _tieneLista(e) { return conLista.indexOf(e) >= 0 }

    //  La enciclopedia se recorre de una ficha en una, como el aparato.
    property int cursorLista: 0

    Sonidos { id: zumbador; activo: plugin.conSonido }

    //  Lo último que el aparato tiene que decirte, y por cuánto tiempo.
    //
    //  Existe porque sin esto pulsar B sobre una acción imposible no hacía
    //  NADA visible —ni mensaje ni sonido—, y el botón parecía roto. El caso
    //  peor era alimentar dormido: no se veía nada y por debajo sumaba un
    //  descuido. Un castigo invisible es peor que un botón muerto.
    property string aviso: ""

    Timer {
        id: avisoTimer
        interval: 2200
        onTriggered: raiz.aviso = ""
    }

    Connections {
        target: Digivice
        function onAviso(texto) {
            raiz.aviso = texto
            avisoTimer.restart()
            zumbador.sonar("atras")
        }

        //  Comer dejó de ser un botón del menú y pasó a la despensa, y con el
        //  cambio se perdieron el pitido y el salto del bicho: comía y no se
        //  enteraba nadie. Van por la señal, así que suenan igual desde la
        //  pantalla, desde el IPC o desde donde sea.
        function onComido(id, nombre) {
            const c = Digivice.comidaPorId(id)
            zumbador.sonar(c && c.veneno ? "fallo" : "comer")
            raiz.reaccion(c ? c.glifo : "\u{F0A70}")
        }

        function onCazado(id, nombre, malo) {
            raiz.reaccion(malo ? "\u{F068C}" : "\u{F03E9}")
        }

        //  Lo que la carretera te pone delante. El rastro abre su minijuego
        //  —el que era la caza— y lo demás es un hallazgo que se anuncia.
        function onHallado(clase, dato) {
            if (clase === "rastro") {
                raiz.cazando = true
                zumbador.sonar("elegir")
                return
            }
            if (clase === "bits") {
                zumbador.sonar("moneda")
                raiz.reaccion("\u{F0830}")
            } else if (clase === "comida") {
                zumbador.sonar("acierto")
                raiz.reaccion(Digivice.glifoObjeto(dato))
            } else if (clase === "datos") {
                zumbador.sonar("acierto")
                raiz.reaccion("\u{F02D3}")
            }
        }

        //  Estas cuatro no sonaban NI se veían. El servicio las emitía desde
        //  las fases 4 y 5 y la vista no las escuchaba, así que usar una
        //  vitamina, cobrar un objetivo o comprar en el mercado eran acciones
        //  mudas: cambiaba un número en la pantalla y nada más.
        function onObjetoUsado(id, nombre) {
            const o = Digivice.comidaPorId(id) || null
            zumbador.sonar("curar")
            raiz.reaccion(Digivice.glifoObjeto(id))
        }

        function onComprado(id, nombre, precio) {
            zumbador.sonar("moneda")
            raiz.reaccion("\u{F0830}")
        }

        function onObjetivoCobrado(id, bits, objeto) {
            zumbador.sonar("victoria")
            raiz.reaccion("\u{F0538}")
            K4.Tema.tintar("digivice", K4.Tema.amarillo, 0.22, 900)
            destinte.restart()
        }

        function onVendido(id, bits) {
            zumbador.sonar("moneda")
            raiz.reaccion("\u{F0830}")
        }

        function onIncubado(id) {
            zumbador.sonar("elegir")
            raiz.reaccion("\u{F0AAF}")
        }

        //  Cambiar de bicho en la guardería: es el gesto que más cambia el
        //  juego de todos los que se hacen desde un menú, y no sonaba nada.
        function onCambioDeCriatura(antes, ahora) {
            zumbador.sonar("invocar")
            raiz.reaccion("\u{F0827}")
        }

        //  Armor, X y Warp: la evolución ya suena por `evoluciono`, pero una
        //  especial merece que se vea QUE fue especial.
        function onEspecial(via, antes, ahora) {
            raiz.reaccion(via === "warp" ? "\u{F0241}"
                        : via === "armor" ? "\u{F113B}" : "\u{F0391}")
        }
    }

    Timer {
        id: destinte
        interval: 950
        onTriggered: K4.Tema.destintar("digivice")
    }

    // ── el teclado ────────────────────────────────────────────────
    //  El foco se queda aquí SIEMPRE y las teclas se reparten desde aquí: si
    //  se lo cediera al combate —que vive dos Items dentro de la pantalla—
    //  dependería de que el foco bajara hasta allí, que es lo que no hay que
    //  suponer.
    focus: true
    property var foco: K4.FocoInicial { objetivo: raiz }

    //  Y reclamarlo al entrar el ratón, que es cuando `tecladoAlPasar` nos da
    //  el teclado: para entonces FocoInicial ya se rindió.
    HoverHandler { onHoveredChanged: if (hovered) raiz.foco.reclamar() }

    Keys.onPressed: function (e) {
        //  Mientras se escribe el código del rival, las teclas son del campo:
        //  si el menú se quedara con ellas, escribir una «a» recorrería los
        //  iconos en vez de escribir una «a».
        if (escena === "pvp" && cargador.item && cargador.item.escribiendo) {
            if (e.key === Qt.Key_Escape) { raiz.forceActiveFocus(); e.accepted = true }
            return
        }
        if (e.key === Qt.Key_Escape) { plugin.close(); e.accepted = true }
        //  El teclado hace lo mismo que los botones, sonido incluido: si solo
        //  pitara el ratón, jugar con las manos en el teclado sería otro juego.
        else if (e.key === Qt.Key_A || e.key === Qt.Key_Left) {
            if (combate === "") zumbador.sonar("boton")
            pulsarA(); e.accepted = true
        }
        //  La llamada, que ya no cabe en los tres botones: su propia tecla.
        else if (e.key === Qt.Key_L && combate !== "") {
            if (cargador.item && cargador.item.llamar) cargador.item.llamar()
            e.accepted = true
        }
        else if (e.key === Qt.Key_C || e.key === Qt.Key_Backspace) {
            zumbador.sonar("atras"); pulsarC(); e.accepted = true
        }
        else if (e.key === Qt.Key_B || e.key === Qt.Key_Space
                 || e.key === Qt.Key_Return) {
            if (combate === "" && !entrenando && !cazando) zumbador.sonar("elegir")
            pulsarB(); e.accepted = true
        }
    }

    //  Qué pantalla le toca a cada icono del menú.
    //
    //  Los que MIRAN tienen la suya; los que HACEN —comer, mimar, curar…—
    //  enseñan al bicho, porque es sobre él sobre quien actúan. Así lo que
    //  señalas es siempre lo que ves.
    function _escenaDe(accion) {
        if (accion === "estado" || accion === "mapa" || accion === "lista"
            || accion === "banco" || accion === "huevos" || accion === "entreno"
            || accion === "evolucion" || accion === "bolsa"
            || accion === "objetivos" || accion === "mercado"
            || accion === "pvp")
            return accion
        return "bicho"
    }

    //  Deja la pantalla en sincronía con el icono señalado. Sin esto, entrar
    //  en el mapa y luego recorrer el menú hasta «Comer» te dejaba mirando el
    //  mapa con su «¡Pelear!» encima: el aparato decía una cosa y enseñaba
    //  otra.
    function _sincronizar() {
        const nueva = _escenaDe(menu[seleccion].accion)
        if (nueva !== escena) {
            escena = nueva
            cursorLista = 0
        }
    }

    // ── los tres botones, que es toda la interacción ──────────────
    function pulsarA() {
        //  En combate los tres botones son las tres decisiones: A ataca.
        if (combate !== "") {
            if (cargador.item && cargador.item.atacar) cargador.item.atacar()
            return
        }
        if (entrenando)
            return
        if (cazando) {
            if (cargador.item && cargador.item.pasar) cargador.item.pasar()
            return
        }
        //  Solo DENTRO de una pantalla A pasa fichas. Mientras miras el menú,
        //  A recorre el menú entero, que es lo que dice hacer.
        if (dentro && _tieneLista(escena)) {
            cursorLista += 1; return
        }
        seleccion = (seleccion + 1) % menu.length
        _sincronizar()
    }

    function pulsarB() {
        //  En combate y entrenando, B es el gesto del juego y no el menú.
        if (combate !== "") {
            if (cargador.item && cargador.item.defender) cargador.item.defender()
            return
        }
        if (entrenando) {
            if (cargador.item && cargador.item.tirar) cargador.item.tirar()
            return
        }
        if (cazando) {
            if (cargador.item && cargador.item.elegir) cargador.item.elegir()
            return
        }
        //  Sin criatura, B es para el huevo: lo abre si está listo y pone
        //  uno nuevo si no hay ninguno. Es lo único que se puede hacer.
        if (!Digivice.hayPartida) {
            if (Digivice.huevoListo) raiz.romperHuevo()
            else if (!Digivice.hayIncubacion) Digivice.nuevaPartida()
            return
        }
        //  En el mapa, con el camino terminado, B lo rehace: cada zona tiene
        //  su comida, sus especies y su Digimental, y dejarla muerta al
        //  vencer al jefe te quedaría sin sitio donde andar.
        if (escena === "mapa" && Digivice.caminoAcabado) {
            if (Digivice.rehacerCamino(Digivice.zona))
                zumbador.sonar("invocar")
            return
        }
        //  Primera pulsación: ENTRAR en la pantalla señalada. Así pasar por
        //  encima de «Bolsa» camino de «Mapa» no le da de comer al bicho de
        //  paso, y A puede seguir recorriendo el menú hasta el final.
        if (!dentro && _tieneLista(escena)) {
            dentro = true
            cursorLista = 0
            return
        }
        //  Ya dentro, B actúa sobre lo señalado: dárselo, comprarlo, cobrarlo.
        if (escena === "bolsa" || escena === "objetivos" || escena === "mercado"
            || escena === "pvp") {
            if (cargador.item && cargador.item.elegir) cargador.item.elegir()
            return
        }
        //  En evolución, B evoluciona o fusiona.
        if (escena === "evolucion") {
            if (cargador.item && cargador.item.elegir) cargador.item.elegir()
            return
        }
        //  En la hoja de entrenamiento, B arranca el minijuego de la
        //  estadística señalada.
        if (escena === "entreno") {
            if (cargador.item && cargador.item.elegir) cargador.item.elegir()
            return
        }
        //  En la incubadora, B pone el huevo elegido o saca al que rompe.
        if (escena === "huevos") {
            if (cargador.item && cargador.item.elegir) cargador.item.elegir()
            return
        }
        //  En la guardería, B saca al que estás mirando.
        if (escena === "banco") {
            if (cargador.item && cargador.item.cambiar) cargador.item.cambiar()
            return
        }

        //  Solo suena lo que de verdad ha pasado: `alimentar` devuelve false
        //  si está lleno o dormido, y celebrar una acción que no ocurrió
        //  enseña al jugador a no fiarse del sonido.
        const a = menu[seleccion].accion
        if (a === "mimar") {
            if (Digivice.mimar()) { zumbador.sonar("mimar"); reaccion("\u{F02D1}") }
        } else if (a === "curar") {
            if (Digivice.curar()) { zumbador.sonar("curar"); reaccion("\u{F06EF}") }
        } else if (a === "limpiar") {
            if (Digivice.limpiar()) { zumbador.sonar("limpiar"); reaccion("\u{F00E2}") }
        }
        else if (a === "salir") plugin.close()
        //  Las pantallas ya se abren al señalarlas, así que aquí no queda
        //  nada que hacer: B es para actuar, no para navegar.
    }

    function pulsarC() {
        //  C carga: la tercera decisión.
        if (combate !== "") {
            if (cargador.item && cargador.item.cargar) cargador.item.cargar()
            return
        }
        if (entrenando)
            return
        if (cazando) {
            if (cargador.item && cargador.item.salir) cargador.item.salir()
            return
        }
        //  C sube UN nivel, no salta al principio. Estando dentro de una
        //  pantalla te devuelve al menú dejándote donde estabas; ya en el
        //  menú, te lleva a casa. Antes hacía siempre lo segundo, así que
        //  salir de la guardería te mandaba al primer icono.
        if (dentro) {
            dentro = false
            cursorLista = 0
            return
        }
        escena = "bicho"
        seleccion = 0
        cursorLista = 0
    }

    // ── el duelo ──────────────────────────────────────────────────
    //
    //  Tres asaltos uno contra uno, y gana quien se lleve dos. Se juegan A
    //  MANO, con la misma pantalla de combate de siempre: resolverlos de
    //  golpe y enseñar un marcador habría sido tirar por la borda todo lo que
    //  costó que pelear fuese una decisión y no un vídeo.
    //  El instante de romper: enseña la pose de partido y el fogonazo antes
    //  de que aparezca la criatura. Sin esta pausa el huevo desaparecía de
    //  golpe y no se veía nacer nada.
    property bool rompiendo: false

    function romperHuevo() {
        if (!Digivice.huevoListo || rompiendo)
            return
        rompiendo = true
        zumbador.sonar("evolucion")
        cascara.restart()
    }

    Timer {
        id: cascara
        interval: 900
        onTriggered: {
            raiz.rompiendo = false
            Digivice.eclosionar()
        }
    }

    property bool enDuelo: false
    property string carteDuelo: ""

    function empezarDuelo() {
        if (!Digivice.hayDuelo)
            return
        enDuelo = true
        escena = "bicho"
        _siguienteAsalto()
    }

    function _siguienteAsalto() {
        if (Digivice.pvpDecidido) {
            _cerrarDuelo()
            return
        }
        const i = Digivice.pvpAsalto
        combate = Digivice.rivalEquipo[i].especie
    }

    function _cerrarDuelo() {
        const gane = Digivice.pvpMios > Digivice.pvpSuyos
        carteDuelo = (gane ? Idioma.t("¡Duelo ganado!") : Idioma.t("Duelo perdido"))
                   + "  " + Digivice.pvpMios + "–" + Digivice.pvpSuyos
        zumbador.sonar(gane ? "victoria" : "derrota")
        Digivice.cerrarDuelo()
        enDuelo = false
        finDuelo.restart()
    }

    Timer {
        id: finDuelo
        interval: 2600
        onTriggered: raiz.carteDuelo = ""
    }

    //  Le pide a la pantalla de casa que el bicho reaccione. Si estás en otra
    //  pantalla no pasa nada: la acción se ha hecho igual.
    //  Toda acción que OCURRE tiene que verse, y verse DONDE ESTÁ EL JUGADOR.
    //
    //  Antes esto se rendía si no estabas en la pantalla del bicho, así que
    //  dar de comer desde la bolsa —que es de donde se da de comer desde la
    //  fase 4— no producía ninguna animación: sonaba un pitido y ya. Lo mismo
    //  con la caza, que ocurre con la pantalla de rastros delante.
    //
    //  Ahora son dos cosas: el bicho salta SI se le ve, y además el símbolo
    //  sube por encima de la pantalla, esté la que esté. La segunda es la que
    //  garantiza que ninguna acción se quede muda.
    property string _simboloAccion: ""

    function reaccion(simbolo) {
        if (cargador.item && cargador.item.reaccionar)
            cargador.item.reaccionar(simbolo)
        _simboloAccion = simbolo
        globoAccion.opacity = 1
        globoAccion.y = globoAccion._base
        subeGlobo.restart()
    }

    //  Un encuentro nuevo lleva al mapa, que es donde se pelea.
    Connections {
        target: Digivice
        function onEncuentro(idEnemigo) {
            //  AVISA, pero no te saca de donde estás.
            //
            //  Antes esto hacía `escena = "mapa"` a secas, y el problema no
            //  es que interrumpa: es QUIÉN lo dispara. El encuentro lo trae
            //  la carretera, y la carretera avanza con lo que haces en el
            //  ESCRITORIO —abrir ventanas, cambiar de espacio—, no con lo que
            //  pulsas aquí. Así que podías estar dándole de comer a tu bicho
            //  y aparecer en el mapa a media pulsación, sin haber hecho nada
            //  en el aparato. Tal cual pasó: «estaba en la zona de Casa y me
            //  salió el combate contra JEFE».
            //
            //  No se pierde nada por esperar: el encuentro BLOQUEA el camino
            //  hasta que lo resuelvas, así que seguirá ahí cuando vayas.
            //
            //  Sí se sale de la caza: esa pantalla se apodera de los tres
            //  botones, y dejar un aviso debajo de un sitio del que no puedes
            //  salir no es avisar de nada.
            if (raiz.cazando)
                raiz.cazando = false
            raiz.aviso = Digivice.jefePendiente
                       ? "★ " + Idioma.t("¡EL JEFE TE CORTA EL PASO!")
                       : Idioma.f(Idioma.t("¡%1 te corta el paso!"),
                                  Digivice.nombreDe(idEnemigo))
            avisoTimer.restart()
            zumbador.sonar("llamada")
        }
        //  La evolución es EL momento del juego y se merece su fanfarria.
        function onEvoluciono(antes, ahora) { zumbador.sonar("evolucion") }
        //  Capturar datos y romper el huevo son los dos momentos de la
        //  colección: los dos suenan.
        function onEscaneado(id, huevo) {
            raiz.aviso = Idioma.f(Idioma.t("Datos de %1 · huevo desbloqueado"),
                                  Digivice.nombreDe(id))
            avisoTimer.restart()
            zumbador.sonar("invocar")
        }
        //  Fusionar es el momento más caro del juego: se pierden dos bichos.
        //  Merece la fanfarria y que la barra entera lo note.
        function onFusionado(a, b, hijo) {
            zumbador.sonar("evolucion")
            K4.Isla.efecto("digivice", "tiron")
            K4.Tema.tintar("digivice", K4.Tema.amarillo, 0.4, 1800)
            raiz.aviso = Idioma.f(Idioma.t("¡%1 ha nacido de la fusión!"),
                                  Digivice.nombreDe(hijo))
            avisoTimer.restart()
        }
        function onEclosiono(id) {
            zumbador.sonar("evolucion")
            K4.Isla.efecto("digivice", "tiron")
        }
        //  El jefe se anuncia con la llamada y un tirón de la barra: es el
        //  momento en que merece la pena que la island llame la atención.
        function onJefeALaVista(idJefe, zonaId) {
            zumbador.sonar("llamada")
            K4.Isla.efecto("digivice", "tiron")
        }
        function onJefeCaido(idJefe, zonaId) {
            K4.Tema.tintar("digivice", K4.Tema.amarillo, 0.35, 1600)
        }
    }

    //  Y lo que pida el plugin desde fuera (el IPC, o pinchar la píldora).
    function _aplicarPedida() {
        if (!plugin.escenaPedida)
            return
        escena = plugin.escenaPedida
        for (let i = 0; i < menu.length; ++i)
            if (menu[i].accion === escena) { seleccion = i; break }
        //  Pedir una pantalla es querer estar DENTRO de ella, no con el
        //  cursor encima: quien llama a `ver bolsa` quiere la bolsa abierta.
        dentro = _tieneLista(escena)
        cursorLista = 0
        plugin.escenaPedida = ""
    }
    //  Uno solo: dos `Component.onCompleted` en el mismo objeto son
    //  «Property value set multiple times» y el plugin no carga.
    Component.onCompleted: {
        foco.reclamar()
        _aplicarPedida()
        plugin.zumbador = zumbador
        //  Si la carretera dejó un rastro a medias mientras la vista estaba
        //  cerrada, se retoma al abrir. Si no, quedaba un camino parado sin
        //  que nada lo enseñara.
        if (Digivice.caceria)
            cazando = true
    }

    Connections {
        target: plugin
        function onEscenaPedidaChanged() { raiz._aplicarPedida() }
    }

    // ── el aparato, llenando la island ────────────────────────────
    Aparato {
        id: aparato
        anchors.fill: parent
        //  El LCD se enciende en cuanto hay ALGO que enseñar, no solo con
        //  criatura. Estaba atado a `hayPartida`, y desde que una partida
        //  empieza con un huevo eso apagaba la pantalla justo encima del
        //  huevo: el aparato salía en negro y no había manera de saber por
        //  qué.
        encendida: Digivice.indiceListo
        iconos: raiz.menu
        //  Con un bicho parado en la carretera, el mapa lleva punto: es lo
        //  que sustituye a sacarte de donde estés.
        alertas: Digivice.encuentroPendiente ? ["mapa"] : []
        //  En combate y entrenando no hay menú: el aparato está a otra cosa.
        iconoActivo: (raiz.combate !== "" || raiz.entrenando || raiz.cazando)
                     ? -1 : raiz.seleccion
        iconoFijo: raiz.dentro
        //  Contra un jefe la pantalla va más roja: el aparato avisa de que
        //  esto no es un bicho más.
        tinteLcd: raiz.combate !== ""
                    ? (Digivice.jefePendiente ? "#2a1010" : "#1d1410")
                : raiz.entrenando ? "#101a24"
                : "#0d1f14"

        leyenda: (raiz.combate !== "" || raiz.entrenando || raiz.cazando
                  || !Digivice.hayPartida) ? ""
               : raiz.dentro ? raiz.menu[raiz.seleccion].nombre + "  ·  C vuelve"
               : raiz.menu[raiz.seleccion].nombre

        zumbador: zumbador

        onPulsadoA: raiz.pulsarA()
        onPulsadoB: raiz.pulsarB()
        onPulsadoC: raiz.pulsarC()

        pantalla: Loader {
            id: cargador
            anchors.fill: parent
            sourceComponent: !Digivice.indiceListo ? cargando
                           : !Digivice.hayPartida ? sinPartida
                           : raiz.combate !== "" ? enCombate
                           : raiz.entrenando ? (raiz.statEntreno === "vel" ? entrenoPelota
                                              : raiz.statEntreno === "pv" ? entrenoAguante
                                              : raiz.statEntreno === "def" ? entrenoBloqueo
                                              : entrenamiento)
                           : raiz.cazando ? enCaza
                           : raiz.escena === "bolsa" ? pantallaBolsa
                           : raiz.escena === "objetivos" ? pantallaObjetivos
                           : raiz.escena === "mercado" ? pantallaMercado
                           : raiz.escena === "pvp" ? pantallaPvp
                           : raiz.escena === "estado" ? pantallaEstado
                           : raiz.escena === "mapa" ? pantallaMapa
                           : raiz.escena === "evolucion" ? pantallaEvolucion
                           : raiz.escena === "entreno" ? pantallaEntreno
                           : raiz.escena === "huevos" ? pantallaHuevos
                           : raiz.escena === "banco" ? pantallaBanco
                           : raiz.escena === "lista" ? pantallaLista
                           : pantallaBicho
        }
    }

    //  El símbolo de la última acción, subiendo y desvaneciéndose. Va aquí
    //  arriba, sobre la pantalla, para que valga sea cual sea la que esté
    //  puesta: la bolsa, la caza o el mapa. Es lo único que hace que una
    //  acción hecha desde un menú no sea muda.
    //
    //  Glifo y no Etiqueta: son iconos de la Nerd Font y con la tipografía de
    //  texto salen como cuadraditos.
    K4.Glifo {
        id: globoAccion
        readonly property real _base: aparato.width * 0.95 * 0.42
        anchors.horizontalCenter: parent.horizontalCenter
        y: _base
        text: raiz._simboloAccion
        font.pixelSize: 22
        color: "#e8f4ea"
        opacity: 0
        z: 7
        //  Sin ratón encima: es un adorno, y tragarse un clic del jugador
        //  justo donde acaba de pasar algo sería lo contrario de ayudar.
        visible: opacity > 0
    }

    ParallelAnimation {
        id: subeGlobo
        NumberAnimation {
            target: globoAccion; property: "y"; duration: 900
            to: globoAccion._base - 34; easing.type: Easing.OutQuad
        }
        NumberAnimation { target: globoAccion; property: "opacity"; duration: 900; to: 0 }
    }

    //  El marcador del duelo, mientras dura. Va fuera de la pantalla de
    //  combate porque el combate no sabe que es parte de una serie: lo suyo es
    //  un asalto, y quién va ganando es cosa del duelo.
    Rectangle {
        visible: raiz.enDuelo && raiz.combate !== ""
        anchors.horizontalCenter: parent.horizontalCenter
        y: 14
        width: marcador.implicitWidth + 16
        height: 18
        radius: 9
        color: "#0a1420"
        border.width: 1
        border.color: "#4a6a9a"
        z: 6

        //  En dos trozos y no en uno: `Idioma.f` solo sustituye %1 y %2, así
        //  que el marcador de cuatro cifras salía con «%3–%4» literal en
        //  pantalla. Se vio jugando el primer duelo.
        K4.Etiqueta {
            id: marcador
            anchors.centerIn: parent
            text: Idioma.f(Idioma.t("Duelo · asalto %1 de %2"),
                           Digivice.pvpAsalto + 1, Digivice.pvpAsaltos)
                + "   " + Digivice.pvpMios + "–" + Digivice.pvpSuyos
            font.pixelSize: 11
            color: "#bcd4f0"
        }
    }

    //  Y el resultado, cuando se acaba.
    Rectangle {
        visible: raiz.carteDuelo !== ""
        anchors.centerIn: parent
        width: cartelD.implicitWidth + 26
        height: 30
        radius: 15
        color: "#0a1420"
        border.width: 1
        border.color: "#7de08a"
        z: 8

        K4.Etiqueta {
            id: cartelD
            anchors.centerIn: parent
            text: raiz.carteDuelo
            font.pixelSize: 13
            font.weight: Font.Bold
            color: "#d8f0de"
        }
    }

    //  El aviso, encima de la pantalla y por dos segundos. Va aquí y no
    //  dentro de cada pantalla porque puede saltar desde cualquiera.
    Rectangle {
        visible: raiz.aviso !== "" && raiz.combate === "" && !raiz.entrenando
                 && !raiz.cazando
        anchors.horizontalCenter: parent.horizontalCenter
        y: aparato.width * 0.95 * 0.60
        width: Math.min(parent.width - 50, textoAviso.implicitWidth + 20)
        height: 22
        radius: 11
        color: "#0a1a10"
        border.width: 1
        border.color: "#3f7a52"
        z: 5

        K4.Etiqueta {
            id: textoAviso
            anchors.centerIn: parent
            text: raiz.aviso
            font.pixelSize: 11
            color: "#cfe8d6"
        }
    }

    // ── las pantallas ─────────────────────────────────────────────
    Component {
        id: cargando
        Item {
            K4.Etiqueta {
                anchors.centerIn: parent
                text: Idioma.t("Cargando…")
                font.pixelSize: 12
                color: "#8fbf9c"
            }
        }
    }

    Component {
        id: sinPartida
        Item {
            //  Sin criatura hay dos estados muy distintos, y antes se
            //  enseñaba el mismo botón para los dos: **un huevo incubando** —
            //  que es como empieza toda partida— y **nada de nada**.
            Column {
                anchors.centerIn: parent
                spacing: 6
                visible: Digivice.hayIncubacion

                Huevo {
                    anchors.horizontalCenter: parent.horizontalCenter
                    lado: 72
                    progreso: Digivice.progresoIncubacion
                    rompiendo: raiz.rompiendo
                }

                K4.Etiqueta {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Digivice.huevoListo ? Idioma.t("¡Está rompiendo!")
                                              : Idioma.t("Incubando…")
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    color: Digivice.huevoListo ? "#e8b45a" : "#9fd8ae"
                }

                //  La barra dice cuánto falta sin dar un número: el huevo ya
                //  lo cuenta meneándose más deprisa.
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 120; height: 4; radius: 2
                    color: "#1a2f20"

                    Rectangle {
                        width: parent.width * Digivice.progresoIncubacion
                        height: parent.height
                        radius: 2
                        color: Digivice.huevoListo ? "#e8b45a" : "#7de08a"
                        Behavior on width { NumberAnimation { duration: 300 } }
                    }
                }

                K4.Etiqueta {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 190
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: Digivice.huevoListo
                        ? Idioma.t("B lo abre")
                        : Idioma.t("Usa el ordenador: el huevo rompe andando")
                    font.pixelSize: 11
                    color: "#5f8f6c"
                }
            }

            Column {
                anchors.centerIn: parent
                spacing: 10
                visible: !Digivice.hayIncubacion

                K4.Etiqueta {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Idioma.t("Sin huevo")
                    font.pixelSize: 13
                    color: "#8fbf9c"
                }

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 110; height: 26; radius: 13
                    color: "#2f6b40"

                    K4.Etiqueta {
                        anchors.centerIn: parent
                        text: Idioma.t("Poner uno")
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Digivice.nuevaPartida()
                    }
                }
            }
        }
    }

    Component { id: pantallaBicho; PantallaBicho {} }
    Component { id: pantallaEstado; PantallaEstado {} }
    Component {
        id: pantallaMapa
        PantallaMapa { onPelear: function (id) { raiz.combate = id } }
    }
    Component { id: pantallaLista; PantallaLista { cursor: raiz.cursorLista } }
    Component { id: pantallaBanco; PantallaBanco { cursor: raiz.cursorLista } }
    Component { id: pantallaHuevos; PantallaHuevos { cursor: raiz.cursorLista } }
    Component {
        id: pantallaEvolucion
        PantallaEvolucion {
            cursor: raiz.cursorLista
            onFusionar: function (hueco) { Digivice.fusionar(hueco) }
        }
    }

    Component {
        id: pantallaEntreno
        PantallaEntreno {
            zumbador: zumbador
            cursor: raiz.cursorLista
            onEmpezar: function (stat) {
                if (Digivice.avisarSiNoEntrena())
                    return
                raiz.statEntreno = stat
                raiz.entrenando = true
            }
        }
    }

    Component {
        id: entrenoAguante
        Aguante {
            zumbador: zumbador
            onTerminado: function (aciertos) {
                Digivice.entrenar(raiz.statEntreno, aciertos)
                raiz.entrenando = false
            }
        }
    }

    Component {
        id: entrenoBloqueo
        Bloqueo {
            zumbador: zumbador
            onTerminado: function (aciertos) {
                Digivice.entrenar(raiz.statEntreno, aciertos)
                raiz.entrenando = false
            }
        }
    }

    Component {
        id: entrenoPelota
        Pelota {
            onTerminado: function (aciertos) {
                Digivice.entrenar(raiz.statEntreno, aciertos)
                zumbador.sonar(aciertos > 0 ? "acierto" : "fallo")
                raiz.entrenando = false
            }
        }
    }

    Component {
        id: entrenamiento
        Entrenamiento {
            zumbador: zumbador
            onTerminado: function (aciertos) {
                Digivice.entrenar(raiz.statEntreno, aciertos)
                raiz.entrenando = false
            }
        }
    }

    Component {
        id: pantallaBolsa
        PantallaBolsa { cursor: raiz.cursorLista }
    }

    Component {
        id: pantallaObjetivos
        PantallaObjetivos { cursor: raiz.cursorLista }
    }

    Component {
        id: pantallaMercado
        PantallaMercado { cursor: raiz.cursorLista }
    }

    Component {
        id: pantallaPvp
        PantallaPvp {
            cursor: raiz.cursorLista
            onPelear: raiz.empezarDuelo()
        }
    }

    Component {
        id: enCaza
        Caza {
            zumbador: zumbador
            onTerminado: raiz.cazando = false
        }
    }

    Component {
        id: enCombate
        Combate {
            //  En un duelo pelea el equipo, no siempre el que llevas encima.
            pvp: raiz.enDuelo
            mio: raiz.enDuelo && Digivice.miEquipo.length > Digivice.pvpAsalto
               ? Digivice.miEquipo[Digivice.pvpAsalto].especie : Digivice.especie
            entrenosMios: raiz.enDuelo && Digivice.miEquipo.length > Digivice.pvpAsalto
               ? Digivice.miEquipo[Digivice.pvpAsalto].entrenos : null
            entrenosSuyos: raiz.enDuelo && Digivice.rivalEquipo.length > Digivice.pvpAsalto
               ? Digivice.rivalEquipo[Digivice.pvpAsalto].entrenos : null
            zumbador: zumbador
            enemigo: raiz.combate
            //  Huir cierra el combate sin victoria ni derrota: el servicio ya
            //  consumió el encuentro y cobró la energía.
            onHuido: {
                raiz.combate = ""
                zumbador.sonar("atras")
            }
            onTerminado: function (gane) {
                //  El id ANTES de vaciarlo: vaciarlo primero y usarlo después
                //  le pasaba una cadena vacía a `aplicarResultado`, o sea que
                //  ganar un combate normal no cobraba nada.
                const quien = raiz.combate
                raiz.combate = ""
                //  Un asalto de duelo NO se cobra como un combate del mundo:
                //  ni da experiencia, ni datos, ni bits, ni cuenta para los
                //  jefes. Si contara, pegar el código de un amigo en bucle
                //  sería la mejor manera de jugar a todo lo demás.
                if (raiz.enDuelo) {
                    Digivice.anotarAsalto(gane)
                    raiz._siguienteAsalto()
                    return
                }
                Digivice.aplicarResultado(quien, gane)
            }
        }
    }
}
