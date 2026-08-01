#!/usr/bin/env python3
"""Pruebas del catálogo de plugins: el guion que instala código de TERCEROS.

    python3 tools/prueba_plugins.py

`plugins.py` es la puerta de entrada de código ajeno a la barra: valida
manifiestos, casa permisos declarados contra lo que el QML usa de verdad, y
rechaza antes de tocar el disco. Que el editor tuviera setenta pruebas y
esta puerta ninguna era el desequilibrio más llamativo del proyecto.

Cada prueba fabrica su carpeta de plugin en un temporal: nada depende de lo
que haya en la máquina.
"""
import json
import pathlib
import struct
import sys
import tempfile
import zlib

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import plugins

fallos = []
BORRADOR = pathlib.Path(tempfile.mkdtemp(prefix="k4-prueba-plugins-"))
HOST = "1.1.0"


def igual(que, es, deberia):
    if es != deberia:
        fallos.append("%s\n      es: %r\n  debería: %r" % (que, es, deberia))


def contiene(que, texto, trozo):
    if trozo not in str(texto):
        fallos.append("%s\n      es: %r\n  debería contener: %r"
                      % (que, texto, trozo))


def carpeta(nombre, manifiesto=None, ficheros=None):
    """Una carpeta de plugin recién fabricada, con lo que se le pida."""
    d = BORRADOR / nombre
    d.mkdir(parents=True, exist_ok=True)
    for viejo in d.iterdir():
        viejo.unlink()
    if manifiesto is not None:
        (d / "plugin.json").write_text(json.dumps(manifiesto))
    for ruta, contenido in (ficheros or {}).items():
        modo = "wb" if isinstance(contenido, bytes) else "w"
        with open(d / ruta, modo) as f:
            f.write(contenido)
    return d


def manifiesto_base(ident):
    return {"id": ident, "entry": "Plugin.qml", "version": "1.0.0",
            "title": ident, "description": "prueba", "host": ">=1.0.0",
            "permisos": []}


def png(ancho, alto):
    """Un PNG mínimo pero legal: firma + IHDR con las medidas pedidas."""
    ihdr = struct.pack(">IIBBBBB", ancho, alto, 8, 2, 0, 0, 0)
    trozo = b"IHDR" + ihdr
    return (b"\x89PNG\r\n\x1a\n"
            + struct.pack(">I", len(ihdr)) + trozo
            + struct.pack(">I", zlib.crc32(trozo)))


# ── las piezas puras ─────────────────────────────────────────────────

def prueba_version_tupla():
    igual("una versión normal", plugins.version_tupla("1.2.3"), (1, 2, 3))
    igual("con basura devuelve None", plugins.version_tupla("uno.dos"), None)


def prueba_host_compatible():
    igual("sin requisito, compatible", plugins.host_compatible(None, HOST), True)
    igual("mayor cumple", plugins.host_compatible(">=1.0.0", HOST), True)
    igual("igual cumple", plugins.host_compatible(">=1.1.0", HOST), True)
    igual("menor no", plugins.host_compatible(">=2.0.0", HOST), False)
    igual("formato raro no cuela", plugins.host_compatible("^1.0.0", HOST), False)


# ── el veredicto de una carpeta ──────────────────────────────────────

def prueba_plugin_valido():
    d = carpeta("hola", manifiesto_base("hola"),
                {"Plugin.qml": "import QtQuick\nItem {}\n"})
    v = plugins.validar_carpeta(d, set(), HOST)
    igual("un plugin sano es cargable", v["cargable"], True)
    igual("la entrada sale absoluta", v["entry"], str(d / "Plugin.qml"))
    igual("y el qmldir se genera solo", (d / "qmldir").is_file(), True)
    contiene("con sus tipos dentro", (d / "qmldir").read_text(), "Plugin 1.0")


def prueba_sin_manifiesto():
    d = carpeta("roto")
    v = plugins.validar_carpeta(d, set(), HOST)
    igual("sin plugin.json no carga", v["cargable"], False)
    contiene("y lo dice", v["motivo"], "plugin.json")


def prueba_manifiesto_ilegible():
    d = carpeta("basura", ficheros={"plugin.json": "{esto no es json"})
    v = plugins.validar_carpeta(d, set(), HOST)
    igual("json roto no carga", v["cargable"], False)
    contiene("con el motivo", v["motivo"], "ilegible")


def prueba_id_invalido():
    d = carpeta("malo", dict(manifiesto_base("malo"), id="Con Mayúsculas"),
                {"Plugin.qml": "Item {}\n"})
    v = plugins.validar_carpeta(d, set(), HOST)
    igual("un id con mayúsculas y espacios no cuela", v["cargable"], False)


def prueba_id_no_coincide_con_carpeta():
    d = carpeta("una-cosa", manifiesto_base("otra-cosa"),
                {"Plugin.qml": "Item {}\n"})
    v = plugins.validar_carpeta(d, set(), HOST)
    igual("id distinto de la carpeta no carga", v["cargable"], False)
    contiene("y nombra a los dos", v["motivo"], "otra-cosa")


def prueba_id_del_repo_gana():
    d = carpeta("game", manifiesto_base("game"), {"Plugin.qml": "Item {}\n"})
    v = plugins.validar_carpeta(d, {"game"}, HOST)
    igual("no se puede suplantar a uno de la barra", v["cargable"], False)


def prueba_entry_con_ruta():
    d = carpeta("listillo", dict(manifiesto_base("listillo"),
                                 entry="../fuera.qml"))
    v = plugins.validar_carpeta(d, set(), HOST)
    igual("una entry que sube por la ruta no carga", v["cargable"], False)


def prueba_entry_inexistente():
    d = carpeta("vacio", manifiesto_base("vacio"))
    v = plugins.validar_carpeta(d, set(), HOST)
    igual("sin el fichero de entrada no carga", v["cargable"], False)


def prueba_host_viejo():
    d = carpeta("futuro", dict(manifiesto_base("futuro"), host=">=9.0.0"),
                {"Plugin.qml": "Item {}\n"})
    v = plugins.validar_carpeta(d, set(), HOST)
    igual("pedir una barra que no existe no carga", v["cargable"], False)


# ── los permisos: el corazón de la puerta ────────────────────────────

def prueba_permiso_desconocido():
    d = carpeta("inventor", dict(manifiesto_base("inventor"),
                                 permisos=["superpoderes"]),
                {"Plugin.qml": "Item {}\n"})
    v = plugins.validar_carpeta(d, set(), HOST)
    igual("un permiso inventado no carga", v["cargable"], False)
    contiene("y se nombra", v["motivo"], "superpoderes")


def prueba_usa_sin_declarar():
    d = carpeta("colado", manifiesto_base("colado"),
                {"Plugin.qml": "Item { K4.Process { command: [\"ls\"] } }\n"})
    v = plugins.validar_carpeta(d, set(), HOST)
    igual("usar K4.Process sin declararlo no carga", v["cargable"], False)
    contiene("y el motivo dice cuál", v["motivo"], "procesos")


def prueba_usa_declarado():
    d = carpeta("honesto", dict(manifiesto_base("honesto"),
                                permisos=["procesos"]),
                {"Plugin.qml": "Item { K4.Process { command: [\"ls\"] } }\n"})
    v = plugins.validar_carpeta(d, set(), HOST)
    igual("declarado, cargable", v["cargable"], True)


def prueba_comentario_no_delata():
    d = carpeta("comentado", manifiesto_base("comentado"),
                {"Plugin.qml": "Item {} // algún día usaré K4.Process\n"})
    v = plugins.validar_carpeta(d, set(), HOST)
    igual("hablar de K4.Process en un comentario no es usarlo",
          v["cargable"], True)


def prueba_huella_exige_permiso():
    d = carpeta("curioso", manifiesto_base("curioso"),
                {"Plugin.qml":
                 "Item { property var j: K4.Huella.steam.juegos }\n"})
    v = plugins.validar_carpeta(d, set(), HOST)
    igual("nombrar K4.Huella sin datos-personales no carga",
          v["cargable"], False)
    contiene("y el motivo lo dice", v["motivo"], "datos-personales")


def prueba_portapapeles_delata_al_leer():
    d = carpeta("fisgon", manifiesto_base("fisgon"),
                {"Plugin.qml":
                 "Item { property var h: K4.Portapapeles.entradas }\n"})
    v = plugins.validar_carpeta(d, set(), HOST)
    igual("solo LEER el portapapeles ya exige permiso", v["cargable"], False)
    contiene("con su nombre", v["motivo"], "portapapeles")


def prueba_la_vista_tambien_se_examina():
    d = carpeta("repartido", manifiesto_base("repartido"),
                {"Plugin.qml": "Item {}\n",
                 "Vista.qml": "Item { K4.Sonido { fuente: \"x.wav\" } }\n"})
    v = plugins.validar_carpeta(d, set(), HOST)
    igual("el permiso se busca en TODOS los .qml, no solo la entrada",
          v["cargable"], False)


# ── el icono ─────────────────────────────────────────────────────────

def prueba_icono_codice():
    d = carpeta("glifo", dict(manifiesto_base("glifo"), icono="0xF04E5"),
                {"Plugin.qml": "Item {}\n"})
    v = plugins.validar_carpeta(d, set(), HOST)
    igual("un códice vale", v["cargable"], True)
    igual("y queda apuntado", v["icono"], "0xF04E5")


def prueba_icono_inexistente():
    d = carpeta("sin-icono", dict(manifiesto_base("sin-icono"),
                                  icono="nada.png"),
                {"Plugin.qml": "Item {}\n"})
    v = plugins.validar_carpeta(d, set(), HOST)
    igual("un icono que no existe no carga", v["cargable"], False)


def prueba_icono_pequeno():
    d = carpeta("borroso", dict(manifiesto_base("borroso"), icono="i.png"),
                {"Plugin.qml": "Item {}\n", "i.png": png(32, 32)})
    v = plugins.validar_carpeta(d, set(), HOST)
    igual("un PNG de 32px no llega al mínimo", v["cargable"], False)
    contiene("y el motivo lo explica", v["motivo"], "32x32")


def prueba_icono_decente():
    d = carpeta("nitido", dict(manifiesto_base("nitido"), icono="i.png"),
                {"Plugin.qml": "Item {}\n", "i.png": png(128, 128)})
    v = plugins.validar_carpeta(d, set(), HOST)
    igual("un PNG de 128px carga", v["cargable"], True)
    contiene("con su ruta absoluta", v["iconoFichero"], str(d / "i.png"))


def prueba_icono_con_ruta():
    d = carpeta("ladron", dict(manifiesto_base("ladron"),
                               icono="../../otro.png"),
                {"Plugin.qml": "Item {}\n"})
    v = plugins.validar_carpeta(d, set(), HOST)
    igual("un icono con ruta no cuela", v["cargable"], False)


def main():
    pruebas = [v for k, v in sorted(globals().items())
               if k.startswith("prueba_")]
    for p in pruebas:
        p()

    if fallos:
        print("%d de %d comprobaciones fallan:\n" % (len(fallos), len(pruebas)))
        for f in fallos:
            print("  " + f + "\n")
        return 1
    print("%d pruebas, todas pasan." % len(pruebas))
    return 0


if __name__ == "__main__":
    sys.exit(main())
