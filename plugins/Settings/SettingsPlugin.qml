//  Ajustes de la barra, en su propia ventana.
//
//  Antes la tarjeta "Ajustes" del centro de control lanzaba directamente
//  nm-connection-editor: una ventana del sistema, con su propio marco y su
//  propia tipografía, que no tenía nada que ver con la barra. Ahora los
//  ajustes viven aquí y esa herramienta queda como un acceso más.
//
//  Y ya no son un panel de la island. Cabían de sobra cuando eran tres
//  grupos; hoy son ocho propios más los que aportan los plugins —cerca de
//  cincuenta opciones— y en una columna única la única forma de encontrar algo
//  era bajar leyendo. Cada plugin que instalas lo empeoraba. El sitio se había
//  quedado pequeño, así que se cambió de sitio: ver `VentanaAjustes.qml`.

import QtQuick
import K4 as K4
import "../../core"
import "../../services"

K4Plugin {
    id: self

    name: "settings"
    title: Idioma.t("Ajustes")
    //  Sin `active`, sin `view` y sin `grabKeyboard`: esto ya no se dibuja en
    //  la island. El teclado lo pide la ventana por su cuenta.
    priority: 66

    //  ── ¿hay k4 nuevo? ───────────────────────────────────────────
    //
    //  Vive aquí y no en un servicio por una razón práctica: un singleton nuevo
    //  en `services/` no se carga en caliente —hace falta reiniciar la barra
    //  entera— y esto se ha escrito, probado y ajustado con `pluginReload
    //  settings`. Y por una de fondo: quien lo enseña son los Ajustes, así que
    //  que lo sepa quien lo enseña.
    property Version version: Version {}

    //  `abrir()` de la API cae en esto, así que el centro de aplicaciones y
    //  el atajo entran por aquí sin saber que detrás hay una ventana.
    function toggle() {
        if (ventanaAbierta)
            cerrarVentana()
        else
            abrirVentana()
    }

    //  El vistazo de fondo, para que la novedad no dependa de que se abran los
    //  Ajustes. Cada seis horas y uno al arrancar — con un minuto de cortesía,
    //  que el arranque de la barra ya tiene bastante que hacer y una llamada a
    //  la red en ese momento solo compite con lo que sí se ve.
    //
    //  Y el plazo va atado a que se haya MIRADO, no a que se haya averiguado.
    //  Atado al resultado —«¿sigue sin haber commit? pues al minuto otra vez»—
    //  una copia que no es un clon de git no averigua nunca nada, así que se
    //  quedaba lanzando un `sh` y cuatro `git` cada minuto para siempre.
    property Timer _vistazo: Timer {
        interval: self.version.ultima > 0 ? 6 * 3600 * 1000 : 60000
        repeat: true
        running: self.habilitado
        onTriggered: self.version.mirar(true)
    }

    function close() { cerrarVentana() }

    // ── una página en la que aterrizar ────────────────────────────
    //
    //  `k4 settingsSection apariencia` y compañía apuntan aquí, y la ventana
    //  aterriza en esa página al abrirse — o en el acto, si ya estaba abierta.
    //  Vacío es arriba del todo, como siempre.
    //
    //  La nota se GASTA al llegar: la ventana la limpia en cuanto la usa, así
    //  que cerrar y volver a abrir por la píldora empieza arriba otra vez. El
    //  favor era para un atajo, no una casa nueva.
    property string paginaPedida: ""

    function abrirPagina(pagina) {
        paginaPedida = String(pagina)
        if (!ventanaAbierta)
            abrirVentana()
    }

    // ── la ventana ────────────────────────────────────────────────
    //
    //  Los ajustes en una superficie propia, con barra lateral. El panel de la
    //  island se queda pequeño: dieciséis secciones y cerca de cincuenta
    //  opciones en una sola columna.
    //
    //  Va en un `Loader` y no siempre puesta: una capa a pantalla completa que
    //  existe todo el rato es una capa que el compositor compone todo el rato.
    property bool ventanaAbierta: false

    function abrirVentana() {
        ventanaAbierta = true
        Consola.revisar()
        self.version.mirar(false)
    }

    function cerrarVentana() { ventanaAbierta = false }

    property Loader _ventana: Loader {
        active: self.ventanaAbierta
        sourceComponent: Component {
            VentanaAjustes { plugin: self }
        }
    }

    K4.Ipc {
        target: "k4.settings"
        function toggle(): void { self.toggle() }
        function close(): void { self.close() }

        //  Abrir por una página, para atarlo a una tecla:
        //  `quickshell ipc call k4.settings abrirPagina apariencia`. Vale el
        //  nombre de la sección o su `vista`, sin distinguir mayúsculas.
        function abrirPagina(pagina: string): void { self.abrirPagina(pagina) }

        function alternar(id: string): void { Settings.alternar(id) }

        //  Para poder mirarle las tripas sin abrir nada: en qué commit está la
        //  barra, cuánto le lleva `origin` y por qué no se sabe, si no se sabe.
        function version(): string {
            return JSON.stringify({
                commit: self.version.commit,
                detras: self.version.detras,
                sucio: self.version.sucio,
                pega: self.version.pega,
                mirando: self.version.mirando
            })
        }

        //  Y para lanzarlo desde fuera, que es lo que hace el botón.
        function actualizar(): void { self.version.actualizar() }
    }
}
