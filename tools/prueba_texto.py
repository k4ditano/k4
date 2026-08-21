#!/usr/bin/env python3
"""Que ningún texto de la interfaz pueda ejecutarse.

Un `Text` de QML usa `AutoText` de fábrica: husmea la cadena y, si le parece
marcado, la INTERPRETA. Por la barra pasa constantemente texto que no escribe el
usuario ni nosotros: el cuerpo de una notificación —lo manda cualquier
aplicación—, lo que hay en el portapapeles, el título de una ventana, el nombre
de una canción, el de un fichero. Una notificación cuyo cuerpo sea
`<img src="http://…">` no se leería: QML montaría la imagen y saldría a la red a
pedirla, que es una baliza de lectura servida por la propia barra.

Medido: `<img src="x.png" width=400 height=60>` mide 475x60 con AutoText —la
caja de la imagen— y 440x19 con PlainText, que es el texto tal cual. Y
`<b>hola</b>` mide 39 contra 113.

Esta prueba falla si aparece un sumidero de texto sin `textFormat` declarado.
Existe porque el arreglo es de una línea y el olvido no avisa: no se rompe nada,
solo deja de ser literal.

Quien quiera texto rico A PROPÓSITO lo dice —`textFormat: TextEdit.MarkdownText`
en el panel de respuestas de Ask— y entonces esta prueba lo da por bueno: lo que
persigue no es el formato, es el silencio.
"""

import os
import re
import sys

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CARPETAS = ["core", "widgets", "services", "plugins", os.path.join("api", "K4")]

#  Los que heredan de Text y husmean el marcado. `TextInput` no: siempre plano.
ABRE = re.compile(r'(?<![A-Za-z_.])(Text|TextEdit)\s*\{')


def cuerpo(texto, i):
    """El cuerpo del bloque que abre en `i`, contando llaves."""
    hondo, j = 0, i
    while j < len(texto):
        if texto[j] == "{":
            hondo += 1
        elif texto[j] == "}":
            hondo -= 1
            if hondo == 0:
                return texto[i:j]
        j += 1
    return texto[i:]


def qmls():
    for carpeta in CARPETAS:
        d = os.path.join(RAIZ, carpeta)
        for base, _, ficheros in os.walk(d):
            for n in sorted(ficheros):
                if n.endswith(".qml"):
                    yield os.path.join(base, n)


def main():
    fallos, mirados = [], 0
    for ruta in qmls():
        texto = open(ruta, encoding="utf-8").read()
        #  Sin comentarios: un `Text {` citado en una explicación no cuenta.
        limpio = re.sub(r'//[^\n]*', '', texto)
        for m in ABRE.finditer(limpio):
            mirados += 1
            if "textFormat" not in cuerpo(limpio, m.end() - 1):
                fallos.append("%s:%d" % (os.path.relpath(ruta, RAIZ),
                                         limpio[:m.start()].count("\n") + 1))

    if fallos:
        print("%d sumideros de texto sin `textFormat`:\n" % len(fallos))
        for f in fallos:
            print("  " + f)
        print("\nPonles `textFormat: Text.PlainText`, o el que quieran a"
              " propósito.")
        return 1
    print("%d sumideros de texto revisados, todos dicen su formato." % mirados)
    return 0


if __name__ == "__main__":
    sys.exit(main())
