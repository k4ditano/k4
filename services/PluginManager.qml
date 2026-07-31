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
        //  Hacen falta las dos patas: el estado del usuario —qué tiene apagado—
        //  y el catálogo combinado. Llegan en asíncrono y en cualquier orden;
        //  quien llega segundo dispara la creación.
        if (listo || !cargado || !catalogoListo)
            return
        for (let i = 0; i < catalogo.length; ++i) {
            const m = catalogo[i]
            //  Un plugin no cargable —manifiesto roto, versión incompatible,
            //  permisos sin declarar— ni se intenta: su motivo ya viene del
            //  listado y Ajustes lo enseña.
            if (m.cargable === false) {
                registrarError(m.id, m.motivo || "no cargable")
                continue
            }
            if (estaHabilitado(m.id))
                _crear(m)
        }
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
        //  TODO se resuelve contra este fichero, nunca con file://, y es de
        //  las cosas que solo se ven al pisarlas: Quickshell sirve el shell
        //  con su propio esquema de URL, y un singleton cargado por dos URLs
        //  distintas son DOS singletons. Con file:// cada plugin traía su
        //  propia copia de la barra entera: dos PluginManager, dos oleadas de
        //  creación, cada target de IPC registrado dos veces y los toggles
        //  contestando desde el cadáver equivocado.
        //
        //  Los de usuario entran por el enlace `externos/` —que apunta a
        //  ~/.config/k4/plugins y lo mantiene tools/plugins.py— justamente
        //  para poder resolverse con el mismo esquema que todo lo demás.
        //  Y una recarga llega ya con su ruta hecha —`recargas/<id>-<n>/…`,
        //  la carpeta nueva que da plugins.py— así que se resuelve tal cual.
        const url = m._recarga ? Qt.resolvedUrl("../" + ruta)
            : ruta.indexOf("/") === 0
            ? Qt.resolvedUrl("../externos/" + m.id + "/"
                             + ruta.split("/").pop())
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

        //  Y sus enganches fuera: una fila de Ajustes o un resultado del
        //  lanzador que apunte a un plugin destruido es una llamada a un
        //  cadáver. Los K4.Ajustes se dan de baja solos al destruirse, pero
        //  eso es diferido y aquí queremos que desaparezcan YA.
        Enganches.quitarDe(id)

        //  Y APAGAR sus IpcHandler, que es lo que desregistra sus targets.
        //
        //  Destruir no desregistra —medido: ni tres segundos después—, así que
        //  sin esto el target quedaba secuestrado por el cadáver: el plugin
        //  recreado registraba en vano («another handler is registered») y
        //  contestaba «Function not found» desde el muerto. Se buscan entre
        //  los hijos declarados los que tengan target y enabled, que son los
        //  K4.Ipc. `Component.onDestruction` dentro del propio Ipc habría sido
        //  más limpio, pero a un IpcHandler no se le puede adjuntar.
        const hijos = obj.services || []
        for (let i = 0; i < hijos.length; ++i) {
            const h = hijos[i]
            if (h && ("target" in h) && ("enabled" in h)) {
                try { h.enabled = false } catch (e) { }
            }
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
    //  Recargar un plugin VIVO: destruirlo y volver a crearlo del disco.
    //
    //  Es la herramienta de desarrollo: editas el QML de tu plugin, lanzas
    //  `k4 pluginReload <id>` y ves el cambio sin reiniciar la barra. Vale
    //  igual para los de casa que para los de fuera.
    //
    //  Si la versión nueva no compila, el plugin queda como roto —con su error
    //  y su reintentar en Ajustes— pero la barra sigue: es exactamente el
    //  mismo camino que un fallo en el arranque. Lo que había ya se destruyó y
    //  no se finge lo contrario.
    //  Recargar un plugin VIVO, del disco, sin reiniciar la barra.
    //
    //  Es la herramienta de desarrollo: editas tu plugin, `k4 pluginReload
    //  <id>`, y ves el cambio. Vale para los de casa y para los de fuera.
    //
    //  Si la versión nueva no compila, el plugin queda como roto —con su error
    //  y su reintentar en Ajustes— y la barra sigue: el mismo camino que un
    //  fallo de arranque. Lo que había ya se destruyó y no se finge otra cosa.
    function recargar(id) {
        if (!estaHabilitado(id))
            return
        const m = metadata(id)
        if (!m || m.cargable === false)
            return
        if (_porId[id])
            _destruir(id)
        _publicar()
        //  Y la creación DESPUÉS, en dos tiempos y por dos motivos distintos:
        //
        //  1. `destroy()` es diferido —el objeto muere cuando el control
        //     vuelve al bucle de eventos— y crear en la misma pasada dejaba el
        //     IPC viejo aún registrado: el nuevo se descartaba con «another
        //     handler is registered» y el plugin quedaba vivo pero SORDO.
        //  2. Hay que pedirle a plugins.py una carpeta nueva. Ponerle `?r1` a
        //     la entrada recarga la entrada y solo la entrada: los hermanos
        //     —la vista, que es justo lo que el autor acaba de editar— se
        //     resuelven contra la misma carpeta y salen de la caché. Se veía
        //     recrear el plugin... con el contenido de antes.
        _pendienteRecarga = id
        procesoRecarga.running = true
    }

    property string _pendienteRecarga: ""

    property var procesoRecarga: Process {
        command: ["python3", Quickshell.shellPath("tools/plugins.py"),
                  "--recargar", manager._pendienteRecarga]
        stdout: StdioCollector {
            onStreamFinished: {
                const id = manager._pendienteRecarga
                const ruta = text.trim()
                manager._pendienteRecarga = ""
                if (!id || !ruta)
                    return
                const m = manager.metadata(id)
                if (!m || !manager.estaHabilitado(id))
                    return
                manager.limpiarError(id)
                manager._crear(Object.assign({}, m, { entry: ruta,
                                                      _recarga: true }))
                manager._repartir()
                manager._publicar()
            }
        }
    }

    //  Reintentar es recargar uno que no llegó a existir. Mismo camino: hace
    //  falta la carpeta nueva igual, porque lo que el autor acaba de arreglar
    //  puede ser la vista y no la entrada.
    function reintentar(id) {
        if (_porId[id] || !estaHabilitado(id))
            return
        recargar(id)
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

    //  Las filas del grupo «Plugins» de Ajustes. Para uno de fuera, la
    //  descripción enseña QUÉ es y QUÉ permisos pide antes del interruptor —
    //  eso es el consentimiento—; para uno con error, el motivo en rojo y la
    //  fila entera como botón de reintentar.
    readonly property var opcionesAjustes: catalogo
        .filter(function (m) { return m.configurable !== false })
        .map(function (m) {
            const error = errores[m.id] || ""
            let desc = "Activar o desactivar este plugin"
            if (m.externo) {
                desc = m.description || "Plugin de usuario"
                if (m.permisos && m.permisos.length > 0)
                    desc += "  ·  pide: " + m.permisos.join(", ")
            }
            if (m.cargable === false)
                desc = m.motivo || "no cargable"
            else if (error.length > 0)
                desc = error
            return { id: "plugin_" + m.id,
                     pluginId: m.id,
                     nombre: m.title + (m.externo ? "  ·  " + (m.version || "") : ""),
                     desc: desc,
                     error: m.cargable === false ? "fijo"
                          : (error.length > 0 ? "recargable" : ""),
                     glifo: m.externo ? 0xF0431 : 0xF06A5 }   // md-puzzle · md-power_plug
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
        //  Y con el estado en la mano, los plugins — si el catálogo ya llegó.
        //  Arrancar desde aquí y no desde shell.qml evita la carrera: el
        //  estado espera al mkdir y el catálogo al listador, y crear antes de
        //  tener los dos instanciaría plugins apagados o se perdería los de
        //  usuario.
        arrancar()
    }

    //  El catálogo lo emite `tools/plugins.py --listar`: los del repo más los
    //  de ~/.config/k4/plugins, ya validados y con su veredicto. La validación
    //  vive en UN sitio —python— y aquí solo se consume; un manifiesto roto
    //  llega como `cargable: false` con su motivo, nunca como una barra que no
    //  arranca.
    property bool catalogoListo: false

    function recibirCatalogo(bruto) {
        try {
            const d = JSON.parse(bruto)
            if (d.plugins && Array.isArray(d.plugins) && d.plugins.length > 0)
                catalogo = d.plugins.map(function (m) {
                    return Object.assign({}, m, {
                        enabled: m.enabledByDefault !== false
                    })
                })
        } catch (e) {
            // Se conserva el catálogo de emergencia embebido.
        }
        catalogoListo = true
        if (listo)
            _sincronizar()
        else
            arrancar()
    }

    //  Releer el catálogo con la barra en marcha: lo que hace que instalar o
    //  quitar un plugin desde el terminal se note sin reiniciar.
    function releerCatalogo() {
        listador.running = false
        listador.running = true
    }

    //  Casar lo que hay vivo con lo que dice el catálogo nuevo.
    //
    //  Solo actúa sobre las diferencias: un plugin que desapareció del disco
    //  se destruye, uno nuevo y habilitado se crea. A los que siguen igual no
    //  se les toca — releer el catálogo no puede costar un parpadeo a los
    //  veinte plugins que no han cambiado.
    function _sincronizar() {
        const vistos = {}
        let cambios = false
        for (let i = 0; i < catalogo.length; ++i) {
            const m = catalogo[i]
            vistos[m.id] = true
            if (m.cargable === false) {
                if (_porId[m.id]) { _destruir(m.id); cambios = true }
                registrarError(m.id, m.motivo || "no cargable")
                continue
            }
            if (estaHabilitado(m.id) && !_porId[m.id]) {
                if (_crear(m))
                    cambios = true
            }
        }
        //  Y el que ya no está en el catálogo: se lo llevaron del disco.
        const ids = Object.keys(_porId)
        for (let j = 0; j < ids.length; ++j) {
            if (!vistos[ids[j]]) {
                _destruir(ids[j])
                limpiarError(ids[j])
                cambios = true
            }
        }
        if (cambios) {
            _repartir()
            _publicar()
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

    Process {
        id: listador
        command: ["python3", Quickshell.shellPath("tools/plugins.py"),
                  "--listar"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: manager.recibirCatalogo(String(this.text))
        }
        //  Si python falla, el catálogo de emergencia embebido sigue ahí: la
        //  barra arranca con los de casa y sin los de usuario.
        onExited: function (codigo) {
            if (codigo !== 0 && !manager.catalogoListo)
                manager.recibirCatalogo("")
        }
    }

    Process {
        command: ["mkdir", "-p", Quickshell.env("HOME") + "/.local/state/k4"]
        running: true
        onExited: manager.cargar()
    }
}
