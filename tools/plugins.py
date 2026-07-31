#!/usr/bin/env python3
"""El catálogo de plugins: valida el del repo y lista el combinado.

    python3 tools/plugins.py            valida (repo + qmldir + usuario)
    python3 tools/plugins.py --listar   emite el catálogo combinado en JSON

El combinado es lo que carga la barra: los plugins del repo más los del
usuario en ~/.config/k4/plugins/<id>/, cada uno con su plugin.json. La
validación vive AQUÍ y en ningún otro sitio: el gestor de QML consume lo que
esto emite, y un manifiesto roto es un plugin marcado como no cargable con su
motivo — nunca una barra que no arranca.

No ejecuta QML: comprueba lo que se puede saber antes de arrancar Quickshell.
"""
from __future__ import annotations

import json
import pathlib
import re
import sys

RAIZ = pathlib.Path(__file__).resolve().parent.parent
CATALOGO = RAIZ / "plugins" / "catalog.json"
DE_USUARIO = pathlib.Path.home() / ".config" / "k4" / "plugins"

RE_ID = re.compile(r"[a-z0-9][a-z0-9-]*")

#  Qué puede pedir un plugin de fuera, y qué delata cada permiso en el QML.
#
#  Esto no es un sandbox y no se vende como tal: QML en el mismo proceso puede
#  hacer lo que la barra pueda hacer. Es consentimiento informado — el usuario
#  ve qué declara el plugin antes de encenderlo — más un análisis que convierte
#  el descuido y el engaño simple en un error de instalación.
PERMISOS = {
    "procesos": re.compile(r"\bK4\.Process\b|\bexecDetached\b"),
    "red": re.compile(r"\bXMLHttpRequest\b|\bWebSocket\b"),
    "ficheros": re.compile(r"\bK4\.Fichero\b"),
}


def version_tupla(v):
    try:
        return tuple(int(x) for x in str(v).split("."))
    except ValueError:
        return None


def host_compatible(requisito, version_host):
    """`>=x.y.z` contra la versión de la barra. Sin requisito, compatible."""
    if not requisito:
        return True
    m = re.fullmatch(r">=\s*(\d+(?:\.\d+)*)", str(requisito).strip())
    if not m:
        return False
    pedido = version_tupla(m.group(1))
    real = version_tupla(version_host)
    return pedido is not None and real is not None and real >= pedido


def leer_catalogo():
    datos = json.loads(CATALOGO.read_text())
    return datos, datos.get("plugins") or []


def validar_repo(plugins, fallos):
    """Los de casa: catálogo, name, carpeta y qmldir al día."""
    ids: set[str] = set()
    for item in plugins:
        ident = item.get("id")
        entrada = item.get("entry")
        if not isinstance(ident, str) or not RE_ID.fullmatch(ident):
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

    carpetas = {p.name for p in (RAIZ / "plugins").iterdir()
                if p.is_dir() and (p / (p.name + "Plugin.qml")).is_file()}
    en_catalogo = {str(item.get("entry", "")).split("/", 1)[0]
                   for item in plugins}
    for carpeta in sorted(carpetas - en_catalogo):
        fallos.append(f"plugin sin catálogo: {carpeta}")

    #  El qmldir de cada carpeta tiene que listar TODOS sus .qml: con el
    #  esquema de URLs de Quickshell la resolución implícita de hermanos no
    #  existe, y un tipo que falte aquí es un «X is not a type» al cargar.
    #  Se generaron al pasar a la carga dinámica; esto evita que envejezcan.
    for carpeta in sorted(carpetas):
        d = RAIZ / "plugins" / carpeta
        qmldir = d / "qmldir"
        if not qmldir.is_file():
            fallos.append(f"{carpeta}: falta qmldir")
            continue
        declarados = set(re.findall(r"^(\w+) 1\.0", qmldir.read_text(),
                                    re.MULTILINE))
        reales = {f.stem for f in d.glob("*.qml")}
        for falta in sorted(reales - declarados):
            fallos.append(f"{carpeta}/qmldir: falta {falta}")
    return ids


def cargar_usuario(ids_repo, version_host):
    """Los de ~/.config/k4/plugins, cada uno con su veredicto.

    Un plugin de usuario mal montado nunca es un fallo del repo: se lista como
    `cargable: false` con su motivo, para que Ajustes lo enseñe y el gestor no
    lo intente. Y los ids del repo ganan: un plugin de fuera no puede
    suplantar a uno de casa.
    """
    salida = []
    if not DE_USUARIO.is_dir():
        return salida
    for d in sorted(DE_USUARIO.iterdir()):
        if not d.is_dir():
            continue
        item = {"id": d.name, "title": d.name, "externo": True,
                "enabledByDefault": False, "cargable": True,
                "permisos": [], "version": "0"}

        def mal(motivo):
            item["cargable"] = False
            item["motivo"] = motivo
            salida.append(item)

        manifiesto = d / "plugin.json"
        if not manifiesto.is_file():
            mal("sin plugin.json")
            continue
        try:
            m = json.loads(manifiesto.read_text())
        except Exception as exc:
            mal(f"plugin.json ilegible: {exc}")
            continue

        for clave in ("id", "title", "version", "description", "permisos",
                      "host"):
            if clave in m:
                item[clave] = m[clave]
        ident = m.get("id")
        if not isinstance(ident, str) or not RE_ID.fullmatch(ident):
            mal(f"id inválido: {ident!r}")
            continue
        if ident != d.name:
            mal(f"el id {ident!r} no coincide con la carpeta {d.name!r}")
            continue
        if ident in ids_repo:
            mal("el id ya lo usa un plugin de la barra")
            continue
        entrada = m.get("entry")
        if not isinstance(entrada, str) or "/" in entrada:
            mal("entry debe ser un fichero de la propia carpeta")
            continue
        ruta = d / entrada
        if not ruta.is_file():
            mal(f"no existe {entrada}")
            continue
        if not host_compatible(m.get("host"), version_host):
            mal(f"pide barra {m.get('host')} y esta es {version_host}")
            continue

        #  El análisis de permisos: lo que el QML usa contra lo declarado.
        declarados = set(m.get("permisos") or [])
        raros = declarados - set(PERMISOS)
        if raros:
            mal("permisos desconocidos: " + ", ".join(sorted(raros)))
            continue
        usados = set()
        for qml in d.glob("**/*.qml"):
            texto = "\n".join(re.sub(r"//.*$", "", l)
                              for l in qml.read_text().split("\n"))
            for permiso, patron in PERMISOS.items():
                if patron.search(texto):
                    usados.add(permiso)
        sin_declarar = usados - declarados
        if sin_declarar:
            mal("usa sin declarar: " + ", ".join(sorted(sin_declarar)))
            continue

        #  Cargable. La entrada sale ABSOLUTA: el gestor no tiene por qué
        #  saber dónde viven los de usuario.
        item["entry"] = str(ruta)
        salida.append(item)
    return salida


def listar():
    datos, plugins = leer_catalogo()
    version_host = str(datos.get("version", "1.0.0"))
    ids_repo = {item.get("id") for item in plugins}
    combinado = list(plugins) + cargar_usuario(ids_repo, version_host)
    print(json.dumps({"schema": 1, "version": version_host,
                      "plugins": combinado}, ensure_ascii=False))
    return 0


def main():
    fallos: list[str] = []
    try:
        datos, plugins = leer_catalogo()
    except Exception as exc:
        print(f"catálogo ilegible: {exc}", file=sys.stderr)
        return 2

    ids = validar_repo(plugins, fallos)
    if fallos:
        print("El catálogo de plugins tiene problemas:\n")
        print("\n".join("  - " + x for x in fallos))
        return 1

    version_host = str(datos.get("version", "1.0.0"))
    externos = cargar_usuario(ids, version_host)
    rotos = [e for e in externos if not e.get("cargable")]
    print(f"{len(plugins)} plugins del repo verificados"
          + (f" · {len(externos)} de usuario" if externos else "")
          + (f" ({len(rotos)} no cargables)" if rotos else "") + ".")
    for e in rotos:
        print(f"  - {e['id']}: {e.get('motivo')}")
    return 0


if __name__ == "__main__":
    sys.exit(listar() if "--listar" in sys.argv else main())
