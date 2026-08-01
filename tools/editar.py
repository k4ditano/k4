#!/usr/bin/env python3
"""El motor del editor de vídeo de k4.

    editar.py abrir    <v.mp4> [--guardar plan.json]   -> plan JSON por stdout
    editar.py proponer <rastro.jsonl> --video <v.mp4>  -> plan JSON con zoom
    editar.py camara   <plan.json>
    editar.py render   <v.mp4> <plan.json> <salida.mp4>
    editar.py previa   <v.mp4> <plan.json> <t> <salida.png>

Se llamaba zoom.py, y el nombre se le quedó pequeño: esto ya no va del zoom sino
de una composición —trozos de vídeo, capas encima, audio— de la que el zoom es
una parte más.

Todo en posproceso y no grabando ya recortado: la región de wf-recorder se fija
al arrancar y no se puede mover. Además, decidir el zoom cuando ya sabes lo que
pasó después sale mucho mejor que decidirlo en directo.

Se usa `zoompan` y no `crop`: en ffmpeg n8.1.2 `crop` ya no tiene la opción
`eval`, así que sus `w`/`h` se evalúan una sola vez y no se pueden animar.

Los motivos y las claves son en español pero NO son texto para el usuario: el
QML los traduce con Idioma.t().
"""
import argparse, json, math, os, re, subprocess, sys, tempfile

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
    #  Sin rastro también se edita.
    #
    #  El rastro del cursor solo existe si el vídeo lo grabó k4. Un vídeo
    #  abierto del disco no lo tiene, y antes esto reventaba con un
    #  FileNotFoundError que se llevaba por delante `camara` y `render`: el
    #  editor se quedaba en blanco sin decir por qué.
    meta, muestras, clics = {}, [], []
    if not ruta or not os.path.exists(ruta):
        return meta, muestras, clics
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
        m["seguir"] = True
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


def trayectoria(plan, fps=None):
    """z(t), x(t), y(t) muestreadas, ya con zona muerta y límite de paneo.

    Todo en tiempo de línea. Para seguir al cursor hay que preguntarle al mapa
    en qué fichero y en qué segundo de ese fichero cae cada instante, porque el
    rastro va en tiempo de fuente y no sabe nada de cortes ni de reordenaciones.
    """
    momentos = plan["momentos"]
    ancho, alto = plan["w"], plan["h"]
    fps = fps or plan["fps"]

    tramos = mapa(plan)
    duracion = tramos[-1][1] if tramos else 0.0

    #  Un rastro por fuente, leído una sola vez. Con cortes y reordenaciones el
    #  mismo fichero aparece varias veces en la línea, y releerlo en cada tramo
    #  sería recorrer un jsonl de miles de líneas por trozo.
    rastros = {f["id"]: suavizar(leer_rastro(f.get("rastro", ""))[1])
               for f in plan["fuentes"]}

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
            elif not activo.get("seguir", True):
                #  Encuadre fijo: te has puesto tú a mover el centro, así que la
                #  cámara se queda donde la dejaste. Sin esta rama, arrastrar el
                #  encuadre no se vería: en cuanto acababa la entrada, la cámara
                #  se volvía a ir detrás del cursor.
                #
                #  Los planes de antes de que esto existiera no traen la clave, y
                #  el `True` por defecto los deja como estaban.
                cx, cy = activo["cx"], activo["cy"]
            else:
                #  Ya dentro: se sigue al cursor, y AQUÍ sí manda el límite de
                #  paneo junto con la zona muerta. Es lo que separa un
                #  seguimiento tranquilo de un temblor perpetuo.
                fuente, ts = donde(tramos, t)
                p = None
                if fuente is not None:
                    p = posicion_en(rastros.get(fuente["id"], []), ts)
                    if p:
                        p = a_lienzo(fuente, p[0], p[1], ancho, alto)
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
    """Quita los puntos que una recta ya predice: menos nodos, misma curva.

    Con una excepción que no es negociable: **donde no hay zoom, no se toca el
    fotograma**. El último punto de una rampa de salida vale 1,0034 y el
    siguiente que sobrevivía era el final del vídeo, así que entre medias se
    interpolaba y quedaba un 1,0005 arrastrándose segundos. Dentro de la
    tolerancia, sí, pero `zoompan` remuestrea igual y el texto de una grabación
    sale ligeramente borroso sin que nada lo explique.

    Los instantes en los que z vale exactamente 1 y su vecino no se marcan como
    intocables: cuesta un puñado de nodos y a cambio el vídeo sin zoom sale
    idéntico al original.
    """
    if len(puntos) < 3:
        return puntos

    def plano(i):
        return abs(puntos[i][1] - 1.0) < 1e-9

    intocables = set()
    for i in range(1, len(puntos) - 1):
        if plano(i) != plano(i - 1) or plano(i) != plano(i + 1):
            intocables.add(i)

    salida = [puntos[0]]
    ancla = 0
    for i in range(1, len(puntos) - 1):
        t0, z0, x0, y0 = puntos[ancla]
        t2, z2, x2, y2 = puntos[i + 1]
        t1, z1, x1, y1 = puntos[i]
        if t2 == t0:
            continue
        u = (t1 - t0) / (t2 - t0)
        if (i in intocables
                or abs(z0 + (z2 - z0) * u - z1) > tol_z
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


# ── el grafo de filtros ───────────────────────────────────────────
#
#  Un solo `filter_complex` con el vídeo y el audio dentro, montado en cuatro
#  pisos: cada clip se recorta y se normaliza, se pegan con `concat`, encima va
#  el `zoompan` y al final las capas.
#
#  La normalización no es opcional: `concat` exige que todos los trozos tengan
#  el mismo tamaño, la misma relación de píxel y el mismo ritmo. Sin ella,
#  juntar una grabación de 1080p con un vídeo de 720p falla, y falla tarde.
NORMA_AUDIO = "aformat=sample_fmts=fltp:sample_rates=48000:channel_layouts=stereo"


def norma_video(ancho, alto, fps):
    #  `decrease` + `pad` y no `scale` a secas: un vídeo de otra proporción hay
    #  que meterlo entero con banda negra, no estirarlo. Es lo mismo que hace
    #  `a_lienzo()` con el rastro del cursor, y tiene que serlo o el zoom
    #  apuntaría a otro sitio.
    return ("scale=%d:%d:force_original_aspect_ratio=decrease,"
            "pad=%d:%d:(ow-iw)/2:(oh-ih)/2,setsar=1,fps=%g,format=yuv420p"
            % (ancho, alto, ancho, alto, fps))


def capas_de(plan, tipo=None):
    """Las capas del plan, de abajo arriba.

    Cada capa pertenece a una **banda**, y las bandas son lo que se apila. La 1
    es la del VÍDEO —los trozos de la pista base—, así que las capas van de la 2
    para arriba y la última es la de más arriba. Dentro de una banda pueden convivir
    varias capas —lo normal es que no se pisen en el tiempo—, y ahí manda el
    orden de la lista.

    Al principio una capa ERA una banda, una cosa suelta con su fila propia. Se
    quedó corto por los dos lados: no había nada que mover de una banda a otra
    —que es lo primero que uno intenta— y con seis imágenes salían seis filas
    cuando lo natural son dos bandas con tres cada una.

    El orden se saca con `sorted`, que en python es estable: dentro de la misma
    banda se conserva el orden de la lista. No hace falta más.
    """
    bandas = {int(b.get("banda", 0)): b for b in plan.get("bandas", [])}
    solo = {b for b, info in bandas.items() if info.get("solo")}
    capas = []
    for c in plan.get("capas", []):
        if tipo is not None and c.get("tipo") != tipo:
            continue
        b = int(c.get("banda", 2))
        info = bandas.get(b, {})
        if c.get("visible", True) is False or info.get("visible", True) is False:
            continue
        if solo and b not in solo:
            continue
        capas.append(c)
    return sorted(capas, key=lambda c: c.get("banda", 2))


def entradas(plan, carpeta=None):
    """Los ficheros que hay que abrir, y en qué orden se los pasamos a ffmpeg.

    Un fichero se abre UNA vez aunque aparezca en seis clips o en tres capas:
    referenciar `[0:v]` varias veces es legal y ffmpeg mete el `split` por su
    cuenta. Devuelve las rutas y, para cada fuente y cada capa, qué entrada le
    toca; y de propina el índice del anillo de los clics, o -1 si no hay.

    `carpeta` solo hace falta para el anillo, que es un fichero que se fabrica
    aquí y no lo trae el usuario. Quien renderiza tiene que pasar la MISMA
    carpeta que le pase al grafo, o los índices no cuadrarían.
    """
    rutas, indice = [], {}

    def apuntar(ruta):
        if ruta not in indice:
            indice[ruta] = len(rutas)
            rutas.append(ruta)
        return indice[ruta]

    de_fuente = {f["id"]: apuntar(f["ruta"]) for f in plan["fuentes"]}
    de_capa = {c["id"]: apuntar(c["ruta"])
               for c in capas_de(plan) if c.get("ruta")}

    idx_anillo = -1
    if carpeta and plan.get("clics", {}).get("activo"):
        anillo = dibujar_anillo(carpeta, plan)
        if anillo:
            idx_anillo = apuntar(anillo)
    return rutas, de_fuente, de_capa, idx_anillo


def carpeta_de(ruta_plan):
    """La carpeta adjunta de un plan: `<vídeo>.k4/` para `<vídeo>.k4.json`."""
    return ruta_plan[:-5] if ruta_plan.endswith(".json") else ruta_plan + ".k4"


def abrir_entradas(plan, rutas):
    """Los argumentos de apertura de cada entrada, en orden.

    Casi todas son un `-i` y ya. Una fuente que es una IMAGEN necesita además
    `-loop 1 -t <segundos>`: sin el bucle es un flujo de un fotograma que se
    acaba al instante, y `trim` no tendría de dónde sacar los demás.

    El `-t` sale del clip más largo que la use, con un segundo de propina: si se
    queda corto el trozo sale más breve de lo que dice el plan, y eso descolocaría
    la línea entera.
    """
    #  Qué ruta corresponde a una fuente imagen y hasta dónde hay que estirarla.
    hasta = {}
    for f in plan.get("fuentes", []):
        if f.get("tipo") != "imagen":
            continue
        largo = float(f.get("dur", 3.0))
        for c in plan.get("clips", []):
            if c.get("fuente") == f["id"]:
                largo = max(largo, float(c.get("hasta", 0)))
        hasta[os.path.abspath(f["ruta"])] = largo + 1.0

    args = []
    for r in rutas:
        t = hasta.get(os.path.abspath(r))
        if t is not None:
            args += ["-loop", "1", "-t", "%.3f" % t]
        args += ["-i", r]
    return args


def cadena_atempo(v):
    """Los `atempo` que hacen falta para un factor cualquiera, o "" si es 1.

    `atempo` acepta de 0,5 a 100 en una instancia —comprobado: 0,25 contesta
    «Numerical result out of range» y tumba la orden entera—, así que para ir
    más lento se encadenan dos, que es la forma que documenta ffmpeg. Se usa
    esto y no `asetrate` porque `atempo` conserva el tono: acelerar con
    `asetrate` convierte una voz en un pitido.
    """
    if abs(v - 1.0) < 1e-6:
        return ""
    trozos = []
    resto = v
    while resto < 0.5 - 1e-9:
        trozos.append(0.5)
        resto /= 0.5
    trozos.append(resto)
    return ",".join("atempo=%.6f" % t for t in trozos)


def rama_audio(i, idx, clip, fuente, dur, fundido=""):
    """La rama de audio de un clip, ya mezclada y a volumen.

    Devuelve las líneas del grafo. Las pistas mudas no entran; si no queda
    ninguna —o la fuente no tiene audio— se rellena con silencio, porque a
    `concat` hay que darle todas las ramas o no arranca.
    """
    #  Un clip mudo no aporta sonido, y eso ya sabe hacerlo la rama de
    #  silencio que existe para los vídeos sin audio. Es lo que deja
    #  «separar el audio» sin tener que inventar nada: se saca a una capa y el
    #  trozo se calla.
    vivas = [] if clip.get("mudo") else [
        p for p in fuente.get("pistas", []) if not p.get("mudo")]

    if not vivas:
        #  Silencio del mismo largo que el trozo. Sin esto, un clip sacado de un
        #  vídeo mudo tumba el `concat` entero, y con él todo el render.
        #  `dur` ya viene en tiempo de línea, o sea con la velocidad aplicada.
        #  Y no lleva fundido: fundir silencio no es nada.
        return ["anullsrc=r=48000:cl=stereo,atrim=0:%.4f,asetpts=PTS-STARTPTS[a%d]"
                % (dur, i)]

    #  El fundido va al final de todo, después de la norma: si fuera antes del
    #  `amix` habría que aplicarlo a cada pista y sonaría dos veces.
    cola = ("," + fundido) if fundido else ""

    # Con una sola pista no hay nada que mezclar, así que su rama ya es la
    # salida del clip y se etiqueta directamente como tal.
    una = len(vivas) == 1

    #  La velocidad va DESPUÉS del recorte y del volumen y ANTES de la norma:
    #  `atrim` corta en segundos del fichero, que es donde el usuario eligió el
    #  trozo, y a `amix` hay que darle todo ya al mismo formato.
    tempo = cadena_atempo(velocidad_de(clip))
    tempo = tempo + "," if tempo else ""

    lineas, etiquetas = [], []
    for p in vivas:
        et = "a%d" % i if una else "c%dp%d" % (i, p["i"])
        lineas.append(
            "[%d:a:%d]atrim=start=%.4f:end=%.4f,asetpts=PTS-STARTPTS,"
            "volume=%.3f,%s%s%s[%s]"
            % (idx, p["i"], clip["desde"], clip["hasta"],
               float(p.get("volumen", 1.0)), tempo, NORMA_AUDIO,
               cola if una else "", et))
        etiquetas.append("[%s]" % et)

    if una:
        return lineas

    #  `normalize=0`: sin esto amix baja el volumen de todas al sumarlas, y
    #  subir una acabaría bajando la otra sin que nadie lo haya pedido.
    lineas.append("%samix=inputs=%d:normalize=0%s[a%d]"
                  % ("".join(etiquetas), len(etiquetas), cola, i))
    return lineas


#  La fuente de los rótulos.
#
#  La misma que usa la interfaz, y por eso está aquí y no en un ajuste: si el
#  editor midiera el texto con una tipografía y ffmpeg lo dibujara con otra, la
#  previa mentiría en el ancho de cada rótulo. Es la de Adwaita, que viene con
#  GNOME y está en cualquier escritorio moderno.
FUENTE = "/usr/share/fonts/Adwaita/AdwaitaSans-Regular.ttf"


def citar(valor):
    """Un valor para dentro de un filtro de ffmpeg, entre comillas simples.

    El parseo de ffmpeg funciona como el del shell: dentro de comillas simples
    todo es literal menos la propia comilla. Las rutas las compone el editor a
    partir del nombre del vídeo, que lo pone el usuario, así que pueden traer
    cualquier cosa.
    """
    return "'" + str(valor).replace("\\", "\\\\").replace("'", r"\'") + "'"


def color_ffmpeg(css, opacidad=1.0):
    """De `#rrggbb` o `#aarrggbb` de QML a lo que entiende ffmpeg.

    ffmpeg quiere `0xRRGGBB@alfa`, con el alfa aparte y en fracción. QML puede
    dar las dos formas, y la de ocho dígitos lleva el alfa DELANTE.
    """
    s = str(css).lstrip("#")
    if len(s) == 8:
        opacidad = opacidad * int(s[0:2], 16) / 255.0
        s = s[2:]
    if len(s) != 6:
        s = "ffffff"
    return "0x%s@%.3f" % (s, max(0.0, min(1.0, opacidad)))


def expresion_animada(capa, campo, defecto):
    """Expresión ffmpeg lineal para los fotogramas clave de una capa."""
    ks = sorted(capa.get("keyframes", []) or [], key=lambda x: float(x.get("t", 0)))
    if not ks:
        return "%.6f" % float(capa.get(campo, defecto))
    puntos = [(float(k.get("t", 0)), float(k.get(campo, defecto))) for k in ks]
    if len(puntos) == 1:
        return "%.6f" % puntos[0][1]
    def tramo(i):
        t0, v0 = puntos[i]
        t1, v1 = puntos[i + 1]
        if abs(t1 - t0) < 1e-6:
            return "%.6f" % v1
        return "(%.6f+(%.6f)*(t-%.6f))" % (v0, (v1 - v0) / (t1 - t0), t0)
    expr = "%.6f" % puntos[-1][1]
    for i in range(len(puntos) - 2, -1, -1):
        expr = "if(lt(t,%.6f),%s,%s)" % (puntos[i + 1][0], tramo(i), expr)
    return expr


def rama_texto(n, capa, ancho, alto, carpeta, entra):
    """Un rótulo. Devuelve (líneas, etiqueta de salida).

    El texto va a un FICHERO y se le pasa con `textfile`, nunca con `text=`. No
    es cautela de más: lo escribe el usuario, y un `:` o una comilla dentro de
    `text=` no rompen el rótulo sino el grafo entero, o sea el render completo.
    Con un fichero, el contenido no pasa por el parseo de filtros.
    """
    ruta = os.path.join(carpeta, "texto-%d.txt" % capa["id"])
    with open(ruta, "w") as f:
        f.write(capa.get("texto", ""))

    tam = max(8, int(round(alto * float(capa.get("tam", 0.06)))))
    #  `expansion=none`: sin esto `drawtext` se cree que el texto lleva formato y
    #  un «50 %» acaba en «Stray %» y en un rótulo a medias. Probado.
    partes = ["drawtext=fontfile=%s" % citar(FUENTE),
              "textfile=%s" % citar(ruta),
              "expansion=none",
              ("fontsize='%s*h'" % expresion_animada(capa, "tam", 0.06)
               if capa.get("keyframes") else "fontsize=%d" % tam),
              "fontcolor=%s" % color_ffmpeg(capa.get("color", "#ffffff")),
              #  Centrado en (x, y) como las demás capas: `text_w` y `text_h` son
              #  lo que mide el rótulo ya compuesto.
              ("x='%s*w-text_w/2'" % expresion_animada(capa, "x", 0.5)
               if capa.get("keyframes") else
               "x=%.4f*w-text_w/2" % float(capa.get("x", 0.5))),
              ("y='%s*h-text_h/2'" % expresion_animada(capa, "y", 0.85)
               if capa.get("keyframes") else
               "y=%.4f*h-text_h/2" % float(capa.get("y", 0.85))),
              "enable='between(t,%.4f,%.4f)'"
              % (float(capa.get("t0", 0)), float(capa.get("t1", 0)))]

    fondo = float(capa.get("fondo", 0.0))
    if fondo > 0.001:
        # Una caja detrás, para que el texto se lea sobre cualquier cosa.
        partes += ["box=1",
                   "boxcolor=%s" % color_ffmpeg(capa.get("colorFondo", "#000000"),
                                                fondo),
                   "boxborderw=%d" % max(2, int(round(tam * 0.28)))]

    sale = "ov%d" % n
    return ["[%s]%s[%s]" % (entra, ":".join(partes), sale)], sale


def rama_pip(n, idx, capa, ancho, alto, entra):
    """Un vídeo dentro del vídeo. Devuelve (líneas, etiqueta de salida).

    Tres cosas que lo separan de una imagen:

    - `trim` para quedarse con el trozo que interesa del fichero de la capa, y
      `setpts` para colocarlo en el instante de la LÍNEA en que se quiere ver. Sin
      el `setpts` el clip empieza en el segundo cero del vídeo grande y lo único
      que hace el `enable` es taparlo hasta su tramo: se vería congelado.
    - `eof_action=pass`. Un clip se acaba antes que el vídeo, y sin esto la salida
      se trunca a la longitud de la capa. Medido: con `endall` el vídeo entero se
      queda en 0,03 s.
    - Su audio se tira. Meterlo sería otra rama y otra decisión —¿a qué volumen?,
      ¿mezclado con qué?—, y una capa de audio ya hace eso mejor.
    """
    lineas = []
    et = "pip%d" % n
    ancho_capa = max(2, int(round(ancho * float(capa.get("escala", 0.3)))))
    escala_expr = expresion_animada(capa, "escala", 0.3)

    recorte = capa.get("recorte") or [0, 0]
    filtros = []
    if float(recorte[1]) > float(recorte[0]):
        filtros.append("trim=start=%.4f:end=%.4f"
                       % (float(recorte[0]), float(recorte[1])))
    # Recorte espacial de la fuente, antes de escalarla y colocarla. Las
    # coordenadas son fracciones del vídeo original para que el plan no dependa
    # de la resolución.
    an, al, px, py = caja_recorte_fuente(capa)
    fuente_w = int(round(float(capa.get("w", an))))
    fuente_h = int(round(float(capa.get("h", al))))
    if an < fuente_w or al < fuente_h:
        filtros.append("crop=%d:%d:%d:%d" % (an, al, px, py))
    #  `setpts` SIEMPRE, aunque no haya recorte: pone los tiempos del clip a cero
    #  y luego lo empuja hasta su instante.
    filtros.append("setpts=PTS-STARTPTS+%.4f/TB" % float(capa.get("t0", 0)))

    #  Quitar el fondo verde, ANTES de escalar.
    #
    #  Antes y no después porque el escalado inventa píxeles intermedios entre
    #  el sujeto y el fondo, y esos ya no son ni verde ni piel: recortarlos
    #  después deja un halo. `despill` quita el reflejo verde que queda en los
    #  bordes, que es lo que delata un croma mal hecho.
    croma = capa.get("croma") or {}
    if croma.get("color"):
        filtros.append("format=rgba")
        filtros.append("chromakey=%s:%.4f:%.4f"
                       % (color_ffmpeg(croma["color"]).split("@")[0],
                          encaja(float(croma.get("tolerancia", 0.15)),
                                 0.01, 1.0),
                          encaja(float(croma.get("suavizado", 0.05)),
                                 0.0, 1.0)))
        filtros.append("despill=type=green")

    rotacion = float(capa.get("rotacion", 0.0))
    hay_rotacion = abs(rotacion) > 0.01 or any(
        abs(float(k.get("rotacion", 0))) > 0.01
        for k in (capa.get("keyframes") or []))
    if hay_rotacion:
        filtros.append("format=rgba")
        if capa.get("keyframes"):
            filtros.append("rotate='%s*PI/180':fillcolor=none" %
                           expresion_animada(capa, "rotacion", rotacion))
        else:
            filtros.append("rotate=%.6f*PI/180:fillcolor=none" % rotacion)

    if capa.get("keyframes"):
        filtros.append("scale=w='round(%d*%s)':h=-1:eval=frame" % (ancho, escala_expr))
    else:
        filtros.append("scale=%d:-1" % ancho_capa)
    filtros.append("setsar=1")

    opacidad = float(capa.get("opacidad", 1.0))
    if opacidad < 0.999:
        if capa.get("keyframes"):
            filtros.append("format=rgba,colorchannelmixer=aa='%s'" %
                           expresion_animada(capa, "opacidad", opacidad))
        else:
            filtros.append("format=rgba,colorchannelmixer=aa=%.3f" % opacidad)

    lineas.append("[%d:v]%s[%s]" % (idx, ",".join(filtros), et))

    sale = "ov%d" % n
    if capa.get("keyframes"):
        linea_overlay = (
            "[%s][%s]overlay=x='%s*W-w/2':y='%s*H-h/2':"
            "enable='between(t,%.4f,%.4f)':eof_action=pass[%s]"
            % (entra, et, expresion_animada(capa, "x", 0.75),
               expresion_animada(capa, "y", 0.75),
               float(capa.get("t0", 0)), float(capa.get("t1", 0)), sale))
    else:
        linea_overlay = (
            "[%s][%s]overlay=x=%.4f*W-w/2:y=%.4f*H-h/2:"
            "enable='between(t,%.4f,%.4f)':eof_action=pass[%s]"
            % (entra, et, float(capa.get("x", 0.75)),
               float(capa.get("y", 0.75)), float(capa.get("t0", 0)),
               float(capa.get("t1", 0)), sale))
    lineas.append(linea_overlay)
    return lineas, sale


def rama_capa(n, idx, capa, ancho, alto, entra):
    """Una capa encima del vídeo. Devuelve (líneas, etiqueta de salida).

    Todo en espacio de SALIDA: la capa va después del `zoompan`, así que no se
    amplía con él. Es lo que se quiere de un logo o un rótulo, y es lo que hace
    que la previa del editor —donde las capas también se pintan fuera de la
    lente— coincida por construcción.

    Las coordenadas del plan son fracciones del fotograma y apuntan al CENTRO de
    la capa: así el plan no depende de la resolución y arrastrar es una regla de
    tres. `overlay` quiere la esquina, de ahí el medio ancho de resta.
    """
    lineas = []
    et = "cap%d" % n
    ancho_capa = max(2, int(round(ancho * float(capa.get("escala", 0.25)))))
    escala_expr = expresion_animada(capa, "escala", 0.25)

    filtros = []
    rotacion = float(capa.get("rotacion", 0.0))
    hay_rotacion = abs(rotacion) > 0.01 or any(
        abs(float(k.get("rotacion", 0))) > 0.01
        for k in (capa.get("keyframes") or []))
    if hay_rotacion:
        filtros.append("format=rgba")
        if capa.get("keyframes"):
            filtros.append("rotate='%s*PI/180':fillcolor=none" %
                           expresion_animada(capa, "rotacion", rotacion))
        else:
            filtros.append("rotate=%.6f*PI/180:fillcolor=none" % rotacion)
    if capa.get("keyframes"):
        filtros.append("scale=w='round(%d*%s)':h=-1:eval=frame" % (ancho, escala_expr))
    else:
        filtros.append("scale=%d:-1" % ancho_capa)
    opacidad = float(capa.get("opacidad", 1.0))
    if opacidad < 0.999:
        #  El alfa hay que tenerlo antes de poder tocarlo: un JPEG llega sin
        #  canal alfa y `colorchannelmixer=aa=` no haría nada, sin quejarse.
        if capa.get("keyframes"):
            filtros.append("format=rgba,colorchannelmixer=aa='%s'" %
                           expresion_animada(capa, "opacidad", opacidad))
        else:
            filtros.append("format=rgba,colorchannelmixer=aa=%.3f" % opacidad)

    lineas.append("[%d:v]%s[%s]" % (idx, ",".join(filtros), et))

    #  Sin `eof_action`, o sea con el `repeat` de fábrica.
    #
    #  Una imagen es un flujo de UN fotograma, así que se acaba en el instante
    #  cero. Con `eof_action=pass` el overlay deja pasar el vídeo tal cual en
    #  cuanto eso ocurre y la capa no llega a verse nunca; con `endall` corta la
    #  salida a un fotograma. Medido con las cuatro opciones sobre el mismo
    #  fichero: por defecto y con `repeat` la capa sale y el vídeo conserva sus
    #  8 s; con `pass` no sale; con `endall` el vídeo se queda en 0,03 s.
    #
    #  Y no hace falta protegerse de que la salida se trunque, porque `shortest`
    #  es 0 de fábrica: manda la duración de la entrada principal.
    sale = "ov%d" % n
    if capa.get("keyframes"):
        linea_overlay = (
            "[%s][%s]overlay=x='%s*W-w/2':y='%s*H-h/2':"
            "enable='between(t,%.4f,%.4f)'[%s]"
            % (entra, et, expresion_animada(capa, "x", 0.5),
               expresion_animada(capa, "y", 0.5),
               float(capa.get("t0", 0.0)), float(capa.get("t1", 0.0)), sale))
    else:
        linea_overlay = (
            "[%s][%s]overlay=x=%.4f*W-w/2:y=%.4f*H-h/2:"
            "enable='between(t,%.4f,%.4f)'[%s]"
            % (entra, et, float(capa.get("x", 0.5)),
               float(capa.get("y", 0.5)), float(capa.get("t0", 0.0)),
               float(capa.get("t1", 0.0)), sale))
    lineas.append(linea_overlay)
    return lineas, sale


#  Cuánto aprieta cada modo de zona.
#
#  En el plan la fuerza es siempre 0-1, y cada modo la traduce a lo suyo: así el
#  panel enseña UN deslizador y cambiar de modo no obliga a volver a ajustarlo.
#  Los topes salen de mirar el resultado: sigma 40 ya es una mancha de color, y
#  bloques de 64 px sobre 1080 son ocho bloques de alto, que es tan ilegible como
#  hace falta.
def fuerza_zona(modo, f):
    f = encaja(float(f), 0.0, 1.0)
    if modo == "pixelado":
        return max(4, int(round(4 + f * 60)))
    if modo == "foco":
        return 0.15 + f * 0.65
    return 2.0 + f * 38.0


def caja_zona(capa, ancho, alto):
    """La zona en píxeles enteros y pares: (an, al, x, y) de la ESQUINA.

    Pares porque el recorte va a formatos con croma submuestreado y una anchura
    impar deja a `crop` colocando la mitad de un píxel. Y acotada al fotograma:
    una zona arrastrada fuera del borde daría un `crop` negativo, que no es un
    aviso sino un error que tumba el render entero.
    """
    def par(v, minimo=2):
        return max(minimo, int(round(v)) & ~1)

    an = par(ancho * encaja(float(capa.get("an", 0.3)), 0.01, 1.0))
    al = par(alto * encaja(float(capa.get("al", 0.2)), 0.01, 1.0))
    an, al = min(an, par(ancho)), min(al, par(alto))
    x = par(ancho * float(capa.get("x", 0.5)) - an / 2.0, 0)
    y = par(alto * float(capa.get("y", 0.5)) - al / 2.0, 0)
    return an, al, min(x, ancho - an), min(y, alto - al)


def caja_recorte_fuente(capa):
    """El recorte rectangular de una capa de vídeo, en píxeles de su fuente."""
    def par(v, minimo=2):
        return max(minimo, int(round(v)) & ~1)

    fuente_w = max(2, int(round(float(capa.get("w", 1920)))))
    fuente_h = max(2, int(round(float(capa.get("h", 1080)))))
    r = capa.get("recorteFuente") or [0, 0, 1, 1]
    if not isinstance(r, (list, tuple)) or len(r) != 4:
        r = [0, 0, 1, 1]
    x = encaja(float(r[0]), 0.0, 0.99)
    y = encaja(float(r[1]), 0.0, 0.99)
    w = encaja(float(r[2]), 0.01, 1.0 - x)
    h = encaja(float(r[3]), 0.01, 1.0 - y)
    ancho = min(par(fuente_w), par(fuente_w * w))
    alto = min(par(fuente_h), par(fuente_h * h))
    px = min(par(fuente_w * x, 0), fuente_w - ancho)
    py = min(par(fuente_h * y, 0), fuente_h - alto)
    return ancho, alto, px, py


def filtro_color(clip):
    """`eq` con el brillo, contraste y saturación del clip, o "" si no toca.

    Va dentro de la normalización de cada trozo, o sea antes del `concat`: es
    del trozo, no de la línea, y así se pueden juntar dos grabaciones que no
    casan de color sin tocar la otra.
    """
    c = clip.get("color") or {}

    #  Nada de `x or por_defecto`: **el cero es falso en python**, así que
    #  `saturacion: 0` —quitar el color, que es justo lo que uno pide— se
    #  convertía en 1 y el filtro no salía. Medido: el fotograma con saturación
    #  cero era idéntico al original.
    def leer(clave, por_defecto, minimo, maximo):
        v = c.get(clave)
        if v is None:
            v = por_defecto
        try:
            return encaja(float(v), minimo, maximo)
        except (TypeError, ValueError):
            return por_defecto

    brillo = leer("brillo", 0.0, -1.0, 1.0)
    contraste = leer("contraste", 1.0, 0.0, 3.0)
    saturacion = leer("saturacion", 1.0, 0.0, 3.0)
    if (abs(brillo) < 1e-4 and abs(contraste - 1.0) < 1e-4
            and abs(saturacion - 1.0) < 1e-4):
        return ""
    return ("eq=brightness=%.4f:contrast=%.4f:saturation=%.4f"
            % (brillo, contraste, saturacion))


def fundidos_de(plan):
    """(entrada, salida, entre) en segundos, saneados."""
    f = plan.get("fundidos") or {}
    def leer(clave):
        try:
            return max(0.0, float(f.get(clave, 0.0) or 0.0))
        except (TypeError, ValueError):
            return 0.0
    return leer("entrada"), leer("salida"), leer("entre")


def filtros_fundido(i, total, dur, plan):
    """Los `fade` de vídeo y audio de un trozo, en tiempo LOCAL del trozo.

    Local y no de línea: van dentro de la rama del clip, antes del `concat`, y
    ahí cada trozo empieza en cero. Y después del `setpts` de la velocidad, o
    sea sobre la duración que el trozo ocupa en la LÍNEA — que es la que se ve.

    Nada de `xfade`: un encadenado de verdad solapa los trozos y acorta la
    línea, y eso descolocaría el mapa y con él todos los rótulos y zooms. Aquí
    «entre» es fundir a negro al final de uno y desde negro al principio del
    siguiente, que cabe dentro del trozo y no mueve nada.
    """
    entrada, salida, entre = fundidos_de(plan)
    dentro = entre / 2.0 if entre > 0 else 0.0

    #  Al primero le toca el fundido de entrada; al último, el de salida; y
    #  entre medias, medio «entre» por cada lado del corte.
    ini = entrada if i == 0 else dentro
    fin = salida if i == total - 1 else dentro

    #  Dos fundidos no pueden solaparse dentro de un trozo corto: si la suma se
    #  pasa de lo que dura, se reparte a partes iguales. Sin esto, un trozo de
    #  0,2 s con un segundo de fundido se queda en negro entero.
    if ini + fin > dur and dur > 0:
        factor = dur / (ini + fin)
        ini, fin = ini * factor, fin * factor

    v, a = [], []
    if ini > 0.001:
        v.append("fade=t=in:st=0:d=%.4f" % ini)
        a.append("afade=t=in:st=0:d=%.4f" % ini)
    if fin > 0.001:
        v.append("fade=t=out:st=%.4f:d=%.4f" % (max(0.0, dur - fin), fin))
        a.append("afade=t=out:st=%.4f:d=%.4f" % (max(0.0, dur - fin), fin))
    return ",".join(v), ",".join(a)


def rama_zona(n, capa, ancho, alto, entra):
    """Tapar o destacar un trozo del fotograma. (líneas, etiqueta de salida).

    Los tres modos son la misma jugada: partir la imagen en dos, tratar una
    copia y volver a pegar el rectángulo encima. Lo que cambia es qué se trata.
    En el desenfoque y el pixelado se estropea la región y se pega sobre el
    original; en el foco se oscurece el ORIGINAL y se pega encima la región
    intacta, que es justo lo contrario.

    Va después del `zoompan`, como todas las capas: la zona es del lienzo de
    salida y no persigue al contenido si el zoom se mueve por debajo. Es lo
    mismo que ya pasa con los rótulos, y es lo que hace que la previa del
    editor coincida por construcción.
    """
    modo = capa.get("modo", "desenfoque")
    an, al, x, y = caja_zona(capa, ancho, alto)
    fuerza = fuerza_zona(modo, capa.get("fuerza", 0.5))
    a, b = float(capa.get("t0", 0.0)), float(capa.get("t1", 0.0))
    corte = "crop=%d:%d:%d:%d" % (an, al, x, y)
    sale = "zon%d" % n

    if modo == "foco":
        return ([
            "[%s]split[zc%d][zf%d]" % (entra, n, n),
            "[zc%d]eq=brightness=%.4f:saturation=%.3f[zo%d]"
            % (n, -fuerza, max(0.0, 1.0 - fuerza * 0.5), n),
            "[zf%d]%s[zr%d]" % (n, corte, n),
            "[zo%d][zr%d]overlay=x=%d:y=%d:enable='between(t,%.4f,%.4f)'[%s]"
            % (n, n, x, y, a, b, sale),
        ], sale)

    if modo == "pixelado":
        tratar = "pixelize=w=%d:h=%d" % (fuerza, fuerza)
    else:
        tratar = "gblur=sigma=%.3f:steps=3" % fuerza

    return ([
        "[%s]split[zc%d][zf%d]" % (entra, n, n),
        "[zf%d]%s,%s[zr%d]" % (n, corte, tratar, n),
        "[zc%d][zr%d]overlay=x=%d:y=%d:enable='between(t,%.4f,%.4f)'[%s]"
        % (n, n, x, y, a, b, sale),
    ], sale)


#  Cuánto dura el destello de un clic y de qué tamaño es.
#
#  0,35 s es lo que tarda en verse sin llegar a molestar; más corto se pierde en
#  un vídeo a 30 fps y más largo se solapa con el clic siguiente al hacer doble
#  clic. El diámetro va en fracción del ancho para que en 4K se vea igual.
CLIC_DUR = 0.35
CLIC_DIAMETRO = 0.055


def dibujar_anillo(carpeta, plan):
    """El PNG del destello, dibujado una vez y reusado por todos los clics.

    Dos círculos concéntricos y nada de relleno: un disco opaco tapa justo lo
    que quieres enseñar, que es dónde has pulsado. Se hace con `magick` porque
    ffmpeg no sabe dibujar un círculo sin montar un `geq` ilegible.

    Devuelve la ruta, o "" si no se pudo dibujar; el render sigue sin él.
    """
    #  La carpeta se crea aquí y no se da por hecha.
    #
    #  `entradas` corre ANTES que `escribir_grafo`, que es quien la creaba, así
    #  que en la primera ejecución de un plan nuevo el anillo no se dibujaba
    #  —magick no puede escribir en un directorio que no existe— pero el grafo
    #  sí lo referenciaba. Los índices de entrada dejaban de cuadrar y ffmpeg se
    #  caía. Solo pasaba la primera vez, que es la peor forma de que pase.
    try:
        os.makedirs(carpeta, exist_ok=True)
    except OSError:
        return ""

    ajustes = plan.get("clics", {})
    color = str(ajustes.get("color", "#ffd60a"))
    lado = max(16, int(round(plan["w"] * CLIC_DIAMETRO)))
    #  El nombre lleva el color y el lado: cambiar el color no puede reusar el
    #  anillo viejo, y dos vídeos de distinto tamaño tampoco comparten el suyo.
    ruta = os.path.join(carpeta, "clic-%s-%d.png"
                        % (color.lstrip("#").lower(), lado))
    if os.path.exists(ruta):
        return ruta

    #  En `-draw circle cx,cy px,py` el SEGUNDO punto está en la circunferencia,
    #  no es un radio. Poniéndolo como si lo fuera salían dos puntos diminutos:
    #  medido, un anillo de 22 px donde tocaban 35.
    r = lado / 2.0
    grosor = max(2, int(round(lado / 12.0)))
    borde = r - grosor / 2.0            # el aro de fuera, pegado al canto
    dentro = r * 0.42                   # y un punto en el centro del clic
    orden = ["magick", "-size", "%dx%d" % (lado, lado), "xc:none",
             "-fill", "none", "-stroke", color, "-strokewidth", str(grosor),
             "-draw", "circle %.1f,%.1f %.1f,%.1f" % (r, r, r, r - borde),
             "-strokewidth", str(max(1, grosor // 2)),
             "-draw", "circle %.1f,%.1f %.1f,%.1f" % (r, r, r, r - dentro),
             ruta]
    try:
        p = subprocess.run(orden, capture_output=True, text=True)
    except OSError:
        return ""
    return ruta if p.returncode == 0 and os.path.exists(ruta) else ""


def clics_de(plan):
    """Los clics del rastro, en tiempo de LÍNEA y en píxeles del lienzo.

    El rastro apunta el instante de cada clic en tiempo de FUENTE, así que hay
    que pasarlo por el mapa. De regalo sale gratis lo que se querría: los clics
    de un trozo que has cortado desaparecen solos, y los de un trozo repetido
    salen las dos veces.

    La posición no la trae el clic —el rastro solo guarda el instante—: se saca
    de la muestra del cursor más cercana, que es lo que se hace también para
    seguir al cursor con el zoom.
    """
    if not plan.get("clics", {}).get("activo"):
        return []

    ancho, alto = plan["w"], plan["h"]
    cache = {}
    salida = []
    for a, b, clip, fuente in mapa(plan):
        ident = fuente["id"]
        if ident not in cache:
            cache[ident] = leer_rastro(fuente.get("rastro", ""))
        _, muestras, clics = cache[ident]
        if not clics or not muestras:
            continue
        v = velocidad_de(clip)
        for tc in clics:
            if not (clip["desde"] <= tc < clip["hasta"]):
                continue
            pos = posicion_en(muestras, tc)
            if pos is None:
                continue
            x, y = a_lienzo(fuente, pos[0], pos[1], ancho, alto)
            salida.append((a + (tc - clip["desde"]) / v, x, y))
    salida.sort()
    return salida


def ramas_clics(plan, idx_anillo, entra):
    """Un destello por clic. (líneas, etiqueta de salida).

    Un `overlay` por clic, encadenados. Referenciar la misma entrada muchas
    veces es legal —ffmpeg mete el `split` por su cuenta— y el grafo va por
    fichero desde el primer día justo para no chocar con el límite de 128 KB
    por argumento.
    """
    if idx_anillo < 0:
        return [], entra
    puntos = clics_de(plan)
    if not puntos:
        return [], entra

    lineas = []
    for n, (t, x, y) in enumerate(puntos):
        sale = "clic%d" % n
        lineas.append(
            "[%s][%d:v]overlay=x=%.2f-w/2:y=%.2f-h/2:"
            "enable='between(t,%.4f,%.4f)'[%s]"
            % (entra, idx_anillo, x, y, t, t + CLIC_DUR, sale))
        entra = sale
    return lineas, entra


def grafo(plan, sin_audio=False, carpeta=None):
    """El filter_complex entero. Devuelve (texto, nodos de la cámara).

    `carpeta` es dónde dejar los ficheros que necesita el grafo —de momento el
    texto de los rótulos—. Si no se da, uno temporal: así se puede pedir un grafo
    para mirarlo sin ensuciar nada.

    `sin_audio` es para sacar un fotograma suelto: en un grafo TODA etiqueta que
    se produce hay que consumirla, así que dejar `[a]` colgando sin mapearla no
    es «se ignora el audio» sino un error que tumba la orden entera. Es lo que
    tenía rota la previa desde que el grafo existe, sin que se notara porque
    todavía no la llama nadie.
    """
    ancho, alto, fps = plan["w"], plan["h"], plan["fps"]
    tramos = mapa(plan)
    #  La carpeta primero: el anillo de los clics se dibuja ahí y entra como una
    #  entrada más, así que `entradas` la necesita.
    if carpeta is None:
        carpeta = tempfile.mkdtemp(prefix="k4-grafo-")
    os.makedirs(carpeta, exist_ok=True)
    _, idx_de, idx_capa, idx_anillo = entradas(plan, carpeta)
    norma = norma_video(ancho, alto, fps)

    lineas = []

    # ── 1. cada trozo, recortado y normalizado
    for i, (a, b, clip, fuente) in enumerate(tramos):
        idx = idx_de[fuente["id"]]
        v = velocidad_de(clip)
        #  La velocidad del vídeo es dividir los PTS, y va en el mismo `setpts`
        #  que ya recolocaba el trozo al origen. El `fps` de la norma viene
        #  después y vuelve a repartir los fotogramas, así que a 4× no salen
        #  saltos: se descartan fotogramas, que es lo que toca.
        pts = ("setpts=(PTS-STARTPTS)/%.6f" % v) if abs(v - 1.0) > 1e-6 \
            else "setpts=PTS-STARTPTS"

        #  El color va DENTRO de la normalización de cada trozo, o sea antes del
        #  `concat`: es del trozo y no de la línea, que es lo que hace falta para
        #  juntar dos grabaciones que no casan.
        #
        #  Y el fundido, el último de la cadena y sobre la duración de LÍNEA:
        #  después del `setpts` de la velocidad, un trozo de 8 s a 2× ocupa 4 y
        #  el fundido tiene que caber en esos 4.
        color = filtro_color(clip)
        fv, fa = filtros_fundido(i, len(tramos), b - a, plan)
        cadena = ",".join(x for x in (pts, norma, color, fv) if x)

        lineas.append(
            "[%d:v]trim=start=%.4f:end=%.4f,%s[v%d]"
            % (idx, clip["desde"], clip["hasta"], cadena, i))
        lineas += rama_audio(i, idx, clip, fuente, b - a, fa)

    # ── 2. pegarlos
    if len(tramos) == 1:
        lineas.append("[v0]null[base]")
        lineas.append("[a0]anull[mez]")
    else:
        pares = "".join("[v%d][a%d]" % (i, i) for i in range(len(tramos)))
        lineas.append("%sconcat=n=%d:v=1:a=1[base][mez]"
                      % (pares, len(tramos)))

    # ── 3. el zoom, encima de lo ya pegado y en tiempo de línea
    puntos = adelgazar(trayectoria(plan, fps))
    lineas.append(
        "[base]zoompan=z='%s':x='%s':y='%s':d=1:s=%dx%d:fps=%g[zoom]"
        % (expresion(puntos, 1), expresion(puntos, 2), expresion(puntos, 3),
           ancho, alto, fps))

    # ── 4. los clics, antes que las capas
    #
    #  Antes a propósito: si tapas una zona con un desenfoque, lo que pasara
    #  ahí debajo no tiene que asomar por encima, ni siquiera un destello.
    lineas_clic, entra = ramas_clics(plan, idx_anillo, "zoom")
    lineas += lineas_clic

    # ── 5. las capas, después del zoom para que no se amplíen con él
    for n, capa in enumerate(capas_de(plan)):
        tipo = capa.get("tipo")
        if tipo == "texto":
            nuevas, entra = rama_texto(n, capa, ancho, alto, carpeta, entra)
            lineas += nuevas
            continue
        if tipo == "zona":
            #  No tiene fichero detrás: se hace con el propio fotograma.
            nuevas, entra = rama_zona(n, capa, ancho, alto, entra)
            lineas += nuevas
            continue
        if tipo not in ("imagen", "video"):
            # El audio va por su cuenta, al final.
            continue
        if not capa.get("ruta") or not os.path.exists(capa["ruta"]):
            #  Una capa cuyo fichero ya no está no puede tumbar el render: se
            #  salta y el resto sale. Borrar un PNG del escritorio meses después
            #  no debería impedirte volver a exportar el vídeo.
            continue
        constructor = rama_pip if tipo == "video" else rama_capa
        nuevas, entra = constructor(n, idx_capa[capa["id"]], capa,
                                    ancho, alto, entra)
        lineas += nuevas

    lineas.append("[%s]format=yuv420p[v]" % entra)

    # ── 6. el audio añadido, encima de lo que ya suena
    lineas += ramas_audio_extra(plan, idx_capa, sin_audio)

    # ── 7. y lo censurado, lo ÚLTIMO
    #
    #  Después de la mezcla a propósito: si fuera antes, la música añadida
    #  seguiría sonando encima de lo que se quería tapar.
    if not sin_audio:
        nuevas, fin = ramas_censura(plan, "amez")
        lineas += nuevas
        lineas.append("[%s]anull[a]" % fin)

    return ";\n".join(lineas), len(puntos)


def ramas_audio_extra(plan, idx_capa, sin_audio):
    """Las capas de audio, mezcladas con el sonido del vídeo.

    Cada una entra con su volumen y a partir de su instante, y todas se suman al
    audio de la base. Si el fotograma que se pide es suelto —una previa— no hay
    audio que mapear y todo va a un sumidero: en un `filter_complex` una etiqueta
    que se produce y no se consume no es «se ignora», es un error que tumba la
    orden entera.
    """
    extras = [c for c in capas_de(plan, "audio")
              if c.get("ruta") and os.path.exists(c["ruta"])]

    if sin_audio:
        # Ni se molestan en entrar: nadie va a escucharlas.
        return ["[mez]anullsink"]
    if not extras:
        return ["[mez]anull[amez]"]

    lineas, etiquetas = [], ["[mez]"]
    for k, capa in enumerate(extras):
        et = "ax%d" % k
        retardo = max(0, int(round(float(capa.get("t0", 0)) * 1000)))

        #  El recorte: qué trozo del fichero se oye.
        #
        #  Hasta ahora una capa de audio entraba entera y solo se elegía CUÁNDO
        #  empezaba. Con recorte se puede además decir QUÉ parte, que es lo que
        #  hace falta para sacar el audio de un trozo de vídeo a su propia capa:
        #  el trozo va del segundo 12 al 18 del fichero, no del 0 al 6.
        #
        #  Va antes del `volume` porque cortar y luego bajar es una operación
        #  menos que al revés, y antes del `adelay` porque el retardo cuenta
        #  desde el principio de lo que se oye, no del fichero.
        recorte = capa.get("recorte") or []
        partes = ["[%d:a]" % idx_capa[capa["id"]]]
        if len(recorte) == 2 and float(recorte[1]) > float(recorte[0]):
            partes[0] += ("atrim=start=%.4f:end=%.4f,asetpts=PTS-STARTPTS,"
                          % (float(recorte[0]), float(recorte[1])))
        partes[0] += "volume=%.3f" % float(capa.get("volumen", 1.0))
        if retardo > 0:
            #  `all=1` y no `delays=N|N`: con un valor por canal hay que saber
            #  cuántos canales trae el fichero, y un mp3 mono y un wav estéreo no
            #  traen los mismos. Con `all` se retrasan todos y da igual.
            partes.append("adelay=delays=%d:all=1" % retardo)
        #  `apad`: sin esto, la pista más corta manda en el `amix` y el vídeo se
        #  quedaría sin sonido a partir de donde se acabe la música.
        partes.append("apad")
        partes.append(NORMA_AUDIO)
        lineas.append(",".join(partes) + "[%s]" % et)
        etiquetas.append("[%s]" % et)

    #  `normalize=0` y `duration=first`: sin el primero, `amix` reparte el volumen
    #  entre las entradas y añadir música bajaría la voz sin que nadie lo pida; sin
    #  el segundo, el `apad` de arriba alargaría el vídeo hasta el infinito.
    lineas.append("%samix=inputs=%d:normalize=0:duration=first[amez]"
                  % ("".join(etiquetas), len(etiquetas)))
    return lineas


def ramas_censura(plan, entra):
    """Callar un tramo del sonido, o taparlo con un pitido.

    Va sobre la mezcla YA hecha, o sea lo último: si fuera antes, la música
    añadida seguiría sonando encima de lo que se quería tapar, que es justo lo
    contrario de censurar.

    Devuelve (líneas, etiqueta de salida). Si no hay nada que censurar devuelve
    la etiqueta que le dieron, sin tocar el grafo.
    """
    capas = [c for c in capas_de(plan, "censura")
             if float(c.get("t1", 0)) > float(c.get("t0", 0))]
    if not capas:
        return [], entra

    lineas = []
    #  Primero se callan todos los tramos. `volume=0` con `enable` es lo mismo
    #  que un silencio, y encadenar varios `volume` no cuesta nada.
    for n, capa in enumerate(capas):
        sale = "cen%d" % n
        lineas.append("[%s]volume=0:enable='between(t,%.4f,%.4f)'[%s]"
                      % (entra, float(capa["t0"]), float(capa["t1"]), sale))
        entra = sale

    #  Y encima, los pitidos de los que lo pidan. Un `sine` recortado a la
    #  ventana y retrasado hasta su sitio, sumado a lo que ya hay.
    pitidos = [c for c in capas if c.get("modo") == "pitido"]
    if not pitidos:
        return lineas, entra

    etiquetas = ["[%s]" % entra]
    for n, capa in enumerate(pitidos):
        t0, t1 = float(capa["t0"]), float(capa["t1"])
        et = "pit%d" % n
        partes = ["sine=f=1000:d=%.4f" % (t1 - t0)]
        retardo = max(0, int(round(t0 * 1000)))
        if retardo > 0:
            partes.append("adelay=delays=%d:all=1" % retardo)
        #  `volume`: un tono a tope tapa pero también taladra. A −12 dB se oye
        #  que hay algo censurado sin que haya que bajar el volumen del vídeo.
        partes.append("volume=0.25")
        partes.append("apad")
        partes.append(NORMA_AUDIO)
        lineas.append(",".join(partes) + "[%s]" % et)
        etiquetas.append("[%s]" % et)

    sale = "cenmix"
    lineas.append("%samix=inputs=%d:normalize=0:duration=first[%s]"
                  % ("".join(etiquetas), len(etiquetas), sale))
    return lineas, sale


# ── datos del vídeo ───────────────────────────────────────────────
def pistas_audio(video):
    """Las pistas de audio del vídeo, con su título si lo lleva.

    El título lo pone quien graba (`Sistema`, `Micrófono`), y sirve para que el
    editor no tenga que enseñar «pista 0» y «pista 1».
    """
    #  `stream_tags` entero y no solo `title`: el muxor de MP4 guarda lo que
    #  se le pasa como `title` bajo la clave `name`, así que pidiendo solo
    #  `title` no vuelve nada y las pistas salían sin nombre.
    p = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "a",
         "-show_entries", "stream=index:stream_tags",
         "-of", "json", video],
        capture_output=True, text=True)
    try:
        flujos = json.loads(p.stdout).get("streams", [])
    except json.JSONDecodeError:
        return []
    salida = []
    for i, f in enumerate(flujos):
        etiquetas = f.get("tags") or {}
        titulo = etiquetas.get("title") or etiquetas.get("name") or ""
        salida.append({"i": i, "titulo": titulo})
    return salida


def duracion_sonda(flujo, contenedor):
    """La duración que vale: la del flujo de vídeo, y si no la declara, la del
    contenedor.

    No son la misma cifra, y en una grabación casi nunca lo son: el audio
    sigue corriendo unas décimas después del último fotograma, y el contenedor
    dura lo que el flujo más largo. Un plan montado sobre la cifra del
    contenedor promete una línea que el render no puede cumplir —los últimos
    segundos del último trozo no tienen fotogramas detrás— y el fichero salía
    más corto que lo que enseñaba la línea de tiempo. Medido: 0,66 s de aire
    en una grabación de 8 s.

    Algunos formatos (webm, mkv) no declaran la duración por flujo y ffprobe
    contesta N/A o nada: entonces la del contenedor es lo único que hay.
    """
    try:
        return float(flujo)
    except (TypeError, ValueError):
        return float(contenedor)


def sondear(video):
    p = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0",
         "-show_entries", "stream=width,height,r_frame_rate,duration",
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
            float(num) / float(den),
            duracion_sonda(s.get("duration"), d["format"]["duration"]),
            hay_audio)


# ── el plan ───────────────────────────────────────────────────────
#
#  Un plan es la composición entera: de qué ficheros sale, qué trozos de cada
#  uno y en qué orden, y qué se le hace encima.
#
#  Hay DOS ejes de tiempo y conviene no confundirlos nunca. El *tiempo de línea*
#  es el del vídeo que va a salir; el *tiempo de fuente*, el de dentro de cada
#  fichero. `momentos` y `capas` van siempre en tiempo de línea. Quien traduce
#  entre los dos ejes es este fichero y nadie más: el QML nunca sabe en qué
#  segundo de qué fichero está mirando, y así no puede equivocarse.
VERSION = 3


#  Lo que ffmpeg va a abrir como imagen fija y no como vídeo.
#
#  La misma lista que `extensionesImagen` en services/Editor.qml. Se mira la
#  extensión y no el contenido porque hay que decidirlo antes de abrir nada.
EXT_IMAGEN = (".png", ".jpg", ".jpeg", ".webp", ".bmp", ".gif", ".avif")


def es_imagen(ruta):
    return str(ruta).lower().endswith(EXT_IMAGEN)


def describir_imagen(ruta, ident=1, dur=3.0):
    """Una imagen como fuente de la pista base: un vídeo de un solo fotograma.

    No tiene duración propia —una imagen dura lo que tú quieras— así que la trae
    puesta y el clip la recorta. Y no tiene pistas de audio: la rama de silencio
    que ya existe para los vídeos mudos se encarga.
    """
    ancho, alto = 1920, 1080
    p = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0",
         "-show_entries", "stream=width,height", "-of", "csv=p=0", ruta],
        capture_output=True, text=True)
    partes = p.stdout.strip().split(",")
    if len(partes) >= 2 and partes[0].isdigit() and partes[1].isdigit():
        ancho, alto = int(partes[0]), int(partes[1])
    return {"id": ident, "ruta": os.path.abspath(ruta), "rastro": "",
            "tipo": "imagen", "w": ancho, "h": alto, "fps": 30.0,
            "dur": round(dur, 3), "pistas": []}


def describir_fuente(ruta, rastro="", ident=1):
    if es_imagen(ruta):
        return describir_imagen(ruta, ident)
    ancho, alto, fps, dur, _ = sondear(ruta)
    # Rutas absolutas siempre: el plan se guarda y se reabre desde otro sitio,
    # y una ruta relativa dentro de él apunta a donde estuviera quien lo hizo.
    ruta = os.path.abspath(ruta)
    rastro = os.path.abspath(rastro) if rastro else ""
    return {"id": ident, "ruta": ruta, "rastro": rastro,
            "w": ancho, "h": alto, "fps": fps, "dur": round(dur, 3),
            # Una entrada por pista de audio, a volumen normal y sin silenciar.
            # Cuelgan de la fuente y no del plan porque cada fichero trae las
            # suyas y no tienen por qué coincidir.
            "pistas": [{"i": p["i"], "titulo": p["titulo"],
                        "volumen": 1.0, "mudo": False}
                       for p in pistas_audio(ruta)]}


def capa_camara(ruta, plan, desfase=0.0):
    """La cámara grabada a la vez, como un vídeo dentro del vídeo.

    Nace abajo a la derecha y a un cuarto de ancho, que es donde la pone todo el
    mundo, y cubriendo la grabación entera. A partir de ahí es una capa normal:
    se mueve, se escala, se recorta o se tira.

    `desfase` es lo que la pantalla se adelantó a la cámara: dos procesos no
    arrancan en el mismo milisegundo. Se descuenta del recorte para que el
    instante cero de la línea sea el mismo en las dos. Si aun así baila, el
    recorte se ajusta a mano — para eso está.
    """
    if not ruta or not os.path.exists(ruta):
        return None
    ancho, alto, _, dur, _ = sondear(ruta)
    if dur <= 0:
        return None
    largo = duracion_linea(plan) or dur
    d = max(0.0, float(desfase))
    return {"id": 1, "tipo": "video", "banda": 2,
            "ruta": os.path.abspath(ruta),
            "t0": 0.0, "t1": round(min(largo, dur - d), 3),
            "recorte": [round(d, 3), round(dur, 3)],
            "w": ancho, "h": alto,
            "x": 0.82, "y": 0.8, "escala": 0.25, "opacidad": 1.0}


def plan_nuevo(video, rastro="", momentos=None, camara="", desfase=0.0):
    f = describir_fuente(video, rastro)
    plan = {"version": VERSION,
            "w": f["w"], "h": f["h"], "fps": f["fps"],
            "fuentes": [f],
            # Un solo trozo, el vídeo entero. Trocearlo es cosa del editor.
            "clips": [{"id": 1, "fuente": 1, "desde": 0.0, "hasta": f["dur"]}],
            "momentos": momentos or [],
            "capas": [],
            "bandas": [],
            "marcadores": [],
            # Lo que se dice en el vídeo, cuando alguien lo pida. Va en el plan
            # para no tener que volver a transcribir al reabrir, que es lo caro.
            "transcripcion": []}

    #  Si se grabó la cámara a la vez, entra ya puesta.
    #
    #  No se busca por el nombre del fichero: quien grabó sabe si hubo cámara y
    #  cuánto se adelantó la pantalla, y adivinarlo por un `.cam.mp4` que ande
    #  cerca metería en el plan un vídeo que a lo mejor no es de esta toma.
    if camara:
        capa = capa_camara(camara, plan, desfase)
        if capa:
            plan["capas"] = [capa]
    return plan


def migrar(plan):
    """Un plan de los de antes al modelo de ahora."""
    if plan.get("version", 1) >= VERSION:
        return plan

    #  Del 2 al 3 solo cambia la numeración de las bandas: el resto del plan ya
    #  está en su sitio y rehacerlo perdería los cortes y las capas.
    if plan.get("version", 1) == 2:
        plan = subir_capas(plan)
        plan["version"] = VERSION
        return plan
    nuevo = plan_nuevo(plan["video"], plan.get("rastro", ""),
                       plan.get("momentos", []))
    #  Los volúmenes que ya se hubieran tocado se conservan: eran del vídeo y
    #  ahora son de la fuente, que es el mismo fichero llamado de otra forma.
    ajustes = {a["i"]: a for a in plan.get("audio", [])}
    for p in nuevo["fuentes"][0]["pistas"]:
        if p["i"] in ajustes:
            p["volumen"] = ajustes[p["i"]].get("volumen", 1.0)
            p["mudo"] = ajustes[p["i"]].get("mudo", False)
    return nuevo


def cargar(ruta):
    """El plan de un fichero, ya en el modelo de ahora.

    Si venía en el viejo se reescribe al vuelo: migrar cuesta dos ffprobe y no
    tiene ninguna gracia pagarlos en cada arrastre del ratón.
    """
    plan = json.load(open(ruta))
    if plan.get("version", 1) < VERSION:
        plan = migrar(plan)
        guardar(plan, ruta)
    return plan


def subir_capas(plan):
    """La banda 1 pasa a ser del vídeo, así que las capas suben una.

    Antes los trozos de vídeo tenían su propia fila y las capas empezaban en la
    banda 1. Ahora el vídeo ES la banda 1 y las capas van de la 2 para arriba,
    que es lo que hace que todo se apile por un solo camino en vez de tres.

    Es una renumeración y nada más: `capas_de()` ordena por banda, así que el
    grafo que sale es exactamente el mismo. Lo que cambia es dónde se dibuja
    cada fila.
    """
    for c in plan.get("capas", []):
        c["banda"] = max(2, int(c.get("banda", 1)) + 1)
    return plan


def guardar(plan, ruta):
    with open(ruta, "w") as f:
        json.dump(plan, f, ensure_ascii=False, indent=1)


def fuente_de(plan, ident):
    for f in plan["fuentes"]:
        if f["id"] == ident:
            return f
    return plan["fuentes"][0]


#  El mapa entre los dos ejes de tiempo. **La única traducción que hay.**
#
#  Los clips van en orden y pegados unos a otros: la línea es su suma, sin
#  huecos. Cada tramo dice desde qué segundo hasta qué segundo de la LÍNEA se
#  está viendo qué trozo de qué FICHERO.
#
#  Todo lo que necesite saber «qué se ve en el segundo 12» pasa por aquí, y por
#  eso no hay dos sitios que puedan discrepar sobre dónde cae un rótulo.
def velocidad_de(clip):
    """La velocidad de un clip, saneada.

    Se acota por arriba y por abajo a lo que sabe hacer el audio: `atempo`
    encadenado cubre de 0,25× a 4×, y más allá el sonido no es que suene mal, es
    que deja de ser reconocible. Un valor absurdo en el plan no debe tumbar el
    render.
    """
    try:
        v = float(clip.get("velocidad", 1.0) or 1.0)
    except (TypeError, ValueError):
        return 1.0
    return encaja(v, 0.25, 4.0)


def mapa(plan):
    """[(inicio, fin, clip, fuente)] en tiempo de línea.

    Aquí es donde entra la velocidad, y en ningún otro sitio: un trozo de 4
    segundos a 2× ocupa 2 segundos de línea. Como todo lo que quiere saber «qué
    se ve en el segundo 12» pregunta a este mapa, el zoom, los rótulos y las
    capas se recolocan solos al cambiar la velocidad de un clip.
    """
    t = 0.0
    tramos = []
    for c in plan.get("clips", []):
        d = max(0.0, c["hasta"] - c["desde"]) / velocidad_de(c)
        # Un clip de duración cero no es un clip, es el resto de un corte mal
        # hecho. Ni sale en la línea ni entra en el grafo, donde `trim` con
        # start == end deja una rama vacía que tumba el concat.
        if d <= 0:
            continue
        tramos.append((t, t + d, c, fuente_de(plan, c["fuente"])))
        t += d
    return tramos


def donde(tramos, t):
    """(fuente, segundo de esa fuente) en el instante t de la línea."""
    for a, b, c, f in tramos:
        if a <= t < b:
            # Multiplicar y no sumar: el segundo de línea vale `velocidad`
            # segundos de fichero. Es la vuelta exacta de lo que hace `mapa`.
            return f, c["desde"] + (t - a) * velocidad_de(c)
    if tramos:
        a, b, c, f = tramos[-1]
        return f, c["hasta"]
    return None, 0.0


def a_lienzo(fuente, x, y, ancho, alto):
    """De píxeles de un fichero a píxeles del lienzo de salida.

    Cada clip entra en el lienzo escalado sin deformar y con banda negra
    alrededor, que es lo que hace la normalización antes del `concat`. El rastro
    del cursor va en píxeles de SU fichero, así que hay que llevarlo por el
    mismo camino: sin esto, el zoom de un clip de otra resolución apuntaría a
    un sitio que no es.
    """
    w, h = float(fuente["w"]), float(fuente["h"])
    e = min(ancho / w, alto / h)
    return (ancho - w * e) / 2 + x * e, (alto - h * e) / 2 + y * e


def duracion_linea(plan):
    tramos = mapa(plan)
    return tramos[-1][1] if tramos else 0.0


def pistas_de(plan):
    if not plan["clips"]:
        return []
    return fuente_de(plan, plan["clips"][0]["fuente"]).get("pistas", [])


# ── órdenes ───────────────────────────────────────────────────────
def orden_abrir(args):
    """Un plan para un vídeo cualquiera, se haya grabado aquí o no.

    Si ya había uno guardado se abre ese. Es lo que hace que «se puede reeditar
    mañana» sea verdad: sin esto, volver a abrir el mismo vídeo rehacía el plan
    de cero y se llevaba por delante los cortes y los zooms de la última vez, sin
    avisar y sin forma de recuperarlos.
    """
    if not os.path.exists(args.video):
        salir(ok=False, motivo="sin-video")
    if args.guardar and os.path.exists(args.guardar):
        plan = cargar(args.guardar)
        salir(ok=True, **plan)
    plan = plan_nuevo(args.video, args.rastro, camara=args.camara,
                      desfase=args.desfase)
    if args.guardar:
        guardar(plan, args.guardar)
    salir(ok=True, **plan)


def orden_proponer(args):
    if not os.path.exists(args.rastro):
        salir(ok=False, motivo="sin-rastro")
    ancho, alto, fps, duracion, _ = sondear(args.video)
    momentos = proponer(args.rastro, ancho, alto, duracion, args.nivel)
    plan = plan_nuevo(args.video, args.rastro, momentos,
                      camara=args.camara, desfase=args.desfase)
    if args.guardar:
        guardar(plan, args.guardar)
    salir(ok=True, **plan)


def orden_medir(args):
    """Cuánto dura un fichero de audio.

    Hace falta para que la capa sepa qué tramo ocupa en la línea antes de que
    nadie la haya escuchado: un bloque de duración inventada se arrastra mal y
    engaña sobre cuándo se acaba la música.
    """
    if not os.path.exists(args.fichero):
        salir(ok=False, motivo="no-existe")
    p = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0",
         "-show_entries", "stream=width,height,duration",
         "-show_entries", "format=duration", "-of", "json", args.fichero],
        capture_output=True, text=True)
    try:
        d = json.loads(p.stdout)
        dur = round(float(d["format"]["duration"]), 3)
    except (json.JSONDecodeError, KeyError, TypeError, ValueError):
        salir(ok=False, motivo="ilegible")

    #  Y el tamaño, si lleva vídeo. Lo necesita el editor para dibujar la capa con
    #  su proporción: `scale=…:-1` la conserva al renderizar, y si la previa la
    #  inventara enseñaría un recuadro que no es el que va a salir.
    #
    #  Con vídeo, la duración buena es la de SU flujo, por lo mismo que en
    #  `sondear`: un PIP prometido más largo que sus fotogramas se queda
    #  congelado al final. Para un audio, la del contenedor es la que hay.
    flujos = d.get("streams") or []
    if flujos and flujos[0].get("width"):
        s = flujos[0]
        dur = round(duracion_sonda(s.get("duration"), dur), 3)
        salir(ok=True, dur=dur, w=int(s["width"]), h=int(s["height"]))
    salir(ok=True, dur=dur)


def orden_camara(args):
    """La trayectoria de la cámara, para previsualizarla sin renderizar.

    Sale la MISMA lista de puntos que se convierte en la expresión de ffmpeg, y
    entre ellos se interpola en línea recta igual que hace el filtro. Por eso lo
    que se ve en el editor y lo que acaba en el fichero coinciden por
    construcción, sin dos implementaciones que se puedan ir separando.
    """
    plan = cargar(args.plan)
    tramos = mapa(plan)
    duracion = tramos[-1][1] if tramos else 0.0
    puntos = adelgazar(trayectoria(plan))
    #  Los clics salen por aquí y no con el plan a propósito: hay que leer el
    #  rastro y pasarlo por el mapa, así que cambian con cada corte igual que la
    #  trayectoria. Recalcularlos juntos es recalcularlos cuando toca.
    salir(ok=True, w=plan["w"], h=plan["h"], duracion=round(duracion, 3),
          audio=pistas_de(plan), fuentes=plan["fuentes"], clips=plan["clips"],
          camara=[[round(t, 3), round(z, 4), round(x, 1), round(y, 1)]
                  for t, z, x, y in puntos],
          clics=[[round(t, 3), round(x, 1), round(y, 1)]
                 for t, x, y in clics_de(plan)])


def escribir_grafo(plan, ruta_plan, sin_audio=False, nombre="grafo.txt"):
    """El grafo a un fichero, y la ruta del fichero.

    `-filter_complex_script` y no `-filter_complex` a secas: el límite no es
    `ARG_MAX` sino `MAX_ARG_STRLEN`, **128 KB por argumento suelto**, y con unos
    cientos de tramos en la expresión de la cámara eso se alcanza. Falla con un
    «Argument list too long» que no dice nada de lo que pasa de verdad.

    De regalo, el grafo se queda en disco: cuando un render falle, ahí está lo
    que se le pidió a ffmpeg, tal cual.
    """
    #  El plan es `<vídeo>.k4.json` y su carpeta adjunta es `<vídeo>.k4/`, así
    #  que solo hay que quitarle el `.json`. Con `splitext` + ".k4" salía
    #  `<vídeo>.k4.k4`, que funcionaba pero era un sitio que nadie esperaba.
    carpeta = carpeta_de(ruta_plan)
    os.makedirs(carpeta, exist_ok=True)
    texto, nodos = grafo(plan, sin_audio, carpeta)
    ruta = os.path.join(carpeta, nombre)
    with open(ruta, "w") as f:
        f.write(texto)
    return ruta, nodos


def orden_render(args):
    plan = cargar(args.plan)
    duracion = duracion_linea(plan)
    rutas, _, _, _ = entradas(plan, carpeta_de(args.plan))
    ruta_grafo, nodos = escribir_grafo(plan, args.plan)

    formato = getattr(args, "formato", "mp4") or "mp4"

    #  El GIF no lleva audio y necesita su propia paleta.
    #
    #  Sin `palettegen`/`paletteuse` un GIF sale con los 216 colores de web y
    #  cualquier degradado se convierte en bandas. Y se limita a 15 fps y 960 px
    #  de ancho: un GIF de un minuto a 60 fps y 1080p son cientos de megas, o
    #  sea un fichero que no se puede mandar a ningún sitio, que es justo para
    #  lo que se hace un GIF.
    if formato == "gif":
        with open(ruta_grafo) as f:
            texto = f.read()
        texto += (";\n[a]anullsink;\n"
                  "[v]fps=15,scale=min(960\\,iw):-2:flags=lanczos,split[gp][gq];\n"
                  "[gp]palettegen=stats_mode=diff[pal];\n"
                  "[gq][pal]paletteuse=dither=bayer:bayer_scale=3"
                  ":diff_mode=rectangle[gif]")
        with open(ruta_grafo, "w") as f:
            f.write(texto)
        orden = (["ffmpeg", "-v", "error", "-y"] + abrir_entradas(plan, rutas)
                 + ["-filter_complex_script", ruta_grafo, "-map", "[gif]",
                    "-loop", "0",
                    "-progress", "pipe:1", "-nostats", args.salida])
    elif formato == "webm":
        orden = (["ffmpeg", "-v", "error", "-y"] + abrir_entradas(plan, rutas)
                 + ["-filter_complex_script", ruta_grafo,
                    "-map", "[v]", "-map", "[a]",
                    #  `row-mt` y `-cpu-used 4`: vp9 sin eso tarda tanto que
                    #  nadie espera a que acabe. La calidad se nota poco.
                    "-c:v", "libvpx-vp9", "-crf", "32", "-b:v", "0",
                    "-row-mt", "1", "-cpu-used", "4",
                    "-c:a", "libopus", "-b:a", "128k",
                    "-progress", "pipe:1", "-nostats", args.salida])
    else:
        orden = ["ffmpeg", "-v", "error", "-y"] + abrir_entradas(plan, rutas)
        orden += ["-filter_complex_script", ruta_grafo,
                  "-map", "[v]", "-map", "[a]",
                  "-c:v", "hevc_nvenc" if args.codec == "hevc" else "h264_nvenc",
                  "-preset", "p5", "-rc", "vbr", "-cq", "21", "-b:v", "0",
                  #  Ya no hay atajo de `-c:a copy`: con varios trozos el audio
                  #  pasa por el grafo sí o sí, porque hay que recortarlo y pegarlo.
                  "-c:a", "aac", "-b:a", "192k",
                  "-progress", "pipe:1", "-nostats", args.salida]

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


def sacar_fotograma(plan, ruta_plan, t, destino):
    """Un fotograma de la LÍNEA a un PNG. True si salió."""
    carpeta = carpeta_de(ruta_plan)
    rutas, _, _, _ = entradas(plan, carpeta)
    ruta_grafo, _ = escribir_grafo(plan, ruta_plan, sin_audio=True,
                                   nombre="grafo-congelar.txt")
    orden = (["ffmpeg", "-v", "error", "-y"] + abrir_entradas(plan, rutas)
             + ["-filter_complex_script", ruta_grafo, "-map", "[v]",
                "-ss", "%.4f" % t, "-frames:v", "1", destino])
    p = subprocess.run(orden, capture_output=True, text=True)
    return p.returncode == 0 and os.path.exists(destino)


def orden_congelar(args):
    """Parar la imagen unos segundos sin parar de hablar.

    Se saca el fotograma que hay bajo el cabezal, se da de alta como fuente
    —una imagen es una fuente más desde que existen los clips de imagen— y se
    parte el trozo en ese punto para meterla en medio.

    El hueco no trae audio, y eso es lo que se quiere: el sonido de debajo sigue
    porque el resto de la línea no se ha movido, solo se ha metido algo delante.
    Quien lo rellena es la rama de silencio que ya existe para los vídeos mudos.
    """
    plan = cargar(args.plan)
    tramos = mapa(plan)
    if not tramos:
        salir(ok=False, motivo="sin-clips")
    total = tramos[-1][1]
    t = encaja(float(args.t), 0.0, max(0.0, total - 0.02))

    carpeta = carpeta_de(args.plan)
    os.makedirs(carpeta, exist_ok=True)
    ident = max([f["id"] for f in plan["fuentes"]] or [0]) + 1
    destino = os.path.join(carpeta, "congelado-%d.png" % ident)
    if not sacar_fotograma(plan, args.plan, t, destino):
        salir(ok=False, motivo="sin-fotograma")

    #  El corte, en el mismo sitio que lo haría `cortar` en la interfaz.
    corte = None
    for a, b, clip, fuente in tramos:
        if a <= t < b:
            corte = (a, clip, velocidad_de(clip))
    if corte is None:
        salir(ok=False, motivo="fuera")
    a, clip, v = corte
    en_fuente = clip["desde"] + (t - a) * v

    plan["fuentes"].append(describir_imagen(destino, ident, float(args.dur)))

    nuevo_id = max([c["id"] for c in plan["clips"]] or [0]) + 1
    i = plan["clips"].index(clip)
    congelado = {"id": nuevo_id + 1, "fuente": ident,
                 "desde": 0.0, "hasta": float(args.dur)}

    #  Si el corte cae en un borde no se parte nada: la imagen se mete delante o
    #  detrás y ya. Partir en «todo» y «nada» dejaría un trozo de duración cero.
    if en_fuente - clip["desde"] < 0.02:
        plan["clips"].insert(i, congelado)
    elif clip["hasta"] - en_fuente < 0.02:
        plan["clips"].insert(i + 1, congelado)
    else:
        izq = dict(clip, hasta=en_fuente)
        der = dict(clip, id=nuevo_id, desde=en_fuente)
        plan["clips"][i:i + 1] = [izq, congelado, der]

    guardar(plan, args.plan)
    salir(ok=True, fuente=ident, clip=congelado["id"], ruta=destino)


def orden_silencios(args):
    """Dónde no se dice nada, en tiempo de línea.

    Se le pasa a ffmpeg el MISMO grafo que al render y se escucha su salida de
    audio con `silencedetect`. Hacerlo sobre la mezcla final y no fichero a
    fichero es lo que hace que los cortes salgan ya en tiempo de línea, sin
    traducir nada: si has bajado el volumen de una pista o has metido música,
    eso cuenta.

    No corta nada: devuelve los tramos y quien decide es el usuario. Sin un
    deshacer, borrar trozos por su cuenta sería jugársela con su grabación.
    """
    plan = cargar(args.plan)
    carpeta = carpeta_de(args.plan)
    rutas, _, _, _ = entradas(plan, carpeta)

    #  El detector va DENTRO del grafo y no como `-af`: ffmpeg no deja mezclar
    #  filtrado simple y complejo sobre el mismo flujo, y contesta «Simple and
    #  complex filtering cannot be used together for the same stream».
    #  Y el vídeo a la basura: en un grafo TODA etiqueta que se produce hay que
    #  consumirla. Dejar `[v]` suelta no es «no me interesa el vídeo», es un
    #  «Filter has output unconnected» que tumba la orden. Es la misma trampa
    #  que ya se pagó con `[a]` en la previa.
    texto, _ = grafo(plan, carpeta=carpeta)
    texto += (";\n[v]nullsink;\n[a]silencedetect=noise=%ddB:d=%.3f[adet]"
              % (args.umbral, args.minimo))
    ruta_grafo = os.path.join(carpeta, "grafo-silencios.txt")
    with open(ruta_grafo, "w") as f:
        f.write(texto)

    orden = ["ffmpeg", "-hide_banner", "-y"] + abrir_entradas(plan, rutas)
    #  Solo el audio: descodificar el vídeo para tirarlo es tiempo regalado, y
    #  aquí se está esperando a que conteste para poder cortar.
    orden += ["-filter_complex_script", ruta_grafo, "-map", "[adet]",
              "-vn", "-f", "null", "-"]

    p = subprocess.run(orden, capture_output=True, text=True)
    if p.returncode != 0:
        salir(ok=False, motivo="fallo", detalle=p.stderr.strip()[-200:])

    #  `silencedetect` no devuelve datos: los escribe en el registro, una línea
    #  por borde. El final del último puede faltar si el vídeo acaba callado, y
    #  entonces el tramo llega hasta el final de la línea.
    total = duracion_linea(plan)
    tramos, abierto = [], None
    for linea in p.stderr.split("\n"):
        m = re.search(r"silence_start:\s*(-?[\d.]+)", linea)
        if m:
            abierto = max(0.0, float(m.group(1)))
            continue
        m = re.search(r"silence_end:\s*(-?[\d.]+)", linea)
        if m and abierto is not None:
            tramos.append([round(abierto, 3),
                           round(min(total, float(m.group(1))), 3)])
            abierto = None
    if abierto is not None and total - abierto > args.minimo:
        tramos.append([round(abierto, 3), round(total, 3)])

    salir(ok=True, duracion=round(total, 3), tramos=tramos)


def orden_previa(args):
    plan = cargar(args.plan)
    rutas, _, _, _ = entradas(plan, carpeta_de(args.plan))
    ruta_grafo, _ = escribir_grafo(plan, args.plan, sin_audio=True,
                                   nombre="grafo-previa.txt")

    orden = ["ffmpeg", "-v", "error", "-y"] + abrir_entradas(plan, rutas)
    # `-ss` como opción de SALIDA, después del grafo. Delante del `-i` ffmpeg
    # pone los tiempos a cero y todas las expresiones, que van en tiempo de
    # línea, apuntarían al sitio equivocado.
    orden += ["-filter_complex_script", ruta_grafo, "-map", "[v]",
              "-ss", str(args.t), "-frames:v", "1", args.salida]

    p = subprocess.run(orden, capture_output=True, text=True)
    if p.returncode != 0:
        salir(ok=False, motivo="fallo", detalle=p.stderr.strip()[:200])
    salir(ok=True, ruta=args.salida)


def main():
    ap = argparse.ArgumentParser(add_help=False)
    sub = ap.add_subparsers(dest="orden", required=True)

    e = sub.add_parser("abrir")
    e.add_argument("video")
    e.add_argument("--rastro", default="")
    e.add_argument("--guardar", default="")
    e.add_argument("--camara", default="")
    e.add_argument("--desfase", type=float, default=0.0)

    a = sub.add_parser("proponer")
    a.add_argument("rastro")
    a.add_argument("--video", required=True)
    a.add_argument("--guardar", default="")
    a.add_argument("--nivel", type=float, default=Z_MAX)
    a.add_argument("--camara", default="")
    a.add_argument("--desfase", type=float, default=0.0)

    #  El vídeo ya no va suelto: sale del plan.
    #
    #  Pasarlo por separado permitía renderizar un plan sobre un vídeo que no
    #  era el suyo, y con varias fuentes deja directamente de tener sentido.
    b = sub.add_parser("render")
    b.add_argument("plan")
    b.add_argument("salida")
    b.add_argument("--codec", default="h264")
    b.add_argument("--formato", default="mp4",
                   choices=["mp4", "webm", "gif"])

    d = sub.add_parser("camara")
    d.add_argument("plan")

    n = sub.add_parser("congelar")
    n.add_argument("plan")
    n.add_argument("t", type=float)
    n.add_argument("--dur", type=float, default=2.0)

    z = sub.add_parser("silencios")
    z.add_argument("plan")
    #  −35 dB y 0,6 s: medido sobre una locución normal, con −50 se cuela el
    #  ruido de sala y con 0,3 s parte entre palabras.
    z.add_argument("--umbral", type=int, default=-35)
    z.add_argument("--minimo", type=float, default=0.6)

    m = sub.add_parser("medir")
    m.add_argument("fichero")

    c = sub.add_parser("previa")
    c.add_argument("plan")
    c.add_argument("t", type=float)
    c.add_argument("salida")

    args = ap.parse_args()
    {"abrir": orden_abrir, "proponer": orden_proponer, "render": orden_render,
     "previa": orden_previa, "camara": orden_camara,
     "silencios": orden_silencios, "congelar": orden_congelar,
     "medir": orden_medir}[args.orden](args)


if __name__ == "__main__":
    try:
        main()
    except (KeyboardInterrupt, BrokenPipeError):
        sys.exit(0)
