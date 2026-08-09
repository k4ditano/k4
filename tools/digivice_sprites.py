#!/usr/bin/env python3
"""Elige QUÉ sprite usa cada especie del Digivice.

Wikimon guarda los sprites de todos los aparatos que ha habido, y de una
misma especie puede haber diez: el del Digital Monster del 97 (monocromo,
52x68), el del Vital Bracelet (color), el de un D-3, el de un Pendulum...
Esta herramienta decide cuál se queda en `datos/sprites.json`.

── por qué existe ────────────────────────────────────────────────────
La primera vez esto se hizo a mano y el script no se guardó. El resultado:
la lista de "aparatos en color" tenia SEIS entradas de las cincuenta y
cuatro que hay, y se coló monocromo en especies que sí tenían sprite en
color —`dark color`, `dv color`, `d3 color` y `ws`—. Sin el generador en el
repo no había forma de revisarlo ni de rehacerlo.

Y por eso el color NO se decide por el nombre del aparato. Se MIDE: se baja
un fichero de muestra por aparato y se cuenta qué proporción de sus píxeles
opacos tienen cromatismo. `dark color` suena a color y lo es (59 %); `dark`
suena parecido y es monocromo (0 %). Adivinar por el nombre es justo lo que
falló.

── uso ───────────────────────────────────────────────────────────────
    python3 tools/digivice_sprites.py --medir     # reclasifica aparatos
    python3 tools/digivice_sprites.py             # reelige y escribe
    python3 tools/digivice_sprites.py --seco      # solo dice qué cambiaría

Entrada:  plugins/Digivice/datos/sprites-fuentes.json  (todos los candidatos)
Salida:   plugins/Digivice/datos/sprites.json          (el elegido por especie)
Tabla:    plugins/Digivice/datos/sprites-aparatos.json (color medido)
"""

import argparse
import hashlib
import io
import json
import pathlib
import sys
import time
import urllib.request

RAIZ = pathlib.Path(__file__).resolve().parent.parent
DATOS = RAIZ / "plugins" / "Digivice" / "datos"
FUENTES = DATOS / "sprites-fuentes.json"
APARATOS = DATOS / "sprites-aparatos.json"
SALIDA = DATOS / "sprites.json"

BASE = "https://wikimon.net/images/"
AGENTE = "k4-digivice/1.0 (herramienta de mantenimiento; solo lectura)"

#  A partir de qué proporción de píxeles con cromatismo se considera color.
#  Los monocromos miden 0.0 clavado y los de color pasan del 40 %, así que
#  el umbral no está en una zona disputada: no hay ningún aparato entre 1 %
#  y 39 %.
UMBRAL = 0.15

#  Cuánto más grande que el destino puede ser un sprite. Los `*_color` son
#  arte de 64x64 subido a 3x (192x192) y se reducen bien; una ilustración de
#  512x512 no es un sprite de aparato y reducida queda papilla.
LADO_MAX = 256


def ruta_wiki(fichero):
    """MediaWiki reparte por el md5 del nombre: a/ab/Nombre.png."""
    f = fichero.replace(" ", "_")
    h = hashlib.md5(f.encode()).hexdigest()
    return f"{h[0]}/{h[:2]}/{f}"


def bajar(fichero):
    pet = urllib.request.Request(BASE + ruta_wiki(fichero),
                                 headers={"User-Agent": AGENTE})
    return urllib.request.urlopen(pet, timeout=25).read()


def cromatismo(datos):
    """Devuelve (proporción de píxeles con color, (ancho, alto))."""
    from PIL import Image
    im = Image.open(io.BytesIO(datos)).convert("RGBA")
    px = [p for p in im.getdata() if p[3] > 40]
    if not px:
        return 0.0, im.size
    con = sum(1 for r, g, b, _ in px if max(r, g, b) - min(r, g, b) > 28)
    return con / len(px), im.size


def medir(fuentes, muestras=2, espera=0.35):
    """Clasifica cada aparato bajando una muestra de sus ficheros."""
    porAparato = {}
    for cands in fuentes.values():
        for aparato, fichero in cands:
            porAparato.setdefault(aparato, []).append(fichero)

    tabla = {}
    for aparato in sorted(porAparato, key=lambda a: -len(porAparato[a])):
        vistos = []
        for fichero in porAparato[aparato][:muestras]:
            try:
                c, tam = cromatismo(bajar(fichero))
                vistos.append((c, tam))
            except Exception as e:                       # noqa: BLE001
                print(f"  ! {fichero}: {e}", file=sys.stderr)
            time.sleep(espera)
        if not vistos:
            continue
        c = max(v[0] for v in vistos)
        lado = max(max(v[1]) for v in vistos)
        tabla[aparato] = {"color": round(c, 3), "lado": lado,
                          "n": len(porAparato[aparato])}
        print(f"  {aparato:16} color {c * 100:5.1f}%  hasta {lado}px"
              f"  ({len(porAparato[aparato])} especies)")
    return tabla


def esColor(aparato, tabla):
    info = tabla.get(aparato)
    return bool(info) and info["color"] >= UMBRAL


def sirve(aparato, tabla):
    """¿Es un sprite de aparato y no otra cosa?

    Se descarta lo que mide más de `LADO_MAX` —`alysion` son ilustraciones
    de 512 px, y reducirlas da papilla, que es justo lo que evita usar
    sprites— y las artes de «cut-in»: son bustos de la pantalla del aparato,
    no el muñeco que anda, así que mezclarlas rompe el estilo.
    """
    info = tabla.get(aparato)
    if not info or info["lado"] > LADO_MAX:
        return False
    return "cutin" not in aparato


def elegir(cands, tabla, actual):
    """Conservador a propósito: SOLO se cambia un sprite monocromo por uno
    en color.

    La versión ambiciosa —«color primero y a igualdad el más grande»— tocaba
    170 especies, y entre ellas cambiaba sprites que ya estaban bien en color
    por otros de otro aparato, con otro estilo. Un arreglo que mueve ciento
    setenta cosas para corregir diecinueve no es un arreglo.
    """
    ahora = next((c for c in cands if ruta_wiki(c[1]) == actual), None)
    if ahora is not None and esColor(ahora[0], tabla):
        return ahora, 1

    mejores = [c for c in cands if esColor(c[0], tabla) and sirve(c[0], tabla)]
    if mejores:
        #  A igualdad de color, el más grande: son los `*_color` de 192 px,
        #  arte de 64x64 subido a 3x, y se reducen limpios.
        mejor = max(mejores, key=lambda c: tabla[c[0]]["lado"])
        return mejor, 1

    return (ahora or cands[0]), 0


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--medir", action="store_true",
                    help="rebaja muestras y reescribe la tabla de aparatos")
    ap.add_argument("--seco", action="store_true",
                    help="no escribe nada, solo dice qué cambiaría")
    args = ap.parse_args()

    if not FUENTES.exists():
        sys.exit(f"falta {FUENTES}: es la lista de candidatos por especie")
    fuentes = json.loads(FUENTES.read_text())["sprites"]

    if args.medir:
        print(f"midiendo aparatos ({len(fuentes)} especies de origen)…")
        tabla = medir(fuentes)
        if not args.seco:
            APARATOS.write_text(json.dumps(tabla, indent=1,
                                           ensure_ascii=False) + "\n")
            print(f"\nescrita {APARATOS.relative_to(RAIZ)}")
        return

    if not APARATOS.exists():
        sys.exit(f"falta {APARATOS}: lánzalo antes con --medir")
    tabla = json.loads(APARATOS.read_text())

    viejo = json.loads(SALIDA.read_text())
    antes = viejo["sprites"]

    nuevo, cambios = {}, []
    for especie, cands in fuentes.items():
        if not cands:
            continue
        prev = antes.get(especie)
        (aparato, fichero), color = elegir(cands, tabla,
                                           prev["r"] if prev else None)
        nuevo[especie] = {"r": ruta_wiki(fichero), "c": color}
        if prev and prev["r"] != nuevo[especie]["r"]:
            cambios.append((especie, prev, nuevo[especie], aparato))

    aColor = sum(1 for v in nuevo.values() if v["c"] == 1)
    print(f"{len(nuevo)} especies · {aColor} en color · "
          f"{len(nuevo) - aColor} monocromas")
    print(f"cambian {len(cambios)}:")
    for especie, prev, ahora, aparato in cambios[:40]:
        print(f"   {especie:6} {prev['r'].split('/')[-1]:34}"
              f" → {ahora['r'].split('/')[-1]} ({aparato})")
    if len(cambios) > 40:
        print(f"   … y {len(cambios) - 40} más")

    if args.seco:
        return
    viejo["sprites"] = nuevo
    SALIDA.write_text(json.dumps(viejo, indent=1, ensure_ascii=False) + "\n")
    print(f"\nescrita {SALIDA.relative_to(RAIZ)}")


if __name__ == "__main__":
    main()
