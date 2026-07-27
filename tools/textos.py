#!/usr/bin/env python3
"""Herramienta de traducción de k4.

Tres órdenes, y ninguna necesita saber QML:

    textos.py plantilla     rehace traducciones/plantilla.json con todas las
                            cadenas que hay ahora en la interfaz
    textos.py estado        dice cuánto lleva traducido cada idioma y qué falta
    textos.py envolver      envuelve en Idioma.t(...) las cadenas que aún están
                            sueltas en el código (--seco para solo mirar)

La clave de cada texto es el propio texto en español. Suena raro hasta que se
piensa en la alternativa: con 422 cadenas repartidas por 70 ficheros, inventar
un identificador para cada una es mucho trabajo, se desincroniza sola y deja al
traductor mirando etiquetas en vez de frases. Así, además, lo que no esté
traducido sale en español en vez de salir roto.
"""

import json
import os
import re
import sys

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TRADUCCIONES = os.path.join(RAIZ, "traducciones")
CARPETAS = ["core", "widgets", "services", "plugins"]

# Propiedades cuyo valor ve el usuario. Deliberadamente corta: `id`, `command`,
# `source` y compañía llevan cadenas que NO se traducen, y meterlas rompería
# el programa en cuanto alguien tradujera un identificador.
# `etiqueta` queda fuera aunque se vea: en el portapapeles se compara
# contra "enlace", "color"… para elegir el icono, así que traducirla
# rompería la lógica. Esas salen de los guiones de Python y se
# traducen allí.
PROPIEDADES = ("text", "nombre", "desc", "papel", "titulo", "grupo", "title")

RE_SUELTA = re.compile(
    r'\b(' + "|".join(PROPIEDADES) + r')\s*:\s*"([^"\\]{2,})"')
RE_ENVUELTA = re.compile(
    r'\b(' + "|".join(PROPIEDADES) + r')\s*:\s*Idioma\.t\(\s*"([^"\\]+)"\s*\)')

# Lo que parece texto pero no lo es.
def traducible(s):
    if len(s.strip()) < 2:
        return False
    if not re.search(r'[A-Za-zÁÉÍÓÚÑáéíóúñü]', s):
        return False
    # rutas, órdenes de shell, identificadores y formatos de fecha
    if re.match(r'^[a-z0-9_.\-/]+$', s) and " " not in s:
        return False
    if s.startswith("/") or s.startswith("~") or s.startswith("assets/"):
        return False
    if re.match(r'^[dMyHhms:\s]+$', s):
        return False
    return True


# ── segundo barrido: los textos que viven dentro de una expresión ──
#
#  La mitad de la interfaz no dice `text: "Hola"` sino
#      text: algo ? "Hola" : "Adiós"
#  o concatena trozos en varias líneas. Con solo el patrón simple se escapaban
#  359 de 411 cadenas, así que hace falta seguir la expresión entera: empieza
#  en la línea del `text:` y sigue mientras la anterior quede a medias.

RE_ABRE = re.compile(r'\b(' + "|".join(PROPIEDADES) + r')\s*:')
RE_CADENA = re.compile(r'"([^"\\]{2,})"')
COLGANDO = ("?", ":", "+", "(", "&&", "||", ",", "=")


def bloques_de_texto(lineas):
    """Índices de las líneas que forman parte de un binding de texto.

    Se decide mirando la línea SIGUIENTE, no la actual: en QML un ternario se
    parte dejando el `:` al principio del renglón de abajo, así que la de
    arriba termina en algo que parece completo. Mirando solo hacia atrás se
    escapaban tres de las cuatro ramas de cada ternario.
    """
    def limpia(x):
        return x.split("//")[0].rstrip()

    def continua(x):
        t = limpia(x).lstrip()
        return t.startswith(("?", ":", "+", "&&", "||", "."))

    dentro = set()
    i = 0
    n = len(lineas)

    while i < n:
        actual = limpia(lineas[i])
        if not RE_ABRE.search(actual):
            i += 1
            continue

        dentro.add(i)

        # `text: {` … `}`: se sigue por llaves hasta cerrar
        if actual.rstrip().endswith("{"):
            hondo = actual.count("{") - actual.count("}")
            j = i + 1
            while j < n and hondo > 0:
                dentro.add(j)
                hondo += limpia(lineas[j]).count("{") - limpia(lineas[j]).count("}")
                j += 1
            i = j
            continue

        # expresión partida en varias líneas
        j = i + 1
        while j < n and continua(lineas[j]):
            dentro.add(j)
            j += 1
        i = j

    return dentro


def ficheros():
    for carpeta in CARPETAS:
        base = os.path.join(RAIZ, carpeta)
        for raiz, _, nombres in os.walk(base):
            for n in sorted(nombres):
                if n.endswith(".qml"):
                    yield os.path.join(raiz, n)


def recolectar():
    """Todas las cadenas de la interfaz, envueltas o no, con dónde salen."""
    encontradas = {}
    for ruta in ficheros():
        try:
            texto = open(ruta, encoding="utf-8").read()
        except OSError:
            continue
        rel = os.path.relpath(ruta, RAIZ)
        lineas = texto.split("\n")
        for i in bloques_de_texto(lineas):
            for m in RE_CADENA.finditer(lineas[i].split("//")[0]):
                s = m.group(1)
                if traducible(s):
                    encontradas.setdefault(s, set()).add(rel)
    return encontradas


def plantilla():
    encontradas = recolectar()
    os.makedirs(TRADUCCIONES, exist_ok=True)

    datos = {
        "_meta": {
            "idioma": "PLANTILLA",
            "codigo": "xx",
            "traducido por": "",
            "cómo": "Copia este fichero a <código>.json, rellena cada valor "
                    "y mándalo por GitHub. Deja vacío lo que no sepas: sale "
                    "en español y no rompe nada.",
        }
    }
    for s in sorted(encontradas):
        datos[s] = ""

    ruta = os.path.join(TRADUCCIONES, "plantilla.json")
    with open(ruta, "w", encoding="utf-8") as f:
        json.dump(datos, f, ensure_ascii=False, indent=1)
        f.write("\n")

    print(f"{len(encontradas)} cadenas -> {os.path.relpath(ruta, RAIZ)}")


def estado():
    encontradas = recolectar()
    total = len(encontradas)
    print(f"{total} cadenas en la interfaz\n")

    for n in sorted(os.listdir(TRADUCCIONES)) if os.path.isdir(TRADUCCIONES) else []:
        if not n.endswith(".json") or n == "plantilla.json":
            continue
        ruta = os.path.join(TRADUCCIONES, n)
        try:
            d = json.load(open(ruta, encoding="utf-8"))
        except Exception:
            print(f"  {n}: ilegible")
            continue

        meta = d.pop("_meta", {})
        hechas = sum(1 for k in encontradas if d.get(k))
        sobran = [k for k in d if k not in encontradas]
        pct = hechas / total * 100 if total else 0
        print(f"  {n:12s} {meta.get('idioma', '?'):12s} "
              f"{hechas:4d}/{total}  {pct:5.1f}%"
              + (f"   ({len(sobran)} ya no se usan)" if sobran else ""))


def envolver(seco=False):
    """Deja las cadenas sueltas listas para traducirse."""
    tocados = 0
    cambios = 0

    for ruta in ficheros():
        try:
            texto = open(ruta, encoding="utf-8").read()
        except OSError:
            continue

        # El propio servicio de idioma no se envuelve a sí mismo.
        if os.path.basename(ruta) == "Idioma.qml":
            continue

        lineas = texto.split("\n")
        dentro = bloques_de_texto(lineas)

        def sustituir(m):
            nonlocal cambios
            s = m.group(1)
            if not traducible(s):
                return m.group(0)
            cambios += 1
            return 'Idioma.t("%s")' % s

        for i in sorted(dentro):
            codigo = lineas[i].split("//")[0]
            resto = lineas[i][len(codigo):]
            # lo ya envuelto no se vuelve a envolver
            if "Idioma.t(" in codigo:
                trozos = re.split(r'(Idioma\.t\(\s*"[^"]*"\s*\))', codigo)
                codigo = "".join(x if x.startswith("Idioma.t(")
                                 else RE_CADENA.sub(sustituir, x) for x in trozos)
            else:
                codigo = RE_CADENA.sub(sustituir, codigo)
            lineas[i] = codigo + resto

        nuevo = "\n".join(lineas)
        if nuevo == texto:
            continue

        # Hace falta el import de los servicios para poder llamar a Idioma.
        if 'import "../../services"' not in nuevo and 'import "../services"' not in nuevo \
                and "pragma Singleton" not in nuevo:
            rel = os.path.relpath(ruta, RAIZ)
            hondo = rel.count(os.sep)
            subida = "../" * hondo
            marca = 'import QtQuick\n'
            if marca in nuevo:
                nuevo = nuevo.replace(marca, marca + 'import "%sservices"\n' % subida, 1)

        tocados += 1
        if not seco:
            open(ruta, "w", encoding="utf-8").write(nuevo)

    print(("(en seco) " if seco else "") +
          f"{cambios} cadenas envueltas en {tocados} ficheros")


def main():
    orden = sys.argv[1] if len(sys.argv) > 1 else "estado"
    if orden == "plantilla":
        plantilla()
    elif orden == "envolver":
        envolver("--seco" in sys.argv)
    else:
        estado()


if __name__ == "__main__":
    main()
