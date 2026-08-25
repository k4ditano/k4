pragma Singleton

// Registro y estado persistente de los plugins.
//
// `active` sigue siendo una decisión momentánea del host —quién ocupa la
// island—; `habilitado` es la decisión del usuario y sobrevive a los reinicios.
// Mantenerlas separadas evita que cerrar un plugin lo desactive para siempre.

import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import "../core"

Singleton {
    id: manager

    readonly property string rutaEstado:
        (Quickshell.env("HOME") || "") + "/.local/state/k4/plugins.json"

    //  Dos redes de seguridad, y las dos existen por lo mismo: actualizar la
    //  barra no puede costarte los plugins que tenías puestos.
    //
    //   · `rutaCopia` es un duplicado del último estado que se pudo leer. Si
    //     `plugins.json` aparece truncado —un corte a media escritura, el
    //     disco lleno— sin esto se cae a los valores de fábrica, y los plugins
    //     de usuario vienen de fábrica APAGADOS: se encuentra uno la barra sin
    //     nada y encima el siguiente guardado deja esa pérdida escrita.
    //
    //   · `rutaCache` es la última lista buena de `tools/plugins.py --list`.
    //     El catálogo lo emite ese guión, y un `git pull` lo reemplaza en
    //     caliente: si la llamada falla una sola vez —fichero a medio escribir,
    //     una dependencia nueva— antes se arrancaba con el catálogo de
    //     emergencia embebido, que solo trae los de casa. Los tuyos
    //     desaparecían de la lista y se descargaban de memoria.
    readonly property string rutaCopia:
        (Quickshell.env("HOME") || "") + "/.local/state/k4/plugins.json.bak"
    readonly property string rutaCache:
        (Quickshell.env("HOME") || "") + "/.local/state/k4/catalogo.json"
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

    //  ── lo que un plugin necesita para tener sentido ──────────────
    //
    //  Hay módulos que solo existen si existe otra cosa: la terminal de la
    //  isla no es «peor» sin k4term, es que no hay nada que enseñar. En vez de
    //  dejarlos a medio gas —una tecla que no hace nada, una sección de
    //  ajustes de algo que no está— se declara la dependencia en el catálogo
    //  (`requiere`) y aquí se comprueba.
    //
    //  Se comprueba TARDE a propósito: qué terminal hay instalada lo averigua
    //  `Consola` con un proceso al arrancar, así que al crear los plugins
    //  todavía no se sabe. Se crean todos y, cuando la respuesta llega, se
    //  destruye lo que no puede ser.
    function requisitoCumplido(m) {
        if (!m || !m.requiere)
            return true
        if (m.requiere === "k4term")
            return Consola.esNuestra
        if (m.requiere === "k4term-isla")
            return Consola.hayIsla
        return true
    }

    function motivoDelRequisito(m) {
        return m && m.requiere === "k4term-isla"
            ? Idioma.t("necesita k4term con su sesión de isla")
            : Idioma.t("necesita k4term instalado")
    }

    //  Cuando `Consola` termina de mirar qué hay, se revisa a quién le falta
    //  su dependencia. Vale para las dos direcciones: si alguien instala
    //  k4term y recarga la barra, el módulo aparece solo.
    property Connections vigilaRequisitos: Connections {
        target: Consola
        function onBinarioChanged() { manager.revisarRequisitos() }
        function onHayIslaChanged() { manager.revisarRequisitos() }
    }

    function revisarRequisitos() {
        if (!listo)
            return
        for (let i = 0; i < catalogo.length; ++i) {
            const m = catalogo[i]
            if (!m.requiere)
                continue
            const puede = requisitoCumplido(m)
            if (!puede && _porId[m.id]) {
                _destruir(m.id)
                _publicar()
            } else if (puede && !_porId[m.id] && estaHabilitado(m.id) && m.cargable !== false) {
                if (_crear(m)) {
                    _repartir()
                    _publicar()
                }
            }
        }
    }

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

        //  Y una revisión al terminar: si `Consola` ya había contestado antes
        //  de que existiera un solo plugin —que es lo normal, tarda menos que
        //  el listado del catálogo— su aviso no encontró a nadie a quien
        //  destruir. Sin esto, el módulo que necesita k4term se creaba igual.
        revisarRequisitos()
    }

    //  La carpeta de un plugin, contada desde la raíz de k4. Son los mismos
    //  tres casos que resuelve la `url` de `_crear`, dichos en ruta en vez de
    //  en url — y por eso viven pegadas: si alguien toca una, toca la otra.
    //
    //  `externos/` es un enlace a ~/.config/k4/plugins que mantiene
    //  tools/plugins.py; leer a través de él va bien y deja una sola forma de
    //  nombrar las cosas.
    function relDeCarpeta(m, ruta) {
        if (m._recarga)
            return String(ruta).replace(/\/[^/]*$/, "")
        if (ruta.indexOf("/") === 0)
            return "externos/" + m.id
        return "plugins/" + String(ruta).replace(/\/[^/]*$/, "")
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
            //  Y su propia carpeta, que hasta ahora un plugin no tenía forma
            //  de saber. `K4.Paths.raiz` es la de k4, no la suya, así que un
            //  plugin de fuera no podía construir la ruta de un guion propio ni
            //  de un asset para pasárselo a un proceso — comprobado: ninguno de
            //  los externos ejecuta nada suyo, y sospecho que es por esto.
            //  Se saca de `Quickshell.shellPath` y NO de la `url` de arriba:
            //  lo que devuelve `Qt.resolvedUrl` aquí dentro es un `qs:@/qs/…`,
            //  el esquema interno de Quickshell, y eso a un `Process` no le
            //  sirve de nada. Se vio porque el guion del plugin no corría y el
            //  plugin decía vivir en «qs:@/qs/externos/…».
            obj = comp.createObject(null, {
                habilitado: true,
                carpeta: Quickshell.shellPath(relDeCarpeta(m, ruta))
            })
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

        //  Y su tinte y su colocación: una barra teñida o desplazada por un
        //  plugin apagado no tiene ya quién la devuelva.
        Theme.destintar(id)
        Island.soltar(id)

        //  Y sus indicadores, por la misma razón. Esto solo se hacía al
        //  APAGAR un plugin, así que recargarlo dejaba en la píldora un
        //  indicador huérfano: con el número congelado en el del momento de
        //  recargar, sin nadie que lo actualice ni lo quite, y llamando al
        //  pulsarlo a un objeto que ya no existe. Va aquí, que es el único
        //  sitio por el que pasan las tres formas de morir —apagado, recarga
        //  y desaparecer del catálogo—, y no en una de ellas.
        Indicadores.quitarDe(id)

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
                  "--reload", manager._pendienteRecarga]
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
        //  Los indicadores los barre `_destruir`, por donde pasa apagar
        //  también. Estaba aquí y solo cubría este camino.
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

    //  El icono de un plugin por su id, en los dos campos que entiende
    //  `K4.IconoPlugin`: su imagen si trae una, su códice si no.
    //
    //  Existe porque el lanzador enseñaba los aportes de los plugins SIN
    //  icono. La fila esperaba un nombre de icono del escritorio —lo que
    //  traen las aplicaciones del sistema— y lo que un plugin declara es otra
    //  cosa: un códice de la Nerd Font o un fichero suyo. Ni encajaba ni
    //  fallaba: salía el hueco. Y un hueco entre filas que sí tienen icono se
    //  lee como «esto está a medias», que era justo lo contrario de lo que
    //  pasaba.
    function iconoDe(id) {
        for (let i = 0; i < catalogo.length; ++i) {
            const m = catalogo[i]
            if (m.id !== id)
                continue
            return { imagen: m.iconoFichero ? "file://" + m.iconoFichero : "",
                     glifo: m.icono ? parseInt(m.icono, 16)
                          : (m.externo ? 0xF0431 : 0xF06A5) }
        }
        return { imagen: "", glifo: 0xF06A5 }
    }

    //  Las filas del grupo «Plugins» de Ajustes. Para uno de fuera, la
    //  descripción enseña QUÉ es y QUÉ permisos pide antes del interruptor —
    //  eso es el consentimiento—; para uno con error, el motivo en rojo y la
    //  fila entera como botón de reintentar.
    readonly property var opcionesAjustes: catalogo
        .filter(function (m) { return m.configurable !== false })
        .map(function (m) {
            const error = errores[m.id] || ""
            let desc = Idioma.t("Activar o desactivar este plugin")
            if (m.externo) {
                desc = m.description || "Plugin de usuario"
                if (m.permisos && m.permisos.length > 0)
                    desc += "  ·  pide: " + m.permisos.join(", ")
            }
            const sinRequisito = !requisitoCumplido(m)
            if (m.cargable === false)
                //  `porque()` y no el motivo pelado: el guion devuelve un
                //  código y esta línea la lee el usuario en su idioma.
                desc = Idioma.porque(m.motivo || "no-cargable", m.detalle)
            else if (sinRequisito)
                desc = motivoDelRequisito(m)
            else if (error.length > 0)
                desc = error
            return { id: "plugin_" + m.id,
                     pluginId: m.id,
                     nombre: Idioma.t(m.title || m.id)
                         + (m.externo ? "  ·  " + (m.version || "") : ""),
                     desc: desc,
                     error: (m.cargable === false || sinRequisito) ? "fijo"
                          : (error.length > 0 ? "recargable" : ""),
                     //  Su icono si lo declara, y si no el genérico: pieza de
                     //  puzle para los de fuera, enchufe para los de casa. Un
                     //  plugin puede traer su propia imagen en vez de un
                     //  códice; van en campos distintos para que la vista no
                     //  tenga que adivinar de qué clase es.
                     imagen: m.iconoFichero ? "file://" + m.iconoFichero : "",
                     glifo: m.icono ? parseInt(m.icono, 16)
                          : (m.externo ? 0xF0431 : 0xF06A5) }
        })

    //  Las aplicaciones: lo que sale en el centro de aplicaciones y en los
    //  accesos directos. Se declara en el catálogo o en el manifiesto
    //  (`aplicacion: true`), no en el código, para que se sepa qué es antes
    //  de cargar nada — y para que un plugin apagado siga saliendo, en gris,
    //  en vez de desaparecer sin explicación.
    readonly property var aplicaciones: catalogo
        .filter(function (m) { return m.aplicacion === true })
        .map(function (m) {
            return { id: m.id,
                     //  Los títulos del catálogo están escritos en el
                     //  idioma de origen. Esta lista alimenta tanto la portada
                     //  como sus accesos directos, así que se traducen antes
                     //  de publicarla y reaccionan al cambio de idioma.
                     nombre: Idioma.t(m.title || m.id),
                     imagen: m.iconoFichero ? "file://" + m.iconoFichero : "",
                     glifo: m.icono ? parseInt(m.icono, 16) : 0xF0431,
                     externo: m.externo === true,
                     habilitado: estaHabilitado(m.id),
                     disponible: m.cargable !== false
                                 && !(errores[m.id] || "").length }
        })

    //  Abrir una por su id. Aquí y no en la vista: quien tiene las instancias
    //  es este gestor, y una aplicación apagada no se abre —se dice.
    function abrirAplicacion(id) {
        const p = _porId[id]
        if (!p)
            return false
        p.abrir()
        return true
    }

    function valorAjuste(id) {
        return estaHabilitado(String(id).replace(/^plugin_/, ""))
    }

    function alternarAjuste(id) {
        alternar(String(id).replace(/^plugin_/, ""))
    }

    //  ¿Trae este texto un estado que se pueda usar? Devuelve el mapa o null,
    //  que no es lo mismo que un mapa vacío: vacío es «no tienes nada puesto»
    //  y null es «no me he enterado», y confundirlos es justo lo que apagaba
    //  los plugins de todo el mundo.
    function _leerEstado(bruto) {
        if (!bruto || bruto.length === 0)
            return null
        try {
            const d = JSON.parse(bruto)
            if (d.habilitados && typeof d.habilitados === "object")
                return d.habilitados
        } catch (e) {
            //  Cae fuera: lo dirá quien llame.
        }
        return null
    }

    //  Se leyó de la copia porque el principal no servía. Se guarda para
    //  poder decirlo: recuperarse en silencio de una pérdida de datos es
    //  cómodo hoy y caro el día que la copia tampoco esté.
    property bool estadoRepuesto: false

    function cargar() {
        const bruto = estado.text()
        let mapa = _leerEstado(bruto)

        if (mapa === null) {
            //  El principal no sirve. Antes de dar por hecho que no había
            //  nada, mirar la copia — que es lo que distingue «primer
            //  arranque» de «se ha roto el fichero».
            const deCopia = _leerEstado(copiaEstado.text())
            if (deCopia !== null) {
                mapa = deCopia
                estadoRepuesto = true
                console.warn("k4: plugins.json no se pudo leer; repuesto de "
                             + manager.rutaCopia)
            }
        }

        if (mapa !== null) {
            habilitados = mapa
            //  Que la copia exista desde el primer arranque y no desde el
            //  primer interruptor que se toque: si solo se escribiera al
            //  guardar, la red no estaría puesta justo el día que hace falta.
            //  Y si se ha leído DE la copia, se repara el principal con ella.
            const bueno = JSON.stringify({ habilitados: mapa }, null, 1)
            if (estadoRepuesto)
                estado.setText(bueno)
            else if (copiaEstado.text() !== bueno)
                copiaEstado.setText(bueno)
        }

        cargado = true
        //  Y con el estado en la mano, los plugins — si el catálogo ya llegó.
        //  Arrancar desde aquí y no desde shell.qml evita la carrera: el
        //  estado espera al mkdir y el catálogo al listador, y crear antes de
        //  tener los dos instanciaría plugins apagados o se perdería los de
        //  usuario.
        arrancar()
    }

    //  El catálogo lo emite `tools/plugins.py --list`: los del repo más los
    //  de ~/.config/k4/plugins, ya validados y con su veredicto. La validación
    //  vive en UN sitio —python— y aquí solo se consume; un manifiesto roto
    //  llega como `cargable: false` con su motivo, nunca como una barra que no
    //  arranca.
    property bool catalogoListo: false

    //  De dónde salió lo que se está enseñando. Vacío es «del guión, como
    //  siempre»; con algo dentro, la tienda lo dice — una lista que puede
    //  estar vieja tiene que ir con la etiqueta puesta.
    property string catalogoDe: ""

    function _aplicarCatalogo(bruto) {
        try {
            const d = JSON.parse(bruto)
            if (d.plugins && Array.isArray(d.plugins) && d.plugins.length > 0) {
                catalogo = d.plugins.map(function (m) {
                    return Object.assign({}, m, {
                        enabled: m.enabledByDefault !== false
                    })
                })
                return true
            }
        } catch (e) {
            //  Lo resuelve quien llama.
        }
        return false
    }

    function recibirCatalogo(bruto) {
        if (_aplicarCatalogo(bruto)) {
            catalogoDe = ""
            _intentosLista = 0
            //  Guardar la última lista buena. Es la que se usará el día que
            //  el guión no conteste, y sin ella ese día la barra arranca sin
            //  los plugins de usuario.
            if (cacheCatalogo.text() !== bruto)
                cacheCatalogo.setText(bruto)
        } else if (catalogo.length === 0 || !catalogoListo) {
            //  No se ha entendido. Antes de caer al catálogo de emergencia
            //  —que solo trae los de casa— probar con la última lista buena:
            //  los plugins siguen en el disco, lo que ha fallado es quien los
            //  cuenta.
            if (_aplicarCatalogo(cacheCatalogo.text())) {
                catalogoDe = "cache"
                console.warn("k4: no se ha podido listar los plugins; se usa "
                             + manager.rutaCache)
            }
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
        //  Un repaso a mano vuelve a dar oportunidades: si no, tras dos
        //  fallos el reintento no se arma nunca más y pulsar «refrescar» no
        //  haría nada.
        _intentosLista = 0
        listador.running = false
        listador.running = true
    }

    //  Y que se note SOLO: la carpeta de plugins del usuario se vigila con
    //  inotify (vía FolderListModel, sin un solo proceso) y aparecer o
    //  desaparecer una carpeta relee el catálogo. Instalar deja de exigir
    //  saberse el `k4 pluginRefresh` — copias, y a los dos segundos está.
    property var _vigiaCarpeta: FolderListModel {
        folder: "file://" + Quickshell.env("HOME") + "/.config/k4/plugins"
        showDirs: true
        showFiles: false
        showDotAndDotDot: false
        //  El primer conteo es la carga inicial, no un cambio: el arranque
        //  ya trae su propio listado.
        onCountChanged: if (manager.listo) manager._relectura.restart()
    }

    //  El respiro: `git clone` crea la carpeta ANTES que sus ficheros, y
    //  validar a medio clonar daría un «roto» falso que se arregla solo.
    property var _relectura: Timer {
        interval: 1200
        onTriggered: manager.releerCatalogo()
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
        const texto = JSON.stringify({ habilitados: habilitados }, null, 1)
        estado.setText(texto)
        //  Y el duplicado. Cuesta un fichero de dos líneas y es lo que
        //  convierte «se me han apagado todos los plugins» en un aviso en el
        //  log. Si el principal se rompe, esto es lo que queda.
        copiaEstado.setText(texto)
        estadoRepuesto = false
    }

    FileView {
        id: estado
        path: manager.rutaEstado
        blockLoading: true
        //  Escribir a un temporal y renombrar. Sin esto, un corte a mitad de
        //  `setText` deja el JSON cortado por la mitad, que es exactamente el
        //  fichero ilegible del que hay que defenderse arriba.
        atomicWrites: true
    }

    FileView {
        id: copiaEstado
        path: manager.rutaCopia
        blockLoading: true
        atomicWrites: true
    }

    Process {
        id: listador
        command: ["python3", Quickshell.shellPath("tools/plugins.py"),
                  "--list"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: manager.recibirCatalogo(String(this.text))
        }
        //  Si python falla se vuelve a intentar, y solo después se tira de la
        //  última lista buena. El caso que se está cubriendo es actualizar la
        //  barra: `git pull` reemplaza `tools/plugins.py` mientras la barra
        //  corre, así que un fallo aquí es muchas veces cosa de un segundo.
        onExited: function (codigo) {
            if (codigo === 0)
                return
            if (manager._intentosLista < 2) {
                manager._intentosLista += 1
                reintentoLista.interval = 3000 * manager._intentosLista
                reintentoLista.restart()
                return
            }
            if (!manager.catalogoListo)
                manager.recibirCatalogo("")
        }
    }

    property int _intentosLista: 0

    Timer {
        id: reintentoLista
        onTriggered: {
            listador.running = false
            listador.running = true
        }
    }

    FileView {
        id: cacheCatalogo
        path: manager.rutaCache
        blockLoading: true
        atomicWrites: true
    }

    //  ── la tienda ────────────────────────────────────────────────────
    //
    //  Buscar, examinar, instalar, actualizar y quitar, todo contra el MISMO
    //  `tools/plugins.py` que se usa desde la terminal. No hay un camino
    //  «de la barra» y otro «de consola»: serían dos validaciones distintas y
    //  la menos usada acabaría siendo la que tiene los agujeros.
    //
    //  Una obra cada vez. Instalar y quitar tocan el disco, y dos a la vez
    //  sobre el mismo plugin es una carrera que no hace falta ganar.

    signal registroListo(var entradas, var descartadas)
    signal examenListo(var d)
    signal obraHecha(string que, string id, bool bien, string motivo)
    signal obraFallo(string que, string motivo)

    property bool ocupado: false
    property string ocupadaEn: ""

    function buscarEnRegistro() {
        return _obrar("buscar", "", ["--search", "--json"])
    }

    //  Mirar sin instalar. Devuelve, entre otras cosas, el commit que ha
    //  visto — y ese es el que hay que pasarle luego a `instalarDesde`, para
    //  que se instale exactamente lo que se enseñó en el diálogo.
    function examinar(repo, carpeta, commit) {
        return _obrar("examinar", "", ["--examine", repo, "--json"]
                      .concat(carpeta ? ["--folder", carpeta] : [])
                      .concat(commit ? ["--commit", commit] : []))
    }

    function instalarDesde(repo, carpeta, commit, id) {
        return _obrar("instalar", id || "",
                      ["--install", repo, "--json", "--yes"]
                      .concat(carpeta ? ["--folder", carpeta] : [])
                      .concat(commit ? ["--commit", commit] : []))
    }

    function actualizarPlugin(id, commit) {
        return _obrar("actualizar", id,
                      ["--update", id, "--json", "--yes"]
                      .concat(commit ? ["--commit", commit] : []))
    }

    function quitarPlugin(id, conEstado) {
        return _obrar("quitar", id, ["--remove", id, "--json", "--yes"]
                      .concat(conEstado ? ["--with-state"] : []))
    }

    function comprobarNovedades() {
        return _obrar("comprobar", "", ["--check", "--json"])
    }

    property var _obra: ({ que: "", id: "", args: [] })
    property var _cola: []
    property string _queja: ""

    //  Se ENCOLA, no se descarta. Descartar parecía razonable —una obra cada
    //  vez— hasta que se vio en pantalla: abrir la tienda lanza la comprobación
    //  de novedades, y la búsqueda en el registro que viene medio segundo
    //  después se perdía. La pestaña «Descubrir» se quedaba vacía para siempre,
    //  sin error ni rueda: no había fallado nada, es que nadie la había pedido.
    //
    //  Una misma clase de obra no se repite en la cola: pulsar «refrescar» tres
    //  veces son tres iguales, y con la primera basta.
    function _obrar(que, id, args) {
        const tarea = { que: que, id: id, args: args }
        if (ocupado) {
            for (let i = 0; i < _cola.length; ++i)
                if (_cola[i].que === que && _cola[i].id === id)
                    return true
            _cola = _cola.concat([tarea])
            return true
        }
        _arrancarObra(tarea)
        return true
    }

    function _arrancarObra(tarea) {
        _queja = ""
        _obra = tarea
        ocupado = true
        ocupadaEn = tarea.id
        tienda.running = true
    }

    function _siguienteObra() {
        if (ocupado || _cola.length === 0)
            return
        const t = _cola[0]
        _cola = _cola.slice(1)
        _arrancarObra(t)
    }

    function _recibirTienda(texto) {
        //  El guion escribe una línea de JSON por suceso; la última es el
        //  veredicto. Se busca hacia atrás porque delante puede haber avisos.
        const lineas = String(texto || "").trim().split("\n")
        for (let i = lineas.length - 1; i >= 0; --i) {
            const l = lineas[i].trim()
            if (!l.startsWith("{"))
                continue
            try {
                return JSON.parse(l)
            } catch (e) {
                //  Una línea que empieza por `{` y no es JSON: se sigue
                //  mirando hacia atrás en vez de darlo todo por perdido.
            }
        }
        return null
    }

    Process {
        id: tienda
        command: ["python3", Quickshell.shellPath("tools/plugins.py")]
                 .concat(manager._obra.args || [])
        stdout: StdioCollector {
            onStreamFinished: manager._salidaTienda = String(this.text)
        }
        stderr: StdioCollector {
            onStreamFinished: manager._queja = String(this.text).trim()
        }
        onExited: function (codigo) {
            const que = manager._obra.que
            const id = manager._obra.id
            const d = manager._recibirTienda(manager._salidaTienda)
            manager._salidaTienda = ""
            manager.ocupado = false
            manager.ocupadaEn = ""
            //  Lo siguiente de la cola arranca pase lo que pase con esta: que
            //  una falle no puede dejar plantadas a las que venían detrás.
            Qt.callLater(manager._siguienteObra)

            //  Un guion que peta sin decir nada deja al usuario mirando una
            //  rueda para siempre. Si no hay veredicto, el motivo es lo que
            //  haya escrito en stderr, y si tampoco hay, al menos el código.
            const bien = codigo === 0 && d && d.ok
            const motivo = (d && d.motivo)
                ? Idioma.porque(d.motivo, d.detalle)
                : (manager._queja
                   || Idioma.f("El guion terminó con el código %1", codigo))

            if (que === "buscar") {
                if (bien)
                    manager.registroListo(d.plugins || [], d.descartadas || [])
                else
                    manager.obraFallo(que, motivo)
                return
            }
            if (que === "examinar") {
                if (bien)
                    manager.examenListo(d)
                else
                    manager.obraFallo(que, motivo)
                return
            }
            if (que === "comprobar") {
                if (bien)
                    manager.novedades = d.plugins || []
                else
                    manager.obraFallo(que, motivo)
                return
            }
            //  Instalar, actualizar y quitar cambian el disco: el catálogo que
            //  tiene la barra en memoria ya no es el de fuera.
            if (bien)
                manager.releerCatalogo()
            manager.obraHecha(que, id, bien, bien ? "" : motivo)
        }
    }

    property string _salidaTienda: ""

    //  Lo que dice `--check`: por id, si hay algo más nuevo publicado.
    property var novedades: []

    function novedadDe(id) {
        for (let i = 0; i < novedades.length; ++i)
            if (novedades[i].id === id)
                return novedades[i]
        return null
    }

    Process {
        command: ["mkdir", "-p", Quickshell.env("HOME") + "/.local/state/k4"]
        running: true
        onExited: manager.cargar()
    }
}
