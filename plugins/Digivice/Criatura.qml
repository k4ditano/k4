//  El bicho, vivo.
//
//  Los sprites de Wikimon son de un fotograma —lo comprobé: ni uno animado—
//  así que la vida no puede venir del sprite. Viene del movimiento: pasea de
//  un lado a otro de la pantalla, se da la vuelta al llegar, respira con un
//  bote pequeño y de noche se tumba. Con eso deja de ser una calcomanía.
//
//  El paseo va a saltos y no continuo: un LCD de puntos no interpola, y
//  moverse de píxel en píxel es lo que lo hace parecer de dentro de la
//  pantalla en vez de encima de ella.

import QtQuick
import K4 as K4
import "../../services"

Item {
    id: self

    property string especie: ""
    property bool durmiendo: false
    property bool enfermo: false

    //  En qué anda, según lo que pasa en TU escritorio: bailando con tu
    //  música, nervioso con el escritorio lleno, tranquilo si llevas un rato
    //  concentrado. El bicho ya vivía de tu escritorio pero solo lo contaba;
    //  esto es que además se entere.
    property string animo: "normal"

    //  Cómo baila ESTE bicho: cuánto salta y a qué ritmo. Lo pone su carácter,
    //  porque todos bailando igual delataba que no hay nadie dentro.
    property int saltoBaile: 8
    property int ritmoBaile: 130
    property real lado: 64
    //  Para el combate: quieto y mirando al rival.
    property bool quieto: false
    property bool mirandoDerecha: true

    property int _paso: 6
    property int _dir: 1

    // ── reacciones ────────────────────────────────────────────────
    //  Cada acción tiene que VERSE en el bicho, no solo en un contador. Un
    //  medidor que sube sin que la criatura se entere es una hoja de cálculo
    //  con sprites.
    property string _simbolo: ""

    function reaccionar(simbolo) {
        _simbolo = simbolo
        globo.opacity = 1
        globo.y = cuerpo.y - 4
        salto.restart()
        subeGlobo.restart()
    }

    //  Sobre un desplazamiento aparte y NO sobre `y`: animar `y` directamente
    //  rompe su enlace para siempre, y con él el respiro. Se ve una vez y el
    //  bicho se queda tieso el resto de la partida.
    SequentialAnimation {
        id: salto
        NumberAnimation {
            target: cuerpo; property: "_salto"; duration: 130
            to: 10; easing.type: Easing.OutQuad
        }
        NumberAnimation {
            target: cuerpo; property: "_salto"; duration: 170
            to: 0; easing.type: Easing.OutBounce
        }
    }

    //  El símbolo que sube y se desvanece: comida, corazón, chispa, escoba.
    //  Glifo y no Etiqueta: son iconos de la Nerd Font y con la tipografía de
    //  texto salen como cuadraditos.
    K4.Glifo {
        id: globo
        x: cuerpo.x + self.lado * 0.55
        text: self._simbolo
        font.pixelSize: 16
        color: "#e8f4ea"
        opacity: 0
        z: 4
    }

    ParallelAnimation {
        id: subeGlobo
        NumberAnimation { target: globo; property: "y"; duration: 900
                          to: cuerpo.y - 30; easing.type: Easing.OutQuad }
        NumberAnimation { target: globo; property: "opacity"; duration: 900; to: 0 }
    }

    Retrato {
        id: cuerpo
        especie: self.especie
        lado: self.lado
        y: (self.height - self.lado) / 2 + _bote - _salto
        x: self.width / 2 - self.lado / 2

        property real _bote: 0
        property real _salto: 0

        //  Mira hacia donde anda.
        //
        //  Los sprites de Wikimon vienen mirando a la IZQUIERDA —comprobado
        //  sobre los de la caché: Agumon, Airdramon, Gabumon, Numemon,
        //  Kabuterimon y Monochromon, todos—. Aquí ponía lo contrario y por
        //  eso en combate los dos bichos se daban la espalda: el mío miraba
        //  hacia fuera de la pantalla y el rival también.
        //
        //  De ahí el signo menos: `mirandoDerecha` y `_dir` positivo quieren
        //  decir «hacia la derecha», y para eso hay que ESPEJAR.
        transform: Scale {
            origin.x: cuerpo.width / 2
            xScale: self.quieto ? (self.mirandoDerecha ? -1 : 1) : -self._dir
        }

        opacity: self.durmiendo ? 0.55 : 1
        Behavior on opacity { NumberAnimation { duration: 400 } }

        //  Dormido se tumba de lado, que es lo que hace el bicho del aparato.
        rotation: self.durmiendo ? 12 : 0
        Behavior on rotation { NumberAnimation { duration: 600; easing.type: Easing.OutBack } }
    }

    //  El paseo. Se para al dormir, al enfermar y en combate: un bicho
    //  enfermo que sigue de excursión no cuenta que está enfermo.
    Timer {
        //  Nervioso anda más deprisa y tranquilo se queda casi quieto: el
        //  ritmo del paseo es lo más barato que hay para contar un estado de
        //  ánimo sin un solo sprite nuevo.
        interval: self.animo === "nervioso" ? 300
                : self.animo === "tranquilo" ? 1400 : 620
        repeat: true
        running: !self.durmiendo && !self.enfermo && !self.quieto
              && self.especie !== "" && self.animo !== "bailando"
              && self.animo !== "resollando"
        onTriggered: {
            const margen = 6
            const limite = self.width - self.lado - margen
            let x = cuerpo.x + self._dir * self._paso
            if (x > limite) { x = limite; self._dir = -1 }
            else if (x < margen) { x = margen; self._dir = 1 }
            cuerpo.x = x
        }
    }

    //  El baile. Se queda en el sitio y salta, alternando el lado al que
    //  mira: es lo que hace un bicho de LCD cuando suena algo, y no necesita
    //  ni un fotograma nuevo.
    SequentialAnimation {
        running: self.animo === "bailando" && !self.durmiendo
        loops: Animation.Infinite

        ScriptAction { script: cuerpo._salto = self.saltoBaile }
        NumberAnimation { target: cuerpo; property: "_salto"; to: 0
                          duration: 170; easing.type: Easing.OutBounce }
        ScriptAction { script: self._dir = -self._dir }
        PauseAnimation { duration: self.ritmoBaile }
        ScriptAction { script: cuerpo._salto = self.saltoBaile }
        NumberAnimation { target: cuerpo; property: "_salto"; to: 0
                          duration: 170; easing.type: Easing.OutBounce }
        PauseAnimation { duration: self.ritmoBaile }
    }

    //  Tomando aire entre tanda y tanda: respira más fuerte y se queda en el
    //  sitio. Es la diferencia entre bailar y estar programado para bailar.
    SequentialAnimation {
        running: self.animo === "resollando" && !self.durmiendo
        loops: Animation.Infinite
        NumberAnimation { target: cuerpo; property: "_bote"; to: 3
                          duration: 260; easing.type: Easing.InOutQuad }
        NumberAnimation { target: cuerpo; property: "_bote"; to: 0
                          duration: 260; easing.type: Easing.InOutQuad }
    }

    //  Respirar. Dos posiciones, sin interpolar: es un sprite de LCD, no un
    //  muñeco de trapo.
    Timer {
        interval: self.durmiendo ? 1400
                : self.animo === "nervioso" ? 300
                : self.animo === "tranquilo" ? 900 : 460
        repeat: true
        running: self.especie !== ""
        onTriggered: cuerpo._bote = cuerpo._bote === 0 ? 2 : 0
    }

    //  Enfermo: parpadea despacio. Es el aviso del aparato de toda la vida.
    SequentialAnimation on opacity {
        running: self.enfermo && !self.durmiendo
        loops: Animation.Infinite
        NumberAnimation { to: 0.35; duration: 700 }
        NumberAnimation { to: 1.0; duration: 700 }
    }

    //  Las zzz.
    K4.Etiqueta {
        visible: self.durmiendo
        text: "z z"
        font.pixelSize: 12
        color: K4.Tema.apagado
        x: cuerpo.x + self.lado * 0.7
        y: cuerpo.y - 6

        SequentialAnimation on opacity {
            running: self.durmiendo
            loops: Animation.Infinite
            NumberAnimation { from: 0.15; to: 0.9; duration: 1300 }
            NumberAnimation { from: 0.9; to: 0.15; duration: 1300 }
        }
    }
}
