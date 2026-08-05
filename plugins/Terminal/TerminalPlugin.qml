//  La terminal de la casa, vista desde la barra.
//
//  k4term vive fuera (Rust, libghostty + GPUI) y esta es su embajada: abre
//  ventanas por IPC y convierte en aviso lo que la terminal cuenta.
//
//  El plugin no ocupa la island nunca. Es una pieza de servicio con forma de
//  plugin, y está bien así: se enciende y se apaga desde Ajustes como todo lo
//  demás, y su target de IPC se desregistra solo al apagarlo.
//
//      quickshell ipc -p shell.qml call k4.term abrir
//      quickshell ipc -p shell.qml call k4.term aqui
//      quickshell ipc -p shell.qml call k4.term ejecutar "yay -Syu"

import QtQuick
import K4 as K4
import "../../core"
import "../../services"

K4Plugin {
    id: self

    name: "terminal"
    title: Idioma.t("Terminal")
    //  Por encima del reproductor y del reloj, por debajo del lanzador: si
    //  estás escribiendo en ella, ninguna canción te la quita.
    priority: 75
    active: abierto

    //  ── la terminal de la island ──────────────────────────────────
    //
    //  Para lo rápido: un `systemctl restart`, un `git status`, mirar cómo va
    //  algo. La sesión vive en k4term-isla, fuera de la barra, así que cerrar
    //  la vista no para nada y volver a abrirla te devuelve donde estabas.
    property bool abierto: false

    //  La estela del cursor y la letra las dice la SESIÓN, que lee los
    //  ajustes de k4term y los vigila: así la isla y la ventana usan lo mismo
    //  tocando un solo sitio. Se declaran abajo, junto a la lista.

    grabKeyboard: abierto
    islandWidth: 900

    //  La island crece con lo que hay dentro, que es lo que se espera de
    //  ella: un `ls` de tres líneas no tiene por qué abrir un cajón de medio
    //  monitor.
    //
    //  Ojo al lazo, que es la trampa de esto: la island decide cuántas filas
    //  tiene el PTY, así que «lo escrito» nunca puede pasar de lo que cabe y
    //  medir el contenido para decidir el tamaño no lleva a ninguna parte.
    //  Lo que funciona es al revés: se abre pequeña y se ensancha cuando se
    //  LLENA, y se recoge cuando se queda medio vacía —después de un `clear`,
    //  por ejemplo—. Con margen entre las dos condiciones para que no baile.
    //
    //  La medida de la letra se toma AQUÍ y la vista la usa de aquí, aunque
    //  quien pinta es ella. Tenerla en los dos sitios costó caro: el alto de
    //  la island se calculaba con 18 y la vista dividía por la métrica de
    //  verdad, 17. Salía una fila más de las que cabían, o sea que `usadas`
    //  nunca llegaba a `filas_n`, o sea que la condición de crecer no se
    //  cumplía NUNCA: la island se quedaba en su tamaño mínimo para siempre y
    //  un programa de pantalla completa —claude, vim— se pintaba aplastado en
    //  siete filas con el cursor al fondo de la caja.
    //
    //  El margen y el pie ocupan lo que ocupan; el resto son filas enteras.
    //  El margen, el pie y la tira de pestañas de arriba. Lo que sobra son
    //  filas enteras.
    readonly property int chrome: 62
    readonly property real altoLinea: Math.ceil(metricas.height)

    //  El ancho de celda, en píxeles ENTEROS y recalculado cuando cambia la
    //  letra. Las dos primeras líneas del bloque no sobran, y costaron caro:
    //  `advanceWidth` es una FUNCIÓN, y un enlace de QML solo se reevalúa
    //  cuando cambia una PROPIEDAD que haya leído. Sin nombrar la familia y el
    //  cuerpo, esto se calculaba UNA vez —con la fuente todavía sin resolver—
    //  y se quedaba con el ancho de la tipografía de reserva para siempre:
    //  13,8 px de celda para una letra que mide 7,8. El texto se pintaba a su
    //  ancho y el cursor a casi el doble, así que se separaba hacia la derecha
    //  cuanto más larga era la línea.
    //
    //  Y entero porque así se pinta: con `NativeRendering` los avances se
    //  redondean a píxel, o sea que una celda fraccionaria no la respeta nadie.
    readonly property real anchoCelda: {
        const _familia = metricas.font.family
        const _cuerpo = metricas.font.pixelSize
        return Math.max(1, Math.round(metricas.advanceWidth("M")))
    }

    property FontMetrics metricas: FontMetrics {
        font.family: self.fuente
        font.pixelSize: self.cuerpo
    }

    readonly property int filasMinimas: 6
    readonly property int filasMaximas: 26

    //  Crecer y recoger, a ritmo constante y con UN solo número.
    //
    //  Antes esto iba a empujones: cada marco que llegaba lleno subía el
    //  destino unas filas y una animación corría detrás. Y se veía, porque el
    //  destino solo se mueve cuando llega un marco —cada 30 a 120 ms—: la
    //  animación llegaba, se paraba y esperaba al siguiente empujón. Medido en
    //  una sola crecida: 555, 111, 938 y 733 px/s. Eso es la escalera.
    //
    //  Peor era lo otro: el alto animado y las filas del PTY se calculaban por
    //  separado, así que la caja y el texto de dentro no se movían a la vez —
    //  encogía uno y luego el otro.
    //
    //  Ahora hay un solo número, `filasReales`, que avanza hacia `objetivo` a
    //  ritmo fijo. De él salen LAS DOS COSAS: el alto de la island y las filas
    //  que se le piden a la sesión. Al salir del mismo sitio no pueden ir
    //  desacompasados, y al avanzar de continuo no hay escalones.
    //  Crecer es una cosa y recoger es otra. Crecer acompaña a algo que está
    //  pasando —la salida del mandato llegando— y quiere ir a su ritmo. Al
    //  recoger ya no hay nada que mirar: lo que sobra es hueco vacío, y
    //  arrastrarlo a la misma velocidad se hace largo.
    readonly property real filasPorSegundo: 22
    readonly property real filasPorSegundoAlRecoger: 65
    property real velocidad: filasPorSegundo

    property real objetivo: filasMinimas
    property real filasReales: objetivo
    readonly property int filasDeseadas: Math.max(filasMinimas, Math.round(filasReales))

    //  Lo mueve el motor de animación y no un Timer, y no es un detalle: un
    //  Timer de 16 ms no dispara a sesenta por segundo —medido, salía a menos
    //  de la mitad del ritmo pedido—, mientras que esto va con el refresco de
    //  la pantalla.
    //
    //  Y en `Behavior`, no en `SmoothedAnimation on`: esa segunda forma corre
    //  UNA vez y al terminar se apaga, así que cambiar el destino después no
    //  hacía nada. Se vio claro — la island crecía hasta la mitad y se
    //  plantaba ahí.
    Behavior on filasReales { SmoothedAnimation { velocity: self.velocidad } }

    onMarcoChanged: {
        if (!marco)
            return

        //  Lo primero que llega del otro lado apaga el camino de la conexión.
        //  Regla de dedo, y conviene decirlo: lo del primer cuarto de segundo
        //  es el eco de lo que se acaba de teclear; a partir de ahí, cualquier
        //  salida —el prompt de allí o un «connection refused»— significa que
        //  la espera terminó. Y un tope, por si no llega nada nunca.
        //  Y si el `ssh` ha terminado, se sale del sitio: fuera el color y
        //  fuera la píldora. Lo dice el bloque del mandato —la shell de aquí,
        //  no la de allí— y vale igual para una salida limpia que para un
        //  corte de red.
        if (sesion && sesion.conectadoA && marco.ultimo
                && marco.ultimo.estado !== "corre") {
            salirDe(claveIsla(sesion.numero))
            mandar({ que: "tinte", color: "" })
            Consola.salioDe(sesion.conectadoA)
            sesion.conectadoA = ""
        }

        //  Con un mandato aún por escribir no se apaga nada: los marcos que
        //  llegan ahora son de la sesión recién nacida sacando su prompt, no
        //  respuesta de nadie. Apagarlo aquí dejaba el camino sin verse jamás.
        if (Consola.conectando && !pendiente) {
            const esperado = Date.now() - Consola.conectandoDesde
            if (esperado > 250)
                Consola.conectado()
        }
        //  «Se ha llenado» es llegar a la última fila o a la penúltima. Lo de
        //  la penúltima no es una concesión: un programa de pantalla completa
        //  se ajusta SIEMPRE al hueco que le das, así que nunca se desborda y
        //  nunca pide más — y si su última fila queda en blanco, como el
        //  diálogo de claude, con la condición estricta la island no crecería
        //  jamás y el programa se quedaría apretado para siempre.
        if (marco.usadas >= marco.filas_n - 1) {
            //  Mientras siga llena, hacia arriba sin parar. En cuanto deje de
            //  estarlo se queda donde esté: no hay destino que perseguir a
            //  saltos, solo una dirección.
            recoger.stop()
            velocidad = filasPorSegundo
            objetivo = filasMaximas
        } else if (marco.usadas * 2 <= marco.filas_n && filasReales > filasMinimas) {
            //  Vaciada del todo —un `clear`, salir de un programa— se recoge
            //  YA: no hay nada que confirmar, y esperar ahí es lo que se
            //  sentía como un retraso raro antes de que la caja reaccionara.
            //
            //  Medio vacía es otra cosa y esa sí espera un poco: al pulsar
            //  Intro la pantalla se queda un instante con menos de lo que
            //  tenía antes de que llegue la salida del mandato, y reaccionar a
            //  ese hueco daba un tirón hacia abajo justo antes de crecer
            //  —medido: 26 px de bajada y 73 de subida a continuación—. Con
            //  esperar dos marcos basta para distinguirlo.
            if (marco.usadas <= 2) {
                recoger.stop()
                encoger()
            } else {
                objetivo = filasReales
                recoger.restart()
            }
        } else {
            recoger.stop()
            objetivo = filasReales
        }
    }

    function encoger() {
        velocidad = filasPorSegundoAlRecoger
        objetivo = Math.max(filasMinimas, marco.usadas + 2)
    }

    Timer {
        id: recoger
        interval: 180
        onTriggered: {
            if (!self.marco)
                return
            if (self.marco.usadas * 2 <= self.marco.filas_n
                    && self.filasReales > self.filasMinimas)
                self.encoger()
        }
    }

    //  Cada sesión nueva empieza recogida.

    //  Sin animación por encima: `filasReales` YA se mueve de continuo, y
    //  ponerle una animación detrás solo añadiría un retardo entre el alto y
    //  las filas que se le piden a la sesión, que es justo lo que hacía que la
    //  caja y el texto no fueran al unísono.
    islandHeight: Math.min(560, chrome + filasReales * altoLinea)
    closeOnHoverExit: false
    handlesBackgroundTap: true
    onBackgroundTapped: {}

    view: Component { TerminalIslaView { plugin: self } }

    function mandar(orden) {
        if (sesion)
            sesion.mandar(orden)
    }

    function cerrar() { abierto = false }

    //  ── el portapapeles ───────────────────────────────────────────
    //
    //  La sesión no tiene ninguno: no es una ventana, no habla con el
    //  compositor y no puede. Lo tiene la barra, así que copiar y pegar pasan
    //  por aquí — y de propina, lo copiado entra en el historial de copias de
    //  la casa como cualquier otra copia.
    //
    //  Para pegar se le pregunta al compositor en el momento y no a la caché
    //  del servicio: entre lo que el servicio vio por última vez y lo que hay
    //  ahora puede haber una copia de otra aplicación, y pegar lo de antes es
    //  de las cosas que uno no perdona.
    function alCopiar(texto) {
        if (texto)
            K4.Sistema.copiar(texto)
    }

    function pegar(primaria) {
        pegador.primaria = primaria === true
        pegador.running = true
    }

    property K4.Process pegador: K4.Process {
        property bool primaria: false
        command: primaria ? ["wl-paste", "--primary", "--no-newline"]
                          : ["wl-paste", "--no-newline"]
        onSalida: function (texto) {
            if (texto)
                self.mandar({ que: "pegar", valor: texto })
        }
        onTerminado: running = false
    }

    //  La primaria se pone al soltar la selección, como en cualquier terminal
    //  de siempre: seleccionas, pegas con el botón de en medio.
    function copiarPrimaria(texto) {
        if (texto)
            K4.Sistema.lanzar(["wl-copy", "--primary", "--", String(texto)])
    }

    //  Lo que la sesión contesta cuando se le pide un trozo del historial. El
    //  motivo dice a qué venía: sin él, una copia y una nota llegarían iguales.
    function alRecibirTexto(contenido, motivo) {
        if (motivo === "primaria") {
            copiarPrimaria(contenido)
            return
        }
        if (!contenido) {
            K4.Sistema.avisar(Idioma.t("Terminal"), Idioma.t("No hay nada que copiar"), false)
            return
        }
        K4.Sistema.copiar(contenido)
    }

    //  Un enlace escrito en la terminal, abierto con lo que el escritorio
    //  tenga puesto. El `www.` a secas no es una dirección para nadie: sin
    //  esquema, xdg-open se lo pasaría al navegador como si fuera un fichero.
    function abrirEnlace(url) {
        const limpio = String(url || "")
        if (!limpio)
            return
        K4.Sistema.abrir(limpio.indexOf("www.") === 0 ? "https://" + limpio : limpio)
    }

    //  ── buscar ────────────────────────────────────────────────────
    //
    //  Rebuscar en el historial lo hace la sesión, que es quien lo tiene; aquí
    //  solo se guarda qué se busca y si lo último cayó en algo, para que la
    //  caja lo diga. Lo amarillo de la pantalla lo pinta la vista con lo que
    //  ve, sin preguntar nada.
    property string aguja: ""
    property bool sinRastro: false
    property int filaHallada: -1

    function buscar(hacia) {
        if (!aguja)
            return
        mandar({ que: "buscar", texto: aguja, hacia: hacia })
    }

    function hallazgo(hay, fila) {
        sinRastro = !hay
        filaHallada = hay ? fila : -1
    }

    //  A la nota del día: el último mandato con su salida, o la sesión entera.
    //  Si no hay Edinot abierto, la sesión lo dice y aquí sale como aviso.
    function anotar(entera) { mandar({ que: "nota", entera: entera === true }) }

    //  ── modo tranquilo ────────────────────────────────────────────
    //
    //  Atenúa lo anterior al último mandato. En una sesión de agente de dos
    //  horas, saber dónde empieza lo nuevo vale más que cualquier color.
    //  Arranca como lo digan los ajustes de k4term y se enciende y apaga con
    //  la tecla, que es como se usa: para un rato, no para siempre.
    property bool tranquilo: conf.tranquilo === "si" || conf.tranquilo === "1"
    function alternarTranquilo() { tranquilo = !tranquilo }

    //  ── correr un mandato de la casa aquí dentro ──────────────────
    //
    //  Actualizar el sistema abría una ventana aparte. Teniendo esto, lo suyo
    //  es verlo en la island: se asoma sola, lo enseña, y si la cierras el
    //  mandato sigue corriendo — que es justo para lo que sirve una sesión que
    //  no depende de la vista.
    //
    //  Se ofrece a Consola en vez de que Consola nos busque: un servicio no
    //  puede depender de que un plugin exista, y este se apaga desde Ajustes
    //  como cualquier otro. Al apagarlo se retira la oferta y todo vuelve a
    //  abrirse en ventana.
    Component.onCompleted: Consola.registrarIsla(function (guion) {
        self.correrAqui(guion)
    })
    Component.onDestruction: Consola.registrarIsla(null)

    function correrAqui(guion) {
        if (!Consola.hayIsla) {
            K4.Sistema.lanzar(Consola.orden(guion))
            return
        }
        //  Los mandatos de la casa van SIEMPRE a una terminal nueva, no a la
        //  que tengas delante: si estabas con claude a medias, meterle un
        //  `yay -Syu` por encima sería una faena.
        nueva()
        abierto = true
        mandar({ que: "pinta" })
        //  Siempre con espera, porque siempre es una sesión recién nacida: el
        //  texto que llegue antes de que la shell saque su prompt lo repite el
        //  tty en crudo y el mandato se ve dos veces, una suelta arriba y otra
        //  en su sitio.
        pendiente = guion
        esperarPrompt.restart()
    }

    property string pendiente: ""

    function escribirMandato(guion) {
        //  Ctrl-U delante: si habías dejado algo a medio escribir, el mandato
        //  se pegaría detrás y saldría un engendro.
        //
        //  Y RETORNO al final, no salto de línea. Parece lo mismo y no lo es:
        //  la tecla Intro manda un retorno, y el editor de línea de la shell
        //  espera eso. Con `\n` el mandato se queda escrito y sin ejecutar —
        //  comprobado en vivo, la línea entera ahí quieta.
        //  Si la conexión lleva contraseña, la terminal se la queda ANTES de
        //  que el mandato salga: cuando el otro lado la pida, la escribe ella.
        //  Aquí no se guarda ni se enseña; en cuanto se entrega, se borra.
        if (Consola.claveConexion) {
            //  Si el binario de enfrente es anterior a esto, la orden se la
            //  traga en silencio y la contraseña no se teclea nunca. Se dice,
            //  que quedarse esperando sin saber por qué es lo peor que puede
            //  pasar aquí.
            if (sesion && sesion.sabeClaves) {
                mandar({ que: "clave", valor: Consola.claveConexion })
            } else {
                K4.Sistema.lanzar(["notify-send", "-a", "k4",
                                   Idioma.t("Actualiza k4term"),
                                   Idioma.t("Esta versión de k4term-isla no sabe teclear contraseñas: la conexión te la pedirá a mano.")])
            }
            Consola.claveConexion = ""
        }

        mandar({ que: "texto", valor: String.fromCharCode(0x15) + guion + "\r" })

        //  El cuarto de segundo de gracia se cuenta desde AQUÍ, que es cuando
        //  el mandato sale de verdad: la sesión de la isla se estrena y espera
        //  a que la shell saque su prompt, así que entre pulsar Intro y esto
        //  pasa casi medio segundo — y el eco llegaba «tarde» y apagaba el
        //  camino antes de empezar.
        if (Consola.conectando) {
            Consola.conectandoDesde = Date.now()

            //  El sitio se apunta en la sesión —no en el plugin— porque puede
            //  haber varias, cada una en su servidor.
            if (sesion) {
                sesion.conectadoA = Consola.conectando
                if (Consola.tinteConexion)
                    mandar({ que: "tinte", color: Consola.tinteConexion })
                entrarEn(claveIsla(sesion.numero), Consola.conectando)
            }
        }
    }

    Timer {
        id: esperarPrompt
        interval: 450
        onTriggered: {
            if (!self.pendiente)
                return
            self.escribirMandato(self.pendiente)
            self.pendiente = ""
        }
    }

    function toggle() {
        //  Sin k4term-isla no hay mini-terminal —habla un protocolo que es
        //  nuestro— pero tampoco hay por qué no hacer nada: se abre una
        //  ventana con la terminal que haya.
        if (!Consola.hayIsla) {
            K4.Sistema.lanzar(Consola.abrir(""))
            return
        }
        //  La primera sesión no se arranca hasta que la pides: quien no use la
        //  terminal de la island no paga ni un proceso.
        if (vivas.length === 0)
            nueva()
        abierto = !abierto
        if (abierto)
            mandar({ que: "pinta" })
    }

    //  Sacarla a lo grande: la sesión SE MUDA, no se copia. Se le pide que
    //  ofrezca su PTY por un socket y se abre una ventana que lo recoge; lo
    //  que estuviera corriendo dentro —un agente, un `make`— sigue como si
    //  nada, porque lo que cambia de manos es el maestro y a él lo que lo ata
    //  es el esclavo, que no se toca.
    //
    //  Sin k4term no hay a quién dársela: entonces se abre lo que haya, que es
    //  lo que se hacía antes de que esto existiera.
    function sacar() {
        if (!sesion || !Consola.esNuestra) {
            K4.Sistema.lanzar(Consola.abrir(""))
            return
        }
        mandar({ que: "emigrar" })
    }

    //  La sesión ya está en el socket: se abre la ventana que se la lleva. Al
    //  cogerla, el proceso de la isla se apaga solo y la pestaña se va con él.
    function alEmigrar(socket) {
        if (!socket)
            return
        K4.Sistema.lanzar([Consola.binario, "--heredar", socket])
        abierto = false
    }

    //  ── las sesiones ──────────────────────────────────────────────
    //
    //  Varias, no una. Tener claude en una y codex en otra es justo para lo
    //  que sirve una terminal que vive fuera de la vista: cambias de una a
    //  otra y las dos siguen corriendo.
    //
    //  La lista es un ListModel y no un contador porque hay que poder cerrar
    //  la de en medio: con un número, el Instantiator siempre se llevaría la
    //  última.
    property ListModel listaSesiones: ListModel {}
    property var vivas: []
    property int actual: 0
    property int contador: 0

    readonly property var sesion: vivas.length > 0 && actual < vivas.length
        ? vivas[actual] : null

    readonly property var marco: sesion ? sesion.marco : null
    readonly property int estela: sesion ? sesion.estela : 8
    readonly property string fuente: sesion ? sesion.fuente : "MesloLGS Nerd Font Mono"
    readonly property bool arrancado: vivas.length > 0

    //  El tamaño de letra sale de los ajustes de k4term —los mismos que la
    //  ventana— y encima va el zoom de esta vista, que es de aquí y de ahora:
    //  agrandar para leer un rato no es cambiar tu preferencia. Se guarda
    //  entre aperturas porque quien lo agranda suele quererlo agrandado.
    readonly property int cuerpoBase: sesion ? sesion.cuerpo : 13
    property int zoom: 0
    readonly property int cuerpo: Math.max(8, Math.min(30, cuerpoBase + zoom))

    function acercar(cuanto) { zoom = Math.max(-5, Math.min(17, zoom + cuanto)) }
    function zoomNormal() { zoom = 0 }

    property Instantiator criadero: Instantiator {
        model: self.listaSesiones
        delegate: SesionIsla {
            required property int sid
            required property string socket
            numero: sid
            //  Si viene con socket, esta sesión no arranca una shell: adopta
            //  la que una ventana acaba de soltar.
            heredar: socket
            onDonde: function (ruta) { self.alDecirDonde(ruta) }
            onDifunta: self.alMorir(numero)
            onTrabajo: function (estado, mandato, salida, segundos) {
                self.alTrabajar(numero, estado, mandato, salida, segundos)
            }
            onCampana: function (titulo) { self.alLlamar(numero, titulo) }
            onPortapapeles: function (texto) { self.alCopiar(texto) }
            onTexto: function (contenido, motivo) { self.alRecibirTexto(contenido, motivo) }
            onBuscado: function (hay, fila) { self.hallazgo(hay, fila) }
            onEmigrando: function (socket) { self.alEmigrar(socket) }
            onAviso: function (texto) { K4.Sistema.avisar(Idioma.t("Terminal"), texto, false) }
        }
        onObjectAdded: function (indice, objeto) {
            const v = self.vivas.slice()
            v.splice(indice, 0, objeto)
            self.vivas = v
        }
        onObjectRemoved: function (indice, objeto) {
            //  Lo que esa terminal tuviera anunciado se va con ella. Aquí y no
            //  en `cerrarSesion`, que este es el único sitio por el que pasan
            //  LOS DOS finales: el que cierras tú y el que se muere solo.
            self.limpiarIsla(objeto.numero)
            const v = self.vivas.slice()
            v.splice(indice, 1)
            self.vivas = v
            if (self.actual >= v.length)
                self.actual = Math.max(0, v.length - 1)
            if (v.length === 0)
                self.abierto = false
        }
    }

    function nueva(socket) {
        listaSesiones.append({ sid: ++contador, socket: socket || "" })
        actual = vivas.length - 1
        //  Recogida: cada terminal nueva empieza pequeña, como al abrir. Se
        //  toca SOLO el objetivo: escribir en `filasReales` rompería su
        //  enlace con él —y con `nueva()` corriendo la primera vez que abres
        //  la isla, la caja se quedaba desenganchada desde el minuto uno y no
        //  volvía a crecer nunca—.
        objetivo = filasMinimas
        return vivas[actual]
    }

    function irA(n) {
        if (n >= 0 && n < vivas.length) {
            actual = n
            mandar({ que: "pinta" })
        }
    }

    function siguiente() { if (vivas.length > 1) irA((actual + 1) % vivas.length) }
    function anterior() { if (vivas.length > 1) irA((actual - 1 + vivas.length) % vivas.length) }

    //  Cerrar una sesión se lleva TODO lo suyo, y la píldora de conexión es
    //  lo suyo: la conexión se ha ido con ella. Antes solo se quitaba al
    //  terminar el `ssh`, así que cerrar la pestaña —o matarla— dejaba la
    //  píldora anunciando para siempre un servidor del que ya no queda nada.
    function olvidarSesion(numero) {
        salirDe(claveIsla(numero))
    }

    function cerrarSesion(n) {
        if (n < 0 || n >= listaSesiones.count)
            return
        olvidarSesion(listaSesiones.get(n).sid)
        listaSesiones.remove(n)
    }

    function alMorir(numero) {
        olvidarSesion(numero)
        for (let i = 0; i < listaSesiones.count; ++i)
            if (listaSesiones.get(i).sid === numero) {
                listaSesiones.remove(i)
                return
            }
    }

    //  La sesión contesta dónde está. Ya no se usa para sacarla —ahora la
    //  sesión se muda entera, no se abre otra en su sitio— pero sigue siendo
    //  la forma de saber en qué directorio anda: lo aprovecha quien quiera
    //  abrir algo «aquí mismo».
    function alDecirDonde(ruta) {
        ultimoDirectorio = String(ruta || "")
    }

    property string ultimoDirectorio: ""

    //  Despierta a los dos servicios que le hacen falta: un singleton de QML
    //  no se instancia hasta que alguien lo mira. El del ambiente publica el
    //  tema para la terminal —apagar este plugin deja de publicarlo, que es
    //  justo lo que tiene que pasar— y el de la consola averigua qué
    //  terminal hay instalada, que lo necesita hasta el actualizador.
    readonly property string ambiente: Ambiente.ruta
    readonly property string cual: Consola.binario

    //  ── trabajos en curso ─────────────────────────────────────────
    //
    //  Lo que se está cociendo ahora mismo, por pid de la ventana que lo
    //  corre. La terminal solo cuenta los que llevan unos segundos vivos, así
    //  que aquí no llega el ruido de un `ls`: si algo está apuntado, es
    //  porque de verdad merece un hueco en la píldora.
    property var trabajos: ({})

    //  La cuenta va aparte y no calculada del mapa: reasignar a una propiedad
    //  `var` el MISMO objeto que ya tenía no notifica a nadie, y el latido se
    //  quedaba parado con el indicador clavado en cero. De ahí también que
    //  aquí se copie el mapa en vez de tocarlo por dentro.
    property int enCurso: 0

    //  De aquí para arriba, además del indicador, un aviso al terminar.
    readonly property int avisoSegundos: 20

    function idDe(pid) { return "terminal." + pid }

    //  Un reloj de píldora: cabe en dos dedos de ancho y no baila al pasar de
    //  los sesenta, que es lo que importa cuando está al lado de la hora.
    function reloj(ms) {
        const s = Math.max(0, Math.round(ms / 1000))
        if (s < 60)
            return s + " s"
        const m = Math.floor(s / 60)
        return m + ":" + String(s % 60).padStart(2, "0")
    }

    //  `llevaba` son los segundos que el mandato acumulaba cuando la terminal
    //  se decidió a contarlo: el reloj de la píldora arranca ahí y no en cero,
    //  o enseñaría menos tiempo del que de verdad lleva trabajando.
    //  Los agentes de consola son otra cosa que un mandato largo: no están
    //  «tardando», están pensando, y uno los deja correr a propósito. Se les
    //  da su propio glifo para distinguirlos de un vistazo.
    readonly property var agentes: ["claude", "codex", "aider", "gemini", "opencode", "goose"]

    //  El programa a secas: sin la ruta por delante y sin sus argumentos.
    //  `/usr/bin/python3 tools/goteo.py` es «python3», que es lo que se lee
    //  de un vistazo en una pestaña de dos dedos.
    function programaDe(mandato) {
        const primero = String(mandato).trim().split(/\s+/)[0] || ""
        return primero.split("/").pop()
    }

    function esAgente(mandato) {
        return agentes.indexOf(programaDe(mandato)) >= 0
    }

    //  Con qué se dibuja lo que corre: glifo y color. Está aparte porque lo
    //  usan la píldora y la tira de pestañas de la isla, y dos copias de esta
    //  decisión acabarían diciendo cosas distintas de lo mismo.
    //
    //  Es pura —solo mira el mandato—, así que un enlace de QML puede
    //  llamarla sin miedo mientras lea por su cuenta el mapa de donde saca el
    //  mandato: lo que no reevalúa un enlace es la función, no el dato.
    function insigniaDe(mandato) {
        const agente = esAgente(mandato)
        return { glifo: agente ? Theme.ico.ask.codePointAt(0) : 0xF018D,
                 color: agente ? Theme.green : Theme.blue }
    }

    function apuntar(pid, mandato, llevaba) {
        const t = Object.assign({}, trabajos)
        t[pid] = { mandato: String(mandato),
                   desde: Date.now() - (Number(llevaba) || 0) * 1000 }
        trabajos = t
        enCurso = Object.keys(t).length

        const insignia = insigniaDe(mandato)
        K4.Pildora.registrar(idDe(pid), reloj(0),
                             insignia.glifo, insignia.color, 30, true)
    }

    //  Los que te esperan van con el id aparte: un mandato largo y un agente
    //  que ha acabado su turno son dos cosas distintas y pueden coincidir.
    function idEspera(pid) { return "terminal.espera." + pid }

    //  Y quiénes la tienen puesta. Al registro de píldoras no se le puede
    //  preguntar, así que sin esta lista no hay forma de saber a quién hay
    //  que vigilar: una campana puede quedarse sola mucho después de que su
    //  mandato acabara, y es justo la que más se nota si sobrevive a su
    //  ventana. Va aparte de `trabajos` porque son cosas distintas.
    property var esperas: ({})

    function esperando(pid, titulo) {
        const nombre = String(titulo || "").trim() || Idioma.t("Terminal")
        //  La campana del tema: dice «te llaman» sin necesidad de leerlo, y
        //  en amarillo, que reclama sin alarmar.
        K4.Pildora.registrar(idEspera(pid), nombre.slice(0, 18), Theme.ico.bell.codePointAt(0),
                             Theme.yellow, 29, true)
        //  Se guarda CON QUIÉN, no un `true`: al atenderla hay que poder
        //  retirar su notificación, y para eso hace falta saber cuál era.
        const e = Object.assign({}, esperas)
        e[pid] = nombre
        esperas = e

        //  De QUÉ ventana es este aviso. Sin esto, pulsarlo buscaba «una
        //  ventana de k4term» y con dos abiertas se iba a la más vieja, que es
        //  la de al lado: el aviso te llevaba a la terminal equivocada. Las de
        //  la isla no tienen ventana —su clave es `isla.N`— y ahí no hay pid
        //  que apuntar.
        if (String(pid).indexOf("isla.") !== 0)
            Notifs.apuntarDestino("k4term", nombre, pid)

        K4.Sistema.lanzar(["notify-send", "-a", "k4term", "-t", "8000",
                           Idioma.t("Te está esperando"), nombre])
    }

    function dejarDeEsperar(pid) {
        K4.Pildora.quitar(idEspera(pid))
        if (esperas[pid] === undefined)
            return
        //  La píldora y la notificación cuentan lo MISMO: quitar una y dejar la
        //  otra deja la mitad del aviso puesta, y esa mitad es la que sale
        //  luego en la tira de debajo del reloj.
        Notifs.descartarDeApp("k4term", esperas[pid])
        Notifs.olvidarDestino("k4term", esperas[pid])
        const e = Object.assign({}, esperas)
        delete e[pid]
        esperas = e
    }

    //  ── ir a la terminal ES atenderla ─────────────────────────────
    //
    //  La campana pide una cosa concreta: que vayas. Una vez estás ahí ya ha
    //  hecho lo suyo, y seguir pidiéndolo desde la píldora es ruido. Hasta
    //  ahora solo se iba pulsándola, que es pedir el mismo gesto dos veces: el
    //  de ir a la terminal y el de decirle a la barra que has ido.
    //
    //  Dos caminos porque hay dos terminales. La de ventana se entera por el
    //  pid de la que toma el foco —que es la clave con la que se apuntó—; la
    //  de la isla, por la pestaña que se está viendo, que es la misma regla
    //  con la que `alLlamar` decide no molestar.
    //
    //  El trabajo en curso NO se toca: ese indicador cuenta algo que sigue
    //  pasando y mirarlo no lo acaba.
    property Connections foco: Connections {
        target: Ventanas
        function onPidActivoChanged() {
            self.dejarDeEsperar(Ventanas.pidActivo)
        }
    }

    function atendidaIsla() {
        if (!abierto || actual < 0 || actual >= vivas.length || !vivas[actual])
            return
        dejarDeEsperar(claveIsla(vivas[actual].numero))
    }

    function olvidar(pid) {
        if (trabajos[pid] === undefined)
            return
        const t = Object.assign({}, trabajos)
        delete t[pid]
        trabajos = t
        enCurso = Object.keys(t).length
        K4.Pildora.quitar(idDe(pid))
    }

    function tictac() {
        const ahora = Date.now()
        for (const pid in trabajos)
            K4.Pildora.actualizar(idDe(pid), { texto: reloj(ahora - trabajos[pid].desde) })
    }

    //  Solo late mientras hay algo que contar: sin trabajos, ni un despertar.
    property Timer latido: Timer {
        interval: 1000
        repeat: true
        running: self.enCurso > 0
        onTriggered: self.tictac()
    }

    //  Pulsar el indicador lleva a la ventana que está trabajando. Se
    //  pregunta primero por ella: si ya no existe —la mataron sin avisar— el
    //  indicador se cura solo, y pulsarlo es el único momento en el que
    //  compensa comprobarlo.
    property Connections clics: Connections {
        target: K4.Pildora
        function onInvocado(id) {
            if (String(id).indexOf("terminal.") !== 0)
                return
            //  El de las terminales abiertas no lleva a ninguna ventana: abre
            //  la island por donde la dejaste.
            if (id === self.idAbiertas) {
                self.abierto = true
                self.mandar({ que: "pinta" })
                return
            }
            //  Ir a la ventana quita el aviso de que te espera: ya la has
            //  atendido, que es lo que el indicador estaba pidiendo.
            const espera = String(id).indexOf("terminal.espera.") === 0
            const resto = String(id).substring(espera ? "terminal.espera.".length
                                                      : "terminal.".length)
            //  Por `dejarDeEsperar` y no quitando la píldora a mano: así el
            //  clic retira también la notificación y borra el apunte, que es
            //  lo mismo que hace ir a la terminal. Quitando solo la píldora,
            //  el aviso seguía en el panel y en la tira del reloj.
            if (espera)
                self.dejarDeEsperar(resto)

            //  Si es de la isla, no hay ventana a la que ir: se abre la
            //  terminal por esa misma sesión.
            if (resto.indexOf("isla.") === 0) {
                const donde = self.indiceDe(parseInt(resto.substring(5), 10))
                if (donde >= 0) {
                    self.actual = donde
                    self.abierto = true
                    self.mandar({ que: "pinta" })
                }
                return
            }

            buscar.pid = resto
            buscar.running = true
        }
    }

    //  ── lo que se cuece en las terminales de la isla ──────────────
    //
    //  Lo mismo que ya hacía la ventana, pero llegando por el canal de la
    //  sesión en vez de por el IPC. Y con una ventaja que el IPC no daba:
    //  sabemos de QUÉ terminal viene, así que pulsar el indicador te trae a
    //  ella en vez de buscar una ventana que no existe.
    function claveIsla(numero) { return "isla." + numero }

    function indiceDe(numero) {
        for (let i = 0; i < vivas.length; ++i)
            if (vivas[i].numero === numero)
                return i
        return -1
    }

    //  Un indicador de una terminal que ya no está es una puerta a ninguna
    //  parte: pulsarlo no puede llevarte a nada.
    function limpiarIsla(numero) {
        const clave = claveIsla(numero)
        olvidar(clave)
        dejarDeEsperar(clave)
    }

    function alTrabajar(numero, estado, mandato, salida, segundos) {
        const clave = claveIsla(numero)
        if (estado === "empieza") {
            apuntar(clave, mandato, segundos)
            return
        }
        olvidar(clave)
        if (segundos >= avisoSegundos)
            avisar(mandato, salida, segundos)
    }

    //  La campana solo merece aviso si NO la estás viendo. Teniendo esa
    //  terminal delante ya te has enterado, y avisarte sería ruido — que es
    //  justo la regla que la ventana aplica con el foco.
    function alLlamar(numero, titulo) {
        const mirando = abierto && vivas[actual] && vivas[actual].numero === numero
        if (mirando)
            return
        //  Con quién te llama, no un «Terminal» a secas: el sentido de esto es
        //  saber CUÁL de tus agentes ha acabado su turno. El título que pide
        //  la aplicación es lo que mejor lo dice; el mandato, si no lo hay.
        const donde = indiceDe(numero)
        const quien = (donde >= 0 && vivas[donde].titulo)
            || titulo || Idioma.t("Terminal")
        esperando(claveIsla(numero), quien)
    }

    //  ── a qué estás conectado ─────────────────────────────────────
    //
    //  Una píldora por sesión que está dentro de un servidor. Se apunta con la
    //  clave de quien la abre —el pid de la ventana o la sesión de la isla—
    //  para que dos conexiones a la vez no se pisen.
    function idConexion(clave) { return "terminal.ssh." + clave }

    //  A dónde está conectada cada una, por su clave. Hace falta para poder
    //  decir de QUÉ servidor se ha salido: la ventana solo manda su pid.
    property var dentroDe: ({})

    function entrarEn(clave, destino) {
        const nombre = String(destino || "").trim()
        if (!nombre)
            return
        const d = Object.assign({}, dentroDe)
        d[clave] = nombre
        dentroDe = d
        K4.Pildora.registrar(idConexion(clave), nombre.slice(0, 20),
                             0xF08C0, Theme.blue, 28, true)
    }

    function salirDe(clave) {
        K4.Pildora.quitar(idConexion(clave))
        const destino = dentroDe[clave]
        if (destino) {
            const d = Object.assign({}, dentroDe)
            delete d[clave]
            dentroDe = d
            Consola.salioDe(destino)
        }
    }

    //  Una ventana puede irse sin decir adiós —la matan, se cuelga, se va la
    //  sesión entera— y su píldora se quedaría anunciando un sitio del que no
    //  queda nada. Se comprueba cada pocos segundos, y SOLO mientras haya
    //  alguna de ventana: las de la isla no lo necesitan, que esas sesiones
    //  son nuestras y sabemos cuándo se van.
    //
    //  Y va por las TRES familias, no solo por la de los servidores: el adiós
    //  de la ventana (`k4.term limpiar`) sale de k4term cuando muere su shell,
    //  y cerrar la ventana no pasa por ahí —el proceso se va en el acto y la
    //  shell se entera después, cuando ya no hay quien lo cuente—. Un mandato
    //  largo o una campana se quedaban entonces en la isla para siempre, con
    //  el reloj subiendo. Aquí no se confía en que nadie se despida.
    readonly property var pidsVigilados: {
        const vistos = ({})
        const anotar = function (clave) {
            //  Las de la isla fuera: sus claves son `isla.N`, no pids, y de
            //  esas sesiones ya sabemos cuándo se van.
            if (String(clave).indexOf("isla.") !== 0)
                vistos[String(clave)] = true
        }
        for (const dentro in dentroDe)
            anotar(dentro)
        for (const curro in trabajos)
            anotar(curro)
        for (const llamada in esperas)
            anotar(llamada)
        return Object.keys(vistos)
    }

    property Timer vigilante: Timer {
        interval: 5000
        repeat: true
        running: self.pidsVigilados.length > 0
        onTriggered: self.revisarVentanas()
    }

    function revisarVentanas() {
        const pids = pidsVigilados
        if (pids.length === 0)
            return
        vivos.command = ["sh", "-c",
            "for p in " + pids.join(" ") + "; do [ -d /proc/$p ] && echo $p; done"]
        vivos.running = true
    }

    //  Al que ya no está se le quitan las tres de golpe: cada una se sabe
    //  ignorar si no era suya, y así no hay que averiguar de qué murió.
    function despedir(pid) {
        salirDe(pid)
        olvidar(pid)
        dejarDeEsperar(pid)
    }

    property K4.Process vivos: K4.Process {
        onSalida: function (texto) {
            const siguen = String(texto).trim().split(/\s+/)
            const pids = self.pidsVigilados
            for (let i = 0; i < pids.length; ++i)
                if (siguen.indexOf(pids[i]) < 0)
                    self.despedir(pids[i])
        }
    }

    //  ── «tienes terminales abiertas» ──────────────────────────────
    //
    //  Con la vista escondida no hay NADA que recuerde que ahí dentro sigue
    //  corriendo algo, y una sesión que sobrevive a su propia vista es
    //  justamente la que se olvida. Un indicador con la cuenta lo dice, y
    //  pulsarlo la trae de vuelta.
    //
    //  Solo cuando está escondida: teniéndola delante, contarte que la tienes
    //  abierta sobra.
    readonly property string idAbiertas: "terminal.abiertas"

    function refrescarAbiertas() {
        if (vivas.length === 0 || abierto) {
            K4.Pildora.quitar(idAbiertas)
            return
        }
        K4.Pildora.registrar(idAbiertas, String(vivas.length),
                             0xF018D, Theme.muted, 31, true)
    }

    onVivasChanged: refrescarAbiertas()
    onAbiertoChanged: { refrescarAbiertas(); atendidaIsla() }
    onActualChanged: atendidaIsla()

    //  Trabajos largos: la terminal avisa al terminar y aquí se convierte en
    //  notificación, que es la vía por la que la casa entera enseña avisos.
    //  El mandato se recorta porque un `find` con veinte argumentos no cabe
    //  en un toast y lo que importa es reconocerlo, no leerlo entero.
    function resumir(mandato) {
        const limpio = String(mandato).trim()
        return limpio.length > 48 ? limpio.slice(0, 47) + "…" : limpio
    }

    function duracion(segundos) {
        const s = Math.round(Number(segundos) || 0)
        if (s < 60)
            return s + " s"
        const m = Math.floor(s / 60)
        return m < 60 ? m + " min " + (s % 60) + " s"
                      : Math.floor(m / 60) + " h " + (m % 60) + " min"
    }

    K4.Ipc {
        target: "k4.term"

        //  Sin decir dónde, en tu casa. Hay que ser explícito: lo que se
        //  hereda al lanzar desde aquí es el directorio de la barra, que no
        //  le importa a nadie.
        function abrir(): void {
            K4.Sistema.lanzar(Consola.abrir(K4.Sistema.entorno("HOME")))
        }

        function abrirEn(ruta: string): void {
            K4.Sistema.lanzar(Consola.abrir(ruta))
        }

        //  Donde la casa corra las cosas: la island si la hay, y si no una
        //  ventana. Antes esto abría ventana siempre, y era incoherente con
        //  que Actualizar sí se vea en la island.
        function ejecutar(mandato: string): void {
            if (mandato)
                Consola.ejecutar(mandato)
        }

        //  Lo de la island, a lo grande y en el mismo sitio.
        function sacar(): void { self.sacar() }

        //  El gesto único: mudar la sesión al otro lado, sea cual sea el otro
        //  lado. Si estás mirando una ventana de k4term, se vuelve a la
        //  island; si no, la de la island se va a una ventana. Dos atajos
        //  para lo mismo no tenían sentido, y encima el de la ventana no
        //  llegaba mientras la island se quedaba el teclado.
        function mudar(): void { quien.running = true }

        //  Abrir donde estás mirando: se pregunta a Hyprland por la ventana
        //  con foco y se baja por el árbol de procesos hasta el último hijo
        //  —el intérprete que de verdad tiene el directorio— para leerle el
        //  cwd. Si algo falla, cae en abrir sin más.
        function aqui(): void { donde.running = true }

        //  Empieza algo largo: a la píldora. Quien decide qué es «largo» es
        //  la terminal, que es la que tiene el reloj puesto.
        function inicio(pid: string, mandato: string, llevaba: string): void {
            self.apuntar(pid, mandato, llevaba)
        }

        //  Y al acabar: fuera de la píldora, y aviso si de verdad ha llevado
        //  su rato. El indicador aparece antes que el aviso a propósito —
        //  primero enterarse de que trabaja, luego de que terminó.
        function fin(pid: string, mandato: string, salida: string,
                     segundos: string): void {
            self.olvidar(pid)
            if (Number(segundos) >= self.avisoSegundos)
                self.avisar(mandato, salida, segundos)
        }

        //  La ventana se cierra con algo dentro: se lleva su indicador.
        function limpiar(pid: string): void {
            self.olvidar(pid)
            self.dejarDeEsperar(pid)
        }

        //  La terminal de la island, para lo rápido.
        function isla(): void { self.toggle() }

        //  Una ventana devuelve su sesión: se abre una pestaña que la adopta.
        //  La ventana se cierra sola en cuanto se la hayan quitado.
        function adoptar(socket: string): void {
            if (!socket)
                return
            self.nueva(socket)
            self.abierto = true
        }

        //  Las de tener varias: abrir otra, moverse entre ellas y cerrar la
        //  que sobra. Lo mismo que las teclas, para quien prefiera un guion.
        function nueva(): void {
            if (!Consola.hayIsla)
                return
            self.nueva()
            self.abierto = true
        }

        function siguiente(): void { self.siguiente() }
        function anterior(): void { self.anterior() }
        function irA(n: string): void { self.irA(parseInt(n, 10) - 1) }
        function cerrarTerminal(): void { self.cerrarSesion(self.actual) }

        //  Teclear en la que tengas delante, sin abrir ninguna nueva. Es lo
        //  que distingue esto de `ejecutar`, que siempre estrena terminal.
        function escribir(texto: string): void {
            //  Los saltos de línea se convierten en retornos por lo mismo que
            //  al pegar: es lo que manda la tecla Intro, y con `\n` la línea
            //  se queda escrita sin ejecutarse.
            if (texto)
                self.mandar({ que: "texto",
                              valor: String(texto).replace(/\r\n|\n/g, "\r") })
        }

        //  Una terminal que toca la campana sin tener el foco casi siempre es
        //  un agente que ha terminado su turno y te espera. Se apunta en la
        //  píldora —con su propio glifo, que no es lo mismo que un mandato
        //  largo— y se avisa una vez.
        function campana(pid: string, titulo: string): void {
            self.esperando(pid, titulo)
        }

        //  Estás dentro de un sitio. Lo dice la ventana al conectar y la
        //  píldora lo enseña: con tres terminales abiertas, saber a cuál
        //  máquina pertenece cada una no debería exigir mirar el prompt.
        function conectado(pid: string, destino: string): void {
            self.entrarEn(pid, destino)
        }

        function desconectado(pid: string): void {
            self.salirDe(pid)
        }

        //  Un recado suelto de la terminal: no tiene dónde decir «guardado»
        //  sin taparse a sí misma, y la isla sí.
        function decir(titulo: string, cuerpo: string): void {
            K4.Sistema.lanzar(["notify-send", "-a", "k4term", "-t", "5000",
                               titulo, cuerpo])
        }
    }

    function avisar(mandato, salida, segundos) {
        const fallo = String(salida) !== "0"
        const cuerpo = resumir(mandato) + " · " + duracion(segundos)
        K4.Sistema.lanzar(["notify-send", "-a", "k4term",
                           fallo ? "-u" : "-t", fallo ? "critical" : "6000",
                           fallo ? Idioma.t("Falló el mandato") + " (" + salida + ")"
                                 : Idioma.t("Mandato terminado"),
                           cuerpo])
    }

    //  ── los ajustes de k4term, en los Ajustes de la casa ──────────
    //
    //  k4term los lee de ~/.config/k4term/k4term.conf y los sigue en
    //  caliente, así que tocar aquí un interruptor se ve en las ventanas
    //  abiertas sin reabrir nada. Se escribe LÍNEA A LÍNEA y no el fichero
    //  entero a propósito: quien lo haya editado a mano tiene derecho a que
    //  no se le borren sus comentarios ni sus claves.

    readonly property string ficheroConf: K4.Sistema.entorno("HOME") + "/.config/k4term/k4term.conf"

    property var conf: ({ tamaño: "13", opacidad: "0.92", estela: "si",
                          tranquilo: "no" })

    function leerConf() {
        const texto = fConf.text() || ""
        const nuevo = Object.assign({}, conf)
        texto.split("\n").forEach(function (linea) {
            const limpia = linea.split("#")[0].trim()
            const corte = limpia.indexOf("=")
            if (corte < 0)
                return
            nuevo[limpia.slice(0, corte).trim()] = limpia.slice(corte + 1).trim()
        })
        conf = nuevo
    }

    function poner(clave, valor) {
        const nuevo = Object.assign({}, conf)
        nuevo[clave] = String(valor)
        conf = nuevo

        let texto = fConf.text() || ""
        const patron = new RegExp("^[ \\t]*" + clave + "[ \\t]*=.*$", "m")
        if (patron.test(texto))
            texto = texto.replace(patron, clave + " = " + valor)
        else
            texto = (texto.length && texto.slice(-1) !== "\n" ? texto + "\n" : texto)
                  + clave + " = " + valor + "\n"
        fConf.setText(texto)
    }

    property K4.Fichero fConf: K4.Fichero {
        path: self.ficheroConf
        onLoaded: self.leerConf()
    }

    K4.Ajustes {
        plugin: "terminal"
        grupo: Idioma.t("Terminal")

        //  Solo si hay k4term. Son SUS ajustes: sin él, esta sección ofrecía
        //  cambiar el tamaño de letra y el cristal de una terminal que no está
        //  instalada, y lo escribía en un fichero que no lee nadie. Con la
        //  lista vacía, la sección entera no sale.
        //
        //  La detección de Consola tarda —es un proceso que corre al
        //  arrancar—, así que esto vale «no» durante los primeros
        //  milisegundos; lo que hace que aparezca después es que K4.Ajustes se
        //  vuelve a registrar cuando `opciones` cambia.
        opciones: !Consola.esNuestra ? [] : [
            { id: "tamaño", nombre: Idioma.t("Tamaño de letra"),
              desc: Idioma.t("De la ventana; en la island manda el hueco"),
              glifo: 0xF0207, tipo: "eleccion",
              alternativas: [{ codigo: "11", nombre: "11" },
                             { codigo: "13", nombre: "13" },
                             { codigo: "15", nombre: "15" },
                             { codigo: "18", nombre: "18" }] },
            { id: "opacidad", nombre: Idioma.t("Cristal"),
              desc: Idioma.t("Cuánto se ve del fondo por detrás"),
              glifo: 0xF00B5, tipo: "eleccion",
              alternativas: [{ codigo: "1", nombre: Idioma.t("Opaca") },
                             { codigo: "0.94", nombre: Idioma.t("Suave") },
                             { codigo: "0.88", nombre: Idioma.t("Media") },
                             { codigo: "0.8", nombre: Idioma.t("Mucha") }] },
            { id: "estela", nombre: Idioma.t("Estela del cursor"),
              desc: Idioma.t("Deja rastro al moverse"), glifo: 0xF05D8 },
            { id: "tranquilo", nombre: Idioma.t("Modo tranquilo"),
              desc: Idioma.t("Atenúa lo anterior al último mandato"),
              glifo: 0xF0335 }
        ]
        valores: ({
            "tamaño": self.conf["tamaño"] || "13",
            opacidad: self.conf.opacidad || "0.94",
            estela: self.conf.estela !== "no" && self.conf.estela !== "0",
            tranquilo: self.conf.tranquilo === "si" || self.conf.tranquilo === "1"
        })
        onCambiado: function (id, valor) {
            if (id === "estela" || id === "tranquilo")
                self.poner(id, valor ? "si" : "no")
            else
                self.poner(id, valor)
        }
    }

    K4.Process {
        id: buscar
        property string pid: ""
        command: ["hyprctl", "clients", "-j"]
        onSalida: function (texto) {
            let ventanas = []
            try {
                ventanas = JSON.parse(texto)
            } catch (e) {
                return
            }
            const viva = ventanas.some(function (v) {
                return String(v.pid) === buscar.pid
            })
            if (!viva) {
                self.olvidar(buscar.pid)
                return
            }
            enfoque.pid = buscar.pid
            enfoque.running = true
        }
        onTerminado: running = false
    }

    //  Hyprland 0.56 ya no traga `dispatch focuswindow pid:N`: su parser Lua
    //  se atraganta con los dos puntos del selector. La vía viva es `eval`,
    //  la misma que usa el tema de Hyprland en esta casa.
    K4.Process {
        id: enfoque
        property string pid: ""
        command: ["hyprctl", "eval",
                  "local v = hl.get_window(\"pid:" + pid + "\")"
                  + " if v then hl.dispatch(hl.dsp.focus({ window = v })) end"]
        onTerminado: running = false
    }

    //  Quién está delante ahora mismo. Con eso se decide hacia dónde muda la
    //  sesión: la barra no puede preguntarle a una ventana de GPUI, pero sí
    //  puede llamarla — y al proceso de una ventana se le llama con una señal.
    K4.Process {
        id: quien
        command: ["hyprctl", "activewindow", "-j"]
        onSalida: function (texto) {
            let v = null
            try {
                v = JSON.parse(texto)
            } catch (e) {
                v = null
            }
            if (v && String(v.class) === "k4term" && v.pid > 0) {
                K4.Sistema.lanzar(["kill", "-USR1", String(v.pid)])
                return
            }
            //  Mudar es mover algo que existe. Sin sesión en la island no hay
            //  nada que llevarse, y abrir una terminal nueva aquí sería una
            //  sorpresa: pasó en la primera prueba y no se entiende.
            if (self.sesion)
                self.sacar()
        }
        onTerminado: running = false
    }

    K4.Process {
        id: donde
        command: ["sh", "-c",
            "p=$(hyprctl activewindow -j | python3 -c 'import json,sys; print(json.load(sys.stdin).get(\"pid\") or 0)' 2>/dev/null);" +
            " [ \"$p\" -gt 0 ] 2>/dev/null || exit 0;" +
            " while c=$(pgrep -P \"$p\" -n 2>/dev/null); [ -n \"$c\" ]; do p=$c; done;" +
            " readlink /proc/$p/cwd 2>/dev/null"]
        onSalida: function (texto) {
            K4.Sistema.lanzar(Consola.abrir(texto.trim()))
        }
        onTerminado: running = false
    }
}
