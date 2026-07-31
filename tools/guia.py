#!/usr/bin/env python3
"""Comprueba que la documentación diga la verdad.

    python3 tools/guia.py

`tools/api.py` ya vigila que ningún tipo de la API se quede sin mencionar. Eso
no basta: que un tipo esté NOMBRADO no garantiza que lo que se dice de él sea
cierto. Un miembro renombrado, un permiso que se fue, una orden de IPC que ya
no existe — la guía los sigue contando igual y nadie se entera hasta que
alguien la sigue al pie de la letra y no le funciona.

Esto comprueba lo que se puede comprobar de verdad:

  · cada `K4.Tipo.miembro` de la documentación existe en api/K4/Tipo.qml;
  · los permisos de la guía y los de tools/plugins.py son los mismos;
  · cada orden de IPC citada existe en algún IpcHandler;
  · cada opción `tools/X.py --opcion` la entiende ese guion;
  · cada fichero del repositorio que se cita existe.

Lo que NO comprueba —y conviene decirlo en vez de dar una falsa sensación de
red— es si una frase describe bien lo que hace el código. Eso solo lo caza
leerlo.
"""
from __future__ import annotations

import pathlib
import re
import sys

RAIZ = pathlib.Path(__file__).resolve().parent.parent
API = RAIZ / "api" / "K4"

#  Los documentos que hablan de la API y por tanto pueden mentir sobre ella.
DOCUMENTOS = ["docs/PLUGINS.md", "docs/API.md", "api/LEEME.md", "README.md",
              "docs/GAMES.md"]

#  Nombres que la documentación se INVENTA a propósito, porque está enseñando
#  a crear algo que todavía no existe. Hay que listarlos a mano: no hay forma
#  de distinguir «este fichero se renombró y la guía no se enteró» de «este
#  fichero te toca crearlo a ti» mirando el texto. La lista es corta y se ve de
#  un vistazo si crece de más.
INVENTADOS = {
    "services/MyGame.qml", "GameView.qml", "GamePlugin.qml", "Battle.qml",
    "Party.qml", "Achievements.qml", "Inventory.qml",
}

#  Lo que QtObject y compañía traen puesto: mencionarlo no es un error.
HEREDADOS = {"objectName", "parent", "children", "data", "width", "height",
             "x", "y", "z", "visible", "opacity", "enabled", "anchors",
             "implicitWidth", "implicitHeight", "text", "color", "font",
             "source", "status", "running", "interval", "repeat", "target"}


def miembros_de(tipo):
    """Lo que declara un tipo de la API: propiedades, funciones y señales."""
    f = API / (tipo + ".qml")
    if not f.is_file():
        return None
    texto = "\n".join(re.sub(r"//.*$", "", l) for l in f.read_text().split("\n"))
    salida = set()
    salida |= set(re.findall(r"\bproperty\s+(?:alias\s+)?[\w<>.]+\s+(\w+)", texto))
    salida |= set(re.findall(r"\breadonly\s+property\s+[\w<>.]+\s+(\w+)", texto))
    salida |= set(re.findall(r"\bfunction\s+(\w+)\s*\(", texto))
    salida |= set(re.findall(r"\bsignal\s+(\w+)", texto))
    #  Un tipo que solo reexporta otro (`IpcHandler {}`, `SoundEffect {}`)
    #  hereda todo lo suyo, y eso no está aquí para mirarlo: se marca para no
    #  dar por falsos miembros que sí existen.
    if re.search(r"^\s*(IconImage|IpcHandler|SoundEffect|GlobalShortcut|"
                 r"QsMenuOpener|LazyLoader|PamContext|WlSessionLock\w*)\s*\{",
                 texto, re.M):
        return None
    return salida


def revisar_miembros(doc, texto):
    fallos = []
    for tipo, miembro in re.findall(r"\bK4\.([A-Z]\w+)\.(\w+)", texto):
        declarados = miembros_de(tipo)
        if declarados is None:          # tipo desconocido o reexportación
            if not (API / (tipo + ".qml")).is_file():
                fallos.append(f"{doc}: K4.{tipo} no existe")
            continue
        if miembro not in declarados and miembro not in HEREDADOS:
            fallos.append(f"{doc}: K4.{tipo}.{miembro} no existe "
                          f"(api/K4/{tipo}.qml no lo declara)")
    return fallos


def revisar_permisos(doc, texto):
    """Los permisos que cita la guía contra los que el código comprueba."""
    import importlib.util
    spec = importlib.util.spec_from_file_location("p", RAIZ / "tools" / "plugins.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    reales = set(mod.PERMISOS)

    fallos = []
    #  Solo en la guía larga, que es la que lleva la tabla de permisos.
    if doc != "docs/PLUGINS.md":
        return fallos

    #  Contra la TABLA, no contra el texto suelto: al probarlo quité una fila
    #  y no se enteró, porque la palabra seguía apareciendo dos párrafos más
    #  arriba. Estar mencionado de pasada no es estar documentado — quien
    #  busca qué permisos hay mira la tabla.
    documentados = set(re.findall(r"^\| `(\w+)` \|", texto, re.M))
    for p in sorted(reales - documentados):
        fallos.append(f"{doc}: el permiso `{p}` existe y no está en la tabla")
    #  Y al revés: un permiso inventado en la guía manda a alguien a declarar
    #  algo que se rechazará como «permisos desconocidos».
    for p in sorted(documentados - reales):
        fallos.append(f"{doc}: la tabla cita el permiso `{p}` y no existe")
    return fallos


def ordenes_ipc():
    """Todas las funciones que publica algún IpcHandler, por objetivo."""
    salida = {}
    #  Los ejemplos cuentan: la guía enseña `k4.hola toggle` y eso tiene que
    #  seguir existiendo, que es justo lo que se copia y se pega.
    for f in (list((RAIZ / "plugins").rglob("*.qml"))
              + list((RAIZ / "ejemplos").rglob("*.qml"))
              + [RAIZ / "shell.qml"]):
        texto = f.read_text()
        for m in re.finditer(r'target:\s*"([\w.]+)"', texto):
            objetivo = m.group(1)
            #  Desde el target hasta el cierre del bloque, a ojo de llaves.
            resto = texto[m.end():]
            nivel, fin = 1, len(resto)
            for i, c in enumerate(resto):
                if c == "{":
                    nivel += 1
                elif c == "}":
                    nivel -= 1
                    if nivel == 0:
                        fin = i
                        break
            salida.setdefault(objetivo, set()).update(
                re.findall(r"\bfunction\s+(\w+)\s*\(", resto[:fin]))
    return salida


def revisar_ipc(doc, texto):
    ordenes = ordenes_ipc()
    fallos = []
    ids = {p.name for p in (RAIZ / "plugins").iterdir() if p.is_dir()}
    for objetivo, orden in re.findall(r"\bcall\s+(k4[\w.]*)\s+(\w+)", texto):
        conocidas = ordenes.get(objetivo)
        if conocidas is None:
            #  Un objetivo que no existe suele ser un ejemplo inventado
            #  («k4.hello»), y avisar de eso es ruido. Lo que sí importa es un
            #  objetivo REAL al que se le atribuyen órdenes que no tiene.
            continue
        if orden not in conocidas:
            fallos.append(f"{doc}: {objetivo} no tiene la orden {orden}")
    return fallos


def revisar_opciones(doc, texto):
    fallos = []
    for guion, opcion in re.findall(r"tools/(\w+\.py)\s+(--[\w-]+)", texto):
        f = RAIZ / "tools" / guion
        if not f.is_file():
            fallos.append(f"{doc}: no existe tools/{guion}")
        elif f'"{opcion}"' not in f.read_text():
            fallos.append(f"{doc}: tools/{guion} no entiende {opcion}")
    return fallos


def revisar_rutas(doc, texto):
    """Los ficheros y carpetas del repositorio que se citan, entre comillas."""
    fallos = []
    for cita in set(re.findall(r"`([\w./-]+\.(?:qml|py|json|md|tsv|lua|conf))`",
                               texto)):
        #  Sin barra es un nombre suelto —«plugin.json», «shell.qml»— y no una
        #  ruta del repositorio: comprobarlo daría por falso lo que solo es una
        #  forma de nombrar las cosas.
        if "/" not in cita or cita.startswith(("~", "/")) or "*" in cita:
            continue
        if cita in INVENTADOS:
            continue
        if not (RAIZ / cita).exists():
            fallos.append(f"{doc}: cita {cita}, que no existe")
    for cita in set(re.findall(r"`(ejemplos/\w+|plugins/\w+|api/K4|tools)/?`",
                               texto)):
        if not (RAIZ / cita).exists():
            fallos.append(f"{doc}: cita {cita}/, que no existe")
    return fallos


def main():
    fallos = []
    for doc in DOCUMENTOS:
        f = RAIZ / doc
        if not f.is_file():
            fallos.append(f"falta el documento {doc}")
            continue
        texto = f.read_text()
        fallos += revisar_miembros(doc, texto)
        fallos += revisar_permisos(doc, texto)
        fallos += revisar_ipc(doc, texto)
        fallos += revisar_opciones(doc, texto)
        fallos += revisar_rutas(doc, texto)

    if not fallos:
        print("%d documentos revisados, no le mienten al código."
              % len(DOCUMENTOS))
        return 0

    print("La documentación dice cosas que no son:\n")
    for x in fallos:
        print("  " + x)
    return 1


if __name__ == "__main__":
    sys.exit(main())
