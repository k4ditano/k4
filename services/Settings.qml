pragma Singleton

//  Preferencias de la barra.
//
//  Solo vive aquí lo que de verdad cambia algo: un interruptor que no está
//  conectado a nada es peor que no tenerlo. Cada opción dice qué módulo la
//  lee, para que no queden huérfanas al refactorizar.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: ajustes

    readonly property string ruta: Quickshell.env("HOME") + "/.local/state/k4/ajustes.json"

    // ── idioma ────────────────────────────────────────────────────
    // "auto" sigue al del sistema. services/Idioma.qml lo lee.
    property string idioma: "auto"

    // ── juego ─────────────────────────────────────────────────────
    // El interruptor maestro. Apagado no es «ocultar»: se paran los relojes
    // del combate, el guardado y el vigía de tokens, que solo trabaja para
    // esto. Quien no quiera el juego no debe pagar nada por tenerlo instalado.
    property bool juegoActivo: true
    // services/Game.qml: al caer el grupo, ¿arranca sola la siguiente?
    property bool juegoContinuar: true
    // widgets/JuegoPildora.qml: oleada y aviso de cofres en la píldora
    property bool juegoEnPildora: true
    // services/Game.qml: el combate solo avanza con tokens de IA gastados
    property bool juegoPorTokens: false

    // ── captura y grabación ───────────────────────────────────────
    // services/Captura.qml los lee. Estaban a fuego ahí, con un comentario que
    // decía «en la fase 6 los lee de Settings»: esta es la fase 6.
    property string capturaDestino: "ambos"     // fichero · portapapeles · ambos · anotar
    property bool capturaCursor: false          // ¿sale el puntero en la foto?
    property string grabarAudio: "ambos"        // ninguno · sistema · micro · ambos
    property string grabarCodec: "h264"         // h264 · hevc
    property int grabarFps: 60
    //  ¿Grabar también la cámara, en un fichero aparte?
    //
    //  Aparte y no incrustada: así en el editor se coloca, se escala y se quita
    //  cuando quieras, en vez de quedar pegada al vídeo para siempre.
    property bool grabarCamara: false
    //  Qué cámara. Vacío es «la primera que haya», que es lo que quiere
    //  cualquiera con una sola. Se rellena solo al detectarlas.
    property string camaraDispositivo: ""

    // ── editor ────────────────────────────────────────────────────
    // services/Editor.qml los lee.
    property bool zoomAuto: true                // ¿propone momentos al grabar?
    property real zoomNivel: 2.5                // cuánto amplía como máximo
    property string editorCodec: "h264"         // con qué se renderiza

    // ── barra ─────────────────────────────────────────────────────
    //  En qué borde vive la barra. shell.qml ancla la ventana, voltea la
    //  silueta y orienta los gestos con esto; los plugins lo leen por
    //  K4.Isla.posicion para adaptar lo que pinten fuera.
    property string posicionBarra: "arriba"     // arriba · abajo
    //  En qué punto del borde se centra la island, en tanto por ciento del
    //  ancho libre: 50 es el centro de siempre. Un plugin puede desplazarla
    //  TEMPORALMENTE con K4.Isla.colocar; esto es la base a la que vuelve.
    property int alineacionBarra: 50            // 15 · 50 · 85
    // widgets/TrayRow.qml: iconos de bandeja en la píldora
    // Apagada de fábrica: en la píldora los iconos de bandeja son ruido casi
    // siempre, y al acercar el ratón la island ya se abre y ahí sí se ven —y
    // encima se pueden pulsar, que en la píldora no—.
    property bool bandejaEnPildora: false
    // widgets/NotifStrip.qml: notificaciones recientes al pasar el ratón
    property bool notificacionesAlPasar: true

    // ── accesos directos ──────────────────────────────────────────
    //  Qué aplicaciones salen en la franja del centro de control, por id de
    //  plugin. plugins/Panel/PanelView.qml la pinta y el centro de
    //  aplicaciones la edita con la chincheta de cada tarjeta.
    //
    //  Ids y no una copia de nombres e iconos: así al renombrar un plugin o
    //  cambiarle el icono el acceso directo se entera solo, y uno que apunte a
    //  un plugin desinstalado simplemente no se pinta.
    property var accesosDirectos: ["game", "hyprtheme", "system", "clipboard"]

    function esAccesoDirecto(id) {
        return (accesosDirectos || []).indexOf(id) >= 0
    }

    function alternarAcceso(id) {
        const l = (accesosDirectos || []).slice()
        const i = l.indexOf(id)
        if (i >= 0)
            l.splice(i, 1)
        else
            l.push(id)
        accesosDirectos = l
        guardar()
    }

    // Cambia el valor de una opción que no es un interruptor.
    function poner(id, valor) {
        if (String(id).indexOf("ext_") === 0) {
            Enganches.ponerAjuste(id, valor)
            return
        }
        ajustes[id] = valor
        guardar()
    }

    readonly property var definicion: [
        {
            grupo: Idioma.t("Idioma"),
            opciones: [
                { id: "idioma", tipo: "eleccion", de: "idiomas",
                  nombre: Idioma.t("Idioma de la barra"),
                  desc: Idioma.t("Automático sigue al del sistema"),
                  glifo: 0xF05CA }
            ]
        },
        {
            grupo: Idioma.t("Mazmorra"),
            opciones: [
                { id: "juegoActivo", nombre: Idioma.t("Mazmorra activa"),
                  desc: Idioma.t("Apagada no corre, no guarda y no ocupa sitio"), glifo: 0xF04E5 },
                { requiere: "juegoActivo", id: "juegoContinuar", nombre: Idioma.t("Continuar sola al morir"),
                  desc: Idioma.t("Encadena la siguiente partida tras el resumen"), glifo: 0xF04E5 },
                { requiere: "juegoActivo", id: "juegoEnPildora", nombre: Idioma.t("Mostrar en la píldora"),
                  desc: Idioma.t("Oleada actual y aviso de cofres sin abrir"), glifo: 0xF0BC2 },
                { requiere: "juegoActivo", id: "juegoPorTokens", nombre: Idioma.t("Pelear con tokens"),
                  desc: Idioma.t("Avanza solo mientras gastas en Claude o Codex"), glifo: 0xF0241 }
            ]
        },
        {
            grupo: Idioma.t("Captura"),
            opciones: [
                { id: "capturaDestino", tipo: "eleccion", de: "destinos",
                  nombre: Idioma.t("Qué hacer con la foto"),
                  desc: Idioma.t("Lo que pasa al capturar sin decir nada más"),
                  glifo: 0xF0E51 },
                { id: "capturaCursor", nombre: Idioma.t("Incluir el puntero"),
                  desc: Idioma.t("Sale el ratón donde estuviera al disparar"),
                  glifo: 0xF037D }
            ]
        },
        {
            grupo: Idioma.t("Grabación"),
            opciones: [
                { id: "grabarAudio", tipo: "eleccion", de: "audios",
                  nombre: Idioma.t("Qué sonido se graba"),
                  desc: Idioma.t("En pistas separadas, para equilibrarlas después"),
                  glifo: 0xF057E },
                { id: "grabarFps", tipo: "eleccion", de: "fps",
                  nombre: Idioma.t("Fotogramas por segundo"),
                  desc: Idioma.t("60 va más suave y ocupa el doble"),
                  glifo: 0xF0567 },
                { id: "grabarCodec", tipo: "eleccion", de: "codecs",
                  nombre: Idioma.t("Códec de la grabación"),
                  desc: Idioma.t("HEVC ocupa menos y tarda más en abrirse"),
                  glifo: 0xF0381 },
                //  Solo si hay cámara: ofrecer un interruptor que no puede
                //  hacer nada es peor que no ofrecerlo.
                { id: "grabarCamara", nombre: Idioma.t("Grabar también la cámara"),
                  desc: Idioma.t("En un fichero aparte, para colocarla en el editor"),
                  glifo: 0xF0567, si: "camara" }
            ]
        },
        {
            grupo: Idioma.t("Editor"),
            opciones: [
                { id: "zoomAuto", nombre: Idioma.t("Proponer zoom al grabar"),
                  desc: Idioma.t("Del rastro del cursor y de los clics"),
                  glifo: 0xF1276 },
                { requiere: "zoomAuto", id: "zoomNivel", tipo: "eleccion",
                  de: "niveles",
                  nombre: Idioma.t("Cuánto amplía"),
                  desc: Idioma.t("El máximo de los momentos que propone"),
                  glifo: 0xF034B },
                { id: "editorCodec", tipo: "eleccion", de: "codecs",
                  nombre: Idioma.t("Códec al renderizar"),
                  desc: Idioma.t("El del vídeo que sale del editor"),
                  glifo: 0xF0381 }
            ]
        },
        {
            grupo: Idioma.t("Island"),
            opciones: [
                { id: "posicionBarra", tipo: "eleccion", de: "posiciones",
                  nombre: Idioma.t("Dónde vive la barra"),
                  desc: Idioma.t("La island y sus alas se voltean solas"),
                  glifo: 0xF10A9 },
                { id: "alineacionBarra", tipo: "eleccion", de: "alineaciones",
                  nombre: Idioma.t("Alineación de la island"),
                  desc: Idioma.t("En qué punto del borde se coloca"),
                  glifo: 0xF11C3 },
                { id: "bandejaEnPildora", nombre: Idioma.t("Bandeja en la píldora"),
                  desc: Idioma.t("Iconos de las aplicaciones en segundo plano"), glifo: 0xF0FB0 },
                { id: "notificacionesAlPasar", nombre: Idioma.t("Notificaciones al pasar el ratón"),
                  desc: Idioma.t("Las recientes, bajo el reloj y el reproductor"), glifo: 0xF009A }
            ]
        },
        {
            grupo: Idioma.t("Plugins"),
            opciones: PluginManager.opcionesAjustes
        }
    //  Y al final, lo que aporten los plugins con K4.Ajustes. Van los
    //  últimos a propósito: lo de la barra primero, y lo instalado después,
    //  que es el orden en que la gente busca.
    ].concat(Enganches.gruposAjustes)

    //  Las alternativas de cada opción de varias respuestas.
    //
    //  Aquí y no en la vista: la vista tenía `de === "idiomas"` a fuego y todo lo
    //  demás devolvía una lista vacía, así que añadir una elección no era añadir
    //  una opción sino tocar el QML de la pantalla. Ahora es una entrada más en
    //  este `switch`.
    function opcionesDe(de) {
        if (de === "idiomas")
            return [{ codigo: "auto", nombre: Idioma.t("Automático") }]
                .concat(Idioma.disponibles)
        if (de === "destinos")
            return [{ codigo: "fichero",      nombre: Idioma.t("Guardar") },
                    { codigo: "portapapeles", nombre: Idioma.t("Copiar") },
                    { codigo: "ambos",        nombre: Idioma.t("Las dos") },
                    { codigo: "anotar",       nombre: Idioma.t("Anotar") }]
        if (de === "audios")
            return [{ codigo: "ninguno", nombre: Idioma.t("Nada") },
                    { codigo: "sistema", nombre: Idioma.t("Sistema") },
                    { codigo: "micro",   nombre: Idioma.t("Micro") },
                    { codigo: "ambos",   nombre: Idioma.t("Los dos") }]
        if (de === "codecs")
            return [{ codigo: "h264", nombre: "H.264" },
                    { codigo: "hevc", nombre: "HEVC" }]
        if (de === "fps")
            return [{ codigo: 30, nombre: "30" },
                    { codigo: 60, nombre: "60" }]
        if (de === "posiciones")
            return [{ codigo: "arriba", nombre: Idioma.t("Arriba") },
                    { codigo: "abajo",  nombre: Idioma.t("Abajo") }]
        if (de === "alineaciones")
            return [{ codigo: 15, nombre: Idioma.t("Izquierda") },
                    { codigo: 50, nombre: Idioma.t("Centro") },
                    { codigo: 85, nombre: Idioma.t("Derecha") }]
        if (de === "niveles")
            //  Etiquetas y no números: «2,5» no le dice nada a nadie, y lo que se
            //  quiere elegir es cuánto se nota.
            return [{ codigo: 1.8, nombre: Idioma.t("Suave") },
                    { codigo: 2.5, nombre: Idioma.t("Medio") },
                    { codigo: 3.2, nombre: Idioma.t("Fuerte") }]
        return []
    }

    function alternar(id) {
        if (String(id).indexOf("plugin_") === 0) {
            PluginManager.alternarAjuste(id)
            return
        }
        //  Los de un plugin no se guardan aquí: los guarda él. Nosotros solo
        //  le decimos que el usuario ha tocado, y él contesta con el valor
        //  nuevo en su `valores` — así lo que se ve es siempre lo guardado.
        if (String(id).indexOf("ext_") === 0) {
            Enganches.alternarAjuste(id)
            return
        }
        ajustes[id] = !ajustes[id]
        guardar()
    }

    function valor(id) {
        if (String(id).indexOf("plugin_") === 0)
            return PluginManager.valorAjuste(id)
        if (String(id).indexOf("ext_") === 0)
            return Enganches.valorAjuste(id)
        return ajustes[id]
    }

    // ── persistencia ──────────────────────────────────────────────
    //
    //  Las claves, en una lista. Antes eran una línea por clave al guardar y otra
    //  al cargar, y con quince preferencias eso son treinta sitios donde
    //  olvidarse de una. Y una lista y no un recorrido del objeto entero porque
    //  un singleton tiene decenas de propiedades internas que no son ajustes.
    readonly property var claves: [
        "idioma",
        "juegoActivo", "juegoContinuar", "juegoEnPildora", "juegoPorTokens",
        "capturaDestino", "capturaCursor",
        "grabarAudio", "grabarCodec", "grabarFps",
        "grabarCamara", "camaraDispositivo",
        "zoomAuto", "zoomNivel", "editorCodec",
        "posicionBarra", "alineacionBarra",
        "bandejaEnPildora", "notificacionesAlPasar",
        "accesosDirectos"
    ]

    function guardar() {
        if (!cargado)
            return
        const d = {}
        for (let i = 0; i < claves.length; ++i)
            d[claves[i]] = ajustes[claves[i]]
        vista.setText(JSON.stringify(d, null, 1))
    }

    property bool cargado: false

    FileView { id: vista; path: ajustes.ruta; blockLoading: true }

    Process {
        command: ["mkdir", "-p", Quickshell.env("HOME") + "/.local/state/k4"]
        running: true
        onExited: ajustes.cargar()
    }

    function cargar() {
        const bruto = vista.text()

        if (bruto.length > 0) {
            try {
                const s = JSON.parse(bruto)
                for (let i = 0; i < claves.length; ++i)
                    if (s[claves[i]] !== undefined)
                        ajustes[claves[i]] = s[claves[i]]
            } catch (e) {
                // preferencias ilegibles: se quedan las de fábrica
            }
        }

        cargado = true
    }
}
