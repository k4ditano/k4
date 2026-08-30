#!/usr/bin/env python3
"""Herramienta de traducción de k4.

Tres órdenes, y ninguna necesita saber QML:

    textos.py plantilla     rehace traducciones/plantilla.json con todas las
                            cadenas que hay ahora en la interfaz
    textos.py estado        dice cuánto lleva traducido cada idioma
    textos.py envolver      envuelve en Idioma.t(...) las cadenas que aún están
                            sueltas en el código (--seco para solo mirar)

La clave de cada texto es el propio texto en español. Con más de quinientas
cadenas repartidas por setenta ficheros, inventar un identificador para cada
una es mucho trabajo, se desincroniza sola y deja al traductor mirando
etiquetas en vez de frases. Así, además, lo que no esté traducido sale en
español en vez de salir roto.

De dónde salen las cadenas
--------------------------

De los `.qml` de widgets/, services/ y plugins/ —las propiedades conocidas
(`text:`, `title:`…) y cualquier `Idioma.t("…")` esté donde esté—, y además de
los guiones de `tools/` que marquen las suyas con `T("…")`.

Esa marca hace falta porque un guion de aquí es un programa de línea de
órdenes y habla español, pero parte de lo que imprime NO es para quien lo
ejecuta: sube en JSON y lo pinta la barra, en el idioma que le hayan puesto.
Los verbos del panel de atajos y las etiquetas del portapapeles son eso.

`T` no hace nada —devuelve lo que le den— y por eso sirve de clave igual que
antes. Está solo para que esta herramienta las vea. Sin marcar no cuentan, y
no contar no significa «sin traducir»: significa que NADIE va a avisar de que
están sin traducir. Así pasaron 23 desapercibidas.

Este fichero no se recoge a sí mismo, y las líneas de comentario tampoco: si
no, el ejemplo de aquí arriba entraría en la lista.
"""

import json
import os
import re
import sys

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TRADUCCIONES = os.path.join(RAIZ, "traducciones")
# `core` queda fuera de momento: un par de piezas de ahí ya importaban
# servicios, así que traducirlas es posible, pero el envoltorio automático
# les tocaba los imports y las rompió una vez. Se hará a mano.
CARPETAS = ["widgets", "services", "plugins"]

# Propiedades cuyo valor ve el usuario.
#
#  `texto` estaba faltando, y es la de `BotonAccion`: o sea, TODOS los botones
#  del editor y de media barra. Setenta y dos cadenas que se ven en pantalla
#  —«Cortar aquí», «Separar el audio», «Apagar»— no llegaban nunca a la
#  plantilla, así que no había forma de traducirlas ni de echarlas de menos: no
#  salían como pendientes, salían como si no existieran.
PROPIEDADES = ("text", "texto", "nombre", "desc", "papel", "titulo", "grupo",
               "title")

# Propiedades que llevan identificadores y no se traducen nunca, aunque caigan
# dentro del bloque de un texto. Traducir un `id` rompe el programa en cuanto
# alguien cambia de idioma, y no se nota hasta que pasa.
NO_TEXTO = ("id", "source", "command", "target", "path", "icono", "glifo",
            "tipo", "efecto", "forma", "clase", "hueco", "sprite", "color",
            "de", "requiere", "afinidad", "codigo", "reto", "valor", "etiqueta",
            "family", "objectName", "sufijo", "prefijo")

RE_ABRE = re.compile(r'\b(' + "|".join(PROPIEDADES) + r')\s*:')
RE_ANTES = re.compile(r'\b(' + "|".join(NO_TEXTO) + r')\s*:\s*$')


def traducible(s):
    """Lo que parece texto y de verdad lo es."""
    if len(s.strip()) < 2:
        return False
    if not re.search(r'[A-Za-zÁÉÍÓÚÑáéíóúñü]', s):
        return False
    # identificadores, rutas y órdenes de shell
    if re.match(r'^[a-z0-9_.\-/]+$', s) and " " not in s:
        return False
    if s.startswith("/") or s.startswith("~") or s.startswith("assets/"):
        return False
    # formatos de fecha tipo "d MMMM" o "HH:mm"
    if re.match(r'^[dMyHhms:\s]+$', s):
        return False
    #  Escapes sueltos: `"\r"` no es texto, es una tecla. Sale de que `texto:`
    #  además de la etiqueta de un botón es el nombre de un campo en los
    #  mensajes que se manda la terminal consigo misma.
    if re.match(r'^(\\[nrt])+$', s):
        return False
    #  Un glifo de la fuente escrito como escape —`\u{F0054}`— es un dibujo,
    #  no una palabra: al traductor solo le puede pasar copiarlo o romperlo.
    if re.match(r'^\\u\{[0-9A-Fa-f]+\}$', s):
        return False
    #  Y un color tampoco.
    if re.match(r'^#[0-9A-Fa-f]{3,8}$', s):
        return False
    return True


# ── literales de verdad ──────────────────────────────────────────────
#
#  Buscar cadenas con una expresión regular fue un error caro: `"([^"]{2,})"`
#  no sabe de paridad de comillas, así que en
#      text: "+" + Tokens.cifra(x) + " " + fuente
#  emparejaba la comilla que CIERRA la primera con la que ABRE la segunda y se
#  tragaba el código de en medio como si fuera texto. En pantalla salía
#  «+Idioma.t(72K) claude». Hay que recorrer el renglón carácter a carácter.

def literales(linea):
    """(inicio, fin, contenido) de cada cadena real del renglón."""
    salida = []
    i, n = 0, len(linea)
    while i < n:
        if linea[i] != '"':
            i += 1
            continue
        j = i + 1
        while j < n:
            if linea[j] == "\\":
                j += 2
                continue
            if linea[j] == '"':
                break
            j += 1
        if j >= n:
            break
        salida.append((i, j + 1, linea[i + 1:j]))
        i = j + 1
    return salida


def envolver_linea(linea):
    """Envuelve las cadenas traducibles del renglón, y solo esas."""
    elegidas = []
    for a, b, contenido in literales(linea):
        delante = linea[:a].rstrip()
        if delante.endswith("Idioma.t("):
            continue
        if RE_ANTES.search(delante):
            continue
        if not traducible(contenido):
            continue
        elegidas.append((a, b, contenido))

    if not elegidas:
        return linea, 0

    trozos = []
    ultimo = 0
    for a, b, contenido in elegidas:
        trozos.append(linea[ultimo:a])
        trozos.append('Idioma.t("%s")' % contenido)
        ultimo = b
    trozos.append(linea[ultimo:])
    return "".join(trozos), len(elegidas)


def bloques_de_texto(lineas):
    """Índices de las líneas que forman parte de un binding de texto.

    Se decide mirando la línea SIGUIENTE, no la actual: en QML un ternario se
    parte dejando el `:` al principio del renglón de abajo, así que el de
    arriba parece completo. Mirando solo hacia atrás se escapaban tres de las
    cuatro ramas de cada ternario.
    """
    def limpia(x):
        return x.split("//")[0].rstrip()

    def continua(x):
        return limpia(x).lstrip().startswith(("?", ":", "+", "&&", "||", "."))

    dentro = set()
    i, n = 0, len(lineas)

    while i < n:
        actual = limpia(lineas[i])
        if not RE_ABRE.search(actual):
            i += 1
            continue

        dentro.add(i)

        # `text: {` … `}`: se sigue por llaves hasta cerrar
        if actual.endswith("{"):
            hondo = actual.count("{") - actual.count("}")
            j = i + 1
            while j < n and hondo > 0:
                dentro.add(j)
                hondo += limpia(lineas[j]).count("{") - limpia(lineas[j]).count("}")
                j += 1
            i = j
            continue

        j = i + 1
        while j < n and continua(lineas[j]):
            dentro.add(j)
            j += 1
        i = j

    return dentro


def ficheros():
    for carpeta in CARPETAS:
        base = os.path.join(RAIZ, carpeta)
        for raiz, _, nombres in os.walk(base):
            for n in sorted(nombres):
                if n.endswith(".qml"):
                    yield os.path.join(raiz, n)


#  `Idioma.t("…")` o `Idioma.t('…')`, en cualquier sitio del fichero. Sin
#  escapes dentro: una cadena de interfaz con comillas escapadas es rarísima y
#  aceptarlas obligaría a un analizador de verdad para ganar muy poco.
#  `"clave": "valor"` de un mapa de QML.
RE_PAR = re.compile(r'"([^"\n]+)"\s*:\s*"([^"\n]*)"')

RE_ENVUELTA = re.compile(r'Idioma\.t\(\s*(["\'])((?:[^"\'\\\n]|\\.)*?)\1')


#  `T("…")` en los guiones de `tools/`: cadenas que nacen en Python pero se
#  pintan en la barra —los verbos del panel de atajos, las etiquetas del
#  portapapeles—. Ver la función `T` en esos ficheros para el porqué.
RE_MARCADA = re.compile(r'\bT\(\s*(["\'])((?:[^"\'\\\n]|\\.)*?)\1\s*\)')


def guiones():
    base = os.path.join(RAIZ, "tools")
    for n in sorted(os.listdir(base)):
        #  Este fichero no: documenta la marca con un ejemplo, y recogerse a
        #  sí mismo metía el «…» del comentario en la lista de cadenas.
        if n.endswith(".py") and n != os.path.basename(__file__):
            yield os.path.join(base, n)


def sin_comentarios(texto):
    """Las líneas de código, sin las de comentario.

    Basta con las que EMPIEZAN por almohadilla: es donde se explica la marca,
    y una `T("…")` a media línea después de un `#` no se ha visto nunca. Un
    analizador de verdad para esto sería pagar mucho por muy poco.
    """
    return "\n".join(l for l in texto.split("\n")
                     if not l.lstrip().startswith("#"))


def recolectar():
    """Todas las cadenas de la interfaz, envueltas o no, con dónde salen."""
    encontradas = {}

    #  Lo que marcan los guiones. Va primero para que su procedencia salga en
    #  el informe aunque la misma cadena aparezca luego en un .qml.
    for ruta in guiones():
        try:
            texto = open(ruta, encoding="utf-8").read()
        except OSError:
            continue
        rel = os.path.relpath(ruta, RAIZ)
        for m in RE_MARCADA.finditer(sin_comentarios(texto)):
            if m.group(2):
                encontradas.setdefault(m.group(2), set()).add(rel)
    for ruta in ficheros():
        try:
            texto = open(ruta, encoding="utf-8").read()
        except OSError:
            continue
        rel = os.path.relpath(ruta, RAIZ)
        lineas = texto.split("\n")

        for i in bloques_de_texto(lineas):
            codigo = lineas[i].split("//")[0]
            for a, b, contenido in literales(codigo):
                if RE_ANTES.search(codigo[:a].rstrip()):
                    continue
                if traducible(contenido):
                    encontradas.setdefault(contenido, set()).add(rel)

        #  Y, esté donde esté, lo que ya va envuelto en `Idioma.t("…")`.
        #
        #  Lo de arriba solo mira las PROPIEDADES conocidas —`text:`, `título:`
        #  y compañía—, así que una cadena traducida dentro de un `model:`, de
        #  un `return` o de un operador ternario no se veía. No es teórico: al
        #  portar el editor aparecieron 51 sin traducir, y el «100 %» que
        #  daba esta herramienta era 100 % de lo que alcanzaba a ver.
        #
        #  Aquí no hace falta `traducible()`: si alguien se ha molestado en
        #  envolverla, es que quiere que se traduzca.
        for m in RE_ENVUELTA.finditer(texto):
            encontradas.setdefault(m.group(2), set()).add(rel)

        #  Y la tabla de motivos, que es un caso aparte y hay que nombrarlo.
        #
        #  `Idioma.porque()` traduce en tiempo de ejecución —`t(motivos[c])`—
        #  así que sus frases SÍ hay que traducirlas, pero no están envueltas:
        #  son los valores de un mapa `código: frase`. Sin esto, el contador
        #  volvería a decir 100 % con cincuenta frases sin traducir dentro, que
        #  es exactamente el fallo que tenía antes.
        if rel.endswith("services/Idioma.qml"):
            dentro = texto.split("property var motivos")
            if len(dentro) > 1:
                for m in RE_PAR.finditer(dentro[1].split("})")[0]):
                    if traducible(m.group(2)):
                        encontradas.setdefault(m.group(2), set()).add(rel)
    return encontradas


def envolver(seco=False):
    tocados = 0
    cambios = 0

    for ruta in ficheros():
        if os.path.basename(ruta) == "Idioma.qml":
            continue
        try:
            texto = open(ruta, encoding="utf-8").read()
        except OSError:
            continue

        lineas = texto.split("\n")
        for i in sorted(bloques_de_texto(lineas)):
            codigo = lineas[i].split("//")[0]
            resto = lineas[i][len(codigo):]
            codigo, n = envolver_linea(codigo)
            cambios += n
            lineas[i] = codigo + resto

        nuevo = "\n".join(lineas)
        if nuevo == texto:
            continue

        # Hace falta el import de los servicios para llamar a Idioma. Los
        # singletons viven en la misma carpeta y no lo necesitan.
        if ('import "../../services"' not in nuevo
                and 'import "../services"' not in nuevo
                and "pragma Singleton" not in nuevo):
            rel = os.path.relpath(ruta, RAIZ)
            subida = "../" * rel.count(os.sep)
            marca = "import QtQuick\n"
            if marca in nuevo:
                nuevo = nuevo.replace(marca, marca + 'import "%sservices"\n' % subida, 1)

        tocados += 1
        if not seco:
            open(ruta, "w", encoding="utf-8").write(nuevo)

    print(("(en seco) " if seco else "")
          + "%d cadenas envueltas en %d ficheros" % (cambios, tocados))


def plantilla():
    encontradas = recolectar()
    os.makedirs(TRADUCCIONES, exist_ok=True)

    datos = {
        "_meta": {
            "idioma": "PLANTILLA",
            "codigo": "xx",
            "traducido por": "",
            "cómo": "Copia este fichero a <código>.json, rellena cada valor y "
                    "mándalo por GitHub. Lo que dejes vacío sale en español y "
                    "no rompe nada.",
        }
    }
    for s in sorted(encontradas):
        datos[s] = ""

    ruta = os.path.join(TRADUCCIONES, "plantilla.json")
    with open(ruta, "w", encoding="utf-8") as f:
        json.dump(datos, f, ensure_ascii=False, indent=1)
        f.write("\n")

    print("%d cadenas -> %s" % (len(encontradas), os.path.relpath(ruta, RAIZ)))


def estado():
    encontradas = recolectar()
    total = len(encontradas)
    print("%d cadenas en la interfaz\n" % total)

    if not os.path.isdir(TRADUCCIONES):
        return

    for n in sorted(os.listdir(TRADUCCIONES)):
        if not n.endswith(".json") or n == "plantilla.json":
            continue
        try:
            d = json.load(open(os.path.join(TRADUCCIONES, n), encoding="utf-8"))
        except Exception:
            print("  %s: ilegible" % n)
            continue

        meta = d.pop("_meta", {})
        hechas = sum(1 for k in encontradas if d.get(k))
        sobran = [k for k in d if k not in encontradas]
        pct = hechas / total * 100 if total else 0
        print("  %-12s %-12s %4d/%d  %5.1f%%%s"
              % (n, meta.get("idioma", "?"), hechas, total, pct,
                 "   (%d ya no se usan)" % len(sobran) if sobran else ""))


def main():
    orden = sys.argv[1] if len(sys.argv) > 1 else "estado"
    if orden == "plantilla":
        plantilla()
    elif orden == "envolver":
        envolver("--seco" in sys.argv)
    else:
        estado()


if __name__ == "__main__":
    main()
