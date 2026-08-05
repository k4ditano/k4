#!/usr/bin/env python3
"""Comprueba que nadie se coloque a mano dentro de un layout.

    python3 tools/layouts.py

Un QQuickLayout —RowLayout, ColumnLayout, GridLayout, StackLayout— gobierna la
geometría de todos sus hijos visibles: les pone x, y, width y height él. Un hijo
directo que se los ponga por su cuenta, o que se ancle, no consigue nada: el
layout lo pisa en cuanto dispone la fila. Y si además no tiene tamaño implícito
—un MouseArea no lo tiene— la celda sale de cero y el elemento acaba midiendo
0×0.

Eso no se ve. No hay error, no hay hueco raro en pantalla, no falta nada: solo
que ese trozo deja de responder. Pasó tres veces en la barra antes de que se
buscara el patrón:

  · la píldora de la mazmorra no se podía pulsar, y el clic seguía hasta el
    fondo de la island, que abre el centro de control — o sea que hacía algo,
    solo que no lo suyo;
  · el botón de parar la grabación tampoco respondía, con el mismo código
    copiado;
  · y las tres acciones de una imagen del Ask —ampliar, guardar, abrir— ni se
    iluminaban al pasar el ratón ni hacían nada al pulsarlas.

Los dos primeros llevaban encima un comentario explicando que se habían quitado
los anchors porque Qt avisaba en cada arranque. El aviso se calló y el fallo se
quedó: el problema nunca fue la forma de colocarse sino quién manda. Un
comentario no comprueba nada, y por eso esto es una herramienta.

Lo que se pide en su lugar: Layout.preferredWidth y compañía para las medidas,
Layout.alignment para la colocación, y si de verdad hace falta anclar algo
—un MouseArea que cubra la fila entera, por ejemplo— entonces la fila va dentro
de un Item que se mida por ella y el elemento anclado se cuelga del Item, que
es quien no está gobernado por nadie.

Lo que esto NO mira, para que su cero no se lea como una garantía que no da:
solo hijos DIRECTOS de un layout. Un hijo sin tamaño implícito que espere que
alguien se lo dé, o uno que se cambie el `parent` visual a mano, se le escapan.
"""
import pathlib, re, sys

RAIZ = pathlib.Path(__file__).resolve().parent.parent

LAYOUTS = ("RowLayout", "ColumnLayout", "GridLayout", "StackLayout")

#  Lo que decide el layout y por tanto no puede fijar el hijo.
#
#  Sin «^» a propósito: `match()` ya ancla en la posición que se le pasa, y el
#  ancla de verdad solo casa en el principio de la CADENA. La primera versión de
#  esto lo llevaba y no casaba nunca nada: daba cero en un repo que tenía ocho.
GEOM = re.compile(r"(x|y|width|height|anchors)\s*[:.]")

#  Un elemento: `Tipo {`, admitiendo nombres cualificados como `K4.Process`.
ELEM = re.compile(r"([A-Z][A-Za-z0-9_]*(?:\.[A-Z][A-Za-z0-9_]*)*)\s*\{")


def sin_ruido(texto):
    """El fichero con comentarios y cadenas en blanco, del mismo largo.

    Llevan llaves y dos puntos dentro, que es justo lo que aquí se cuenta. Se
    sustituyen por espacios en vez de quitarse para que las posiciones sigan
    valiendo y los números de línea salgan bien.
    """
    salida, i, n = [], 0, len(texto)
    while i < n:
        c = texto[i]
        if c == "/" and i + 1 < n and texto[i + 1] == "/":
            j = texto.find("\n", i)
            j = n if j < 0 else j
        elif c == "/" and i + 1 < n and texto[i + 1] == "*":
            j = texto.find("*/", i + 2)
            j = n if j < 0 else j + 2
        elif c in "\"'":
            j = i + 1
            while j < n and texto[j] != c:
                j += 2 if texto[j] == "\\" else 1
            j = min(j + 1, n)
        else:
            salida.append(c)
            i += 1
            continue
        salida.append(" " * (j - i))
        i = j
    return "".join(salida)


def revisar(texto):
    """Los sitios donde un hijo directo de un layout se coloca a mano."""
    limpio = sin_ruido(texto)
    pila, prof, avisos = [], 0, []
    i, n = 0, len(limpio)

    while i < n:
        c = limpio[i]

        if c == "{":
            #  De quién es esta llave: el último `Tipo {` que acabe justo aquí.
            tipo = None
            for m in ELEM.finditer(limpio, max(0, i - 160), i + 1):
                if m.end() == i + 1:
                    tipo = m.group(1)
            prof += 1
            pila.append((tipo, prof))
            i += 1
            continue

        if c == "}":
            if pila and pila[-1][1] == prof:
                pila.pop()
            prof -= 1
            i += 1
            continue

        #  ¿Empieza aquí una sentencia, y es de las que decide el layout?
        if c.isalpha() and (i == 0 or limpio[i - 1] in "\n\t ;{"):
            m = GEOM.match(limpio, i)
            if m:
                if len(pila) >= 2 and pila[-1][0] and pila[-2][0] in LAYOUTS:
                    linea = texto.count("\n", 0, i) + 1
                    avisos.append((linea, pila[-2][0], pila[-1][0], m.group(1)))
                i = m.end()
                continue

        i += 1

    return avisos


#  Un caso roto de verdad, de los que costaron el arreglo. Está aquí y no en un
#  fichero aparte porque una comprobación que puede dar un cero falso tiene que
#  demostrar que sabe encontrar algo ANTES de que su cero valga.
CONTROL = """
import QtQuick
import QtQuick.Layouts

RowLayout {
    id: indicador
    spacing: 4

    Text { text: "hola"; Layout.alignment: Qt.AlignVCenter }

    MouseArea {
        x: -3
        y: -3
        width: indicador.width + 6
        height: indicador.height + 6
        onClicked: indicador.abrir()
    }
}
"""


def autocomprobar():
    """Que el detector detecta. Devuelve el motivo si no, o None si va bien."""
    salida = revisar(CONTROL)
    fijadas = sorted(set(p for _, _, _, p in salida))
    if fijadas != ["height", "width", "x", "y"]:
        return ("el caso de control tenía que dar x, y, width y height, y dio: "
                + (", ".join(fijadas) if fijadas else "nada"))
    return None


def main():
    fallo = autocomprobar()
    if fallo:
        print("La comprobación está rota:", fallo)
        print("\nSu «0 sitios» no significaría nada, así que no se da por buena.")
        return 1

    ficheros = sorted(RAIZ.rglob("*.qml"))
    todos = []
    for ruta in ficheros:
        if ".git" in ruta.parts:
            continue
        for linea, layout, hijo, prop in revisar(ruta.read_text(encoding="utf-8")):
            todos.append((ruta.relative_to(RAIZ), linea, layout, hijo, prop))

    if not todos:
        print("%d ficheros revisados, nadie se coloca a mano dentro de un layout."
              % len(ficheros))
        return 0

    print("Hay %d sitios colocándose a mano dentro de un layout:\n" % len(todos))
    for ruta, linea, layout, hijo, prop in todos:
        print("  %s:%d  %s dentro de %s fija «%s»" % (ruta, linea, hijo, layout, prop))
    print("\nEl layout gobierna la geometría de sus hijos: eso no se aplica, y")
    print("sin tamaño implícito el elemento acaba midiendo 0×0 —deja de")
    print("responder sin dar un solo error—. Se usa Layout.preferredWidth y")
    print("Layout.alignment; y si hace falta anclar de verdad, la fila va")
    print("dentro de un Item que se mida por ella y lo anclado cuelga del Item.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
