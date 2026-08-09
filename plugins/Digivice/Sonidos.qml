//  El zumbador del aparato.
//
//  Un sitio y no catorce: los `K4.Sonido` se declaran aquí una vez y el
//  resto del plugin pide `Sonidos.sonar("golpe")`. Si estuvieran repartidos,
//  cada componente cargaría los suyos y el mismo pitido existiría tres veces
//  en memoria.
//
//  Son WAV a propósito: K4.Sonido los carga con SoundEffect, que los tiene en
//  memoria y los dispara sin latencia. Los formatos comprimidos pasan por
//  MediaPlayer, que abre el fichero al reproducir y llega tarde — en el golpe
//  de un combate eso se nota.
//
//  Los genera `tools/digivice_sonidos.py`: ondas cuadradas sintetizadas, no
//  grabaciones. Un juguete de LCD no tiene altavoz para más que eso, así que
//  la fidelidad y no usar nada de nadie apuntan al mismo sitio.

import QtQuick
import K4 as K4

Item {
    id: self

    //  Lo apaga el ajuste del plugin. Un juego que suena cuando no lo has
    //  pedido es un juego que se desinstala.
    property bool activo: true

    readonly property var nombres: [
        "boton", "elegir", "atras", "comer", "mimar", "curar",
        "evolucion", "golpe", "recibido", "victoria", "derrota", "limpiar",
        "acierto", "fallo", "llamada", "invocar", "estado", "moneda"
    ]

    property var _banco: ({})

    //  Cuántos han cargado de verdad. `K4.Sonido.listo` es la única forma de
    //  saberlo: un WAV que no se encuentra no da error, simplemente no suena.
    function diagnostico() {
        let ok = 0, mal = []
        for (let i = 0; i < nombres.length; ++i) {
            const s = _banco[nombres[i]]
            if (s && s.listo) ok += 1
            else mal.push(nombres[i])
        }
        if (mal.length === 0)
            return ok + "/" + nombres.length + " cargados"
        //  Al fallar sí interesa la ruta: casi siempre es que el fichero no
        //  está donde el plugin cree que está.
        const uno = _banco[mal[0]]
        return ok + "/" + nombres.length + " cargados · fallan: "
             + mal.join(", ") + " · ruta esperada: "
             + (uno ? uno.fuente : "(sin objeto)")
    }

    function sonar(nombre) {
        if (!activo)
            return
        const s = _banco[nombre]
        if (s)
            s.sonar()
    }

    Repeater {
        model: self.nombres

        //  Por `id` y no por `parent`: dentro de un delegado, el `parent` de
        //  un objeto no visual no es la celda, así que `parent.modelData`
        //  salía `undefined` y las catorce rutas acababan en
        //  «sonidos/undefined.wav». No daba ningún error: simplemente no
        //  sonaba nada, que es como fallan los WAV que no existen.
        Item {
            id: celda
            required property string modelData

            property var pieza: K4.Sonido {
                fuente: Qt.resolvedUrl("sonidos/" + celda.modelData + ".wav")
                volumen: 0.45
            }

            Component.onCompleted: {
                //  El objeto se reemplaza entero y no se muta: QML solo
                //  propaga cambios cuando cambia la IDENTIDAD de la property.
                const copia = Object.assign({}, self._banco)
                copia[celda.modelData] = celda.pieza
                self._banco = copia
            }
        }
    }
}
