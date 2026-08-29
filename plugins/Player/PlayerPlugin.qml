//  Reproductor: carátula, pista, línea de tiempo arrastrable y transporte.
//  Se activa al pasar el ratón si hay algo sonando, ganándole al reloj, y se
//  asoma solo unos segundos cuando cambia la canción.

import QtQuick
import K4 as K4
import "../../core"
import "../../services"

K4Plugin {
    id: self

    name: "player"
    title: Idioma.t("Reproductor")
    priority: 55

    //  Sin cazador de clics: esto solo aparece al pasar el ratón o en el asomo
    //  de un cambio de pista —sin que nadie lo pida— y se va cuando el puntero
    //  se va. El mismo caso que el HUD del volumen. Ver `closeOnClickOutside`
    //  en el contrato.
    closeOnClickOutside: false

    //  Al pasar el ratón —lo de siempre— y además durante el asomo.
    //
    //  El asomo NO pide `isPlaying`: al cambiar de pista hay reproductores que
    //  pasan un instante por «parado», y con la condición compartida el asomo
    //  se moría en ese parpadeo justo al empezar.
    active: habilitado
        && ((Island.hovered && Media.isPlaying) || asomando)

    //  ── asomarse al cambiar de canción ───────────────────────────
    //
    //  Antes solo salía al pasar el ratón, así que era lo único del sistema que
    //  no tenía forma de pedir la island por su cuenta: con la barra escondida,
    //  una canción nueva no se la enteraba nadie. El aviso, el volumen y la
    //  captura sí salen solos; esto faltaba.
    //
    //  La pista se identifica por lo que se LEE —título y artista— y no por el
    //  `xesam:trackid`: hay reproductores que no lo publican, y los navegadores
    //  lo cambian sin que cambie la canción.
    property bool asomarAlCambiar: true
    property bool asomando: false

    readonly property string pista:
        Media.hasPlayer && String(Media.activePlayer.trackTitle || "").length > 0
            ? String(Media.activePlayer.trackTitle) + " · "
              + String(Media.activePlayer.trackArtist || "")
            : ""

    property string pistaPrevia: ""

    //  Y se deja POSAR antes de comparar, que esto no es un detalle: los
    //  metadatos de MPRIS llegan A TROZOS. Medido con un reproductor de prueba:
    //  primero aparece el título y un instante después el artista, así que la
    //  cadena cambia DOS veces por una sola canción — y la segunda vez ya había
    //  una anterior no vacía, o sea que parecía un cambio de pista. Se asomaba
    //  con la primera canción de la sesión, que es exactamente lo que el guardia
    //  de abajo existe para evitar.
    onPistaChanged: posarTimer.restart()

    Timer {
        id: posarTimer
        interval: 350
        onTriggered: {
            const antes = self.pistaPrevia
            self.pistaPrevia = self.pista
            if (!self.asomarAlCambiar || !self.habilitado)
                return
            //  Hacen falta las DOS: que haya una nueva y que hubiera otra antes.
            //  Al arrancar la barra con música puesta lo que llega no es un
            //  cambio de canción sino el descubrimiento de que la había, y
            //  asomarse ahí sería saludar en cada inicio de sesión. Lo mismo al
            //  cerrar el reproductor.
            if (self.pista.length === 0 || antes.length === 0
                    || antes === self.pista)
                return
            self.asomando = true
            asomoTimer.restart()
        }
    }

    //  Lo justo para leer título y artista y volver a lo tuyo.
    Timer {
        id: asomoTimer
        interval: 3200
        onTriggered: self.asomando = false
    }

    //  Y que ESC lo quite, como cualquier otra cosa que ocupe la island. Con el
    //  ratón encima no cierra nada, que ahí manda el hover: es el mismo
    //  comportamiento de siempre.
    function close() { self.asomando = false }

    K4.Ajustes {
        plugin: "player"
        grupo: Idioma.t("Reproductor")
        opciones: [
            { id: "asomarAlCambiar",
              nombre: Idioma.t("Asomarse al cambiar de canción"),
              desc: Idioma.t("Unos segundos con la pista nueva, y se va sola"),
              glifo: 0xF075A }   // md-music
        ]
        valores: ({ asomarAlCambiar: self.asomarAlCambiar })
        onCambiado: function (id, valor) {
            if (id !== "asomarAlCambiar")
                return
            self.asomarAlCambiar = valor === true
            guardado.guardar({ asomarAlCambiar: self.asomarAlCambiar })
        }
    }

    property var guardado: K4.Guardado {
        plugin: "player"
        onCargado: function (d) {
            if (d && d.asomarAlCambiar !== undefined)
                self.asomarAlCambiar = d.asomarAlCambiar === true
        }
    }

    // el centro de control y la bandeja; los inyecta el host
    property var panel: null
    property var tray: null
    property var juego: null

    //  Las píldoras de los plugins también cuentan: sin ellas en la suma, una
    //  campana de agente empujaba el grupo de la derecha sobre el título de la
    //  canción. Mismo problema que tenía el reloj, y misma explicación larga
    //  está allí.
    //  Asomándose, lo justo para un título: alto de píldora y algo más ancho
    //  que ella. Lo demás no se pinta, así que pedirlo sería dejar un hueco.
    islandWidth: asomando ? 300
        : 340 + (Tray.count > 0 ? Math.min(Tray.count, 4) * 24 + 8 : 0)
        + (Game.cargado ? 46 : 0)
        + Indicadores.anchoAproximado
    // crece para dejar sitio a las notificaciones recientes
    //  El base ya lleva sus márgenes de 14 arriba y abajo. La tira añade lo que
    //  mide más el espaciado de 13 del reparto y los 2 de su propio topMargin.
    readonly property int alturaTira: Settings.notificacionesAlPasar
        ? Notifs.stripHeight(3) : 0
    //  Asomándose, solo la fila de la pista: 44 px de carátula más sus dos
    //  márgenes de 14. El resto —línea de tiempo, transporte, notificaciones—
    //  lo esconde la vista, así que pedir más sería dejar un hueco negro.
    //
    //  Existe porque el asomo con el alto entero era insufrible: un vídeo
    //  tonto de treinta segundos abría media island, y cada vez que cambiaba
    //  de pista otra vez. Enterarse de qué suena no necesita el mando entero.
    islandHeight: asomando ? Theme.baseHeight
        : (Media.hasTimeline ? 140 : 115)
          + (alturaTira > 0 ? alturaTira + 15 : 0)

    view: Component {
        PlayerView {
            panel: self.panel; tray: self.tray; juego: self.juego
            //  Sin esto la vista no sabe si es un asomo y sale entera.
            plugin: self
        }
    }

    //  Y si te acercas, deja de ser un asomo: se despliega entero y se queda
    //  mientras tengas el ratón encima, que es lo que ya hacía al pasar por la
    //  píldora. Acercarse es pedirlo.
    Connections {
        target: Island
        function onHoveredChanged() {
            if (Island.hovered && self.asomando)
                self.asomando = false
        }
    }
}
