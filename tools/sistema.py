#!/usr/bin/env python3
"""Muestreador del estado del equipo.

Publica una línea JSON cada pocos segundos con lo que está pasando: CPU, RAM,
GPU, red, disco y los procesos que más comen. El módulo de la island solo pinta
lo que llega; leer /proc desde QML sería posible pero acabaría en veinte
FileView releyendo ficheros y calculando deltas a mano.

Casi todo se mide por diferencia entre dos muestras —el uso de CPU y el tráfico
de red no son valores, son ritmos—, así que la primera vuelta no publica nada:
no hay con qué comparar.
"""

import json
import os
import subprocess
import sys
import time

INTERVALO = 2.0
HILOS = os.cpu_count() or 1
RELOJ = os.sysconf("SC_CLK_TCK")


# ── CPU ──────────────────────────────────────────────────────────────

def lee_cpu():
    with open("/proc/stat") as f:
        campos = f.readline().split()[1:]
    nums = [int(x) for x in campos]
    ocioso = nums[3] + nums[4]          # idle + iowait
    return sum(nums), ocioso


def uso_cpu(antes, ahora):
    dt = ahora[0] - antes[0]
    di = ahora[1] - antes[1]
    if dt <= 0:
        return 0.0
    return max(0.0, min(100.0, (1 - di / dt) * 100))


# ── temperaturas ─────────────────────────────────────────────────────
#
#  Se busca por nombre de chip: k10temp es el Ryzen, coretemp el Intel. La
#  placa (gigabyte_wmi, nct6…) publica media docena de sondas sin etiquetar
#  que no dicen nada, así que se ignoran.

CHIPS_CPU = ("k10temp", "coretemp", "zenpower", "cpu_thermal")
ETIQUETAS_CPU = ("Tctl", "Tdie", "Package id 0")


def temperaturas():
    cpu = None
    nvme = None

    for base in sorted(os.listdir("/sys/class/hwmon")):
        ruta = os.path.join("/sys/class/hwmon", base)
        try:
            with open(os.path.join(ruta, "name")) as f:
                chip = f.read().strip()
        except OSError:
            continue

        for fichero in sorted(os.listdir(ruta)):
            if not fichero.endswith("_input") or not fichero.startswith("temp"):
                continue
            try:
                with open(os.path.join(ruta, fichero)) as f:
                    valor = int(f.read().strip()) / 1000.0
            except (OSError, ValueError):
                continue

            etiqueta = ""
            try:
                with open(os.path.join(ruta, fichero.replace("_input", "_label"))) as f:
                    etiqueta = f.read().strip()
            except OSError:
                pass

            if chip in CHIPS_CPU and (cpu is None or etiqueta in ETIQUETAS_CPU):
                cpu = valor
            elif chip == "nvme" and nvme is None:
                nvme = valor

    return cpu, nvme


# ── memoria ──────────────────────────────────────────────────────────

def memoria():
    datos = {}
    with open("/proc/meminfo") as f:
        for linea in f:
            partes = linea.split()
            if len(partes) >= 2:
                datos[partes[0].rstrip(":")] = int(partes[1])

    total = datos.get("MemTotal", 0) / 1048576.0          # GiB
    disponible = datos.get("MemAvailable", 0) / 1048576.0
    usada = max(0.0, total - disponible)

    swapTotal = datos.get("SwapTotal", 0) / 1048576.0
    swapUsada = max(0.0, swapTotal - datos.get("SwapFree", 0) / 1048576.0)

    return {
        "usada": round(usada, 2),
        "total": round(total, 2),
        "pct": round(usada / total * 100, 1) if total else 0,
        "swapUsada": round(swapUsada, 2),
        "swapTotal": round(swapTotal, 2),
    }


# ── red ──────────────────────────────────────────────────────────────

def lee_red():
    total = {}
    with open("/proc/net/dev") as f:
        f.readline(); f.readline()
        for linea in f:
            nombre, resto = linea.split(":", 1)
            nombre = nombre.strip()
            if nombre == "lo":
                continue
            campos = resto.split()
            total[nombre] = (int(campos[0]), int(campos[8]))
    return total


def trafico(antes, ahora, dt):
    """La interfaz que más se mueve, que es la que de verdad estás usando."""
    mejor = None
    for nombre, (rx, tx) in ahora.items():
        if nombre not in antes:
            continue
        drx = max(0, rx - antes[nombre][0]) / dt
        dtx = max(0, tx - antes[nombre][1]) / dt
        if mejor is None or drx + dtx > mejor["rx"] + mejor["tx"]:
            mejor = {"iface": nombre, "rx": drx, "tx": dtx}

    if mejor is None:
        return {"iface": "", "rx": 0, "tx": 0}
    mejor["rx"] = round(mejor["rx"])
    mejor["tx"] = round(mejor["tx"])
    return mejor


# ── disco ────────────────────────────────────────────────────────────

def disco():
    try:
        st = os.statvfs(os.path.expanduser("~"))
    except OSError:
        return None
    total = st.f_blocks * st.f_frsize / 1073741824.0
    libre = st.f_bavail * st.f_frsize / 1073741824.0
    usado = total - libre
    return {
        "usado": round(usado, 1),
        "total": round(total, 1),
        "pct": round(usado / total * 100, 1) if total else 0,
    }


# ── GPU ──────────────────────────────────────────────────────────────
#
#  nvidia-smi tarda lo suyo en arrancar, así que se pregunta una vuelta sí y
#  otra no: a dos segundos por muestra sigue siendo información fresca y se
#  ahorra la mitad de los procesos.

CONSULTA_GPU = ["nvidia-smi",
                "--query-gpu=name,utilization.gpu,temperature.gpu,memory.used,memory.total",
                "--format=csv,noheader,nounits"]


def gpu():
    try:
        r = subprocess.run(CONSULTA_GPU, capture_output=True, text=True, timeout=4)
    except Exception:
        return None
    linea = r.stdout.strip().split("\n")[0] if r.stdout.strip() else ""
    if not linea:
        return None

    partes = [p.strip() for p in linea.split(",")]
    if len(partes) < 5:
        return None
    try:
        return {
            "nombre": partes[0].replace("NVIDIA ", ""),
            "uso": float(partes[1]),
            "temp": float(partes[2]),
            "memUsada": float(partes[3]),
            "memTotal": float(partes[4]),
        }
    except ValueError:
        return None


# ── procesos ─────────────────────────────────────────────────────────
#
#  El porcentaje de CPU de un proceso también es un ritmo: `ps` da la media
#  desde que arrancó, que para un navegador abierto desde ayer no dice nada.
#  Aquí se guarda el tiempo de cada uno y se compara con la muestra anterior.

def lee_procesos():
    salida = {}
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        try:
            with open(f"/proc/{pid}/stat") as f:
                bruto = f.read()
            # el nombre va entre paréntesis y puede llevar espacios dentro
            cierre = bruto.rfind(")")
            nombre = bruto[bruto.find("(") + 1:cierre]
            campos = bruto[cierre + 2:].split()
            tiempo = int(campos[11]) + int(campos[12])      # utime + stime
            rss = int(campos[21]) * 4096 / 1048576.0        # páginas -> MiB
        except (OSError, ValueError, IndexError):
            continue
        salida[pid] = (nombre, tiempo, rss)
    return salida


def top(antes, ahora, dt, cuantos=6):
    lista = []
    for pid, (nombre, tiempo, rss) in ahora.items():
        if pid not in antes:
            continue
        dcpu = (tiempo - antes[pid][1]) / RELOJ / dt * 100
        if dcpu <= 0.1 and rss < 50:
            continue
        lista.append({"pid": int(pid), "nombre": nombre,
                      "cpu": round(min(dcpu, 100 * HILOS), 1), "ram": round(rss)})

    lista.sort(key=lambda p: (-p["cpu"], -p["ram"]))
    return lista[:cuantos]


# ── bucle ────────────────────────────────────────────────────────────

def main():
    antesCpu = lee_cpu()
    antesRed = lee_red()
    antesProc = lee_procesos()
    ultimoGpu = None
    vuelta = 0

    while True:
        time.sleep(INTERVALO)
        vuelta += 1

        ahoraCpu = lee_cpu()
        ahoraRed = lee_red()
        ahoraProc = lee_procesos()

        tempCpu, tempNvme = temperaturas()

        if vuelta % 2 == 1 or ultimoGpu is None:
            ultimoGpu = gpu()

        muestra = {
            "cpu": {"uso": round(uso_cpu(antesCpu, ahoraCpu), 1),
                    "temp": tempCpu, "hilos": HILOS},
            "ram": memoria(),
            "red": trafico(antesRed, ahoraRed, INTERVALO),
            "disco": disco(),
            "tempNvme": tempNvme,
            "procesos": top(antesProc, ahoraProc, INTERVALO),
        }
        if ultimoGpu:
            muestra["gpu"] = ultimoGpu

        print(json.dumps(muestra), flush=True)

        antesCpu, antesRed, antesProc = ahoraCpu, ahoraRed, ahoraProc


if __name__ == "__main__":
    try:
        main()
    except (KeyboardInterrupt, BrokenPipeError):
        # que se cierre quien lee no es un fallo: es el final
        sys.exit(0)
