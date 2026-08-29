pragma Singleton

//  Las extensiones de flanco de la píldora: la cápsula creciendo hacia un
//  borde de la pantalla, con el nombre de lo que un plugin tenga entre manos.
//
//  Esto es la mitad ÁRBITRA de una API pública. Un plugin no toca nunca la
//  geometría de la píldora: declara su extensión por `K4.Capsula` y a partir
//  de ahí manda este servicio — mide el texto con la fuente de la propia
//  píldora, capa el ancho por el `largoMaximo` que pida el plugin Y por el
//  hueco que quede hasta el borde de la pantalla, y publica lo que ha ganado
//  cada flanco. La vista de reposo reserva ese hueco, el host ancla la island
//  para que el cuerpo de la píldora no se mueva, y widgets/ZonaExtension.qml
//  las pinta.
//
//  Por qué un servicio y no la cuenta de cada plugin: la píldora es UNA y sus
//  contribuyentes son muchos. Los indicadores ya se arbitran así —K4.Pildora →
//  Indicadores → PluginPildora— para las cápsulas pequeñas de dentro; esto es
//  la misma idea para los flancos, donde el ancho no es cosmético porque mueve
//  la island.

import QtQuick
import Quickshell
import "../core"

Singleton {
    id: extensiones

    //  [{ id, lado, texto, glifo, color, largoMaximo, visible, abrazo }]
    //
    //  `id` es el del plugin dueño: una extensión por plugin, y volver a
    //  registrarse reemplaza a la anterior. El orden de registro es el de
    //  pintado dentro de un mismo lado.
    property var lista: []

    //  La fuente de la propia píldora, para que «abrazar el texto» abrace el
    //  texto. La zona se pinta a 12 px Medium, y medir a cualquier otra cosa
    //  recorta nombres que caben: medido en Normal y pintado en Medium, los
    //  nombres salían con puntos suspensivos sobrándoles sitio.
    readonly property var metro: TextMetrics {
        font.family: Theme.uiFont
        font.pixelSize: 12
        font.weight: Font.Medium
    }

    //  Lo que ocupa una extensión aparte de su texto: el glifo, el hueco hasta
    //  el texto, la separación con lo demás de la fila, y un poco de holgura
    //  —el hinting puede pintar un pelo más ancho que el avance, y un nombre
    //  que cabe no puede salir recortado por un píxel—.
    readonly property int adornos: 14 + 6 + 8 + 4

    //  El abrazo, medido UNA VEZ al registrar y JAMÁS dentro de una binding.
    //  Escribir `metro.text` mientras una binding se evalúa es un bucle: la
    //  escritura notifica, el avance se vuelve a leer y la binding corre otra
    //  vez. `registrar()` y `actualizar()` son llamadas imperativas desde
    //  manejadores, así que ahí medir es seguro; las bindings de abajo solo
    //  LEEN lo ya medido.
    function medir(texto) {
        metro.text = String(texto || "")
        return Math.ceil(metro.advanceWidth) + adornos
    }

    //  Lo que ocupa una extensión: su abrazo, capado dos veces —por el
    //  `largoMaximo` del plugin y por el hueco que queda hasta el borde de la
    //  pantalla—. Una píldora aparcada en un extremo (alineación 15 u 85)
    //  tiene menos sitio que el máximo por ese lado, y una extensión que se
    //  saliera de la pantalla sería una mentira. Los ~220 son medio cuerpo de
    //  píldora, las alas y un margen.
    function anchoDe(item) {
        const frac = item.lado === "izquierda"
            ? Settings.alineacionBarra / 100
            : 1 - Settings.alineacionBarra / 100
        const hueco = Math.max(0, Math.round(Island.anchoPantalla * frac - 220))
        const tope = Number(item.largoMaximo) > 0
            ? Math.ceil(Number(item.largoMaximo)) : 300
        return Math.max(0, Math.min(Number(item.abrazo) || 0, tope, hueco))
    }

    //  Lo que ha ganado cada flanco en total. Bindings y no funciones: el
    //  plugin de reposo reserva a partir de esto, y tiene que volver a
    //  contarlo cuando cambie la alineación o se repiense un monitor — las
    //  lecturas de dentro de `anchoDe()` dejan puesta esa dependencia gratis.
    readonly property int anchoIzquierdo: suma("izquierda")
    readonly property int anchoDerecho: suma("derecha")

    function suma(lado) {
        let total = 0
        for (let i = 0; i < lista.length; ++i)
            if (lista[i].lado === lado && lista[i].visible !== false)
                total += anchoDe(lista[i])
        return total
    }

    function registrar(dueno, campos) {
        if (!dueno || String(dueno).length === 0 || !campos)
            return
        const item = {
            id: String(dueno),
            lado: campos.lado === "izquierda" ? "izquierda" : "derecha",
            texto: String(campos.texto || ""),
            glifo: Number(campos.glifo) || 0,
            color: campos.color !== undefined ? campos.color : null,
            largoMaximo: campos.largoMaximo,
            visible: campos.visible !== false,
            abrazo: medir(campos.texto)
        }
        lista = lista.filter(function (x) { return x.id !== item.id })
            .concat([item])
    }

    function actualizar(dueno, campos) {
        lista = lista.map(function (x) {
            if (x.id !== String(dueno))
                return x
            const d = Object.assign({}, x, campos)
            if (campos.texto !== undefined)
                d.abrazo = medir(campos.texto)
            return d
        })
    }

    function quitar(dueno) {
        lista = lista.filter(function (x) { return x.id !== String(dueno) })
    }
}
