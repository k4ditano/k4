pragma Singleton

// Registro y estado persistente de los plugins.
//
// `active` sigue siendo una decisión momentánea del host —quién ocupa la
// island—; `habilitado` es la decisión del usuario y sobrevive a los reinicios.
// Mantenerlas separadas evita que cerrar un plugin lo desactive para siempre.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: manager

    readonly property string rutaEstado:
        (Quickshell.env("HOME") || "") + "/.local/state/k4/plugins.json"
    readonly property string rutaCatalogo:
        Quickshell.shellPath("plugins/catalog.json")

    property bool cargado: false
    property var habilitados: ({})
    property var errores: ({})

    // El catálogo en JSON es la fuente que leen las herramientas externas. La
    // copia mínima evita que la barra se quede sin defaults si el fichero se
    // está actualizando o si se arranca con una versión antigua instalada.
    property var catalogo: [
        { id: "idle", title: "Píldora", version: "1.0.0", enabled: true, configurable: false },
        { id: "volume", title: "Volumen", version: "1.0.0", enabled: true },
        { id: "clock", title: "Reloj", version: "1.0.0", enabled: true },
        { id: "player", title: "Reproductor", version: "1.0.0", enabled: true },
        { id: "toast", title: "Notificación", version: "1.0.0", enabled: true },
        { id: "panel", title: "Centro de control", version: "1.0.0", enabled: true },
        { id: "launcher", title: "Lanzador", version: "1.0.0", enabled: true },
        { id: "ask", title: "Preguntar", version: "1.0.0", enabled: true },
        { id: "hyprtheme", title: "Tema de Hyprland", version: "1.0.0", enabled: true },
        { id: "weather", title: "El tiempo", version: "1.0.0", enabled: true },
        { id: "tray", title: "Bandeja", version: "1.0.0", enabled: true },
        { id: "game", title: "Mazmorra", version: "1.0.0", enabled: true },
        { id: "settings", title: "Ajustes", version: "1.0.0", enabled: true, configurable: false },
        { id: "clipboard", title: "Portapapeles", version: "1.0.0", enabled: true },
        { id: "system", title: "Sistema", version: "1.0.0", enabled: true },
        { id: "files", title: "Archivos", version: "1.0.0", enabled: true },
        { id: "keys", title: "Atajos", version: "1.0.0", enabled: true },
        { id: "windows", title: "Ventanas", version: "1.0.0", enabled: true },
        { id: "session", title: "Sesión", version: "1.0.0", enabled: true },
        { id: "captura", title: "Captura", version: "1.0.0", enabled: true }
    ]

    signal cambiado(string id, bool habilitado)

    // ── las instancias vivas ──────────────────────────────────────
    //
    //  Aquí está el cambio de fondo: los plugins ya no se instancian
    //  estáticamente en shell.qml sino que los crea este gestor desde el
    //  catálogo, uno a uno y cada uno en su try. La diferencia no es
    //  cosmética: con la instanciación estática, UN plugin roto dejaba
    //  «Type X unavailable» y cero barras —pasó esta semana—; con esta, el
    //  roto se apunta en `errores` y los otros diecinueve arrancan.
    //
    //  Y «deshabilitado» pasa a significar NO INSTANCIADO: apagar un plugin
    //  lo destruye y encenderlo lo vuelve a crear. Antes solo se le ponía una
    //  bandera y el objeto seguía ahí, gastando y pudiendo romper.
    property var instancias: []
    property var _porId: ({})
    property bool listo: false

    function instancia(id) { return _porId[id] || null }

    //  El clic de fondo de la island abre el centro de control. Vive aquí
    //  porque shell.qml ya no tiene una referencia directa al panel.
    function abrirPanel() {
        const p = instancia("panel")
        if (p)
            p.toggle()
    }

    //  Qué referencia cruzada corresponde a cada propiedad que un plugin puede
    //  declarar. Antes eran ocho asignaciones a mano en shell.qml; ahora
    //  cualquier plugin —también uno de fuera— declara `property var panel` y
    //  la recibe. El reparto es una segunda pasada tras crear todos, así que
    //  los ciclos (panel↔launcher) no dependen del orden del catálogo.
    readonly property var referencias: ({
        panel: "panel", tray: "tray", juego: "game", launcher: "launcher",
        theme: "hyprtheme", weather: "weather", ajustes: "settings",
        sistema: "system"
    })

    function arrancar() {
        if (listo)
            return
        for (let i = 0; i < catalogo.length; ++i)
            if (estaHabilitado(catalogo[i].id))
                _crear(catalogo[i])
        _repartir()
        _publicar()
        listo = true
    }

    function _crear(m) {
        const ruta = m.entry
        if (!ruta) {
            registrarError(m.id, "sin entry en el catálogo")
            return null
        }
        //  Los de casa, resueltos CONTRA ESTE FICHERO y no con file://, y esto
        //  es de las cosas que solo se ven al pisarlas: Quickshell carga el
        //  shell con su propio esquema de URL, y un singleton de services/
        //  cargado por dos URLs distintas —la del esquema y file://— son DOS
        //  singletons. Con file:// cada plugin traía su propia copia de todos
        //  los servicios: dos PluginManager, dos arranques, cada IPC registrado
        //  dos veces. `Qt.resolvedUrl` conserva el esquema del shell y todo
        //  vuelve a ser uno.
        //
        //  Los de fuera sí van con file://: no importan services/ —no tienen
        //  ruta— así que no hay singleton que duplicar.
        const url = ruta.indexOf("/") === 0
            ? "file://" + ruta
            : Qt.resolvedUrl("../plugins/" + ruta)

        //  `Qt.createComponent` es síncrono con ficheros locales, y el error
        //  se queda en `errorString()` en vez de tumbar el motor: esto es lo
        //  que convierte «barra cero» en «un plugin menos y un aviso».
        const comp = Qt.createComponent(url)
        if (comp.status === Component.Error) {
            registrarError(m.id, comp.errorString())
            return null
        }
        let obj = null
        try {
            //  `habilitado: true` de fábrica: solo se crean los habilitados,
            //  así que la bandera vieja queda como constante y los bindings
            //  de los plugins (`running: habilitado && …`) siguen valiendo.
            obj = comp.createObject(null, { habilitado: true })
        } catch (e) {
            registrarError(m.id, String(e))
            return null
        }
        if (!obj) {
            registrarError(m.id, comp.errorString() || "createObject devolvió null")
            return null
        }
        const d = Object.assign({}, _porId)
        d[m.id] = obj
        _porId = d
        limpiarError(m.id)
        return obj
    }

    //  El reparto de referencias: para cada instancia, cada propiedad del mapa
    //  que declare se rellena con la instancia que le toca — o con null si esa
    //  no está cargada, que es lo que deja los bindings con guarda en paz.
    function _repartir() {
        for (const id in _porId) {
            const obj = _porId[id]
            for (const prop in referencias) {
                if (!(prop in obj))
                    continue
                const destino = _porId[referencias[prop]] || null
                if (obj[prop] !== destino)
                    obj[prop] = destino
            }
        }
    }

    function _publicar() {
        const lista = []
        for (let i = 0; i < catalogo.length; ++i)
            if (_porId[catalogo[i].id])
                lista.push(_porId[catalogo[i].id])
        instancias = lista
    }

    function _destruir(id) {
        const obj = _porId[id]
        if (!obj)
            return
        //  Cerrar antes de destruir: que suelte la island y sus vistas por las
        //  buenas. Lo que era un Connections en shell.qml vive ahora aquí.
        if (typeof obj.close === "function") {
            try { obj.close() } catch (e) { }
        }
        const d = Object.assign({}, _porId)
        delete d[id]
        _porId = d
        //  Y el reparto otra vez: quien tuviera esta referencia pasa a null en
        //  vez de quedarse con un objeto muerto, que revienta al primer uso.
        _repartir()
        obj.destroy()
    }

    //  Volver a intentar un plugin que falló: es lo que hace útil el botón de
    //  «reintentar» de Ajustes. Solo para los que no están cargados; recargar
    //  uno vivo con procesos y vistas es otra historia y queda fuera.
    function reintentar(id) {
        if (_porId[id] || !estaHabilitado(id))
            return
        const m = metadata(id)
        if (!m)
            return
        limpiarError(id)
        if (_crear(m)) {
            _repartir()
            _publicar()
        }
    }

    onCambiado: function (id, valor) {
        if (!listo)
            return
        if (valor && !_porId[id]) {
            const m = metadata(id)
            if (m && _crear(m)) {
                _repartir()
                _publicar()
            }
        } else if (!valor && _porId[id]) {
            _destruir(id)
            _publicar()
        }
    }

    function indice(id) {
        for (let i = 0; i < catalogo.length; ++i)
            if (catalogo[i].id === id)
                return i
        return -1
    }

    function metadata(id) {
        const i = indice(id)
        return i >= 0 ? catalogo[i] : null
    }

    function estaHabilitado(id) {
        const m = metadata(id)
        if (!m)
            return false
        return habilitados[id] !== undefined ? !!habilitados[id] : m.enabled !== false
    }

    function puedeConfigurar(id) {
        const m = metadata(id)
        return !!(m && m.configurable !== false)
    }

    function poner(id, valor) {
        if (indice(id) < 0 || !puedeConfigurar(id))
            return
        const d = Object.assign({}, habilitados)
        d[id] = !!valor
        habilitados = d
        if (!valor)
            Indicadores.quitarDe(id)
        guardar()
        cambiado(id, !!valor)
    }

    function alternar(id) { poner(id, !estaHabilitado(id)) }

    function habilitar(id) { poner(id, true) }
    function deshabilitar(id) { poner(id, false) }

    function registrarError(id, motivo) {
        const d = Object.assign({}, errores)
        d[id] = String(motivo || "error de carga")
        errores = d
    }

    function limpiarError(id) {
        const d = Object.assign({}, errores)
        delete d[id]
        errores = d
    }

    readonly property var opcionesAjustes: catalogo
        .filter(function (m) { return m.configurable !== false })
        .map(function (m) {
            return { id: "plugin_" + m.id,
                     pluginId: m.id,
                     nombre: m.title,
                     desc: "Activar o desactivar este plugin",
                     glifo: 0xF04E5 }
        })

    function valorAjuste(id) {
        return estaHabilitado(String(id).replace(/^plugin_/, ""))
    }

    function alternarAjuste(id) {
        alternar(String(id).replace(/^plugin_/, ""))
    }

    function cargar() {
        const bruto = estado.text()
        if (bruto.length > 0) {
            try {
                const d = JSON.parse(bruto)
                if (d.habilitados && typeof d.habilitados === "object")
                    habilitados = d.habilitados
            } catch (e) {
                // Un estado roto no impide arrancar: se usan los defaults.
            }
        }
        cargado = true
        //  Y con el estado en la mano, los plugins. Arrancar desde aquí y no
        //  desde shell.qml evita la carrera: el estado llega en asíncrono
        //  —espera al mkdir— y crear antes de saberlo instanciaría plugins que
        //  el usuario tiene apagados.
        arrancar()
    }

    function cargarCatalogo() {
        const bruto = catalogoFile.text()
        if (!bruto || bruto.length === 0)
            return
        try {
            const d = JSON.parse(bruto)
            if (!d.plugins || !Array.isArray(d.plugins))
                return
            catalogo = d.plugins.map(function (m) {
                return Object.assign({}, m, {
                    enabled: m.enabledByDefault !== false
                })
            })
        } catch (e) {
            // Se conserva el catálogo de emergencia embebido.
        }
    }

    function guardar() {
        if (!cargado)
            return
        estado.setText(JSON.stringify({ habilitados: habilitados }, null, 1))
    }

    FileView {
        id: estado
        path: manager.rutaEstado
        blockLoading: true
    }

    FileView {
        id: catalogoFile
        path: manager.rutaCatalogo
        blockLoading: true
        onLoaded: manager.cargarCatalogo()
    }

    Process {
        command: ["mkdir", "-p", Quickshell.env("HOME") + "/.local/state/k4"]
        running: true
        onExited: manager.cargar()
    }
}
