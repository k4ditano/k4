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
import argparse, json, math, os, subprocess, sys, tempfile

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

    Cada capa pertenece a una **banda**, y las bandas son lo que se apila: la 1
    es la de abajo y la última la de arriba. Dentro de una banda pueden convivir
    varias capas —lo normal es que no se pisen en el tiempo—, y ahí manda el
    orden de la lista.

    Al principio una capa ERA una banda, una cosa suelta con su fila propia. Se
    quedó corto por los dos lados: no había nada que mover de una banda a otra
    —que es lo primero que uno intenta— y con seis imágenes salían seis filas
    cuando lo natural son dos bandas con tres cada una.

    El orden se saca con `sorted`, que en python es estable: dentro de la misma
    banda se conserva el orden de la lista. No hace falta más.
    """
    capas = [c for c in plan.get("capas", [])
             if tipo is None or c.get("tipo") == tipo]
    return sorted(capas, key=lambda c: c.get("banda", 1))


def entradas(plan):
    """Los ficheros que hay que abrir, y en qué orden se los pasamos a ffmpeg.

    Un fichero se abre UNA vez aunque aparezca en seis clips o en tres capas:
    referenciar `[0:v]` varias veces es legal y ffmpeg mete el `split` por su
    cuenta. Devuelve las rutas y, para cada fuente y cada capa, qué entrada le
    toca.
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
    return rutas, de_fuente, de_capa


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


def rama_audio(i, idx, clip, fuente, dur):
    """La rama de audio de un clip, ya mezclada y a volumen.

    Devuelve las líneas del grafo. Las pistas mudas no entran; si no queda
    ninguna —o la fuente no tiene audio— se rellena con silencio, porque a
    `concat` hay que darle todas las ramas o no arranca.
    """
    vivas = [p for p in fuente.get("pistas", []) if not p.get("mudo")]

    if not vivas:
        #  Silencio del mismo largo que el trozo. Sin esto, un clip sacado de un
        #  vídeo mudo tumba el `concat` entero, y con él todo el render.
        #  `dur` ya viene en tiempo de línea, o sea con la velocidad aplicada.
        return ["anullsrc=r=48000:cl=stereo,atrim=0:%.4f,asetpts=PTS-STARTPTS[a%d]"
                % (dur, i)]

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
            "volume=%.3f,%s%s[%s]"
            % (idx, p["i"], clip["desde"], clip["hasta"],
               float(p.get("volumen", 1.0)), tempo, NORMA_AUDIO, et))
        etiquetas.append("[%s]" % et)

    if una:
        return lineas

    #  `normalize=0`: sin esto amix baja el volumen de todas al sumarlas, y
    #  subir una acabaría bajando la otra sin que nadie lo haya pedido.
    lineas.append("%samix=inputs=%d:normalize=0[a%d]"
                  % ("".join(etiquetas), len(etiquetas), i))
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
              "fontsize=%d" % tam,
              "fontcolor=%s" % color_ffmpeg(capa.get("color", "#ffffff")),
              #  Centrado en (x, y) como las demás capas: `text_w` y `text_h` son
              #  lo que mide el rótulo ya compuesto.
              "x=%.4f*w-text_w/2" % float(capa.get("x", 0.5)),
              "y=%.4f*h-text_h/2" % float(capa.get("y", 0.85)),
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

    recorte = capa.get("recorte") or [0, 0]
    filtros = []
    if float(recorte[1]) > float(recorte[0]):
        filtros.append("trim=start=%.4f:end=%.4f"
                       % (float(recorte[0]), float(recorte[1])))
    #  `setpts` SIEMPRE, aunque no haya recorte: pone los tiempos del clip a cero
    #  y luego lo empuja hasta su instante.
    filtros.append("setpts=PTS-STARTPTS+%.4f/TB" % float(capa.get("t0", 0)))
    filtros.append("scale=%d:-1" % ancho_capa)
    filtros.append("setsar=1")

    opacidad = float(capa.get("opacidad", 1.0))
    if opacidad < 0.999:
        filtros.append("format=rgba,colorchannelmixer=aa=%.3f" % opacidad)

    lineas.append("[%d:v]%s[%s]" % (idx, ",".join(filtros), et))

    sale = "ov%d" % n
    lineas.append(
        "[%s][%s]overlay=x=%.4f*W-w/2:y=%.4f*H-h/2:"
        "enable='between(t,%.4f,%.4f)':eof_action=pass[%s]"
        % (entra, et, float(capa.get("x", 0.75)), float(capa.get("y", 0.75)),
           float(capa.get("t0", 0)), float(capa.get("t1", 0)), sale))
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

    filtros = ["scale=%d:-1" % ancho_capa]
    opacidad = float(capa.get("opacidad", 1.0))
    if opacidad < 0.999:
        #  El alfa hay que tenerlo antes de poder tocarlo: un JPEG llega sin
        #  canal alfa y `colorchannelmixer=aa=` no haría nada, sin quejarse.
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
    lineas.append(
        "[%s][%s]overlay=x=%.4f*W-w/2:y=%.4f*H-h/2:"
        "enable='between(t,%.4f,%.4f)'[%s]"
        % (entra, et, float(capa.get("x", 0.5)), float(capa.get("y", 0.5)),
           float(capa.get("t0", 0.0)), float(capa.get("t1", 0.0)), sale))
    return lineas, sale


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
    _, idx_de, idx_capa = entradas(plan)
    norma = norma_video(ancho, alto, fps)
    if carpeta is None:
        carpeta = tempfile.mkdtemp(prefix="k4-grafo-")
    os.makedirs(carpeta, exist_ok=True)

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
        lineas.append(
            "[%d:v]trim=start=%.4f:end=%.4f,%s,%s[v%d]"
            % (idx, clip["desde"], clip["hasta"], pts, norma, i))
        lineas += rama_audio(i, idx, clip, fuente, b - a)

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

    # ── 4. las capas, después del zoom para que no se amplíen con él
    entra = "zoom"
    for n, capa in enumerate(capas_de(plan)):
        tipo = capa.get("tipo")
        if tipo == "texto":
            nuevas, entra = rama_texto(n, capa, ancho, alto, carpeta, entra)
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

    # ── 5. el audio añadido, encima de lo que ya suena
    lineas += ramas_audio_extra(plan, idx_capa, sin_audio)

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
        return ["[mez]anull[a]"]

    lineas, etiquetas = [], ["[mez]"]
    for k, capa in enumerate(extras):
        et = "ax%d" % k
        retardo = max(0, int(round(float(capa.get("t0", 0)) * 1000)))
        partes = ["[%d:a]volume=%.3f"
                  % (idx_capa[capa["id"]], float(capa.get("volumen", 1.0)))]
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
    lineas.append("%samix=inputs=%d:normalize=0:duration=first[a]"
                  % ("".join(etiquetas), len(etiquetas)))
    return lineas


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
VERSION = 2


def describir_fuente(ruta, rastro="", ident=1):
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


def plan_nuevo(video, rastro="", momentos=None):
    f = describir_fuente(video, rastro)
    return {"version": VERSION,
            "w": f["w"], "h": f["h"], "fps": f["fps"],
            "fuentes": [f],
            # Un solo trozo, el vídeo entero. Trocearlo es cosa del editor.
            "clips": [{"id": 1, "fuente": 1, "desde": 0.0, "hasta": f["dur"]}],
            "momentos": momentos or [],
            "capas": [],
            # Lo que se dice en el vídeo, cuando alguien lo pida. Va en el plan
            # para no tener que volver a transcribir al reabrir, que es lo caro.
            "transcripcion": []}


def migrar(plan):
    """Un plan de los de antes —un vídeo y sus momentos— al modelo de ahora."""
    if plan.get("version", 1) >= VERSION:
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
    plan = plan_nuevo(args.video, args.rastro)
    if args.guardar:
        guardar(plan, args.guardar)
    salir(ok=True, **plan)


def orden_proponer(args):
    if not os.path.exists(args.rastro):
        salir(ok=False, motivo="sin-rastro")
    ancho, alto, fps, duracion, _ = sondear(args.video)
    momentos = proponer(args.rastro, ancho, alto, duracion, args.nivel)
    plan = plan_nuevo(args.video, args.rastro, momentos)
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
        ["ffprobe", "-v", "error", "-show_entries", "format=duration",
         "-of", "csv=p=0", args.fichero], capture_output=True, text=True)
    try:
        dur = round(float(p.stdout.strip()), 3)
    except ValueError:
        salir(ok=False, motivo="ilegible")

    #  Y el tamaño, si lleva vídeo. Lo necesita el editor para dibujar la capa con
    #  su proporción: `scale=…:-1` la conserva al renderizar, y si la previa la
    #  inventara enseñaría un recuadro que no es el que va a salir.
    q = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0",
         "-show_entries", "stream=width,height", "-of", "csv=p=0",
         args.fichero], capture_output=True, text=True)
    partes = q.stdout.strip().split(",")
    if len(partes) == 2 and partes[0].isdigit():
        salir(ok=True, dur=dur, w=int(partes[0]), h=int(partes[1]))
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
    salir(ok=True, w=plan["w"], h=plan["h"], duracion=round(duracion, 3),
          audio=pistas_de(plan), fuentes=plan["fuentes"], clips=plan["clips"],
          camara=[[round(t, 3), round(z, 4), round(x, 1), round(y, 1)]
                  for t, z, x, y in puntos])


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
    carpeta = ruta_plan[:-5] if ruta_plan.endswith(".json") else ruta_plan + ".k4"
    os.makedirs(carpeta, exist_ok=True)
    texto, nodos = grafo(plan, sin_audio, carpeta)
    ruta = os.path.join(carpeta, nombre)
    with open(ruta, "w") as f:
        f.write(texto)
    return ruta, nodos


def orden_render(args):
    plan = cargar(args.plan)
    duracion = duracion_linea(plan)
    rutas, _, _ = entradas(plan)
    ruta_grafo, nodos = escribir_grafo(plan, args.plan)

    orden = ["ffmpeg", "-v", "error", "-y"]
    for r in rutas:
        orden += ["-i", r]
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


def orden_previa(args):
    plan = cargar(args.plan)
    rutas, _, _ = entradas(plan)
    ruta_grafo, _ = escribir_grafo(plan, args.plan, sin_audio=True,
                                   nombre="grafo-previa.txt")

    orden = ["ffmpeg", "-v", "error", "-y"]
    for r in rutas:
        orden += ["-i", r]
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

    a = sub.add_parser("proponer")
    a.add_argument("rastro")
    a.add_argument("--video", required=True)
    a.add_argument("--guardar", default="")
    a.add_argument("--nivel", type=float, default=Z_MAX)

    #  El vídeo ya no va suelto: sale del plan.
    #
    #  Pasarlo por separado permitía renderizar un plan sobre un vídeo que no
    #  era el suyo, y con varias fuentes deja directamente de tener sentido.
    b = sub.add_parser("render")
    b.add_argument("plan")
    b.add_argument("salida")
    b.add_argument("--codec", default="h264")

    d = sub.add_parser("camara")
    d.add_argument("plan")

    m = sub.add_parser("medir")
    m.add_argument("fichero")

    c = sub.add_parser("previa")
    c.add_argument("plan")
    c.add_argument("t", type=float)
    c.add_argument("salida")

    args = ap.parse_args()
    {"abrir": orden_abrir, "proponer": orden_proponer, "render": orden_render,
     "previa": orden_previa, "camara": orden_camara,
     "medir": orden_medir}[args.orden](args)


if __name__ == "__main__":
    try:
        main()
    except (KeyboardInterrupt, BrokenPipeError):
        sys.exit(0)
