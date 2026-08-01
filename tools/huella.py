#!/usr/bin/env python3
"""Los lectores de la huella: datos personales AGREGADOS, nunca crudos.

    huella.py steam       juegos instalados y minutos jugados (agregado)
    huella.py paquetes    inventario de pacman: cuántos, cuándo se actualizó

Cada lector emite UN objeto JSON por stdout y nada más. La agregación pasa
aquí, en python, antes de tocar QML: lo crudo no llega ni al proceso de la
barra. Y todo es opcional por diseño: si una fuente no existe en esta
máquina (sin Steam, sin pacman), contesta un objeto vacío con `ok: false`
en vez de romper.
"""
import glob
import json
import os
import re
import sys


def salir(**d):
    print(json.dumps(d, ensure_ascii=False), flush=True)
    return 0


# ── steam ────────────────────────────────────────────────────────────

def steam():
    """Biblioteca y minutos, de los .acf y localconfig.vdf de Steam."""
    raiz = None
    for c in ("~/.steam/steam", "~/.local/share/Steam"):
        c = os.path.expanduser(c)
        if os.path.isdir(os.path.join(c, "steamapps")):
            raiz = c
            break
    if not raiz:
        return salir(ok=False, motivo="sin Steam")

    juegos = []
    for acf in glob.glob(os.path.join(raiz, "steamapps", "*.acf")):
        try:
            texto = open(acf, encoding="utf-8", errors="replace").read()
        except OSError:
            continue
        nombre = re.search(r'"name"\s+"([^"]+)"', texto)
        if nombre:
            juegos.append(nombre.group(1))

    #  Minutos por juego: el localconfig del primer usuario que haya.
    minutos = 0
    for lc in glob.glob(os.path.join(raiz, "userdata", "*",
                                     "config", "localconfig.vdf")):
        try:
            texto = open(lc, encoding="utf-8", errors="replace").read()
        except OSError:
            continue
        minutos += sum(int(m) for m in
                       re.findall(r'"Playtime"\s+"(\d+)"', texto))

    return salir(ok=True, juegos=len(juegos), minutos=minutos,
                 titulos=sorted(juegos)[:200])


# ── paquetes ─────────────────────────────────────────────────────────

def paquetes():
    """El inventario de pacman: cuántos hay y cuándo fue la última síncro."""
    registro = "/var/log/pacman.log"
    if not os.path.isfile(registro):
        return salir(ok=False, motivo="sin pacman")

    total = 0
    try:
        import subprocess
        r = subprocess.run(["pacman", "-Qq"], capture_output=True,
                           text=True, timeout=10)
        total = len(r.stdout.strip().split("\n")) if r.returncode == 0 else 0
    except Exception:
        pass

    ultima = ""
    try:
        with open(registro, "rb") as f:
            f.seek(max(0, os.path.getsize(registro) - 65536))
            cola = f.read().decode("utf-8", errors="replace")
        fechas = re.findall(r"\[([0-9T:+\-]+)\] \[PACMAN\] starting full system upgrade",
                            cola)
        if fechas:
            ultima = fechas[-1][:10]
    except OSError:
        pass

    return salir(ok=True, total=total, ultimaActualizacion=ultima)


ORDENES = {"steam": steam, "paquetes": paquetes}

if __name__ == "__main__":
    orden = sys.argv[1] if len(sys.argv) > 1 else ""
    if orden not in ORDENES:
        print(__doc__.strip(), file=sys.stderr)
        sys.exit(2)
    sys.exit(ORDENES[orden]())
