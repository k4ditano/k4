//  El Digivice: la island, el IPC y el ciclo de vida.
//
//  Aquí no hay reglas. Las reglas están en services/Digivice.qml y las puras
//  en services/DigiviceReglas.js; esto solo abre, cierra y traduce gestos a
//  llamadas al servicio. Si algo de este fichero decide cuánta hambre pasa un
//  bicho, está en el sitio equivocado.

import QtQuick
import K4 as K4
import "../../core"
import "../../services"

K4Plugin {
    id: self

    name: "digivice"
    title: "Digivice"
    priority: 63
    active: habilitado && abierto

    //  Teclas mientras el ratón esté encima, que es cuando se juega.
    //
    //  Con `tecladoOpcional` esto se quedó sin ESC: «bajo demanda» significa
    //  que el compositor da el teclado solo si PINCHAS la superficie, así que
    //  abierto por IPC o por atajo no llegaba una tecla. Y `grabKeyboard` no
    //  vale para un juego que se queda abierto: dejaría el escritorio entero
    //  sin escribir.
    tecladoAlPasar: abierto

    property bool abierto: false

    //  La island NO es un panel con un aparato dentro: es el aparato.
    //
    //  Estrecha y alta, colgando de la barra. Sale gratis porque la silueta
    //  que dibuja el host ya tiene lo que hace falta —esquinas de 32 abajo y
    //  «alas» arriba que se funden con el borde— así que su fondo hace de
    //  carcasa y no hay dos juegos de esquinas peleándose. El tope del host
    //  son 880 de alto, así que 430 va sobrado.
    islandWidth: 300
    //  Calculada y no puesta a ojo: 8 de margen, la pantalla —que es casi
    //  cuadrada sobre el ancho útil—, la leyenda, los botones y la correa.
    //  Con un número a mano sobraban 80 px de cuerpo vacío.
    islandHeight: Math.round(4 + (islandWidth - 28) * 0.95 + 111)

    //  Sin esto, un clic en cualquier hueco de la vista abre el centro de
    //  control: es lo que hace el host cuando el plugin no reclama el fondo.
    //  En un juego donde se clica por todas partes —el minijuego se juega a
    //  clic— eso es insufrible. Aquí se traga: salir es cosa del aspa y del
    //  ESC, que para eso están.
    handlesBackgroundTap: true
    onBackgroundTapped: {}

    //  Lo último que pasó con la barra cerrada, para poder contarlo al abrir.
    property var resumenOffline: null

    //  El sonido se puede apagar, y por eso vive en Ajustes y no en el juego.
    //  Un plugin que hace ruido en la barra de alguien y no se puede callar
    //  es un plugin que se desinstala.
    property bool conSonido: true

    property var misAjustes: K4.Ajustes {
        plugin: "digivice"
        grupo: Idioma.t("Digivice")
        opciones: [
            { id: "conSonido", nombre: Idioma.t("Sonido del aparato"),
              desc: Idioma.t("Los pitidos de los botones, el combate y la evolución"),
              glifo: 0xF057E }
        ]
        valores: ({ conSonido: self.conSonido })
        onCambiado: function (id, valor) {
            if (id === "conSonido") {
                self.conSonido = valor
                self._apuntar()
            }
        }
    }

    property var guardado: K4.Guardado {
        plugin: "digivice"
        nombre: "ajustes"
        onCargado: function (d) { self.conSonido = d.conSonido !== false }
    }

    function _apuntar() { guardado.guardar({ conSonido: conSonido }) }

    function toggle() {
        abierto = !abierto
        if (abierto)
            resumenOffline = _pendiente
    }

    //  El host cierra el módulo activo con ESC llamando justo a esto. Sin
    //  `close()` la tecla no hace NADA —el host comprueba que la función
    //  exista— y la vista se convierte en una trampa: se abre y no se sale.
    //  Que faltara no daba ningún error, que es lo que costó verlo.
    function close() {
        abierto = false
    }

    //  Ya no hay pestañas: lo que se elige es qué enseña la pantalla.
    property string escenaPedida: ""

    function ver(p) {
        escenaPedida = p
        abierto = true
    }

    property var _pendiente: null

    //  El zumbador lo crea la vista; el plugin solo lo guarda para poder
    //  preguntarle si cargó.
    property var zumbador: null

    view: Component { DigiviceView { plugin: self } }

    Connections {
        target: Digivice
        function onRecuperado(resumen) { self._pendiente = resumen }

        //  La píldora es la voz del bicho con la barra plegada. Solo habla
        //  cuando hay algo que hacer: un indicador que siempre grita deja de
        //  significar nada.
        function onDescuido(motivo) { self._refrescarPildora() }
        function onEnfermo_(si) { self._refrescarPildora() }
        function onEvoluciono(antes, ahora) { self._refrescarPildora() }
        //  Vaciarse un medidor no emite señal propia —es una resta en un
        //  tick— y es justo el momento en que el bicho tiene algo que decir.
        function onHambreChanged() { self._refrescarPildora() }
        function onAnimoChanged() { self._refrescarPildora() }
        function onEspecieChanged() { self._refrescarPildora() }
        function onEnemigoPendienteChanged() { self._refrescarPildora() }
    }

    function _refrescarPildora() {
        if (!Digivice.hayPartida) {
            K4.Pildora.quitar("digivice.estado")
            return
        }
        //  La cacería cuenta: la carretera la puso delante y se queda
        //  parada hasta que la resuelvas. Un camino detenido sin avisar es
        //  progreso perdido en silencio.
        const reclama = Digivice.enfermo || Digivice.hambre === 0
                     || Digivice.animo === 0 || Digivice.puedeEvolucionar()
                     || Digivice.encuentroPendiente || Digivice.caceria !== null
        if (!reclama) {
            K4.Pildora.quitar("digivice.estado")
            return
        }
        const texto = Digivice.enfermo ? Idioma.t("enfermo")
                    : Digivice.puedeEvolucionar() ? Idioma.t("evoluciona")
                    : Digivice.encuentroPendiente ? Idioma.t("combate")
                    : Digivice.caceria !== null ? Idioma.t("rastro")
                    : Digivice.hambre === 0 ? Idioma.t("hambre")
                    : Idioma.t("triste")
        K4.Pildora.registrar("digivice.estado", texto, 0xF06D3,
                             Digivice.enfermo ? K4.Tema.rojo : K4.Tema.amarillo,
                             63, true)
    }

    //  Pinchar el aviso te lleva al juego, y a la pestaña que toca: si lo que
    //  reclama es un combate, al mapa —que es donde se pelea—; si es hambre o
    //  una evolución, al bicho. Un indicador que te dice que pasa algo y no te
    //  lleva a ello te obliga a buscarlo tú, que es trabajo que ya había hecho
    //  la barra.
    //
    //  Con la island en reposo la píldora no se pincha (así lo quiere
    //  PluginPildora: en reposo solo se mira); al acercar el ratón, la island
    //  pasa a reloj o reproductor y ahí sí.
    property var _clicPildora: Connections {
        target: K4.Pildora
        function onInvocado(id) {
            if (id !== "digivice.estado")
                return
            self.ver(Digivice.encuentroPendiente || Digivice.caceria
                     ? "mapa" : "bicho")
        }
    }

    Component.onCompleted: _refrescarPildora()

    K4.Ipc {
        target: "k4.digivice"
        function toggle(): void { self.toggle() }
        function close(): void { self.close() }
        function nueva(): void { Digivice.nuevaPartida(); self._refrescarPildora() }
        function incubar(i: int): string {
            const l = Digivice.huevosDisponibles
            if (i < 0 || i >= l.length)
                return "no hay huevo en ese hueco"
            return Digivice.incubar(l[i]) ? "incubando " + Digivice.nombreDe(l[i])
                                          : "no se pudo"
        }
        function eclosionar(): string {
            return Digivice.eclosionar() ? "ha nacido " + Digivice.nombreDe(Digivice.especie)
                                         : "el huevo no está listo"
        }
        function huevos(): string {
            if (Digivice.hayIncubacion)
                return "incubando " + Digivice.nombreDe(Digivice.incubando)
                     + " · " + Digivice.pasosIncubados + "/" + Digivice.pasosParaEclosionar
                     + (Digivice.huevoListo ? " · ¡listo!" : "")
            const l = Digivice.huevosDisponibles
            if (l.length === 0)
                return "sin huevos: gana combates para capturar datos"
            return l.map(function (k, i) { return i + ": " + Digivice.nombreDe(k) }).join(" · ")
        }

        function fusiones(): string {
            const l = Digivice.fusionesPosibles
            if (l.length === 0)
                return "ninguna fusión posible con la guardería"
            return l.map(function (f) {
                return f.hueco + ": +" + Digivice.nombreDe(f.con)
                     + " = " + Digivice.nombreDe(f.da)
            }).join(" · ")
        }
        function fusionar(i: int): string {
            return Digivice.fusionar(i) ? "fusionado: " + Digivice.nombreDe(Digivice.especie)
                                        : "no hacen pareja"
        }

        function guarderia(): string {
            if (Digivice.banco.length === 0)
                return "la guardería está vacía"
            let out = []
            for (let i = 0; i < Digivice.banco.length; ++i) {
                const f = Digivice.datoDe(Digivice.banco[i].especie)
                out.push(i + ": " + (f ? f.n + " (" + f.l + ")" : "?"))
            }
            return out.join(" · ")
        }
        function sacar(i: int): string {
            return Digivice.cambiarA(i) ? "sacado" : "no hay nadie en ese hueco"
        }
        function ver(p: string): void { self.ver(p) }
        function comer(): void { Digivice.alimentar() }
        function mimar(): void { Digivice.mimar() }
        function entrenar(stat: string): void { Digivice.entrenar(stat, 2) }
        function dificultad(): string {
            Digivice.cambiarDificultad()
            return Digivice.dificultad
        }
        function curar(): void { Digivice.curar() }
        function limpiar(): void { Digivice.limpiar() }
        function evolucionar(): void { Digivice.evolucionar() }
        function zona(z: string): void { Digivice.cambiarZona(z) }

        //  Pelear sin ratón: resuelve el encuentro que espera y cuenta cómo
        //  fue. La vista lo enseña con animación; esto es para jugar desde la
        //  terminal y para poder probar el combate sin clicar.
        function pelear(): string {
            const c = Digivice.tomarEncuentro()
            if (!c)
                return Idioma.t("no hay ningún encuentro esperando")
            Digivice.aplicarCombate(c)
            const f = Digivice.datoDe(c.enemigo)
            //  Un recuento de lo que ha pasado dentro, no solo quién ganó:
            //  con formas y estados, «derrota en 10 turnos» ya no cuenta el
            //  combate, y sin esto no hay manera de ver desde fuera si el
            //  veneno prendió o si el aliado llegó a salir.
            let formas = {}
            let estados = 0
            for (let i = 0; i < c.turnos.length; ++i) {
                const t = c.turnos[i]
                if (t.forma) formas[t.forma] = (formas[t.forma] || 0) + 1
                if (t.estado) estados += 1
            }
            const reparto = Object.keys(formas).map(function (k) {
                return k + "×" + formas[k]
            }).join(" ")
            return (c.gane ? Idioma.t("victoria") : Idioma.t("derrota"))
                 + " contra " + (f ? f.n : "?")
                 + " en " + c.turnos.length + " turnos"
                 + " · " + c.restanteMia + "/" + c.vidaMia + " PV"
                 + (reparto ? " · " + reparto : "")
                 + (estados ? " · " + estados + " estados" : "")
                 + (c.aliadoUsado ? " · salió el aliado" : "")
        }

        //  La carretera: lo andado, lo que viene y a qué distancia. Sin esto
        //  no hay manera de ver desde fuera si la expedición avanza.
        function camino(): string {
            if (!Digivice.hayPartida)
                return "sin partida"
            const h = Digivice.siguienteHito
            return Digivice.zona + ": " + Digivice.distanciaZona
                 + "/" + Digivice.distanciaJefeZona
                 + " · vuelta " + (Digivice.vueltaDe(Digivice.zona) + 1)
                 + (Digivice.vueltaCerrada(Digivice.zona) ? " · terminada" : "")
                 + (h ? "  ·  próximo hito en " + h.en
                        + (h.jefe ? " (JEFE)" : " (" + h.evento + ")") : "")
        }

        function rehacer(): string {
            return Digivice.rehacerCamino(Digivice.zona)
                 ? "camino rehecho · vuelta "
                   + (Digivice.vueltaDe(Digivice.zona) + 1)
                 : "todavía no se puede rehacer"
        }

        //  Andar a mano, para probar sin tener que cambiar de ventana veinte
        //  veces. `gesto` es ventana, escritorio, app o reloj.
        function andar(gesto: string, veces: int): string {
            const n = Math.max(1, Math.min(500, veces || 1))
            for (let i = 0; i < n; ++i)
                Digivice.darPaso(gesto || "ventana")
            return camino()
        }

        // ── duelo por código ──────────────────────────────────────
        function codigo(): string {
            if (!Digivice.hayPartida)
                return "sin partida"
            return Digivice.miCodigo + "  ("
                 + Digivice.miEquipo.map(function (c) {
                       return Digivice.nombreDe(c.especie)
                   }).join(", ") + ")"
        }

        //  Leer un código sin pelear: para comprobar que lo que te han pasado
        //  es lo que crees ANTES de gastar tres asaltos en averiguarlo.
        function leer(cod: string): string {
            const r = Digivice.leerCodigo(cod)
            if (r.error)
                return "no vale: " + r.error
            return r.equipo.map(function (c) {
                return Digivice.nombreDe(c.especie) + " ("
                     + c.entrenos.pv + "/" + c.entrenos.atq + "/"
                     + c.entrenos.def + "/" + c.entrenos.vel + ")"
            }).join(" · ")
        }

        //  El duelo entero sin manos, para probarlo desde la terminal. La
        //  versión jugada usa la misma pantalla de combate de siempre.
        function duelo(cod: string): string {
            if (!Digivice.retar(cod))
                return "no se ha podido retar"
            const partes = []
            while (!Digivice.pvpDecidido) {
                const r = Digivice.resolverAsalto()
                if (!r) break
                partes.push(Digivice.nombreDe(r.mio) + " vs "
                          + Digivice.nombreDe(r.suyo) + ": "
                          + (r.gane ? "gano" : "pierdo"))
                Digivice.anotarAsalto(r.gane)
            }
            const m = Digivice.pvpMios, s = Digivice.pvpSuyos
            Digivice.cerrarDuelo()
            return partes.join(" · ") + "  →  " + m + "-" + s
                 + (m > s ? " ¡GANADO!" : " perdido")
                 + " · bits " + Digivice.bits
        }

        // ── el meta-juego ─────────────────────────────────────────
        function objetivos(): string {
            return Digivice.objetivos.map(function (e) {
                return (e.cobrado ? "✓ " : e.cobrable ? "¡COBRA! " : "")
                     + e.obj.id + " " + e.hay + "/" + e.meta
            }).join(" · ")
        }

        function cobrar(id: string): string {
            if (!Digivice.cobrarObjetivo(id))
                return "no se puede cobrar ese objetivo"
            return "cobrado · bits " + Digivice.bits
        }

        function bolsa(): string {
            const l = Digivice.bolsa
            if (l.length === 0)
                return "vacía"
            return "bits " + Digivice.bits + " · " + l.map(function (e) {
                return e.nombre + (e.cuantas < 0 ? " ∞" : " ×" + e.cuantas)
            }).join(" · ")
        }

        function comprar(id: string): string {
            if (!Digivice.comprar(id))
                return "no se ha podido comprar"
            return "comprado · quedan " + Digivice.bits + " bits"
        }

        function vender(id: string): string {
            if (!Digivice.vender(id))
                return "no se ha podido vender"
            return "vendido · tienes " + Digivice.bits + " bits"
        }

        function usar(id: string, cual: string): string {
            if (!Digivice.usarObjeto(id, cual || "atq"))
                return "no se ha podido usar"
            return "usado · " + Digivice.nombreObjeto(id)
        }

        //  Las cinco vías de evolución que tengas abiertas ahora mismo. Sin
        //  esto no hay manera de saber desde fuera si un digimental sirve
        //  para algo con el bicho que llevas.
        function vias(): string {
            const v = []
            if (Digivice.puedeEvolucionar()) v.push("normal")
            if (Digivice.puedeWarp) v.push("warp -> " + Digivice.nombreDe(Digivice.warpsPosibles[0]))
            const ar = Digivice.armoresPosibles
            for (let i = 0; i < ar.length; ++i)
                v.push("armor(" + ar[i].dig + ") -> " + Digivice.nombreDe(ar[i].da))
            if (Digivice.puedeX) v.push("x -> " + Digivice.nombreDe(Digivice.formaX))
            const f = Digivice.fusionesPosibles
            for (let j = 0; j < f.length; ++j)
                v.push("jogress+" + Digivice.nombreDe(f[j].con) + " -> " + Digivice.nombreDe(f[j].da))
            return v.length ? v.join(" · ") : "ninguna vía abierta"
        }

        function armor(i: int): string {
            return Digivice.evolucionarArmor(i)
                 ? "Armor: " + Digivice.nombreDe(Digivice.especie) : "no se ha podido"
        }
        function equis(): string {
            return Digivice.evolucionarX()
                 ? "X: " + Digivice.nombreDe(Digivice.especie) : "no se ha podido"
        }
        function warp(): string {
            return Digivice.evolucionarWarp(0)
                 ? "Warp: " + Digivice.nombreDe(Digivice.especie) : "no se ha podido"
        }

        // ── la comida ─────────────────────────────────────────────
        function despensa(): string {
            const l = Digivice.despensaVisible
            if (l.length === 0)
                return "vacía"
            return l.map(function (e) {
                return e.comida.nombre
                     + (e.cuantas < 0 ? " ∞" : " ×" + e.cuantas)
            }).join(" · ")
        }

        //  `comer` sin argumento da la ración de siempre, que es lo que hacía
        //  antes de que hubiera despensa: los atajos de quien ya la usaba no
        //  pueden dejar de funcionar por añadir variedad.
        function comerDe(id: string): string {
            const c = Digivice.comidaPorId(id)
            if (!c)
                return "no existe esa comida"
            if (!Digivice.alimentarCon(id))
                return "no ha podido comérsela"
            return c.nombre + " · hambre " + Digivice.hambre
                 + "/" + Digivice.maxCorazones + " · peso " + Digivice.peso
                 + (Digivice.envenenado ? " · ENVENENADO" : "")
                 + (Digivice.vigor > 0 ? " · vigor " + Digivice.vigor : "")
        }

        //  Olfatear: gastar rastro en descartar una huella mala más.
        function olfatear(): string {
            if (!Digivice.olfatear())
                return "no se puede olfatear ahora"
            const c = Digivice.caceria
            return c.rastros.map(function (r, i) {
                return i + ": " + (r.marcado ? "descartado" : "?")
            }).join(" · ") + "  (rastro " + Digivice.rastro + ")"
        }

        //  Huir del combate que tengas delante, pagando energía.
        function huir(): string {
            if (!Digivice.huir())
                return Digivice.encuentroPendiente
                     ? "sin energía para escapar" : "no hay de qué huir"
            return "escapado · energía " + Digivice.energia
        }

        //  El minijuego de los rastros, cuando la carretera lo pone delante.
        function rastro(i: int): string {
            const r = Digivice.elegirRastro(i)
            if (!r)
                return "no hay ningún rastro delante"
            const c = Digivice.comidaPorId(r.comida)
            return (r.malo ? "mal rastro: " : "encontrado: ")
                 + (c ? c.nombre : r.comida)
        }

        //  Qué formas tienes abiertas ahora mismo. Es lo que decide si el
        //  selector del combate aparece o no, así que hace falta poder verlo
        //  sin abrir la pantalla.
        function tecnicas(): string {
            const l = Digivice.tecnicasFormas
            if (!l || l.length === 0)
                return "ninguna"
            return l.map(function (t) {
                return t.nombre + " (" + t.forma + ")"
            }).join(" · ")
        }

        //  Quién sale a ayudar y qué haría. Sin esto no hay manera de saber
        //  si la guardería está eligiendo bien al aliado.
        function aliado(): string {
            const a = Digivice.aliado
            if (!a)
                return "la guardería está vacía"
            const g = Digivice.golpeDelAliado(Digivice.especie)
            return a.nombre + " (" + a.etapa + ", hueco " + a.hueco + ")"
                 + (g ? " · " + (g.tecnica || "golpe") + " " + g.forma
                        + " ≈" + g.daño + " de daño"
                        + (g.estado ? " · deja " + g.estado : "")
                      : "")
                 + " · cuesta " + Digivice.costeLlamada
                 + (Digivice.puedeLlamar ? "" : " (sin energía)")
        }

        //  Disparar un sonido a mano: para probar sin jugar, y para que
        //  quien no oiga nada pueda averiguar si es el fichero o el altavoz.
        function pitar(nombre: string): string {
            if (!self.zumbador)
                return "la vista no está abierta"
            self.zumbador.sonar(nombre)
            return "sonando " + nombre
        }

        function sonidos(): string {
            return self.zumbador ? self.zumbador.diagnostico()
                                 : "la vista no está abierta"
        }

        function estado(): string {
            if (!Digivice.hayPartida) {
                //  «Sin partida» a secas era mentira desde que una partida
                //  empieza por un huevo: hay partida, lo que no hay todavía
                //  es criatura.
                if (Digivice.hayIncubacion)
                    return "huevo de " + Digivice.nombreDe(Digivice.incubando)
                         + " · " + Digivice.pasosIncubados + "/"
                         + Digivice.pasosParaEclosionar
                         + (Digivice.huevoListo ? " · ¡listo!" : " · incubando")
                return "sin huevo"
            }
            const f = Digivice.ficha
            return (f ? f.n : "?") + " · " + Digivice.etapa
                 + " · hambre " + Digivice.hambre + "/" + Digivice.maxCorazones
                 + " · ánimo " + Digivice.animo + "/" + Digivice.maxCorazones
                 + " · PV" + Digivice.entrenoDe("pv")
                 + "/ATQ" + Digivice.entrenoDe("atq")
                 + "/DEF" + Digivice.entrenoDe("def")
                 + "/VEL" + Digivice.entrenoDe("vel")
                 + " (tope " + Digivice.topeEntreno + ")"
                 + " · peso " + Digivice.peso + "/" + Digivice.pesoMinimo
                 + " · suciedad " + Digivice.suciedad
                 + " · energía " + Digivice.energia + "/" + Digivice.maxEnergia
                 + " · zona " + Digivice.zona
                 + " (" + Digivice.distanciaZona + "/"
                 + Digivice.distanciaJefeZona
                 + (Digivice.jefeVencido(Digivice.zona) ? " ★" : "") + ")"
                 + " · jefes " + Digivice.jefesCaidos + "/9"
                 + " · xp " + Digivice.xp
                 + (Digivice.falta ? " (faltan " + Digivice.falta.minutos + "min/"
                                   + Digivice.falta.victorias + "V/"
                                   + Digivice.falta.xp + "xp)" : " (cima)")
                 + " · criados " + Digivice.cuantosCriados
                 + " · guardería " + Digivice.banco.length + "/" + Digivice.maxBanco
                 + (Digivice.jefePendiente ? " · ¡JEFE!" : "")
                
                 + " · " + Digivice.caracter.nombre
                 + " · " + Digivice.animo_
                 + " · rastro " + Digivice.rastro
                 + " · bits " + Digivice.bits
                 + (Digivice.objetivosCobrables > 0
                    ? " · " + Digivice.objetivosCobrables + " objetivos que cobrar" : "")
                 + (Digivice.enfermo ? " · enfermo" : "")
                 + (Digivice.envenenado ? " · ENVENENADO" : "")
                 + (Digivice.vigor > 0 ? " · vigor " + Digivice.vigor : "")
                 + (Digivice.durmiendo ? " · durmiendo" : "")
                 + " · " + Digivice.victorias + "V/" + Digivice.derrotas + "D"
        }
    }
}
