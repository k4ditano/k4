//  Captura de pantalla.
//
//  Dos caras: un menú para elegir qué capturar, y un asomo corto tras hacer la
//  foto con la miniatura y qué hacer con ella. La segunda es la que se usa el
//  99 % de las veces, porque lo normal es disparar con un atajo y no abrir
//  ningún menú.
//
//  El estado no vive aquí sino en services/Captura.qml. Un plugin solo existe
//  mientras es el módulo activo, y grabar dura minutos con la island cerrada.

import QtQuick
import K4 as K4
import "../../core"
import "../../services"

K4Plugin {
    id: self

    name: "captura"
    title: Idioma.t("Captura")
    active: habilitado && open
    viewLoaded: open
    //  También durante la cuenta atrás, o el ESC que la cancela no llega a
    //  ninguna parte. Son tres segundos en los que nadie está escribiendo.
    //  En «hecha» no: es un asomo de cinco segundos con la miniatura, y
    //  robarle el teclado al escritorio por eso sería un incordio. En «abrir»
    //  sí, y en exclusiva: ahí se escribe para buscar el vídeo.
    grabKeyboard: open && modo !== "hecha"

    //  La cuenta atrás manda sobre todo lo demás mientras dura: si te tapa el
    //  reloj tres segundos no pasa nada, pero perderte el 3-2-1 sí importa.
    //
    //  «hecha» es el caso contrario y por eso baja hasta el 58. Esa vista no la
    //  ha pedido nadie: sale sola al hacer la foto, dice que salió y ofrece
    //  anotarla o copiarla. Con 84 le ganaba al lanzador, así que pulsar su
    //  atajo con la miniatura delante enseñaba la miniatura sus cinco segundos
    //  enteros y el lanzador después. En 58 le gana al reloj y al reproductor
    //  —o sea que pasar el ratón no se la lleva, que es lo suyo mientras
    //  decides si anotarla— y pierde con todo lo que abres tú. Lo demás
    //  —el menú, el vídeo, el editor— sí lo has pedido y se queda en 84.
    priority: modo === "cuenta" ? 92 : (modo === "hecha" ? 58 : 84)

    //  Y con la prioridad no basta: su reloj se rearma mientras el ratón esté
    //  sobre la island, así que sin esto volvería a salir en cuanto cerraras lo
    //  que abriste encima. Marcada transitoria, shell.qml la cierra del todo.
    transitorio: modo === "hecha"

    property var panel: null

    property bool open: false
    property string modo: "menu"      // menu · cuenta · hecha · video · editor · abrir
    property int index: 0

    readonly property var ambitos: [
        { clave: "pantalla", texto: Idioma.t("Pantalla"), icono: 0xF0379 },
        { clave: "region",   texto: Idioma.t("Región"),   icono: 0xF019E },
        { clave: "ventana",  texto: Idioma.t("Ventana"),  icono: 0xF05AF }
    ]

    //  «Anotar» ya no es un destino: dejaba el anotador abriéndose solo en
    //  CADA captura siguiente, y con el botón de la tarjeta no hace falta.
    readonly property var destinos: [
        { clave: "portapapeles", texto: Idioma.t("Copiar"),  icono: 0xF018F },
        { clave: "fichero",      texto: Idioma.t("Guardar"), icono: 0xF0193 },
        { clave: "ambos",        texto: Idioma.t("Las dos"), icono: 0xF05E0 }
    ]

    // 500 y no 440: con cuatro botones debajo del nombre del fichero, a 440 se
    // salía «Copiar» por el borde derecho.
    // La cuenta atrás se queda la island entera y sin nada más: es un número
    // gigante, y para eso no hace falta anchura.
    //  1000 y no 940 desde que el pie lleva cuatro botones de añadir: con 940 el
    //  de renderizar se salía por la derecha.
    islandWidth: modo === "cuenta" ? 200
        : (modo === "editor" ? 1000 : (modo === "abrir" ? 640
        : (modo === "video" ? 620 : (modo === "hecha" ? 500 : 520))))
    //  El editor crece con las capas.
    //
    //  Cada banda añade una fila a la línea de tiempo. Antes el alto topaba en
    //  cinco bandas —`min(5, bandas)`— mientras la línea seguía creciendo, así
    //  que a partir de la sexta las filas de abajo se salían por debajo del
    //  borde de la island sin ningún aviso. Medido: con ocho bandas la línea
    //  pedía 318 px y la island seguía dando los mismos 755.
    //
    //  Ahora el alto sigue a las bandas de verdad y quien pone el tope es la
    //  island, que ya lo tenía; pasado ese punto la línea se recorre en vertical
    //  dentro de su propio hueco, que es lo que hace `rodilloV` en el cuerpo.
    //
    //  La banda 1 es el vídeo y su fila es más alta que las demás: de ahí que la
    //  primera cuente distinto.
    islandHeight: modo === "cuenta" ? 150
        : (modo === "editor"
           ? Math.min(Theme.maxIslandHeight,
                      610 + Math.max(0, Editor.cuantasBandas - 1) * 29)
        : (modo === "abrir" ? 440 : (modo === "video" ? 164
        : (modo === "hecha" ? 132 : 208))))

    view: Component {
        Loader {
            // El editor es otra vista entera, no un modo más de la de captura:
            // comparten plugin pero no se parecen en nada.
            sourceComponent: self.modo === "editor" ? editor
                : (self.modo === "abrir" ? selector : normal)
        }
    }

    property Component normal: Component { CapturaView { plugin: self } }
    property Component editor: Component { EditorZoom { plugin: self } }
    property Component selector: Component { SelectorVideo { plugin: self } }

    // ── el menú ───────────────────────────────────────────────────
    function abrir() {
        modo = "menu"
        index = 0
        open = true
        if (panel)
            panel.close()
    }

    //  El ESC del host entra por aquí, así que cerrar durante la cuenta atrás
    //  tiene que significar «no grabes», no solo «quita la vista».
    function close() {
        if (modo === "cuenta") {
            Captura.parar()
            return
        }
        if (grande) {
            //  Apartar desde la ventana: se cierra y queda en la píldora, igual
            //  que desde la island.
            grande = false
            Modulos.minimizar("editor", Idioma.t("Editor"),
                              Editor.rutaVideo.split("/").pop(),
                              0xF1122)         // md-movie_edit
            return
        }
        if (modo === "editor") {
            //  Cerrar el editor lo aparta, no lo tira. Editar un vídeo lleva su
            //  rato y no tiene sentido obligar a tenerlo delante hasta acabar:
            //  se cierra, se sigue con lo que sea, y se retoma desde la
            //  píldora por donde ibas.
            Modulos.minimizar("editor", Idioma.t("Editor"),
                              Editor.rutaVideo.split("/").pop(),
                              0xF1122)         // md-movie_edit
            modo = "menu"
        }
        open = false
    }
    function toggle() { open && modo === "menu" ? close() : abrir() }

    //  Apartar y descartar son cosas distintas y la cabecera del editor tiene
    //  un botón para cada una. `close()` aparta —es lo que hace también ESC—;
    //  esto cierra el proyecto.
    //
    //  Preguntando, si has tocado algo. El editor guarda solo mientras
    //  trabajas, así que cerrar no pierde nada: lo que la pregunta ofrece de
    //  verdad es lo contrario —poder DESHACER la sesión entera y dejar el
    //  fichero como estaba al abrirlo—. Sin cambios no pregunta, que un
    //  diálogo que siempre tiene la misma respuesta se acaba pulsando sin
    //  leerlo.
    property bool preguntandoCierre: false

    function descartar() {
        if (Editor.hayCambios) {
            preguntandoCierre = true
            return
        }
        cerrarProyecto()
    }

    function cerrarProyecto(volcando) {
        preguntandoCierre = false
        Editor.descartar(volcando)
        grande = false
        modo = "menu"
        open = false
    }

    function cerrarDescartando() {
        Editor.descartarCambios()
        cerrarProyecto(false)
    }

    // ── abrir un vídeo del disco ──────────────────────────────────
    //
    //  Editar dejó de ser «lo que pasa después de grabar». Se puede traer un
    //  vídeo de cualquier sitio, y por eso el selector no cuelga del grabador.
    function pedirVideo() {
        modo = "abrir"
        open = true
    }

    function abrirVideo(ruta) {
        modo = "menu"
        open = false
        Editor.abrir(ruta, "")
    }

    function editarUltimaGrabacion() {
        marcharse.stop()
        Captura.pasarCamaraAlEditor()
        modo = "editor"
        open = true
        if (Editor.zoomAuto)
            Editor.proponer(Captura.rutaVideo, Captura.rutaRastro)
        else
            Editor.abrir(Captura.rutaVideo, Captura.rutaRastro)
    }

    //  Elegir un vídeo por el diálogo del sistema.
    //
    //  Vive aquí y no en la vista del selector, y no es cosmético: la vista se
    //  destruye al cerrarse, y con ella el proceso. Si eso pasa mientras el
    //  diálogo está abierto, el aviso de «ha terminado» no llega nunca, el
    //  contador de diálogos se queda arriba y **la island no vuelve**. El
    //  plugin dura lo que dura la barra.
    function pedirVideoDelDisco() { selectorVideoDisco.running = true }

    K4.Process {
        id: selectorVideoDisco
        //  Mientras el diálogo esté abierto, la island se aparta: va en una capa
        //  por encima de todo y el selector le sale por debajo, donde no se ve
        //  ni se puede pulsar.
        onArrancado: Island.abrirDialogo()
        onTerminado: Island.cerrarDialogo()
        command: ["zenity", "--file-selection",
                  "--title=" + Idioma.t("Elegir vídeo o proyecto"),
                  //  El otro diálogo de más abajo —el de meter un vídeo
                  //  ENCIMA— no lleva `.k4v` a propósito: un proyecto no es
                  //  una capa, y ofrecerlo ahí solo puede acabar en un error.
                  "--file-filter=" + Idioma.t("Vídeo o proyecto")
                  + " | *.mp4 *.mkv *.mov *.webm *.avi *.m4v *.k4v"]
        onSalida: function (texto) {
            const ruta = String(texto).trim()
            // Sale vacío si le has dado a cancelar, que no es un fallo.
            if (ruta.length > 0)
                self.abrirVideo(ruta)
        }
    }

    //  Traer una imagen para ponerla encima del vídeo.
    //
    //  Por el diálogo del sistema y no por un buscador propio: una imagen se
    //  reconoce mirándola, y zenity trae vista previa. Cuelga del plugin y no de
    //  la vista porque elegir el fichero lleva su rato y la island puede
    //  cambiar de dueño mientras tanto.
    property real dondeVaLaImagen: 0

    function pedirImagen(t, enCapaNueva) {
        dondeVaLaImagen = t
        // Si se pidió desde «+ Capa», se prepara una banda nueva; si se pidió
        // desde el pie, se conserva la banda elegida o se busca un hueco.
        if (enCapaNueva !== undefined) {
            if (enCapaNueva === true)
                Editor.crearBanda()
            else
                Editor.bandaObjetivo = 0
        }
        selectorImagen.running = true
    }

    K4.Process {
        id: selectorImagen
        //  Mientras el diálogo esté abierto, la island se aparta: va en una capa
        //  por encima de todo y el selector le sale por debajo, donde no se ve
        //  ni se puede pulsar.
        onArrancado: Island.abrirDialogo()
        onTerminado: Island.cerrarDialogo()
        command: ["zenity", "--file-selection",
                  "--title=" + Idioma.t("Elegir imagen"),
                  "--file-filter=" + Idioma.t("Imagen")
                  + " | *.png *.jpg *.jpeg *.webp *.gif *.bmp"]
        onSalida: function (texto) {
            const ruta = String(texto).trim()
            // Vacío es que le has dado a cancelar, que no es un fallo.
            if (ruta.length > 0)
                Editor.crearImagen(ruta, self.dondeVaLaImagen)
        }
    }

    //  Traer una pista de audio.
    //
    //  Por el diálogo del sistema, igual que la imagen: un fichero de música se
    //  reconoce por el nombre y por la carpeta donde lo guardaste, y zenity ya
    //  sabe navegar.
    property real dondeVaElAudio: 0

    function pedirAudio(t) {
        dondeVaElAudio = t
        selectorAudio.running = true
    }

    K4.Process {
        id: selectorAudio
        //  Mientras el diálogo esté abierto, la island se aparta: va en una capa
        //  por encima de todo y el selector le sale por debajo, donde no se ve
        //  ni se puede pulsar.
        onArrancado: Island.abrirDialogo()
        onTerminado: Island.cerrarDialogo()
        command: ["zenity", "--file-selection",
                  "--title=" + Idioma.t("Elegir audio"),
                  "--file-filter=" + Idioma.t("Audio")
                  + " | *.mp3 *.m4a *.aac *.wav *.flac *.ogg *.opus"]
        onSalida: function (texto) {
            const ruta = String(texto).trim()
            if (ruta.length > 0)
                Editor.crearAudio(ruta, self.dondeVaElAudio)
        }
    }

    //  Un vídeo dentro del vídeo. El mismo selector que para abrir uno, pero lo
    //  que sale es una capa y no un proyecto nuevo.
    property real dondeVaElPip: 0

    function pedirPip(t) {
        dondeVaElPip = t
        selectorPip.running = true
    }

    K4.Process {
        id: selectorPip
        //  Mientras el diálogo esté abierto, la island se aparta: va en una capa
        //  por encima de todo y el selector le sale por debajo, donde no se ve
        //  ni se puede pulsar.
        onArrancado: Island.abrirDialogo()
        onTerminado: Island.cerrarDialogo()
        command: ["zenity", "--file-selection",
                  "--title=" + Idioma.t("Elegir vídeo para encima"),
                  "--file-filter=" + Idioma.t("Vídeo")
                  + " | *.mp4 *.mkv *.mov *.webm *.avi *.m4v"]
        onSalida: function (texto) {
            const ruta = String(texto).trim()
            if (ruta.length > 0)
                Editor.crearPip(ruta, self.dondeVaElPip)
        }
    }

    function avanzar()    { index = (index + 1) % ambitos.length }
    function retroceder() { index = (index - 1 + ambitos.length) % ambitos.length }

    function elegir() { disparar(ambitos[index].clave) }

    // ── disparar ──────────────────────────────────────────────────
    //
    //  Cerrar el menú es solo la mitad: la píldora plegada seguiría saliendo en
    //  la foto. De apartar la island entera se encarga el servicio, que espera
    //  un frame antes de llamar a grim.
    function disparar(ambito, aDonde) {
        close()
        if (ambito === "region") {
            // La región pasa por el selector propio, que congela la pantalla
            // antes de dejarte encuadrar.
            Captura.destinoPuntual = aDonde || ""
            Captura.pedirRegion("foto")
        } else {
            Captura.foto(ambito, "", aDonde || "")
        }
    }

    //  El selector vive colgado del plugin y no de la vista: la vista solo
    //  existe mientras el módulo tiene la island, y encuadrar una región es
    //  justamente cuando la island no está.
    //
    //  Ojo: la propiedad por defecto de K4.Cargador es `component`, así que el
    //  hijo suelto ES lo que se carga. Es lo que se quiere aquí.
    K4.Cargador {
        // Se carga también mientras solo hay que tapar —antes de que exista el
        // fotograma y un momento después de disparar—: ahí está transparente y
        // lo único que hace es que ningún clic caiga en la ventana de debajo.
        active: Captura.seleccionando || Captura.tapando
        SelectorRegion {}
    }

    //  El editor en grande, en su propia ventana.
    //
    //  Cuelga del plugin y no de la vista por lo mismo que el selector: la
    //  vista solo existe mientras el módulo tiene la island, y aquí la island
    //  se libera justamente al abrir la ventana.
    property bool grande: false

    K4.Cargador {
        active: self.grande
        EditorGrande { plugin: self }
    }

    function abrirGrande() {
        grande = true
        modo = "menu"
        open = false
    }

    function cerrarGrande() {
        grande = false
        //  Se mira si hay algo abierto, no si hay momentos. Un vídeo sin zoom
        //  también se edita, y con la condición vieja encoger la ventana lo
        //  hacía desaparecer sin dejar ni la cápsula para volver.
        if (Editor.abierto) {
            modo = "editor"
            open = true
        }
    }

    // ── la cuenta atrás y el vídeo ────────────────────────────────
    Connections {
        target: Captura

        function onEstadoChanged() {
            if (Captura.estado === "cuenta") {
                self.modo = "cuenta"
                self.open = true
            } else if (self.modo === "cuenta") {
                self.modo = "menu"
                self.open = false
            }
        }

        function onVideoListo(ruta) {
            // No abrimos el editor por sorpresa: enseñamos primero la misma
            // tarjeta con preview y acciones que ya usamos para las capturas.
            self.modo = "video"
            self.open = true
            marcharse.restart()
        }

        function onVideoFallido(motivo, detalle) {
            //  `porque()` y no el motivo pelado: los guiones devuelven un
            //  código en español y esto es una notificación que lee el
            //  usuario. Con la barra en inglés salía el título traducido y el
            //  porqué debajo en español.
            K4.Sistema.lanzar(["notify-send", "-a", "k4", "-u", "critical",
                                     Idioma.t("No se pudo grabar"),
                                     Idioma.porque(motivo, detalle)])
        }

        function onFotoLista(ruta) {
            self.modo = "hecha"
            self.open = true
            marcharse.restart()
        }

        function onFotoFallida(motivo, detalle) {
            // Un fallo de verdad sí merece aviso del sistema: puede pasar con
            // la island cerrada y sin nadie mirando la barra.
            K4.Sistema.lanzar(["notify-send", "-a", "k4", "-u", "critical",
                                     Idioma.t("No se pudo capturar"),
                                     Idioma.porque(motivo, detalle)])
        }
    }

    // ── el editor ─────────────────────────────────────────────────
    Connections {
        target: Editor

        function onPlanListo() {
            //  Si estaba abierto en grande, se queda en grande: acabas de
            //  abrir otro vídeo desde ahí y encogerte la ventana por eso sería
            //  desconcertante.
            if (self.grande)
                return
            self.modo = "editor"
            self.open = true
        }

        function onRenderListo(ruta) {
            Modulos.quitar("editor")
            self.grande = false
            self.modo = "menu"
            self.open = false
            K4.Sistema.lanzar(["notify-send", "-a", "k4",
                                     Idioma.t("Vídeo listo"),
                                     ruta.split("/").pop()])
        }

        function onFallo(motivo, detalle) {
            K4.Sistema.lanzar(["notify-send", "-a", "k4", "-u", "critical",
                                     Idioma.t("No se pudo editar"),
                                     Idioma.porque(motivo, detalle)])
        }

        function onMiniaturaGuardada(ruta) {
            K4.Sistema.lanzar(["notify-send", "-a", "k4",
                                     Idioma.t("Miniatura guardada"),
                                     ruta.split("/").pop()])
        }
    }

    // Se va sola, pero no mientras tengas el ratón encima: si estás leyendo
    // los botones, es que los ibas a usar.
    //  Nada de atar `running` a una condición: `restart()` rompería el binding
    //  en cuanto llegara la segunda foto. Se rearma a mano, y si al vencer
    //  sigues con el ratón encima se da otra vuelta.
    //  5 s, no 1,8: con menos no da tiempo a llevar el ratón hasta «Anotar»
    //  desde donde estuvieras. Es lo que dura la miniatura de macOS, y por
    //  algo será.
    Timer {
        id: marcharse
        interval: 5000
        onTriggered: {
            if (Island.hovered)
                restart()
            else
                self.close()
        }
    }

    //  Los clics para el zoom.
    //
    //  Hyprland no los publica por su socket de eventos —no hay ningún suceso
    //  de ratón—, así que la única vía razonable es un atajo global. Va con
    //  `non_consuming` en binds.lua para que el clic siga llegando a la
    //  aplicación: si se lo comiera, el ratón dejaría de funcionar mientras
    //  grabas, que sería un remedio bastante peor.
    //
    //  Si esto no llegara a funcionar no se pierde el zoom: tools/editar.py sabe
    //  deducir los momentos del propio rastro, por los reposos del cursor.
    K4.Atajo {
        name: "clic"
        description: "Marca un clic izquierdo en el rastro de la grabación"
        onPressed: Captura.marcarClic(1)
    }

    K4.Atajo {
        name: "clicDerecho"
        description: "Marca un clic derecho en el rastro de la grabación"
        onPressed: Captura.marcarClic(3)
    }

    Connections {
        target: Modulos

        function onRestaurado(id) {
            if (id !== "editor")
                return
            self.modo = "editor"
            self.open = true
        }
    }

    K4.Ipc {
        target: "k4.captura"

        function menu(): void { self.toggle() }
        function close(): void { self.close() }

        function pantalla(): void { self.disparar("pantalla") }
        function region(): void { self.disparar("region") }
        function ventana(): void { self.disparar("ventana") }

        //  Antes esto capturaba Y abría el anotador. Ya no: el anotador se
        //  abre desde el botón de la tarjeta, cuando se pide. El atajo sigue
        //  existiendo para no romper los binds, y hace lo honesto: capturar.
        function anotar(): void { self.disparar("region") }

        // ── vídeo ──
        function grabar(): void { self.close(); Captura.grabar("") }
        function grabarRegion(): void { self.close(); Captura.grabarRegion() }
        function parar(): void { Captura.parar() }
        function grabarAlternar(): void { self.close(); Captura.alternarGrabacion() }

        function grande(): void { self.abrirGrande() }
        function encoger(): void { self.cerrarGrande() }
    }

    //  El editor tiene su propio canal.
    //
    //  No es cosmético: llegar al editor ya no pasa por haber grabado, y
    //  colgarlo de `k4.captura` diría lo contrario a quien lea los atajos.
    K4.Ipc {
        target: "k4.editor"

        // Elegir un vídeo del disco y editarlo.
        function abrir(): void { self.pedirVideo() }

        //  El diálogo del sistema, directamente: exactamente el mismo camino
        //  que el botón «Examinar…» del selector.
        function examinar(): void { self.pedirVideoDelDisco() }

        // Editar un vídeo concreto, sin pasar por el selector.
        function editar(ruta: string): void { self.abrirVideo(ruta) }

        //  Editar la última grabación, con su rastro y su cámara si los hay:
        //  el mismo camino que el botón «Editor» de la tarjeta, pero sin
        //  tener que cazar la tarjeta antes de que se marche sola.
        function ultima(): void {
            if (Captura.rutaVideo.length > 0)
                self.editarUltimaGrabacion()
        }

        //  Poner una imagen encima, sin pasar por el diálogo.
        //
        //  Sirve para automatizar y también para un atajo que suelte encima lo
        //  que haya en el portapapeles. `t` en segundos de la línea; con -1 va
        //  por donde vaya la reproducción.
        function imagen(ruta: string, t: real): void {
            Editor.crearImagen(ruta, t >= 0 ? t : Editor.posicionEditor)
        }

        // Lo mismo, pero en una capa nueva encima de todo.
        function imagenEncima(ruta: string, t: real): void {
            Editor.crearBanda()
            Editor.crearImagen(ruta, t >= 0 ? t : Editor.posicionEditor)
        }

        //  Ponerle voz al montaje: abre el micro, arranca la previa y lo que
        //  digas entra como una capa de audio. El mismo botón para empezar y
        //  para parar. `t` en segundos de la línea; con -1, por donde vaya la
        //  reproducción.
        function voz(t: real): void {
            Editor.grabarVozAlternar(t >= 0 ? t : Editor.posicionEditor)
        }

        //  Toda la transcripción como subtítulos, de golpe.
        function subtitular(): void { Editor.quemarTranscripcion() }

        //  En qué formato sale el render: mp4, webm o gif.
        function formato(cual: string): void {
            if (cual === "mp4" || cual === "webm" || cual === "gif")
                Editor.formatoSalida = cual
        }

        //  Sacar el audio de un trozo a su propia capa, o devolvérselo.
        function separarAudio(): void { Editor.separarAudio(Editor.idSel) }
        function devolverAudio(): void { Editor.devolverAudio(Editor.idSel) }
        //  Elegir un trozo por su número en la línea, para poder probar esto
        //  sin ratón. `n` empieza en 1.
        function elegirTrozo(n: int): void {
            const i = Math.max(0, n - 1)
            if (i < Editor.tramos.length)
                Editor.seleccionar("clip", Editor.tramos[i].clip)
        }

        //  Parar la imagen unos segundos. `t` en segundos de la línea; con -1
        //  va por donde vaya la reproducción.
        function congelar(t: real, dur: real): void {
            Editor.congelar(t >= 0 ? t : Editor.posicionEditor,
                            dur > 0 ? dur : 2)
        }

        //  Buscar los trozos callados y marcarlos. No borra nada: para eso está
        //  `quitarSilencios`, que se pide aparte a propósito.
        function silencios(): void { Editor.buscarSilencios() }
        function quitarSilencios(): void { Editor.quitarSilencios() }
        function olvidarSilencios(): void { Editor.olvidarSilencios() }

        // Volver a lo que estuviera abierto, por si se cerró sin querer.
        function retomar(): void {
            if (!Editor.abierto)
                return
            self.modo = "editor"
            self.open = true
        }

        function grande(): void { self.abrirGrande() }
        function encoger(): void { self.cerrarGrande() }

        // Apartarlo a la píldora, que es lo mismo que hace ESC.
        function apartar(): void { self.close() }
    }
}
