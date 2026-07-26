//  Consulta rápida a Codex CLI, autenticado con la cuenta de ChatGPT del
//  usuario. Nada de automatizar chatgpt.com: esto es el binario oficial.
//
//  Cada apertura empieza conversación nueva, para no heredar el contexto de la
//  consulta anterior ni el de otras sesiones de Codex que haya por ahí.

import QtQuick
import Quickshell
import Quickshell.Io
import "../../core"
import "../../services"

K4Plugin {
    id: self

    name: "ask"
    title: "Preguntar"
    priority: 90
    active: open
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
    readonly property string script: Quickshell.shellPath("ask.sh")

    islandWidth: 700
    islandHeight: messages.length > 0 ? 430 : 128

    function openAsk(attach) {
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
            askProcess.signal(15)

        timeoutTimer.stop()
        query = ""
        messages = []
        threadId = ""
        lastError = ""
        status = ""
        selection = ""
        selectionCandidate = ""
        attachSelectionOnOpen = false
    }

    function appendMessage(role, text) {
        messages = messages.concat([{ role: role, text: text }])
    }

    function updateLastMessage(role, text) {
        const list = messages.slice()
        for (let i = list.length - 1; i >= 0; --i) {
            if (list[i].role === "assistant" || list[i].role === "error") {
                list[i] = { role: role, text: text }
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

    function close() {
        newConversation()
        open = false
        image = ""
    }

    function send() {
        const question = query.trim()
        if (question.length === 0 || status === "thinking")
            return

        lastError = ""
        status = "thinking"
        appendMessage("user", question)
        appendMessage("assistant", "")
        query = ""

        // el preámbulo solo en el primer turno: después ya vive en la sesión
        let prompt = threadId.length === 0
            ? "Eres un asistente rápido integrado en la barra del escritorio. "
                + "Responde en español, breve y directo, en texto plano sin markdown ni listas numeradas. "
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
        }
    }

    // Lo que se adjunta tiene que verse: un texto seleccionado que el usuario
    // ya no recuerda haber marcado envenena la respuesta sin dejar rastro.
    function preview(source) {
        const text = source.replace(/\s+/g, " ").trim()
        return text.length > 30 ? text.substring(0, 30) + "…" : text
    }

    function copyAnswer() {
        for (let i = messages.length - 1; i >= 0; --i) {
            if (messages[i].role === "assistant" && messages[i].text.length > 0) {
                Quickshell.execDetached(["wl-copy", "--", messages[i].text])
                return
            }
        }
    }

    Process {
        command: ["mkdir", "-p", self.dir]
        running: true
    }

    Process {
        id: selectionProcess
        command: ["wl-paste", "--primary", "--no-newline"]

        stdout: StdioCollector {
            onStreamFinished: {
                self.selectionCandidate = this.text.trim().substring(0, 4000)
                // solo se adjunta si lo pediste explícitamente
                if (self.attachSelectionOnOpen)
                    self.selection = self.selectionCandidate
            }
        }
    }

    Process {
        id: shotProcess
        onExited: function (code) {
            const shot = code === 0 ? self.dir + "/shot.png" : ""
            self.openAsk(false)
            self.image = shot
        }
    }

    Process {
        id: askProcess

        stdout: SplitParser {
            onRead: function (line) { self.handleEvent(line) }
        }

        stderr: SplitParser {
            onRead: function (line) {
                if (line.indexOf("ERROR") !== -1 || line.indexOf("error:") !== -1)
                    self.lastError = line
            }
        }

        onExited: function (code) {
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
            }
        }
    }

    Timer {
        id: timeoutTimer
        interval: 120000
        onTriggered: {
            if (askProcess.running) {
                askProcess.signal(15)
                self.status = "error"
                self.updateLastMessage("error", "Codex no respondió en 2 minutos.")
            }
        }
    }

    IpcHandler {
        target: "k4.ask"
        function toggle(): void {
            if (self.open) self.close()
            else self.openAsk(false)
        }
        function selection(): void { self.openAsk(true) }
        function screen(): void { self.withScreenshot() }
        function region(): void { self.withRegion() }
        function now(question: string): void {
            self.openAsk(false)
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
