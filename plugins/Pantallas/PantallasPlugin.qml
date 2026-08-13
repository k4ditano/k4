import QtQuick
import K4 as K4

K4.Plugin {
    id: self

    name: "pantallas"
    title: K4.Idioma.t("Pantallas")
    priority: 67
    active: abierto
    islandWidth: 920
    // La distribución es compacta; Escritorios necesita algo más de tablero.
    islandHeight: tab === "pantallas" ? 510 : 540
    grabKeyboard: abierto
    handlesBackgroundTap: true
    onBackgroundTapped: {}

    property bool abierto: false
    property bool ocupado: false
    property string tab: "pantallas"
    property var monitores: []
    property var borradores: ({})
    property var asignaciones: ({})
    property string seleccionado: ""
    property string principal: ""
    property string principalPreferido: ""
    property string mensaje: ""
    property bool mensajeError: false

    readonly property string helper: K4.Paths.enRaiz("plugins/Pantallas/pantallas.py")

    function monitor(name) {
        for (let i = 0; i < monitores.length; ++i)
            if (monitores[i].name === name)
                return monitores[i]
        return null
    }

    function draft(name) {
        return borradores[name] || null
    }

    function modeSize(mode) {
        const match = String(mode).match(/^(\d+)x(\d+)/)
        return match ? { width: Number(match[1]), height: Number(match[2]) }
                     : { width: 1920, height: 1080 }
    }

    function logicalSize(name) {
        const d = draft(name)
        if (!d)
            return { width: 1, height: 1 }
        const size = modeSize(d.mode)
        const rotated = d.transform === 1 || d.transform === 3
        return {
            width: Math.round((rotated ? size.height : size.width) / d.scale),
            height: Math.round((rotated ? size.width : size.height) / d.scale)
        }
    }

    function setDraft(key, value) {
        const current = draft(seleccionado)
        if (!current)
            return
        const all = Object.assign({}, borradores)
        const next = Object.assign({}, current)
        next[key] = value
        all[seleccionado] = next
        borradores = all
    }

    function setPosition(name, x, y) {
        const current = draft(name)
        if (!current)
            return
        const all = Object.assign({}, borradores)
        const next = Object.assign({}, current)
        next.x = Math.round(x)
        next.y = Math.round(y)
        all[name] = next
        borradores = all
    }

    function normalizePositions() {
        let minX = 999999
        let minY = 999999
        for (let i = 0; i < monitores.length; ++i) {
            const d = draft(monitores[i].name)
            if (d) {
                minX = Math.min(minX, d.x)
                minY = Math.min(minY, d.y)
            }
        }
        if (minX === 999999 || (minX === 0 && minY === 0))
            return
        const all = Object.assign({}, borradores)
        for (let i = 0; i < monitores.length; ++i) {
            const name = monitores[i].name
            const d = draft(name)
            if (!d)
                continue
            const next = Object.assign({}, d)
            next.x = Math.round(d.x - minX)
            next.y = Math.round(d.y - minY)
            all[name] = next
        }
        borradores = all
    }

    function setAssignment(number, monitorName) {
        const next = Object.assign({}, asignaciones)
        next[String(number)] = monitorName
        asignaciones = next
    }

    function workspacesFor(monitorName) {
        const result = []
        for (let number = 1; number <= 10; ++number)
            if (asignaciones[String(number)] === monitorName)
                result.push(number)
        return result
    }

    function cycleAssignment(number) {
        if (monitores.length < 2)
            return
        const current = asignaciones[String(number)]
        let index = 0
        for (let i = 0; i < monitores.length; ++i)
            if (monitores[i].name === current) {
                index = i
                break
            }
        setAssignment(number, monitores[(index + 1) % monitores.length].name)
    }

    function place(where) {
        const selected = draft(seleccionado)
        if (!selected || monitores.length < 2)
            return
        let referenceName = ""
        for (let i = 0; i < monitores.length; ++i)
            if (monitores[i].name !== seleccionado && !monitores[i].disabled) {
                referenceName = monitores[i].name
                break
            }
        const reference = draft(referenceName)
        if (!reference)
            return
        const mine = logicalSize(seleccionado)
        const theirs = logicalSize(referenceName)
        let x = selected.x
        let y = selected.y
        if (where === "left") {
            x = reference.x - mine.width
            y = reference.y
        } else if (where === "right") {
            x = reference.x + theirs.width
            y = reference.y
        } else if (where === "above") {
            x = reference.x
            y = reference.y - mine.height
        } else if (where === "below") {
            x = reference.x
            y = reference.y + theirs.height
        } else if (where === "mirror") {
            x = reference.x
            y = reference.y
        }
        setPosition(seleccionado, x, y)
        normalizePositions()
    }

    function snapPosition(name) {
        const selected = draft(name)
        if (!selected || monitores.length < 2) {
            normalizePositions()
            return
        }
        let referenceName = ""
        for (let i = 0; i < monitores.length; ++i)
            if (monitores[i].name !== name) {
                referenceName = monitores[i].name
                break
            }
        const reference = draft(referenceName)
        if (!reference) {
            normalizePositions()
            return
        }
        const mine = logicalSize(name)
        const theirs = logicalSize(referenceName)
        const candidates = [
            { axis: "x", value: reference.x - mine.width,
              distance: Math.abs(selected.x + mine.width - reference.x), horizontal: true },
            { axis: "x", value: reference.x + theirs.width,
              distance: Math.abs(selected.x - reference.x - theirs.width), horizontal: true },
            { axis: "y", value: reference.y - mine.height,
              distance: Math.abs(selected.y + mine.height - reference.y), horizontal: false },
            { axis: "y", value: reference.y + theirs.height,
              distance: Math.abs(selected.y - reference.y - theirs.height), horizontal: false }
        ]
        candidates.sort(function (a, b) { return a.distance - b.distance })
        let x = selected.x
        let y = selected.y
        const closest = candidates[0]
        if (closest.distance < 300) {
            if (closest.axis === "x") x = closest.value
            else y = closest.value

            const alignments = closest.horizontal
                ? [reference.y,
                   reference.y + (theirs.height - mine.height) / 2,
                   reference.y + theirs.height - mine.height]
                : [reference.x,
                   reference.x + (theirs.width - mine.width) / 2,
                   reference.x + theirs.width - mine.width]
            let best = 999999
            let aligned = 0
            for (let i = 0; i < alignments.length; ++i) {
                const distance = Math.abs((closest.horizontal ? y : x) - alignments[i])
                if (distance < best) {
                    best = distance
                    aligned = alignments[i]
                }
            }
            if (best < 180) {
                if (closest.horizontal) y = aligned
                else x = aligned
            }
        }
        setPosition(name, x, y)
        normalizePositions()
    }

    function layoutMetrics(width, height) {
        let minX = 999999
        let minY = 999999
        let maxX = -999999
        let maxY = -999999
        for (let i = 0; i < monitores.length; ++i) {
            const name = monitores[i].name
            const d = draft(name)
            if (!d || monitores[i].disabled)
                continue
            const size = logicalSize(name)
            minX = Math.min(minX, d.x)
            minY = Math.min(minY, d.y)
            maxX = Math.max(maxX, d.x + size.width)
            maxY = Math.max(maxY, d.y + size.height)
        }
        if (minX === 999999)
            return { minX: 0, minY: 0, spanX: 1, spanY: 1,
                     zoom: 1, offsetX: 0, offsetY: 0 }
        const spanX = Math.max(1, maxX - minX)
        const spanY = Math.max(1, maxY - minY)
        const zoom = Math.min((width - 36) / spanX, (height - 36) / spanY)
        return {
            minX: minX, minY: minY, spanX: spanX, spanY: spanY, zoom: zoom,
            offsetX: (width - spanX * zoom) / 2,
            offsetY: (height - spanY * zoom) / 2
        }
    }

    function refresh() {
        if (statusProcess.running)
            return
        ocupado = true
        mensaje = K4.Idioma.t("Leyendo Hyprland…")
        mensajeError = false
        statusProcess.command = ["python3", helper, "status"]
        statusProcess.running = true
    }

    function receiveStatus(text) {
        try {
            const data = JSON.parse(text)
            const drafts = {}
            const active = []
            for (let i = 0; i < data.monitors.length; ++i) {
                const monitor = data.monitors[i]
                if (monitor.disabled)
                    continue
                active.push(monitor)
                const exactMode = monitor.width + "x" + monitor.height + "@"
                    + Number(monitor.refreshRate).toFixed(2) + "Hz"
                drafts[monitor.name] = {
                    name: monitor.name,
                    mode: monitor.availableModes.indexOf(exactMode) >= 0
                        ? exactMode : monitor.availableModes[0],
                    x: monitor.x,
                    y: monitor.y,
                    scale: monitor.scale,
                    transform: monitor.transform
                }
            }
            monitores = active
            borradores = drafts
            const assignments = Object.assign({}, data.assignments || ({}))
            const fallback = active.length ? active[0].name : ""
            for (let number = 1; number <= 10; ++number)
                if (!assignments[String(number)])
                    assignments[String(number)] = fallback
            asignaciones = assignments
            if (!monitor(seleccionado))
                seleccionado = active.length ? active[0].name : ""
            if (monitor(principalPreferido))
                principal = principalPreferido
            else if (!monitor(principal))
                principal = active.length ? active[0].name : ""
            mensaje = active.length
                ? K4.Idioma.f(K4.Idioma.t("%1 pantallas conectadas"), active.length)
                : K4.Idioma.t("No hay pantallas activas")
        } catch (error) {
            mensaje = K4.Idioma.t("No pude leer la configuración")
            mensajeError = true
        }
    }

    function payload(persist) {
        const configs = []
        for (let i = 0; i < monitores.length; ++i) {
            const d = draft(monitores[i].name)
            if (d)
                configs.push(d)
        }
        return JSON.stringify({
            monitors: configs,
            assignments: asignaciones,
            primary: principal,
            persist: persist
        })
    }

    function apply(persist) {
        if (applyProcess.running || monitores.length === 0)
            return
        ocupado = true
        mensajeError = false
        mensaje = persist ? K4.Idioma.t("Guardando distribución…")
                          : K4.Idioma.t("Aplicando distribución…")
        applyProcess.command = ["python3", helper, "apply", payload(persist)]
        applyProcess.running = true
        principalPreferido = principal
        guardado.guardar({ primary: principal })
    }

    function receiveApply(text) {
        try {
            const result = JSON.parse(text)
            mensaje = result.message || K4.Idioma.t("Configuración aplicada")
            mensajeError = result.ok !== true
        } catch (error) {
            mensaje = K4.Idioma.t("Hyprland devolvió una respuesta inesperada")
            mensajeError = true
        }
    }

    function toggle() {
        abierto = !abierto
        if (abierto)
            refresh()
    }

    function close() { abierto = false }

    property var guardado: K4.Guardado {
        plugin: "pantallas"
        onCargado: function (data) {
            self.principalPreferido = data.primary || ""
            if (self.monitor(self.principalPreferido))
                self.principal = self.principalPreferido
        }
    }

    K4.Process {
        id: statusProcess
        onSalida: function (text) { self.receiveStatus(text) }
        onTerminado: function (code) {
            self.ocupado = false
            if (code !== 0) {
                self.mensaje = K4.Idioma.t("No pude consultar Hyprland")
                self.mensajeError = true
            }
        }
    }

    K4.Process {
        id: applyProcess
        onSalida: function (text) { self.receiveApply(text) }
        onTerminado: function (code) {
            self.ocupado = false
            if (code !== 0 && !self.mensajeError) {
                self.mensaje = K4.Idioma.t("No se pudo aplicar la distribución")
                self.mensajeError = true
            }
            refreshAfterApply.restart()
        }
    }

    Timer {
        id: refreshAfterApply
        interval: 900
        onTriggered: self.refresh()
    }

    K4.Ipc {
        target: "k4.pantallas"
        function toggle(): void { self.toggle() }
        function open(): void { self.abierto = true; self.refresh() }
        function close(): void { self.close() }
        function refresh(): void { self.refresh() }
        function apply(): void { self.apply(false) }
        function save(): void { self.apply(true) }
        function place(where: string): void { self.place(where) }
        function state(): string {
            return JSON.stringify({ selected: self.seleccionado,
                                    drafts: self.borradores })
        }
        function tab(name: string): void {
            self.abierto = true
            self.tab = name === "workspaces" ? "workspaces" : "pantallas"
            self.refresh()
        }
    }

    view: Component { PantallasView { plugin: self } }
}
