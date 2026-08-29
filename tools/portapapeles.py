#!/usr/bin/env python3
"""Almacén del historial del portapapeles.

Quickshell expone `clipboardText`, pero en Wayland su señal de cambio no salta
cuando copia otra aplicación —probado: ni siquiera lee el contenido inicial—,
así que quien vigila es `wl-paste --watch`, que sí se entera de todo. Este
guión es lo que ese vigilante ejecuta en cada copia.

Órdenes:

    guardar texto|imagen   lee la copia de la entrada estándar y la archiva
    listar                 saca el índice en JSON, lo más nuevo primero
    copiar <id>            devuelve esa entrada al portapapeles
    borrar <id>            la quita
    fijar <id>             la clava arriba, y ya no caduca
    limpiar                borra todo lo que no esté fijado

Cada entrada se guarda en su propio fichero y el índice solo lleva lo que hace
falta para pintar la lista. El identificador es el hash del contenido, así que
volver a copiar lo mismo no duplica: lo sube arriba y ya está.
"""

import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time

BASE = os.path.expanduser("~/.local/state/k4/portapapeles")
DATOS = os.path.join(BASE, "datos")
INDICE = os.path.join(BASE, "indice.json")

TOPE_ENTRADAS = 300
TOPE_BYTES = 8 * 1024 * 1024      # una copia mayor que esto no vale la pena
#  Y un techo para el conjunto: 300 entradas de imágenes generosas podían
#  ser cientos de MB perfectamente legales. El historial es una comodidad,
#  no un archivo: lo viejo cede sitio.
TOPE_TOTAL = 50 * 1024 * 1024
RESUMEN = 400                     # lo que se guarda para pintar la fila


# ── índice ───────────────────────────────────────────────────────────

def carga():
    try:
        with open(INDICE) as f:
            d = json.load(f)
        return d.get("entradas", [])
    except Exception:
        return []


def guarda(entradas):
    os.makedirs(BASE, exist_ok=True)
    tmp = INDICE + ".tmp"
    with open(tmp, "w") as f:
        json.dump({"entradas": entradas}, f)
    os.replace(tmp, INDICE)


def ruta(ident):
    return os.path.join(DATOS, ident)


# ── de qué es esto ───────────────────────────────────────────────────
#
#  Una etiqueta corta ayuda a encontrar de un vistazo «ese color» o «ese
#  enlace» entre doscientas líneas de texto plano.

RE_URL = re.compile(r"^\s*(https?|ftp|ssh|magnet)://\S+\s*$", re.I)
RE_COLOR = re.compile(r"^\s*#[0-9a-fA-F]{3,8}\s*$")
RE_RUTA = re.compile(r"^\s*[~/][^\s\0]*\s*$")
RE_ORDEN = re.compile(r"^\s*(sudo|git|npm|pnpm|yarn|cargo|python3?|pip|docker|"
                      r"systemctl|pacman|yay|ssh|scp|curl|wget|make|cmake|kubectl)\b")


#  ── una cadena que acaba en la BARRA ─────────────────────────────────
#
#  No hace nada: devuelve lo que le den. Está para MARCAR, porque estas
#  cadenas son de interfaz aunque nazcan en un guion de línea de órdenes —las
#  pinta la barra, en el idioma que le hayan puesto— y `tools/textos.py` las
#  recoge buscando exactamente esta llamada.
#
#  Sin la marca no cuentan para la cobertura, y una cadena que no cuenta es
#  una cadena que un día sale sin traducir y nadie se entera.
def T(s):
    return s


#  Las etiquetas se pintan en la barra, así que van marcadas. Y siguen
#  valiendo de clave: `T` devuelve lo que le den, y ClipboardView elige el
#  glifo comparando con estas mismas palabras.
def etiqueta(texto):
    if RE_URL.match(texto):
        return T("enlace")
    if RE_COLOR.match(texto):
        return T("color")
    if RE_RUTA.match(texto) and len(texto) < 300:
        return T("ruta")
    if RE_ORDEN.match(texto):
        return T("orden")
    if "\n" in texto.strip() and re.search(r"[{};()=]|^\s{2,}", texto, re.M):
        return T("código")
    return ""


def es_secreto():
    """¿Lo ha puesto un gestor de contraseñas?

    Los gestores marcan la oferta con una pista propia justo para que los
    historiales no la archiven. Guardarla sería la peor clase de fallo, así
    que ante la duda no se guarda.
    """
    try:
        tipos = subprocess.run(["wl-paste", "--list-types"],
                               capture_output=True, text=True, timeout=2).stdout
    except Exception:
        return False
    return "password" in tipos.lower() or "x-kde-passwordManagerHint" in tipos


# ── guardar ──────────────────────────────────────────────────────────

def guardar(tipo):
    bruto = sys.stdin.buffer.read()
    if not bruto or len(bruto) > TOPE_BYTES:
        return

    if tipo == "texto":
        try:
            texto = bruto.decode("utf-8")
        except UnicodeDecodeError:
            return
        if not texto.strip():
            return
        if es_secreto():
            return
        resumen = texto[:RESUMEN]
        marca = etiqueta(texto)
        mime = "text/plain"
    else:
        resumen = ""
        #  También se pinta, así que también va marcada. Y sigue siendo la
        #  clave con la que el servicio distingue una imagen (`tipo`).
        marca = T("imagen")
        mime = "image/png"

    ident = hashlib.sha1(bruto).hexdigest()[:16]
    entradas = carga()

    # ya estaba: sube arriba y conserva si estaba fijada
    previa = None
    for e in entradas:
        if e["id"] == ident:
            previa = e
            break
    if previa:
        entradas.remove(previa)
        previa["cuando"] = time.time()
        entradas.insert(0, previa)
        guarda(entradas)
        print("nuevo", flush=True)
        return

    os.makedirs(DATOS, exist_ok=True)
    with open(ruta(ident), "wb") as f:
        f.write(bruto)

    entradas.insert(0, {
        "id": ident,
        "tipo": tipo,
        "mime": mime,
        "resumen": resumen,
        "etiqueta": marca,
        "bytes": len(bruto),
        "lineas": resumen.count("\n") + 1 if tipo == "texto" else 0,
        "cuando": time.time(),
        "fijado": False,
    })

    podar(entradas)
    guarda(entradas)
    print("nuevo", flush=True)


def podar(entradas):
    """Recorta por el final —número Y bytes totales—, sin tocar lo fijado."""
    sobran = max(0, len(entradas) - TOPE_ENTRADAS)

    def peso(e):
        try:
            return os.path.getsize(ruta(e["id"]))
        except OSError:
            return 0

    total = sum(peso(e) for e in entradas)

    for e in reversed(list(entradas)):
        if sobran <= 0 and total <= TOPE_TOTAL:
            break
        if e.get("fijado"):
            continue
        total -= peso(e)
        entradas.remove(e)
        try:
            os.remove(ruta(e["id"]))
        except OSError:
            pass
        sobran -= 1


# ── el resto de órdenes ──────────────────────────────────────────────

def listar():
    # Lo fijado primero y, dentro de cada grupo, lo más reciente arriba.
    entradas = carga()
    entradas.sort(key=lambda e: (not e.get("fijado"), -e.get("cuando", 0)))
    for e in entradas:
        e["ruta"] = ruta(e["id"])
    print(json.dumps({"entradas": entradas}), flush=True)


def copiar(ident):
    entradas = carga()
    for e in entradas:
        if e["id"] != ident:
            continue
        try:
            with open(ruta(ident), "rb") as f:
                datos = f.read()
        except OSError:
            return
        # --type explícito: sin él wl-copy adivina, y una imagen pegada como
        # texto sale como un churro de bytes
        subprocess.run(["wl-copy", "--type", e.get("mime", "text/plain")],
                       input=datos, check=False)
        return


def borrar(ident):
    entradas = [e for e in carga() if e["id"] != ident]
    try:
        os.remove(ruta(ident))
    except OSError:
        pass
    guarda(entradas)
    print("nuevo", flush=True)


def fijar(ident):
    entradas = carga()
    for e in entradas:
        if e["id"] == ident:
            e["fijado"] = not e.get("fijado", False)
    guarda(entradas)
    print("nuevo", flush=True)


def limpiar():
    entradas = carga()
    quedan = [e for e in entradas if e.get("fijado")]
    conservados = {e["id"] for e in quedan}

    for e in entradas:
        if e["id"] in conservados:
            continue
        try:
            os.remove(ruta(e["id"]))
        except OSError:
            pass

    guarda(quedan)
    print("nuevo", flush=True)


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return

    orden = sys.argv[1]
    arg = sys.argv[2] if len(sys.argv) > 2 else ""

    if orden == "guardar":
        guardar(arg or "texto")
    elif orden == "listar":
        listar()
    elif orden == "copiar":
        copiar(arg)
    elif orden == "borrar":
        borrar(arg)
    elif orden == "fijar":
        fijar(arg)
    elif orden == "limpiar":
        limpiar()


if __name__ == "__main__":
    main()
