#!/usr/bin/env python3
"""Búsqueda de ficheros para el módulo de la island.

El motor es `fd`, no `plocate`, y no por gusto: medido en este equipo, el
índice de plocate no contiene ni una ruta del home —consultarlo por ficheros
propios devuelve cero—, y además es una foto que se rehace cada tantas horas,
así que lo que acabas de guardar no aparece. `fd` recorre los 187.000 ficheros
del home en 50 ms y siempre está al día.

Dos banderas que no son opcionales: `--hidden` y `--no-ignore`. Sin ellas fd se
salta lo oculto y lo que esté en un .gitignore, que en un home es justo donde
vive media vida —todo ~/.config, para empezar—. Sin ellas la misma búsqueda
devolvía cero resultados.

    buscar.py <consulta> [--ambito home|sistema] [--tope N] [--solo dir|archivo]

Saca JSON: cada resultado con su ruta, nombre, tamaño, fecha y una puntuación
de lo bien que encaja, ya ordenado.
"""

import json
import os
import subprocess
import sys
import time

TOPE = 60
# Ni el ruido de las cachés ni los árboles de dependencias: llenan la lista de
# cosas que nadie busca por su nombre.
EXCLUIR = [
    "node_modules", ".git", ".cache", "__pycache__", ".venv", "venv",
    ".npm", ".cargo/registry", ".rustup", ".local/share/Trash",
    ".mozilla/firefox/*/cache2", ".steam", "Steam/steamapps",
]

CARPETAS_SISTEMA = ["/usr", "/etc", "/opt", "/srv", "/var/log"]


def ejecutar(consulta, ambito, tope, solo):
    orden = ["fd", "--hidden", "--no-ignore", "--absolute-path",
             "--max-results", str(tope * 4), "--ignore-case"]

    for patron in EXCLUIR:
        orden += ["--exclude", patron]

    if solo == "dir":
        orden += ["--type", "directory"]
    elif solo == "archivo":
        orden += ["--type", "file"]

    orden.append(consulta)

    if ambito == "sistema":
        orden += CARPETAS_SISTEMA
    else:
        orden.append(os.path.expanduser("~"))

    try:
        r = subprocess.run(orden, capture_output=True, text=True, timeout=8)
    except Exception:
        return []
    return [l for l in r.stdout.split("\n") if l.strip()]


def puntuar(ruta, consulta):
    """Lo que mejor encaja, arriba.

    Se mira solo el nombre del fichero, no la ruta entera: si buscas «informe»
    interesa `informe.pdf`, no cualquier cosa dentro de una carpeta que se
    llame así. La ruta larga penaliza un poco, que suele ser cosa enterrada.
    """
    nombre = os.path.basename(ruta).lower()
    q = consulta.lower()
    if not q:
        return 0

    if nombre == q:
        base = 1000
    elif os.path.splitext(nombre)[0] == q:
        base = 900
    elif nombre.startswith(q):
        base = 700
    elif q in nombre:
        base = 500
    else:
        base = 200                      # solo encajaba en la ruta

    return base - min(200, ruta.count("/") * 8)


def describir(ruta, consulta):
    try:
        st = os.lstat(ruta)
    except OSError:
        return None

    carpeta = os.path.isdir(ruta)
    return {
        "ruta": ruta,
        "nombre": os.path.basename(ruta) or ruta,
        "carpeta": os.path.dirname(ruta),
        "esCarpeta": carpeta,
        "extension": "" if carpeta else os.path.splitext(ruta)[1].lstrip(".").lower(),
        "bytes": 0 if carpeta else st.st_size,
        "cuando": st.st_mtime,
        "punto": puntuar(ruta, consulta),
    }


def main():
    args = sys.argv[1:]
    consulta = ""
    ambito = "home"
    tope = TOPE
    solo = ""

    i = 0
    while i < len(args):
        a = args[i]
        if a == "--ambito" and i + 1 < len(args):
            ambito = args[i + 1]; i += 2
        elif a == "--tope" and i + 1 < len(args):
            tope = int(args[i + 1]); i += 2
        elif a == "--solo" and i + 1 < len(args):
            solo = args[i + 1]; i += 2
        else:
            consulta = a; i += 1

    if len(consulta.strip()) < 2:
        print(json.dumps({"resultados": [], "consulta": consulta}), flush=True)
        return

    inicio = time.time()
    rutas = ejecutar(consulta, ambito, tope, solo)

    salida = []
    for r in rutas:
        # fd termina las carpetas en barra: sin quitarla, basename devuelve
        # cadena vacía y la carpeta se queda sin nombre y sin puntuación
        r = r.rstrip("/") or "/"
        d = describir(r, consulta)
        if d:
            salida.append(d)

    # primero lo que mejor encaja y, a igualdad, lo más reciente
    salida.sort(key=lambda d: (-d["punto"], -d["cuando"]))

    print(json.dumps({
        "consulta": consulta,
        "ambito": ambito,
        "ms": round((time.time() - inicio) * 1000),
        "total": len(salida),
        "resultados": salida[:tope],
    }), flush=True)


if __name__ == "__main__":
    try:
        main()
    except (KeyboardInterrupt, BrokenPipeError):
        sys.exit(0)
