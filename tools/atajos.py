#!/usr/bin/env python3
"""Lee los atajos de teclado configurados en Hyprland.

La fuente es el propio fichero de configuración y no `hyprctl binds`, y no por
comodidad: con configuración en Lua, hyprctl informa de todos los atajos con
`dispatcher: __lua` y `arg: 6`, o sea, la tecla sí pero no qué hace; y encima
su salida en JSON viene malformada en esta versión —las claves y los valores
salen desparejados—. El fichero, en cambio, dice exactamente qué hace cada uno
y viene ya agrupado por secciones con los comentarios que escribiste.

    atajos.py

Saca JSON con la lista, cada atajo con su combinación, lo que hace y a qué
sección pertenece.
"""

import json
import os
import re
import sys

CONFIG = os.path.expanduser("~/.config/hypr/config")
BINDS = os.path.join(CONFIG, "binds.lua")

RE_LOCAL = re.compile(r'^\s*local\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*"([^"]*)"')
RE_GLOBAL = re.compile(r'^\s*([A-Z_][A-Z0-9_]*)\s*=\s*"([^"]*)"')
RE_NUM = re.compile(r'^\s*([A-Z_][A-Z0-9_]*)\s*=\s*(\d+)')
RE_BIND = re.compile(r'hl\.bind\s*\(\s*(.+)$')
RE_FOR = re.compile(r'^\s*for\s+(\w+)\s*=\s*(\w+)\s*,\s*(\w+)\s*do')
# Dentro del bucle se suele hacer `local key = i % 10` y luego atar con `key`:
# sin seguir ese alias, la combinación salía literalmente como «+ key».
RE_ALIAS = re.compile(r'^\s*local\s+(\w+)\s*=\s*.*\b%s\b')

# Lo que hace cada despachador, en cristiano. Los que no estén salen con su
# nombre limpio, que sigue diciendo bastante.
VERBOS = {
    "window.close": "Cerrar la ventana",
    "window.fullscreen": "Pantalla completa",
    "window.float": "Flotar o anclar la ventana",
    "window.move": "Mover la ventana",
    "window.resize": "Redimensionar",
    "window.cycle_next": "Siguiente ventana",
    "window.pin": "Fijar la ventana",
    "window.pseudo": "Modo pseudo",
    "focus": "Cambiar el foco",
    "workspace": "Ir al espacio de trabajo",
    "layout": "Cambiar la disposición",
    "exit": "Salir de Hyprland",
    "kill": "Matar una ventana",
    "exec_cmd": "",              # se resuelve con el propio comando
}


def variables():
    """Todo lo que haga falta para reconstruir las cadenas."""
    vals = {}
    for fichero in ("variables.lua", "binds.lua"):
        ruta = os.path.join(CONFIG, fichero)
        try:
            texto = open(ruta).read()
        except OSError:
            continue
        for linea in texto.split("\n"):
            for rx in (RE_LOCAL, RE_GLOBAL):
                m = rx.match(linea)
                if m:
                    vals[m.group(1)] = m.group(2)
                    break
            else:
                m = RE_NUM.match(linea)
                if m:
                    vals[m.group(1)] = m.group(2)
    return vals


def resolver(expr, vals, indice=None):
    """Junta una expresión Lua de concatenaciones en una cadena."""
    trozos = []
    for parte in expr.split(".."):
        parte = parte.strip()
        if not parte:
            continue
        if parte.startswith('"') and parte.endswith('"'):
            trozos.append(parte[1:-1])
        elif parte in vals:
            trozos.append(vals[parte])
        elif indice is not None and parte in indice:
            trozos.append("№")          # marca del bucle, se sustituye luego
        else:
            trozos.append(parte)
    return "".join(trozos)


def partir(texto):
    """Separa los dos argumentos de hl.bind respetando paréntesis y comillas."""
    hondo = 0
    comillas = False
    for i, c in enumerate(texto):
        if c == '"' and (i == 0 or texto[i - 1] != "\\"):
            comillas = not comillas
        elif not comillas:
            if c in "({[":
                hondo += 1
            elif c in ")}]":
                hondo -= 1
            elif c == "," and hondo == 0:
                return texto[:i], texto[i + 1:]
    return texto, ""


def describir(accion, vals):
    accion = accion.strip().rstrip(")").strip()

    m = re.match(r'hl\.dsp\.([A-Za-z_.]+)\s*\((.*)$', accion, re.S)
    if not m:
        return accion[:80]

    nombre, dentro = m.group(1), m.group(2)

    if nombre == "exec_cmd":
        orden = resolver(dentro.rstrip(")"), vals).strip()
        # los tres prefijos largos que aparecen una y otra vez
        if "quickshell ipc" in orden:
            return "k4 · " + orden.split("call k4 ")[-1].strip()
        if orden.startswith("noctalia msg "):
            return "noctalia · " + orden[len("noctalia msg "):].strip()
        if orden.startswith("uwsm app -- "):
            return "Abrir " + orden[len("uwsm app -- "):].strip()
        return orden[:70]

    base = VERBOS.get(nombre, nombre.replace(".", " · ").replace("_", " "))
    detalle = ""
    for clave in ("direction", "mode", "action", "workspace", "monitor", "window"):
        m2 = re.search(clave + r'\s*=\s*"?([^",}]+)"?', dentro)
        if m2:
            detalle = m2.group(1).strip()
            break
    if not detalle:
        m2 = re.match(r'\s*"?([^",)]+)"?', dentro)
        if m2 and m2.group(1).strip():
            detalle = m2.group(1).strip()

    # En los atajos generados en bucle el detalle es la propia variable, que
    # no dice nada: la combinación ya enseña el rango.
    if detalle in ("i", "key"):
        detalle = "el número"
    elif detalle.startswith("m~"):
        detalle = "en este monitor"

    return base + (" · " + detalle if detalle else "")


def leer():
    vals = variables()
    try:
        lineas = open(BINDS).read().split("\n")
    except OSError:
        return []

    salida = []
    seccion = "General"
    bucle = None
    alias = set()
    hasta = ""

    for linea in lineas:
        limpia = linea.strip()

        # títulos de sección: ---- ASÍ ---- o -- así
        m = re.match(r'^-{2,}\s*(.+?)\s*-{2,}$', limpia)
        if m and m.group(1).strip("- "):
            seccion = m.group(1).strip("- ").capitalize()
            continue
        m = re.match(r'^--\s+([A-ZÁÉÍÓÚÑ][^.]{3,60})$', limpia)
        if m:
            seccion = m.group(1).strip()
            continue

        m = RE_FOR.match(linea)
        if m:
            bucle = m.group(1)
            alias = {bucle}
            hasta = vals.get(m.group(3), m.group(3))
            continue
        if limpia == "end":
            bucle = None
            alias = set()
            continue

        if bucle:
            m = re.compile(RE_ALIAS.pattern % re.escape(bucle)).match(linea)
            if m:
                alias.add(m.group(1))
                continue

        m = RE_BIND.match(limpia)
        if not m:
            continue

        tecla, accion = partir(m.group(1))
        combo = resolver(tecla, vals, alias if bucle else None)
        if "№" in combo:
            combo = combo.replace("№", "1–" + str(hasta))

        salida.append({
            "combo": combo.strip(),
            "hace": describir(accion, vals),
            "seccion": seccion,
        })

    return salida


def main():
    atajos = leer()
    print(json.dumps({"total": len(atajos), "atajos": atajos}), flush=True)


if __name__ == "__main__":
    try:
        main()
    except (KeyboardInterrupt, BrokenPipeError):
        sys.exit(0)
