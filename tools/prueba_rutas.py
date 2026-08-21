#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Que ninguna ruta ajena salga a la red ni escriba donde no debe.

Dos agujeros reales, encontrados en la revisión del directorio de plugins de
Omarchy, y esta es la prueba que se queda para que no vuelvan:

1.  Un `.k4v` es JSON con rutas dentro y te lo pasan como te pasan un vídeo. Si
    una de esas rutas era `http://…`, abrir el proyecto hacía que ffmpeg pidiera
    esa dirección. Se comprobó con un servidor local: registró el GET con el
    user-agent de libavformat.

2.  El id de una capa de audio acababa dentro del nombre de la copia que oye la
    previa. Con `../` dentro, el fichero salía de la carpeta del proyecto — el
    FLAC apareció en /tmp.

Se mira el CÓDIGO y no sólo el comportamiento a propósito: lo que falla en esto
no es la llamada que había cuando se arregló, es la diecisiete que alguien
añade el mes que viene sin la lista blanca.

    python3 tools/prueba_rutas.py
"""

import io, os, re, sys

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

#  El mismo fichero vale en los dos repos: el editor vive en `Estado/` en
#  Omascreen y en `services/` en k4, y lo único que cambia es el nombre de la
#  carpeta. Manteniéndolo idéntico, un arreglo en uno se copia al otro tal cual.
QML = "Estado" if os.path.isdir(os.path.join(RAIZ, "Estado")) else "services"


def leer(rel):
    with io.open(os.path.join(RAIZ, rel), encoding="utf-8") as f:
        return f.read()


def sin_red(fallos):
    """Toda invocación de ffmpeg/ffprobe lleva la lista blanca de protocolos."""
    for rel in ("tools/editar.py", "tools/transcribir.py"):
        t = leer(rel)
        for m in re.finditer(r'\["(ffmpeg|ffprobe)"[,\]]', t):
            linea = t[:m.start()].count("\n") + 1
            #  o la trae pegada en la misma lista, o va por `SIN_RED` justo
            #  detrás del nombre del programa.
            trozo = t[m.start():m.start() + 240]
            if "SIN_RED" in trozo or "-protocol_whitelist" in trozo:
                continue
            fallos.append("%s:%d  %s sin lista blanca de protocolos"
                          % (rel, linea, m.group(1)))


def sondeos_con_reloj(fallos):
    """Ningún ffprobe puede quedarse esperando para siempre."""
    t = leer("tools/editar.py")
    for m in re.finditer(r'subprocess\.run\(\s*\["ffprobe"\]', t):
        fallos.append("tools/editar.py:%d  ffprobe sin tiempo de espera "
                      "(usa correr_sondeo)" % (t[:m.start()].count("\n") + 1))


def id_higienizado(fallos):
    """El id de una capa no entra crudo en un nombre de fichero."""
    t = leer(QML + "/Editor.qml")
    for m in re.finditer(r'"previa-"\s*\+\s*([A-Za-z0-9_.]+)', t):
        if "nombreSeguro" not in t[max(0, m.start() - 40):m.end() + 40]:
            fallos.append(QML + "/Editor.qml:%d  el id entra crudo en el "
                          "nombre del fichero (usa nombreSeguro)"
                          % (t[:m.start()].count("\n") + 1))
    if "nombreSeguro" not in t:
        fallos.append(QML + "/Editor.qml  falta nombreSeguro()")
    if "--dentro" not in leer(QML + "/EditorProcesos.qml"):
        fallos.append(QML + "/EditorProcesos.qml  la limpieza no dice "
                      "`--dentro`, así que nadie confina la salida")


def plan_revisado(fallos):
    """Cargar un plan comprueba sus rutas."""
    t = leer("tools/editar.py")
    if "revisar_rutas(plan" not in t:
        fallos.append("tools/editar.py  cargar() no llama a revisar_rutas()")
    q = leer(QML + "/Editor.qml")
    if "esRutaLocal(fuentes[0].ruta)" not in q:
        fallos.append(QML + "/Editor.qml  la ruta del plan se adopta sin "
                      "comprobar que es local")


def main():
    fallos = []
    for prueba in (sin_red, sondeos_con_reloj, id_higienizado, plan_revisado):
        prueba(fallos)
    if fallos:
        print("Rutas sin vigilar:\n")
        for f in fallos:
            print("  " + f)
        print("\n%d sitio(s)." % len(fallos))
        return 1
    print("Rutas: bien. Sin red, con reloj y dentro de su carpeta.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
