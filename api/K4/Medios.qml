pragma Singleton

//  Lo que está sonando, venga de donde venga (MPRIS).
//
//  Leer es libre: un plugin de letras, un scrobbler o un simple «ahora suena»
//  solo miran. Los controles —pausar, saltar, buscar— piden el permiso
//  `medios`, que parar la música de alguien sin avisar es de mala educación.
//
//  `posicion` solo se actualiza si alguien la mira: llama a `seguirPosicion()`
//  cuando montes tu vista y a `dejarPosicion()` al soltarla. Si no, el
//  temporizador no corre y no gastas batería por una barra que nadie ve.

import QtQuick

QtObject {
    readonly property var _m: Puente.medios
    readonly property var _p: _m ? _m.activePlayer : null

    readonly property bool hay: _m ? _m.hasPlayer : false
    readonly property bool sonando: _m ? _m.isPlaying : false

    readonly property string titulo: _p ? (_p.trackTitle || "") : ""
    readonly property string artista: _p ? (_p.trackArtist || "") : ""
    readonly property string album: _p ? (_p.trackAlbum || "") : ""
    readonly property string aplicacion: _p ? (_p.identity || "") : ""

    //  La carátula, ya resuelta a algo que un Image sabe cargar.
    readonly property string caratula: (_m && _p) ? (_m.coverFor(_p) || "") : ""

    readonly property real posicion: _p ? (_p.position || 0) : 0
    readonly property real duracion: _p ? (_p.length || 0) : 0
    readonly property bool hayLinea: _m ? _m.hasTimeline : false

    //  «3:07» a partir de segundos, con el mismo formato que la barra.
    function comoTiempo(segundos) {
        return _m ? _m.formatTime(segundos) : "0:00"
    }

    function seguirPosicion() { if (_m) _m.watchPosition() }
    function dejarPosicion() { if (_m) _m.unwatchPosition() }

    //  ── requieren el permiso `medios` ─────────────────────────────
    function alternarPausa() { if (_m) _m.togglePlaying() }
    function siguiente() { if (_m) _m.siguiente() }
    function anterior() { if (_m) _m.anterior() }
    function buscar(fraccion) { if (_m) _m.seekTo(fraccion) }
}
