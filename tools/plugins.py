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

import contextlib
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
import time

RAIZ = pathlib.Path(__file__).resolve().parent.parent
CATALOGO = RAIZ / "plugins" / "catalog.json"
DE_USUARIO = pathlib.Path.home() / ".config" / "k4" / "plugins"

RE_ID = re.compile(r"[a-z0-9][a-z0-9-]*")

#  Cuarenta caracteres, en minúsculas y completo. Un SHA corto o una rama NO
#  valen aquí a propósito: la gracia de anclar es que lo que se revisó sea
#  exactamente lo que se instala, y una rama se mueve después de la revisión.
RE_SHA = re.compile(r"[0-9a-f]{40}")

#  Qué puede pedir un plugin de fuera, y qué delata cada permiso en el QML.
#
#  Esto no es un sandbox y no se vende como tal: QML en el mismo proceso puede
#  hacer lo que la barra pueda hacer. Es consentimiento informado — el usuario
#  ve qué declara el plugin antes de encenderlo — más un análisis que convierte
#  el descuido y el engaño simple en un error de instalación.
#  La línea la marca el efecto, no el módulo: mirar el volumen no le hace nada
#  a nadie y cambiarlo sí, así que se vigila `ponerVolumen`, no `K4.Audio`. El
#  portapapeles es la excepción y va al revés — ahí lo delicado es LEER, que
#  guarda contraseñas y tokens, así que basta con nombrarlo.
PERMISOS = {
    #  `K4.Terminal.ejecutar` y `.abrir` corren un guion; que lo lance otro
    #  por ti no lo hace menos correr un guion. Mirar qué terminal hay
    #  —`cual`, `enLaIsla`, `cierre`— no delata nada y va libre.
    "procesos": re.compile(r"\bK4\.Process\b|\bexecDetached\b"
                           r"|\bK4\.Terminal\.(ejecutar|abrir)\b"),
    "red": re.compile(r"\bXMLHttpRequest\b|\bWebSocket\b"),
    "ficheros": re.compile(r"\bK4\.Fichero\b"),
    "audio": re.compile(r"\bK4\.Audio\.(ponerVolumen|alternarSilencio)\b"),
    "medios": re.compile(r"\bK4\.Medios\."
                         r"(alternarPausa|siguiente|anterior|buscar)\b"),
    "notificaciones": re.compile(r"\bK4\.Notificaciones\.limpiar\b"),
    "portapapeles": re.compile(r"\bK4\.Portapapeles\b"),
    "sonido": re.compile(r"\bK4\.Sonido\b"),
    #  La huella entera con solo nombrarla: en datos personales no hay
    #  lectura inocente.
    "datos-personales": re.compile(r"\bK4\.Huella\b"),
}

#  Y QUÉ ES cada plugin: dónde se dibuja y por dónde se le llama.
#
#  Los permisos dicen qué puede TOCAR; esto dice qué OCUPA. Hasta ahora el host
#  lo descubría por efectos secundarios —¿pone `view`? ¿crea una `K4.Ventana`?—
#  y eso tiene dos costes: Ajustes no puede contarte qué es un plugin sin
#  cargarlo, y nadie puede negarle una superficie que no pidió.
#
#  Declararlo es opcional: un manifiesto sin `superficies` sigue valiendo y esto
#  no dice nada. Quien lo declare, se compromete.
#  ── reglas con nombre ────────────────────────────────────────────────
#
#  Los permisos dicen qué API de k4 toca un plugin. Esto es otra cosa: patrones
#  que, estén donde estén —en el QML, en un guion suyo—, hacen que el código
#  que acabas ejecutando NO sea el que alguien miró.
#
#  Cada regla lleva por qué importa y qué hacer, y eso no es adorno: un aviso
#  que no dice cómo arreglarse se ignora, y entonces da igual tenerlo.
#
#  «bloquea» es lo que impide PUBLICAR, no instalar. Si te traes tu propio
#  plugin a tu propia máquina, allá tú; lo que no puede pasar es que el
#  registro le sirva a un desconocido algo que se descarga y ejecuta lo que
#  haya en ese momento en internet.
#
#  Y el resto no bloquean: marcan el envío para que lo mire una persona. Pedir
#  `procesos` no tiene nada de malo —media barra ejecuta cosas— pero es lo que
#  hay que leer antes de firmar.

REGLAS = [
    {
        "id": "descarga-y-ejecuta",
        "que": "Se descarga algo de internet y se lo pasa a una shell",
        "porque": "Lo que se ejecuta es lo que haya en esa URL en ese momento,"
                  " no lo que se revisó. Quien controle la URL controla la"
                  " máquina de quien instale el plugin.",
        "arreglo": ["Trae el fichero, compruébalo y ejecútalo por separado.",
                    "O mejor: mételo en el repositorio del plugin, que así va"
                    " atado al commit."],
        "bloquea": True,
        "patron": re.compile(r"(?:curl|wget)[^\n|;]*\|\s*(?:sudo\s+)?"
                             r"(?:ba|z|k)?sh\b"),
    },
    {
        "id": "clon-sin-commit",
        "que": "Clona un repositorio sin fijar el commit",
        "porque": "Una rama o una etiqueta se mueven. Lo que se ejecute la"
                  " semana que viene no será lo que se miró hoy.",
        "arreglo": ["Pásale el SHA completo y haz `checkout` de él.",
                    "Actualiza ese SHA en un commit tuyo cuando quieras subir"
                    " de versión."],
        #  Este NO bloquea, y es a propósito: saber si un clon está anclado
        #  de verdad es difícil —el `checkout` puede venir tres líneas más
        #  abajo— y un falso positivo pararía a alguien que lo hizo bien. Se
        #  marca para que lo mire una persona, que sí sabe leer tres líneas.
        "bloquea": False,
        "patron": re.compile(r"git\s+clone(?![^\n]*[0-9a-f]{40})"
                             r"[^\n]*(?:https?://|git@)"),
    },
    {
        "id": "sudo-sin-contrasena",
        "que": "Pide root sin que nadie escriba una contraseña",
        "porque": "Cualquier proceso que corra como tú puede invocar eso como"
                  " root, y un plugin no está en ninguna jaula.",
        "arreglo": ["Pide autenticación de verdad, o quítalo.",
                    "Nada de comodines ni de argumentos que venga de fuera."],
        "bloquea": True,
        "patron": re.compile(r"\bNOPASSWD\b|\bsudo\s+-n\b|\bpkexec\b"),
    },
    {
        "id": "qml-desde-texto",
        "que": "Construye QML a partir de una cadena en tiempo de ejecución",
        "porque": "Lo que se ejecuta no está en el repositorio, así que"
                  " revisarlo no dice nada de lo que hará. Si la cadena viene"
                  " de fuera —un fichero, una respuesta— es peor.",
        "arreglo": ["Usa un `Loader` con un componente que esté en el"
                    " repositorio.",
                    "Si la forma cambia, haz varios componentes y elige."],
        "bloquea": False,
        "patron": re.compile(r"\bQt\.createQmlObject\b|\beval\s*\("
                             r"|\bnew\s+Function\s*\("),
    },
    {
        "id": "borra-a-lo-ancho",
        "que": "Borra recursivamente con comodines o rutas de fuera",
        "porque": "Un `rm -rf` con una variable vacía dentro borra otra cosa."
                  " Ha pasado en proyectos con mucha más gente mirando.",
        "arreglo": ["Borra rutas concretas, dentro de la carpeta del plugin.",
                    "Comprueba que la variable no esté vacía antes de usarla."],
        "bloquea": False,
        "patron": re.compile(r"rm\s+-[a-z]*[rR][a-z]*f|rm\s+-[a-z]*f[a-z]*[rR]"),
    },
]

#  Dónde se buscan: en todo lo que el plugin traiga y pueda acabar
#  ejecutándose. Un `.md` no ejecuta nada y un README con un ejemplo de
#  `curl | sh` no es el plugin haciéndolo.
EJECUTABLES = (".qml", ".js", ".sh", ".bash", ".zsh", ".py", ".mjs")


def revisar_reglas(carpeta):
    """Qué reglas incumple lo que hay en esa carpeta, con dónde."""
    fuera = []
    for ruta in sorted(pathlib.Path(carpeta).rglob("*")):
        if not ruta.is_file() or ruta.suffix.lower() not in EJECUTABLES:
            continue
        try:
            texto = ruta.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        rel = str(ruta.relative_to(carpeta))
        for regla in REGLAS:
            for m in regla["patron"].finditer(texto):
                fuera.append({
                    "id": regla["id"],
                    "que": regla["que"],
                    "porque": regla["porque"],
                    "arreglo": regla["arreglo"],
                    "bloquea": regla["bloquea"],
                    "donde": "%s:%d" % (rel, texto[:m.start()].count("\n") + 1),
                })
                break   # una vez por fichero y regla; el resto es ruido
    return fuera


SUPERFICIES = {
    #  Se dibuja en la island: tiene vista.
    "island": re.compile(r"^\s*view\s*:", re.MULTILINE),
    #  Habla en la píldora aunque esté cerrado.
    "pildora": re.compile(r"\bK4\.Pildora\b"),
    #  Pinta FUERA de la island, en su propia superficie.
    "ventana": re.compile(r"\bK4\.Ventana\b"),
    #  Se le puede llamar desde fuera.
    "ipc": re.compile(r"\bK4\.Ipc\b"),
    #  Se queda un atajo global del escritorio.
    "atajo": re.compile(r"\bK4\.Atajo\b"),
}


#  Los COMANDOS que un plugin registra: los targets de IPC por los que se le
#  puede llamar desde fuera y los nombres de atajo que le pide al escritorio.
#
#  Se sacan del QML y no del manifiesto porque es lo que de verdad se registra:
#  un manifiesto puede declarar misa, pero quien se queda `k4.notas` es el
#  `K4.Ipc` que hay escrito. Es la misma idea que los permisos —mirar la fuente
#  y no fiarse de lo declarado— aplicada a lo que se reparte entre plugins.
#
#  La ventana de 400 caracteres es un apaño consciente: en QML `target` y `name`
#  se escriben en la primera o segunda línea del bloque, y casar llaves
#  anidadas con una expresión regular es peor negocio que este recorte. Si
#  alguien esconde su target quinientos caracteres más abajo, aquí no sale — y
#  el choque se lo encontrará en el log, como hasta ahora.
RE_IPC_BLOQUE = re.compile(r"\bK4\.Ipc\b\s*\{")
RE_ATAJO_BLOQUE = re.compile(r"\bK4\.Atajo\b\s*\{")
RE_TARGET = re.compile(r"\btarget\s*:\s*[\"']([^\"']+)[\"']")
RE_NOMBRE = re.compile(r"\bname\s*:\s*[\"']([^\"']+)[\"']")


def comandos_de_texto(texto, ipc, atajos):
    """Apunta en `ipc` y `atajos` lo que registre este QML."""
    for m in RE_IPC_BLOQUE.finditer(texto):
        hallado = RE_TARGET.search(texto[m.end():m.end() + 400])
        if hallado:
            ipc.add(hallado.group(1))
    for m in RE_ATAJO_BLOQUE.finditer(texto):
        hallado = RE_NOMBRE.search(texto[m.end():m.end() + 400])
        if hallado:
            atajos.add(hallado.group(1))


def comandos_de_carpeta(d):
    """`{"ipc": [...], "atajos": [...]}` de una carpeta de plugin."""
    ipc, atajos = set(), set()
    for qml in d.glob("**/*.qml"):
        try:
            texto = "\n".join(re.sub(r"//.*$", "", l)
                              for l in qml.read_text().split("\n"))
        except OSError:
            continue
        comandos_de_texto(texto, ipc, atajos)
    return {"ipc": sorted(ipc), "atajos": sorted(atajos)}


def marcar_choques(combinado):
    """Marca no cargable a quien pida un comando que ya se ha llevado otro.

    Quién gana: el primero del catálogo combinado, y el combinado va con los
    del repo delante. O sea que un plugin de fuera nunca le quita un comando a
    uno de casa — la misma regla que ya rige con los ids.

    Sin esto el choque no se ve: Quickshell registra el primero, deja el
    segundo MUERTO y lo cuenta en el log y en ningún sitio más. El plugin
    figura cargado y sin error, y sus comandos sencillamente no contestan.
    """
    dueno_ipc, dueno_atajo = {}, {}
    for item in combinado:
        if not item.get("cargable", True):
            continue
        cmds = item.get("comandos") or {}
        ident = item.get("id")
        choque = None
        for t in cmds.get("ipc") or []:
            if t in dueno_ipc:
                choque = ("comando-ocupado",
                          f"el comando {t} ya lo registra «{dueno_ipc[t]}»", t)
                break
        if choque is None:
            for n in cmds.get("atajos") or []:
                if n in dueno_atajo:
                    choque = ("atajo-ocupado",
                              f"el atajo {n} ya lo registra «{dueno_atajo[n]}»",
                              n)
                    break
        if choque:
            item["cargable"] = False
            item["motivo"], item["dice"], item["detalle"] = choque
            continue
        for t in cmds.get("ipc") or []:
            dueno_ipc[t] = ident
        for n in cmds.get("atajos") or []:
            dueno_atajo[n] = ident
    return combinado


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


#  Lo que se admite como icono de imagen, y por qué ese mínimo.
#
#  64 px es el tamaño al que se pinta en el centro de aplicaciones en una
#  pantalla normal; por debajo se ve borroso justo donde más se mira. No es
#  un capricho: un icono pixelado hace que un plugin bueno parezca malo.
#  SVG no lleva mínimo — escala, para eso está.
ICONO_MINIMO = 64
ICONO_MAXIMO_MB = 1
ICONO_MAXIMO_BYTES = ICONO_MAXIMO_MB * 1024 * 1024


def medida_png(ruta):
    """Ancho y alto de un PNG leyendo su cabecera. Nada de dependencias: son
    veinticuatro bytes y el formato lleva veinte años sin moverse."""
    with open(ruta, "rb") as f:
        cab = f.read(24)
    if len(cab) < 24 or cab[:8] != b"\x89PNG\r\n\x1a\n" or cab[12:16] != b"IHDR":
        return None
    return (int.from_bytes(cab[16:20], "big"), int.from_bytes(cab[20:24], "big"))


def revisar_icono(carpeta, icono, item):
    """Valida el icono declarado. Devuelve el motivo del fallo, o None.

    Como efecto, deja en `item` lo que la barra necesita: `icono` si es un
    códice, `iconoFichero` (ruta absoluta) si es una imagen. Se separan aquí
    para que el QML no tenga que adivinar de qué clase es.
    """
    if not isinstance(icono, str) or not icono:
        return f"icono debe ser un códice o un fichero, no {icono!r}"

    if re.fullmatch(r"0[xX][0-9a-fA-F]{4,6}", icono):
        item["icono"] = icono
        return None

    #  Un fichero de la propia carpeta: nada de rutas absolutas ni de subir
    #  por ella. El icono de un plugin es SUYO.
    if "/" in icono or icono.startswith("."):
        return "el icono debe ser un fichero de tu carpeta, sin rutas"
    ext = icono.lower().rsplit(".", 1)[-1] if "." in icono else ""
    if ext not in ("png", "svg"):
        return f"icono {icono!r}: solo PNG o SVG (o un códice tipo 0xF04E5)"

    ruta = carpeta / icono
    if not ruta.is_file():
        return f"no existe el icono {icono}"
    if ruta.stat().st_size > ICONO_MAXIMO_BYTES:
        return (f"el icono pesa {ruta.stat().st_size // 1024} KB; el tope es "
                f"{ICONO_MAXIMO_BYTES // 1024} KB")

    if ext == "png":
        medida = medida_png(ruta)
        if medida is None:
            return f"{icono} no es un PNG válido"
        ancho, alto = medida
        if ancho < ICONO_MINIMO or alto < ICONO_MINIMO:
            return (f"el icono es de {ancho}x{alto} y el mínimo es "
                    f"{ICONO_MINIMO}x{ICONO_MINIMO}: más pequeño se ve "
                    f"borroso justo donde más se mira")

    item.pop("icono", None)
    item["iconoFichero"] = str(ruta)
    return None


def validar_carpeta(d, ids_repo, version_host):
    """El veredicto sobre UNA carpeta de plugin: `{…, cargable, motivo}`.

    Vale para una ya instalada y para un clon recién bajado que todavía no ha
    entrado en ~/.config/k4/plugins — que es justo lo que permite validar
    ANTES de instalar, en vez de instalar y ver qué pasa.
    """
    item = {"id": d.name, "title": d.name, "externo": True,
            "enabledByDefault": False, "cargable": True,
            "permisos": [], "version": "0"}

    #  Dos cosas a la vez, y las dos hacen falta:
    #
    #  `motivo` es un CÓDIGO, para la barra, que escribe la frase en el idioma
    #  del usuario. `dice` es la frase en español, para quien está mirando una
    #  terminal — que es el público de este guion y no merece leer códigos.
    #
    #  Antes solo estaba la frase, y acababa en la interfaz: con la barra en
    #  inglés salía el título traducido y el porqué debajo en español.
    def mal(codigo, dice, detalle=""):
        item["cargable"] = False
        item["motivo"] = codigo
        item["dice"] = dice
        if detalle:
            item["detalle"] = detalle
        return item

    manifiesto = d / "plugin.json"
    if not manifiesto.is_file():
        return mal("sin-manifiesto", "sin plugin.json")
    try:
        m = json.loads(manifiesto.read_text())
    except Exception as exc:
        return mal("manifiesto-ilegible", f"plugin.json ilegible: {exc}",
                   str(exc))

    for clave in ("id", "title", "version", "description", "permisos", "host",
                  "aplicacion"):
        if clave in m:
            item[clave] = m[clave]
    ident = m.get("id")
    if not isinstance(ident, str) or not RE_ID.fullmatch(ident):
        return mal("id-invalido", f"id inválido: {ident!r}", str(ident))
    if ident != d.name:
        return mal("id-no-coincide",
                   f"el id {ident!r} no coincide con la carpeta {d.name!r}",
                   f"{ident} / {d.name}")
    if ident in ids_repo:
        return mal("id-ocupado", "el id ya lo usa un plugin de la barra")
    entrada = m.get("entry")
    if not isinstance(entrada, str) or "/" in entrada:
        return mal("entrada-fuera",
                   "entry debe ser un fichero de la propia carpeta")
    ruta = d / entrada
    if not ruta.is_file():
        return mal("sin-entrada", f"no existe {entrada}", str(entrada))
    if not host_compatible(m.get("host"), version_host):
        return mal("barra-vieja",
                   f"pide barra {m.get('host')} y esta es {version_host}",
                   str(m.get("host") or ""))

    #  El icono, que puede ser un códice de la Nerd Font o una imagen propia.
    #  Se valida aquí para que uno mal puesto sea un error de instalación y no
    #  un cuadradito vacío en el centro de aplicaciones.
    if m.get("icono") is not None:
        fallo = revisar_icono(d, m.get("icono"), item)
        if fallo:
            #  El icono trae su propia frase ya escrita; el código es común
            #  porque para el usuario todos son «ese icono no vale».
            return mal("icono-malo", fallo)

    #  El análisis de permisos: lo que el QML usa contra lo declarado.
    declarados = set(m.get("permisos") or [])
    raros = declarados - set(PERMISOS)
    if raros:
        return mal("permisos-raros",
                   "permisos desconocidos: " + ", ".join(sorted(raros)),
                   ", ".join(sorted(raros)))
    usados = set()
    for qml in d.glob("**/*.qml"):
        texto = "\n".join(re.sub(r"//.*$", "", l)
                           for l in qml.read_text().split("\n"))
        for permiso, patron in PERMISOS.items():
            if patron.search(texto):
                usados.add(permiso)
    sin_declarar = usados - declarados
    if sin_declarar:
        return mal("sin-declarar",
                   "usa sin declarar: " + ", ".join(sorted(sin_declarar)),
                   ", ".join(sorted(sin_declarar)))

    #  Las superficies: qué OCUPA, frente a qué TOCA.
    #
    #  Opcional a propósito. Un manifiesto sin `superficies` sigue siendo
    #  válido y esto no dice nada: no se rompe a nadie por una comodidad que
    #  no existía ayer. Pero quien la declare se compromete, y entonces sí se
    #  comprueba contra lo que el QML hace de verdad — que es lo que la
    #  vuelve útil y no un adorno del manifiesto.
    sup_declaradas = m.get("superficies")
    if sup_declaradas is not None:
        sup_declaradas = set(sup_declaradas or [])
        #  Y se pasan al resultado, que si no se validan y se tiran: la tienda
        #  y el informe de un envío preguntan por ellas y les llegaba una
        #  lista vacía aunque el manifiesto las declarase. Toda la gracia de
        #  las superficies es que alguien las VEA antes de encender el plugin.
        item["superficies"] = sorted(sup_declaradas)
        raras = sup_declaradas - set(SUPERFICIES)
        if raras:
            return mal("superficies-raras",
                       "superficies desconocidas: " + ", ".join(sorted(raras)),
                       ", ".join(sorted(raras)))
        sup_usadas = set()
        for qml in d.glob("**/*.qml"):
            texto = "\n".join(re.sub(r"//.*$", "", l)
                               for l in qml.read_text().split("\n"))
            for sup, patron in SUPERFICIES.items():
                if patron.search(texto):
                    sup_usadas.add(sup)
        faltan = sup_usadas - sup_declaradas
        if faltan:
            return mal("superficie-sin-declarar",
                       "ocupa sin declarar: " + ", ".join(sorted(faltan)),
                       ", ".join(sorted(faltan)))

    #  Los comandos que registra, para que la barra los enseñe y para que
    #  `marcar_choques` pueda cruzarlos con los del resto.
    item["comandos"] = comandos_de_carpeta(d)

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
            return mal("sin-qmldir", "no puedo escribir el qmldir")

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
    fuera = []
    for d in sorted(DE_USUARIO.iterdir()):
        if not d.is_dir() or d.name.startswith("."):
            continue
        item = validar_carpeta(d, ids_repo, version_host)
        #  Marcado para la barra: un plugin de casa no se puede quitar ni
        #  actualizar, y la tienda necesita distinguirlos sin adivinar por el
        #  id. Va aquí porque es aquí donde se sabe de dónde salió.
        item["deUsuario"] = True
        fuera.append(item)
    return fuera


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


#  El papel que un plugin instalado lleva encima: de dónde salió y, sobre
#  todo, EN QUÉ COMMIT. Antes era un `.origen` con la URL suelta, y con eso no
#  se podía contestar a «¿qué versión tengo puesta?» ni a «¿ha cambiado el
#  repo desde que la puse?». Se sigue leyendo el viejo para no romper lo que ya
#  está instalado; a la primera actualización se queda en el formato de ahora.
ORIGEN = ".origen.json"


def leer_origen(ident):
    """El papel de un plugin instalado, en el formato de ahora o en el viejo."""
    d = DE_USUARIO / ident
    nuevo = d / ORIGEN
    if nuevo.is_file():
        try:
            o = json.loads(nuevo.read_text())
            if isinstance(o, dict) and o.get("repo"):
                return o
        except Exception:
            pass
    viejo = d / ".origen"
    if viejo.is_file():
        #  El formato de antes: una URL y nada más. Sin carpeta —que era un
        #  fallo: actualizar un plugin que vivía en una subcarpeta del repo
        #  volvía a adivinarla— y sin commit.
        return {"repo": viejo.read_text().strip()}
    return None


def escribir_origen(destino, repo, subcarpeta, commit, item):
    (destino / ORIGEN).write_text(json.dumps({
        "repo": repo,
        "carpeta": subcarpeta or "",
        "commit": commit or "",
        "version": item.get("version", "0"),
        "cuando": int(time.time()),
    }, ensure_ascii=False, indent=1) + "\n")


def _contexto():
    """El par que hace falta para juzgar a un plugin: ids de casa y versión."""
    datos, plugins = leer_catalogo()
    return ({item.get("id") for item in plugins},
            str(datos.get("version", "1.0.0")))


def _commit_de(clon):
    """En qué commit ha quedado el clon, o cadena vacía si no se sabe."""
    try:
        p = subprocess.run(["git", "-C", str(clon), "rev-parse", "HEAD"],
                           capture_output=True, text=True, timeout=20)
        sha = p.stdout.strip()
        return sha if RE_SHA.fullmatch(sha) else ""
    except Exception:
        return ""


def _ir_al_commit(clon, url, commit):
    """Dejar el clon EXACTAMENTE en ese commit. ¿Se ha podido?"""
    g = ["git", "-C", str(clon)]
    #  ¿Ya lo tiene? Pasa cuando el commit pedido es la punta de la rama.
    try:
        if subprocess.run(g + ["cat-file", "-e", commit + "^{commit}"],
                          capture_output=True, timeout=20).returncode == 0:
            return subprocess.run(g + ["checkout", "-q", "--detach", commit],
                                  capture_output=True, timeout=60).returncode == 0
    except Exception:
        return False
    #  Si no, pedirlo suelto. Y si el servidor no los sirve, traer el
    #  historial entero: lento, pero es la única forma de garantizar que se
    #  instala lo que se revisó.
    for traer in (["fetch", "-q", "--depth", "1", url, commit],
                  ["fetch", "-q", "--unshallow"],
                  ["fetch", "-q", url]):
        try:
            subprocess.run(g + traer, capture_output=True, timeout=600)
            if subprocess.run(g + ["checkout", "-q", "--detach", commit],
                              capture_output=True,
                              timeout=60).returncode == 0:
                return True
        except Exception:
            continue
    return False


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


class Traido:
    """Lo que sale de traerse un repo y mirarlo: un plugin válido, o el porqué.

    El `motivo` es un CÓDIGO y el dato va en `detalle`, para que la frase la
    escriba quien sabe en qué idioma está el usuario. Ver `Idioma.porque()`.
    """

    def __init__(self, ok, motivo="", carpeta=None, item=None, commit="",
                 detalle=""):
        self.ok = ok
        self.motivo = motivo
        self.detalle = detalle
        self.carpeta = carpeta
        self.item = item
        self.commit = commit

    def contar(self):
        """Para una persona en una terminal, que sí quiere la frase entera."""
        return self.motivo + (": " + self.detalle if self.detalle else "")


@contextlib.contextmanager
def _traer(url, subcarpeta=None, commit=None):
    """Clonar, anclar, encontrar el plugin dentro y validarlo.

    Está aparte porque lo hacen DOS: instalar, y el examen que la barra pide
    antes de enseñarte los permisos. Y tienen que hacerlo idéntico — si el
    examen mirase una cosa y la instalación trajese otra, el diálogo de
    permisos estaría mintiendo. Por eso el examen devuelve el commit que vio y
    la barra lo pasa como ancla: se instala exactamente lo que se enseñó.

    Cede un `Traido` mientras el temporal sigue vivo. Al salir se borra.
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
            yield Traido(False, "sin-clonar", detalle=f"{url}: {exc}")
            return

        #  Si se pide un commit concreto, se va A ESE y no a la punta de la
        #  rama. Un clon `--depth 1` no lo tiene, así que hay que pedirlo
        #  aparte; si el servidor no sirve SHAs sueltos —GitHub sí—, se cae al
        #  clon entero, que siempre lo tiene.
        if commit:
            if not RE_SHA.fullmatch(commit):
                yield Traido(False, "commit-raro", detalle=str(commit))
                return
            if not _ir_al_commit(clon, url, commit):
                yield Traido(False, "sin-commit",
                             detalle="%s · %s" % (commit[:12], url))
                return

        #  El SHA se apunta SIEMPRE, lo hubieran pedido o no: es la respuesta a
        #  «¿qué tengo instalado exactamente?», y después de borrar el `.git`
        #  ya no hay a quién preguntárselo.
        traido = _commit_de(clon)
        shutil.rmtree(clon / ".git", ignore_errors=True)

        carpeta = (clon / subcarpeta) if subcarpeta else _carpeta_del_clon(clon)
        if carpeta is None or not carpeta.is_dir():
            yield Traido(False, "sin-plugin")
            return

        #  El id manda sobre el nombre del clon: la carpeta se llama como el
        #  repositorio y el manifiesto exige que coincida con el id.
        try:
            ident = json.loads((carpeta / "plugin.json").read_text())["id"]
        except Exception as exc:
            yield Traido(False, "ilegible", detalle=str(exc))
            return
        if isinstance(ident, str) and RE_ID.fullmatch(ident) \
                and carpeta.name != ident:
            nueva = carpeta.parent / ident
            if nueva.exists():
                shutil.rmtree(nueva)
            carpeta = carpeta.rename(nueva)

        item = validar_carpeta(carpeta, ids_repo, version_host)
        if not item.get("cargable"):
            yield Traido(False, "no-cargable",
                         detalle=str(item.get("dice")
                                     or item.get("motivo") or ""),
                         commit=traido)
            return

        yield Traido(True, "", carpeta, item, traido)


def instalar(url, sin_preguntar=False, subcarpeta=None, commit=None):
    """Clonar, validar y —con permiso— instalar un plugin de fuera.

    El orden importa y es el único defendible: se clona a un temporal, se
    valida ENTERO ahí, y solo entonces se enseña lo que declara y se pide
    permiso. Nada llega a ~/.config/k4/plugins sin haber pasado el mismo
    examen que pasan los ya instalados, así que no existe el estado «medio
    instalado y roto».

    Y llega DESHABILITADO, siempre. Instalar es traerlo; encenderlo es otra
    decisión, y se toma en Ajustes viendo estos mismos permisos.
    """
    with _traer(url, subcarpeta, commit) as t:
        if not t.ok:
            print(t.contar(), file=sys.stderr)
            return 1
        carpeta, item, traido = t.carpeta, t.item, t.commit

        destino = DE_USUARIO / item["id"]
        print(f"\nDe {url}:\n")
        print(_describir(item))
        if traido:
            #  El commit sale ANTES de pedir permiso, no después: es parte de
            #  lo que estás aceptando. «Confío en este repo» y «confío en este
            #  código» no son la misma frase.
            print(f"  Commit:   {traido[:12]}"
                  + ("  (el que pediste)" if commit else "  (punta de la rama)"))
        anterior = leer_origen(item["id"]) or {}
        print("\n  Se instalará en", destino)
        print("  Llega apagado: se enciende en Ajustes.")
        if destino.exists():
            print("  YA EXISTE: se reemplaza la versión instalada.")
        print()
        #  Los avisos van ANTES de la frase de siempre y antes de preguntar:
        #  después de un «¿instalar? [s/N]» ya no los lee nadie.
        avisos = revisar_reglas(carpeta)
        if avisos:
            print()
            for a in avisos:
                print("  %s %s" % ("BLOQUEA " if a["bloquea"] else "aviso:  ",
                                   a["que"]))
                print("           en %s" % a["donde"])
                print("           %s" % a["porque"])
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
                print("sin terminal para preguntar; usa --yes si estás seguro.",
                      file=sys.stderr)
                return 1

        DE_USUARIO.mkdir(parents=True, exist_ok=True)
        reemplaza = destino.exists()
        if reemplaza:
            shutil.rmtree(destino)
        shutil.copytree(carpeta, destino)
        escribir_origen(destino, url, subcarpeta, traido, item)

    ident = item["id"]
    if reemplaza:
        print(f"\nactualizado: {ident} v{item.get('version', '0')}.")
        antes = (anterior.get("commit") or "")[:12]
        if traido and antes and antes != traido[:12]:
            print(f"  {antes} → {traido[:12]}")
        elif traido and antes:
            print(f"  sigue en {traido[:12]}: no había nada nuevo.")
        #  Si estaba encendido, en la barra sigue corriendo el código viejo:
        #  el disco cambió, la instancia no.
        print(f"  Si lo tenías encendido: `k4 pluginReload {ident}`.")
    else:
        print(f"\ninstalado: {ident}. Enciéndelo en Ajustes"
              f" (o `k4 pluginRefresh` y `k4 pluginEnable {ident}`).")
    return 0


def actualizar(ident, sin_preguntar=False, commit=None):
    """Reinstalar desde donde vino, y a la carpeta correcta.

    Lo de la carpeta no es un detalle: antes solo se guardaba la URL, así que
    actualizar un plugin que vive en una subcarpeta del repo —los ejemplos de
    k4, sin ir más lejos— volvía a adivinarla, y con más de un candidato ya no
    se podía. Ahora va apuntada.

    Sin `--commit`, actualizar es «tráeme la punta de la rama», que es lo que
    uno espera al pedir una actualización. Con él, «tráeme exactamente este».
    """
    o = leer_origen(ident)
    if not o:
        print(f"{ident} no se instaló desde una URL, no sé de dónde "
              "actualizarlo.", file=sys.stderr)
        return 1
    return instalar(o["repo"], sin_preguntar, o.get("carpeta") or None, commit)


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
            print("sin terminal para preguntar; usa --yes.", file=sys.stderr)
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
        estado = ("ok" if item.get("cargable")
                  else "NO CARGA: %s" % (item.get("dice")
                                         or item.get("motivo") or "?"))
        o = leer_origen(item["id"])
        de = o["repo"] if o else "local"
        if o and o.get("carpeta"):
            de += "  ·  " + o["carpeta"]
        sha = (o or {}).get("commit") or ""
        print(f"{item['id']:<16} v{item.get('version', '0'):<8} {estado}")
        print(f"{'':<16} {de}")
        #  Sin commit apuntado es que se instaló antes de que esto existiera:
        #  se sabe de dónde vino pero no QUÉ vino, y eso hay que decirlo.
        print(f"{'':<16} {sha[:12] if sha else 'commit desconocido (instalado con la versión de antes)'}")
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

    #  Los del repo no pasan por `validar_carpeta` —su catálogo va escrito a
    #  mano—, así que se les miran las fuentes aquí. Sin esto el cruce solo
    #  vería a los de fuera y un plugin de usuario podría quitarle el comando
    #  al lanzador sin que nadie chistara.
    for item in plugins:
        entrada = item.get("entry")
        if not entrada:
            continue
        carpeta = (RAIZ / "plugins" / entrada).parent
        if carpeta.is_dir():
            item["comandos"] = comandos_de_carpeta(carpeta)

    combinado = marcar_choques(list(plugins)
                               + cargar_usuario(ids_repo, version_host))
    print(json.dumps({"schema": 1, "version": version_host,
                      "plugins": combinado}, ensure_ascii=False))
    return 0


#  El escaparate: un JSON público con lo que la comunidad publica. Vive en
#  el propio repositorio para no depender de ningún servidor, y cualquiera
#  puede apuntar a otro con --registro.
REGISTRO = ("https://raw.githubusercontent.com/k4ditano/k4/main/"
            "plugins/registro.json")


def leer_registro(url=None):
    """El registro publicado. Lanza si no se puede leer."""
    import urllib.request
    with urllib.request.urlopen(url or REGISTRO, timeout=10) as r:
        return json.loads(r.read().decode("utf-8"))


def buscar(termino=None, url=None):
    """Lista lo publicado en el registro, filtrado si hay término."""
    try:
        datos = leer_registro(url)
    except Exception as exc:
        print(f"no pude leer el registro: {exc}", file=sys.stderr)
        return 2

    t = (termino or "").lower()
    aciertos = [e for e in datos.get("plugins") or []
                if not t
                or t in str(e.get("id", "")).lower()
                or t in str(e.get("title", "")).lower()
                or t in str(e.get("description", "")).lower()]

    if not aciertos:
        print("nada en el registro"
              + (f" que case con {termino!r}" if t else "") + ".")
        return 1

    for e in aciertos:
        print(f"  {e.get('title', e.get('id'))}  ·  {e.get('id')}"
              + (f"  ·  de {e['autor']}" if e.get("autor") else ""))
        if e.get("description"):
            print(f"    {e['description']}")
        sha = str(e.get("commit") or "")
        if sha:
            print(f"    commit {sha[:12]}")
        orden = f"    install: tools/plugins.py --install {e.get('repo')}"
        if e.get("carpeta"):
            orden += f" --folder {e['carpeta']}"
        #  La orden que se copia y se pega lleva el commit dentro. Si no, la
        #  gente instala la punta de la rama y el ancla no sirve de nada.
        if sha:
            orden += f" --commit {sha}"
        print(orden + "\n")
    return 0


FICHERO_REGISTRO = RAIZ / "plugins" / "registro.json"


def validar_registro(datos, fallos):
    """El registro es un PR de un desconocido: se revisa como tal.

    Se comprueba aquí, en CI, y no al instalar: una entrada mal puesta que
    llegue a `main` se la come todo el que busque, y el error saldría en la
    máquina de otro. Es el mismo trato que reciben los manifiestos.
    """
    entradas = datos.get("plugins")
    if not isinstance(entradas, list):
        fallos.append("el registro no trae una lista de plugins")
        return
    vistos = set()
    for i, e in enumerate(entradas):
        donde = f"registro[{i}]"
        if not isinstance(e, dict):
            fallos.append(f"{donde}: no es un objeto")
            continue
        ident = e.get("id")
        donde = f"registro/{ident}" if ident else donde
        if not isinstance(ident, str) or not RE_ID.fullmatch(ident):
            fallos.append(f"{donde}: id ausente o con formato raro")
        elif ident in vistos:
            fallos.append(f"{donde}: id repetido")
        else:
            vistos.add(ident)
        for campo in ("title", "description", "repo"):
            if not isinstance(e.get(campo), str) or not e[campo].strip():
                fallos.append(f"{donde}: falta {campo}")
        repo = str(e.get("repo") or "")
        if repo and not repo.startswith(("https://", "http://")):
            fallos.append(f"{donde}: el repo tiene que ser una URL http(s)")
        #  El commit es opcional MIENTRAS dure la transición, pero si está
        #  tiene que ser un SHA entero: medio ancla no ancla.
        sha = e.get("commit")
        if sha is not None and (not isinstance(sha, str)
                                or not RE_SHA.fullmatch(sha)):
            fallos.append(f"{donde}: commit tiene que ser un SHA de 40 en "
                          "minúscula")
        carpeta = e.get("carpeta")
        if carpeta is not None:
            c = str(carpeta)
            if c.startswith("/") or ".." in c.split("/"):
                fallos.append(f"{donde}: carpeta tiene que ser relativa y sin ..")


#  ── hablar con la barra ──────────────────────────────────────────────
#
#  Las mismas órdenes, contestando en JSON. No es un guion aparte a propósito:
#  dos caminos para instalar acabarían divergiendo, y el que se usa menos sería
#  el que tiene los fallos. Es el mismo código y la misma validación; lo único
#  que cambia es quién lee la respuesta.
#
#  Una línea por suceso y `flush`, como el editor: la barra quiere enseñar
#  «clonando…» mientras clona, no un tocho cuando acabe.

def _decir(**d):
    print(json.dumps(d, ensure_ascii=False), flush=True)


def json_examinar(url, subcarpeta=None, commit=None):
    """Traerse un plugin, mirarlo y contarlo SIN instalar nada.

    Es la mitad de arriba del diálogo de permisos de la barra. Devuelve el
    commit que ha visto, y la barra lo pasa después como `--commit`: así lo
    que se instala es exactamente lo que se enseñó, aunque la rama se mueva
    entre que lo lees y le das a instalar.
    """
    with _traer(url, subcarpeta, commit) as t:
        if not t.ok:
            _decir(ok=False, motivo=t.motivo, detalle=t.detalle,
                   commit=t.commit)
            return 1
        i = t.item
        anterior = leer_origen(i["id"]) or {}
        _decir(ok=True,
               reglas=revisar_reglas(t.carpeta),
               plugin={
                   "id": i["id"],
                   "title": i.get("title", i["id"]),
                   "version": i.get("version", "0"),
                   "description": i.get("description", ""),
                   "permisos": i.get("permisos") or [],
                   "superficies": i.get("superficies") or [],
                   "host": i.get("host", ""),
               },
               repo=url,
               carpeta=subcarpeta or "",
               commit=t.commit,
               anclado=bool(commit),
               reemplaza=(DE_USUARIO / i["id"]).is_dir(),
               commitAnterior=anterior.get("commit", ""))
    return 0


def json_buscar(url=None):
    """El registro, tal cual, para que lo pinte la barra."""
    try:
        datos = leer_registro(url)
    except Exception as exc:
        _decir(ok=False, motivo="sin-registro", detalle=str(exc))
        return 2
    fallos_reg = []
    validar_registro(datos, fallos_reg)
    #  Un registro con entradas rotas se sirve igual, pero sin las rotas: que
    #  un PR mal puesto no deje la tienda en blanco.
    malas = {f.split("/", 1)[1].split(":")[0] for f in fallos_reg if "/" in f}
    entradas = [e for e in datos.get("plugins") or []
                if str(e.get("id")) not in malas]
    instalado = {}
    for d in (DE_USUARIO.iterdir() if DE_USUARIO.is_dir() else []):
        if d.is_dir():
            o = leer_origen(d.name) or {}
            instalado[d.name] = o.get("commit", "")
    for e in entradas:
        i = str(e.get("id"))
        e["instalado"] = i in instalado
        e["alDia"] = bool(e.get("commit")) and instalado.get(i) == e["commit"]
    _decir(ok=True, plugins=entradas, descartadas=sorted(malas))
    return 0


def json_instalados():
    ids_repo, version_host = _contexto()
    fuera = []
    for item in cargar_usuario(ids_repo, version_host):
        o = leer_origen(item["id"]) or {}
        fuera.append({
            "id": item["id"],
            "version": item.get("version", "0"),
            "title": item.get("title", item["id"]),
            "cargable": bool(item.get("cargable")),
            "motivo": item.get("motivo", ""),
            "detalle": item.get("detalle", ""),
            "dice": item.get("dice", ""),
            "permisos": item.get("permisos") or [],
            "repo": o.get("repo", ""),
            "carpeta": o.get("carpeta", ""),
            "commit": o.get("commit", ""),
            "cuando": o.get("cuando", 0),
        })
    _decir(ok=True, plugins=fuera)
    return 0


def json_comprobar(url=None):
    ids_repo, version_host = _contexto()
    try:
        datos = leer_registro(url)
    except Exception as exc:
        _decir(ok=False, motivo="sin-registro", detalle=str(exc))
        return 2
    publicado = {str(e.get("id")): e for e in datos.get("plugins") or []}
    fuera = []
    for item in cargar_usuario(ids_repo, version_host):
        ident = item["id"]
        mio = str((leer_origen(ident) or {}).get("commit") or "")
        e = publicado.get(ident)
        suyo = str((e or {}).get("commit") or "")
        if not e:
            estado = "fuera-del-registro"
        elif not mio:
            estado = "sin-anclar"
        elif not suyo:
            estado = "registro-sin-commit"
        elif suyo == mio:
            estado = "al-dia"
        else:
            estado = "novedad"
        fuera.append({"id": ident, "estado": estado,
                      "mio": mio, "suyo": suyo})
    _decir(ok=True, plugins=fuera)
    return 0


def comprobar(url=None):
    """Qué tienes instalado que ya no es lo que dice el registro.

    Es la pregunta que antes no se podía contestar: sabías de dónde vino un
    plugin, pero no qué versión de allí, así que «¿tengo lo último?» y «¿me han
    cambiado el código debajo?» eran las dos indistinguibles.
    """
    ids_repo, version_host = _contexto()
    externos = cargar_usuario(ids_repo, version_host)
    if not externos:
        print("no hay plugins de usuario instalados.")
        return 0
    try:
        datos = leer_registro(url)
    except Exception as exc:
        print(f"no pude leer el registro: {exc}", file=sys.stderr)
        return 2
    publicado = {str(e.get("id")): e for e in datos.get("plugins") or []}

    novedades = 0
    for item in externos:
        ident = item["id"]
        o = leer_origen(ident) or {}
        mio = str(o.get("commit") or "")
        e = publicado.get(ident)
        if not e:
            que = "no está en el registro (instalado a mano)"
        elif not mio:
            que = "no sé en qué commit está (instalado con la versión de antes)"
        elif not e.get("commit"):
            que = "el registro no dice commit, no puedo comparar"
        elif str(e["commit"]) == mio:
            que = f"al día  ·  {mio[:12]}"
        else:
            que = f"hay novedad  ·  {mio[:12]} → {str(e['commit'])[:12]}"
            novedades += 1
        print(f"{ident:<16} {que}")

    if novedades:
        print(f"\n{novedades} con novedad. Para traerla:"
              " tools/plugins.py --update <id> --commit <sha>")
    return 0


def main():
    fallos: list[str] = []
    try:
        datos, plugins = leer_catalogo()
    except Exception as exc:
        print(f"catálogo ilegible: {exc}", file=sys.stderr)
        return 2

    ids = validar_repo(plugins, fallos)

    #  Y el escaparate, si está: es parte del repo y se rompe igual de fácil.
    if FICHERO_REGISTRO.is_file():
        try:
            validar_registro(json.loads(FICHERO_REGISTRO.read_text()), fallos)
        except Exception as exc:
            fallos.append(f"registro.json ilegible: {exc}")

    if fallos:
        print("El catálogo de plugins tiene problemas:\n")
        print("\n".join("  - " + x for x in fallos))
        return 1

    version_host = str(datos.get("version", "1.0.0"))

    #  El mismo cruce que hace `listar()`, para que quien valida desde la
    #  terminal vea el choque aquí y no cuando el plugin deje de contestar.
    for item in plugins:
        entrada = item.get("entry")
        if not entrada:
            continue
        carpeta = (RAIZ / "plugins" / entrada).parent
        if carpeta.is_dir():
            item["comandos"] = comandos_de_carpeta(carpeta)

    externos = cargar_usuario(ids, version_host)
    marcar_choques(list(plugins) + externos)
    rotos = [e for e in externos if not e.get("cargable")]
    print(f"{len(plugins)} plugins del repo verificados"
          + (f" · {len(externos)} de usuario" if externos else "")
          + (f" ({len(rotos)} no cargables)" if rotos else "") + ".")
    for e in rotos:
        print(f"  - {e['id']}: {e.get('dice') or e.get('motivo')}")
    return 0


AYUDA = """k4's plugin catalog.

    tools/plugins.py                    validate the repo and what's installed
    tools/plugins.py --new <id>         create one that already runs
    tools/plugins.py --test <id>        open it on its own, without touching your bar
    tools/plugins.py --list             emit the combined catalog (JSON)
    tools/plugins.py --installed        what you have from outside
    tools/plugins.py --install <url>    clone, validate, ask, install
    tools/plugins.py --update <id>      reinstall from where it came
    tools/plugins.py --check            what you have that the registry has moved past
    tools/plugins.py --remove <id>      uninstall
    tools/plugins.py --search [text]    what's published in the registry
    tools/plugins.py --examine <url>    look at a plugin without installing it (JSON)

    --pantalla <m>  with --test, open it on THAT monitor (`hyprctl monitors`)
    --commit <sha>  install or update THAT commit, not the tip of the branch
    --folder <dir>  when plugin.json is not at the repo root
    --registry <url>  point at a registry other than the published one
    --json          answer in JSON, for the bar
    --yes           don't ask (for scripts)
    --with-state    when removing, also delete what the plugin saved
    --help          this

The Spanish flags this started with —--instalar, --probar, --nuevo…— still
work and are not going away. The code speaks Spanish; the door doesn't have
to.
"""


#  ── empezar un plugin, y probarlo sin jugarte el escritorio ──────────
#
#  Las dos cosas que más se echan de menos al escribir el primero. La
#  documentación son quinientas líneas buenas, pero la primera hora no quiere
#  leer: quiere algo que arranque. Y probar cargando el plugin en TU barra —la
#  que lleva tu portapapeles y tu sesión— significa que un bucle infinito te
#  tira el escritorio.

PLANTILLA_MANIFIESTO = """{
  "id": "%(id)s",
  "entry": "%(clase)sPlugin.qml",
  "version": "0.1.0",
  "title": "%(titulo)s",
  "description": "Un plugin recién nacido",
  "host": ">=1.1.0",
  "permisos": [],
  "superficies": ["island"]
}
"""

PLANTILLA_QML = """//  %(titulo)s
//
//  Un plugin de k4 es un objeto con nombre y vista. El host lo crea UNA vez y
//  lo deja vivo; lo que aparece y desaparece es la vista. Por eso el estado se
//  guarda aquí y sobrevive a cerrarla.
//
//  Para probarlo sin tocar tu barra:
//
//      tools/plugins.py --test %(id)s

import QtQuick
import K4 as K4

K4.Plugin {
    id: raiz

    name: "%(id)s"
    title: "%(titulo)s"

    //  Cuánto sitio pide en la island.
    islandWidth: 320
    islandHeight: 120

    //  El host abre y cierra por aquí.
    property bool abierto: false
    active: abierto
    function toggle() { abierto = !abierto }
    //  Sin `close()` el ESC no hace nada: el host cierra llamándola.
    function close() { abierto = false }

    view: Component {
        Item {
            K4.Etiqueta {
                anchors.centerIn: parent
                text: "Hola desde %(titulo)s"
                font.pixelSize: 16
            }
        }
    }
}
"""


def nuevo(ident):
    """Un plugin que ya arranca, para no empezar por una carpeta vacía."""
    if not re.match(r"^[a-z][a-z0-9-]*$", ident or ""):
        print("Un id son minúsculas, números y guiones: mi-plugin")
        return 2
    destino = DE_USUARIO / ident
    if destino.exists():
        print("Ya existe: %s" % destino)
        return 1
    clase = "".join(p.capitalize() for p in ident.split("-"))
    datos = {"id": ident, "titulo": clase, "clase": clase}
    destino.mkdir(parents=True)
    (destino / "plugin.json").write_text(PLANTILLA_MANIFIESTO % datos)
    (destino / (clase + "Plugin.qml")).write_text(PLANTILLA_QML % datos)
    print("Hecho: %s" % destino)
    print()
    print("  tools/plugins.py --test %s    opens it without touching your bar" % ident)
    print("  tools/plugins.py                 validates it")
    print("  quickshell ipc -p shell.qml call k4 pluginEnable %s" % ident)
    return 0


BANCO = """//  Banco de pruebas de un plugin. Lo genera `tools/plugins.py --test`.
//
//  Carga UN plugin y nada más: ni barra, ni servicios, ni tus notificaciones.
//  Si el plugin se cuelga, se cuelga esto y no tu escritorio.
//
//  Vive en la raíz de k4 a propósito: Quickshell no carga ficheros de fuera de
//  la carpeta de la configuración, así que un banco en /tmp no podría abrir el
//  plugin.

import QtQuick
import Quickshell
import Quickshell.Wayland
import K4 as K4

ShellRoot {
    id: banco

    property var plugin: null

    Component.onCompleted: {
        const c = Qt.createComponent("%(entry)s")
        if (c.status === Component.Error) {
            console.log("BANCO no carga:\\n" + c.errorString())
            return
        }
        banco.plugin = c.createObject(null, {
            habilitado: true,
            carpeta: Quickshell.shellPath("%(carpeta)s")
        })
        if (banco.plugin && typeof banco.plugin.toggle === "function")
            banco.plugin.toggle()
        console.log("BANCO listo:", banco.plugin ? banco.plugin.name : "nada")
    }

    PanelWindow {
        visible: banco.plugin !== null

        //  En qué monitor se abre. Vacío es donde el compositor quiera, que
        //  es lo de siempre; con `--pantalla` se manda a uno concreto —para
        //  poder probar en la segunda mientras se usa la primera, que es de
        //  las pocas cosas que un banco de pruebas debe dejarte hacer.
        screen: {
            const quiere = "%(pantalla)s"
            if (quiere.length === 0)
                return null
            const lista = Quickshell.screens
            for (let i = 0; i < lista.length; ++i)
                if (lista[i].name === quiere)
                    return lista[i]
            console.log("BANCO: no hay ninguna pantalla «" + quiere + "»")
            return null
        }

        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        WlrLayershell.namespace: "k4-banco"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        exclusionMode: ExclusionMode.Ignore

        Rectangle {
            anchors.fill: parent
            color: "#cc000000"
            MouseArea { anchors.fill: parent; onClicked: Qt.quit() }
        }

        Rectangle {
            anchors.centerIn: parent
            width: banco.plugin ? banco.plugin.islandWidth : 320
            height: banco.plugin ? banco.plugin.islandHeight : 120
            radius: 14
            color: "#1c1c1e"
            border.width: 1
            border.color: "#3a3a3c"
            clip: true

            Loader {
                anchors.fill: parent
                sourceComponent: banco.plugin ? banco.plugin.view : null
            }
        }

        //  Un recordatorio: es fácil olvidarse de que esto no es la barra.
        Text {
            textFormat: Text.PlainText
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 40
            text: "banco de pruebas · clic fuera para salir"
            color: "#8e8e93"
            font.pixelSize: 12
        }
    }
}
"""


def probar(ident, pantalla=""):
    """Abre UN plugin en una instancia aparte, sin tocar la barra de verdad."""
    #  `leer_catalogo` devuelve (datos, lista): la lista es lo que importa.
    catalogo = {m.get("id"): m for m in leer_catalogo()[1]}
    if ident in catalogo:
        entry = "plugins/" + catalogo[ident]["entry"]
    else:
        manif = DE_USUARIO / ident / "plugin.json"
        if not manif.exists():
            print("No encuentro el plugin «%s»." % ident)
            return 1
        try:
            m = json.loads(manif.read_text(encoding="utf-8"))
        except ValueError as e:
            print("Su plugin.json no se lee: %s" % e)
            return 1
        entry = "externos/%s/%s" % (ident, m.get("entry", ""))

    if not (RAIZ / entry).exists():
        print("El entry no está donde dice el manifiesto: %s" % entry)
        return 1

    banco = RAIZ / ".banco.qml"
    banco.write_text(BANCO % {"entry": entry,
                              "carpeta": str(pathlib.PurePosixPath(entry).parent),
                              "pantalla": pantalla})

    entorno = dict(os.environ)
    api = str(RAIZ / "api")
    entorno["QML_IMPORT_PATH"] = (api + ":" + entorno["QML_IMPORT_PATH"]
                                  if entorno.get("QML_IMPORT_PATH") else api)
    print("Abriendo «%s» en un banco aparte. Clic fuera para salir." % ident)
    try:
        return subprocess.call(["quickshell", "-p", str(banco)], env=entorno)
    except KeyboardInterrupt:
        return 0
    finally:
        try:
            banco.unlink()
        except OSError:
            pass


def _valor(bandera):
    if bandera in sys.argv:
        i = sys.argv.index(bandera)
        if i + 1 < len(sys.argv):
            return sys.argv[i + 1]
    return None


#  Las banderas se escriben en inglés, y las de antes siguen valiendo.
#
#  El código de este proyecto habla español y va a seguir hablándolo, pero una
#  bandera de línea de órdenes no es código: es la puerta. Quien llega a
#  instalar un plugin puede no saber qué es «probar», y un ecosistema al que
#  solo entra quien sepa español no es un ecosistema — el mismo motivo por el
#  que el formulario de publicar está en inglés.
#
#  Las españolas no se retiran ni se avisa de que están viejas: están en el
#  README, en guiones de gente y en los dedos de quien lleva meses usándolas.
#  Cuestan un diccionario.
EN_ESPANOL = {
    "--install": "--instalar",
    "--test": "--probar",
    "--new": "--nuevo",
    "--check": "--comprobar",
    "--search": "--buscar",
    "--remove": "--quitar",
    "--update": "--actualizar",
    "--examine": "--examinar",
    "--list": "--listar",
    "--installed": "--instalados",
    "--reload": "--recargar",
    "--yes": "--si",
    "--folder": "--carpeta",
    "--registry": "--registro",
    "--with-state": "--con-estado",
}


def traducir_banderas(argv):
    """Las banderas en inglés, pasadas a las de dentro."""
    return [EN_ESPANOL.get(a, a) for a in argv]


if __name__ == "__main__":
    #  Antes de mirar nada: así el resto del guion solo conoce un juego de
    #  nombres y no hay que acordarse de aceptar los dos en cada `if`.
    sys.argv = traducir_banderas(sys.argv)

    #  `--help` también, aunque todo esto esté en español: es lo que teclea
    #  cualquiera por reflejo, y sin ello NO fallaba —se caía a validar el
    #  catálogo entero, que tarda y no es lo que le habías pedido.
    if ("--ayuda" in sys.argv or "--help" in sys.argv or "-h" in sys.argv):
        print(AYUDA)
        sys.exit(0)
    _si = "--si" in sys.argv
    _commit = _valor("--commit")
    #  `--json` no es un guion aparte: son las mismas órdenes contestando en
    #  JSON, para que la barra no tenga que leer texto pensado para personas.
    _json = "--json" in sys.argv
    if "--examinar" in sys.argv:
        _url = _valor("--examinar")
        sys.exit(json_examinar(_url, _valor("--carpeta"), _commit)
                 if _url else 2)
    if "--instalar" in sys.argv:
        _url = _valor("--instalar")
        if not _url:
            sys.exit(2)
        _r = instalar(_url, _si, _valor("--carpeta"), _commit)
        if _json:
            _decir(ok=_r == 0, id=_valor("--instalar"))
        sys.exit(_r)
    if "--actualizar" in sys.argv:
        _id = _valor("--actualizar")
        sys.exit(actualizar(_id, _si, _commit) if _id else 2)
    if "--comprobar" in sys.argv:
        _u = _valor("--registro")
        sys.exit(json_comprobar(_u) if _json else comprobar(_u))
    if "--quitar" in sys.argv:
        _id = _valor("--quitar")
        if not _id:
            sys.exit(2)
        _r = quitar(_id, _si, "--con-estado" in sys.argv)
        if _json:
            _decir(ok=_r == 0, id=_id)
        sys.exit(_r)
    if "--buscar" in sys.argv:
        _t = _valor("--buscar")
        if _json:
            sys.exit(json_buscar(_valor("--registro")))
        sys.exit(buscar(None if _t and _t.startswith("--") else _t,
                        _valor("--registro")))
    if "--nuevo" in sys.argv:
        _id = _valor("--nuevo")
        sys.exit(nuevo(_id) if _id else 2)
    if "--probar" in sys.argv:
        _id = _valor("--probar")
        sys.exit(probar(_id, _valor("--pantalla") or "") if _id else 2)
    if "--instalados" in sys.argv:
        sys.exit(json_instalados() if _json else instalados())
    if "--recargar" in sys.argv:
        i = sys.argv.index("--recargar")
        sys.exit(recargar(sys.argv[i + 1]) if i + 1 < len(sys.argv) else 2)
    sys.exit(listar() if "--listar" in sys.argv else main())
