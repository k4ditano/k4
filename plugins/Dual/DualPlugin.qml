//  Modo dual: la barra de arriba se va y se convierte en el dock de abajo.
//
//  La secuencia: la barra se pone negra y se encoge hasta desaparecer, y de sus
//  dos extremos salen dos gotas que corren cada una por su borde de pantalla
//  hasta juntarse abajo, donde se estiran y montan el dock. De vuelta, igual al
//  revés.
//
//  Que la barra de arriba desaparezca se consigue COGIENDO la island con
//  prioridad alta y pidiéndola de tamaño cero: no hay que tocar el host para
//  nada, es la misma facultad que usa el editor de vídeo para pasar de tira a
//  pantalla grande.
//
//      quickshell ipc -p <shell.qml> call k4.dual toggle

import QtQuick
import K4 as K4

K4.Plugin {
    id: self

    name: "dual"
    title: K4.Idioma.t("Modo dual")

    //  "barra" · "encogiendo" · "bajando" · "dock" ·
//  "recogiendo" · "subiendo" · "creciendo"
    //
    //  La salida es la entrada al revés, y por eso hay un modo de más. Al bajar
    //  el orden es: viajar, juntarse, y ENTONCES crecer el dock. Al subir tiene
    //  que ser al espejo: encogerse el dock primero, y solo después salir de
    //  viaje. Haciendo las dos cosas a la vez —que es como estaba— el dock se
    //  desinflaba mientras los trozos ya se iban, y por el medio se veía un
    //  hueco negro que no es nada.
    property string modo: "barra"

    readonly property bool viajando: modo === "bajando" || modo === "subiendo"
    //  Los trozos están en pantalla también mientras el dock se recoge encima
    //  de ellos, aunque no se muevan — pero NO desde el principio.
    //
    //  Sacándolos al empezar la recogida se pintaban sobre el dock todavía
    //  entero (van en una capa por encima), y como son negros tapaban la mitad
    //  de abajo de los iconos: parecía que salía una gota encima del dock antes
    //  de que pasara nada. Esperando a que el dock esté casi recogido, aparecen
    //  cuando ya miden lo mismo que él y no se ve el relevo.
    readonly property bool trozosFuera: viajando
        || (modo === "recogiendo" && muelle.despliegue < 0.18)

    //  ── el ancho de la barra mientras la tenemos cogida ──────────
    //
    //  Se anima AQUÍ y no se deja al host a propósito. Soltando la island sin
    //  más, la barra reaparecía con la animación del host —440 ms con rebote— y
    //  desde CERO, que no se parece en nada a cómo se pone el dock abajo. Con
    //  la misma curva que el dock (760 ms, sin rebote) y saliendo del tamaño de
    //  los trozos, arriba y abajo hacen por fin lo mismo.
    //
    //  16 es el radio del ala: `K4.Isla.rect` mide la island CON alas y
    //  `islandWidth` va sin ellas.
    readonly property int ala: 16
    property real anchoBarra: 0
    //  Para poner el ancho de golpe cuando hay que empalmar sin que se note.
    property bool suave: false

    islandWidth: Math.max(0, Math.round(anchoBarra))

    //  Más corta que la del dock, y a propósito.
    //
    //  El dock se recoge de 470 a 130 y la barra solo de 208 a 130: con la
    //  misma duración, arriba se quedaba casi tres cuartos de segundo sin
    //  aparente pasar nada antes de partirse, mientras que abajo la división se
    //  ve a los 500 ms —en cuanto los trozos asoman sobre el dock ya recogido—.
    //  Recorrido más corto, tiempo más corto.
    Behavior on anchoBarra {
        enabled: self.suave
        NumberAnimation { duration: 440; easing.type: Easing.InOutCubic }
    }

    //  Lo que medía la barra al empezar, y lo que miden los dos trozos juntos.
    property real anchoLleno: 0
    readonly property real anchoSemilla: largoTrozo * 2 - ala * 2
    readonly property bool fuera: modo !== "barra"

    //  «Ya está puesto abajo»: el dock ha llegado Y ha terminado de crecer.
    //  Es el instante en que el dock se queda su sitio, y por tanto el único
    //  momento en que tiene sentido soltar el de arriba.
    readonly property bool asentado: modo === "dock" && muelle.despliegue > 0.98

    //  Que el host NO le guarde el sitio a la barra: solo cuando el dock ya se
    //  ha quedado el suyo abajo. Así el escritorio se recoloca una vez, al
    //  final, y no al empezar el reparto.
    //
    //  Se intentó antes con una franja propia que reservase esos 34 px durante
    //  el viaje, y salió peor: un `exclusiveZone` no solo aparta ventanas,
    //  también aparta las CAPAS que vienen detrás, así que la franja empujaba
    //  a la barra hacia abajo y se la veía descolgarse antes de partirse.
    //  Los píxeles que el host debe seguir guardándole a la barra.
    //
    //  Se suelta justo cuando el dock empieza a crecer, y el dock arranca
    //  reservando exactamente esos mismos 34: el relevo sale a cero y desde ahí
    //  el escritorio ACOMPAÑA al crecimiento en vez de pegar un salto al final.
    //  Al revés igual: no se recupera hasta que el dock ya se ha recogido.
    property int reservaBarra: (modo === "dock" || modo === "recogiendo")
        ? 0 : K4.Tema.altoPlegado

    readonly property int altoMuelle: 76

    //  Lo que mide cada trozo que viaja: LA MITAD DE LA BARRA que se acaba de
    //  partir, congelada al arrancar junto con el origen.
    //
    //  Estaba en 96 fijos, y eso no era partir la barra en dos: con la píldora
    //  en 122, dos trozos de 96 saliendo de sus extremos ocupaban 218 px
    //  juntos, casi el doble de lo que había. Se veía como que abajo llegaba
    //  algo más gordo de lo que se fue.
    //
    //  Lo comparten la escena —para saber dónde se juntan— y el dock, que nace
    //  exactamente de ese ancho: los dos trozos pegados SON la barra otra vez,
    //  y de ahí se estira.
    property int largoTrozo: 61

    //  Se coge la island por encima de todo para que no la pinte nadie más, y
    //  se pide de tamaño cero: la barra se encoge sola con la animación que ya
    //  tiene el host y desaparece.
    //  Solo se coge la island para las DOS ANIMACIONES en las que la barra
    //  tiene que encogerse o crecer, medio segundo cada una. El resto del
    //  tiempo la barra se aparta con `barraApartada`, que es por pantalla y no
    //  bloquea a nadie: con `active` puesto todo el rato y prioridad 90, la
    //  island del otro monitor se quedaba muerta —ni se desplegaba ni
    //  respondía— porque el host solo admite un plugin activo global.
    readonly property bool mandaIsla: modo === "encogiendo"
        || modo === "creciendo"

    priority: 90
    active: mandaIsla

    //  La pantalla que se lleva la barra, y lo que hay que seguir guardándole.
    property var barraApartada: (fuera && !mandaIsla)
        ? ({ pantalla: pantalla, reserva: reservaBarra }) : null
    //  Mientras se encoge o crece, la barra conserva su GROSOR y solo cambia
    //  de ancho: es lo que hace que se vea recogerse sobre los trozos en vez de
    //  desinflarse hacia arriba. Se va a cero cuando los trozos ya la tapan.
    islandHeight: (modo === "encogiendo" || modo === "creciendo")
        ? K4.Tema.altoPlegado : 0
    view: null

    //  De dónde salen las gotas. Se CONGELA al arrancar: en cuanto se coge la
    //  island, su rect empieza a encogerse hacia cero, y si las gotas leyeran
    //  el rect en vivo saldrían de un punto que se les escapa.
    property real origenIzqX: 0
    property real origenDerX: 0
    property real origenY: 0

    //  Y en qué pantalla pasa todo. Con dos monitores esto no es un detalle:
    //  `K4.Isla.rect` da la island de la pantalla PRINCIPAL, y si la barra que
    //  se va está en la otra, las gotas salían de un punto que ni siquiera cae
    //  dentro de la ventana —las coordenadas son locales a cada monitor—. No
    //  se veía mal: no se veía.
    property string pantalla: ""

    function congelarOrigen() {
        //  Defensivo a propósito: si la barra corre una API vieja que no
        //  publica `pantalla`, esto valía `undefined`, la asignación a una
        //  property de texto reventaba, y como la llamada va ANTES de mover el
        //  modo, el modo no cambiaba y el comando entero no hacía nada. Sin un
        //  error a la vista: simplemente no pasaba nada al pulsar.
        pantalla = K4.Isla.pantalla || ""
        const r = K4.Isla.rectEn(pantalla)

        //  Los dos trozos juntos miden MENOS que la barra —un 62 %—, y salen
        //  centrados en ella. Eso es lo que deja ver la barra encogiéndose
        //  sobre ellos antes de partirse, igual que abajo se ve el dock
        //  recogiéndose sobre ellos antes de salir. Midiendo lo mismo que la
        //  barra no había nada que encoger y el paso se daba de golpe.
        anchoLleno = r.ancho - ala * 2
        //  Con un suelo: por debajo de unos 56 px el trozo deja de parecerse a
        //  un cacho de barra por mucho que las esquinas se acoten.
        //  Anchos de sobra para que se lean APLANADOS: con la píldora desnuda
        //  un 36 % se quedaba en 60 px y un trozo de 60×34 con esquinas
        //  pequeñas es casi un cuadrado. Con el suelo de 70 la proporción se
        //  mantiene 2:1 y las esquinas salen redondas.
        //
        //  Cada trozo es la MITAD DE LA BARRA YA ENCOGIDA, y por eso sale de
        //  una fracción de la barra y no de una medida propia.
        //
        //  Tuve un suelo de 104 px «para que se leyeran aplanados», y con la
        //  píldora estrecha eso hacía que los dos sumaran MÁS que la barra: la
        //  contracción de arriba era en realidad un ensanchamiento, y al
        //  partirse y al reencontrarse quedaban desproporcionados. El suelo de
        //  ahora es solo el mínimo para que la silueta se trace.
        largoTrozo = Math.max(56, Math.round(r.ancho * 0.36))
        const centro = r.x + r.ancho / 2
        origenIzqX = centro - largoTrozo / 2
        origenDerX = centro + largoTrozo / 2
        origenY = r.y + r.alto / 2
    }

    readonly property var preferidas: [
        "kitty", "firefox", "org.kde.dolphin", "code", "discord",
        "org.telegram.desktop", "vlc", "steam"
    ]

    //  Los ids que hay puestos, EN ORDEN. Es lo único que se guarda: las
    //  aplicaciones se resuelven cada vez contra las instaladas, así que
    //  desinstalar una la quita del dock sola en vez de dejar un hueco muerto.
    property var idsDock: []

    //  Hasta que no se ha leído lo guardado, no se guarda NADA.
    //
    //  La lectura es asíncrona: durante ese rato `idsDock` está vacío, y
    //  cualquier cosa que guarde en ese hueco escribe el vacío —o la lista de
    //  arranque— encima del dock que tenías. No es hipotético: se me llevó por
    //  delante un dock recargando el plugin mientras probaba.
    property bool cargado: false

    K4.Guardado {
        id: guardado
        plugin: "dual"
        onCargado: function (d) {
            const l = (d && d.apps) || []
            self.idsDock = l.length > 0 ? l : self.preferidas.slice()
            if (d && d.animar !== undefined)
                self.animar = !!d.animar
            self.cargado = true
        }
    }

    function guardarDock() {
        if (!cargado)
            return
        guardado.guardar({ apps: idsDock, animar: animar })
    }

    //  ── el viaje, o el cambio a secas ────────────────────────────
    //
    //  El viaje es lo que cuenta lo que está pasando: sin él, la barra
    //  desaparece de arriba y hay un dock abajo, y quien no lo haya visto nunca
    //  no sabe que son la misma cosa. Pero son tres segundos, y quien ya lo
    //  sabe los hace veinte veces al día.
    //
    //  Apagado, no se acelera la animación: se salta entera. Los modos de en
    //  medio no llegan a existir, así que las gotas no se crean, la barra se
    //  aparta de golpe y el dock ya está puesto.
    property bool animar: true

    K4.Ajustes {
        plugin: "dual"
        grupo: K4.Idioma.t("Modo dual")
        opciones: [{
            id: "animar",
            nombre: K4.Idioma.t("Viaje animado"),
            //  De una pieza y no partida con un `+`: el extractor de textos
            //  ve DOS literales y en marcha `t()` recibe la suma, que no casa
            //  con ninguno de los dos. La cadena se queda larga y se traduce.
            desc: K4.Idioma.t("Bajan por los bordes hasta hacerse dock; apagado, el cambio es seco"),
            glifo: 0xF15B2
        }]
        valores: ({ animar: self.animar })
        onCambiado: function (id, valor) {
            if (id !== "animar")
                return
            self.animar = valor
            self.guardarDock()
        }
    }

    //  ── lo que está abierto ──────────────────────────────────────
    //
    //  Las aplicaciones ABIERTAS salen en el dock aunque no estén fijadas, y al
    //  cerrarlas se van solas. Es lo que uno espera de un dock: lo fijado está
    //  siempre y lo demás es un reflejo de lo que tienes entre manos.
    //
    //  De dónde sale: del mismo sondeo que ya usa el rebote. `hyprctl` da la
    //  CLASE de cada ventana, que en la práctica es el id del .desktop —
    //  `firefox`, `org.kde.dolphin`, `org.telegram.desktop`—, así que se casan
    //  por ahí y, si no, por el nombre.
    //  id de aplicación -> [{ direccion, titulo }] de sus ventanas.
    property var ventanasPorId: ({})
    readonly property var idsAbiertos: Object.keys(ventanasPorId)

    function ventanasDe(id) { return ventanasPorId[id] || [] }

    //  A qué aplicación pertenece una clase de ventana.
    function _appDeClase(c) {
        for (let i = 0; i < K4.Apps.lista.length; ++i) {
            const a = K4.Apps.lista[i]
            const id = String(a.id || "").toLowerCase()
            const nom = String(a.name || "").toLowerCase()
            if (c === id || c === nom || (c.length > 2 && id.indexOf(c) >= 0))
                return String(a.id || "")
        }
        return ""
    }

    //  Llevar a una ventana que ya existe, en vez de abrir otra.
    //
    //  OJO con la sintaxis: la configuración de Hyprland de esta máquina es
    //  Lua, y los dispatch clásicos —`hyprctl dispatch focuswindow address:…`—
    //  fallan EN SILENCIO: no dan error y no hacen nada. Van contra `hl.dsp`.
    function enfocar(direccion) {
        if (!direccion)
            return
        K4.Sistema.lanzar(["hyprctl", "dispatch",
            'hl.dsp.focus({ window = "address:' + direccion + '" })'])
    }

    function estaFijada(id) { return idsDock.indexOf(id) >= 0 }

    //  Primero las fijadas, en su orden; detrás las abiertas que no lo estén.
    readonly property var apps: {
        const fuera = []
        for (let i = 0; i < idsDock.length; ++i) {
            const a = K4.Apps.porId(idsDock[i])
            if (a)
                fuera.push(a)
        }
        for (let i = 0; i < idsAbiertos.length; ++i) {
            if (estaFijada(idsAbiertos[i]))
                continue
            const a = K4.Apps.porId(idsAbiertos[i])
            if (a)
                fuera.push(a)
        }
        return fuera
    }

    //  Cuántas hay fijadas: la frontera entre un grupo y otro, para pintar la
    //  divisoria justo ahí.
    readonly property int fijadas: {
        let n = 0
        for (let i = 0; i < idsDock.length; ++i)
            if (K4.Apps.porId(idsDock[i]))
                n += 1
        return n
    }

    //  Se vigila solo con el dock puesto: sondear cuando no se ve no le sirve a
    //  nadie y son dos procesos por segundo.
    Timer {
        id: vigia
        interval: 1500
        repeat: true
        running: self.modo === "dock"
        triggeredOnStart: true
        onTriggered: if (!clientes.running) clientes.running = true
    }

    K4.Process {
        id: clientes
        command: ["hyprctl", "clients", "-j"]
        onSalida: function (texto) {
            let l = []
            try {
                l = JSON.parse(texto)
            } catch (e) {
                return
            }
            //  Contenedor NUEVO: mutar el objeto no repinta nada en QML.
            const mapa = {}
            for (let i = 0; i < l.length; ++i) {
                const c = String(l[i].class || "").toLowerCase()
                if (c.length === 0)
                    continue
                const id = self._appDeClase(c)
                if (!id)
                    continue
                if (!mapa[id])
                    mapa[id] = []
                mapa[id].push({
                    direccion: String(l[i].address || ""),
                    titulo: String(l[i].title || c)
                })
            }
            self.ventanasPorId = mapa
        }
    }

    function idDe(app) {
        return app ? String(app.id || app.name || "") : ""
    }

    function quitarDelDock(id) {
        //  Contenedor NUEVO: mutar el array no repinta nada en QML.
        idsDock = idsDock.filter(function (x) { return x !== id })
        guardarDock()
    }

    //  Meter una aplicación en el dock, en la posición donde se ha soltado.
    //  Si ya estaba, se MUEVE en vez de duplicarse.
    function ponerEnDock(id, donde) {
        if (!id)
            return
        const l = idsDock.filter(function (x) { return x !== id })
        const n = Math.max(0, Math.min(l.length, donde))
        l.splice(n, 0, id)
        idsDock = l
        guardarDock()
    }

    //  Mover un icono de sitio. `desde` y `hasta` son posiciones de LO QUE SE
    //  VE, que no es lo mismo que posiciones de lo guardado.
    //
    //  La lista guardada y la fila del dock no casan índice a índice: una
    //  fijada cuyo .desktop ya no existe sigue apuntada pero no se pinta, y las
    //  que están abiertas sin fijar se pintan al final sin estar en la lista.
    //  Moviendo con los índices de la fila «del 0 al 2» movía a otro sitio —una
    //  posición corta, con una sola fijada fantasma de por medio—. Así que se
    //  reordena la lista de las que SE VEN y luego se devuelve a sus mismos
    //  huecos, dejando a las fantasma donde estaban.
    function moverEnDock(desde, hasta) {
        const visibles = []
        const huecos = []
        for (let i = 0; i < idsDock.length; ++i)
            if (K4.Apps.porId(idsDock[i])) {
                visibles.push(idsDock[i])
                huecos.push(i)
            }

        //  Fuera de la parte fijada no hay nada que reordenar: lo de después
        //  son las abiertas, que no están en la lista.
        if (desde < 0 || desde >= visibles.length)
            return
        const h = Math.max(0, Math.min(visibles.length - 1, hasta))
        if (h === desde)
            return

        visibles.splice(h, 0, visibles.splice(desde, 1)[0])
        const l = idsDock.slice()
        for (let i = 0; i < huecos.length; ++i)
            l[huecos[i]] = visibles[i]
        idsDock = l
        guardarDock()
    }

    //  El cajón NO abre otro módulo: crece del propio dock (ver Muelle.qml).
    //  El centro de aplicaciones de la barra es el de los MÓDULOS, y aquí lo
    //  que hace falta son las aplicaciones del escritorio.

    //  ── el rebote al abrir ───────────────────────────────────────
    //
    //  El icono que acabas de pulsar bota hasta que la aplicación ABRE VENTANA,
    //  como el dock de macOS. No es un adorno: entre pulsar y ver algo pueden
    //  pasar varios segundos, y sin señal uno vuelve a pulsar.
    //
    //  Cuándo parar no lo sabe la API —`services/Ventanas` es del host y un
    //  plugin de fuera no llega ahí— así que se cuenta a mano: se apunta
    //  cuántas ventanas hay al lanzar y se sondea hasta que hay una más.
    property string botando: ""
    property int ventanasAlLanzar: -1

    //  Y un tope. Si la aplicación no abre —o abre en otro escritorio y el
    //  recuento no cambia— el icono no se queda botando para siempre.
    Timer {
        id: findeRebote
        interval: 12000
        onTriggered: self.pararRebote()
    }

    function pararRebote() {
        botando = ""
        ventanasAlLanzar = -1
        findeRebote.stop()
        sondeo.stop()
        conteo.running = false
    }

    Timer {
        id: sondeo
        interval: 350
        repeat: true
        onTriggered: if (!conteo.running) conteo.running = true
    }

    K4.Process {
        id: conteo
        command: ["hyprctl", "clients", "-j"]
        onSalida: function (texto) {
            let n = 0
            try {
                n = JSON.parse(texto).length
            } catch (e) {
                return
            }
            if (self.ventanasAlLanzar < 0) {
                self.ventanasAlLanzar = n
                return
            }
            if (n > self.ventanasAlLanzar)
                self.pararRebote()
        }
    }

    function abrir(app) {
        if (!app)
            return

        //  Se apunta el recuento ANTES de lanzar, y de ahí en adelante se
        //  vigila. El primer sondeo fija la referencia; los siguientes buscan
        //  la ventana nueva.
        botando = String(app.id || app.name || "")
        ventanasAlLanzar = -1
        conteo.running = true
        sondeo.restart()
        findeRebote.restart()
        //  Como el lanzador: `execute()` heredaría el directorio de trabajo de
        //  la barra y las terminales abrirían en la carpeta de configuración.
        const dir = app.workingDirectory && app.workingDirectory.length > 0
            ? app.workingDirectory : K4.Sistema.entorno("HOME")
        if (!app.command || app.command.length === 0) {
            app.execute()
            return
        }
        K4.Sistema.lanzar(["sh", "-c",
            "cd " + JSON.stringify(dir) + " && exec \"$@\"", "sh"]
            .concat(app.command))
    }

    //  Poner el ancho SIN animar, para empalmar sin que se note.
    function ponerAncho(v) {
        suave = false
        anchoBarra = v
        suave = true
    }

    function bajar() {
        if (modo !== "barra")
            return
        //  Lo que ya estuviera abierto al pulsar no cuenta como una petición:
        //  ver `pedidoPendiente`.
        pedidoPendiente = false
        congelarOrigen()
        //  Se coge la barra exactamente como estaba y se la encoge sobre el
        //  tamaño de los dos trozos. Solo cuando ha terminado se parte.
        ponerAncho(anchoLleno)
        modo = "encogiendo"

        //  Y la pantalla se relee AHORA, no en `congelarOrigen`.
        //
        //  `K4.Isla.pantalla` es la pantalla del módulo activo, y el host la
        //  fija al activarse uno: preguntándola antes de coger la island venía
        //  vacía si nadie se había activado desde que arrancó la barra —recién
        //  recargado el plugin, por ejemplo—. Con la cadena vacía, `apartada`
        //  no casaba con ninguna pantalla y la barra no se iba.
        pantalla = K4.Isla.pantalla || pantalla

        //  Sin viaje: ni encogerse ni gotas ni empalme. La barra se aparta y el
        //  dock ya está abajo.
        if (!animar) {
            modo = "dock"
            return
        }

        anchoBarra = anchoSemilla
        encogida.restart()
    }

    Timer {
        id: encogida
        //  Casa con la contracción de arriba, no con la del dock: así el
        //  reparto empieza en el mismo momento que abajo, sobre el medio
        //  segundo, y las dos direcciones se sienten igual de vivas.
        interval: 500
        onTriggered: if (self.modo === "encogiendo") {
            //  A cero de golpe: los trozos ya están dibujados justo encima y
            //  miden lo mismo, así que el corte no se ve.
            self.ponerAncho(0)
            self.modo = "bajando"
        }
    }

    //  La barra coge su ancho de empalme ANTES de que lleguen los trozos.
    //
    //  El host anima el ancho de la island con su propia curva, así que
    //  poniéndoselo en el momento del encuentro crecía desde cero: durante un
    //  cuarto de segundo no asomaba por detrás de los trozos y lo que se veía
    //  era la pieza montada con el puente, quieta, y solo después salía la
    //  barra. Dándole la salida antes de tiempo —con el alto todavía a cero,
    //  así que no se ve— al juntarse ya está a su tamaño y crece sin pausa.
    Timer {
        id: ventaja
        interval: 1700
        onTriggered: if (self.modo === "subiendo")
            self.ponerAncho(self.anchoSemilla)
    }

    Timer {
        id: crecida
        //  Lo justo para que el ancho y el grosor de empalme lleguen a
        //  aplicarse; el crecimiento de verdad lo hace el host al soltar.
        interval: 90
        onTriggered: if (self.modo === "creciendo") self.modo = "barra"
    }

    function subir() {
        if (modo !== "dock")
            return
        if (!animar) {
            ponerAncho(anchoLleno)
            modo = "barra"
            return
        }

        //  Primero se recoge el dock sobre los dos trozos; el viaje empieza
        //  cuando ha terminado.
        ponerAncho(0)
        modo = "recogiendo"
        recogida.restart()
    }

    Timer {
        id: recogida
        //  Lo que tarda el dock en encogerse, y un pelín más para que no se
        //  solape con el arranque del viaje.
        interval: 820
        onTriggered: if (self.modo === "recogiendo") {
            self.modo = "subiendo"
            ventaja.restart()
        }
    }

    //  ¿Hay alguien pidiendo la island que no seamos nosotros?
    //
    //  La píldora no cuenta: es el fondo de armario y está siempre. Los avisos
    //  tampoco —un toast que llega solo no tiene por qué deshacerte el dock—.
    //  Lo que sí cuenta es un módulo que se abre porque has pulsado su atajo.
    readonly property bool islaPedida: {
        const q = K4.Isla.ocupadaPor
        return q.length > 0 && q !== "idle" && q !== "dual" && q !== "toast"
    }

    //  Y entonces la barra VUELVE, con su viaje entero.
    //
    //  El host ya no hace la excepción de sacarla a tamaño completo por su
    //  cuenta: mientras `barraApartada` esté puesta, la island está a cero. El
    //  módulo que has abierto ya está activo y espera; sale cuando los trozos
    //  han subido y la barra se ha vuelto a montar, que es lo que se ve.
    //  Solo cuenta lo que llega DESPUÉS de irse la barra.
    //
    //  Si tenías el lanzador abierto y pulsabas el atajo del dock, la barra
    //  bajaba entera y volvía a subir de inmediato: al llegar abajo se
    //  encontraba con que la island estaba ocupada desde antes y se daba media
    //  vuelta. Nunca podías bajar con algo abierto. Lo que hay que atender es
    //  el atajo que pulsas con el dock ya puesto, y ese SÍ es un cambio.
    property bool pedidoPendiente: false

    onIslaPedidaChanged: {
        if (!islaPedida)
            return
        pedidoPendiente = true
        reclamada()
    }

    function reclamada() {
        if (!pedidoPendiente || modo !== "dock")
            return
        pedidoPendiente = false
        subir()
    }

    function alternar() {
        if (modo === "barra")
            bajar()
        else if (modo === "dock")
            subir()
    }

    function viajeTerminado() {
        if (modo === "bajando") {
            modo = "dock"
            //  Por si el atajo se pulsó MIENTRAS bajaba: entonces `subir` se
            //  negó —no estaba en el dock— y nadie iba a volver a preguntar.
            reclamada()
        } else if (modo === "subiendo") {
            //  Los trozos han llegado arriba y se han juntado. Se deja la barra
            //  EMPALMADA con su tamaño y se suelta enseguida: el crecimiento lo
            //  hace el host, que es el único que puede hacerlo CON CONTENIDO
            //  dentro.
            //
            //  Antes lo animaba yo durante 760 ms y salía mal por fuerza: la
            //  vista de este plugin es nula, así que lo que crecía era una barra
            //  VACÍA, y solo al soltarla aparecía el reloj con su propio
            //  desvanecido. Eso era el parpadeo, y el "encoge y vuelve a crecer"
            //  era el reajuste al ancho que pide la píldora de verdad.
            //  El ancho ya lo trae puesto desde `ventaja`; aquí solo se le
            //  devuelve el grosor y se suelta.
            modo = "creciendo"
            crecida.restart()
        }
    }

    //  Las dos superficies. Van en el PLUGIN y no en `view` porque una vista
    //  solo existe mientras se tiene la island, y aquí la island está a cero
    //  justamente para que no se vea.
    Escena { plugin: self }

    //  La franja que RESERVA el sitio del dock, y nada más.
    //
    //  El muelle ocupa la pantalla entera —lo necesita para recibir el clic de
    //  fuera del cajón—, y una superficie pegada a los cuatro bordes no puede
    //  quitarle sitio a nadie: sin un borde libre no hay borde del que quitar y
    //  el compositor la ignora. Así que el hueco lo pide esta, que no pinta ni
    //  recoge un solo clic y solo existe mientras el dock está puesto.
    K4.Ventana {
        nombre: "k4-dual-hueco"
        pantalla: self.pantalla
        visible: muelle.mostrando
        encima: false
        pegadaArriba: false
        implicitHeight: Math.round(muelle.altoDock)
        reserva: muelle.mostrando ? Math.round(muelle.altoDock) : 0

        //  Sin zona activa se tragaría los clics del dock, que está justo
        //  encima de ella.
        zonaActiva: nadaHueco

        Item { id: nadaHueco; width: 0; height: 0 }
    }

    Muelle {
        id: muelle
        plugin: self

        //  Se va cuando ha terminado de RECOGERSE, no cuando empieza la
        //  subida. Atado solo al modo, al pulsar para subir el dock se quedaba
        //  plantado en su sitio —negro y vacío— durante los dos segundos del
        //  viaje, porque su tamaño de reposo no es cero sino el de los dos
        //  trozos juntos. Ahora se encoge hasta ser exactamente esos dos trozos
        //  y entonces se quita, justo cuando ellos ya están dibujados encima.
        //  Cuándo existe su superficie lo decide ella: ver Muelle.qml.
        despliegue: self.modo === "dock" ? 1 : 0
        //  Que se despliegue DESPACIO y sin rebote.
        //
        //  Estaba en 420 ms con OutBack: crecía de golpe y el rebote del final
        //  remataba la sensación de salto. Lo que se está enseñando es masa
        //  extendiéndose, y eso no rebota — arranca suave, coge cuerpo y para
        //  suave, que es lo que hace InOutCubic.
        Behavior on despliegue {
            enabled: self.animar
            NumberAnimation {
                duration: 760
                easing.type: Easing.InOutCubic
            }
        }
    }

    //  El atajo global. El nombre es lo único que se declara aquí: la tecla la
    //  ata el compositor a `k4:dual`, que es como funcionan todos los de la
    //  barra —ver `hypr/k4.conf`—. Así no hay que arrancar un proceso para
    //  alternar: la barra recibe la señal directamente.
    K4.Atajo {
        name: "dual"
        description: "Modo dual: la barra baja de gotas y se hace dock"
        onPressed: self.alternar()
    }

    K4.Ipc {
        target: "k4.dual"

        //  Para poder mirarle las tripas desde la terminal: el modo, la
        //  pantalla y de dónde salen las gotas. Sin esto, depurar una
        //  animación de 820 ms es perseguirla con capturas.
        function estado(): string {
            return JSON.stringify({
                modo: self.modo, viajando: self.viajando,
                pantalla: self.pantalla,
                islaPantalla: K4.Isla.pantalla,
                izq: Math.round(self.origenIzqX),
                der: Math.round(self.origenDerX),
                y: Math.round(self.origenY),
                dockDentro: muelle.dentro,
                dockRaton: Math.round(muelle.ratonX),
                dockMuestra: muelle.mostrando,
                ocupante: K4.Isla.ocupadaPor,
                islaPedida: self.islaPedida,
                selectorDe: muelle.selectorDe,
                menuDe: muelle.menuDe
            })
        }

        function toggle(): void { self.alternar() }
        function bajar(): void { self.bajar() }
        function subir(): void { self.subir() }
    }
}
