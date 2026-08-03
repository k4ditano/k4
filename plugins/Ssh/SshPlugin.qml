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
                 rapido: false }
    }

    readonly property var lista: {
        const q = busqueda.trim().toLowerCase()
        const salida = []

        for (let i = 0; i < guardados.length; ++i) {
            const h = conExtras(guardados[i])
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
        const guion = mandato(h)
        if (!guion)
            return

        if (!h.rapido)
            apuntarVisita(h.alias)

        if (enVentana === true)
            K4.Sistema.lanzar([Consola.binario || "k4term", "-e", "sh", "-c", guion])
        else
            K4.Terminal.ejecutar(guion)

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
    function guardar(h, alias) {
        const nombre = String(alias || h.host).trim()
        if (!nombre)
            return

        let texto = fSsh.text() || ""
        if (texto.length > 0 && texto.slice(-1) !== "\n")
            texto += "\n"

        let bloque = "\nHost " + nombre + "\n"
        bloque += "    HostName " + h.host + "\n"
        if (h.usuario)
            bloque += "    User " + h.usuario + "\n"
        if (h.puerto)
            bloque += "    Port " + h.puerto + "\n"

        fSsh.setText(texto + bloque)
        cerrarFichero.running = true
        //  Y a releer, pero no aquí mismo: `text()` todavía devuelve lo que
        //  había cuando se cargó, así que leerlo ahora deja la lista en cero
        //  —se vio— y encima con el fichero ya escrito, que es lo que
        //  desconcierta. Se recarga y `onLoaded` la rehace.
        relee.restart()
        busqueda = ""
        indice = 0
    }

    Timer {
        id: relee
        interval: 120
        onTriggered: self.fSsh.reload()
    }

    function guardarActual() {
        const h = lista[indice]
        if (h && h.rapido)
            guardar(h, h.host)
    }

    function borrarActual() {
        const h = lista[indice]
        if (!h || h.rapido)
            return

        //  Se corta desde su `Host` hasta el siguiente `Host` (o el final).
        //  Por líneas y no con una expresión sobre todo el fichero: así lo que
        //  hay alrededor no corre ningún riesgo.
        const lineas = (fSsh.text() || "").split("\n")
        const salida = []
        let dentro = false

        for (let i = 0; i < lineas.length; ++i) {
            const limpia = lineas[i].replace(/#.*$/, "").trim()
            const esHost = /^host[\s=]/i.test(limpia)
            if (esHost) {
                const nombres = limpia.slice(4).replace(/^[\s=]+/, "").split(/\s+/)
                dentro = nombres.length > 0 && nombres[0] === h.alias
            }
            if (!dentro)
                salida.push(lineas[i])
        }

        fSsh.setText(salida.join("\n"))
        relee.restart()

        const nuevo = Object.assign({}, extras)
        delete nuevo[h.alias]
        extras = nuevo
        fExtras.setText(JSON.stringify(extras, null, 2) + "\n")

        indice = Math.max(0, Math.min(indice, cuantos - 2))
    }

    //  ── la clave, si no tienes ninguna ────────────────────────────
    //
    //  Sin clave, entrar pide contraseña cada vez y guardar contraseñas es
    //  justo lo que este plugin no va a hacer. Crear una y mandarla al
    //  servidor es el paso que lo arregla para siempre, y se hace EN LA
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
