#!/usr/bin/env python3
"""Rastro del cursor durante una grabación, para el zoom automático.

    rastro.py --salida /tmp/k4-captura/rastro-X.jsonl [--hz 30] [--region "X,Y WxH"]

Escribe JSONL: una línea de cabecera y luego una por muestra. Los clics NO se
sondean —Hyprland no los publica—: llegan por la entrada estándar, una línea
«clic <boton>» por cada uno, que es quien los recibe con un atajo global.

La posición se pide por el socket de Hyprland y no con `hyprctl cursorpos`:
medido, la consulta cuesta 0,019 ms, mientras que lanzar un proceso treinta
veces por segundo se nota. A 30 Hz esto es un 0,06 % de un hilo.
"""
import argparse, json, os, select, signal, socket, sys, time

# ── el socket de peticiones de Hyprland ───────────────────────────
FIRMA = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", "")
RUNTIME = os.environ.get("XDG_RUNTIME_DIR", "/run/user/%d" % os.getuid())
SOCKET = "%s/hypr/%s/.socket.sock" % (RUNTIME, FIRMA)

parar = False


def al_cortar(*_):
    global parar
    parar = True


def preguntar(orden):
    """Una consulta al compositor. Devuelve texto, o None si no contesta."""
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(0.2)
        s.connect(SOCKET)
        s.sendall(orden.encode())
        trozos = []
        while True:
            d = s.recv(4096)
            if not d:
                break
            trozos.append(d)
        s.close()
        return b"".join(trozos).decode()
    except (OSError, socket.timeout):
        return None


def posicion():
    """El cursor, en coordenadas globales. `cursorpos` devuelve «582, 859»."""
    t = preguntar("cursorpos")
    if not t:
        return None
    try:
        x, y = t.split(",")
        return int(x.strip()), int(y.strip())
    except ValueError:
        return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--salida", required=True)
    ap.add_argument("--hz", type=float, default=30.0)
    ap.add_argument("--region", default="")     # "X,Y WxH"
    args = ap.parse_args()

    signal.signal(signal.SIGINT, al_cortar)
    signal.signal(signal.SIGTERM, al_cortar)

    if not os.path.exists(SOCKET):
        print(json.dumps({"ok": False, "motivo": "sin-socket"}), flush=True)
        return 1

    os.makedirs(os.path.dirname(args.salida), exist_ok=True)
    intervalo = 1.0 / args.hz
    t0 = time.monotonic()

    with open(args.salida, "w") as f:
        f.write(json.dumps({"meta": {
            "hz": args.hz,
            "region": args.region,
            "epoch": time.time(),
        }}) + "\n")
        f.flush()

        # El latido por stdout le sirve a quien nos lanzó para saber que
        # seguimos vivos sin tener que leer el fichero.
        print(json.dumps({"ok": True, "estado": "rastreando"}), flush=True)

        muestras = 0
        while not parar:
            ciclo = time.monotonic()

            p = posicion()
            if p is not None:
                f.write(json.dumps({"t": round(ciclo - t0, 4),
                                    "x": p[0], "y": p[1]}) + "\n")
                muestras += 1

            # Los clics que hayan llegado mientras tanto. Se leen sin bloquear
            # porque el reloj de las muestras manda: un clic se apunta cuando
            # llega, no cuando nos apetece mirar.
            while select.select([sys.stdin], [], [], 0)[0]:
                linea = sys.stdin.readline()
                if not linea:
                    break
                partes = linea.split()
                if partes and partes[0] == "clic":
                    boton = int(partes[1]) if len(partes) > 1 else 1
                    f.write(json.dumps({"t": round(time.monotonic() - t0, 4),
                                        "tipo": "clic", "boton": boton}) + "\n")

            # Cada segundo por si se corta la luz: perder el rastro entero por
            # no haber vaciado el buffer sería tonto.
            if muestras % int(args.hz) == 0:
                f.flush()

            resto = intervalo - (time.monotonic() - ciclo)
            if resto > 0:
                time.sleep(resto)

        f.flush()

    print(json.dumps({"ok": True, "estado": "fin", "muestras": muestras}),
          flush=True)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (KeyboardInterrupt, BrokenPipeError):
        # Que se muera quien nos lee no es un fallo nuestro.
        sys.exit(0)
