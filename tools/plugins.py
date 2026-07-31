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
        if not d.is_dir() or d.name.startswith("."):
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

        #  El qmldir, generado si falta o si envejeció: con el esquema de
        #  URLs de Quickshell los tipos hermanos no se resuelven solos, y
        #  pedirle a cada autor que mantenga la lista a mano es pedir un
        #  «X is not a type» al primer fichero nuevo.
        reales = sorted(f.stem for f in d.glob("*.qml"))
        qmldir = d / "qmldir"
        declarados = (set(re.findall(r"^(\w+) 1\.0", qmldir.read_text(),
                                     re.MULTILINE))
                      if qmldir.is_file() else set())
        if set(reales) - declarados:
            try:
                qmldir.write_text(
                    "#  Generado por k4 (tools/plugins.py): los tipos de esta\n"
                    "#  carpeta, para que se resuelvan bajo el esquema qs:.\n\n"
                    + "".join(f"{n} 1.0 {n}.qml\n" for n in reales))
            except OSError:
                mal("no puedo escribir el qmldir")
                continue

        #  Cargable. La entrada sale ABSOLUTA: el gestor no tiene por qué
        #  saber dónde viven los de usuario.
        item["entry"] = str(ruta)
        salida.append(item)
    return salida


def enlazar_externos():
    """El puente por el que la barra carga los de usuario: un enlace dentro
    del árbol del shell.

    No es un capricho: Quickshell sirve su configuración bajo un esquema de
    URL propio, y un fichero QML cargado por file:// trae SUS PROPIAS copias
    de todos los singletons — dos PluginManager, dos servicios de todo, cada
    target de IPC registrado dos veces. Con el enlace, los de usuario viven
    (a ojos del motor) dentro del árbol y comparten esquema y singletons con
    el resto. Se paga con un symlink; la alternativa se pagaba con duplicar
    la barra entera.
    """
    DE_USUARIO.mkdir(parents=True, exist_ok=True)
    enlace = RAIZ / "externos"
    try:
        if enlace.is_symlink():
            if enlace.readlink() != DE_USUARIO:
                enlace.unlink()
                enlace.symlink_to(DE_USUARIO)
        elif not enlace.exists():
            enlace.symlink_to(DE_USUARIO)
    except OSError:
        pass


def recargar(ident):
    """Una carpeta nueva para una recarga en caliente.

    El truco de ponerle `?r1` a la entrada recarga la entrada... y solo la
    entrada. Los ficheros hermanos —la vista, casi siempre lo que el autor
    acaba de editar— se resuelven contra la MISMA carpeta y salen calentitos
    de la caché: el plugin se recreaba enseñando la versión anterior. Muy
    difícil de ver, porque el plugin sí se recreaba.

    Así que se recarga la carpeta entera: un enlace nuevo en `recargas/` es
    una URL nueva para TODO lo que hay dentro. Cuesta un symlink por recarga
    y se limpian los anteriores del mismo plugin.
    """
    enlazar_externos()
    datos, plugins = leer_catalogo()
    ids_repo = {item.get("id") for item in plugins}
    todos = list(plugins) + cargar_usuario(ids_repo,
                                           str(datos.get("version", "1.0.0")))
    for item in todos:
        if item.get("id") != ident:
            continue
        if not item.get("cargable", True):
            return 1
        entrada = str(item.get("entry", ""))
        origen = (pathlib.Path(entrada) if entrada.startswith("/")
                  else RAIZ / "plugins" / entrada)
        carpeta = origen.parent
        destino = RAIZ / "recargas"
        destino.mkdir(exist_ok=True)
        ronda = 1
        for viejo in destino.glob(ident + "-*"):
            try:
                ronda = max(ronda, int(viejo.name.rsplit("-", 1)[1]) + 1)
                viejo.unlink()
            except (ValueError, OSError):
                pass
        enlace = destino / f"{ident}-{ronda}"
        enlace.symlink_to(carpeta)
        print(f"recargas/{enlace.name}/{origen.name}")
        return 0
    return 1


def listar():
    enlazar_externos()
    #  Las carpetas de recarga son de la sesión anterior: al arrancar sobran.
    for viejo in (RAIZ / "recargas").glob("*"):
        try:
            viejo.unlink()
        except OSError:
            pass
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
    if "--recargar" in sys.argv:
        i = sys.argv.index("--recargar")
        sys.exit(recargar(sys.argv[i + 1]) if i + 1 < len(sys.argv) else 2)
    sys.exit(listar() if "--listar" in sys.argv else main())
