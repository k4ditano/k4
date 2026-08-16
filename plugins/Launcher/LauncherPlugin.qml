//  Lanzador estilo Spotlight, con un segundo modo para instalar paquetes.
//
//  Dos velocidades en la búsqueda: pacman lee la base local (~0.3 s) y sale al
//  instante; yay consulta el RPC de AUR (~1.3 s) y se deja para cuando dejas
//  de teclear, para no abusar del servicio.

import QtQuick
import K4 as K4
import "../../core"
import "../../services"

K4Plugin {
    id: self

    name: "launcher"
    title: Idioma.t("Lanzador")
    priority: 80
    // sigue ocupando la island mientras se encoge, pero ya sin contenido
    active: habilitado && (open || closing)
    viewLoaded: open
    grabKeyboard: open

    // lo aparta al abrirse; lo inyecta el host
    property var panel: null

    property bool open: false
    property bool closing: false
    property string query: ""
    property int index: 0
    property var matches: []
    property string mode: "apps"        // "apps" | "packages"

    property var repoResults: []
    property var aurResults: []
    property var installedPackages: ({})
    property bool aurSearching: false

    // Al abrir el lanzador se actualiza el índice de aplicaciones del usuario.
    // K4.Apps ya vigila cambios, pero este paso cubre instalaciones que
    // crean el .desktop mientras k4 estaba cerrado o durante un escaneo.
    readonly property string applicationsDir: {
        const dataHome = K4.Sistema.entorno("XDG_DATA_HOME")
        const base = dataHome && dataHome.length > 0
            ? dataHome : K4.Sistema.entorno("HOME") + "/.local/share"
        return base + "/applications"
    }

    islandWidth: 720
    islandHeight: 440

    readonly property int count: mode === "packages" ? packageMatches.length : matches.length

    // repos primero, y dentro de cada origen los nombres más parecidos arriba
    readonly property var packageMatches: {
        const q = packageQuery().toLowerCase()
        const scored = []
        const all = repoResults.concat(aurResults)

        for (let i = 0; i < all.length; ++i) {
            const pkg = all[i]
            const name = pkg.name.toLowerCase()
            let score = 0
            if (name === q) score = 0
            else if (name.indexOf(q) === 0) score = 1
            else if (name.indexOf(q) !== -1) score = 2
            else score = 3

            scored.push({
                repo: pkg.repo,
                name: pkg.name,
                version: pkg.version,
                description: pkg.description,
                installed: installedPackages[pkg.name] === true,
                score: score + (pkg.repo === "aur" ? 4 : 0),
                order: i
            })
        }

        scored.sort(function (a, b) {
            if (a.score !== b.score) return a.score - b.score
            return a.order - b.order
        })

        // CachyOS sirve muchos paquetes también desde sus repos propios: se
        // queda el primero, que es el que pacman elegiría por prioridad
        const seen = ({})
        const unique = []
        for (let j = 0; j < scored.length; ++j) {
            if (seen[scored[j].name] === true)
                continue
            seen[scored[j].name] = true
            unique.push(scored[j])
        }

        return unique.slice(0, 60)
    }

    function packageQuery() {
        // pacman -Ss interpreta el patrón como regex: fuera todo lo que pueda
        // romperlo o convertirse en un comodín inesperado
        return query.replace(/[^A-Za-z0-9 _.+-]/g, "").trim()
    }

    function parsePackages(text, onlyAur) {
        const lines = text.split("\n")
        const packages = []
        let current = null

        for (let i = 0; i < lines.length; ++i) {
            const line = lines[i]
            if (line.length === 0)
                continue

            if (line.charAt(0) === " " || line.charAt(0) === "\t") {
                if (current && current.description.length === 0)
                    current.description = line.trim()
                continue
            }

            const match = line.match(/^([^\s\/]+)\/(\S+)\s+(\S+)/)
            if (!match) {
                current = null
                continue
            }

            if (onlyAur && match[1] !== "aur") {
                current = null
                continue
            }

            current = {
                repo: match[1],
                name: match[2],
                version: match[3],
                description: ""
            }
            packages.push(current)
        }

        return packages
    }

    function runRepoSearch() {
        const q = packageQuery()
        if (q.length < 2) {
            repoResults = []
            return
        }

        if (repoSearchProcess.running)
            repoSearchProcess.parar(15)

        repoSearchProcess.command = ["pacman", "-Ss", "--"].concat(q.split(/\s+/))
        repoSearchProcess.running = true
    }

    function runAurSearch() {
        const q = packageQuery()
        if (q.length < 2) {
            aurResults = []
            aurSearching = false
            return
        }

        if (aurSearchProcess.running)
            aurSearchProcess.parar(15)

        aurSearching = true
        aurSearchProcess.command = ["yay", "-Ss", "--aur", "--color=never", "--"].concat(q.split(/\s+/))
        aurSearchProcess.running = true
    }

    function schedulePackageSearch() {
        repoSearchTimer.restart()
        aurSearchTimer.restart()
    }

    // atajo directo al modo instalar, sin pasar por la lista de apps
    function openPackageSearch(initial) {
        if (panel) panel.close()
        Notifs.dismissToast()
        closing = false
        open = true
        query = initial !== undefined ? initial : ""
        enterPackageMode()
    }

    function enterPackageMode() {
        mode = "packages"
        index = 0
        repoResults = []
        aurResults = []
        installedListProcess.running = true
        schedulePackageSearch()
    }

    function leavePackageMode() {
        mode = "apps"
        index = 0
        repoSearchTimer.stop()
        aurSearchTimer.stop()
        aurSearching = false
        rebuild()
    }

    // Un nombre llega de pacman o yay, pero sigue siendo dato: se cita antes
    // de meterlo en el guion que recibe la terminal. Así ni una comilla ni un
    // carácter de shell pueden convertir un paquete en una orden distinta.
    function shellArgument(value) {
        return "'" + String(value || "").replace(/'/g, "'\"'\"'") + "'"
    }

    function installPackage(pkg) {
        if (!pkg)
            return

        // yay no puede correr como root (makepkg se niega), y AUR pide revisar
        // PKGBUILD y responder preguntas: por eso va en una terminal de verdad
        // y no en un proceso mudo. La island lo es, así que vale igual — y si
        // se queda corta para leer un PKGBUILD, SUPER+ALT+T la saca a ventana
        // con la instalación dentro, sin cortarla.
        const name = shellArgument(pkg.name)
        const script = "yay -S --needed -- " + name
            + " && notify-send -a 'Instalar' " + name + " 'Instalado correctamente'"
            + " || { notify-send -a 'Instalar' -u critical " + name + " 'La instalación falló';"
            + Consola.cierre + " }"

        Consola.ejecutar(script)
        close()
    }

    function uninstallPackage(pkg) {
        if (!pkg || pkg.installed !== true)
            return

        // pacman enseña qué se va a retirar y pide confirmación antes de tocar
        // nada. Sirve también para paquetes de AUR: una vez instalados, todos
        // viven en la misma base local de pacman.
        const name = shellArgument(pkg.name)
        const script = "sudo pacman -Rns --confirm -- " + name
            + " && notify-send -a 'Desinstalar' " + name + " 'Desinstalado correctamente'"
            + " || { notify-send -a 'Desinstalar' -u critical " + name + " 'La desinstalación falló';"
            + Consola.cierre + " }"

        Consola.ejecutar(script)
        close()
    }

    function uninstallSelected() {
        if (mode !== "packages" || index < 0 || index >= packageMatches.length)
            return
        uninstallPackage(packageMatches[index])
    }

    // `conservarSeleccion` lo usa el refresco periódico: sin él, cada segundo
    // se reponía el índice a cero y la lista te devolvía arriba mientras
    // bajabas con las flechas o la rueda.
    function rebuild(conservarSeleccion) {
        const q = query.trim().toLowerCase()
        const applications = K4.Apps.lista
        const found = []

        for (let i = 0; i < applications.length; ++i) {
            const app = applications[i]
            if (app.noDisplay)
                continue

            const haystack = (app.name + " " + app.genericName + " " + app.id).toLowerCase()
            if (q.length === 0 || haystack.indexOf(q) !== -1)
                found.push(app)
        }

        found.sort(function (a, b) { return a.name.localeCompare(b.name) })

        //  Este panel es el de las aplicaciones DEL SISTEMA y manda eso: lo
        //  que aporten los plugins va detrás, nunca por delante. Quien abre el
        //  lanzador y escribe «fire» quiere Firefox, y un aporte por bien
        //  intencionado que sea no puede colarse encima de lo que la persona
        //  venía a buscar. Para las cosas de la barra está su propio cajón
        //  (SUPER+SHIFT+Space); aquí salen para que se puedan ENCONTRAR, no
        //  para competir.
        //  Tres maneras de tener icono, en este orden: el que trae el propio
        //  resultado —`imagen` o `glifo`—, el nombre de icono del escritorio
        //  si lo que aporta ES una aplicación instalada, y si no el de su
        //  plugin. Antes solo existía la segunda, así que un aporte de un
        //  plugin salía con el hueco vacío: la fila esperaba un nombre de
        //  icono del escritorio y lo que un plugin tiene es otra cosa. Un
        //  hueco entre filas que sí tienen icono se lee como «esto está a
        //  medias», que era justo lo contrario de lo que pasaba.
        const extras = (Enganches.resultados || []).map(function (r) {
            let imagen = r.imagen || ""
            let glifo = r.glifo || 0
            if (!imagen && !glifo && !r.icono) {
                const suyo = PluginManager.iconoDe(r._plugin || "")
                imagen = suyo.imagen
                glifo = suyo.glifo
            }
            return { name: r.titulo || "", genericName: r.desc || "",
                     icon: r.icono || "", _enganche: r,
                     _imagen: imagen, _glifo: glifo }
        })
        const list = found.slice(0, 40).concat(extras)

        if (q.length > 0) {
            const installEntry = {
                isInstall: true,
                name: "Instalar «" + query.trim() + "»",
                genericName: "Buscar en los repos oficiales y AUR",
                icon: ""
            }

            // se puede alcanzar escribiendo "instalar"/"install", que la sube arriba
            const triggered = "instalar".indexOf(q) === 0 || "install".indexOf(q) === 0
            if (triggered)
                list.unshift(installEntry)
            else
                list.push(installEntry)
        }

        matches = list
        if (conservarSeleccion === true)
            index = Math.max(0, Math.min(index, list.length - 1))
        else
            index = 0
    }

    //  Avisar a los plugins de lo que se está escribiendo, y repintar cuando
    //  contesten — que puede ser más tarde, si lo suyo cuesta.
    onQueryChanged: Enganches.buscar(query)

    property Connections _aportes: Connections {
        target: Enganches
        function onResultadosChanged() { self.rebuild(true) }
    }

    function refreshApplications() {
        desktopDatabaseProcess.running = true
        rebuild()
    }

    function toggle() {
        if (open) {
            close()
            return
        }

        query = ""
        mode = "apps"
        closing = false
        if (panel) panel.close()
        Notifs.dismissToast()
        //  De paso se miran las actualizaciones: el lanzador es la puerta
        //  que el usuario abre veinte veces al día, y el contador vive en
        //  el servicio con su caché — no cuesta nada.
        Paquetes.comprobar(false)
        open = true
        refreshApplications()
    }

    function close() {
        open = false
        closing = true
        query = ""
        mode = "apps"
        repoSearchTimer.stop()
        aurSearchTimer.stop()
        aurSearching = false
        closeTimer.restart()
    }

    function launchSelected() {
        if (mode === "packages") {
            installPackage(packageMatches[index])
            return
        }

        if (matches.length === 0)
            return

        const entry = matches[index]

        //  Uno aportado por un plugin: se lo devolvemos y él sabrá.
        if (entry && entry._enganche) {
            close()
            Enganches.elegir(entry._enganche)
            return
        }

        if (entry && entry.isInstall === true) {
            enterPackageMode()
            return
        }

        close()
        abrir(entry)
    }

    // No se usa entry.execute(): eso hereda el directorio de trabajo de la
    // barra, que es la carpeta de configuración de quickshell —de ahí que las
    // terminales abrieran en ~/.config/quickshell/k4—. Se lanza con el
    // directorio que pida la propia entrada y, si no pide ninguno, en casa.
    function abrir(entry) {
        const dir = entry.workingDirectory && entry.workingDirectory.length > 0
            ? entry.workingDirectory : K4.Sistema.entorno("HOME")

        if (!entry.command || entry.command.length === 0) {
            entry.execute()
            return
        }

        K4.Sistema.lanzar(["sh", "-c",
            "cd " + JSON.stringify(dir) + " && exec \"$@\"", "sh"].concat(entry.command))
    }

    function moveSelection(delta) {
        if (count === 0)
            return

        index = Math.max(0, Math.min(count - 1, index + delta))
    }

    // Una notificación aparta el lanzador.
    Connections {
        target: Notifs
        function onNotified() { self.open = false }
    }

    Connections {
        target: K4.Apps
        function onListaChanged() { self.rebuild() }
    }

    Timer {
        id: closeTimer
        interval: 320
        onTriggered: self.closing = false
    }

    Timer {
        interval: 1000
        repeat: true
        running: self.open && self.mode === "apps"
        onTriggered: self.rebuild(true)
    }

    K4.Process {
        id: installedListProcess
        command: ["pacman", "-Qq"]

        onSalida: function (texto) {
            const set = ({})
            const names = texto.split("\n")
            for (let i = 0; i < names.length; ++i) {
                const name = names[i].trim()
                if (name.length > 0)
                    set[name] = true
            }
            self.installedPackages = set
        }
    }

    K4.Process {
        id: desktopDatabaseProcess
        command: ["update-desktop-database", self.applicationsDir]
        onTerminado: self.rebuild()
    }

    K4.Process {
        id: repoSearchProcess
        environment: ({ "LC_ALL": "C" })

        onSalida: function (texto) {
            self.repoResults = self.parsePackages(texto, false)
        }
    }

    K4.Process {
        id: aurSearchProcess
        environment: ({ "LC_ALL": "C" })

        onSalida: function (texto) {
            self.aurResults = self.parsePackages(texto, true)
            self.aurSearching = false
        }

        onTerminado: self.aurSearching = false
    }

    Timer {
        id: repoSearchTimer
        interval: 180
        onTriggered: self.runRepoSearch()
    }

    Timer {
        id: aurSearchTimer
        interval: 500
        onTriggered: self.runAurSearch()
    }

    K4.Ipc {
        target: "k4.launcher"
        function toggle(): void { self.toggle() }
        function install(q: string): void { self.openPackageSearch(q) }
        function search(q: string): void {
            if (!self.open)
                self.toggle()
            self.query = q
            self.rebuild()
        }
    }

    view: Component {
        LauncherView { plugin: self }
    }
}
