#!/usr/bin/env python3
"""Comprueba que la documentación diga la verdad.

    python3 tools/guia.py

`tools/api.py` ya vigila que ningún tipo de la API se quede sin mencionar. Eso
no basta: que un tipo esté NOMBRADO no garantiza que lo que se dice de él sea
cierto. Un miembro renombrado, un permiso que se fue, una orden de IPC que ya
no existe — la guía los sigue contando igual y nadie se entera hasta que
alguien la sigue al pie de la letra y no le funciona.

Esto comprueba lo que se puede comprobar de verdad:

  · cada `K4.Tipo.miembro` de la documentación existe en api/K4/Tipo.qml;
  · los permisos de la guía y los de tools/plugins.py son los mismos;
  · cada orden de IPC citada existe en algún IpcHandler;
  · cada opción `tools/X.py --opcion` la entiende ese guion;
  · cada fichero del repositorio que se cita existe;
  · cada ejemplo en QML de la guía COMPILA, con qmllint y la API de verdad;
  · los números que la guía promete —64 px de icono, 1 MB, el alto máximo—
    son los que el código usa;
  · cada atajo que se cita existe en hypr/k4.lua.

Lo que NO comprueba —y conviene decirlo en vez de dar una falsa sensación de
red— es si un párrafo en prosa describe bien lo que hace el código. Un ejemplo
que compila puede seguir estando mal explicado. Eso solo lo caza leerlo.
"""
from __future__ import annotations

import pathlib
import re
import shutil
import subprocess
import sys

RAIZ = pathlib.Path(__file__).resolve().parent.parent
API = RAIZ / "api" / "K4"

#  Los documentos que hablan de la API y por tanto pueden mentir sobre ella.
DOCUMENTOS = ["docs/PLUGINS.md", "docs/API.md", "api/LEEME.md", "README.md",
              "docs/GAMES.md"]

#  Nombres que la documentación se INVENTA a propósito, porque está enseñando
#  a crear algo que todavía no existe. Hay que listarlos a mano: no hay forma
#  de distinguir «este fichero se renombró y la guía no se enteró» de «este
#  fichero te toca crearlo a ti» mirando el texto. La lista es corta y se ve de
#  un vistazo si crece de más.
INVENTADOS = {
    "services/MyGame.qml", "GameView.qml", "GamePlugin.qml", "Battle.qml",
    "Party.qml", "Achievements.qml", "Inventory.qml",
}

#  Lo que QtObject y compañía traen puesto: mencionarlo no es un error.
HEREDADOS = {"objectName", "parent", "children", "data", "width", "height",
             "x", "y", "z", "visible", "opacity", "enabled", "anchors",
             "implicitWidth", "implicitHeight", "text", "color", "font",
             "source", "status", "running", "interval", "repeat", "target"}


def miembros_de(tipo):
    """Lo que declara un tipo de la API: propiedades, funciones y señales."""
    f = API / (tipo + ".qml")
    if not f.is_file():
        return None
    texto = "\n".join(re.sub(r"//.*$", "", l) for l in f.read_text().split("\n"))
    salida = set()
    salida |= set(re.findall(r"\bproperty\s+(?:alias\s+)?[\w<>.]+\s+(\w+)", texto))
    salida |= set(re.findall(r"\breadonly\s+property\s+[\w<>.]+\s+(\w+)", texto))
    salida |= set(re.findall(r"\bfunction\s+(\w+)\s*\(", texto))
    salida |= set(re.findall(r"\bsignal\s+(\w+)", texto))
    #  Un tipo que solo reexporta otro (`IpcHandler {}`, `SoundEffect {}`)
    #  hereda todo lo suyo, y eso no está aquí para mirarlo: se marca para no
    #  dar por falsos miembros que sí existen.
    if re.search(r"^\s*(IconImage|IpcHandler|SoundEffect|GlobalShortcut|"
                 r"QsMenuOpener|LazyLoader|PamContext|WlSessionLock\w*)\s*\{",
                 texto, re.M):
        return None
    return salida


def revisar_miembros(doc, texto):
    fallos = []
    for tipo, miembro in re.findall(r"\bK4\.([A-Z]\w+)\.(\w+)", texto):
        declarados = miembros_de(tipo)
        if declarados is None:          # tipo desconocido o reexportación
            if not (API / (tipo + ".qml")).is_file():
                fallos.append(f"{doc}: K4.{tipo} no existe")
            continue
        if miembro not in declarados and miembro not in HEREDADOS:
            fallos.append(f"{doc}: K4.{tipo}.{miembro} no existe "
                          f"(api/K4/{tipo}.qml no lo declara)")
    return fallos


def revisar_permisos(doc, texto):
    """Los permisos que cita la guía contra los que el código comprueba."""
    import importlib.util
    spec = importlib.util.spec_from_file_location("p", RAIZ / "tools" / "plugins.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    reales = set(mod.PERMISOS)

    fallos = []
    #  Solo en la guía larga, que es la que lleva la tabla de permisos.
    if doc != "docs/PLUGINS.md":
        return fallos

    #  Contra la TABLA, no contra el texto suelto: al probarlo quité una fila
    #  y no se enteró, porque la palabra seguía apareciendo dos párrafos más
    #  arriba. Estar mencionado de pasada no es estar documentado — quien
    #  busca qué permisos hay mira la tabla.
    #  `[\w-]`: los permisos pueden llevar guion (datos-personales fue el
    #  primero y destapó que `\w+` no los veía).
    documentados = set(re.findall(r"^\| `([\w-]+)` \|", texto, re.M))

    #  La guía tiene DOS tablas con esta forma: los permisos y las reglas con
    #  nombre. Se separan por lo que son y se comprueban las dos, en vez de
    #  mirar solo una y que la otra pueda mentir sin que nadie se entere.
    reglas = {r["id"] for r in getattr(mod, "REGLAS", [])}

    for p in sorted(reales - documentados):
        fallos.append(f"{doc}: el permiso `{p}` existe y no está en la tabla")
    for r in sorted(reglas - documentados):
        fallos.append(f"{doc}: la regla `{r}` existe y no está en la tabla")
    #  Y al revés: un permiso inventado en la guía manda a alguien a declarar
    #  algo que se rechazará como «permisos desconocidos», y una regla
    #  inventada le hace buscar un aviso que nunca va a saltar.
    for p in sorted(documentados - reales - reglas):
        fallos.append(f"{doc}: la tabla cita `{p}` y no es ni permiso ni regla")
    return fallos


def ordenes_ipc():
    """Todas las funciones que publica algún IpcHandler, por objetivo."""
    salida = {}
    #  Los ejemplos cuentan: la guía enseña `k4.hola toggle` y eso tiene que
    #  seguir existiendo, que es justo lo que se copia y se pega.
    for f in (list((RAIZ / "plugins").rglob("*.qml"))
              + list((RAIZ / "ejemplos").rglob("*.qml"))
              + [RAIZ / "shell.qml"]):
        texto = f.read_text()
        for m in re.finditer(r'target:\s*"([\w.]+)"', texto):
            objetivo = m.group(1)
            #  Desde el target hasta el cierre del bloque, a ojo de llaves.
            resto = texto[m.end():]
            nivel, fin = 1, len(resto)
            for i, c in enumerate(resto):
                if c == "{":
                    nivel += 1
                elif c == "}":
                    nivel -= 1
                    if nivel == 0:
                        fin = i
                        break
            salida.setdefault(objetivo, set()).update(
                re.findall(r"\bfunction\s+(\w+)\s*\(", resto[:fin]))
    return salida


def revisar_ipc(doc, texto):
    ordenes = ordenes_ipc()
    fallos = []
    ids = {p.name for p in (RAIZ / "plugins").iterdir() if p.is_dir()}
    for objetivo, orden in re.findall(r"\bcall\s+(k4[\w.]*)\s+(\w+)", texto):
        conocidas = ordenes.get(objetivo)
        if conocidas is None:
            #  Un objetivo que no existe suele ser un ejemplo inventado
            #  («k4.hello»), y avisar de eso es ruido. Lo que sí importa es un
            #  objetivo REAL al que se le atribuyen órdenes que no tiene.
            continue
        if orden not in conocidas:
            fallos.append(f"{doc}: {objetivo} no tiene la orden {orden}")
    return fallos


def revisar_opciones(doc, texto):
    fallos = []
    for guion, opcion in re.findall(r"tools/(\w+\.py)\s+(--[\w-]+)", texto):
        f = RAIZ / "tools" / guion
        if not f.is_file():
            fallos.append(f"{doc}: no existe tools/{guion}")
        elif f'"{opcion}"' not in f.read_text():
            fallos.append(f"{doc}: tools/{guion} no entiende {opcion}")
    return fallos


def revisar_rutas(doc, texto):
    """Los ficheros y carpetas del repositorio que se citan, entre comillas."""
    fallos = []
    for cita in set(re.findall(r"`([\w./-]+\.(?:qml|py|json|md|tsv|lua|conf))`",
                               texto)):
        #  Sin barra es un nombre suelto —«plugin.json», «shell.qml»— y no una
        #  ruta del repositorio: comprobarlo daría por falso lo que solo es una
        #  forma de nombrar las cosas.
        if "/" not in cita or cita.startswith(("~", "/")) or "*" in cita:
            continue
        if cita in INVENTADOS:
            continue
        if not (RAIZ / cita).exists():
            fallos.append(f"{doc}: cita {cita}, que no existe")
    for cita in set(re.findall(r"`(ejemplos/\w+|plugins/\w+|api/K4|tools)/?`",
                               texto)):
        if not (RAIZ / cita).exists():
            fallos.append(f"{doc}: cita {cita}/, que no existe")
    return fallos


#  Los números que la guía promete y de dónde salen de verdad. Un número en
#  prosa es de lo que más envejece: se cambia la constante y la frase se queda
#  con el valor viejo, tan convincente como el día que era cierto.
#  Los números que la guía promete y de dónde salen de verdad.
#
#  Un número en prosa es de lo que más envejece: se cambia la constante y la
#  frase se queda con el valor viejo, tan convincente como el día que era
#  cierto. Cada entrada dice cómo se escribe en la guía y de dónde sale en el
#  código, y se comparan los dos valores.
#
#  Ojo con la dirección: mi primer intento comprobaba «si la guía dice 64 y el
#  código dice otra cosa», y eso NO caza el caso que importa —la guía diciendo
#  128 cuando el código dice 64—, porque entonces el 64 ya no aparece y no
#  compara nada. Se saca el número DE LA GUÍA y se compara con el del código.
NUMEROS = [
    (r"\*\*(\d+)×\d+\*\*", "tools/plugins.py", r"ICONO_MINIMO\s*=\s*(\d+)",
     "el mínimo de un icono PNG"),
    (r"menos de (\d+) MB", "tools/plugins.py",
     r"ICONO_MAXIMO_MB\s*=\s*(\d+)", "el peso máximo de un icono"),
    (r"\((\d+) hoy\)", "core/Theme.qml", r"maxIslandHeight:\s*(\d+)",
     "el alto máximo de la island"),
]


def revisar_numeros(doc, texto):
    fallos = []
    for en_guia, fuente, en_codigo, que in NUMEROS:
        dicho = re.search(en_guia, texto)
        if not dicho:
            continue
        m = re.search(en_codigo, (RAIZ / fuente).read_text())
        if not m:
            fallos.append(f"{doc}: no encuentro {que} en {fuente}")
            continue
        if dicho.group(1) != m.group(1):
            fallos.append(f"{doc}: dice {dicho.group(1)} para {que} y "
                          f"{fuente} usa {m.group(1)}")
    return fallos


def revisar_atajos(doc, texto):
    """Los atajos que la guía promete tienen que estar en hypr/k4.lua."""
    lua = (RAIZ / "hypr" / "k4.lua").read_text()
    fallos = []
    for combo in set(re.findall(r"\bSUPER\+((?:SHIFT\+|ALT\+|CONTROL\+)*\w+)",
                                texto)):
        partes = combo.split("+")
        tecla = partes[-1]
        mods = partes[:-1]
        #  En el lua se escribe `mod .. " + SHIFT + Space"`.
        esperado = " + ".join(mods + [tecla])
        if not re.search(r'mod \.\. " \+ %s"' % re.escape(esperado), lua):
            fallos.append(f"{doc}: promete el atajo SUPER+{combo} y "
                          f"hypr/k4.lua no lo ata")
    return fallos


#  qmllint se muere EN SILENCIO —sale con 255 y sin una palabra— en cuanto ve
#  una función con tipo de retorno, `function toggle(): void`. Y esas no son
#  opcionales: el IPC de Quickshell las exige. Así que se le quitan antes de
#  pasárselo. Costó un rato descubrirlo porque no dice nada.
RE_TIPADA = re.compile(r"function (\w+)\(([^)]*)\):\s*\w+")


def revisar_ejemplos(doc, texto):
    """Que los ejemplos en QML de la guía compilen de verdad."""
    if not shutil.which("qmllint"):
        return []
    fallos = []
    bloques = re.findall(r"```qml\n(.*?)```", texto, re.S)
    for i, bloque in enumerate(bloques, 1):
        cuerpo = RE_TIPADA.sub(r"function \1(\2)", bloque)
        sin_comentarios = "\n".join(
            l for l in cuerpo.split("\n") if not l.strip().startswith("//"))
        primera = next((l for l in sin_comentarios.split("\n") if l.strip()), "")
        #  Solo los que son un objeto completo. Un trozo suelto de propiedades
        #  no se puede compilar solo y envolverlo sería inventarse contexto.
        if not re.match(r"^[A-Z]\w*(\.\w+)?\s*\{", primera.strip()):
            continue
        #  Ni los que llevan puntos suspensivos: `{ ... }` es «aquí va lo
        #  tuyo», no código. Exigirle que compile sería exigirle que deje de
        #  ser un ejemplo.
        if re.search(r"(^|\s)\.\.\.($|\s)", sin_comentarios):
            continue
        #  Ni los que enseñan dos objetos sueltos para comparar: eso no es un
        #  fichero.
        if len(re.findall(r"^[A-Z]\w*(?:\.\w+)?\s*\{", sin_comentarios,
                          re.M)) > 1:
            continue
        if "import " not in cuerpo:
            cuerpo = "import QtQuick\nimport QtQuick.Layouts\nimport K4 as K4\n\n" + cuerpo
        tmp = RAIZ / "tools" / ".guia_tmp.qml"
        tmp.write_text(cuerpo)
        r = subprocess.run(["qmllint", "-I", str(RAIZ / "api"), str(tmp)],
                           capture_output=True, text=True)
        tmp.unlink(missing_ok=True)
        if r.returncode != 0:
            aviso = (r.stdout + r.stderr).strip().split("\n")
            aviso = next((l for l in aviso if l.strip()), "qmllint salió %d"
                         % r.returncode)
            fallos.append(f"{doc}: el ejemplo {i} no compila: {aviso[:120]}")
    return fallos


def revisar_motivos():
    """Todo motivo que alguien emita tiene que tener frase en `Idioma`.

    Un motivo sin frase no falla: sale el código crudo en la interfaz —
    «sin-declarar» en mitad de Ajustes—, que es feo y además no dice nada a
    quien no ha leído el guion. Es exactamente el fallo que había, y la única
    manera de que no vuelva es que añadir uno sin su frase pare el flujo.
    """
    fallos = []
    idioma = RAIZ / "services" / "Idioma.qml"
    if not idioma.is_file():
        return ["falta services/Idioma.qml"]
    bloque = idioma.read_text().split("readonly property var motivos")
    if len(bloque) < 2:
        return ["services/Idioma.qml ya no tiene la tabla de motivos"]
    conocidos = set(re.findall(r'"([^"\n]+)"\s*:\s*"',
                               bloque[1].split("})")[0]))

    #  Los que emiten los guiones y los que emite la propia barra.
    emitidos = {}
    for ruta in list((RAIZ / "tools").glob("*.py")):
        if ruta.name.startswith("prueba_"):
            continue
        t = ruta.read_text()
        for m in re.finditer(r'motivo=["\']([a-z][a-z0-9-]*)["\']', t):
            emitidos.setdefault(m.group(1), set()).add(ruta.name)
        for m in re.finditer(r'mal\(\s*"([a-z][a-z0-9-]*)"', t):
            emitidos.setdefault(m.group(1), set()).add(ruta.name)
    for ruta in list((RAIZ / "services").glob("*.qml")) \
            + list((RAIZ / "plugins").glob("*/*.qml")):
        t = ruta.read_text()
        for m in re.finditer(
                r'(?:fallo|fotoFallida|videoFallido)\(\s*"([a-z][a-z0-9-]*)"', t):
            emitidos.setdefault(m.group(1), set()).add(ruta.name)

    for codigo, donde in sorted(emitidos.items()):
        if codigo not in conocidos:
            fallos.append("services/Idioma.qml: falta la frase del motivo "
                          "`%s`, que emite %s"
                          % (codigo, ", ".join(sorted(donde))))
    return fallos


def main():
    fallos = []
    for doc in DOCUMENTOS:
        f = RAIZ / doc
        if not f.is_file():
            fallos.append(f"falta el documento {doc}")
            continue
        texto = f.read_text()
        fallos += revisar_miembros(doc, texto)
        fallos += revisar_permisos(doc, texto)
        fallos += revisar_ipc(doc, texto)
        fallos += revisar_opciones(doc, texto)
        fallos += revisar_rutas(doc, texto)
        fallos += revisar_numeros(doc, texto)
        fallos += revisar_atajos(doc, texto)
        fallos += revisar_ejemplos(doc, texto)

    fallos += revisar_motivos()

    if not fallos:
        print("%d documentos revisados, no le mienten al código."
              % len(DOCUMENTOS))
        return 0

    print("La documentación dice cosas que no son:\n")
    for x in fallos:
        print("  " + x)
    return 1


if __name__ == "__main__":
    sys.exit(main())
