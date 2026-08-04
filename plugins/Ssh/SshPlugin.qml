//  Los servidores de uno, a dos golpes.
//
//  Escribes tres letras y entras. Nada más — pero con dos decisiones detrás
//  que conviene tener claras:
//
//  **Los hosts viven en `~/.ssh/config`, no en una base de datos nuestra.**
//  Es lo que hace que guardar aquí sirva también para `ssh` a pelo, `scp`,
//  `git`, `rsync` y cualquier cosa que hable ssh. Un vault propio sería más
//  fácil de escribir y te dejaría preso de k4.
//
//  **Contraseñas, ninguna.** Ni en claro ni cifradas por nosotros: se conecta
//  con claves y agente, que es como se hace. Si no tienes clave, esto te la
//  crea y te la manda al servidor — el resto lo lleva ssh, que para eso está.
//
//  Lo que sí es nuestro va en `~/.config/k4term/hosts.json`: lo que el fichero
//  de ssh no sabe decir —favoritos, cuándo entraste por última vez, etiquetas—
//  y que no tiene por qué ensuciar una configuración que leen otros programas.

import QtQuick
import K4 as K4
import "../../core"
import "../../services"

K4Plugin {
    id: self

    name: "ssh"
    title: Idioma.t("Servidores")
    //  Como el portapapeles: se pide a propósito, así que manda sobre lo que
    //  esté puesto.
    priority: 82
    active: abierto || cerrando
    viewLoaded: abierto
    grabKeyboard: abierto

    islandWidth: 760
    islandHeight: 460

    property bool abierto: false
    property bool cerrando: false
    property string busqueda: ""
    property int indice: 0

    //  Dos caras de la misma ventana: la lista para elegir y el formulario
    //  para configurar. Se cambia de una a otra sin cerrar nada, que abrir un
    //  diálogo encima de un diálogo es de las cosas que hacen que uno deje de
    //  usar algo.
    property string modo: "lista"
    property var borrador: ({})
    property int campo: 0

    //  Los campos, en el orden en que se rellenan. Los cuatro primeros van a
    //  `~/.ssh/config` —los entiende ssh y los aprovechan scp, git y todo lo
    //  demás—; los tres últimos son nuestros y viven en `hosts.json`.
    //  Los campos de la ficha. Es una lista calculada y no una constante por
    //  un motivo: la contraseña solo se ofrece si hay una terminal NUESTRA
    //  —la ventana o la de la isla—, porque el tecleo automático lo hace la
    //  terminal mirando su propio PTY y eso kitty o alacritty no lo hacen.
    //  Un campo que se rellena y luego no hace nada es peor que no tenerlo.
    readonly property bool puedeContrasena: Consola.esNuestra || Consola.hayIsla

    readonly property var campos: puedeContrasena ? camposTodos
        : camposTodos.filter(function (c) { return c.id !== "contrasena" })

    readonly property var camposTodos: [
        { id: "alias",      nombre: Idioma.t("Nombre"),     ayuda: Idioma.t("como lo vas a llamar"),          suyo: false },
        { id: "host",       nombre: Idioma.t("Máquina"),    ayuda: Idioma.t("dominio o IP"),                  suyo: false },
        { id: "usuario",    nombre: Idioma.t("Usuario"),    ayuda: Idioma.t("vacío = el tuyo"),               suyo: false },
        //  La contraseña no va ni al `ssh_config` ni a `hosts.json`: esos dos
        //  se abren y se copian sin pensar. Vive en `claves.json` con 600, y
        //  en la ficha se enseña con puntos salvo que pidas verla (ctrl+O).
        { id: "contrasena", nombre: Idioma.t("Contraseña"), ayuda: Idioma.t("si entra con contraseña en vez de con clave"), suyo: false, secreto: true },
        { id: "puerto",     nombre: Idioma.t("Puerto"),     ayuda: Idioma.t("vacío = 22"),                    suyo: false },
        { id: "clave",      nombre: Idioma.t("Clave"),      ayuda: Idioma.t("ruta de la privada, si no la de siempre"), suyo: false },
        { id: "salto",      nombre: Idioma.t("Salto"),      ayuda: Idioma.t("pasar por otro servidor (ProxyJump)"), suyo: false },
        { id: "etiquetas",  nombre: Idioma.t("Etiquetas"),  ayuda: Idioma.t("separadas por espacios, para buscar"), suyo: true },
        { id: "alConectar", nombre: Idioma.t("Al entrar"),  ayuda: Idioma.t("un mandato que se teclea al conectar"), suyo: true },
        { id: "tinte",      nombre: Idioma.t("Color"),      ayuda: Idioma.t("rojo, ámbar, verde, azul, morado — para saber dónde estás"), suyo: true },
        { id: "tuneles",    nombre: Idioma.t("Túneles"),    ayuda: Idioma.t("8080:localhost:80 · socks:1080 · R:9000:localhost:9000"), suyo: true }
    ]

    //  Si la contraseña se enseña o va con puntos. Se apaga al abrir la ficha
    //  y al cerrarla: que se quede encendida de la vez anterior es justo lo
    //  que no se espera.
    property bool verClave: false

    function editar(h) {
        verClave = false
        borrador = {
            original: h && !h.rapido ? h.alias : "",
            alias: h ? h.alias : "",
            host: h ? (h.host || h.alias) : "",
            usuario: h ? h.usuario : "",
            contrasena: h ? claveDe(h.alias) : "",
            puerto: h ? h.puerto : "",
            clave: h ? (h.clave || "") : "",
            salto: h ? (h.salto || "") : "",
            etiquetas: h && h.etiquetas ? h.etiquetas.join(" ") : "",
            alConectar: h && h.alConectar ? h.alConectar : "",
            tinte: h && h.tinte ? h.tinte : "",
            tuneles: h && h.tuneles ? h.tuneles : "",
            favorito: h ? h.favorito === true : false
        }
        campo = 0
        modo = "editar"
    }

    function editarActual() {
        const h = lista[indice]
        if (h)
            editar(h)
    }

    function nuevoDesdeBusqueda() {
        const d = comoDestino(busqueda)
        editar(d ? { alias: d.host, host: d.host, usuario: d.usuario,
                     puerto: d.puerto, rapido: true } : null)
    }

    function ponerCampo(id, valor) {
        const nuevo = Object.assign({}, borrador)
        nuevo[id] = String(valor)
        borrador = nuevo
    }

    function moverCampo(paso) {
        campo = Math.max(0, Math.min(campos.length - 1, campo + paso))
    }

    function cancelarEdicion() {
        modo = "lista"
        borrador = ({})
    }

    view: Component { SshView { plugin: self } }

    function abrir() {
        fSsh.reload()
        fExtras.reload()
        busqueda = ""
        indice = 0
        cerrando = false
        abierto = true
        claves.running = true
        //  `~/.ssh` con los permisos que ssh exige. Si lo crea por su cuenta
        //  quien escriba el fichero, sale con los de todo el mundo (755) y
        //  ssh se planta: para él, un directorio que otros pueden mirar no es
        //  sitio para claves. Comprobado — nos pasó al guardar el primero.
        permisos.running = true
    }

    property K4.Process permisos: K4.Process {
        command: ["sh", "-c", "mkdir -p ~/.ssh && chmod 700 ~/.ssh"]
        onTerminado: running = false
    }

    //  Y el fichero, solo para ti. No lleva secretos, pero dice a qué máquinas
    //  entras y con qué usuario, que tampoco es cosa de nadie.
    property K4.Process cerrarFichero: K4.Process {
        command: ["sh", "-c", "chmod 600 ~/.ssh/config 2>/dev/null"]
        onTerminado: running = false
    }

    function cerrar() {
        if (!abierto)
            return
        abierto = false
        cerrando = true
        salida.restart()
    }

    function alternar() { abierto ? cerrar() : abrir() }

    Timer {
        id: salida
        interval: 260
        onTriggered: self.cerrando = false
    }

    //  ── lo que dice ~/.ssh/config ─────────────────────────────────
    //
    //  Un analizador pequeño y a propósito tolerante: de las cincuenta
    //  opciones que admite ssh solo se leen las cinco que sirven para
    //  enseñar y conectar. Lo demás se respeta sin tocarlo — este fichero es
    //  del usuario, no nuestro.
    readonly property string rutaSsh: K4.Sistema.entorno("HOME") + "/.ssh/config"
    readonly property string rutaExtras: K4.Sistema.entorno("HOME") + "/.config/k4term/hosts.json"

    property var guardados: []
    property var extras: ({})

    property K4.Fichero fSsh: K4.Fichero {
        path: self.rutaSsh
        onLoaded: self.guardados = self.leerSsh()
        //  Sin fichero no hay nada que leer, y es lo normal la primera vez.
        onLoadFailed: self.guardados = []
    }

    property K4.Fichero fExtras: K4.Fichero {
        path: self.rutaExtras
        onLoaded: {
            try {
                self.extras = JSON.parse(fExtras.text() || "{}")
            } catch (e) {
                self.extras = ({})
            }
        }
        onLoadFailed: self.extras = ({})
    }

    //  ── las contraseñas ───────────────────────────────────────────
    //
    //  En su propio fichero y con 600, como en la ventana: `claves.json` no
    //  sale nunca de aquí, y ni el `ssh_config` ni `hosts.json` lo tocan. Van
    //  en claro, con el mismo trato que una clave privada sin frase — en este
    //  equipo no hay servicio de secretos que funcione, y el día que lo haya
    //  esto es lo único que cambia.
    readonly property string rutaClaves: K4.Sistema.entorno("HOME") + "/.config/k4term/claves.json"

    property var contrasenas: ({})

    property K4.Fichero fClaves: K4.Fichero {
        path: self.rutaClaves
        onLoaded: {
            try {
                self.contrasenas = JSON.parse(fClaves.text() || "{}")
            } catch (e) {
                self.contrasenas = ({})
            }
        }
        onLoadFailed: self.contrasenas = ({})
    }

    function claveDe(alias) {
        const c = contrasenas[String(alias || "")]
        return c ? String(c) : ""
    }

    //  Una contraseña vacía BORRA la que hubiera: es la única forma de
    //  quitarla desde la ficha.
    function guardarClave(alias, clave) {
        const nombre = String(alias || "")
        if (!nombre)
            return
        const nuevo = Object.assign({}, contrasenas)
        if (String(clave).length === 0)
            delete nuevo[nombre]
        else
            nuevo[nombre] = String(clave)
        contrasenas = nuevo
        fClaves.setText(JSON.stringify(contrasenas, null, 2) + "\n")
        cerrarClaves.running = true
    }

    //  El fichero recién escrito sale con los permisos de todo el mundo, y
    //  esto no es un fichero cualquiera.
    property K4.Process cerrarClaves: K4.Process {
        command: ["sh", "-c",
                  "chmod 700 ~/.config/k4term 2>/dev/null; " +
                  "chmod 600 ~/.config/k4term/claves.json 2>/dev/null"]
    }

    function leerSsh() {
        const texto = fSsh.text() || ""
        const lista = []
        let actual = null

        texto.split("\n").forEach(function (linea) {
            //  Los comentarios fuera, y la separación puede ser espacio o
            //  igual: `Port 22` y `Port=22` son lo mismo para ssh.
            const limpia = linea.replace(/#.*$/, "").trim()
            if (limpia.length === 0)
                return
            const corte = limpia.search(/[\s=]/)
            if (corte < 0)
                return
            const clave = limpia.slice(0, corte).toLowerCase()
            const valor = limpia.slice(corte).replace(/^[\s=]+/, "").trim()

            if (clave === "host") {
                //  Los patrones (`Host *`) son valores por defecto, no sitios
                //  a los que ir: no se enseñan.
                const nombres = valor.split(/\s+/)
                const primero = nombres.length > 0 ? nombres[0] : ""
                actual = null
                if (primero && primero.indexOf("*") < 0 && primero.indexOf("?") < 0) {
                    actual = { alias: primero, host: "", usuario: "", puerto: "",
                               clave: "", salto: "" }
                    lista.push(actual)
                }
                return
            }

            if (!actual)
                return
            if (clave === "hostname") actual.host = valor
            else if (clave === "user") actual.usuario = valor
            else if (clave === "port") actual.puerto = valor
            else if (clave === "identityfile") actual.clave = valor
            else if (clave === "proxyjump") actual.salto = valor
        })

        return lista
    }

    //  ── la lista que se ve ────────────────────────────────────────
    //
    //  Primero los favoritos, luego por cuándo entraste —lo de ayer suele ser
    //  lo de hoy— y al final por nombre. Ordenar por uso es lo que hace que
    //  con tres letras el primero sea casi siempre el bueno.
    function conExtras(h) {
        const e = extras[h.alias] || ({})
        return { alias: h.alias, host: h.host || h.alias, usuario: h.usuario,
                 puerto: h.puerto, clave: h.clave, salto: h.salto,
                 favorito: e.favorito === true,
                 ultimo: Number(e.ultimo) || 0,
                 etiquetas: e.etiquetas || [],
                 alConectar: e.alConectar || "",
                 tinte: e.tinte || "",
                 tuneles: e.tuneles || "",
                 rapido: false }
    }

    readonly property var lista: {
        const q = busqueda.trim().toLowerCase()
        const salida = []

        for (let i = 0; i < guardados.length; ++i) {
            //  Los alias de agentes no son un sitio más al que ir: son la
            //  puerta de atrás de uno que ya está en la lista. Se ven como una
            //  marca en el suyo, no como una fila aparte.
            if (esAliasAgentes(guardados[i].alias))
                continue
            const h = conExtras(guardados[i])
            h.agentes = tieneAgentes(h.alias)
            const paja = (h.alias + " " + h.host + " " + h.usuario + " "
                          + h.etiquetas.join(" ")).toLowerCase()
            if (q.length === 0 || paja.indexOf(q) >= 0)
                salida.push(h)
        }

        salida.sort(function (a, b) {
            if (a.favorito !== b.favorito)
                return a.favorito ? -1 : 1
            if (a.ultimo !== b.ultimo)
                return b.ultimo - a.ultimo
            return a.alias.localeCompare(b.alias)
        })

        //  Conexión al vuelo: si lo escrito parece un destino y no es ninguno
        //  de los guardados, se ofrece ir directamente. Es lo que uno hace la
        //  primera vez, antes de tener nada guardado.
        const destino = self.comoDestino(busqueda)
        if (destino) {
            const yaEsta = salida.some(function (h) {
                return h.alias === destino.host || h.host === destino.host
            })
            if (!yaEsta) {
                salida.unshift({ alias: destino.host, host: destino.host,
                                 usuario: destino.usuario, puerto: destino.puerto,
                                 clave: "", salto: "", favorito: false, ultimo: 0,
                                 etiquetas: [], rapido: true })
            }
        }

        return salida
    }

    readonly property int cuantos: lista.length

    //  ¿Esto que has escrito parece un sitio? `usuario@maquina:puerto`, con
    //  las dos primeras partes opcionales. Se pide un punto o dos letras y
    //  media para no ofrecer «conectar a p» mientras escribes.
    function comoDestino(texto) {
        const t = String(texto).trim()
        if (t.length < 3 || /\s/.test(t))
            return null
        const m = t.match(/^(?:([\w.\-]+)@)?([\w.\-]+)(?::(\d+))?$/)
        if (!m)
            return null
        return { usuario: m[1] || "", host: m[2], puerto: m[3] || "" }
    }

    onCuantosChanged: if (indice >= cuantos) indice = Math.max(0, cuantos - 1)

    function mover(paso) {
        if (cuantos === 0)
            return
        indice = Math.max(0, Math.min(cuantos - 1, indice + paso))
    }

    //  ── conectar ──────────────────────────────────────────────────
    //
    //  El mandato se compone igual para los dos sitios; lo único que cambia es
    //  dónde sale. En la isla va por `K4.Terminal`, que abre pestaña nueva —lo
    //  que quieres, para no pisar lo que tuvieras a medias.
    function mandato(h) {
        if (!h)
            return ""
        const partes = ["ssh"]
        if (h.puerto)
            partes.push("-p", h.puerto)
        //  Un host guardado se llama por su alias y ya está: lo demás lo pone
        //  el propio ssh leyendo su configuración, incluida la clave y el
        //  salto. Solo el destino al vuelo lleva usuario delante.
        partes.push(h.rapido && h.usuario ? h.usuario + "@" + h.host : h.alias)
        return partes.join(" ")
    }

    function conectar(h, enVentana) {
        let guion = mandato(h)
        if (!guion)
            return

        //  Lo que pediste que se corriera al entrar va detrás, en la misma
        //  línea: así entra por el mismo sitio y no hay que adivinar cuándo
        //  ha terminado de arrancar la sesión de allí.
        if (h.alConectar)
            guion += " -t " + JSON.stringify(String(h.alConectar))

        if (!h.rapido)
            apuntarVisita(h.alias)

        //  Los túneles, con la conexión: se levantan aquí y se caen cuando la
        //  terminal avise de que se salió.
        abrirTuneles(h)

        if (enVentana === true) {
            //  Por `Consola` y no a pelo: es quien sabe que wezterm y
            //  gnome-terminal no aceptan `-e` como las demás, y quien envuelve
            //  con uwsm para que la ventana no se muera con la barra. Estaba
            //  escrito a mano y las dos cosas fallaban.
            //  Y con la salida de emergencia de la casa detrás: una ventana
            //  que se cierra sola con el «connection refused» a medio leer no
            //  sirve de nada. Solo si falla — al salir de una sesión buena,
            //  cerrarse es lo que uno espera.
            K4.Sistema.lanzar(Consola.orden(guion + " || { " + Consola.cierre + " }"))
        } else {
            //  Que la terminal sepa que lo que viene es una conexión y pinte
            //  el camino mientras tanto.
            Consola.conectandoA(h.rapido && h.usuario
                                ? h.usuario + "@" + h.host : h.alias,
                                h.tinte || "",
                                h.rapido ? "" : claveDe(h.alias))
            K4.Terminal.ejecutar(guion)
        }

        cerrar()
    }

    function elegir(enVentana) { conectar(lista[indice], enVentana) }

    //  ── lo nuestro: favoritos y visitas ───────────────────────────
    function tocar(alias, cambio) {
        //  Copiar y no tocar por dentro: reasignar a una propiedad `var` el
        //  mismo objeto que ya tenía no avisa a nadie, y la lista se quedaría
        //  igual en pantalla.
        const nuevo = Object.assign({}, extras)
        nuevo[alias] = Object.assign({}, nuevo[alias] || ({}), cambio)
        extras = nuevo
        fExtras.setText(JSON.stringify(extras, null, 2) + "\n")
    }

    function apuntarVisita(alias) { tocar(alias, { ultimo: Date.now() }) }

    function favoritoActual() {
        const h = lista[indice]
        if (h && !h.rapido)
            tocar(h.alias, { favorito: !h.favorito })
    }

    //  ── guardar y borrar en ~/.ssh/config ─────────────────────────
    //
    //  Se escribe el bloque y se deja el resto del fichero intacto: ahí puede
    //  haber cosas de años que no son nuestras.
    //  Guardar lo del formulario. Es también EDITAR: si ese host ya estaba
    //  —o se le ha cambiado el nombre— su bloque viejo se va y se escribe el
    //  nuevo, para que no haya dos caminos que mantener.
    function guardarBorrador() {
        const b = borrador
        const alias = String(b.alias || b.host || "").trim()
        if (!alias || !String(b.host || "").trim())
            return false

        let texto = fSsh.text() || ""
        //  Fuera el bloque anterior: el suyo y, si se ha renombrado, el que
        //  tuviera el nombre nuevo.
        texto = sinBloque(texto, alias)
        if (b.original && b.original !== alias)
            texto = sinBloque(texto, b.original)

        if (texto.length > 0 && texto.slice(-1) !== "\n")
            texto += "\n"

        let bloque = "\nHost " + alias + "\n"
        bloque += "    HostName " + String(b.host).trim() + "\n"
        //  La huella de una máquina nueva se acepta sola; la que CAMBIA sigue
        //  parando la conexión. Igual que en la ventana, y por lo mismo: así
        //  no sale la pregunta y no hay que contestarla a la vista de nadie.
        bloque += "    StrictHostKeyChecking accept-new\n"
        const deSsh = [["User", b.usuario], ["Port", b.puerto],
                       ["IdentityFile", b.clave], ["ProxyJump", b.salto]]
        for (let i = 0; i < deSsh.length; ++i) {
            const valor = String(deSsh[i][1] || "").trim()
            if (valor)
                bloque += "    " + deSsh[i][0] + " " + valor + "\n"
        }

        fSsh.setText(texto + bloque)
        cerrarFichero.running = true
        relee.restart()

        //  Y lo nuestro, que ssh no sabe guardar.
        const etiquetas = String(b.etiquetas || "").trim()
        tocar(alias, {
            favorito: b.favorito === true,
            etiquetas: etiquetas ? etiquetas.split(/\s+/) : [],
            alConectar: String(b.alConectar || "").trim(),
            tinte: String(b.tinte || "").trim(),
            tuneles: String(b.tuneles || "").trim()
        })
        guardarClave(alias, String(b.contrasena || ""))
        if (b.original && b.original !== alias) {
            olvidarExtra(b.original)
            guardarClave(b.original, "")
        }

        modo = "lista"
        borrador = ({})
        busqueda = ""
        indice = 0
        return true
    }

    //  El fichero sin el bloque de ese host. «Host» y luego un separador: ni
    //  `HostName` ni `HostKeyAlias` empiezan bloque, y darlos por buenos deja
    //  líneas huérfanas en el fichero de otro.
    function sinBloque(texto, alias) {
        const lineas = String(texto).split("\n")
        const salida = []
        let dentro = false

        for (let i = 0; i < lineas.length; ++i) {
            const limpia = lineas[i].replace(/#.*$/, "").trim()
            if (/^host[\s=]/i.test(limpia)) {
                const nombres = limpia.slice(4).replace(/^[\s=]+/, "").split(/\s+/)
                dentro = nombres.length > 0 && nombres[0] === alias
            }
            if (!dentro)
                salida.push(lineas[i])
        }

        while (salida.length > 0 && salida[salida.length - 1].trim() === "")
            salida.pop()
        return salida.length > 0 ? salida.join("\n") + "\n" : ""
    }

    //  `text()` no ve lo que se acaba de escribir con `setText`: hay que
    //  recargar y dejar que `onLoaded` rehaga la lista. Leerlo ahí mismo la
    //  dejaba en cero con el fichero ya escrito.
    Timer {
        id: relee
        interval: 120
        onTriggered: self.fSsh.reload()
    }

    function olvidarExtra(alias) {
        const nuevo = Object.assign({}, extras)
        delete nuevo[alias]
        extras = nuevo
        fExtras.setText(JSON.stringify(extras, null, 2) + "\n")
    }

    //  Guardar lo escrito al vuelo no es escribirlo y ya: se abre el
    //  formulario con lo que se sabe y se completa el resto. Antes se guardaba
    //  a ciegas con el nombre de la máquina y no había forma de tocar nada
    //  más, que es justo lo que uno quiere hacer a continuación.
    function guardarActual() {
        const h = lista[indice]
        if (h)
            editar(h)
    }

    function borrarActual() {
        const h = lista[indice]
        if (!h || h.rapido)
            return

        fSsh.setText(sinBloque(fSsh.text() || "", h.alias))
        relee.restart()

        const nuevo = Object.assign({}, extras)
        delete nuevo[h.alias]
        extras = nuevo
        fExtras.setText(JSON.stringify(extras, null, 2) + "\n")
        //  Y su contraseña: guardar el secreto de una máquina a la que ya no
        //  vas es lo peor de los dos mundos.
        guardarClave(h.alias, "")

        indice = Math.max(0, Math.min(indice, cuantos - 2))
    }

    //  ── la clave, si no tienes ninguna ────────────────────────────
    //
    //  Sin clave, entrar pide contraseña cada vez. Se puede guardar —está el
    //  campo, y va a `claves.json` con 600— pero una clave es mejor: no viaja,
    //  no caduca y no hay que teclearla. Crear una y mandarla al servidor es
    //  el paso que lo arregla para siempre, y se hace EN LA
    //  TERMINAL a propósito: `ssh-keygen` pregunta por la frase de paso y
    //  `ssh-copy-id` por la contraseña del servidor, y eso lo tienes que
    //  teclear tú, no un diálogo nuestro.
    property int cuantasClaves: -1

    property K4.Process claves: K4.Process {
        command: ["sh", "-c", "ls -1 ~/.ssh/*.pub 2>/dev/null | wc -l"]
        onSalida: function (texto) { self.cuantasClaves = parseInt(texto.trim(), 10) || 0 }
        onTerminado: running = false
    }

    readonly property bool sinClaves: cuantasClaves === 0

    function crearClave() {
        const h = lista[indice]
        const destino = h ? (h.rapido && h.usuario ? h.usuario + "@" + h.host : h.alias) : ""
        const crear = "ssh-keygen -t ed25519 -C k4term"
        K4.Terminal.ejecutar(destino ? crear + " && ssh-copy-id " + destino : crear)
        cerrar()
    }

    //  ── la puerta de los agentes ──────────────────────────────────
    //
    //  Un agente que corre en la terminal ya tiene tu shell, así que puede
    //  lanzar `ssh` él solo; lo que no puede es teclear una contraseña. Darle
    //  la tuya sería darle TODO, así que se le da otra cosa: una clave propia
    //  (`~/.ssh/k4-agentes`), un alias propio (`casa-agentes`) y, en el
    //  servidor, lo que tú quieras dejarle en su `authorized_keys`. Se revoca
    //  borrando una línea allí, sin tocar nada tuyo.
    //
    //  Lo que hace falta hacer ALLÍ —mandar la clave, o quitarla— se corre en
    //  la terminal, a la vista: pide tu contraseña y toca su fichero, y esas
    //  dos cosas no se hacen a escondidas.
    readonly property string claveAgentes: K4.Sistema.entorno("HOME") + "/.ssh/k4-agentes"

    //  El sello de la clave, que es lo que permite quitarla del servidor sin
    //  adivinar: se busca esa marca en su `authorized_keys` y se borra la
    //  línea. TIENE que salir igual aquí y en la ventana —el mismo fichero,
    //  no `$HOSTNAME`, que en la sesión de la barra viene vacío y dejaba dos
    //  sellos distintos: el puesto por un lado no lo encontraba el otro.
    property string nombreEquipo: "k4"

    property K4.Fichero fEquipo: K4.Fichero {
        path: "/etc/hostname"
        onLoaded: {
            const t = String(fEquipo.text() || "").trim()
            if (t.length > 0)
                self.nombreEquipo = t
        }
    }

    readonly property string marcaAgentes: "k4-agentes@" + nombreEquipo

    function aliasAgentes(alias) { return String(alias || "") + "-agentes" }

    function esAliasAgentes(alias) {
        return String(alias || "").slice(-8) === "-agentes"
    }

    function tieneAgentes(alias) {
        const buscado = aliasAgentes(alias)
        for (let i = 0; i < guardados.length; ++i)
            if (guardados[i].alias === buscado)
                return true
        return false
    }

    function alternarAgentes() {
        const h = lista[indice]
        if (!h || h.rapido)
            return

        const marca = marcaAgentes
        let texto = fSsh.text() || ""

        if (tieneAgentes(h.alias)) {
            fSsh.setText(sinBloque(texto, aliasAgentes(h.alias)))
            cerrarFichero.running = true
            relee.restart()
            //  Y allí: fuera la línea de esa clave. Se busca por su marca, que
            //  para eso la lleva.
            K4.Terminal.ejecutar("ssh " + h.alias
                + " \"sed -i '/" + marca + "/d' ~/.ssh/authorized_keys\"")
            cerrar()
            return
        }

        texto = sinBloque(texto, aliasAgentes(h.alias))
        if (texto.length > 0 && texto.slice(-1) !== "\n")
            texto += "\n"

        let bloque = "\nHost " + aliasAgentes(h.alias) + "\n"
        bloque += "    HostName " + String(h.host || h.alias) + "\n"
        if (h.usuario)
            bloque += "    User " + h.usuario + "\n"
        if (h.puerto)
            bloque += "    Port " + h.puerto + "\n"
        bloque += "    IdentityFile " + claveAgentes + "\n"
        //  Sin `IdentitiesOnly` ssh ofrece también tus claves y el agente
        //  entraría como tú: justo lo que esta puerta viene a evitar.
        bloque += "    IdentitiesOnly yes\n"
        //  Y que no pregunte NADA: esta puerta es para lo que no tiene a nadie
        //  delante, así que una clave que no vale tiene que dar error al
        //  instante y no dejar al agente esperando un prompt que no ve.
        bloque += "    BatchMode yes\n"
        bloque += "    StrictHostKeyChecking accept-new\n"

        fSsh.setText(texto + bloque)
        cerrarFichero.running = true
        relee.restart()

        K4.Terminal.ejecutar(
            "[ -f " + claveAgentes + " ] || ssh-keygen -t ed25519 -N '' -C '"
            + marca + "' -f " + claveAgentes
            + "; ssh-copy-id -i " + claveAgentes + ".pub " + h.alias)
        cerrar()
    }

    //  ── los túneles ───────────────────────────────────────────────
    //
    //  Un túnel es otro `ssh` corriendo por su cuenta (`ssh -N`), así que vive
    //  fuera de la terminal: no ocupa pestaña, no se ve, y por eso mismo se
    //  olvida. La píldora es el sitio de la casa para lo que corre por detrás
    //  —ahí están los mandatos largos y los agentes—, así que ahí van: cada
    //  túnel el suyo, y pulsarlo lo mata.
    //
    //  Se levantan al conectar y se caen al salir. Podrían vivir solos, pero
    //  entonces habría que acordarse de apagarlos; atados a la sesión, hacen
    //  lo que uno espera sin pensarlo.
    property ListModel tuneles: ListModel {}

    //  `8080:localhost:80` (local), `R:9000:localhost:9000` (remoto),
    //  `socks:1080` o `D:1080` (SOCKS). Separados por espacios o comas.
    function leerTuneles(texto) {
        const salida = []
        String(texto || "").split(/[\s,]+/).forEach(function (trozo) {
            if (!trozo)
                return
            const bajo = trozo.toLowerCase()
            if (bajo.indexOf("socks:") === 0 || bajo.indexOf("d:") === 0) {
                const puerto = trozo.split(":").pop()
                if (puerto)
                    salida.push({ bandera: "-D", spec: puerto, mote: "socks " + puerto })
                return
            }
            if (bajo.indexOf("r:") === 0) {
                const spec = trozo.slice(2)
                if (spec)
                    salida.push({ bandera: "-R", spec: spec, mote: "↰ " + spec.split(":")[0] })
                return
            }
            const spec = bajo.indexOf("l:") === 0 ? trozo.slice(2) : trozo
            if (spec.indexOf(":") > 0)
                salida.push({ bandera: "-L", spec: spec, mote: "↳ " + spec.split(":")[0] })
        })
        return salida
    }

    function abrirTuneles(h) {
        if (!h || !h.tuneles)
            return
        const destino = h.rapido && h.usuario ? h.usuario + "@" + h.host : h.alias
        const lista = leerTuneles(h.tuneles)
        for (let i = 0; i < lista.length; ++i) {
            tuneles.append({ destino: destino, bandera: lista[i].bandera,
                             spec: lista[i].spec, mote: lista[i].mote })
        }
    }

    function cerrarTuneles(destino) {
        for (let i = tuneles.count - 1; i >= 0; --i)
            if (tuneles.get(i).destino === String(destino))
                tuneles.remove(i)
    }

    property Connections alSalir: Connections {
        target: Consola
        function onSalioDe(destino) { self.cerrarTuneles(destino) }
    }

    //  Cada túnel, su proceso y su píldora. El `Instantiator` los crea y los
    //  destruye con la lista, que es lo que hace que cerrar la conexión los
    //  apague sin tener que ir matando nada a mano.
    property Instantiator tuneleros: Instantiator {
        model: self.tuneles

        delegate: QtObject {
            id: tunel
            required property string destino
            required property string bandera
            required property string spec
            required property string mote

            readonly property string clave: "terminal.tunel." + destino + "." + spec

            //  Reconexión: un túnel que se cae por un corte de red debe volver
            //  solo, pero con cuidado — si el fallo es del otro lado (puerto
            //  ocupado, permiso denegado) reintentar cada segundo es una
            //  ametralladora. Se espera cada vez un poco más, hasta medio
            //  minuto.
            property int intentos: 0

            property var proceso: K4.Process {
                command: ["ssh", "-N", tunel.bandera, tunel.spec, tunel.destino]
                running: true
                onTerminado: {
                    running = false
                    tunel.intentos += 1
                    reintento.interval = Math.min(30000, 2000 * tunel.intentos)
                    reintento.restart()
                }
            }

            property var reintento: Timer {
                onTriggered: tunel.proceso.running = true
            }

            Component.onCompleted: K4.Pildora.registrar(
                tunel.clave, tunel.mote, 0xF0BBB, Theme.green, 27, true)
            Component.onDestruction: {
                tunel.reintento.stop()
                tunel.proceso.running = false
                K4.Pildora.quitar(tunel.clave)
            }
        }
    }

    //  ── llevarle nuestra integración al servidor ──────────────────
    //
    //  Los bloques, el filete del margen y el aviso de «te está esperando»
    //  funcionan porque la shell de aquí los emite. Por SSH, la shell es la de
    //  ALLÍ: sin esto, entrar en un servidor apaga media terminal.
    //
    //  Se manda por una tubería (`k4term --integracion zsh | ssh …`) en vez de
    //  copiar un fichero: así no hace falta saber dónde vive el repo, que en
    //  una barra instalada no se sabe. Y se corre EN LA TERMINAL porque puede
    //  pedirte la contraseña del servidor.
    function llevarIntegracion() {
        const h = lista[indice]
        if (!h || !Consola.esNuestra)
            return
        const destino = h.rapido && h.usuario ? h.usuario + "@" + h.host : h.alias

        //  La línea del rc lleva su propia marca para poder quitarla luego, y
        //  se comprueba antes de escribir: instalarlo dos veces dejaría la
        //  shell emitiendo cada marcador por duplicado.
        const guion =
            "set -e; " +
            "echo '→ copiando la integración a " + destino + "'; " +
            "k4term --integracion zsh  | ssh " + destino +
                " 'mkdir -p ~/.config/k4term && cat > ~/.config/k4term/k4term.zsh'; " +
            "k4term --integracion fish | ssh " + destino +
                " 'cat > ~/.config/k4term/k4term.fish'; " +
            "ssh -t " + destino + " '" +
                "for par in \"$HOME/.zshrc:zsh\" \"$HOME/.config/fish/config.fish:fish\"; do " +
                "  rc=${par%:*}; cual=${par#*:}; " +
                "  [ -f \"$rc\" ] || continue; " +
                "  grep -q k4term/k4term.$cual \"$rc\" && { echo \"✓ $cual ya estaba\"; continue; }; " +
                "  printf \"\\n#  k4term: integración de la shell\\n\" >> \"$rc\"; " +
                "  printf \". ~/.config/k4term/k4term.%s\\n\" \"$cual\" >> \"$rc\"; " +
                "  echo \"✓ $cual integrada\"; " +
                "done'; " +
            "echo '→ listo: vuelve a entrar y los bloques funcionarán también allí'"

        K4.Terminal.ejecutar(guion + K4.Terminal.cierre)
        cerrar()
    }

    //  Pulsar la píldora de un túnel lo cierra: es lo que uno espera de algo
    //  que está ahí precisamente para recordarte que sigue abierto.
    property Connections clicsPildora: Connections {
        target: K4.Pildora
        function onInvocado(id) {
            const marca = "terminal.tunel."
            if (String(id).indexOf(marca) !== 0)
                return
            for (let i = self.tuneles.count - 1; i >= 0; --i) {
                const t = self.tuneles.get(i)
                if ("terminal.tunel." + t.destino + "." + t.spec === String(id)) {
                    self.tuneles.remove(i)
                    return
                }
            }
        }
    }

    K4.Ipc {
        target: "k4.ssh"

        //  El selector, que es para lo que se abre esto.
        function abrir(): void { self.abrir() }
        function cerrar(): void { self.cerrar() }
        function alternar(): void { self.alternar() }

        //  Y conectar por guion, sin abrir nada: para atajos propios o para
        //  llamarlo desde otro sitio.
        function conectar(alias: string): void {
            self.fSsh.reload()
            const h = self.guardados.find(function (x) { return x.alias === alias })
            if (h)
                self.conectar(self.conExtras(h), false)
        }
    }
}
