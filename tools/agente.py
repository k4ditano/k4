#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Put k4's skill where coding agents will find it.

    python3 tools/agente.py            where it is, and whether it's linked
    python3 tools/agente.py --install  link it
    python3 tools/agente.py --remove   unlink it

(`--instalar` y `--quitar` siguen valiendo: las banderas van en inglés porque
son la puerta, pero nadie tiene que reaprenderse las que ya usaba.)

Un agente que trabaja en esta máquina no sabe que hay una barra llamada k4, ni
que todo lo suyo son plugins, ni que hay una orden para crear uno que ya
arranca. Se lo puedes contar cada vez, o dejarlo escrito una vez donde lo lea
solo. Esto es lo segundo.

Se enlaza y no se copia: la habilidad vive en el repositorio, así que al
actualizar k4 se actualiza también lo que lee el agente. Una copia se queda
vieja y nadie se entera hasta que le dice a alguien que haga algo que ya no
existe.
"""

from __future__ import annotations

import os
import pathlib
import sys

RAIZ = pathlib.Path(__file__).resolve().parent.parent
HABILIDAD = RAIZ / "agentes" / "skills" / "k4"

#  Dónde busca cada uno. Se ponen todos los que existan en la máquina: que
#  esté para Claude y no para Codex es un despiste raro de diagnosticar.
DESTINOS = [
    pathlib.Path.home() / ".claude" / "skills" / "k4",
    pathlib.Path.home() / ".config" / "agents" / "skills" / "k4",
]


def estado(d):
    if d.is_symlink():
        return "enlazada" if d.resolve() == HABILIDAD else "enlazada a OTRA cosa"
    if d.exists():
        return "ocupado por algo que no es un enlace"
    return "sin poner"


def mirar():
    print("La habilidad: %s" % HABILIDAD)
    if not HABILIDAD.is_dir():
        print("  NO ESTÁ. ¿Repositorio incompleto?")
        return 1
    for d in DESTINOS:
        print("  %-46s %s" % (d, estado(d)))
    return 0


def instalar():
    if not HABILIDAD.is_dir():
        print("no encuentro %s" % HABILIDAD, file=sys.stderr)
        return 1
    puestas = 0
    for d in DESTINOS:
        if d.is_symlink() and d.resolve() == HABILIDAD:
            print("  ya estaba: %s" % d)
            continue
        if d.exists() and not d.is_symlink():
            #  Algo real ahí dentro no se toca: puede ser una habilidad que
            #  haya escrito el usuario, y borrarla para poner la nuestra sería
            #  decidir por él.
            print("  ocupado, lo dejo: %s" % d)
            continue
        d.parent.mkdir(parents=True, exist_ok=True)
        if d.is_symlink():
            d.unlink()
        d.symlink_to(HABILIDAD)
        print("  puesta: %s" % d)
        puestas += 1
    if puestas:
        print("\nLos agentes que empiecen a partir de ahora sabrán que esto es"
              " k4\ny cómo escribirle un plugin.")
    return 0


def quitar():
    for d in DESTINOS:
        if d.is_symlink() and d.resolve() == HABILIDAD:
            d.unlink()
            print("  quitada: %s" % d)
        elif d.exists():
            print("  no es nuestra, la dejo: %s" % d)
    return 0


if __name__ == "__main__":
    #  En inglés, y las de antes también.
    sys.argv = [{"--install": "--instalar",
                 "--remove": "--quitar"}.get(a, a) for a in sys.argv]
    if "--instalar" in sys.argv:
        sys.exit(instalar())
    if "--quitar" in sys.argv:
        sys.exit(quitar())
    if "-h" in sys.argv or "--help" in sys.argv or "--ayuda" in sys.argv:
        print(__doc__)
        sys.exit(0)
    sys.exit(mirar())
