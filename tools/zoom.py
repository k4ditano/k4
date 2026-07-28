#!/usr/bin/env python3
"""Zoom automático estilo Screen Studio, en posproceso.

    zoom.py proponer <rastro.jsonl> --video <v.mp4>   -> plan JSON por stdout
    zoom.py render   <v.mp4> <plan.json> <salida.mp4>
    zoom.py previa   <v.mp4> <plan.json> <t> <salida.png>

Por qué en posproceso y no grabando ya recortado: la región de wf-recorder se
fija al arrancar y no se puede mover. Además, decidir el zoom cuando ya sabes lo
que pasó después sale mucho mejor que decidirlo en directo.

Se usa `zoompan` y no `crop`: en ffmpeg n8.1.2 `crop` ya no tiene la opción
`eval`, así que sus `w`/`h` se evalúan una sola vez y no se pueden animar.

Los motivos y las claves son en español pero NO son texto para el usuario: el
QML los traduce con Idioma.t().
"""
import argparse, json, math, os, subprocess, sys

# ── el tacto de la cámara ─────────────────────────────────────────
#
#  Estos números son el 90 % de que quede bien o parezca mareante. La entrada es
#  rápida y la salida lenta a propósito: entrar deprisa se lee como intención
#  —«mira esto»— y salir despacio evita el tirón.
ENTRADA = 0.55          # s en llegar al zoom
SALIDA = 0.90           # s en volver
MINIMO = 1.5            # s que dura un momento como poco
JUNTAR = 1.5            # s de hueco por debajo del cual dos momentos se funden
AGRUPAR = 2.5           # s dentro de los que dos sucesos son el mismo momento
TOPE_CUBIERTO = 0.60    # fracción del clip que como mucho lleva zoom
ZONA_MUERTA = 0.25      # del encuadre visible: dentro de esto la cámara no se mueve
PANEO_MAX = 420.0       # px/s en coordenadas de origen
Z_MIN, Z_MAX = 1.4, 2.5

# ── detección de reposos, por si no hay clics ─────────────────────
V_LENTA = 60.0          # px/s: por debajo, el cursor está «parado»
V_RAPIDA = 400.0        # px/s: por encima, venía «lanzado»
QUIETO = 0.4            # s que hay que estar parado


def salir(**d):
    print(json.dumps(d, ensure_ascii=False), flush=True)
    sys.exit(0 if d.get("ok", True) else 1)


# ── leer el rastro ────────────────────────────────────────────────
def leer_rastro(ruta):
    meta, muestras, clics = {}, [], []
    with open(ruta) as f:
        for linea in f:
            linea = linea.strip()
            if not linea:
                continue
            try:
                d = json.loads(linea)
            except json.JSONDecodeError:
                continue
            if "meta" in d:
                meta = d["meta"]
            elif d.get("tipo") == "clic":
                clics.append(d["t"])
            elif "x" in d:
                muestras.append((d["t"], float(d["x"]), float(d["y"])))
    muestras.sort(key=lambda m: m[0])
    return meta, muestras, clics


def suavizar(muestras, ventana=5):
    """Mediana móvil: mata el temblor de la mano sin arrastrar los saltos."""
    if len(muestras) < ventana:
        return muestras
    salida = []
    mitad = ventana // 2
    for i in range(len(muestras)):
        a = max(0, i - mitad)
        b = min(len(muestras), i + mitad + 1)
        xs = sorted(m[1] for m in muestras[a:b])
        ys = sorted(m[2] for m in muestras[a:b])
        salida.append((muestras[i][0], xs[len(xs) // 2], ys[len(ys) // 2]))
    return salida


def velocidades(muestras):
    v = [0.0] * len(muestras)
    for i in range(1, len(muestras)):
        dt = muestras[i][0] - muestras[i - 1][0]
        if dt <= 0:
            continue
        dx = muestras[i][1] - muestras[i - 1][1]
        dy = muestras[i][2] - muestras[i - 1][2]
        v[i] = math.hypot(dx, dy) / dt
    return v


def reposos(muestras, v):
    """Instantes en que el cursor llega a algo y se para.

    Es el sustituto de los clics cuando no los hay, y funciona sorprendentemente
    bien porque el gesto que importa —ir rápido a un sitio y quedarse— es el
    mismo se pulse o no.
    """
    salida = []
    i = 1
    while i < len(muestras):
        if v[i] > V_RAPIDA:
            # venía lanzado: ¿se para justo después?
            j = i
            while j < len(muestras) and v[j] > V_LENTA:
                j += 1
            if j >= len(muestras):
                break
            inicio = muestras[j][0]
            k = j
            while k < len(muestras) and v[k] <= V_LENTA:
                k += 1
            if muestras[min(k, len(muestras) - 1)][0] - inicio >= QUIETO:
                salida.append(inicio)
                i = k
                continue
            i = j
        i += 1
    return salida


# ── proponer momentos ─────────────────────────────────────────────
def posicion_en(muestras, t):
    if not muestras:
        return None
    mejor = min(muestras, key=lambda m: abs(m[0] - t))
    return mejor[1], mejor[2]


def proponer(rastro, ancho, alto, duracion, nivel_max=Z_MAX):
    meta, muestras, clics = leer_rastro(rastro)
    muestras = suavizar(muestras)
    if not muestras:
        return []

    v = velocidades(muestras)
    sucesos = sorted(set([round(c, 2) for c in clics]
                         + [round(r, 2) for r in reposos(muestras, v)]))
    if not sucesos:
        return []

    # agrupar los que caen cerca
    grupos, actual = [], [sucesos[0]]
    for s in sucesos[1:]:
        if s - actual[-1] <= AGRUPAR:
            actual.append(s)
        else:
            grupos.append(actual)
            actual = [s]
    grupos.append(actual)

    momentos = []
    for g in grupos:
        t0 = max(0.0, g[0] - 0.35)
        t1 = min(duracion, g[-1] + 1.2)
        if t1 - t0 < MINIMO:
            t1 = min(duracion, t0 + MINIMO)
        if t1 - t0 < MINIMO:
            continue

        dentro = [m for m in muestras if t0 <= m[0] <= t1]
        if not dentro:
            continue

        # El rango entre cuartiles y no el total: dentro de la ventana está
        # también el viaje hasta el sitio, y contarlo hinchaba la dispersión
        # hasta dejar el zoom siempre en el mínimo.
        momentos.append({"t0": round(t0, 3), "t1": round(t1, 3),
                         "caja": caja(dentro)})

    # ── fundir los que se pisan ───────────────────────────────────
    #
    #  Solo hasta JUNTAR. Salir del zoom y volver a entrar en menos de segundo y
    #  medio se ve frenético; más allá de eso son dos gestos distintos y merecen
    #  dos momentos. Probé a fundir hasta cuatro segundos y en un clip de 14 s
    #  los tres gestos acababan en un solo bloque de casi diez, que además se
    #  pasaba del tope de metraje y se descartaba entero: cero momentos.
    fundidos = []
    for m in momentos:
        if fundidos and m["t0"] - fundidos[-1]["t1"] < JUNTAR:
            a = fundidos[-1]
            a["t1"] = m["t1"]
            a["caja"] = unir(a["caja"], m["caja"])
        else:
            fundidos.append(m)

    salida, cubierto = [], 0.0
    for m in fundidos:
        # Tope de metraje: un vídeo entero con zoom marea. Pero al menos uno
        # siempre, o un clip corto con un gesto largo se quedaría sin nada.
        if salida and cubierto + (m["t1"] - m["t0"]) > TOPE_CUBIERTO * duracion:
            continue
        cubierto += m["t1"] - m["t0"]
        x0, y0, x1, y1 = m.pop("caja")
        m["cx"] = round((x0 + x1) / 2)
        m["cy"] = round((y0 + y1) / 2)
        # Que quepa lo que has estado mirando, con un margen. Cuanto más
        # ancho el gesto, menos se aprieta.
        holgura = 1.6
        anchoUtil = max(40.0, (x1 - x0) * holgura)
        altoUtil = max(40.0, (y1 - y0) * holgura)
        z = min(ancho / anchoUtil, alto / altoUtil)
        m["z"] = round(max(Z_MIN, min(nivel_max, z)), 3)
        m["id"] = len(salida) + 1
        salida.append(m)

    return salida


def caja(muestras):
    """Dónde estuvo el cursor, entre cuartiles, para ignorar el viaje de ida."""
    xs = sorted(m[1] for m in muestras)
    ys = sorted(m[2] for m in muestras)
    n = len(xs)
    a, b = n // 4, max(n // 4, (3 * n) // 4 - 1)
    return xs[a], ys[a], xs[b], ys[b]


def unir(c1, c2):
    return (min(c1[0], c2[0]), min(c1[1], c2[1]),
            max(c1[2], c2[2]), max(c1[3], c2[3]))


# ── la trayectoria de la cámara ───────────────────────────────────
def encaja(v, minimo, maximo):
    return max(minimo, min(maximo, v))


def suave_entrada(u):
    return 1 - (1 - u) ** 3                 # easeOutCubic


def suave_salida(u):
    return 0.5 - 0.5 * math.cos(math.pi * u)  # easeInOutSine


def trayectoria(momentos, rastro, ancho, alto, duracion, fps=30.0):
    """z(t), x(t), y(t) muestreadas, ya con zona muerta y límite de paneo."""
    _, muestras, _ = leer_rastro(rastro)
    muestras = suavizar(muestras)

    pasos = int(duracion * fps) + 1
    cx, cy = ancho / 2.0, alto / 2.0
    puntos = []

    anterior = None
    origen = (cx, cy)

    for i in range(pasos):
        t = i / fps

        activo = None
        for m in momentos:
            if m["t0"] <= t <= m["t1"]:
                activo = m
                break

        # Al empezar un momento se recuerda de dónde venía la cámara: el viaje
        # hasta el sitio se hace con la misma curva que el zoom, no arrastrando.
        if activo is not None and activo is not anterior:
            origen = (cx, cy)
        anterior = activo

        if activo is None:
            z = 1.0
            visible_w, visible_h = ancho, alto
            cx, cy = ancho / 2.0, alto / 2.0
        else:
            u_ent = (t - activo["t0"]) / ENTRADA
            u_sal = (activo["t1"] - t) / SALIDA
            f = 1.0
            if u_ent < 1:
                f = suave_entrada(encaja(u_ent, 0, 1))
            if u_sal < 1:
                f = min(f, suave_salida(encaja(u_sal, 0, 1)))
            z = 1.0 + (activo["z"] - 1.0) * f
            visible_w, visible_h = ancho / z, alto / z

            if u_ent < 1:
                #  Entrando: la cámara VA al sitio con la misma curva que el
                #  zoom. Con el límite de paneo aquí no llegaba nunca —cruzar
                #  la pantalla a 420 px/s lleva dos segundos y un momento dura
                #  uno y medio—, así que el zoom acababa apuntando a medio
                #  camino de donde había que mirar.
                g = suave_entrada(encaja(u_ent, 0, 1))
                cx = origen[0] + (activo["cx"] - origen[0]) * g
                cy = origen[1] + (activo["cy"] - origen[1]) * g
            else:
                #  Ya dentro: se sigue al cursor, y AQUÍ sí manda el límite de
                #  paneo junto con la zona muerta. Es lo que separa un
                #  seguimiento tranquilo de un temblor perpetuo.
                p = posicion_en(muestras, t)
                objetivo = p if p else (activo["cx"], activo["cy"])
                if (abs(objetivo[0] - cx) > visible_w * ZONA_MUERTA / 2
                        or abs(objetivo[1] - cy) > visible_h * ZONA_MUERTA / 2):
                    paso = PANEO_MAX / fps
                    dx, dy = objetivo[0] - cx, objetivo[1] - cy
                    d = math.hypot(dx, dy)
                    if d > paso:
                        dx, dy = dx * paso / d, dy * paso / d
                    cx += dx
                    cy += dy

        # ── que el recorte no se salga del fotograma
        cxr = encaja(cx, visible_w / 2, ancho - visible_w / 2)
        cyr = encaja(cy, visible_h / 2, alto - visible_h / 2)


        puntos.append((t, z, cxr - visible_w / 2, cyr - visible_h / 2))

    return puntos


def adelgazar(puntos, tol_z=0.002, tol_p=0.6):
    """Quita los puntos que una recta ya predice: menos nodos, misma curva."""
    if len(puntos) < 3:
        return puntos
    salida = [puntos[0]]
    ancla = 0
    for i in range(1, len(puntos) - 1):
        t0, z0, x0, y0 = puntos[ancla]
        t2, z2, x2, y2 = puntos[i + 1]
        t1, z1, x1, y1 = puntos[i]
        if t2 == t0:
            continue
        u = (t1 - t0) / (t2 - t0)
        if (abs(z0 + (z2 - z0) * u - z1) > tol_z
                or abs(x0 + (x2 - x0) * u - x1) > tol_p
                or abs(y0 + (y2 - y0) * u - y1) > tol_p):
            salida.append(puntos[i])
            ancla = i
    salida.append(puntos[-1])
    return salida


def expresion(puntos, indice):
    """Función lineal a trozos como expresión de ffmpeg.

    Anidada en busca binaria y no como una ristra de `between`: el evaluador
    recorre la expresión en CADA fotograma, así que con doscientos tramos la
    diferencia entre profundidad 8 y profundidad 200 se nota.
    """
    def tramo(i):
        t0, t1 = puntos[i][0], puntos[i + 1][0]
        v0, v1 = puntos[i][indice], puntos[i + 1][indice]
        if abs(t1 - t0) < 1e-9 or abs(v1 - v0) < 1e-9:
            return "%.4f" % v0
        m = (v1 - v0) / (t1 - t0)
        return "(%.4f+%.5f*(time-%.4f))" % (v0, m, t0)

    def construir(lo, hi):
        if hi - lo <= 1:
            return tramo(lo)
        mitad = (lo + hi) // 2
        return "if(lt(time,%.4f),%s,%s)" % (
            puntos[mitad][0], construir(lo, mitad), construir(mitad, hi))

    if len(puntos) < 2:
        return "%.4f" % (puntos[0][indice] if puntos else 1.0)
    return construir(0, len(puntos) - 1)


def filtro(momentos, rastro, ancho, alto, duracion, fps):
    puntos = adelgazar(trayectoria(momentos, rastro, ancho, alto, duracion, fps))
    return ("zoompan=z='%s':x='%s':y='%s':d=1:s=%dx%d:fps=%g,format=yuv420p"
            % (expresion(puntos, 1), expresion(puntos, 2), expresion(puntos, 3),
               ancho, alto, fps)), len(puntos)


# ── datos del vídeo ───────────────────────────────────────────────
def sondear(video):
    p = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0",
         "-show_entries", "stream=width,height,r_frame_rate",
         "-show_entries", "format=duration", "-of", "json", video],
        capture_output=True, text=True)
    d = json.loads(p.stdout)
    s = d["streams"][0]
    num, den = s["r_frame_rate"].split("/")
    hay_audio = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "a:0",
         "-show_entries", "stream=codec_name", "-of", "csv=p=0", video],
        capture_output=True, text=True).stdout.strip() != ""
    return (int(s["width"]), int(s["height"]),
            float(num) / float(den), float(d["format"]["duration"]), hay_audio)


# ── órdenes ───────────────────────────────────────────────────────
def orden_proponer(args):
    if not os.path.exists(args.rastro):
        salir(ok=False, motivo="sin-rastro")
    ancho, alto, fps, duracion, _ = sondear(args.video)
    momentos = proponer(args.rastro, ancho, alto, duracion, args.nivel)
    plan = {"video": args.video, "rastro": args.rastro,
            "w": ancho, "h": alto, "fps": fps, "duracion": round(duracion, 3),
            "momentos": momentos}
    if args.guardar:
        with open(args.guardar, "w") as f:
            json.dump(plan, f, ensure_ascii=False, indent=1)
    salir(ok=True, **plan)


def orden_camara(args):
    """La trayectoria de la cámara, para previsualizarla sin renderizar.

    Sale la MISMA lista de puntos que se convierte en la expresión de ffmpeg, y
    entre ellos se interpola en línea recta igual que hace el filtro. Por eso lo
    que se ve en el editor y lo que acaba en el fichero coinciden por
    construcción, sin dos implementaciones que se puedan ir separando.
    """
    plan = json.load(open(args.plan))
    ancho, alto, fps, duracion, _ = sondear(plan["video"])
    puntos = adelgazar(trayectoria(plan["momentos"], plan["rastro"],
                                   ancho, alto, duracion, fps))
    salir(ok=True, w=ancho, h=alto, duracion=round(duracion, 3),
          camara=[[round(t, 3), round(z, 4), round(x, 1), round(y, 1)]
                  for t, z, x, y in puntos])


def orden_render(args):
    plan = json.load(open(args.plan))
    ancho, alto, fps, duracion, hay_audio = sondear(args.video)
    cadena, nodos = filtro(plan["momentos"], plan["rastro"],
                           ancho, alto, duracion, fps)

    orden = ["ffmpeg", "-v", "error", "-y", "-i", args.video,
             "-vf", cadena,
             "-c:v", "hevc_nvenc" if args.codec == "hevc" else "h264_nvenc",
             "-preset", "p5", "-rc", "vbr", "-cq", "21", "-b:v", "0"]
    if hay_audio:
        orden += ["-c:a", "copy"]
    orden += ["-progress", "pipe:1", "-nostats", args.salida]

    print(json.dumps({"ok": True, "estado": "renderizando", "nodos": nodos}),
          flush=True)

    p = subprocess.Popen(orden, stdout=subprocess.PIPE, text=True)
    for linea in p.stdout:
        if linea.startswith("out_time_ms="):
            try:
                us = int(linea.split("=")[1])
            except ValueError:
                continue
            if duracion > 0:
                print(json.dumps({"progreso": round(
                    min(1.0, us / 1e6 / duracion), 3)}), flush=True)
    p.wait()
    if p.returncode != 0 or not os.path.exists(args.salida):
        salir(ok=False, motivo="fallo")
    salir(ok=True, estado="fin", ruta=args.salida)


def orden_previa(args):
    plan = json.load(open(args.plan))
    ancho, alto, fps, duracion, _ = sondear(args.video)
    cadena, _ = filtro(plan["momentos"], plan["rastro"],
                       ancho, alto, duracion, fps)
    # `-ss` DESPUÉS de `-i`: buscando por la entrada, ffmpeg pone los tiempos a
    # cero y las expresiones, que van en tiempo absoluto, apuntarían al sitio
    # equivocado.
    p = subprocess.run(
        ["ffmpeg", "-v", "error", "-y", "-i", args.video, "-ss", str(args.t),
         "-vf", cadena, "-frames:v", "1", args.salida],
        capture_output=True, text=True)
    if p.returncode != 0:
        salir(ok=False, motivo="fallo", detalle=p.stderr.strip()[:200])
    salir(ok=True, ruta=args.salida)


def main():
    ap = argparse.ArgumentParser(add_help=False)
    sub = ap.add_subparsers(dest="orden", required=True)

    a = sub.add_parser("proponer")
    a.add_argument("rastro")
    a.add_argument("--video", required=True)
    a.add_argument("--guardar", default="")
    a.add_argument("--nivel", type=float, default=Z_MAX)

    b = sub.add_parser("render")
    b.add_argument("video")
    b.add_argument("plan")
    b.add_argument("salida")
    b.add_argument("--codec", default="h264")

    d = sub.add_parser("camara")
    d.add_argument("plan")

    c = sub.add_parser("previa")
    c.add_argument("video")
    c.add_argument("plan")
    c.add_argument("t", type=float)
    c.add_argument("salida")

    args = ap.parse_args()
    {"proponer": orden_proponer, "render": orden_render,
     "previa": orden_previa, "camara": orden_camara}[args.orden](args)


if __name__ == "__main__":
    try:
        main()
    except (KeyboardInterrupt, BrokenPipeError):
        sys.exit(0)
