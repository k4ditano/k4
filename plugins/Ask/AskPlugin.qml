//  Consulta rápida a Codex CLI, autenticado con la cuenta de ChatGPT del
//  usuario. Nada de automatizar chatgpt.com: esto es el binario oficial.
//
//  Cada apertura empieza conversación nueva, para no heredar el contexto de la
//  consulta anterior ni el de otras sesiones de Codex que haya por ahí.

import QtQuick
import K4 as K4
import "../../core"
import "../../services"

K4Plugin {
    id: self

    name: "ask"
    title: Idioma.t("Preguntar")
    priority: 90
    active: habilitado && open
    grabKeyboard: true

    // los aparta al abrirse; los inyecta el host
    property var panel: null
    property var launcher: null

    property bool open: false
    property string query: ""
    property string status: ""        // "" | "thinking" | "error"
    property string image: ""
    property string selection: ""           // adjunto de verdad (opt-in)
    property string selectionCandidate: ""  // lo seleccionado, aún sin adjuntar
    property bool attachSelectionOnOpen: false
    property var messages: []         // [{ role: "user"|"assistant"|"error", text }]
    property string lastError: ""

    // id de sesión de Codex de ESTA conversación. Vacío = sesión nueva.
    // Nunca se resume con --last, que engancharía con otras sesiones.
    property string threadId: ""

    readonly property string dir: "/tmp/k4-ask"
    readonly property string script: K4.Paths.enRaiz("ask.sh")

    islandWidth: 700
    islandHeight: messages.length > 0 ? 430 : 128

    //  Abrir RETOMA lo que hubiera apartado — con Escape o con el −, daba
    //  igual: volver a pulsar el atajo no puede costar la conversación que
    //  dejaste a medias. Para empezar de cero está el botón «nueva» (y
    //  `fresco: true`, que usa el IPC de pregunta directa).
    function openAsk(attach, fresco) {
        const retomar = fresco !== true && messages.length > 0
        Modulos.quitar("ask")
        if (!retomar)
            newConversation()
        if (panel) panel.close()
        if (launcher) launcher.close()
        Notifs.dismissToast()
        attachSelectionOnOpen = attach === true
        // se lee para poder ofrecerla, pero no se adjunta sin permiso
        selectionProcess.running = true
        open = true
    }

    function attach() {
        if (selectionCandidate.length > 0)
            selection = selectionCandidate
    }

    function newConversation() {
        if (askProcess.running)
            askProcess.parar(15)

        timeoutTimer.stop()
        query = ""
        messages = []
        threadId = ""
        lastError = ""
        status = ""
        imagenVista = ""
        selection = ""
        selectionCandidate = ""
        attachSelectionOnOpen = false
    }

    function appendMessage(role, text, imagen) {
        messages = messages.concat([{
            role: role, text: text, imagen: imagen || ""
        }])
    }

    // Imágenes en la respuesta, por dos caminos:
    //
    //  - Una ruta absoluta suelta: Codex tocó un fichero y lo nombra.
    //  - `attachment://exec-<id>.png`: su herramienta de GENERAR imágenes.
    //    Ese esquema no es ninguna ruta, pero el fichero real está en
    //    ~/.codex/generated_images/<sesión>/ y la sesión es nuestro threadId
    //    — así que se reconstruye. Antes esto se perdía: generaba la imagen
    //    y la conversación enseñaba un enlace roto.
    function imagenEn(texto) {
        const t = String(texto)
        const adjunto = t.match(/attachment:\/\/([^\s"'`)]+\.(?:png|jpe?g|webp|gif))/i)
        if (adjunto && threadId.length > 0)
            return K4.Sistema.entorno("HOME") + "/.codex/generated_images/"
                + threadId + "/" + adjunto[1]
        const ruta = t.match(/(\/[^\s"'`)]+\.(?:png|jpe?g|webp|gif))/i)
        return ruta ? ruta[1] : ""
    }

    //  El markdown de una imagen que ya se enseña aparte es un enlace roto
    //  en medio del texto: fuera.
    function sinAdjuntos(texto) {
        return String(texto)
            .replace(/!?\[[^\]]*\]\(attachment:\/\/[^\)]*\)/g, "")
            .replace(/attachment:\/\/[^\s"'`)]+/g, "")
            .trim()
    }

    function updateLastMessage(role, text) {
        const list = messages.slice()
        for (let i = list.length - 1; i >= 0; --i) {
            if (list[i].role === "assistant" || list[i].role === "error") {
                const imagen = imagenEn(text)
                list[i] = { role: role,
                            text: imagen ? sinAdjuntos(text) : text,
                            imagen: imagen }
                messages = list
                return
            }
        }
        appendMessage(role, text)
    }

    function withScreenshot() {
        // se captura antes de expandir la island, así no sale ella en la foto
        image = ""
        attachSelectionOnOpen = false
        shotProcess.command = ["grim", dir + "/shot.png"]
        shotProcess.running = true
    }

    function withRegion() {
        image = ""
        shotProcess.command = ["sh", "-c", "grim -g \"$(slurp -d)\" " + dir + "/shot.png"]
        shotProcess.running = true
    }

    //  Cerrar aparta la conversación, no la tira.
    //
    //  Antes `close()` llamaba a newConversation() y con eso se perdía todo: la
    //  pregunta, la respuesta y el hilo de Codex. Eso obligaba a dejar la
    //  island ocupada hasta terminar de leer, porque cerrarla costaba la
    //  conversación entera.
    function close() {
        if (messages.length > 0) {
            Modulos.minimizar("ask", Idioma.t("Pregunta"),
                              resumenConversacion(), Theme.ico.ask.codePointAt(0))
        }
        open = false
    }

    // Descartar de verdad: esto sí olvida.
    function cerrarYOlvidar() {
        Modulos.quitar("ask")
        newConversation()
        open = false
        image = ""
    }

    // Las primeras palabras de lo que preguntaste, para reconocerla en la
    // píldora sin tener que abrirla.
    function resumenConversacion() {
        for (let i = 0; i < messages.length; ++i) {
            if (messages[i].role === "user") {
                const t = String(messages[i].text || "").trim()
                return t.length > 26 ? t.substring(0, 26) + "…" : t
            }
        }
        return ""
    }

    function send() {
        const question = query.trim()
        if (question.length === 0 || status === "thinking")
            return

        lastError = ""
        status = "thinking"
        appendMessage("user", question, image)
        appendMessage("assistant", "")
        query = ""

        // el preámbulo solo en el primer turno: después ya vive en la sesión
        let prompt = threadId.length === 0
            ? "Eres un asistente rápido integrado en la barra del escritorio. "
                + "Responde en español, breve y directo. Puedes usar markdown sencillo: "
                + "negrita, cursiva, código y enlaces. Nada de tablas ni encabezados. "
                + "No ejecutes comandos ni leas archivos salvo que la pregunta lo pida explícitamente.\n\n"
                + "Pregunta: " + question
            : question

        if (selection.length > 0)
            prompt += "\n\nTexto que el usuario tiene seleccionado en pantalla:\n" + selection

        if (image.length > 0)
            prompt += "\n\nSe adjunta una captura de la pantalla del usuario."

        // vía wrapper: necesita cerrar stdin, si no `codex exec` se cuelga
        // esperando EOF (Quickshell le deja el pipe abierto)
        askProcess.command = [script, prompt, image, threadId]
        askProcess.running = true
        timeoutTimer.restart()

        // los adjuntos son de este turno, no de toda la conversación
        image = ""
        selection = ""
    }

    //  La herramienta de generar imágenes de Codex no deja rastro fiable en
    //  el texto: a veces `attachment://…`, a veces un mensaje final VACÍO —
    //  la imagen solo existe como fichero en generated_images/<sesión>/. Así
    //  que al acabar el turno se mira ahí directamente, y si hay una nueva se
    //  engancha al último mensaje (aunque fuera un «error» por respuesta
    //  vacía: una imagen ES la respuesta).
    property string imagenVista: ""

    function buscarImagenGenerada() {
        if (threadId.length === 0)
            return
        buscadorImagen.command = ["sh", "-c",
            "ls -t " + K4.Sistema.entorno("HOME") + "/.codex/generated_images/"
            + threadId + "/*.png 2>/dev/null | head -1"]
        buscadorImagen.running = true
    }

    K4.Process {
        id: buscadorImagen
        onSalida: function (texto) {
            const ruta = texto.trim()
            if (ruta.length === 0 || ruta === self.imagenVista)
                return
            self.imagenVista = ruta
            const list = self.messages.slice()
            for (let i = list.length - 1; i >= 0; --i) {
                if (list[i].role === "assistant" || list[i].role === "error") {
                    const t = (list[i].role === "assistant"
                               && list[i].text.length > 0)
                        ? list[i].text : Idioma.t("Aquí la tienes:")
                    list[i] = { role: "assistant", text: t, imagen: ruta }
                    self.messages = list
                    if (self.status === "error")
                        self.status = ""
                    return
                }
            }
        }
    }

    function handleEvent(line) {
        const text = line.trim()
        if (text.length === 0 || text.charAt(0) !== "{")
            return

        let event
        try {
            event = JSON.parse(text)
        } catch (error) {
            return
        }

        if (event.type === "thread.started" && event.thread_id) {
            threadId = event.thread_id
        } else if ((event.type === "item.completed" || event.type === "item.updated") && event.item) {
            if (event.item.type === "agent_message" && event.item.text)
                updateLastMessage("assistant", event.item.text)
        } else if (event.type === "turn.failed" || event.type === "error") {
            status = "error"
            updateLastMessage("error",
                event.error && event.error.message ? event.error.message : "Codex devolvió un error.")
        } else if (event.type === "turn.completed") {
            if (status === "thinking")
                status = ""
            buscarImagenGenerada()
        }
    }

    // Lo que se adjunta tiene que verse: un texto seleccionado que el usuario
    // ya no recuerda haber marcado envenena la respuesta sin dejar rastro.
    function preview(source) {
        const text = source.replace(/\s+/g, " ").trim()
        return text.length > 30 ? text.substring(0, 30) + "…" : text
    }

    function guardarImagen(ruta) {
        if (!ruta || ruta.length === 0)
            return
        const destino = K4.Sistema.entorno("HOME") + "/Imágenes"
        K4.Sistema.lanzar(["sh", "-c",
            "mkdir -p " + JSON.stringify(destino)
            + " && cp -n " + JSON.stringify(ruta) + " " + JSON.stringify(destino) + "/"])
    }

    function abrirExterno(ruta) {
        if (ruta && ruta.length > 0)
            K4.Sistema.lanzar(["xdg-open", ruta])
    }

    function copyAnswer() {
        for (let i = messages.length - 1; i >= 0; --i) {
            if (messages[i].role === "assistant" && messages[i].text.length > 0) {
                K4.Sistema.lanzar(["wl-copy", "--", messages[i].text])
                return
            }
        }
    }

    K4.Process {
        command: ["mkdir", "-p", self.dir]
        running: true
    }

    K4.Process {
        id: selectionProcess
        command: ["wl-paste", "--primary", "--no-newline"]

        onSalida: function (texto) {
            self.selectionCandidate = texto.trim().substring(0, 4000)
            // solo se adjunta si lo pediste explícitamente
            if (self.attachSelectionOnOpen)
                self.selection = self.selectionCandidate
        }
    }

    K4.Process {
        id: shotProcess
        onTerminado: function (code) {
            const shot = code === 0 ? self.dir + "/shot.png" : ""
            self.openAsk(false)
            self.image = shot
        }
    }

    K4.Process {
        id: askProcess
        porLineas: true

        onLinea: function (line) { self.handleEvent(line) }

        onLineaError: function (line) {
            if (line.indexOf("ERROR") !== -1 || line.indexOf("error:") !== -1)
                self.lastError = line
        }

        onTerminado: function (code) {
            timeoutTimer.stop()

            const last = self.messages.length > 0
                ? self.messages[self.messages.length - 1] : null
            const answered = last && last.role === "assistant" && last.text.length > 0

            if (!answered) {
                self.status = "error"
                self.updateLastMessage("error", self.lastError.length > 0
                    ? self.lastError
                    : "Codex terminó con código " + code + " y sin respuesta.")
            } else if (self.status === "thinking") {
                self.status = ""
                //  Apartada mientras pensaba: avisar de que ya está, que para
                //  eso se apartó — para no quedarse mirando.
                if (!self.open)
                    K4.Sistema.avisar(Idioma.t("Respuesta lista"),
                                      self.resumenConversacion(), false)
            }

            //  Y en cualquier caso, mirar si este turno dejó una imagen: el
            //  veredicto de «sin respuesta» se corrige solo si aparece.
            self.buscarImagenGenerada()
        }
    }

    Timer {
        id: timeoutTimer
        interval: 120000
        onTriggered: {
            if (askProcess.running) {
                askProcess.parar(15)
                self.status = "error"
                self.updateLastMessage("error", "Codex no respondió en 2 minutos.")
            }
        }
    }

    Connections {
        target: Modulos
        function onRestaurado(id) {
            if (id === "ask")
                self.open = true
        }
    }

    K4.Ipc {
        target: "k4.ask"
        function toggle(): void {
            if (self.open) self.close()
            else self.openAsk(false)
        }
        function selection(): void { self.openAsk(true) }
        function screen(): void { self.withScreenshot() }
        function region(): void { self.withRegion() }
        function now(question: string): void {
            //  Pregunta directa: esta sí empieza de cero, que viene de un
            //  guion y mezclar hilos sería peor.
            self.openAsk(false, true)
            self.query = question
            self.send()
        }
        function followUp(question: string): void {
            if (!self.open)
                self.openAsk(false)
            self.query = question
            self.send()
        }
    }

    view: Component {
        AskView { plugin: self }
    }
}
