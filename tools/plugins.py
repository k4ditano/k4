#!/usr/bin/env python3
"""Valida el catálogo y el contrato de plugins de k4.

    python3 tools/plugins.py

No ejecuta QML: comprueba lo que se puede detectar antes de arrancar
Quickshell y da errores de instalación claros.
"""
from __future__ import annotations

import json
import pathlib
import re
import sys

RAIZ = pathlib.Path(__file__).resolve().parent.parent
CATALOGO = RAIZ / "plugins" / "catalog.json"


def main() -> int:
    fallos: list[str] = []
    try:
        datos = json.loads(CATALOGO.read_text())
    except Exception as exc:
        print(f"catálogo ilegible: {exc}", file=sys.stderr)
        return 2

    plugins = datos.get("plugins")
    if not isinstance(plugins, list) or not plugins:
        fallos.append("plugins debe ser una lista no vacía")
        plugins = []

    ids: set[str] = set()
    nombres_qml: set[str] = set()
    for item in plugins:
        ident = item.get("id")
        entrada = item.get("entry")
        if not isinstance(ident, str) or not re.fullmatch(r"[a-z0-9][a-z0-9-]*", ident):
            fallos.append(f"id inválido: {ident!r}")
            continue
        if ident in ids:
            fallos.append(f"id duplicado: {ident}")
        ids.add(ident)
        if not isinstance(entrada, str):
            fallos.append(f"{ident}: falta entry")
            continue
        ruta = RAIZ / "plugins" / entrada
        if not ruta.is_file():
            fallos.append(f"{ident}: no existe {entrada}")
            continue
        texto = ruta.read_text()
        nombres = re.findall(r"^\s{4}name\s*:\s*['\"]([^'\"]+)['\"]\s*$",
                             texto, re.MULTILINE)
        if len(nombres) != 1:
            fallos.append(f"{ident}: debe declarar exactamente un name")
        elif nombres[0] != ident:
            fallos.append(f"{ident}: name QML es {nombres[0]!r}")
        nombres_qml.update(nombres)

    carpetas = {p.name for p in (RAIZ / "plugins").iterdir()
                if p.is_dir() and (p / (p.name + "Plugin.qml")).is_file()}
    catalogo_carpetas = {str(item.get("entry", "")).split("/", 1)[0]
                         for item in plugins}
    for carpeta in sorted(carpetas - catalogo_carpetas):
        fallos.append(f"plugin sin catálogo: {carpeta}")

    shell = (RAIZ / "shell.qml").read_text()
    for ident in sorted(ids):
        if f'PluginManager.estaHabilitado("{ident}")' not in shell:
            fallos.append(f"{ident}: no está enlazado a PluginManager en shell.qml")

    if fallos:
        print("El catálogo de plugins tiene problemas:\n")
        print("\n".join("  - " + x for x in fallos))
        return 1

    print(f"{len(plugins)} plugins catalogados y verificados.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
