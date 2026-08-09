pragma Singleton

//  El Digivice: criar un Digimon en la barra.
//
//  Vive aquí y no en el plugin por la misma razón que la mazmorra: una
//  criatura que solo tiene hambre cuando la miras no es una criatura. El
//  hambre corre con la barra cerrada; lo que no corre es la muerte.
//
//  Es una adaptación original. No carga nada del emulador de dispositivos
//  que sirvió para entender las reglas —ni su código, ni sus gráficos, ni
//  sus datos— y los datos de especies vienen de digi-api.com (CC-BY-SA 3.0,
//  sobre todo de Wikimon). Las imágenes son de Bandai y por eso NO se
//  empaquetan: se descargan a la caché del usuario la primera vez que hacen
//  falta. Cambiar de arte es cambiar `rutaImagen`, no reescribir el juego.
//
//  El grafo de evolución sale de la API, que es enciclopédica y no de juego:
//  las evoluciones de Agumon incluyen a Agnimon y a Agumon (Black) X. Por eso
//  todo candidato se filtra por escalón —solo se sube un peldaño cada vez— y
//  se ordena de forma determinista para que la misma crianza dé el mismo
//  bicho.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import K4 as K4
import "DigiviceReglas.js" as Reglas

Singleton {
    id: dv

    // ── la escalera ───────────────────────────────────────────────
    //  Nomenclatura japonesa porque es la que usa la API. Armor, Hybrid y
    //  Unknown existen en los datos y quedan FUERA a propósito: son ramas
    //  laterales sin peldaño siguiente, y meterlas en la escalera es
    //  regalar callejones sin salida.
    //
    //  Las reglas puras viven en DigiviceReglas.js —lo que sigue solo las
    //  ata al estado— para que se puedan probar sin arrancar la barra.
    readonly property var escalera: Reglas.ESCALERA

    // ── cuidado ───────────────────────────────────────────────────
    readonly property int maxCorazones: 4
    //  Vaciar los cuatro corazones cuesta 2 h de hambre y 2 h 40 de ánimo.
    //  Descompasados adrede: si cayeran a la vez, atender sería un solo gesto
    //  y no habría nada que administrar.
    //  Medido con `tools/digivice_balance.js`. Los números de antes —30 y 40—
    //  vaciaban los corazones en 2 h y hacían REGRESAR de etapa a las 3 h 20
    //  de no tocarlo. Para un bicho que vive en una barra que no se mira eso
    //  no es exigente, es roto: te ibas a comer y volvías con la crianza de
    //  horas deshecha. Le pasó de verdad, dos veces, durante las pruebas.
    //
    //  Con 60 y 80 el hambre se vacía en 4 h —lo atiendes dos o tres veces al
    //  día, que es lo que puede pedir un cacharro de escritorio— y el fondo
    //  del abandono queda a 9 h 20, por encima de una jornada de trabajo y
    //  por encima del tope de 8 h de progreso con la barra cerrada.
    //  La vigilia: dentro de esta ventana ocurre todo lo del cuidado. Fuera,
    //  el bicho duerme y no se le pide nada — que es lo que antes había que
    //  tratar como un caso aparte y ahora sale solo de no tener agenda ahí.
    readonly property int minutosVigilia: (24 - duermeDesde + duermeHasta) * 60

    //  La semilla de la agenda: estable por bicho, para que su ritmo sea SUYO
    //  y no cambie al reiniciar la barra. Dos bichos criados a la vez no
    //  piden de comer a la misma hora, que es medio carácter.
    readonly property int _semillaAgenda: {
        let n = 0
        const k = String(especie) + ":" + Math.floor(nacidoEn)
        for (let i = 0; i < k.length; ++i)
            n = (n * 31 + k.charCodeAt(i)) | 0
        return Math.abs(n) % 1000000
    }

    // ── lo que pasa en tu escritorio ──────────────────────────────
    //
    //  El bicho ya vivía DE tu escritorio —los pasos, la carretera, la pelota
    //  cruzando tus ventanas— pero solo lo contaba. Esto es que además se
    //  entere: baila con tu música, se pone nervioso con veinte ventanas
    //  abiertas y se sienta tranquilo cuando llevas un rato concentrado.
    //
    //  `K4.Medios` se puede LEER sin permiso —la API solo lo pide para
    //  controlar la música— y aquí no se mira ni el título ni el artista ni la
    //  aplicación: solo si suena algo. La promesa de no leer nada de tu
    //  escritorio sigue en pie.
    readonly property bool sonandoMusica: K4.Medios.hay && K4.Medios.sonando

    //  Muchas ventanas abiertas: el escritorio hecho un lío.
    readonly property int ventanasAbiertas: _cuantasVentanas
    readonly property bool escritorioLleno: ventanasAbiertas >= 8

    //  Un rato largo sin cambiar de ventana: estás concentrado.
    property real _ahoraCalma: 0
    readonly property bool concentrado: {
        _ahoraCalma          // la dependencia que hace que esto se recalcule
        return hayPartida && _ultimoPasoActividad > 0
            && (ahora() - _ultimoPasoActividad) > 8 * 60
    }

    //  En qué anda el bicho, mirando tu escritorio. El orden es de prioridad:
    //  dormir y estar enfermo mandan sobre todo lo demás.
    //  Bailar CANSA. Alterna tramos de baile y de resuello según su carácter:
    //  un tozudo no piensa parar y un tímido descansa el doble de lo que
    //  baila. Bailar sin fin delataba que no había nadie dentro.
    property bool _resollando: false

    property var _bailePausa: Timer {
        interval: (dv.hayPartida
                   ? (dv._resollando ? dv.caracter.baile.descanso
                                     : dv.caracter.baile.aguante) : 30) * 1000
        repeat: true
        running: dv.hayPartida && dv.sonandoMusica && !dv.durmiendo
        onTriggered: dv._resollando = !dv._resollando
        //  Al dejar de sonar la música vuelve a estar entero, para que la
        //  siguiente canción no le pille a media pausa.
        onRunningChanged: if (!running) dv._resollando = false
    }

    readonly property string animo_: !hayPartida ? ""
            : durmiendo ? "durmiendo"
            : enfermo ? "enfermo"
            : (sonandoMusica && !_resollando) ? "bailando"
            : sonandoMusica ? "resollando"
            : escritorioLleno ? "nervioso"
            : concentrado ? "tranquilo"
            : "normal"

    //  Lo que el aparato tiene que contarte, de más urgente a menos. Sale de
    //  reglas puras: aquí solo se junta el estado.
    readonly property var consejos: hayPartida
            ? Reglas.consejosDe({
                  enfermo: enfermo, envenenado: envenenado,
                  hambre: hambre, animo: animo,
                  suciedad: suciedad, maxSuciedad: maxSuciedad,
                  peso: peso, pesoMinimo: pesoMinimo,
                  encuentro: encuentroPendiente, rastro: caceria !== null,
                  puedeEvolucionar: puedeEvolucionar(),
                  objetivosCobrables: objetivosCobrables,
                  anteElJefe: distanciaZona >= distanciaJefeZona
                              && !vueltaCerrada(zona),
                  caminoAcabado: caminoAcabado,
                  entrenoTotal: entrenoTotal,
                  etapaIdx: Reglas.ESCALERA.indexOf(etapa),
                  banco: banco.length, criados: cuantosCriados,
                  animo_: animo_
              }, caracter.nota, caracter.comoBaila)
            : []

    //  El carácter: sale de la misma semilla que su agenda y su carretera, así
    //  que es SUYO y no cambia al reiniciar. Colorea cuánto pide de comer y de
    //  mimo, y qué le sienta mejor.
    readonly property var caracter: hayPartida ? Reglas.caracterDe(_semillaAgenda)
                                               : Reglas.CARACTERES[0]

    //  Hasta dónde se ha leído ya la agenda. Es un CURSOR, no una deuda: no
    //  puede crecer sin tope, que es exactamente lo que rompía el modelo
    //  anterior.
    property real _cursorCuidado: 0

    //  De un instante a (día, minuto dentro de la vigilia). Los ratos de
    //  sueño se aplastan contra el arranque del día siguiente: si vuelves a
    //  las 3 de la mañana no te has perdido nada, porque a esa hora no había
    //  nada agendado.
    function _puntoAgenda(t) {
        const f = new Date(t * 1000)
        const dia = Math.floor(t / 86400)
        const min = f.getHours() * 60 + f.getMinutes()
        const ini = duermeHasta * 60
        if (min < ini)
            return { dia: dia - 1, min: minutosVigilia }
        const rel = min - ini
        return rel > minutosVigilia ? { dia: dia, min: minutosVigilia }
                                    : { dia: dia, min: rel }
    }
    //  El margen antes de anotar un descuido. Sin él, cerrar el portátil a la
    //  hora de comer ya sería un error de cuidado, y eso es un castigo por
    //  vivir, no por descuidar.
    //  90 min por tramo. Con la agenda, un día «cargado» —el reparto tiene
    //  margen y hay días de 17 comidas— vaciaba los medidores antes y el
    //  peor caso regresaba a las 7,5 h, otra vez dentro de una jornada. Con
    //  90 el peor caso queda en 10 h y enfermar sigue llegando a las 5,5.
    readonly property int minutosGraciaError: 90
    readonly property int erroresParaEnfermar: 3
    //  Y para el fondo del pozo, seis descuidos MÁS. Antes eran tres, y con
    //  dos medidores anotando a la vez eso son veinte minutos: regresar es lo
    //  más caro que hace este juego y no puede dispararse por una reunión.
    readonly property int erroresParaRegresar: erroresParaEnfermar + 6

    // ── suciedad y peso ───────────────────────────────────────────
    //  Las dos cosas que le faltaban al cuidado para tener decisiones. Sin
    //  ellas, alimentar no tiene contrapartida y cuidar se reduce a pulsar un
    //  botón cuando hay hambre, que es la definición de clicker.
    //
    //  El emulador las tiene las dos: `poop_count`, `poop_cycles`,
    //  `additional_poops`, `overfeed_min/max` y `min_weight`.
    readonly property int maxSuciedad: 4
    //  Cada comida acaba en una caca al rato. Veinticinco minutos: lo bastante
    //  para que no sea inmediato y lo bastante poco para que una tarde sin
    //  mirar deje el suelo hecho un desastre.
    readonly property int minutosParaCaca: 25
    //  Lo que aguanta sin recoger antes de contar como descuido.
    readonly property int minutosGraciaSuciedad: 40
    //  Comidas de más seguidas antes de que cuente como descuido. Cebarlo una
    //  vez no es maltrato; hacerlo tres veces sí es no estar mirando.
    readonly property int sobrealimentarMax: 3

    // ── sueño ─────────────────────────────────────────────────────
    //  Con el reloj real: el bicho duerme cuando tú deberías. Molestarlo
    //  dormido cuenta como descuido, igual que en los aparatos.
    readonly property int duermeDesde: 22
    readonly property int duermeHasta: 8

    // ── fuera de la barra ─────────────────────────────────────────
    //  Ocho horas, como la mazmorra. Y una regla que la separa de ella: el
    //  hambre SÍ corre con la barra cerrada, pero la criatura no se muere
    //  sin que la veas. Al fondo del descuido hay enfermedad y regresión
    //  —el aparato original también regresaba—, que duele y se puede
    //  remontar. Matarla a espaldas del jugador sería cobrarle por cerrar
    //  el portátil.
    readonly property int topeOfflineSegundos: 8 * 3600

    // ── zonas ─────────────────────────────────────────────────────
    //  Los "fields" de la API, que son afinidades de especie, se usan como
    //  mapa. Sale gratis y además agrupa bichos que pegan entre sí.
    readonly property var zonas: [
        { id: "Nature Spirits",    nombre: "Bosque Verde" },
        { id: "Deep Savers",       nombre: "Mar Profundo" },
        { id: "Wind Guardians",    nombre: "Cielo Roto" },
        { id: "Jungle Troopers",   nombre: "Jungla" },
        { id: "Dragon's Roar",     nombre: "Rugido del Dragón" },
        { id: "Metal Empire",      nombre: "Imperio de Metal" },
        { id: "Nightmare Soldiers", nombre: "Pesadilla" },
        { id: "Virus Busters",     nombre: "Orden" },
        { id: "Dark Area",         nombre: "Área Oscura" }
    ]

    // ── andar ─────────────────────────────────────────────────────
    //  En los aparatos la exploración salía de TUS pasos: el Digivice del 98
    //  llevaba podómetro, y en el emulador eso es `area_distance` y
    //  `boss_distance`. Aquí no hay podómetro, pero sí hay una medida honesta
    //  de que te estás moviendo: cambiar de ventana o de escritorio.
    //
    //  Solo se mira QUE cambió, nunca a qué: no se lee ni se guarda un
    //  título, un pid ni un nombre de aplicación. Contar movimientos no
    //  necesita saber qué estabas haciendo.
    //  El goteo del reloj es el SUELO, no el motor: quien pasa el día en una
    //  sola ventana también avanza, pero despacio.
    //
    //  Estaba en 90 s y eso son 560 de distancia al día sin tocar nada —
    //  medido con `tools/digivice_balance.js`— así que hasta en «uso normal»
    //  solo el 35 % del avance venía de usar el ordenador. O sea que la idea
    //  entera de la fase 7 («usar el ordenador te lleva por el camino») la
    //  estaba anulando un temporizador. A 8 minutos aporta 105 al día y el
    //  uso activo manda con holgura.
    readonly property int segundosPorPaso: 480
    //  Y un margen entre pasos por actividad, o alternar dos ventanas a lo
    //  loco sería una cinta de correr.
    readonly property int segundosEntrePasos: 8

    // ── energía ───────────────────────────────────────────────────
    //  El recurso de combate del aparato: `mine_energy` y `enemy_energy` en
    //  el emulador, con su `call_cost` y su `call_power`. Sirve para LLAMAR
    //  en mitad de un choque —un empujón de golpe que no sale de aporrear—
    //  y por eso le da a la pelea un segundo verbo: aporrear o guardar.
    readonly property int maxEnergia: 8
    //  Un rayo cada doce minutos despierto. Llenar el medidor entero cuesta
    //  hora y media, así que llamar es algo que se administra, no que se
    //  repite.
    readonly property int minutosPorEnergia: 12
    //  Y DORMIDO va al doble. Es lo que le da a dormir algo más que «no
    //  molestes»: descansar recupera, como debe ser.
    readonly property real energiaDurmiendo: 2.0
    readonly property int costeLlamada: 3

    // ── jefes ─────────────────────────────────────────────────────
    //  El jefe está AL FINAL DEL CAMINO, no en una tirada de suerte: es el
    //  `boss_distance` del emulador. Se llega ganando en la zona, y por eso
    //  explorar tiene meta en vez de ser lo mismo nueve veces.
    //  El Área Oscura es la final: cerrada hasta que caigan los otros ocho.
    //  El emulador hace lo mismo con `final_area` y `last_boss_unlocked`.
    readonly property string zonaFinal: "Dark Area"
    readonly property int jefesParaFinal: 4

    // ── estado ────────────────────────────────────────────────────
    property string especie: ""          // id en el índice, como string
    property real nacidoEn: 0
    property real etapaDesde: 0
    property int hambre: 4
    property int animo: 4
    //  Cuatro estadísticas entrenables por separado en vez de una «fuerza»
    //  que subía sola. Entrenar deja de ser un número y pasa a ser decidir en
    //  qué quieres que sea bueno.
    property var entrenos: ({ pv: 0, atq: 0, def: 0, vel: 0 })
    property int errores: 0
    property bool enfermo: false
    property int victorias: 0
    property int derrotas: 0
    //  La carretera: cuánto llevas andado de cada zona. Permanente, no se
    //  gasta — es un cuentakilómetros, no un depósito. Es lo que hace que
    //  usar el ordenador SEA el progreso y no solo el combustible.
    property var distancias: ({})

    //  La semilla del camino: estable por bicho, para que su carretera sea
    //  suya y no cambie al reiniciar la barra.
    readonly property int _semillaCarretera: (_semillaAgenda * 7 + 13) % 1000000

    //  Cuántas veces has recorrido cada zona, y en qué vuelta cayó su jefe
    //  por última vez. Conquistar es para siempre —la estrella no se pierde—
    //  pero el camino se puede rehacer: cada zona tiene su comida, sus
    //  especies y su Digimental, y dejarlas muertas al vencer al jefe te
    //  quedaría sin sitio donde andar al final de la partida.
    property var vueltas: ({})
    property var jefeVuelta: ({})

    function vueltaDe(zonaId) { return vueltas[zonaId] || 0 }

    //  ¿El jefe de ESTA vuelta ya cayó?
    function vueltaCerrada(zonaId) {
        return jefeVencido(zonaId) && jefeVuelta[zonaId] === vueltaDe(zonaId)
    }

    signal caminoRehecho(string zonaId, int vuelta)

    //  Volver a empezar la zona. La distancia a cero y una vuelta más, que
    //  cambia la semilla: la carretera nueva NO es la misma de antes.
    function rehacerCamino(zonaId) {
        const z = zonaId || zona
        if (!jefeVencido(z)) {
            aviso(Idioma.t("Primero vence a su jefe"))
            return false
        }
        if (!vueltaCerrada(z)) {
            aviso(Idioma.t("El jefe todavía te espera"))
            return false
        }
        if (distanciaEn(z) < Reglas.distanciaJefe(zonas.map(function (x) {
                return x.id }).indexOf(z))) {
            aviso(Idioma.t("Todavía te queda camino"))
            return false
        }
        //  Con algo esperando no: sería empezar un camino nuevo dejando a
        //  medias un bicho del anterior, y la carretera vieja ya no existe.
        if (encuentroPendiente || caceria) {
            aviso(Idioma.t("Resuelve lo que tienes delante"))
            return false
        }
        const copiaV = Object.assign({}, vueltas)
        copiaV[z] = vueltaDe(z) + 1
        vueltas = copiaV
        _ponerDistancia(z, 0)
        guardar()
        caminoRehecho(z, copiaV[z])
        return true
    }

    //  Camino acabado: la vuelta cerrada Y estando al final. Las dos cosas.
    readonly property bool caminoAcabado: hayPartida
            && vueltaCerrada(zona) && distanciaZona >= distanciaJefeZona

    //  Lo andado de verdad: lo de la vuelta actual de cada zona MÁS lo de las
    //  vueltas ya cerradas. Sin la segunda parte, rehacer un camino borraría
    //  del contador todo lo que llevabas recorrido de esa zona.
    readonly property int recorridoTotal: {
        let t = 0
        for (let i = 0; i < zonas.length; ++i) {
            const z = zonas[i].id
            t += distanciaEn(z) + vueltaDe(z) * Reglas.distanciaJefe(i)
        }
        return t
    }

    readonly property int vueltasTotales: {
        let t = 0
        for (let i = 0; i < zonas.length; ++i)
            t += vueltaDe(zonas[i].id)
        return t
    }

    function distanciaEn(zonaId) { return distancias[zonaId] || 0 }

    function _ponerDistancia(zonaId, d) {
        const copia = Object.assign({}, distancias)
        copia[zonaId] = d
        distancias = copia
    }

    //  Lo que hace falta para pintar la carretera.
    readonly property int distanciaZona: distanciaEn(zona)
    readonly property int distanciaJefeZona: Reglas.distanciaJefe(indiceZona)
    readonly property real avanceZona: distanciaJefeZona > 0
            ? Math.min(1, distanciaZona / distanciaJefeZona) : 0
    //  La semilla de la zona EN LA VUELTA EN QUE ESTÁS.
    readonly property int _semillaZona: Reglas.semillaDeVuelta(
            _semillaCarretera, indiceZona, vueltaDe(zona))

    readonly property var siguienteHito: hayPartida
            ? Reglas.proximoHito(_semillaZona, indiceZona, distanciaZona) : null

    property int peso: 0
    //  La experiencia: el tercer requisito para evolucionar. Se gana
    //  peleando —más cuanto más arriba esté el rival— y entrenando.
    property int xp: 0
    property int energia: 0
    property real _restoEnergia: 0
    property int suciedad: 0
    property int sobrealimentado: 0
    property real suciedadDesde: 0

    // ── la despensa ───────────────────────────────────────────────
    //  Cuántas unidades hay de cada comida. La ración NO se cuenta: es
    //  infinita a propósito, para que quedarse sin nada de comer no pueda
    //  matar a un bicho por un fallo del sistema de caza.
    property var despensa: ({})

    //  Veneno de la comida, que SÍ dura fuera del combate: es lo que hace
    //  que comer algo en mal estado sea una equivocación con consecuencias y
    //  no un texto rojo que se olvida. Mientras dura, el ánimo cae al doble y
    //  entras envenenado a las peleas.
    property bool envenenado: false

    //  El vigor de la carne: ataque de más durante los próximos combates. Se
    //  gasta por combate y no por reloj, para que sea una decisión y no una
    //  carrera contra un cronómetro.
    property int vigor: 0

    //  Rastro acumulado andando. Es lo que cuesta cazar, y por eso comer bien
    //  queda atado a haber estado usando el ordenador. Va aparte de `pasos`,
    //  que se reinicia en cada encuentro y no sirve de moneda.
    property int rastro: 0

    // ── el meta-juego ─────────────────────────────────────────────
    //  Bits: la moneda. Se gana peleando —escalada por la etapa del rival— y
    //  cobrando objetivos, y se gasta en el mercado.
    property int bits: 0

    //  El inventario: { "<id>": cuántos }. Los digimentales van con la clave
    //  "dig:<Nombre>", que es como los nombra el índice de especiales.
    property var objetos: ({})

    //  Qué objetivos has COBRADO ya. Guardar los cobrados y no los hechos es
    //  a propósito: «hecho» se recalcula solo del estado de la partida, así
    //  que si mañana añado un objetivo nuevo, lo que ya cumplías cuenta.
    property var objetivosCobrados: ({})

    //  Contadores que ningún otro sitio lleva y que los objetivos necesitan.
    //  `etapaMax` es el escalón más alto al que has llegado NUNCA, no el de
    //  ahora: regresar por descuido no puede borrarte un logro.
    property int etapaMax: 0
    property int evoluciones: 0
    property int fusiones: 0
    property int cazas: 0
    // ── la colección ──────────────────────────────────────────────
    //  El bicho ACTIVO sigue viviendo en las propiedades sueltas de siempre;
    //  los demás esperan aquí, en instantáneas. Se hizo así y no con una
    //  lista de criaturas porque en QML enlazar a un elemento de un array es
    //  un campo de minas —mutar dentro no notifica— y habría obligado a
    //  reescribir todo el servicio para ganar nada.
    //
    //  Los del banco NO pasan hambre ni se ensucian: están en la guardería,
    //  no abandonados. Castigar por coleccionar es la forma más rápida de que
    //  nadie coleccione.
    property var banco: []
    readonly property int maxBanco: 5

    //  La enciclopedia en dos niveles. `descubiertos` es a quién has VISTO
    //  —peleaste contra él— y esto es a quién has CRIADO, que es lo que
    //  convierte un registro en una colección: lo primero se rellena solo, lo
    //  segundo cuesta.
    property var criados: ({})

    // ── captura e incubación ──────────────────────────────────────
    //  El emulador lo tiene: `catch_digimon`, `captured_digimon_list`,
    //  `avaliable_eggs`, `egg_counter`, `egg_break`.
    //
    //  Ganar te da los DATOS de la especie, no la especie: de un Adult te
    //  llevas el huevo de su línea y lo crías tú desde abajo. Es lo fiel
    //  —el aparato guardaba datos, no mascotas— y es lo que evita acabar
    //  con un equipo de Adults que no has criado.
    property var datos: ({})            // especie -> true (datos capturados)
    property string incubando: ""       // el huevo puesto, si hay
    property int pasosIncubados: 0

    //  Uno de cada tres normales; los jefes siempre. Sin el azar, capturar
    //  sería un trámite; con demasiado, coleccionar sería una tómbola.
    readonly property real probEscaneo: 0.34
    //  Lo que tarda un huevo en romper, en zancada acumulada — la misma que
    //  mueve la carretera, no pulsaciones sueltas.
    //
    //  Estaba en 24 y se quedaba corto: medido con `tools/digivice_balance.js`
    //  son 50 minutos de uso normal y 23 de uso intensivo, o sea nada. A 120
    //  son unas 4 h de uso normal y 2 de uso intensivo: una espera de las de
    //  dejarlo y volver, que es lo que tiene que ser un huevo y además lo
    //  primero que ve quien abre el plugin.
    readonly property int pasosParaEclosionar: 120

    property var jefesVencidos: ({})     // zona -> true
    property bool jefePendiente: false
    property int _cacasPendientes: 0
    property string zona: "Nature Spirits"
    property var descubiertos: ({})      // id -> true, para la enciclopedia
    property real ultimoTick: 0
    property real hambreDesdeCero: 0
    property real animoDesdeCero: 0

    readonly property bool hayPartida: especie !== ""
    readonly property var ficha: hayPartida ? datoDe(especie) : null
    readonly property string etapa: ficha ? ficha.l : ""

    //  Lo que pesa de menos no existe: por debajo del mínimo de su etapa un
    //  bicho no baja, y lo que sobra es lo que lastra.
    readonly property int pesoMinimo: Reglas.pesoBaseDe(etapa)
    readonly property int excesoPeso: Reglas.excesoDePeso(etapa, peso)
    // ── evolucionar ───────────────────────────────────────────────
    readonly property int minutosEnEtapa: hayPartida
        ? Math.floor((ahora() - etapaDesde) / 60) : 0
    readonly property var requisitos: Reglas.requisitosDe(etapa)
    readonly property var falta: Reglas.faltaPara(etapa, minutosEnEtapa, victorias, xp)
    readonly property bool cumpleRequisitos:
        Reglas.cumpleRequisitos(etapa, minutosEnEtapa, victorias, xp)

    readonly property int entrenoTotal: (entrenos.pv || 0) + (entrenos.atq || 0)
                                      + (entrenos.def || 0) + (entrenos.vel || 0)

    readonly property int jefesCaidos: Object.keys(jefesVencidos).length
    readonly property bool puedeLlamar: energia >= costeLlamada

    //  Huir de un combate. El segundo uso de la energía, y tapa un hueco de
    //  verdad: hasta ahora NO se podía salir de una pelea. Si te topabas con
    //  un jefe que te superaba, estabas obligado a perder — y perder cuesta
    //  ánimo, hambre y una derrota en el expediente.
    //
    //  Huir no es gratis pero tampoco castiga: se paga con energía, que es lo
    //  que también mueve al aliado, así que escapar hoy es no poder llamar
    //  mañana. Ni victoria ni derrota: no ha pasado nada.
    readonly property int costeHuida: 2
    readonly property bool puedeHuir: hayPartida && energia >= costeHuida

    signal huido(string idEnemigo)

    function huir() {
        if (!encuentroPendiente) return false
        if (energia < costeHuida) {
            aviso(Idioma.t("Sin energía para escapar"))
            return false
        }
        const e = enemigoPendiente
        energia -= costeHuida
        enemigoPendiente = ""
        jefePendiente = false
        guardar()
        huido(e)
        return true
    }

    //  Gastar la llamada. Devuelve false si no llega, y quien llame decide
    //  qué hacer con eso —aquí no se avisa: avisar es cosa de la vista.
    function gastarLlamada() {
        if (!hayPartida || energia < costeLlamada)
            return false
        energia -= costeLlamada
        guardar()
        return true
    }

    //  Para que el paisaje de cada zona sea el suyo y no cambie.
    readonly property int indiceZona: {
        for (let i = 0; i < zonas.length; ++i)
            if (zonas[i].id === zona) return i
        return 0
    }

    readonly property int cuantosCriados: Object.keys(criados).length
    readonly property int cuantosDatos: Object.keys(datos).length
    readonly property bool hayIncubacion: incubando !== ""
    readonly property bool huevoListo: hayIncubacion
                                    && pasosIncubados >= pasosParaEclosionar
    //  De 0 a 1, para que el huevo pueda enseñar cuánto le queda sin un
    //  número: se menea más deprisa y se raja según sube esto.
    readonly property real progresoIncubacion: pasosParaEclosionar > 0
            ? Math.min(1, pasosIncubados / pasosParaEclosionar) : 0

    signal escaneado(string id, string huevo)
    signal eclosiono(string id)
    signal incubado(string id)

    //  Los huevos que puedes poner: uno por cada línea capturada, sin
    //  repetir. Se calcula y no se guarda porque es una vista de `datos`.
    readonly property var huevosDisponibles: {
        const vistos = {}, out = []
        for (const k in datos) {
            const h = Reglas.raizDe(indice, k)
            if (h && !vistos[h]) { vistos[h] = true; out.push(h) }
        }
        out.sort(function (a, b) { return nombreDe(a).localeCompare(nombreDe(b)) })
        return out
    }

    function escanear(idEnemigo, seguro) {
        const k = String(idEnemigo)
        if (!k || datos[k])
            return false
        if (!seguro && Math.random() > probEscaneo)
            return false
        const copia = Object.assign({}, datos)
        copia[k] = true
        datos = copia
        descubrir(k)
        escaneado(k, Reglas.raizDe(indice, k))
        return true
    }

    function incubar(idHuevo) {
        if (hayIncubacion) { aviso(Idioma.t("Ya hay un huevo dentro")); return false }
        if (huevosDisponibles.indexOf(String(idHuevo)) < 0)
            return false
        incubando = String(idHuevo)
        pasosIncubados = 0
        guardar()
        incubado(String(idHuevo))
        return true
    }

    //  Sacar al recién nacido. Si ya llevas uno, el que llevabas se va a la
    //  guardería; si está llena, el huevo espera puesto en vez de perderse.
    function eclosionar() {
        if (!huevoListo)
            return false
        if (hayPartida && !_alBanco())
            return false

        const nuevo = incubando
        incubando = ""
        pasosIncubados = 0

        especie = nuevo
        nacidoEn = ahora()
        etapaDesde = nacidoEn
        hambre = maxCorazones
        animo = maxCorazones
        entrenos = ({ pv: 0, atq: 0, def: 0, vel: 0 })
        xp = 0
        errores = 0
        enfermo = false
        victorias = 0
        derrotas = 0
        peso = Reglas.pesoBaseDe(datoDe(nuevo).l)
        suciedad = 0
        suciedadDesde = 0
        sobrealimentado = 0
        energia = Math.floor(maxEnergia / 2)
        _cacasPendientes = 0
        _restoEnergia = 0
        _cursorCuidado = ahora()
        despiertoHasta = 0
        ultimoTick = ahora()
        descubrir(nuevo)
        marcarCriado(nuevo)
        guardar()
        eclosiono(nuevo)
        return true
    }
    function estaCriado(id) { return criados[String(id)] === true }

    function marcarCriado(id) {
        const k = String(id)
        if (!k || criados[k])
            return
        const copia = Object.assign({}, criados)
        copia[k] = true
        criados = copia
        descubrir(k)
    }

    //  ── jogress ───────────────────────────────────────────────────
    signal fusionado(string a, string b, string hijo)

    //  Con quién de la GUARDERÍA puede fusionar el que llevas, y qué sale.
    //  Se calcula sobre lo que tienes, no sobre la tabla entera: enseñar
    //  fusiones imposibles sería un catálogo, no una decisión.
    readonly property var fusionesPosibles: {
        if (!hayPartida)
            return []
        const out = []
        for (let i = 0; i < banco.length; ++i) {
            const otro = banco[i].especie
            const hijo = Reglas.jogressCon(indiceJogress, especie, otro)
            if (hijo && datoDe(hijo))
                out.push({ hueco: i, con: otro, da: hijo })
        }
        return out
    }

    //  Fusionar consume LOS DOS, como se decidió: el que llevas y el de la
    //  guardería desaparecen y sale uno nuevo. Es lo que hace que la decisión
    //  pese —criaste dos para tener uno— y lo que la separa de evolucionar.
    function fusionar(hueco) {
        if (!hayPartida)
            return false
        let elegida = null
        for (let i = 0; i < fusionesPosibles.length; ++i)
            if (fusionesPosibles[i].hueco === hueco) { elegida = fusionesPosibles[i]; break }
        if (!elegida) {
            aviso(Idioma.t("No hacen pareja"))
            return false
        }

        const a = especie, b = elegida.con, hijo = elegida.da
        //  Los entrenos del otro padre hay que leerlos ANTES de sacarlo del
        //  banco, o se pierden.
        const suyos = _entrenosDe(banco[hueco])

        //  Los dos padres quedan registrados como criados: los has perdido,
        //  pero constan en la colección. Perderlos sin dejar rastro sería
        //  cobrar dos crianzas por una.
        marcarCriado(a)
        marcarCriado(b)

        //  Sale del banco el que se fusiona.
        const copia = banco.slice()
        copia.splice(hueco, 1)
        banco = copia

        especie = hijo
        nacidoEn = ahora()
        etapaDesde = nacidoEn
        //  Nace hecho: hereda la mitad de lo entrenado de los dos padres. Es
        //  el premio por haber criado dos, y evita que fusionar te devuelva
        //  a empezar de cero.
        const heredado = Object.assign({}, entrenos)
        for (let i = 0; i < estadisticas.length; ++i) {
            const k = estadisticas[i]
            heredado[k] = Math.round(((heredado[k] || 0) + (suyos[k] || 0)) / 2)
        }
        entrenos = heredado
        xp = 0
        errores = 0
        enfermo = false
        hambre = maxCorazones
        animo = maxCorazones
        peso = Reglas.pesoBaseDe(datoDe(hijo).l)
        suciedad = 0
        suciedadDesde = 0
        _cacasPendientes = 0
        energia = Math.floor(maxEnergia / 2)
        ultimoTick = ahora()

        descubrir(hijo)
        marcarCriado(hijo)
        fusiones += 1
        etapaMax = Math.max(etapaMax, Reglas.ESCALERA.indexOf(datoDe(hijo).l))
        guardar()
        fusionado(a, b, hijo)
        return true
    }

    //  ── el banco ──────────────────────────────────────────────────
    signal cambioDeCriatura(string antes, string ahora)

    function _instantaneaCriatura() {
        return {
            especie: especie, nacidoEn: nacidoEn, etapaDesde: etapaDesde,
            hambre: hambre, animo: animo, entrenos: entrenos, errores: errores,
            enfermo: enfermo, victorias: victorias, derrotas: derrotas, xp: xp,
            peso: peso, suciedad: suciedad, sobrealimentado: sobrealimentado,
            energia: energia, despiertoHasta: despiertoHasta,
            cursorCuidado: _cursorCuidado, restoEnergia: _restoEnergia,
            cacasPendientes: _cacasPendientes,
            //  El veneno y el vigor son DEL BICHO, no del jugador: viajan con
            //  él a la guardería. Si se quedaran en las propiedades sueltas,
            //  cambiar de criatura curaría el veneno, que sería la manera más
            //  tonta de romper el castigo de la comida en mal estado.
            envenenado: envenenado, vigor: vigor,
            hambreDesdeCero: 0, animoDesdeCero: 0, suciedadDesde: 0
        }
    }

    function _aplicarCriatura(c) {
        especie = c.especie
        nacidoEn = c.nacidoEn || ahora()
        etapaDesde = c.etapaDesde || nacidoEn
        hambre = c.hambre !== undefined ? c.hambre : maxCorazones
        animo = c.animo !== undefined ? c.animo : maxCorazones
        entrenos = _entrenosDe(c)
        xp = c.xp || 0
        errores = c.errores || 0
        enfermo = !!c.enfermo
        victorias = c.victorias || 0
        derrotas = c.derrotas || 0
        peso = c.peso || Reglas.pesoBaseDe(datoDe(c.especie) ? datoDe(c.especie).l : "")
        suciedad = c.suciedad || 0
        sobrealimentado = c.sobrealimentado || 0
        energia = c.energia || 0
        despiertoHasta = c.despiertoHasta || 0
        _cursorCuidado = c.cursorCuidado || ahora()
        _restoEnergia = c.restoEnergia || 0
        _cacasPendientes = c.cacasPendientes || 0
        envenenado = !!c.envenenado
        vigor = c.vigor || 0
        hambreDesdeCero = 0
        animoDesdeCero = 0
        suciedadDesde = 0
        ultimoTick = ahora()
    }

    //  Guardar el que llevas y quedarte sin ninguno. Lo usa `nuevaPartida`.
    function _alBanco() {
        if (!hayPartida)
            return false
        if (banco.length >= maxBanco) {
            aviso(Idioma.t("La guardería está llena"))
            return false
        }
        banco = banco.concat([_instantaneaCriatura()])
        especie = ""
        return true
    }

    //  Cambiar el que llevas por uno del banco. El que sale ocupa su hueco,
    //  así que el número total no cambia y nadie se pierde por el camino.
    function cambiarA(i) {
        if (i < 0 || i >= banco.length)
            return false
        const entra = banco[i]
        const sale = hayPartida ? _instantaneaCriatura() : null
        const copia = banco.slice()
        if (sale) copia[i] = sale
        else copia.splice(i, 1)
        banco = copia

        const antes = especie
        _aplicarCriatura(entra)
        //  Al volver del banco no arrastra el tiempo que estuvo fuera: en la
        //  guardería no se pasa hambre.
        guardar()
        cambioDeCriatura(antes, especie)
        return true
    }

    function jefeDe(zonaId) { return Reglas.jefeDe(indice, zonaId, etapa) }
    function jefeVencido(zonaId) { return jefesVencidos[zonaId] === true }

    //  Cuánto falta para que salga el jefe de esa zona.
    function zonaAbierta(zonaId) {
        return zonaId !== zonaFinal || jefesCaidos >= jefesParaFinal
    }

    //  Por qué NO se pudo hacer lo que pediste.
    //
    //  Las acciones devuelven un booleano, y con eso la vista sabe que no
    //  pasó nada pero no sabe decir por qué. Un botón que se pulsa y no
    //  responde parece roto —y el caso peor es alimentar dormido, que sí
    //  hacía algo: sumaba un descuido sin decir ni pío—.
    signal aviso(string texto)

    signal jefeALaVista(string idJefe, string zonaId)
    signal jefeCaido(string idJefe, string zonaId)

    signal evoluciono(string antes, string ahora)
    signal encuentro(string idEnemigo)
    signal descuido(string motivo)
    signal enfermo_(bool si)

    // ── índice de especies ────────────────────────────────────────
    property var indice: ({})
    property bool indiceListo: false
    property int totalEspecies: 0

    function datoDe(id) {
        const d = indice[String(id)]
        return d || null
    }

    function nombreDe(id) {
        const d = datoDe(id)
        return d ? d.n : "?"
    }

    //  ── el arte ───────────────────────────────────────────────────
    //
    //  Dos fuentes y una cascada. Lo primero que se intenta es el SPRITE del
    //  aparato, sacado de Wikimon: está dibujado a ese tamaño, así que se lee
    //  perfecto pequeño. Reducir la ilustración no vale —probado: Gomamon se
    //  convierte en papilla a 48 px— y por eso no hay un solo camino.
    //
    //  Preferencia dentro del sprite: color antes que los monocromos de los
    //  aparatos clásicos. 1113 de 1488 tienen uno, 855 a color; el resto cae
    //  a la ilustración de digi-api, que siempre está. Así nunca falta cara.
    //
    //  Que 258 salgan en blanco y negro NO es un filtro flojo: solo 14 de los
    //  54 aparatos que hay dibujan en color, y esas especies no tienen sprite
    //  de color en ningún sitio. La elección la hace —y se puede rehacer—
    //  `tools/digivice_sprites.py`, que mide el color en vez de deducirlo del
    //  nombre del aparato.
    property var indiceSprites: ({})

    //  Las parejas de fusión: 3804 sobre 620 especies, sacadas del campo
    //  `condition` de la API. Es lo que le da propósito a la guardería.
    property var indiceJogress: ({})

    function spriteDe(id) {
        return indiceSprites[String(id)] || null
    }

    readonly property string baseSprites: "https://wikimon.net/images/"

    function urlImagen(id) {
        const s = spriteDe(id)
        if (s)
            return baseSprites + s.r
        const d = datoDe(id)
        if (!d)
            return ""
        return "https://digi-api.com/images/digimon/w/"
             + encodeURIComponent(d.n.replace(/ /g, "_")) + ".png"
    }

    //  Si lo que se pinta es un sprite, la vista NO debe suavizarlo: un pixel
    //  art interpolado es exactamente lo que no queremos.
    function esSprite(id) {
        return spriteDe(id) !== null
    }

    //  A mano y no con K4.Paths porque los servicios no importan la API: la
    //  usan los plugins. Es el mismo directorio que daría `estadoDe`.
    readonly property string dirEstado: Quickshell.env("HOME")
                                      + "/.local/state/k4/plugins/digivice"
    readonly property string dirImagenes: dirEstado + "/img"

    //  El fichero local, se haya descargado o no. La vista lo pide y pinta lo
    //  que haya; si falta, `pedirImagen` lo trae y la vista se entera sola
    //  porque cambia `imagenesListas`.
    //  El nombre en caché lleva el origen para que cambiar de fuente no
    //  reutilice por error una imagen del otro tipo.
    function rutaImagen(id) {
        const d = datoDe(id)
        if (!d)
            return ""
        const marca = esSprite(id) ? "_s" : "_i"
        return dirImagenes + "/" + d.n.replace(/[\/ ()]/g, "_") + marca + ".png"
    }

    //  Donde cae la descarga cruda, antes de convertirla: los sprites vienen
    //  en GIF tantas veces como en PNG.
    function rutaCruda(id) {
        return dirImagenes + "/.bajando"
    }

    // ── reglas puras ──────────────────────────────────────────────
    //  Separadas de lo que escribe estado para poder probarlas sin arrancar
    //  Quickshell.

    function escalonSiguiente(e) { return Reglas.escalonSiguiente(e) }
    function poderDeEtapa(e) { return Reglas.poderDeEtapa(e) }
    function ventaja(a, b) { return Reglas.ventaja(a, b) }
    //  Con el peso del bicho cuando es el nuestro; los rivales no engordan.
    //  Con los entrenos y el peso del bicho cuando es el nuestro; los rivales
    //  ni entrenan ni engordan.
    function statsDe(id, e, p) {
        const mio = String(id) === especie
        return Reglas.statsDe(indice, id,
                              e !== undefined ? e : (mio ? entrenos : null),
                              p !== undefined ? p : (mio ? peso : undefined))
    }
    function dañoDe(a, d, atrA, atrD) { return Reglas.dañoDe(a, d, atrA, atrD) }
    function probEsquiva(d, a) { return Reglas.probEsquiva(d, a) }

    // ── evolución ─────────────────────────────────────────────────
    function candidatosEvolucion(id) {
        return Reglas.candidatosEvolucion(indice, id)
    }

    function tecnicasAbiertas(id, e) {
        return Reglas.tecnicasAbiertas(indice, id,
                                       e !== undefined ? e : entrenos)
    }

    function gradoCrianza() {
        //  El «esfuerzo» para el grado de crianza pasa a ser la suma de los
        //  cuatro entrenos: da igual en qué lo hayas metido, lo que cuenta es
        //  que lo hayas cuidado y trabajado.
        return Reglas.gradoCrianza(errores, entrenoTotal, enfermo, excesoPeso)
    }

    function puedeEvolucionar() {
        if (!hayPartida || enfermo)
            return false
        if (!cumpleRequisitos)
            return false
        return candidatosEvolucion(especie).length > 0
    }

    function evolucionar() {
        if (!puedeEvolucionar())
            return false
        const cands = candidatosEvolucion(especie)
        const idx = Math.min(gradoCrianza(), cands.length - 1)
        return _convertirEn(cands[idx])
    }

    //  El cuerpo de CUALQUIER evolución: la normal, la Armor, la X y el Warp.
    //  Existe separado porque las cuatro hacen exactamente lo mismo con el
    //  bicho —lo guardan en la colección, reinician cuerpo y contadores— y
    //  tenerlo cuatro veces garantizaba que tarde o temprano una se olvidara
    //  de reiniciar algo.
    function _convertirEn(nuevo) {
        if (!nuevo || !datoDe(nuevo))
            return false
        const antes = especie
        //  Lo que dejas atrás se queda EN LA COLECCIÓN. Antes evolucionar
        //  borraba al anterior sin más: criabas un Jyarimon durante horas y
        //  al subir de etapa no quedaba constancia de que hubiera existido.
        //  Eso es lo que hacía que entrenar y evolucionar no dejaran poso.
        marcarCriado(antes)
        especie = nuevo
        etapaDesde = ahora()
        //  La evolución cura y reencuadra: el marcador de errores se reinicia
        //  porque castigar en Perfect lo que hiciste mal en Child convierte
        //  un mal día en una partida perdida.
        errores = 0
        hambre = maxCorazones
        animo = maxCorazones
        //  Cuerpo nuevo: la experiencia de la etapa anterior no se arrastra,
        //  o subir el segundo escalón sería gratis por lo hecho en el primero.
        xp = 0
        //  Cuerpo nuevo, báscula nueva: el peso arranca en el mínimo de la
        //  etapa a la que sube. Arrastrarlo dejaría a un Ultimate pesando lo
        //  de un Child, o al revés, según cómo se hubiera criado antes.
        peso = Reglas.pesoBaseDe(datoDe(especie).l)
        suciedad = 0
        suciedadDesde = 0
        _cacasPendientes = 0
        sobrealimentado = 0
        descubrir(especie)
        marcarCriado(especie)
        //  Contadores del meta-juego. `etapaMax` solo sube: regresar por un
        //  descuido no puede borrarte el objetivo que ya habías cumplido.
        evoluciones += 1
        etapaMax = Math.max(etapaMax, Reglas.ESCALERA.indexOf(datoDe(especie).l))
        guardar()
        evoluciono(antes, especie)
        return true
    }

    // ── evoluciones especiales ────────────────────────────────────
    //
    //  Armor con un digimental, X con el anticuerpo y Warp con crianza
    //  impecable. Son el 5 % de las aristas y por eso valen: son logros, no
    //  rutas. Las tres pasan por `_convertirEn`, así que no pueden divergir
    //  de la normal.
    property var indiceEspeciales: ({})

    readonly property var armoresPosibles: hayPartida && !enfermo
            ? Reglas.armorConLoQueTienes(indiceEspeciales, especie, objetos) : []

    readonly property string formaX: hayPartida
            ? Reglas.xDe(indiceEspeciales, especie) : ""
    readonly property bool puedeX: formaX !== "" && !enfermo
                                && (objetos["antidoto"] || 0) > 0

    readonly property var warpsPosibles: hayPartida ? Reglas.warpDe(indiceEspeciales, especie) : []
    readonly property bool puedeWarp: warpsPosibles.length > 0 && !enfermo
            && Reglas.puedeWarp(etapa, minutosEnEtapa, victorias, xp, errores)

    signal especial(string via, string antes, string ahora)

    function evolucionarArmor(i) {
        const l = armoresPosibles
        if (i < 0 || i >= l.length) {
            aviso(Idioma.t("No tienes ese Digimental"))
            return false
        }
        const antes = especie
        //  El digimental se GASTA. Si no, el primero que cayera abriría esa
        //  rama para siempre y dejaría de haber motivo para volver a un jefe.
        _quitarObjeto(l[i].objeto)
        if (!_convertirEn(l[i].da))
            return false
        especial("armor", antes, especie)
        return true
    }

    function evolucionarX() {
        if (!puedeX) {
            aviso(formaX === "" ? Idioma.t("Este no tiene forma X")
                                : Idioma.t("Te falta el Anticuerpo X"))
            return false
        }
        const antes = especie
        _quitarObjeto("antidoto")
        if (!_convertirEn(formaX))
            return false
        especial("x", antes, especie)
        return true
    }

    function evolucionarWarp(i) {
        if (!puedeWarp) {
            aviso(errores > 0 ? Idioma.t("El Warp pide cero descuidos")
                              : Idioma.t("Todavía no llega para un Warp"))
            return false
        }
        const l = warpsPosibles
        //  Si no piden una en concreto, la elige la CRIANZA, igual que en la
        //  evolución normal: es la misma pregunta —«¿en cuál de sus ramas
        //  cae?»— y responderla de dos maneras distintas sería incoherente.
        const j = (i === undefined || i === null)
                ? Math.min(gradoCrianza(), l.length - 1)
                : Math.max(0, Math.min(i, l.length - 1))
        const antes = especie
        if (!_convertirEn(l[j]))
            return false
        especial("warp", antes, especie)
        return true
    }

    // ── el inventario ─────────────────────────────────────────────
    function cuantosObjetos(id) {
        return objetos[id] || 0
    }

    function nombreObjeto(id) {
        const o = Reglas.objetoDe(id)
        if (o) return o.nombre
        const c = Reglas.comidaDe(id)
        return c ? c.nombre : id
    }

    function glifoObjeto(id) {
        const o = Reglas.objetoDe(id)
        if (o) return o.glifo
        const c = Reglas.comidaDe(id)
        return c ? c.glifo : ""
    }

    function _meterObjeto(id, n) {
        const copia = Object.assign({}, objetos)
        copia[id] = (copia[id] || 0) + (n || 1)
        objetos = copia
    }

    function _quitarObjeto(id) {
        const copia = Object.assign({}, objetos)
        copia[id] = Math.max(0, (copia[id] || 0) - 1)
        if (copia[id] === 0)
            delete copia[id]
        objetos = copia
    }

    //  La bolsa: comida y objetos en una sola lista. Van juntos porque el
    //  jugador no piensa «comida» y «objeto», piensa «qué llevo encima», y
    //  dos pantallas para eso serían dos iconos más en un menú que ya va
    //  lleno.
    readonly property var bolsa: {
        const out = []
        for (let i = 0; i < Reglas.COMIDAS.length; ++i) {
            const c = Reglas.COMIDAS[i]
            const n = c.infinita ? -1 : (despensa[c.id] || 0)
            if (n !== 0)
                out.push({ clase: "comida", id: c.id, nombre: c.nombre,
                           nota: c.nota, glifo: c.glifo, cuantas: n,
                           malo: !!c.veneno })
        }
        const claves = Object.keys(objetos).sort()
        for (let j = 0; j < claves.length; ++j) {
            const o = Reglas.objetoDe(claves[j])
            if (!o || objetos[claves[j]] <= 0)
                continue
            out.push({ clase: "objeto", id: o.id, nombre: o.nombre,
                       nota: o.nota, glifo: o.glifo,
                       cuantas: objetos[claves[j]], malo: false })
        }
        return out
    }

    signal objetoUsado(string id, string nombre)

    //  Usar lo que sea que esté señalado en la bolsa. Los digimentales y el
    //  anticuerpo NO se usan desde aquí: son llaves de una evolución y se
    //  gastan en su pantalla, donde se ve en qué te vas a convertir.
    function usarObjeto(id, cual) {
        if (!hayPartida) return false
        if (cuantosObjetos(id) <= 0) return false
        if (durmiendo) { molestar(); return false }

        if (String(id).indexOf("dig:") === 0 || id === "antidoto") {
            aviso(Idioma.t("Se usa en Evolución"))
            return false
        }

        if (id === "vitamina") {
            const k = cual || "atq"
            if (entrenoDe(k) >= topeEntreno) {
                aviso(Idioma.t("Ya está al tope"))
                return false
            }
            const copia = Object.assign({}, entrenos)
            copia[k] = Math.min(topeEntreno, (copia[k] || 0) + 1)
            entrenos = copia
        } else if (id === "cinta") {
            if (peso <= pesoMinimo) {
                aviso(Idioma.t("No le sobra peso"))
                return false
            }
            peso = Math.max(pesoMinimo, peso - 4)
        } else {
            return false
        }

        _quitarObjeto(id)
        guardar()
        const o = Reglas.objetoDe(id)
        objetoUsado(id, o ? o.nombre : id)
        return true
    }

    // ── objetivos ─────────────────────────────────────────────────
    //
    //  El resumen que miran: un solo objeto con todo lo contable, para que
    //  añadir un objetivo no obligue a tocar ninguna lógica.
    readonly property var resumenObjetivos: ({
        victorias: victorias, derrotas: derrotas,
        jefes: jefesCaidos, criados: cuantosCriados,
        vistos: Object.keys(descubiertos).length,
        etapaMax: etapaMax, evoluciones: evoluciones,
        fusiones: fusiones, cazas: cazas,
        //  Lo andado en TODAS las zonas y en todas las vueltas: es la cifra
        //  que mide de verdad cuánto has explorado.
        recorrido: recorridoTotal,
        vueltas: vueltasTotales
    })

    readonly property var objetivos: Reglas.estadoObjetivos(resumenObjetivos,
                                                            objetivosCobrados)
    readonly property int objetivosCobrables: {
        let n = 0
        for (let i = 0; i < objetivos.length; ++i)
            if (objetivos[i].cobrable) n += 1
        return n
    }

    signal objetivoCobrado(string id, int bits, string objeto)

    function cobrarObjetivo(id) {
        const o = Reglas.objetivoDe(id)
        if (!o) return false
        const hay = resumenObjetivos[o.campo] || 0
        if (hay < o.meta) { aviso(Idioma.t("Todavía no")); return false }
        if (objetivosCobrados[id]) { aviso(Idioma.t("Ya lo cobraste")); return false }

        const copia = Object.assign({}, objetivosCobrados)
        copia[id] = true
        objetivosCobrados = copia
        bits += o.bits
        if (o.objeto)
            _meterObjeto(o.objeto, 1)
        guardar()
        objetivoCobrado(id, o.bits, o.objeto || "")
        return true
    }

    // ── PVP por código ────────────────────────────────────────────
    //
    //  Los aparatos peleaban por cable o por infrarrojos. Aquí no hay cable ni
    //  servidor: el equipo se empaqueta en un código que se pasa copiando y
    //  pegando, como cualquier otra cosa entre dos personas.
    //
    //  Tu equipo es el que llevas encima más los dos primeros de la guardería.
    //  No los mejores: los PRIMEROS, para que decidas tú a quién pones delante
    //  ordenando la guardería, en vez de que lo decida una fórmula.
    readonly property var miEquipo: {
        if (!hayPartida)
            return []
        const eq = [{ especie: especie, entrenos: entrenos }]
        for (let i = 0; i < banco.length && eq.length < Reglas.MAX_EQUIPO; ++i)
            eq.push({ especie: banco[i].especie, entrenos: _entrenosDe(banco[i]) })
        return eq
    }

    readonly property string miCodigo: Reglas.codificarEquipo(miEquipo)

    //  Los códigos que ya has ganado. Se guardan para que vencer al mismo
    //  amigo cien veces no sea una máquina de bits: el premio es por equipo
    //  nuevo, no por combate.
    property var codigosVencidos: ({})
    readonly property int bitsPorPvp: 120

    //  El último código con el que peleaste, para tenerlo puesto la próxima
    //  vez. Casi siempre se duela contra la misma persona, y volver a pedir
    //  el portapapeles cada vez sería un peaje por jugar dos veces seguidas.
    property string ultimoCodigo: ""

    //  El duelo en curso: el equipo rival y por dónde va el marcador.
    property var rivalEquipo: []
    property string rivalCodigo: ""
    property int pvpAsalto: 0
    property int pvpMios: 0
    property int pvpSuyos: 0

    readonly property bool hayDuelo: rivalEquipo.length > 0
    readonly property int pvpAsaltos: Reglas.asaltosDe(miEquipo, rivalEquipo)
    //  Gana quien se lleve más de la mitad: con tres asaltos, dos.
    readonly property bool pvpDecidido: hayDuelo
            && (pvpMios > pvpAsaltos / 2 || pvpSuyos > pvpAsaltos / 2
                || pvpAsalto >= pvpAsaltos)

    signal dueloTerminado(bool gane, int bits)

    function retar(codigo) {
        if (!hayPartida) return false
        const r = Reglas.descodificarEquipo(indice, codigo)
        if (r.error) {
            aviso(Idioma.t(Reglas.motivoDeCodigo(r.error)))
            return false
        }
        //  Contra tu propio código no: no demuestra nada y regalaría bits.
        const limpio = String(codigo).replace(/[^0-9A-Za-z]/g, "").toUpperCase()
        if (limpio === miCodigo.replace(/-/g, "")) {
            aviso(Idioma.t("Ese es tu propio código"))
            return false
        }
        rivalEquipo = r.equipo
        rivalCodigo = limpio
        ultimoCodigo = String(codigo).trim()
        guardar()
        pvpAsalto = 0
        pvpMios = 0
        pvpSuyos = 0
        return true
    }

    function anotarAsalto(gane) {
        if (!hayDuelo)
            return
        if (gane) pvpMios += 1
        else pvpSuyos += 1
        pvpAsalto += 1
        if (!pvpDecidido)
            return
        const gano = pvpMios > pvpSuyos
        //  El premio, solo la primera vez que ganas a ESE equipo. Sin esto,
        //  pegar el código de un amigo en bucle sería la mejor manera de
        //  ganar bits del juego, y todo lo demás sobraría.
        let premio = 0
        if (gano && !codigosVencidos[rivalCodigo]) {
            const copia = Object.assign({}, codigosVencidos)
            copia[rivalCodigo] = true
            codigosVencidos = copia
            premio = bitsPorPvp
            bits += premio
        }
        guardar()
        dueloTerminado(gano, premio)
    }

    //  Leer un código sin pelear, para poder comprobar lo que te han pasado.
    function leerCodigo(codigo) {
        return Reglas.descodificarEquipo(indice, codigo)
    }

    //  Un asalto sin manos, con las mismas reglas que el jugado. Es lo que
    //  usa el IPC; la vista juega los suyos en la pantalla de combate.
    function resolverAsalto() {
        if (!hayDuelo || pvpDecidido)
            return null
        const i = pvpAsalto
        if (i >= miEquipo.length || i >= rivalEquipo.length)
            return null
        const a = miEquipo[i], b = rivalEquipo[i]
        //  Sin hambre, sin enfermedad y sin zona: en un duelo no puede ganar
        //  quien haya abierto la barra más recientemente.
        const r = Reglas.resolverCombate(indice, a.especie, b.especie, {
            fuerza: a.entrenos,
            statsSuyo: Reglas.statsDe(indice, b.especie, b.entrenos)
        })
        return { mio: a.especie, suyo: b.especie, gane: !!(r && r.gane) }
    }

    function cerrarDuelo() {
        rivalEquipo = []
        rivalCodigo = ""
        pvpAsalto = 0
        pvpMios = 0
        pvpSuyos = 0
    }

    // ── el mercado ────────────────────────────────────────────────
    readonly property var alaVenta: {
        const out = []
        const ids = ["grande", "carne", "omni", "vitamina", "cinta", "antidoto"]
        for (let i = 0; i < ids.length; ++i) {
            const id = ids[i]
            const c = Reglas.comidaDe(id)
            const o = c ? null : Reglas.objetoDe(id)
            const f = c || o
            if (!f) continue
            out.push({ id: id, nombre: f.nombre, nota: f.nota, glifo: f.glifo,
                       precio: Reglas.precioDe(id),
                       tengo: c ? (despensa[id] || 0) : cuantosObjetos(id) })
        }
        return out
    }

    signal comprado(string id, string nombre, int precio)

    function comprar(id) {
        const precio = Reglas.precioDe(id)
        if (precio <= 0) { aviso(Idioma.t("Eso no se vende")); return false }
        if (bits < precio) {
            aviso(Idioma.f(Idioma.t("Te faltan %1 bits"), precio - bits))
            return false
        }
        bits -= precio
        if (Reglas.comidaDe(id))
            _meterEnDespensa(id, 1)
        else
            _meterObjeto(id, 1)
        guardar()
        const f = Reglas.comidaDe(id) || Reglas.objetoDe(id)
        comprado(id, f ? f.nombre : id, precio)
        return true
    }

    signal vendido(string id, int bits)

    function vender(id) {
        if (!Reglas.seVende(id)) { aviso(Idioma.t("Eso no se vende")); return false }
        const esComida = !!Reglas.comidaDe(id)
        const tengo = esComida ? (despensa[id] || 0) : cuantosObjetos(id)
        if (tengo <= 0) { aviso(Idioma.t("No te queda")); return false }
        if (esComida)
            _quitarDeDespensa(id)
        else
            _quitarObjeto(id)
        const cobro = Reglas.precioVenta(id)
        bits += cobro
        guardar()
        vendido(id, cobro)
        return true
    }

    //  Regresión: el fondo del descuido. Baja un peldaño por el `prior` que
    //  esté justo debajo, sin pasar de Baby I.
    function regresar() {
        const opts = Reglas.candidatosRegresion(indice, especie)
        if (opts.length === 0)
            return false
        const antes = especie
        especie = opts[0]
        etapaDesde = ahora()
        errores = 0
        enfermo = false
        hambre = maxCorazones
        animo = Math.max(1, maxCorazones - 2)
        peso = Reglas.pesoBaseDe(datoDe(especie).l)
        suciedad = 0
        suciedadDesde = 0
        _cacasPendientes = 0
        guardar()
        evoluciono(antes, especie)
        return true
    }

    // ── el reloj ──────────────────────────────────────────────────
    function ahora() { return Date.now() / 1000 }

    //  `cuando` en segundos epoch; sin él, ahora. Se puede preguntar por un
    //  momento pasado porque el rato que estuviste fuera puede haber cruzado
    //  la noche entera.
    function esHoraDeDormir(cuando) {
        const h = (cuando ? new Date(cuando * 1000) : new Date()).getHours()
        return duermeDesde > duermeHasta
             ? (h >= duermeDesde || h < duermeHasta)
             : (h >= duermeDesde && h < duermeHasta)
    }

    //  Despertarlo lo DESPIERTA. Antes `durmiendo` solo miraba el reloj, así
    //  que molestarlo te cobraba el descuido y el bicho seguía roncando: el
    //  aparato decía «lo has despertado» y enseñaba las zzz al mismo tiempo.
    //
    //  Se queda despierto un rato y luego se vuelve a dormir solo, que es lo
    //  que hace uno cuando le encienden la luz.
    property real despiertoHasta: 0
    readonly property int minutosDespiertoAlaFuerza: 10

    //  Depende de `ultimoTick` A PROPÓSITO, aunque no lo use: el reloj no es
    //  una propiedad reactiva, así que sin una dependencia que cambie sola
    //  este enlace no se reevalúa NUNCA. Ya pasaba antes de lo de despertar
    //  —al cruzar las 22:00 el bicho no se dormía hasta que cambiara otra
    //  cosa— y con el despertar temporal se notaría el doble: se quedaría
    //  despierto para siempre.
    readonly property bool durmiendo: {
        ultimoTick        // la dependencia que hace que esto se recalcule
        return hayPartida && esHoraDeDormir() && ahora() > despiertoHasta
    }

    //  Avanza el cuidado `segundos` hacia delante. Se usa igual para el tick
    //  de un segundo que para las ocho horas que estuviste fuera, y por eso
    //  no puede depender de nada que solo exista con la vista abierta.
    function avanzarCuidado(segundos, cuando) {
        if (!hayPartida || segundos <= 0)
            return

        //  Los sucesos del día, contados entre donde nos quedamos y ahora.
        //
        //  Ya no hay goteo ni deuda: se pregunta a la AGENDA cuántas veces
        //  tocaba tener hambre, ganas de mimo o hacer sus cosas entre los dos
        //  instantes. Sin acumuladores —los que crecían sin tope y hacían que
        //  dar de comer no sirviera de nada— y sin ritmo de metrónomo.
        //
        //  Vale igual para el tick de un segundo que para las ocho horas que
        //  estuviste fuera, y da el mismo resultado por los dos caminos,
        //  porque la agenda se genera de una semilla estable.
        const hasta = cuando || ahora()
        const desde = Math.min(hasta, _cursorCuidado || (hasta - segundos))
        const p0 = _puntoAgenda(desde), p1 = _puntoAgenda(hasta)

        const comidas = Reglas.sucesosEntre(_semillaAgenda, "hambre",
                                            p0.dia, p0.min, p1.dia, p1.min,
                                            minutosVigilia, caracter.hambre)
        const mimos = Reglas.sucesosEntre(_semillaAgenda, "animo",
                                          p0.dia, p0.min, p1.dia, p1.min,
                                          minutosVigilia, caracter.animo)
        const cacas = Reglas.sucesosEntre(_semillaAgenda, "caca",
                                          p0.dia, p0.min, p1.dia, p1.min,
                                          minutosVigilia)
        _cursorCuidado = hasta

        if (comidas > 0)
            hambre = Math.max(0, hambre - comidas)
        //  Envenenado el ánimo baja el doble: es lo que hace que comer algo en
        //  mal estado sea una equivocación con consecuencias.
        if (mimos > 0)
            animo = Math.max(0, animo - mimos * (envenenado ? 2 : 1))

        //  Lo comido acaba en el suelo. Sigue atado a las comidas pendientes
        //  y no al reloj a secas: si no ha comido, no ensucia.
        for (let ic = 0; ic < cacas && _cacasPendientes > 0
                         && suciedad < maxSuciedad; ++ic) {
            _cacasPendientes -= 1
            suciedad += 1
        }

        //  El instante simulado, no el real: durante el repaso de lo que pasó
        //  fuera, todos los trozos verían el mismo `ahora()` y el margen de
        //  gracia no vencería nunca, así que el abandono salía gratis.
        //  La energía sube SIEMPRE, dormido incluso —y ahí más deprisa—, así
        //  que va fuera del bloque de «solo despierto» donde están el hambre
        //  y la suciedad.
        const minsTotales = segundos / 60
        _restoEnergia += minsTotales * (esHoraDeDormir(cuando) ? energiaDurmiendo : 1)
        while (_restoEnergia >= minutosPorEnergia && energia < maxEnergia) {
            _restoEnergia -= minutosPorEnergia
            energia += 1
        }
        if (energia >= maxEnergia)
            _restoEnergia = 0

        const t = cuando || ahora()
        if (hambre === 0 && hambreDesdeCero === 0) hambreDesdeCero = t
        if (hambre > 0) hambreDesdeCero = 0
        if (animo === 0 && animoDesdeCero === 0) animoDesdeCero = t
        if (animo > 0) animoDesdeCero = 0

        //  Un descuido por cada tramo de gracia con un medidor a cero. Se
        //  cobra por tramo y no por minuto: la diferencia entre olvidarte una
        //  tarde y abandonar al bicho.
        const gracia = minutosGraciaError * 60
        if (hambreDesdeCero > 0 && t - hambreDesdeCero >= gracia) {
            hambreDesdeCero = t
            anotarDescuido("hambre")
        }
        if (animoDesdeCero > 0 && t - animoDesdeCero >= gracia) {
            animoDesdeCero = t
            anotarDescuido("ánimo")
        }

        //  Y la suciedad sin recoger. Con el suelo lleno se cobra el doble de
        //  rápido: cuatro cacas alrededor es el aviso más claro que sabe dar
        //  un aparato de estos.
        if (suciedad > 0 && suciedadDesde === 0) suciedadDesde = t
        if (suciedad === 0) suciedadDesde = 0
        if (suciedadDesde > 0) {
            const graciaSuciedad = minutosGraciaSuciedad * 60
                                 / (suciedad >= maxSuciedad ? 2 : 1)
            if (t - suciedadDesde >= graciaSuciedad) {
                suciedadDesde = t
                anotarDescuido("suciedad")
            }
        }
    }


    function anotarDescuido(motivo) {
        errores += 1
        descuido(motivo)
        if (!enfermo && errores >= erroresParaEnfermar) {
            enfermo = true
            enfermo_(true)
        }
        //  El fondo: enfermo y siguiendo el abandono, regresa. No muere.
        if (enfermo && errores >= erroresParaRegresar)
            regresar()
    }

    // ── acciones ──────────────────────────────────────────────────
    //  Comer engorda SIEMPRE, y con el estómago lleno engorda el doble y
    //  cuenta. Antes, con los corazones llenos, esto devolvía `false` y no
    //  pasaba nada: dar de comer no tenía ningún coste y por eso el cuidado
    //  no tenía decisiones.
    //  Comer la ración de siempre. Sigue existiendo con este nombre porque es
    //  por donde entran el IPC, el atajo y quien no ha cazado nunca.
    function alimentar() {
        return alimentarCon("racion")
    }

    // ── la despensa ───────────────────────────────────────────────
    readonly property var comidas: Reglas.COMIDAS

    function comidaPorId(id) {
        return Reglas.comidaDe(id)
    }

    function cuantasHay(id) {
        const c = Reglas.comidaDe(id)
        if (!c) return 0
        //  La ración no se cuenta: es infinita para que un fallo de la caza no
        //  pueda dejar a un bicho sin nada que llevarse a la boca.
        return c.infinita ? -1 : (despensa[id] || 0)
    }

    function hayComida(id) {
        return cuantasHay(id) !== 0
    }

    //  Lo que tienes, para la pantalla: la ración siempre, y de las demás solo
    //  las que tengas. Un menú lleno de ceros no es un menú.
    readonly property var despensaVisible: {
        const out = []
        for (let i = 0; i < Reglas.COMIDAS.length; ++i) {
            const c = Reglas.COMIDAS[i]
            const n = c.infinita ? -1 : (despensa[c.id] || 0)
            if (n !== 0)
                out.push({ comida: c, cuantas: n })
        }
        return out
    }

    function _quitarDeDespensa(id) {
        const copia = Object.assign({}, despensa)
        copia[id] = Math.max(0, (copia[id] || 0) - 1)
        if (copia[id] === 0)
            delete copia[id]
        despensa = copia
    }

    function _meterEnDespensa(id, n) {
        const c = Reglas.comidaDe(id)
        if (!c || c.infinita)
            return
        const copia = Object.assign({}, despensa)
        copia[id] = (copia[id] || 0) + (n || 1)
        despensa = copia
    }

    signal comido(string id, string nombre)

    //  Comer engorda SIEMPRE, y con el estómago lleno engorda el doble y
    //  cuenta. Antes, con los corazones llenos, esto devolvía `false` y no
    //  pasaba nada: dar de comer no tenía ningún coste y por eso el cuidado
    //  no tenía decisiones.
    function alimentarCon(id) {
        if (!hayPartida) return false
        if (durmiendo) { molestar(); return false }

        const c = Reglas.comidaDe(id)
        if (!c) return false
        if (!hayComida(id)) {
            aviso(Idioma.f(Idioma.t("No queda %1"), Idioma.t(c.nombre)))
            return false
        }

        //  La fruta cura y no llena: dársela a un bicho sano y sin veneno
        //  sería tirarla, y tirar el objeto más raro del juego en silencio es
        //  justo lo que no puede pasar.
        if (c.cura && !enfermo && !envenenado && animo >= maxCorazones) {
            aviso(Idioma.t("No le hace falta"))
            return false
        }

        _quitarDeDespensa(id)

        if (c.cura) {
            if (enfermo) { enfermo = false; enfermo_(false) }
            envenenado = false
            errores = Math.max(0, errores - 1)
        }
        if (c.veneno) {
            envenenado = true
            aviso(Idioma.t("Le ha sentado fatal"))
        }
        if (c.vigor > 0)
            vigor = Math.min(3, vigor + c.vigor)
        if (c.animo !== 0)
            animo = Math.max(0, Math.min(maxCorazones, animo + c.animo))
        //  Al glotón la comida le alegra; a los demás no tanto. Es lo único
        //  que hace el carácter en la comida, y basta para que se note.
        if (caracter.comer > 0 && c.hambre > 0)
            animo = Math.min(maxCorazones, animo + caracter.comer)

        if (c.hambre > 0 && hambre >= maxCorazones) {
            //  Con el estómago lleno, engorda el doble de lo que pesa esa
            //  comida y cuenta para el descuido.
            peso += c.peso * 2
            sobrealimentado += 1
            _cacasPendientes += 1
            if (sobrealimentado >= sobrealimentarMax) {
                sobrealimentado = 0
                anotarDescuido("sobrealimentado")
            }
        } else {
            hambre = Math.min(maxCorazones, hambre + c.hambre)
            peso += c.peso
            if (c.hambre > 0)
                _cacasPendientes += 1
        }

        guardar()
        comido(c.id, c.nombre)
        //  Devuelve true: ha pasado algo, aunque no sea bueno.
        return true
    }

    function mimar() {
        if (!hayPartida) return false
        if (durmiendo) { molestar(); return false }
        if (animo >= maxCorazones) { aviso(Idioma.t("Ya está contento")); return false }
        //  Al juguetón y al tímido el mimo les llena el doble: es lo que hace
        //  que criar a uno u otro se juegue distinto.
        animo = Math.min(maxCorazones, animo + 1 + caracter.mimo)
        guardar()
        return true
    }

    readonly property int rondasEntreno: 3

    // ── entrenamiento ─────────────────────────────────────────────
    readonly property var estadisticas: Reglas.ESTADISTICAS
    readonly property int topeEntreno: Reglas.topeEntreno(etapa)

    //  Fácil, normal y duro. Lo que cambia es cuánto ganas y qué te juegas:
    //  en duro fallar del todo cuesta ánimo, y por eso elegir dificultad es
    //  una decisión y no un ajuste.
    readonly property var dificultades: [
        { id: "facil",  nombre: "Suave",  factor: 1, castigo: false },
        { id: "normal", nombre: "Normal", factor: 2, castigo: false },
        { id: "duro",   nombre: "Duro",   factor: 3, castigo: true }
    ]
    property string dificultad: "normal"

    function entrenoDe(cual) { return entrenos[cual] || 0 }

    //  Lee los entrenos de un guardado, y MIGRA los antiguos: las partidas de
    //  antes tenían una sola `fuerza`, que se reparte a partes iguales entre
    //  las cuatro. Sin esto, quien ya jugaba perdería todo lo entrenado.
    function _entrenosDe(d) {
        if (d && d.entrenos)
            return {
                pv: d.entrenos.pv || 0, atq: d.entrenos.atq || 0,
                def: d.entrenos.def || 0, vel: d.entrenos.vel || 0
            }
        const f = (d && d.fuerza) || 0
        const c = Math.floor(f / 4)
        return { pv: c, atq: c, def: c, vel: c }
    }

    //  Repartir entreno entre las cuatro, para los premios que no eligen una.
    function _sumarEntreno(n) {
        const copia = Object.assign({}, entrenos)
        for (let i = 0; i < estadisticas.length; ++i) {
            const k = estadisticas[i]
            copia[k] = Math.min(topeEntreno, (copia[k] || 0) + n)
        }
        entrenos = copia
    }

    function _factorDificultad() {
        for (let i = 0; i < dificultades.length; ++i)
            if (dificultades[i].id === dificultad) return dificultades[i]
        return dificultades[1]
    }

    function puedeEntrenar() {
        return hayPartida && !durmiendo && hambre > 0
    }

    //  Y por qué NO se puede, para que el botón no se quede mudo: es el mismo
    //  fallo que ya tenían comer y curar.
    function avisarSiNoEntrena() {
        if (!hayPartida) return true
        if (durmiendo) { molestar(); return true }
        if (hambre === 0) { aviso(Idioma.t("Tiene demasiada hambre")); return true }
        return false
    }

    //  `cual` es la estadística que se entrena y `aciertos` viene del
    //  minijuego (0..rondasEntreno).
    function entrenar(cual, aciertos) {
        if (!hayPartida) return false
        if (durmiendo) { molestar(); return false }
        if (hambre === 0) { aviso(Idioma.t("Tiene demasiada hambre")); return false }

        const stat = estadisticas.indexOf(cual) >= 0 ? cual : "atq"
        const a = (aciertos === undefined) ? 1
                : Math.max(0, Math.min(rondasEntreno, aciertos))
        const dif = _factorDificultad()

        //  Entrenar cuesta hambre acierte o no: sin coste sería un botón que
        //  se pulsa cien veces. Lo que cambia con la puntería es lo que SACAS.
        hambre -= 1
        //  Y adelgaza, que es la otra mitad de la báscula.
        peso = Math.max(pesoMinimo, peso - 1)

        //  Entrenar también enseña, aunque menos que pelear.
        xp += a * dif.factor * 2

        const ganado = a * dif.factor
        if (ganado > 0) {
            //  Objeto nuevo y no mutación: QML solo propaga cambios cuando
            //  cambia la IDENTIDAD de la property.
            const copia = Object.assign({}, entrenos)
            copia[stat] = Math.min(topeEntreno, (copia[stat] || 0) + ganado)
            entrenos = copia
        }

        //  Fallar del todo desanima; bordarlo anima. Y en duro, fallar cuesta
        //  el doble: es lo que hace que elegir dificultad importe.
        if (a === 0)
            animo = Math.max(0, animo - (dif.castigo ? 2 : 1))
        else if (a === rondasEntreno)
            animo = Math.min(maxCorazones, animo + 1)

        guardar()
        return true
    }

    function cambiarDificultad() {
        let i = 0
        for (let k = 0; k < dificultades.length; ++k)
            if (dificultades[k].id === dificultad) { i = k; break }
        dificultad = dificultades[(i + 1) % dificultades.length].id
        guardar()
    }

    function limpiar() {
        if (!hayPartida) return false
        if (suciedad === 0) { aviso(Idioma.t("No hay nada que limpiar")); return false }
        suciedad = 0
        suciedadDesde = 0
        guardar()
        return true
    }

    function curar() {
        if (!hayPartida) return false
        //  La medicina también quita el veneno de la comida: son la misma
        //  clase de problema y tener que buscar una fruta rara para algo que
        //  te has hecho tú comiendo basura sería un castigo desproporcionado.
        if (!enfermo && !envenenado) {
            aviso(Idioma.t("No está enfermo"))
            return false
        }
        if (enfermo) {
            enfermo = false
            enfermo_(false)
            errores = Math.max(0, errores - 2)
        }
        envenenado = false
        guardar()
        return true
    }

    // ── la caza ───────────────────────────────────────────────────
    //
    //  Comer era gratis e infinito, así que el hambre no era un problema:
    //  era un botón. Cazar ata la comida buena a haber andado, que es lo
    //  único que este juego tiene de moneda honesta.

    //  La cacería en curso: la monta `cazar()` y la resuelve `elegirRastro()`.
    property var caceria: null

    signal cazado(string id, string nombre, bool malo)

    //  ── el rastro se gasta ────────────────────────────────────────
    //
    //  Andando acumulas rastro. Al absorber la caza dentro de la carretera le
    //  quité su único precio y se quedó en un contador que solo subía y no
    //  hacía NADA — dinero muerto guardado en la partida.
    //
    //  Ahora se gasta en lo que lleva su nombre: olfatear. Descarta un rastro
    //  malo más antes de elegir. Uno solo: con dos de tres marcados la
    //  cacería se resolvería sola.
    readonly property int costeOlfato: 25
    readonly property bool puedeOlfatear: caceria !== null
                                       && rastro >= costeOlfato
                                       && caceria.rastros.filter(function (r) {
                                              return !r.marcado }).length > 2

    signal olfateado()

    function olfatear() {
        if (!caceria) return false
        if (rastro < costeOlfato) {
            aviso(Idioma.f(Idioma.t("Necesitas %1 de rastro"), costeOlfato))
            return false
        }
        //  Sobre una copia: mutar dentro del objeto no dispara los enlaces y
        //  la marca no se vería aparecer. Ya pasó con los estados del combate.
        const copia = caceria.rastros.map(function (r) {
            return { comida: r.comida, bueno: r.bueno, malo: r.malo,
                     marcado: r.marcado }
        })
        if (!Reglas.marcarOtro(copia)) {
            aviso(Idioma.t("Ya no hay nada más que oler"))
            return false
        }
        rastro -= costeOlfato
        caceria = { rastros: copia, pistas: caceria.pistas + 1 }
        guardar()
        olfateado()
        return true
    }

    function elegirRastro(i) {
        if (!caceria || i < 0 || i >= caceria.rastros.length)
            return null
        const r = caceria.rastros[i]
        caceria = null
        _meterEnDespensa(r.comida, 1)
        const c = Reglas.comidaDe(r.comida)
        guardar()
        cazado(r.comida, c ? c.nombre : "", !!r.malo)
        return r
    }

    function cancelarCaza() {
        //  Salirse del rastro sin seguir ninguno. Ya no devuelve nada: el
        //  rastro no se compra, te lo encuentras andando.
        caceria = null
    }

    function molestar() {
        despiertoHasta = ahora() + minutosDespiertoAlaFuerza * 60
        //  Despertarlo cuenta, igual que en los aparatos. Y AHORA SE DICE:
        //  antes esto castigaba en silencio, así que el jugador veía un botón
        //  que no hacía nada mientras por debajo le sumaba descuidos.
        aviso(Idioma.t("Lo has despertado"))
        anotarDescuido("sueño")
        guardar()
    }

    function descubrir(id) {
        const k = String(id)
        if (descubiertos[k])
            return
        const copia = Object.assign({}, descubiertos)
        copia[k] = true
        descubiertos = copia
    }

    // ── exploración ───────────────────────────────────────────────
    //  Los candidatos de una zona: especies con ese field y de etapa cercana
    //  a la tuya, para que explorar en Child no te cruce con un Ultimate.
    function habitantesDe(zonaId, etapaRef) {
        return Reglas.habitantesDe(indice, zonaId, etapaRef)
    }

    //  Un encuentro esperando a que lo mires. Es el punto medio entre las dos
    //  cosas que no pueden ser: que explorar solo avance mientras tienes el
    //  ratón encima —docs/GAMES.md lo prohíbe, y además `pasos` se quedaba en
    //  1 tras dos minutos— y que la barra pelee sola y te devuelva derrotas
    //  que no viste. Los pasos corren siempre; el combate te espera.
    property string enemigoPendiente: ""
    readonly property bool encuentroPendiente: enemigoPendiente !== ""

    //  Avanzar por la carretera. `gesto` dice la zancada: cambiar de ventana
    //  es un paso, cambiar de escritorio dos, abrir una aplicación cinco.
    //
    //  Sustituye al contador de pasos que cada seis soltaba un combate de la
    //  nada. Ahora la distancia es un cuentakilómetros por zona y los eventos
    //  están COLOCADOS en el camino; cruzar un hito es lo que hace que pase
    //  algo.
    function darPaso(gesto) {
        if (!indiceListo)
            return

        //  El huevo se incuba ANDANDO, tengas bicho o no. Va antes que todo
        //  lo demás porque es lo primero que tienes: una partida empieza con
        //  un huevo y sin criatura, y si esto dependiera de `hayPartida` el
        //  primer huevo no rompería jamás.
        if (hayIncubacion && pasosIncubados < pasosParaEclosionar) {
            //  Con la ZANCADA, igual que la carretera. Contaba pulsaciones,
            //  así que abrir una aplicación avanzaba 5 de camino y solo 1 de
            //  huevo: dos monedas distintas para el mismo gesto.
            pasosIncubados = Math.min(pasosParaEclosionar,
                                      pasosIncubados + Reglas.zancadaDe(gesto || "ventana"))
            guardar()
        }

        if (!hayPartida || durmiendo || enfermo)
            return
        //  Con algo interactivo esperando, la carretera SE PARA. Es lo que
        //  evita apilar combates: el camino te espera donde lo dejaste en vez
        //  de acumular cinco bichos mientras trabajas.
        if (encuentroPendiente || caceria)
            return

        const z = indiceZona
        const antes = distanciaEn(zona)
        const fin = Reglas.distanciaJefe(z)
        const punto = Reglas.estadoCarretera(z, antes, vueltaCerrada(zona))
        if (punto !== "andando") {
            if (punto === "terminada")
                return                   // zona terminada: no hay más camino
            //  Al final del camino y con el jefe vivo, el jefe VUELVE A
            //  SALIR. Sin esto, perder contra él te dejaba con la carretera
            //  al máximo, sin hitos por delante y sin manera de volver a
            //  retarlo: la zona quedaba muerta para siempre.
            const j2 = jefeDe(zona)
            if (j2) {
                enemigoPendiente = j2
                jefePendiente = true
                guardar()
                jefeALaVista(j2, zona)
                encuentro(j2)
            }
            return
        }

        const paso = Reglas.zancadaDe(gesto || "ventana")
        const ahoraD = Math.min(fin, antes + paso)
        _ponerDistancia(zona, ahoraD)
        //  El rastro sigue existiendo: lo gasta el minijuego de los tres
        //  rastros cuando sale como evento del camino.
        rastro += paso

        const hitos = Reglas.hitosEntre(_semillaZona, z, antes, ahoraD)
        for (let i = 0; i < hitos.length; ++i) {
            //  Solo se resuelve UNO interactivo por tanda; el resto del
            //  camino queda sin andar y se retoma después.
            if (_resolverHito(hitos[i]))
                break
        }
        guardar()
    }

    //  Devuelve true si el hito EXIGE al jugador y hay que parar el camino.
    function _resolverHito(h) {
        if (h.jefe) {
            if (jefeVencido(zona))
                return false
            const j = jefeDe(zona)
            if (!j)
                return false
            enemigoPendiente = j
            jefePendiente = true
            jefeALaVista(j, zona)
            encuentro(j)
            return true
        }
        switch (h.evento) {
        case "bicho": {
            const pool = habitantesDe(zona, etapa)
            if (pool.length === 0)
                return false
            enemigoPendiente = pool[Math.floor(Math.random() * pool.length)]
            jefePendiente = false
            encuentro(enemigoPendiente)
            return true
        }
        case "rastro":
            //  El minijuego de los tres rastros, que era la caza. Aquí no
            //  cuesta rastro: ya has pagado andando hasta el hito.
            caceria = Reglas.montarCaza(zona, Reglas.entrenoDe(entrenos, "vel"),
                                        etapa, Math.random)
            cazas += 1
            hallado("rastro", "")
            return true
        case "hallazgo": {
            //  Lo que se encuentra sin pelear: comida de la zona, o bits.
            const tabla = Reglas.CAZA_POR_ZONA[zona] || ["grande"]
            if (Math.random() < 0.35) {
                const b = 5 + Math.floor(Math.random() * 20)
                bits += b
                hallado("bits", String(b))
            } else {
                const c = tabla[Math.floor(Math.random() * tabla.length)]
                _meterEnDespensa(c, 1)
                hallado("comida", c)
            }
            return false
        }
        case "datos": {
            const pool2 = habitantesDe(zona, etapa)
            if (pool2.length === 0)
                return false
            const id = pool2[Math.floor(Math.random() * pool2.length)]
            descubrir(id)
            hallado("datos", id)
            return false
        }
        default:
            return false          // «nada»: el camino respira
        }
    }

    signal hallado(string clase, string dato)


    //  Lo consume la vista al entrar en el mapa.
    function tomarEncuentro() {
        if (!encuentroPendiente)
            return null
        const e = enemigoPendiente
        enemigoPendiente = ""
        const r = resolverCombate(e)
        //  Si el aliado salió, se cobra: misma factura que jugando a mano.
        if (r && r.aliadoUsado)
            gastarLlamada()
        guardar()
        return r
    }

    // ── los pasos que das tú ──────────────────────────────────────
    property real _ultimoPasoActividad: 0

    //  Cuántas ventanas había la última vez: si sube, es que se ha ABIERTO
    //  una aplicación, que es el tranco más largo. No se mira cuál: solo
    //  cuántas hay, igual que solo se mira QUE hubo un cambio de ventana.
    property int _cuantasVentanas: 0

    function _pasoPorActividad() {
        if (!indiceListo)
            return
        const t = ahora()
        if (t - _ultimoPasoActividad < segundosEntrePasos)
            return
        _ultimoPasoActividad = t

        //  Qué gesto ha sido, para saber la zancada. Se distingue por lo
        //  único observable sin leer nada: si el NÚMERO de ventanas ha subido,
        //  se ha abierto una aplicación. Ni títulos, ni pids, ni nombres.
        let gesto = "ventana"
        const n = Hyprland.toplevels ? Hyprland.toplevels.values.length : 0
        if (n > _cuantasVentanas && _cuantasVentanas > 0)
            gesto = "app"
        _cuantasVentanas = n

        darPaso(gesto)
    }

    //  Cambiar de escritorio es un tranco más largo que cambiar de ventana:
    //  te has movido a otro sitio, no solo mirado a otro lado.
    function _pasoPorEscritorio() {
        if (!indiceListo)
            return
        const t = ahora()
        if (t - _ultimoPasoActividad < segundosEntrePasos)
            return
        _ultimoPasoActividad = t
        darPaso("escritorio")
    }

    //  Directo a Hyprland y no a través de `Ventanas`/`Workspaces`: es la
    //  señal que el resto de la barra ya usa para esto —`Notifs` y el propio
    //  `Ventanas` cuelgan de ella— y quitando el intermediario se quita la
    //  duda de si el singleton de en medio estaba instanciado.
    //
    //  `activeToplevel` cambia tanto al saltar de ventana como al saltar de
    //  escritorio (porque cambia la ventana con foco), así que con una basta.
    //  Hijo suelto y NO `property var`: es el idioma que usan `Notifs` y
    //  `Ventanas` para esta misma señal, y es el que funciona. Colgado de una
    //  property no llegaba ni una.
    Connections {
        target: Hyprland
        function onActiveToplevelChanged() { dv._pasoPorActividad() }
        //  El escritorio aparte, con su zancada. `focusedWorkspace` cambia al
        //  saltar de escritorio aunque la ventana con foco sea la misma.
        function onFocusedWorkspaceChanged() { dv._pasoPorEscritorio() }
    }

    //  Un latido lento solo para que «concentrado» cambie sin depender de que
    //  pase nada más. Un minuto: es un estado de ánimo, no un cronómetro.
    property var _calmaTimer: Timer {
        interval: 60000
        repeat: true
        running: dv.hayPartida
        onTriggered: dv._ahoraCalma = dv.ahora()
    }

    property var _pasoTimer: Timer {
        interval: dv.segundosPorPaso * 1000
        repeat: true
        //  Corre también sin bicho: hay un huevo que romper.
        running: dv.indiceListo && !dv.durmiendo && !dv.enfermo
              && !dv.encuentroPendiente
        onTriggered: dv.darPaso("reloj")
    }

    function cambiarZona(z) {
        if (!zonaAbierta(z))
            return false
        zona = z
        guardar()
        return true
    }

    // ── combate ───────────────────────────────────────────────────
    //  Se resuelve entero de una vez y la vista lo reproduce: así el
    //  resultado no depende de que la ventana siga abierta ni de a cuántos
    //  fps vaya la animación.
    //  Con qué estados ENTRAS a la pelea. Hoy solo el veneno de la comida,
    //  pero el hueco existe para lo que venga: un estado que se borrase al
    //  abrir el combate no sería un castigo, sería un adorno.
    readonly property var estadosDeEntrada: envenenado
            ? [{ tipo: "veneno", turnos: Reglas.ESTADOS.veneno.turnos }] : []

    function resolverCombate(idEnemigo) {
        return Reglas.resolverCombate(indice, especie, idEnemigo, {
            fuerza: entrenos, enfermo: enfermo, hambre: hambre,
            animo: animo, maxCorazones: maxCorazones, zona: zona,
            vigor: vigor, estadosMios: estadosDeEntrada,
            //  El aliado también entra en la pelea sin manos: si solo saliera
            //  jugando a mano, criar un segundo bicho valdría distinto según
            //  por dónde pelees, y eso no lo entiende nadie. Y solo si hay
            //  energía para pagarlo, que es lo que cuesta a mano.
            aliado: puedeLlamar ? aliado : null
        })
    }

    //  Un choque: lo que eliges tú contra lo que elige él.
    //
    //  `turno` es el número de intercambio DENTRO de este combate, no el
    //  total de combates jugados: de él salen la técnica y la forma que rota
    //  el rival, y con el contador global el rival empezaba siempre en el
    //  mismo sitio y no rotaba nunca dentro de una misma pelea.
    //  `o.mio` y `o.entrenosMios` existen para el PVP: en el segundo y el
    //  tercer asalto no pelea el bicho que llevas encima, sino el que toque de
    //  tu equipo. Sin ellos el combate solo sabía pelear con `especie`, y el
    //  PVP habría acabado siendo tres veces el mismo bicho.
    //
    //  Y en el PVP el cuidado NO cuenta: el hambre y la enfermedad son cosa de
    //  la partida de cada uno, y colarlas en un duelo haría que ganase quien
    //  hubiera abierto la barra más recientemente.
    function choque(idEnemigo, mia, carga, forma, estadosMios, estadosSuyos, turno, o) {
        o = o || {}
        const idMio = o.mio || especie
        const entMios = o.entrenosMios || entrenos
        const pvp = !!o.pvp
        return Reglas.intercambio(indice, idMio, idEnemigo, {
            fuerza: entMios, zona: pvp ? "" : zona, mia: mia, carga: carga,
            forma: forma || "simple", vigor: pvp ? 0 : vigor,
            estadosMios: estadosMios || [], estadosSuyos: estadosSuyos || [],
            enfermo: pvp ? false : enfermo,
            hambre: pvp ? maxCorazones : hambre,
            animo: pvp ? maxCorazones : animo,
            maxCorazones: maxCorazones,
            statsSuyo: o.entrenosSuyos
                     ? Reglas.statsDe(indice, idEnemigo, o.entrenosSuyos)
                     : undefined,
            turno: turno === undefined ? 0 : turno
        })
    }

    //  Qué haría el bicho por su cuenta. Es el mismo criterio con el que juega
    //  el rival —y con el que se midió el equilibrio— así que dejarle pelear
    //  solo no es dejarle pelear mal.
    function eligeAccion(id, ent) {
        return Reglas.eligeRival(indice, id || especie, Math.random,
                                 Reglas.statsDe(indice, id || especie,
                                                ent || entrenos))
    }

    //  Las técnicas que puedes usar ahora mismo, con su forma. Es lo que
    //  enseña el selector del combate. Con argumentos, las de otro bicho: el
    //  PVP las necesita para los asaltos que no pelea el que llevas encima.
    function tecnicasFormasDe(id, ent) {
        return Reglas.tecnicasConForma(indice, id, ent || {})
    }

    readonly property var tecnicasFormas: hayPartida
            ? Reglas.tecnicasConForma(indice, especie, entrenos) : []

    //  El aliado: el mejor criado de la guardería. Sale una vez por combate y
    //  cuesta lo mismo que costaba la llamada, porque la sustituye.
    readonly property var aliado: hayPartida && banco.length > 0
            ? Reglas.aliadoDe(indice, banco) : null

    function golpeDelAliado(idEnemigo) {
        return aliado ? Reglas.golpeAliado(indice, aliado, idEnemigo) : null
    }

    //  Descontar un intercambio a los estados y decir lo que quema el veneno.
    function tickEstados(estados, vidaMax) {
        return Reglas.tickEstados(estados, vidaMax)
    }

    function aplicarEstado(estados, tipo) {
        return Reglas.aplicarEstado(estados, tipo)
    }

    function textoEstado(tipo) {
        const d = Reglas.ESTADOS[tipo]
        return d ? d.texto : ""
    }

    //  Con qué pinta pega esta especie: forma por arquetipo, halo por
    //  atributo. Lo decide `Reglas` para que se pueda probar sobre las 1488
    //  fichas de golpe, que es como se vio que el 41 % caía en el respaldo.
    function golpeVistaDe(id) {
        return Reglas.golpeVistaDe(indice, id)
    }

    function glifoEstado(tipo) {
        const d = Reglas.ESTADOS[tipo]
        return d ? d.glifo : ""
    }

    //  Cobrar un combate jugado a mano, donde la vista ya sabe quién ganó.
    //  Y AQUÍ se consume el encuentro, no al empezar: si el jugador se va a
    //  mitad, se lo encuentra esperando en vez de haberlo perdido por cerrar.
    function aplicarResultado(idEnemigo, gane) {
        const eraJefe = jefePendiente
        enemigoPendiente = ""
        jefePendiente = false
        aplicarCombate({ enemigo: idEnemigo, gane: gane })

        if (!gane) {
            //  Perder contra el jefe no borra el camino andado: el jefe sigue
            //  ahí esperando. Mandar al jugador a empezar la zona de cero
            //  castigaría el intento, que es justo lo que se quiere premiar.
            return
        }

        //  Del jefe, datos SEGUROS: es el premio de la zona. El escaneo
        //  normal vive en `aplicarCombate`, por donde pasan los dos caminos
        //  —la pelea a mano y la del IPC—; aquí solo se fuerza el del jefe.
        if (eraJefe)
            escanear(idEnemigo, true)

        if (eraJefe) {
            const copia = Object.assign({}, jefesVencidos)
            copia[zona] = true
            jefesVencidos = copia
            //  Y la vuelta queda cerrada: el jefe no vuelve a salir hasta que
            //  rehagas el camino.
            const copiaJ = Object.assign({}, jefeVuelta)
            copiaJ[zona] = vueltaDe(zona)
            jefeVuelta = copiaJ
            //  Y de premio, esfuerzo: es lo que abre la siguiente evolución.
            //  El jefe entrena de golpe: reparte entre las cuatro, y da el
            //  triple de experiencia. Es el atajo para subir de etapa.
            _sumarEntreno(2)
            xp += Reglas.xpDe(indice, idEnemigo, true) - Reglas.xpDe(indice, idEnemigo, false)
            bits += Reglas.bitsDe(indice, idEnemigo, true)
                  - Reglas.bitsDe(indice, idEnemigo, false)
            //  Y el DIGIMENTAL de la zona, que es lo que convierte al jefe en
            //  algo más que una barra de vida: cada zona suelta el suyo y
            //  cada uno abre unas evoluciones Armor distintas.
            const dig = Reglas.digimentalDeZona(zona)
            if (dig)
                _meterObjeto(dig, 1)
            jefeCaido(idEnemigo, zona)
        } else {
        }
        guardar()
    }

    //  Aplicar es aparte de resolver para que la vista pueda enseñar los
    //  turnos y solo entonces cobrar el resultado.
    function aplicarCombate(res) {
        if (!res)
            return
        descubrir(res.enemigo)
        //  El vigor de la carne se gasta POR COMBATE. Aquí y no en la vista
        //  porque por esta función pasan los dos caminos —la pelea a mano y
        //  la del IPC— y un consumible que solo se gastara por uno de ellos
        //  sería munición infinita para quien pelee por el otro.
        if (vigor > 0)
            vigor -= 1
        if (res.gane) {
            //  Bits: la moneda sale de pelear, escalada por la etapa del
            //  rival, igual que la experiencia. Premia subir de nivel de
            //  juego, no repetir mil veces el combate más fácil.
            bits += Reglas.bitsDe(indice, res.enemigo, false)
            //  Ganar deja datos, con suerte. Aquí y no en `aplicarResultado`
            //  porque por aquí pasan la pelea jugada Y la del IPC.
            escanear(res.enemigo, false)
            victorias += 1
            //  Pelear también entrena, poco y repartido.
            _sumarEntreno(1)
            xp += Reglas.xpDe(indice, res.enemigo, false)
            //  `energy_gain`: ganar recarga algo. Encadenar combates es
            //  viable, pero no gratis.
            energia = Math.min(maxEnergia, energia + 1)
            animo = Math.min(maxCorazones, animo + 1)
        } else {
            derrotas += 1
            animo = Math.max(0, animo - 1)
            hambre = Math.max(0, hambre - 1)
        }
        guardar()
    }

    // ── partida ───────────────────────────────────────────────────
    //  Se empieza en Baby I, como toca. Se elige entre los que tengan camino
    //  hacia arriba, porque nacer en un callejón sin salida es un bug con
    //  forma de huevo.
    //  Abrir un huevo teniendo bicho ya NO lo tira: lo manda a la guardería.
    //  Si está llena, no se abre —y se dice—: perder una crianza de horas
    //  por pulsar un botón sería imperdonable.
    //  Una partida empieza con un HUEVO, no con un bicho.
    //
    //  Antes te daba un Baby I ya nacido y el aparato arrancaba con una
    //  criatura andando: te saltabas lo primero que hace cualquiera de estos
    //  cacharros, que es esperar a que rompa. La incubación ya existía —para
    //  los huevos que capturas— y no había ninguna razón para que la tuya
    //  fuese distinta.
    function nuevaPartida() {
        if (hayPartida && !_alBanco())
            return false

        const semillas = []
        for (const k in indice) {
            if (indice[k].l === "Baby I" && candidatosEvolucion(k).length > 0)
                semillas.push(k)
        }
        if (semillas.length === 0)
            return false

        //  Sin criatura: solo el huevo. `hayPartida` es falso hasta que rompa.
        especie = ""
        incubando = semillas[Math.floor(Math.random() * semillas.length)]
        pasosIncubados = 0
        nacidoEn = 0
        etapaDesde = 0
        hambre = maxCorazones
        animo = maxCorazones
        entrenos = ({ pv: 0, atq: 0, def: 0, vel: 0 })
        xp = 0
        errores = 0
        enfermo = false
        victorias = 0
        derrotas = 0
        peso = 0
        suciedad = 0
        suciedadDesde = 0
        sobrealimentado = 0
        _cacasPendientes = 0
        energia = Math.floor(maxEnergia / 2)
        _restoEnergia = 0
        zona = "Nature Spirits"
        _cursorCuidado = ahora()
        despiertoHasta = 0
        envenenado = false
        vigor = 0
        ultimoTick = ahora()
        guardar()
        return true
    }

    //  «Soltar» pasa a ser «dejar en la guardería»: no se tira nada.
    function soltar() {
        if (_alBanco())
            guardar()
    }

    // ── ticks ─────────────────────────────────────────────────────
    property var _tick: Timer {
        interval: 1000
        repeat: true
        running: dv.hayPartida && dv.indiceListo
        onTriggered: {
            const t = dv.ahora()
            //  Tope de 5 s por tick igual que la mazmorra: si el equipo se
            //  suspende, el salto lo cobra `recuperarOffline`, no esto.
            const delta = Math.max(0, Math.min(5, t - dv.ultimoTick))
            dv.ultimoTick = t
            dv.avanzarCuidado(delta)
        }
    }

    property var _guardadoPeriodico: Timer {
        interval: 30000
        repeat: true
        running: dv.hayPartida
        onTriggered: dv.guardar()
    }

    //  Lo que pasó con la barra cerrada, con tope. Devuelve el resumen para
    //  que la vista pueda contarlo al abrir: volver y no saber qué te has
    //  perdido es lo que hace que no vuelvas.
    function recuperarOffline(desde) {
        if (!hayPartida || desde <= 0)
            return null
        const transcurrido = Math.min(topeOfflineSegundos, Math.max(0, ahora() - desde))
        if (transcurrido < 60)
            return null
        const antesH = hambre, antesA = animo, antesE = errores

        //  A trozos y no de golpe: la ventana puede cruzar la noche entera, y
        //  preguntando una sola vez —con la hora a la que VUELVES— ocho horas
        //  de sueño contarían como ocho horas de hambre. Volver por la mañana
        //  te encontraba el bicho enfermo por haber dormido.
        const paso = 900
        const inicio = ahora() - transcurrido
        for (let t = 0; t < transcurrido; t += paso) {
            const trozo = Math.min(paso, transcurrido - t)
            avanzarCuidado(trozo, inicio + t + trozo / 2)
        }

        return {
            segundos: Math.floor(transcurrido),
            hambre: antesH - hambre,
            animo: antesA - animo,
            errores: errores - antesE,
            tope: transcurrido >= topeOfflineSegundos
        }
    }

    // ── imágenes, en la caché del usuario ─────────────────────────
    //  No se empaquetan porque no son nuestras: se piden a la API la primera
    //  vez y se quedan en ~/.local/state/k4/plugins/digivice/img.
    property var _cola: []
    property bool _bajando: false
    property int imagenesListas: 0

    function pedirImagen(id) {
        const d = datoDe(id)
        if (!d || _cola.indexOf(String(id)) >= 0)
            return
        _cola = _cola.concat([String(id)])
        _siguienteImagen()
    }

    function _siguienteImagen() {
        if (_bajando || _cola.length === 0 || !_dirsListos)
            return
        const id = _cola[0]
        _bajando = true
        _bajada.command = ["curl", "-s", "--max-time", "20", "-f",
                           "-A", "k4-digivice/1.0", "-o",
                           rutaCruda(id), urlImagen(id)]
        _bajada.running = true
    }

    function _terminarImagen() {
        _cola = _cola.slice(1)
        _bajando = false
        //  Cambiar esto es lo que hace que la silueta se vuelva bicho: las
        //  vistas releen el fichero cuando el contador se mueve.
        imagenesListas += 1
        _siguienteImagen()
    }

    property var _bajada: Process {
        onExited: function (codigo) {
            if (codigo !== 0 || dv._cola.length === 0) {
                dv._terminarImagen()
                return
            }
            //  Tanto las ilustraciones de digi-api (las 1488 opacas, no hay
            //  ni una transparente) como los sprites monocromos vienen con
            //  fondo blanco, y sobre la island oscura eso es un recorte de
            //  papel pegado. Se rellena desde el BORDE y no por color: quitar
            //  "todo lo blanco" le abre agujeros a los que son blancos por
            //  dentro y Gomamon se queda sin tripa (medido: 12 800 píxeles de
            //  más). Aquí además convierte de GIF a PNG, que la mitad de los
            //  sprites vienen en GIF. ImageMagick ya es dependencia base.
            const cruda = dv.rutaCruda(dv._cola[0])
            const f = dv.rutaImagen(dv._cola[0])
            //  Y `-trim` al final porque los sprites vienen con lienzo de
            //  sobra: el de Jyarimon son 192×192 con el bicho ocupando 72×60
            //  abajo del todo. Sin recortar, se pinta diminuto y descentrado
            //  dentro de su hueco.
            dv._recorte.command = [
                "magick", cruda + "[0]", "-alpha", "set",
                "-bordercolor", "white", "-border", "1",
                "-fuzz", "8%", "-fill", "none", "-floodfill", "+0+0", "white",
                "-shave", "1x1", "-trim", "+repage", f
            ]
            dv._recorte.running = true
        }
    }

    //  Si el recorte falla nos quedamos con la imagen opaca: fea, pero está.
    property var _recorte: Process {
        onExited: dv._terminarImagen()
    }

    //  El directorio primero y la lectura después: leer de uno que no existe
    //  no es un fallo —es la primera partida— pero escribir sí lo sería.
    property bool _dirsListos: false
    property var _mkdir: Process {
        command: ["mkdir", "-p", dv.dirImagenes]
        running: true
        onExited: {
            dv._dirsListos = true
            dv.cargar()
            dv._siguienteImagen()
        }
    }

    // ── datos y persistencia ──────────────────────────────────────
    property var _datos: FileView {
        path: Quickshell.shellPath("plugins/Digivice/datos/digimon.json")
        blockLoading: true
        onLoaded: {
            try {
                dv.indice = JSON.parse(text()).digimon || {}
                dv.totalEspecies = Object.keys(dv.indice).length
                dv.indiceListo = dv.totalEspecies > 0
            } catch (e) {
                dv.indice = ({})
                dv.totalEspecies = 0
                dv.indiceListo = false
            }
        }
    }

    //  Las descripciones van aparte y solo se leen cuando alguien abre la
    //  enciclopedia: es medio megabyte que no tiene por qué pagar en cada
    //  arranque quien solo viene a dar de comer.
    property var descripciones: ({})
    property bool descripcionesListas: false

    function cargarDescripciones() {
        if (descripcionesListas || _desc.path !== "")
            return
        _desc.path = Quickshell.shellPath("plugins/Digivice/datos/digimon-desc.json")
    }

    property var _desc: FileView {
        blockLoading: true
        onLoaded: {
            try {
                dv.descripciones = JSON.parse(text()).desc || {}
            } catch (e) {
                dv.descripciones = ({})
            }
            dv.descripcionesListas = true
        }
    }

    property var _jogress: FileView {
        path: Quickshell.shellPath("plugins/Digivice/datos/jogress.json")
        blockLoading: true
        onLoaded: {
            try {
                dv.indiceJogress = JSON.parse(text()).jogress || {}
            } catch (e) {
                dv.indiceJogress = ({})
            }
        }
    }

    //  Armor, X y Warp: 7 KB. Se carga al arrancar como el de fusiones —lo
    //  mira la pantalla de evolución, que es de las que más se abren.
    property var _especiales: FileView {
        path: Quickshell.shellPath("plugins/Digivice/datos/especiales.json")
        blockLoading: true
        onLoaded: {
            try {
                dv.indiceEspeciales = JSON.parse(text()) || ({})
            } catch (e) {
                dv.indiceEspeciales = ({})
            }
        }
    }

    property var _sprites: FileView {
        path: Quickshell.shellPath("plugins/Digivice/datos/sprites.json")
        blockLoading: true
        onLoaded: {
            try {
                dv.indiceSprites = JSON.parse(text()).sprites || {}
            } catch (e) {
                //  Sin índice de sprites se juega igual: todo cae a la
                //  ilustración, que es lo que había antes.
                dv.indiceSprites = ({})
            }
        }
    }

    readonly property string ruta: dirEstado + "/partida.json"

    function instantanea() {
        return {
            version: 1,
            especie: especie, nacidoEn: nacidoEn, etapaDesde: etapaDesde,
            hambre: hambre, animo: animo, entrenos: entrenos, errores: errores,
            enfermo: enfermo, victorias: victorias, derrotas: derrotas,
            xp: xp, dificultad: dificultad,
            zona: zona, descubiertos: descubiertos,
            distancias: distancias, vueltas: vueltas, jefeVuelta: jefeVuelta,
            peso: peso, suciedad: suciedad, sobrealimentado: sobrealimentado,
            energia: energia, restoEnergia: _restoEnergia,
            suciedadDesde: suciedadDesde, cacasPendientes: _cacasPendientes,
            despiertoHasta: despiertoHasta,
            banco: banco, criados: criados, datos: datos,
            incubando: incubando, pasosIncubados: pasosIncubados,
            jefesVencidos: jefesVencidos,
            jefePendiente: jefePendiente,
            enemigoPendiente: enemigoPendiente,
            cursorCuidado: _cursorCuidado,
            hambreDesdeCero: hambreDesdeCero, animoDesdeCero: animoDesdeCero,
            despensa: despensa, envenenado: envenenado, vigor: vigor,
            rastro: rastro,
            bits: bits, objetos: objetos, objetivosCobrados: objetivosCobrados,
            codigosVencidos: codigosVencidos, ultimoCodigo: ultimoCodigo,
            etapaMax: etapaMax, evoluciones: evoluciones,
            fusiones: fusiones, cazas: cazas,
            cerradoEn: ahora()
        }
    }

    function guardar() {
        if (!_dirsListos)
            return
        _partida.setText(JSON.stringify(instantanea(), null, 1))
    }

    //  Lo que había en disco. Una partida rota no puede impedir arrancar: se
    //  empieza de cero y el fichero malo se queda por si hay algo que salvar.
    signal recuperado(var resumen)

    function cargar() {
        let d = {}
        try {
            const bruto = _partida.text()
            if (bruto && bruto.length > 0)
                d = JSON.parse(bruto)
        } catch (e) {
            return
        }
        //  Con huevo y sin criatura TAMBIÉN hay partida que cargar. Esta
        //  guarda pedía `especie` y nada más, así que desde que una partida
        //  empieza por un huevo el huevo se perdía en cada reinicio: abrías
        //  la barra y el aparato decía «sin huevo».
        if (!d.especie && !d.incubando)
            return

        especie = d.especie
        nacidoEn = d.nacidoEn || ahora()
        etapaDesde = d.etapaDesde || nacidoEn
        hambre = d.hambre !== undefined ? d.hambre : maxCorazones
        animo = d.animo !== undefined ? d.animo : maxCorazones
        entrenos = _entrenosDe(d)
        xp = d.xp || 0
        dificultad = d.dificultad || "normal"
        errores = d.errores || 0
        enfermo = !!d.enfermo
        victorias = d.victorias || 0
        derrotas = d.derrotas || 0
        distancias = d.distancias || ({})
        //  Una partida anterior a la carretera no tiene distancias, pero sí
        //  jefes vencidos. Esas zonas tienen su camino HECHO: dejarlas a cero
        //  con el jefe ya caído las enseñaba como «terminadas» estando en el
        //  kilómetro cero, que es una contradicción a la vista del jugador.
        if (!d.distancias && d.jefesVencidos) {
            const dd = {}
            for (let iz = 0; iz < zonas.length; ++iz) {
                const zz = zonas[iz].id
                if (d.jefesVencidos[zz])
                    dd[zz] = Reglas.distanciaJefe(iz)
            }
            distancias = dd
        }
        vueltas = d.vueltas || ({})
        //  Una partida anterior a las vueltas tiene jefes vencidos en la
        //  vuelta 0, que es donde está: así su zona sale cerrada, no con el
        //  jefe otra vez plantado en la puerta.
        jefeVuelta = d.jefeVuelta || ({})
        if (!d.jefeVuelta && d.jefesVencidos) {
            const j0 = {}
            for (const k in d.jefesVencidos) if (d.jefesVencidos[k]) j0[k] = 0
            jefeVuelta = j0
        }
        //  Una partida anterior a la despensa no tiene ninguno de estos
        //  campos, y eso no puede impedirle seguir jugando: se entra con la
        //  despensa vacía, sin veneno y sin vigor, que es exactamente donde
        //  estaba.
        despensa = d.despensa || {}
        envenenado = !!d.envenenado
        vigor = d.vigor || 0
        rastro = d.rastro || 0
        bits = d.bits || 0
        objetos = d.objetos || {}
        objetivosCobrados = d.objetivosCobrados || {}
        codigosVencidos = d.codigosVencidos || {}
        ultimoCodigo = d.ultimoCodigo || ""
        evoluciones = d.evoluciones || 0
        fusiones = d.fusiones || 0
        cazas = d.cazas || 0
        //  Una partida vieja no lleva `etapaMax`; se deduce de en qué etapa
        //  está ahora, que es lo más justo que se puede saber sin inventar.
        etapaMax = d.etapaMax !== undefined ? d.etapaMax
                 : Math.max(0, Reglas.ESCALERA.indexOf(
                       datoDe(d.especie) ? datoDe(d.especie).l : ""))
        peso = d.peso || 0
        energia = d.energia || 0
        _restoEnergia = d.restoEnergia || 0
        suciedad = d.suciedad || 0
        sobrealimentado = d.sobrealimentado || 0
        suciedadDesde = d.suciedadDesde || 0
        _cacasPendientes = d.cacasPendientes || 0
        despiertoHasta = d.despiertoHasta || 0
        banco = d.banco || []
        criados = d.criados || ({})
        datos = d.datos || ({})
        incubando = d.incubando || ""
        pasosIncubados = d.pasosIncubados || 0
        //  Partidas de antes de la colección: el que llevas cuenta como
        //  criado, que para eso lo has criado.
        if (especie && !criados[especie])
            marcarCriado(especie)
        jefesVencidos = d.jefesVencidos || ({})
        jefePendiente = !!d.jefePendiente
        zona = d.zona || "Nature Spirits"
        enemigoPendiente = d.enemigoPendiente || ""
        descubiertos = d.descubiertos || ({})
        //  Una partida del modelo viejo no trae cursor: se arranca desde
        //  ahora, que es lo único honesto — la deuda que llevara guardada era
        //  precisamente lo que había que quitar.
        _cursorCuidado = d.cursorCuidado || ahora()
        hambreDesdeCero = d.hambreDesdeCero || 0
        animoDesdeCero = d.animoDesdeCero || 0

        //  Partidas de antes de que existiera la báscula: un peso de 0 no
        //  es «está flaco», es «no había peso». Se le pone el mínimo de su
        //  etapa, que es también el invariante que el resto del código da
        //  por supuesto.
        if (peso < pesoMinimo)
            peso = pesoMinimo

        ultimoTick = ahora()
        const resumen = recuperarOffline(d.cerradoEn || 0)
        if (resumen)
            recuperado(resumen)
    }

    property var _partida: FileView {
        path: dv.ruta
        blockLoading: true
    }
}
