#!/usr/bin/env python3
"""Comprueba que ningún plugin se salte la API.

    python3 tools/api.py

La regla de oro de k4: **un plugin importa QtQuick y K4. Nada más.**

No es purismo. Todo lo que un plugin importe de Quickshell solo existe donde
existe Quickshell, o sea en Linux con Wayland. El día que haya un host propio
para Windows o Mac, lo que esté escrito contra `Quickshell.Io` no se porta: hay
que reescribirlo. Lo que esté escrito contra `K4` se porta reescribiendo
únicamente la carpeta api/.

Y hay un beneficio que se nota ya, sin esperar a ningún host: quien quiera
escribir un plugin tiene una API pequeña y documentada en un sitio, en vez de
tener que aprenderse Quickshell entero.

Los servicios de services/ SÍ pueden usar Quickshell directamente: son
implementación, no superficie pública. Si un plugin necesita algo de
plataforma, o se añade a la API o se baja a un servicio.

Esta comprobación existe porque la regla de capas de k4 ya funciona así: se
cumple porque se comprueba. Una regla que solo vive en un comentario dura hasta
el primer día con prisa.
"""
import pathlib, re, sys

RAIZ = pathlib.Path(__file__).resolve().parent.parent


def revisar_documentacion():
    """Que todo lo que la API ofrece esté en la guía.

    Una API pública con tipos que no aparecen en ninguna documentación no
    existe para quien la va a usar: la comprobación es porque pasó — doce
    tipos llevaban tiempo ahí sin una línea que los mencionara, algunos de
    ellos citados como disponibles. Esto lo convierte en un fallo de las
    herramientas en vez de en algo que hay que acordarse de mirar.

    `Puente` se salta a propósito: es fontanería entre el host y la API, no
    algo que un plugin deba tocar.
    """
    qmldir = (RAIZ / "api" / "K4" / "qmldir").read_text()
    tipos = [t for t in re.findall(r"^(?:singleton )?([A-Z]\w+) 1\.0",
                                   qmldir, re.M)
             if t != "Puente"]
    fallos = []
    #  Dos guías y las dos cuentan: la larga para quien escribe
    #  un plugin, y la tabla en inglés de api/LEEME.md, que es lo primero que
    #  mira quien llega al repositorio. Una API que solo está en una de las dos
    #  acaba contándose distinto en cada sitio.
    for doc in ("docs/PLUGINS.md", "api/LEEME.md"):
        texto = (RAIZ / doc).read_text()
        for t in tipos:
            if not re.search(r"\bK4\.%s\b" % t, texto):
                fallos.append("api/K4/%s.qml no se menciona en %s" % (t, doc))
    return fallos


def revisar_api():
    """La regla inversa: un fichero de api/K4 no importa la barra.

    El módulo K4 se resuelve por file:// para todo el mundo, así que un import
    relativo desde dentro carga una SEGUNDA copia de services/ y core/ — dos
    PluginManager, dos oleadas de plugins, cada IPC registrado dos veces. Lo
    que necesite la API se inyecta por el Puente (api/K4/Puente.qml).
    """
    fallos = []
    for f in sorted((RAIZ / "api" / "K4").glob("*.qml")):
        for n, linea in enumerate(f.read_text().split("\n"), 1):
            limpia = re.sub(r"//.*$", "", linea)
            if re.search(r'import\s+"\.\./', limpia):
                fallos.append("api/K4/%s:%d importa la barra por ruta "
                              "relativa: %s" % (f.name, n, limpia.strip()))
    return fallos

#  Lo que un plugin puede importar.
#
#  La línea se traza donde de verdad está: **Qt es portable, Quickshell no**.
#  QtQuick, QtMultimedia, QtQml… existen igual en Windows y en Mac, así que
#  envolverlos no aportaría nada más que una capa que mantener. Quickshell solo
#  existe aquí, y eso es lo que hay que esconder.
#
#  También se permiten los imports por ruta relativa —"../../core"— que son los
#  del propio k4.
PERMITIDOS = re.compile(
    r"^import\s+(Qt\w*(\.\w+)*|K4(\s+as\s+\w+)?|\"[^\"]+\"(\s+as\s+\w+)?)\s*$"
)

# Tipos que delatan un import que se ha colado por otra vía.
SOSPECHOSOS = [
    "Quickshell", "IpcHandler", "SplitParser", "StdioCollector", "FileView",
    "PanelWindow", "WlrLayershell", "WlSessionLock", "GlobalShortcut",
    "DesktopEntries", "QsMenuOpener", "IconImage", "PamContext", "LazyLoader",
]


def sin_comentarios(texto):
    """Quita los // para no delatar menciones en la documentación."""
    return "\n".join(re.sub(r"//.*$", "", l) for l in texto.split("\n"))


def revisar(fichero):
    fallos = []
    texto = fichero.read_text()
    relativa = fichero.relative_to(RAIZ)

    for n, linea in enumerate(texto.split("\n"), 1):
        pelada = linea.strip()
        if not pelada.startswith("import "):
            continue
        if not PERMITIDOS.match(pelada):
            fallos.append((relativa, n, pelada, "import fuera de la API"))

    limpio = sin_comentarios(texto)
    for tipo in SOSPECHOSOS:
        for m in re.finditer(r"\b" + tipo + r"\b", limpio):
            n = limpio[:m.start()].count("\n") + 1
            fallos.append((relativa, n, tipo, "tipo de plataforma sin envolver"))

    return fallos


def main():
    ficheros = sorted((RAIZ / "plugins").rglob("*.qml"))
    if not ficheros:
        print("no encuentro plugins/, ¿desde dónde se está llamando?",
              file=sys.stderr)
        return 2

    todos = []
    for f in ficheros:
        todos.extend(revisar(f))

    sin_doc = revisar_documentacion()
    if sin_doc:
        print("La API ofrece cosas que la guía no cuenta:\n")
        for x in sin_doc:
            print("  " + x)
        print("\nUn tipo público que no está documentado no existe para quien")
        print("va a usarlo.")
        return 1

    #  La regla inversa, que se paga carísima: ver revisar_api().
    dobles = revisar_api()
    if dobles:
        print("La API importa la barra por ruta relativa:\n")
        for x in dobles:
            print("  " + x)
        print("\nEso carga una SEGUNDA copia de services/ y core/: dos")
        print("PluginManager, los plugins creados dos veces y cada IPC")
        print("registrado por duplicado. Lo que necesite la API se inyecta")
        print("desde shell.qml por api/K4/Puente.qml.")
        return 1

    if not todos:
        print("%d ficheros revisados, ninguno se salta la API." % len(ficheros))
        return 0

    print("La API se está saltando en %d sitios:\n" % len(todos))
    for ruta, n, que, porque in todos:
        print("  %s:%d  %s  (%s)" % (ruta, n, que, porque))
    print("\nSi hace falta algo que la API no da, se añade a api/K4 o se baja a")
    print("un servicio. Importarlo a pelo desde un plugin no es una opción.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
