//  Ajustes de la barra, dentro de la island.
//
//  Antes la tarjeta "Ajustes" del centro de control lanzaba directamente
//  nm-connection-editor: una ventana del sistema, con su propio marco y su
//  propia tipografía, que no tenía nada que ver con la barra. Ahora los
//  ajustes viven aquí y esa herramienta queda como un acceso más.

import QtQuick
import K4 as K4
import "../../core"
import "../../services"

K4Plugin {
    id: self

    name: "settings"
    title: Idioma.t("Ajustes")
    priority: 66
    active: habilitado && open
    //  El teclado entero mientras está abierto: «opcional» es OnDemand y
    //  el compositor solo lo da si PINCHAS la superficie, así que abierto
    //  desde el centro de aplicaciones o por atajo no llegaba ni el ESC.
    //  Ver `tecladoOpcional` en api/K4/Plugin.qml.
    grabKeyboard: open

    property bool open: false
    property var panel: null

    //  ── ¿hay k4 nuevo? ───────────────────────────────────────────
    //
    //  Vive aquí y no en un servicio por una razón práctica: un singleton nuevo
    //  en `services/` no se carga en caliente —hace falta reiniciar la barra
    //  entera— y esto se ha escrito, probado y ajustado con `pluginReload
    //  settings`. Y por una de fondo: quien lo enseña son los Ajustes, así que
    //  que lo sepa quien lo enseña.
    property Version version: Version {}

    islandWidth: 600
    //  El contenido ya no cabe en una pantalla y se recorre, así que esto no es
    //  «lo que mide» sino «cuánto se enseña de una vez». 640 deja ver cinco filas
    //  y media, que es bastante para no sentir que estás mirando por una rendija,
    //  y no se acerca al techo de 880 de la superficie.
    //
    //  Antes eran 516 y los ajustes eran tres grupos. Al añadir captura,
    //  grabación y editor el contenido pasó de novecientos píxeles y el reparto lo
    //  aplastó: el grupo del editor no llegaba a verse. Lo que faltaba no era
    //  alto, era poder desplazar.
    islandHeight: 640

    handlesBackgroundTap: true
    onBackgroundTapped: {}

    closeOnHoverExit: true
    hoverExitDelay: 1200
    onHoverTimedOut: close()

    function toggle() {
        open = !open
        if (open) {
            if (panel) panel.close()
            Notifs.dismissToast()
            //  Y de paso, volver a mirar qué hay instalado. Aquí es donde se
            //  lee qué plugins están encendidos y por qué está apagado el que
            //  lo esté: si has instalado —o desinstalado— k4term desde que
            //  arrancó la barra, esta lista tiene que decir la verdad.
            Consola.revisar()
            //  Y de mirar si hay versión nueva. Trae su propia gracia de diez
            //  minutos, así que abrir y cerrar los Ajustes tres veces seguidas
            //  no son tres viajes a la red.
            self.version.mirar(false)
        }
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

    function close() { open = false }

    K4.Ipc {
        target: "k4.settings"
        function toggle(): void { self.toggle() }
        function close(): void { self.close() }
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

    view: Component {
        SettingsView { plugin: self }
    }
}
