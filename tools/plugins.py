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
import shutil
import subprocess
import sys
import tempfile

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


def validar_carpeta(d, ids_repo, version_host):
    """El veredicto sobre UNA carpeta de plugin: `{…, cargable, motivo}`.

    Vale para una ya instalada y para un clon recién bajado que todavía no ha
    entrado en ~/.config/k4/plugins — que es justo lo que permite validar
    ANTES de instalar, en vez de instalar y ver qué pasa.
    """
    item = {"id": d.name, "title": d.name, "externo": True,
            "enabledByDefault": False, "cargable": True,
            "permisos": [], "version": "0"}

    def mal(motivo):
        item["cargable"] = False
        item["motivo"] = motivo
        return item

    manifiesto = d / "plugin.json"
    if not manifiesto.is_file():
        return mal("sin plugin.json")
    try:
        m = json.loads(manifiesto.read_text())
    except Exception as exc:
        return mal(f"plugin.json ilegible: {exc}")

    for clave in ("id", "title", "version", "description", "permisos", "host"):
        if clave in m:
            item[clave] = m[clave]
    ident = m.get("id")
    if not isinstance(ident, str) or not RE_ID.fullmatch(ident):
        return mal(f"id inválido: {ident!r}")
    if ident != d.name:
        return mal(f"el id {ident!r} no coincide con la carpeta {d.name!r}")
    if ident in ids_repo:
        return mal("el id ya lo usa un plugin de la barra")
    entrada = m.get("entry")
    if not isinstance(entrada, str) or "/" in entrada:
        return mal("entry debe ser un fichero de la propia carpeta")
    ruta = d / entrada
    if not ruta.is_file():
        return mal(f"no existe {entrada}")
    if not host_compatible(m.get("host"), version_host):
        return mal(f"pide barra {m.get('host')} y esta es {version_host}")

    #  El análisis de permisos: lo que el QML usa contra lo declarado.
    declarados = set(m.get("permisos") or [])
    raros = declarados - set(PERMISOS)
    if raros:
        return mal("permisos desconocidos: " + ", ".join(sorted(raros)))
    usados = set()
    for qml in d.glob("**/*.qml"):
        texto = "\n".join(re.sub(r"//.*$", "", l)
                           for l in qml.read_text().split("\n"))
        for permiso, patron in PERMISOS.items():
            if patron.search(texto):
                usados.add(permiso)
    sin_declarar = usados - declarados
    if sin_declarar:
        return mal("usa sin declarar: " + ", ".join(sorted(sin_declarar)))

    #  El qmldir, generado si falta o si envejeció: con el esquema de URLs de
    #  Quickshell los tipos hermanos no se resuelven solos, y pedirle a cada
    #  autor que mantenga la lista a mano es pedir un «X is not a type» al
    #  primer fichero nuevo.
    reales = sorted(f.stem for f in d.glob("*.qml"))
    qmldir = d / "qmldir"
    declarados_qml = (set(re.findall(r"^(\w+) 1\.0", qmldir.read_text(),
                                     re.MULTILINE))
                      if qmldir.is_file() else set())
    if set(reales) - declarados_qml:
        try:
            qmldir.write_text(
                "#  Generado por k4 (tools/plugins.py): los tipos de esta\n"
                "#  carpeta, para que se resuelvan bajo el esquema qs:.\n\n"
                + "".join(f"{n} 1.0 {n}.qml\n" for n in reales))
        except OSError:
            return mal("no puedo escribir el qmldir")

    #  Cargable. La entrada sale ABSOLUTA: el gestor no tiene por qué saber
    #  dónde viven los de usuario.
    item["entry"] = str(ruta)
    return item


def cargar_usuario(ids_repo, version_host):
    """Los de ~/.config/k4/plugins, cada uno con su veredicto.

    Un plugin de usuario mal montado nunca es un fallo del repo: se lista como
    `cargable: false` con su motivo, para que Ajustes lo enseñe y el gestor no
    lo intente. Y los ids del repo ganan: un plugin de fuera no puede
    suplantar a uno de casa.
    """
    if not DE_USUARIO.is_dir():
        return []
    return [validar_carpeta(d, ids_repo, version_host)
            for d in sorted(DE_USUARIO.iterdir())
            if d.is_dir() and not d.name.startswith(".")]


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


def _contexto():
    """El par que hace falta para juzgar a un plugin: ids de casa y versión."""
    datos, plugins = leer_catalogo()
    return ({item.get("id") for item in plugins},
            str(datos.get("version", "1.0.0")))


def _carpeta_del_clon(base):
    """Dónde está el plugin dentro de lo clonado.

    Se acepta el plugin.json en la raíz —lo normal, un repo por plugin— o en
    una única subcarpeta, que es como quedan los repos que traen el ejemplo
    dentro. Más de un candidato y no se adivina: que lo diga el usuario.
    """
    if (base / "plugin.json").is_file():
        return base
    candidatos = [d for d in sorted(base.iterdir())
                  if d.is_dir() and (d / "plugin.json").is_file()]
    if len(candidatos) == 1:
        return candidatos[0]
    return None


def _describir(item):
    lineas = [f"  {item.get('title', item['id'])}  ·  {item['id']}"
              f"  ·  v{item.get('version', '0')}"]
    if item.get("description"):
        lineas.append(f"  {item['description']}")
    permisos = item.get("permisos") or []
    lineas.append("  Permisos: " + (", ".join(permisos) if permisos
                                    else "ninguno"))
    return "\n".join(lineas)


def instalar(url, sin_preguntar=False, subcarpeta=None):
    """Clonar, validar y —con permiso— instalar un plugin de fuera.

    El orden importa y es el único defendible: se clona a un temporal, se
    valida ENTERO ahí, y solo entonces se enseña lo que declara y se pide
    permiso. Nada llega a ~/.config/k4/plugins sin haber pasado el mismo
    examen que pasan los ya instalados, así que no existe el estado «medio
    instalado y roto».

    Y llega DESHABILITADO, siempre. Instalar es traerlo; encenderlo es otra
    decisión, y se toma en Ajustes viendo estos mismos permisos.
    """
    ids_repo, version_host = _contexto()
    with tempfile.TemporaryDirectory(prefix="k4-plugin-") as tmp:
        clon = pathlib.Path(tmp) / "clon"
        #  `--depth 1` solo para lo remoto: en un clon local git avisa de que
        #  la ignora, y ese aviso en medio de la pantalla de permisos parece
        #  un error cuando no lo es.
        orden = ["git", "clone", "-q"]
        if "://" in url and not url.startswith("file://"):
            orden += ["--depth", "1"]
        try:
            subprocess.run(orden + [url, str(clon)], check=True)
        except (subprocess.CalledProcessError, FileNotFoundError) as exc:
            print(f"no he podido clonar {url}: {exc}", file=sys.stderr)
            return 1
        shutil.rmtree(clon / ".git", ignore_errors=True)

        carpeta = (clon / subcarpeta) if subcarpeta else _carpeta_del_clon(clon)
        if carpeta is None or not carpeta.is_dir():
            print("no encuentro un plugin.json ni en la raíz ni en una única "
                  "subcarpeta; dime cuál con --carpeta <nombre>",
                  file=sys.stderr)
            return 1

        #  El id manda sobre el nombre del clon: la carpeta se llama como el
        #  repositorio y el manifiesto exige que coincida con el id.
        try:
            ident = json.loads((carpeta / "plugin.json").read_text())["id"]
        except Exception as exc:
            print(f"plugin.json ilegible: {exc}", file=sys.stderr)
            return 1
        if isinstance(ident, str) and RE_ID.fullmatch(ident) \
                and carpeta.name != ident:
            nueva = carpeta.parent / ident
            if nueva.exists():
                shutil.rmtree(nueva)
            carpeta = carpeta.rename(nueva)

        item = validar_carpeta(carpeta, ids_repo, version_host)
        if not item.get("cargable"):
            print(f"ese plugin no se puede cargar: {item.get('motivo')}",
                  file=sys.stderr)
            return 1

        destino = DE_USUARIO / item["id"]
        print(f"\nDe {url}:\n")
        print(_describir(item))
        print("\n  Se instalará en", destino)
        print("  Llega apagado: se enciende en Ajustes.")
        if destino.exists():
            print("  YA EXISTE: se reemplaza la versión instalada.")
        print()
        print("  Un plugin corre dentro de la barra y puede hacer lo que la")
        print("  barra pueda hacer. Los permisos son lo que DECLARA, no una")
        print("  jaula: instalarlo es confiar en quien lo escribió.")
        if not sin_preguntar:
            try:
                if input("\n¿Instalar? [s/N] ").strip().lower() not in ("s", "si", "sí"):
                    print("nada instalado.")
                    return 1
            except EOFError:
                print("sin terminal para preguntar; usa --si si estás seguro.",
                      file=sys.stderr)
                return 1

        DE_USUARIO.mkdir(parents=True, exist_ok=True)
        reemplaza = destino.exists()
        if reemplaza:
            shutil.rmtree(destino)
        shutil.copytree(carpeta, destino)
        (destino / ".origen").write_text(url + "\n")

    ident = item["id"]
    if reemplaza:
        print(f"\nactualizado: {ident} v{item.get('version', '0')}.")
        #  Si estaba encendido, en la barra sigue corriendo el código viejo:
        #  el disco cambió, la instancia no.
        print(f"  Si lo tenías encendido: `k4 pluginReload {ident}`.")
    else:
        print(f"\ninstalado: {ident}. Enciéndelo en Ajustes"
              f" (o `k4 pluginRefresh` y `k4 pluginEnable {ident}`).")
    return 0


def actualizar(ident, sin_preguntar=False):
    """Reinstalar desde el origen que quedó apuntado al instalar."""
    marca = DE_USUARIO / ident / ".origen"
    if not marca.is_file():
        print(f"{ident} no se instaló desde una URL, no sé de dónde "
              "actualizarlo.", file=sys.stderr)
        return 1
    return instalar(marca.read_text().strip(), sin_preguntar)


def quitar(ident, sin_preguntar=False, con_estado=False):
    """Desinstalar: la carpeta, y si se pide, también lo que había guardado."""
    d = DE_USUARIO / ident
    if not d.is_dir():
        print(f"{ident} no está instalado.", file=sys.stderr)
        return 1
    estado = (pathlib.Path.home() / ".local" / "state" / "k4" / "plugins"
              / ident)
    print(f"se borrará {d}")
    if con_estado and estado.is_dir():
        print(f"y su estado guardado en {estado}")
    if not sin_preguntar:
        try:
            if input("¿Seguro? [s/N] ").strip().lower() not in ("s", "si", "sí"):
                print("nada borrado.")
                return 1
        except EOFError:
            print("sin terminal para preguntar; usa --si.", file=sys.stderr)
            return 1
    shutil.rmtree(d)
    if con_estado:
        shutil.rmtree(estado, ignore_errors=True)
    print(f"quitado: {ident}")
    return 0


def instalados():
    """Los de fuera que hay, con su veredicto y de dónde vinieron."""
    ids_repo, version_host = _contexto()
    externos = cargar_usuario(ids_repo, version_host)
    if not externos:
        print("no hay plugins de usuario instalados.")
        return 0
    for item in externos:
        estado = "ok" if item.get("cargable") else f"NO CARGA: {item['motivo']}"
        origen = DE_USUARIO / item["id"] / ".origen"
        de = origen.read_text().strip() if origen.is_file() else "local"
        print(f"{item['id']:<16} v{item.get('version', '0'):<8} {estado}")
        print(f"{'':<16} {de}")
    return 0


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


AYUDA = """El catálogo de plugins de k4.

    tools/plugins.py                      valida el repo y los instalados
    tools/plugins.py --listar             emite el catálogo combinado (JSON)
    tools/plugins.py --instalados         qué hay instalado de fuera
    tools/plugins.py --instalar <url>     clona, valida, pregunta e instala
    tools/plugins.py --actualizar <id>    reinstala desde su origen
    tools/plugins.py --quitar <id>        desinstala

    --si          no preguntar (para guiones)
    --con-estado  al quitar, borra también lo que el plugin guardó
    --carpeta <n> al instalar, cuál del repo si hay varias
"""


def _valor(bandera):
    if bandera in sys.argv:
        i = sys.argv.index(bandera)
        if i + 1 < len(sys.argv):
            return sys.argv[i + 1]
    return None


if __name__ == "__main__":
    if "--ayuda" in sys.argv or "-h" in sys.argv:
        print(AYUDA)
        sys.exit(0)
    _si = "--si" in sys.argv
    if "--instalar" in sys.argv:
        _url = _valor("--instalar")
        sys.exit(instalar(_url, _si, _valor("--carpeta")) if _url else 2)
    if "--actualizar" in sys.argv:
        _id = _valor("--actualizar")
        sys.exit(actualizar(_id, _si) if _id else 2)
    if "--quitar" in sys.argv:
        _id = _valor("--quitar")
        sys.exit(quitar(_id, _si, "--con-estado" in sys.argv) if _id else 2)
    if "--instalados" in sys.argv:
        sys.exit(instalados())
    if "--recargar" in sys.argv:
        i = sys.argv.index("--recargar")
        sys.exit(recargar(sys.argv[i + 1]) if i + 1 < len(sys.argv) else 2)
    sys.exit(listar() if "--listar" in sys.argv else main())
