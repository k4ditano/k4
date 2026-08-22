#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Revisar un envío de plugin y, si se aprueba, publicarlo en el registro.

    python3 tools/publicar.py --revisar <cuerpo.txt>   informe en markdown
    python3 tools/publicar.py --anadir  <cuerpo.txt>   mete la entrada al registro

El envío llega como una incidencia con un formulario. Este guion lee ese
cuerpo, se trae EL COMMIT que dice, lo valida con el mismo `tools/plugins.py`
que usa todo lo demás, y escribe un informe.

Dos cosas que no hace, y son a propósito:

**No ejecuta nada del plugin.** Clona, mira ficheros y compara lo que el
manifiesto DECLARA contra lo que el QML usa de verdad. Eso es análisis
estático y nada más. Ejecutar código de un desconocido en el runner para
decidir si es de fiar es exactamente al revés.

**No publica solo.** `--revisar` corre en cada apertura y edición de la
incidencia y no toca el registro; `--anadir` solo lo dispara una etiqueta que
pone una persona. El robot dice lo que ve; publicar es una firma.

Y el informe se ata al commit: si el repositorio cambia entre la revisión y la
aprobación, los SHA no casan y `--anadir` se niega. Sin eso, aprobar sería
aprobar «ese repositorio», que es una promesa que nadie puede cumplir.
"""

from __future__ import annotations

import io
import json
import os
import pathlib
import re
import subprocess
import sys

RAIZ = pathlib.Path(__file__).resolve().parent.parent
REGISTRO = RAIZ / "plugins" / "registro.json"
GUION = RAIZ / "tools" / "plugins.py"

RE_SHA = re.compile(r"^[0-9a-f]{40}$")
RE_REPO = re.compile(r"^https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/?$")


#  ── leer el formulario ───────────────────────────────────────────────
#
#  Los formularios de incidencia de GitHub llegan como markdown: un `### ` con
#  el rótulo del campo y debajo el valor. Se lee así y no con JSON porque es lo
#  que hay: la API no devuelve los campos por separado.

def campos(cuerpo):
    """Los campos del formulario, por rótulo en minúsculas."""
    fuera = {}
    rotulo = None
    lineas = []
    for linea in (cuerpo or "").splitlines():
        if linea.startswith("### "):
            if rotulo:
                fuera[rotulo] = "\n".join(lineas).strip()
            rotulo = linea[4:].strip().lower()
            lineas = []
        elif rotulo:
            lineas.append(linea)
    if rotulo:
        fuera[rotulo] = "\n".join(lineas).strip()
    #  «_No response_» es lo que escribe GitHub en un campo opcional vacío.
    return {k: ("" if v == "_No response_" else v) for k, v in fuera.items()}


def envio(cuerpo):
    """Lo que pide el formulario, ya limpio, o los motivos por los que no."""
    c = campos(cuerpo)

    def dame(*nombres):
        for n in nombres:
            if c.get(n):
                return c[n].strip()
        return ""

    d = {
        "repo": dame("repositorio", "repository", "repo"),
        "commit": dame("commit", "sha").lower(),
        "carpeta": dame("carpeta", "folder", "subcarpeta"),
    }
    malos = []
    if not RE_REPO.match(d["repo"]):
        malos.append("El repositorio tiene que ser una URL de GitHub pública, "
                     "de la forma `https://github.com/quien/que`.")
    if not RE_SHA.match(d["commit"]):
        malos.append("El commit tiene que ser el SHA completo de 40 "
                     "caracteres, en minúscula. Una rama no vale: se mueve "
                     "después de la revisión, y entonces lo que se instala ya "
                     "no es lo que se revisó.")
    if d["carpeta"] and (d["carpeta"].startswith("/")
                         or ".." in d["carpeta"].split("/")):
        malos.append("La carpeta tiene que ser relativa y sin `..`.")
    d["repo"] = d["repo"].rstrip("/")
    return d, malos


#  ── mirar el plugin ──────────────────────────────────────────────────

def examinar(d):
    """Lo que dice `plugins.py --examine` de ese commit exacto."""
    orden = [sys.executable, str(GUION), "--examine", d["repo"],
             "--json", "--commit", d["commit"]]
    if d["carpeta"]:
        orden += ["--folder", d["carpeta"]]
    try:
        p = subprocess.run(orden, capture_output=True, text=True, timeout=600)
    except subprocess.TimeoutExpired:
        return {"ok": False, "motivo": "el repositorio tardó demasiado en "
                                       "clonarse (más de diez minutos)"}
    for linea in reversed((p.stdout or "").strip().splitlines()):
        linea = linea.strip()
        if linea.startswith("{"):
            try:
                return json.loads(linea)
            except ValueError:
                continue
    return {"ok": False,
            "motivo": (p.stderr or "").strip()[:400] or "sin respuesta"}


def ya_publicado(ident):
    try:
        d = json.loads(REGISTRO.read_text())
    except Exception:
        return None
    for e in d.get("plugins") or []:
        if str(e.get("id")) == ident:
            return e
    return None


#  ── el informe ───────────────────────────────────────────────────────

def informe(d, malos, res):
    """Markdown para comentar en la incidencia, y el veredicto."""
    if malos:
        cuerpo = ["El formulario tiene algo que arreglar:", ""]
        cuerpo += ["- " + m for m in malos]
        cuerpo += ["", "Edita la incidencia y se vuelve a revisar sola."]
        return "\n".join(cuerpo), "necesita-arreglos"

    if not res.get("ok"):
        return ("No he podido validar ese commit:\n\n> %s\n\n"
                "Arréglalo y edita la incidencia: se revisa otra vez sola."
                % res.get("motivo", "sin motivo"), "necesita-arreglos")

    p = res["plugin"]
    ident = str(p.get("id", ""))
    antes = ya_publicado(ident)
    permisos = p.get("permisos") or []
    superficies = p.get("superficies") or []

    l = []
    l.append("**%s** · `%s` · v%s" % (p.get("title", ident), ident,
                                      p.get("version", "0")))
    if p.get("description"):
        l.append("")
        l.append(p["description"])
    l.append("")
    l.append("| | |")
    l.append("|---|---|")
    l.append("| Repositorio | %s |" % d["repo"])
    l.append("| Commit | `%s` |" % d["commit"])
    if d["carpeta"]:
        l.append("| Carpeta | `%s` |" % d["carpeta"])
    l.append("| Host que pide | `%s` |" % (p.get("host") or "cualquiera"))
    l.append("| Permisos | %s |"
             % (", ".join("`%s`" % x for x in permisos) if permisos
                else "ninguno"))
    l.append("| Superficies | %s |"
             % (", ".join("`%s`" % x for x in superficies) if superficies
                else "sin declarar"))
    l.append("")

    if antes:
        if str(antes.get("commit") or "") == d["commit"]:
            l.append("Ese id ya está publicado **en este mismo commit**: no "
                     "hay nada que cambiar.")
            return "\n".join(l), "necesita-arreglos"
        l.append("Actualiza a `%s`, que ya está publicado en `%s`."
                 % (ident, str(antes.get("commit") or "?")[:12]))
        l.append("")

    #  Las reglas, si alguna salta. Cada una con su porqué y su arreglo: un
    #  aviso que no dice cómo arreglarse se ignora, y entonces sobra.
    reglas = res.get("reglas") or []
    bloquean = [r for r in reglas if r.get("bloquea")]
    if reglas:
        l.append("")
        l.append("### Lo que ha saltado")
        l.append("")
        for r in reglas:
            l.append("**%s** — %s  \n`%s`"
                     % ("Hay que arreglarlo" if r.get("bloquea") else "Para mirar",
                        r.get("que", r.get("id")), r.get("donde", "")))
            l.append("")
            l.append("> %s" % r.get("porque", ""))
            l.append("")
            for paso in r.get("arreglo") or []:
                l.append("- %s" % paso)
            l.append("")

    l.append("Validado con `tools/plugins.py`, que compara lo que el "
             "manifiesto declara contra lo que el QML usa de verdad: usar algo "
             "sin declararlo deja el plugin sin cargar y no llegaría hasta "
             "aquí.")
    l.append("")
    l.append("**Esto no es una auditoría de seguridad.** Es una comprobación "
             "estática de un commit concreto, sin ejecutar nada del plugin. Un "
             "plugin corre dentro de la barra y puede hacer lo que la barra "
             "pueda hacer; los permisos son lo que declara, no una jaula.")

    #  Pedir permisos no es un problema —un reproductor necesita `sonido`—,
    #  pero sí es lo que una persona tiene que mirar antes de firmar.
    if bloquean:
        l.append("")
        l.append("Eso de arriba hay que arreglarlo antes de publicar: hace que"
                 " el código que la gente acabe ejecutando no sea el de este"
                 " commit, y entonces revisarlo no sirve de nada. Sube el"
                 " arreglo y edita la incidencia con el SHA nuevo.")
        return "\n".join(l), "necesita-arreglos"

    etiqueta = ("revision-de-seguridad" if (permisos or reglas) else "validado")
    if permisos or reglas:
        l.append("")
        l.append("Nada de esto impide publicar, pero lo mira una persona antes"
                 " de firmarlo.")
    return "\n".join(l), etiqueta


#  ── publicar ─────────────────────────────────────────────────────────

def anadir(d, res):
    """Meter la entrada en el registro. Solo tras la etiqueta de una persona."""
    if not res.get("ok"):
        print("no valido: no se publica", file=sys.stderr)
        return 1
    #  El informe se ató a un commit; si el que se aprueba es otro, esto se
    #  para. Aprobar «el repositorio» sería aprobar lo que venga después.
    if res.get("commit") != d["commit"]:
        print("el commit revisado (%s) no es el que se aprueba (%s)"
              % (res.get("commit"), d["commit"]), file=sys.stderr)
        return 1
    #  Y aunque alguien ponga la etiqueta, esto no se publica: la firma de una
    #  persona vale para juzgar lo dudoso, no para saltarse lo inequívoco.
    bloquean = [r for r in (res.get("reglas") or []) if r.get("bloquea")]
    if bloquean:
        print("no se publica, hay %d cosa(s) que bloquean: %s"
              % (len(bloquean), ", ".join(r["id"] for r in bloquean)),
              file=sys.stderr)
        return 1

    p = res["plugin"]
    ident = str(p.get("id", ""))
    datos = json.loads(REGISTRO.read_text())
    entradas = datos.setdefault("plugins", [])
    nueva = {
        "id": ident,
        "title": p.get("title", ident),
        "description": p.get("description", ""),
        "repo": d["repo"],
        "commit": d["commit"],
    }
    if d["carpeta"]:
        nueva["carpeta"] = d["carpeta"]

    for i, e in enumerate(entradas):
        if str(e.get("id")) == ident:
            #  Se conserva lo que el registro sabe y el envío no trae, como el
            #  autor: actualizar una versión no debería borrar eso.
            nueva = {**e, **nueva}
            entradas[i] = nueva
            break
    else:
        entradas.append(nueva)

    REGISTRO.write_text(json.dumps(datos, ensure_ascii=False, indent=1) + "\n")
    print("publicado: %s en %s" % (ident, d["commit"][:12]))
    return 0


def main():
    args = sys.argv[1:]
    if not args or args[0] in ("-h", "--help", "--ayuda"):
        print(__doc__)
        return 0
    orden = args[0]
    if len(args) < 2:
        print("falta el fichero con el cuerpo de la incidencia",
              file=sys.stderr)
        return 2
    cuerpo = io.open(args[1], encoding="utf-8").read()
    d, malos = envio(cuerpo)
    res = examinar(d) if not malos else {"ok": False, "motivo": "formulario"}

    if orden == "--revisar":
        texto, etiqueta = informe(d, malos, res)
        print(texto)
        #  La etiqueta va por el fichero que GitHub deja para las salidas, no
        #  por la salida estándar: eso es el informe y se comenta tal cual.
        salidas = os.environ.get("GITHUB_OUTPUT")
        if salidas:
            with io.open(salidas, "a", encoding="utf-8") as f:
                f.write("etiqueta=%s\n" % etiqueta)
                f.write("commit=%s\n" % d["commit"])
                f.write("id=%s\n" % (res.get("plugin", {}).get("id", "")
                                     if res.get("ok") else ""))
        return 0
    if orden == "--anadir":
        if malos:
            print("el formulario no está bien: no se publica", file=sys.stderr)
            return 1
        return anadir(d, res)
    print("no sé qué es %r" % orden, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
