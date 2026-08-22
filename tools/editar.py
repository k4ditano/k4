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

#  Ni ffmpeg ni ffprobe salen a la red. Nunca.
#
#  Un proyecto es un JSON con rutas dentro, y un `.k4v` puede llegarte de otra
#  persona igual que llega un fichero cualquiera. Sin esto, una «ruta» que en
#  realidad sea `http://…` hace que tu máquina se la pida: comprobado contra un
#  servidor local, que registró el `GET` con el user-agent de libavformat.
#
#  Va aquí y no en un `if` porque un `if` se olvida en la llamada diecisiete.
#  Esto lo corta ffmpeg mismo: «Protocol 'http' not on whitelist» y ni un
#  paquete. `crypto` y `data` se quedan porque son locales y algún contenedor
#  legítimo los usa.
SIN_RED = ["-protocol_whitelist", "file,crypto,data"]


#  ── de dónde puede salir un fichero, y dónde puede caer ──────────────
#
#  Un proyecto es un JSON con rutas dentro y puede venir de cualquiera. Lo que
#  sigue son las dos preguntas que hay que hacerle a una ruta que no has escrito
#  tú: ¿es un fichero de esta máquina?, ¿y va a caer donde debe?
#
#  `SIN_RED` ya impide que ffmpeg salga a la red, así que esto es la segunda
#  capa. Existe igualmente por dos razones: dice POR QUÉ se para —«ok: true» con
#  la lista vacía parece que el fichero no tenía audio, y eso engaña— y protege
#  de protocolos que no van por la red pero tampoco son ficheros.

#  Los motivos van como CÓDIGO, no como frase. La frase la escribe la barra,
#  que es quien sabe en qué idioma está el usuario: con la prosa aquí dentro,
#  una barra en inglés enseñaba el título traducido y el motivo en español
#  debajo. El dato —la ruta, el protocolo— va aparte, en `detalle`.
#
#  Para quien lee el JSON a mano no se pierde nada: `{"motivo": "no-es-local",
#  "detalle": "http://…"}` dice lo mismo y encima se puede comparar.

def es_local(ruta):
    """¿Es una ruta de fichero y no otra cosa disfrazada?"""
    r = str(ruta or "")
    if not r:
        return False
    #  `http://`, `data:`, `concat:`, `pipe:`, `subfile,…` … cualquier cosa con
    #  esquema delante. Una ruta normal no lleva dos puntos antes de la primera
    #  barra.
    if re.match(r"^[A-Za-z][A-Za-z0-9+.\-]*://", r):
        return False
    cabeza = r.split("/")[0]
    if ":" in cabeza:
        return False
    return True


def exigir_local(ruta, que="fichero"):
    """La ruta, o se sale diciendo qué pasa."""
    if not es_local(ruta):
        salir(ok=False, motivo="no-es-local", que=que, detalle=str(ruta))
    if not os.path.exists(ruta):
        salir(ok=False, motivo="no-existe", que=que, detalle=str(ruta))
    return ruta


def dentro_de(base, ruta):
    """¿`ruta` cae dentro de `base`, resueltos los `..` y los enlaces?"""
    b = os.path.realpath(base)
    r = os.path.realpath(ruta)
    return r == b or r.startswith(b + os.sep)


def exigir_dentro(base, ruta, que="salida"):
    if not dentro_de(base, ruta):
        salir(ok=False, motivo="fuera-de-carpeta", que=que, detalle=str(ruta))
    return ruta


#  Un sondeo que no vuelve deja al editor esperando para siempre. Veinte
#  segundos es holgadísimo para leer una cabecera —lo normal son décimas— y
#  corto para un cuelgue. Los RENDERS no llevan tiempo: pueden durar minutos y
#  cortarlos sería romper trabajo bueno.
ESPERA_SONDEO = 20


def correr_sondeo(orden, **kw):
    """`subprocess.run` con reloj, para lo que debe tardar poco."""
    kw.setdefault("capture_output", True)
    kw.setdefault("text", True)
    try:
        return subprocess.run(orden, timeout=ESPERA_SONDEO, **kw)
    except subprocess.TimeoutExpired:
        salir(ok=False, motivo="no-responde",
              detalle=(orden[-1] if orden else ""))


#  La escoba: quitar el ruido de fondo, en UN solo sitio.
#
#  La usan tres caminos —las pistas del vídeo, las capas de audio, y la copia
#  limpia que oye la previa— y tienen que ser exactamente el mismo filtro, o la
#  previa mentiría sobre lo que va a salir del render. Un número repetido en
#  tres sitios se separa solo en cuanto alguien toca uno.
#
#  `nr=12` quita el aire sin comerse la voz; `nf=-25` es el suelo de ruido que
#  se le supone. Medido sobre un render: el siseo baja 5,1 dB y la voz 0,6.
FILTRO_ESCOBA = "afftdn=nr=12:nf=-25"


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

    #  Las formas no traen fichero: se dibujan aquí y su PNG entra como una
    #  imagen más. Sin carpeta no hay dónde dibujar, y la capa se salta.
    if carpeta:
        for c in capas_de(plan, "forma"):
            ruta = dibujar_forma(carpeta, c)
            if ruta:
                de_capa[c["id"]] = apuntar(ruta)

    idx_anillo = -1
    if carpeta and plan.get("clics", {}).get("activo"):
        anillo = dibujar_anillo(carpeta, plan)
        if anillo:
            idx_anillo = apuntar(anillo)
    return rutas, de_fuente, de_capa, idx_anillo


def carpeta_de(ruta_plan):
    """La carpeta adjunta de un plan: `<vídeo>.k4/` para `<vídeo>.k4v`.

    Se sigue entendiendo el nombre viejo —`<vídeo>.k4.json`— porque los
    proyectos de antes existen y se abren igual; quitarle el `.json` da la
    misma carpeta, así que los dos nombres apuntan al mismo sitio.
    """
    if ruta_plan.endswith(".k4v"):
        return ruta_plan[:-1]
    return ruta_plan[:-5] if ruta_plan.endswith(".json") else ruta_plan + ".k4"


def migrar_nombre(ruta_plan):
    """Un proyecto guardado con el nombre viejo pasa a llamarse `.k4v`.

    Se hace al abrir y una sola vez: el fichero es el mismo por dentro, solo
    cambia cómo se llama. Si por lo que sea ya existe el nuevo, el viejo se
    deja quieto —no vaya a ser que se pise algo— y manda el nuevo.
    """
    if not ruta_plan.endswith(".k4v"):
        return
    viejo = ruta_plan[:-4] + ".k4.json"
    if os.path.exists(viejo) and not os.path.exists(ruta_plan):
        os.rename(viejo, ruta_plan)


def orden_onda(args):
    """Los picos de una pista de audio, para dibujarla en la línea de tiempo.

    Un bloque de audio que es un rectángulo de color no dice nada: para saber
    dónde empieza a hablar alguien hay que reproducir y esperar. Con la onda
    dibujada se ve, que es la mitad de por qué un editor se edita mirando.

    Se saca a 2 kHz y en mono a propósito. Una onda de una línea de tiempo son
    unos cientos de barras; muestrear a 48 kHz para luego tirar el 99,9% sería
    leer treinta veces más bytes para pintar exactamente lo mismo. Una hora de
    vídeo son 14 MB en vez de 345.

    Y el pico de cada tramo, no la media: la media aplana la voz hasta dejarla
    igual que el silencio y la onda sale plana y mentirosa.
    """
    if not os.path.exists(args.fichero):
        salir(ok=False, motivo="sin-fichero")

    puntos = max(16, min(2000, int(args.puntos)))
    orden = ["ffmpeg"] + SIN_RED + ["-v", "error", "-i", args.fichero,
             "-map", "0:a:%d" % max(0, int(args.pista)),
             "-ac", "1", "-ar", "2000", "-f", "s16le", "-"]
    try:
        p = subprocess.run(orden, stdout=subprocess.PIPE,
                           stderr=subprocess.DEVNULL)
    except OSError:
        salir(ok=False, motivo="sin-ffmpeg")
    if p.returncode != 0 or not p.stdout:
        #  Una pista que no existe o un fichero sin audio no es un fallo del
        #  que haya que quejarse: es un bloque que se dibuja liso, y ya.
        salir(ok=True, picos=[], dur=0.0)

    import array
    muestras = array.array("h")
    #  `frombytes` exige múltiplo del tamaño del elemento, y un flujo cortado a
    #  media muestra es perfectamente posible.
    crudo = p.stdout
    muestras.frombytes(crudo[:len(crudo) - (len(crudo) % 2)])
    total = len(muestras)
    if total == 0:
        salir(ok=True, picos=[], dur=0.0)

    paso = max(1, total // puntos)
    picos = []
    for i in range(0, total, paso):
        trozo = muestras[i:i + paso]
        if not trozo:
            continue
        picos.append(round(max(max(trozo), -min(trozo)) / 32768.0, 4))

    #  Y CUÁNTO dura lo que se ha medido, que sale gratis: se ha leído el flujo
    #  entero a 2 kHz, así que el número de muestras ES la duración.
    #
    #  Hace falta para saber a qué pico corresponde un instante. Sin esto había
    #  que deducirlo del `dur` de la capa, y ese no es la duración del FICHERO
    #  sino la del trozo que se oye: una capa recortada —o una pista separada de
    #  un clip— apuntaba a un pico que no era el suyo.
    salir(ok=True, picos=picos[:puntos], dur=round(total / 2000.0, 4))


def plan_de_video(video, propuesto):
    """Dónde está el plan de un vídeo, ahora que un proyecto puede llamarse
    como le dé la gana.

    El nombre de fábrica es `<vídeo>.k4v` y con eso bastaba mientras nadie
    pudiera renombrarlo. Desde que se puede, ese nombre solo es el PRIMER sitio
    donde mirar: si no está, hay que buscar quién dice ser el plan de este
    vídeo, y eso no se adivina del nombre —se lee.

    Se mira solo en la carpeta del vídeo. Recorrer el disco entero para abrir un
    fichero sería pagar un precio enorme por un caso raro, y mover el proyecto
    lejos de su vídeo ya es pedir que no se encuentren.

    Un `.k4v` ilegible o de otro vídeo no estorba: se salta y se sigue.
    """
    if propuesto and os.path.exists(propuesto):
        return propuesto

    quiero = os.path.abspath(video)
    carpeta = os.path.dirname(quiero) or "."
    try:
        nombres = sorted(os.listdir(carpeta))
    except OSError:
        return propuesto

    for n in nombres:
        if not n.endswith(".k4v"):
            continue
        ruta = os.path.join(carpeta, n)
        if ruta == propuesto:
            continue
        try:
            with open(ruta) as f:
                d = json.load(f)
        except (OSError, ValueError):
            continue
        for fu in d.get("fuentes", []):
            if os.path.abspath(fu.get("ruta", "")) == quiero:
                return ruta
    return propuesto


def nombre_libre(carpeta, nombre):
    """Que renombrar no pise nunca un proyecto que ya existe.

    Devuelve `<nombre>.k4v`, o `<nombre> (2).k4v` y siguientes si hace falta.
    Preguntar «¿lo sobrescribo?» desde aquí no se puede —esto no habla con
    nadie— y perder el montaje de otro por reusar un nombre es de las cosas que
    no se pueden deshacer.
    """
    limpio = re.sub(r"[/\\\x00]", "_", (nombre or "").strip()) or "proyecto"
    destino = os.path.join(carpeta, limpio + ".k4v")
    if not os.path.exists(destino):
        return destino
    n = 2
    while os.path.exists(os.path.join(carpeta, "%s (%d).k4v" % (limpio, n))):
        n += 1
    return os.path.join(carpeta, "%s (%d).k4v" % (limpio, n))


def orden_renombrar(args):
    """Ponerle nombre a un proyecto: el fichero Y su carpeta adjunta.

    Las dos cosas a la vez y no solo el `.k4v`: la carpeta se llama a partir del
    plan —`<plan>.k4/`, ver `carpeta_de`— así que renombrar uno sin el otro deja
    el SRT y el texto de los rótulos huérfanos, y el editor los buscaría donde
    ya no están.
    """
    if not os.path.exists(args.plan):
        salir(ok=False, motivo="sin-plan")

    carpeta = os.path.dirname(os.path.abspath(args.plan))
    destino = nombre_libre(carpeta, args.nombre)
    if os.path.abspath(destino) == os.path.abspath(args.plan):
        salir(ok=True, plan=args.plan)

    adjunta_vieja = carpeta_de(args.plan)
    os.rename(args.plan, destino)
    #  La carpeta puede no existir —un montaje sin rótulos ni transcripción no
    #  la necesita— y eso no es un fallo.
    if os.path.isdir(adjunta_vieja):
        os.rename(adjunta_vieja, carpeta_de(destino))
    salir(ok=True, plan=destino)


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

    #  Y una capa de IMAGEN animada —efectos o fotogramas clave— necesita el
    #  mismo bucle: sus filtros evalúan con `t`, y un flujo de un solo
    #  fotograma se filtra UNA vez, en el instante cero. Sin esto, la escala
    #  animada de una imagen salía congelada en su primer valor y el fundido
    #  ni aparecía. Estirada hasta su t1; de ahí en adelante ya la apaga el
    #  `enable` del overlay.
    for c in capas_de(plan):
        if c.get("tipo") == "imagen" and c.get("ruta") and capa_animada(c):
            r = os.path.abspath(c["ruta"])
            hasta[r] = max(hasta.get(r, 0.0), float(c.get("t1", 0.0)) + 1.0)

    #  Y una FORMA animada, igual: su PNG no está en el plan —se dibuja al
    #  montar las entradas— así que se localiza por su nombre, que es
    #  determinista (modo y color).
    for c in capas_de(plan, "forma"):
        if not capa_animada(c):
            continue
        nombre = nombre_forma(c)
        for r in rutas:
            if os.path.basename(r) == nombre:
                ra = os.path.abspath(r)
                hasta[ra] = max(hasta.get(ra, 0.0),
                                float(c.get("t1", 0.0)) + 1.0)

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


#  Las transiciones de los cortes, con nombre de casa y filtro de ffmpeg.
XFADE = {"encadenado": "fade", "deslizar": "slideleft", "barrido": "wipeleft"}


def transicion_de(plan):
    """La transición de los cortes, normalizada, o None si es corte seco.

    Global y no por corte, como los fundidos: es una decisión del montaje
    entero. La duración se acota a 0,15–1: por debajo no se ve y por encima
    ya no es una transición, es un efecto.
    """
    tr = plan.get("transicion") or {}
    tipo = tr.get("tipo") or ""
    if tipo not in XFADE:
        return None
    return {"tipo": XFADE[tipo],
            "dur": encaja(float(tr.get("dur", 0.5) or 0.5), 0.15, 1.0)}


def duraciones_transicion(tramos, tr):
    """Cuánto dura la transición en CADA corte, acotada a los vecinos.

    Un corte entre dos trozos cortos no puede llevarse media vida de ambos:
    se recorta al 45 % del más breve, que deja siempre trozo a la vista.
    """
    D = []
    for i in range(len(tramos) - 1):
        d0 = tramos[i][1] - tramos[i][0]
        d1 = tramos[i + 1][1] - tramos[i + 1][0]
        D.append(max(0.05, min(tr["dur"], 0.45 * d0, 0.45 * d1)))
    return D


def rama_audio(i, idx, clip, fuente, dur, fundido="", ext=0.0):
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
                % (dur + ext, i)]

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

    #  La cola de la transición: el trozo entrega `ext` segundos de más para
    #  que el encadenado tenga con qué mezclar SIN comerse al siguiente. El
    #  `apad,atrim` deja el largo clavado aunque el fichero se acabe antes.
    exacto = (",apad,atrim=0:%.4f" % (dur + ext)) if ext > 0 else ""
    hasta_ext = clip["hasta"] + ext * velocidad_de(clip)

    lineas, etiquetas = [], []
    for p in vivas:
        et = "a%d" % i if una else "c%dp%d" % (i, p["i"])
        #  La limpieza de ruido, por pista y ANTES del volumen: el soplido del
        #  micro se quita del original y luego se sube lo limpio. `afftdn` con
        #  la puerta suave de fábrica; nr=12 quita el aire sin comerse la voz.
        limpia = FILTRO_ESCOBA + "," if p.get("limpia") else ""
        lineas.append(
            "[%d:a:%d]atrim=start=%.4f:end=%.4f,asetpts=PTS-STARTPTS,"
            "%svolume=%.3f,%s%s%s%s[%s]"
            % (idx, p["i"], clip["desde"], hasta_ext, limpia,
               float(p.get("volumen", 1.0)), tempo, NORMA_AUDIO,
               exacto if una else "", cola if una else "", et))
        etiquetas.append("[%s]" % et)

    if una:
        return lineas

    #  `normalize=0`: sin esto amix baja el volumen de todas al sumarlas, y
    #  subir una acabaría bajando la otra sin que nadie lo haya pedido.
    lineas.append("%samix=inputs=%d:normalize=0%s%s[a%d]"
                  % ("".join(etiquetas), len(etiquetas), exacto, cola, i))
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
    """Expresión ffmpeg para los fotogramas clave de una capa.

    Recta entre punto y punto, o suave si la capa lo pide (`suave: true`):
    la misma smoothstep de toda la vida, u²(3−2u), que arranca y frena sin
    tirón. Es POR CAPA y no por clave a propósito: un movimiento mezcla los
    dos estilos y ya no se sabe qué va a hacer entre dos rombos.
    """
    ks = sorted(capa.get("keyframes", []) or [], key=lambda x: float(x.get("t", 0)))
    if not ks:
        return "%.6f" % float(capa.get(campo, defecto))
    puntos = [(float(k.get("t", 0)), float(k.get(campo, defecto))) for k in ks]
    if len(puntos) == 1:
        return "%.6f" % puntos[0][1]
    suave = bool(capa.get("suave"))
    def tramo(i):
        t0, v0 = puntos[i]
        t1, v1 = puntos[i + 1]
        if abs(t1 - t0) < 1e-6:
            return "%.6f" % v1
        if suave:
            u = "clip((t-%.6f)/%.6f,0,1)" % (t0, t1 - t0)
            return "(%.6f+(%.6f)*%s*%s*(3-2*%s))" % (v0, v1 - v0, u, u, u)
        return "(%.6f+(%.6f)*(t-%.6f))" % (v0, (v1 - v0) / (t1 - t0), t0)
    expr = "%.6f" % puntos[-1][1]
    for i in range(len(puntos) - 2, -1, -1):
        expr = "if(lt(t,%.6f),%s,%s)" % (puntos[i + 1][0], tramo(i), expr)
    return expr


#  Los efectos de entrada y salida de una capa.
#
#  `entrada` y `salida` son {tipo, dur}. Dos tipos, y cada uno toca lo suyo:
#  «desvanecer» funde el alfa y «deslizar» funde Y empuja desde abajo, que es
#  lo que hace un tercio inferior. La envolvente es una rampa lineal de `dur`
#  segundos pegada a t0 o a t1.
#
#  No hay un «crecer» y no es olvido: en el ffmpeg de hoy (8.1) las
#  expresiones de `scale` NO avanzan con el tiempo —`t` y `n` quedan
#  congelados, comprobado con vídeo y con imagen en bucle—, así que un tamaño
#  animado exige otra maquinaria (zoompan sobre lienzo acolchado). Esa pieza
#  llegará con el Ken Burns, que la necesita igual.


#  Los efectos que existen, y con qué curva corre su rampa.
#
#  La duración dice cuánto tarda; la curva, CÓMO reparte ese tiempo. Recta es
#  velocidad constante —lo de siempre—, «suave» arranca y frena (la misma
#  smoothstep que ya usan las claves), y «golpe» entra rápido y se posa, que es
#  lo que hace que un rótulo parezca que llega con intención.
EFECTOS = ("desvanecer", "deslizar", "maquina", "crecer", "girar")


def curvar(u, curva):
    """Envuelve una rampa 0→1 en su curva. `u` es una expresión de ffmpeg."""
    if curva == "suave":
        return "((%s)*(%s)*(3-2*(%s)))" % (u, u, u)
    if curva == "golpe":
        #  1-(1-u)³: sale disparada y llega frenando.
        return "(1-(1-(%s))*(1-(%s))*(1-(%s)))" % (u, u, u)
    return "(%s)" % u


def efecto_de(capa, cual):
    """El efecto de entrada o salida, normalizado, o None si no hay.

    La duración se acota a MEDIA ventana de la capa: una entrada de dos
    segundos en una capa de uno no es un efecto, es la capa entera
    apareciendo, y encima se pisaría con la salida.
    """
    e = capa.get(cual) or {}
    tipo = e.get("tipo") or ""
    if tipo not in EFECTOS:
        return None
    ventana = max(0.1, float(capa.get("t1", 0.0)) - float(capa.get("t0", 0.0)))
    curva = e.get("curva") or "recta"
    return {"tipo": tipo,
            "curva": curva if curva in ("recta", "suave", "golpe") else "recta",
            "dur": encaja(float(e.get("dur", 0.4)), 0.05, ventana / 2)}


def rampa(capa, cual, efecto, var="t"):
    """La rampa 0→1 del efecto, ya curvada, en expresión de ffmpeg.

    Vale 0 cuando el efecto empieza y 1 cuando ha terminado, tanto al entrar
    —cuenta desde t0— como al salir —cuenta hacia t1—. Todo lo que anima un
    efecto se cuelga de aquí, y por eso la curva se aplica en un solo sitio.
    """
    if cual == "entrada":
        u = "clip((%s-%.4f)/%.4f,0,1)" % (var, float(capa.get("t0", 0.0)),
                                          efecto["dur"])
    else:
        u = "clip((%.4f-%s)/%.4f,0,1)" % (float(capa.get("t1", 0.0)), var,
                                          efecto["dur"])
    return curvar(u, efecto["curva"])


def capa_animada(capa):
    """Si los filtros de la capa dependen del tiempo: claves, efectos o
    Ken Burns."""
    return bool(capa.get("keyframes")) or bool(efecto_de(capa, "entrada")) \
        or bool(efecto_de(capa, "salida")) or bool(kenburns_de(capa))


#  Cuánto empuja «deslizar», en fracción del alto del fotograma.
DESLIZA = 0.08


def efectos_video(capa):
    """Lo que aportan los efectos a una capa con imagen detrás.

    Devuelve (fades, dys): filtros `fade` para el alfa —parámetros
    constantes, que es lo único que ese filtro acepta— y sumandos para la y
    del overlay en fracción del alto. El alfa va por `fade` y no por una
    expresión en `colorchannelmixer` porque ese filtro NO evalúa expresiones:
    se las traga como error, y de ahí que el alfa animado por claves nunca
    funcionara.
    """
    fades, dys = [], []
    t0, t1 = float(capa.get("t0", 0.0)), float(capa.get("t1", 0.0))
    alfas = []
    for cual, e in (("entrada", efecto_de(capa, "entrada")),
                    ("salida", efecto_de(capa, "salida"))):
        if not e:
            continue
        r = rampa(capa, cual, e)
        #  «Girar» y «crecer» no funden: llegan girando o creciendo, y a tamaño
        #  y giro completos ya se ven. Fundirlos además sería otro efecto.
        if e["tipo"] in ("desvanecer", "deslizar", "maquina"):
            if e["curva"] == "recta":
                #  Con rampa recta manda `fade`, que es un filtro barato y
                #  probado. La curva no la sabe hacer, y entonces toca `geq`.
                if cual == "entrada":
                    fades.append("fade=t=in:st=%.4f:d=%.4f:alpha=1"
                                 % (t0, e["dur"]))
                else:
                    fades.append("fade=t=out:st=%.4f:d=%.4f:alpha=1"
                                 % (t1 - e["dur"], e["dur"]))
            else:
                alfas.append(r)
        if e["tipo"] == "deslizar":
            dys.append("%.3f*(1-%s)" % (DESLIZA, r))
    if alfas:
        #  `T` y no `t`: dentro de `geq` el instante se llama así. El resto de
        #  la capa se copia tal cual y solo se toca el alfa.
        expr = "*".join(a.replace("(t-", "(T-").replace("-t)", "-T)")
                        for a in alfas)
        fades.append("format=rgba")
        fades.append("geq=r='r(X,Y)':g='g(X,Y)':b='b(X,Y)':"
                     "a='alpha(X,Y)*%s'" % expr)
    return fades, dys


#  Cuánto encoge «crecer» al empezar: la mitad. Sale de la aritmética de
#  `zoompan`, que no sabe alejar por debajo de 1: se acolcha la capa al doble
#  con transparente y el zoom recorre 1→2, o sea de media a entera.
CRECE = 2


def medida_pintada(capa, ancho_capa, alto_capa):
    """Cuánto ocupa la capa DESPUÉS del aspecto, en píxeles.

    Hace falta para `zoompan`, que solo acepta números: la máscara redonda se
    queda con el cuadrado del centro y el marco añade su grosor por cada lado,
    así que la medida de después no es la de antes.
    """
    an, al = ancho_capa, alto_capa
    if (capa.get("mascara") or "") == "circulo":
        an = al = min(an, al)
    grosor = round(ancho_capa * float(capa.get("marco", 0.0) or 0.0))
    if grosor > 0.5:
        an, al = an + 2 * grosor, al + 2 * grosor
    return max(2, int(an)), max(2, int(al))


def hay_crecer(capa):
    for cual in ("entrada", "salida"):
        e = efecto_de(capa, cual)
        if e and e["tipo"] == "crecer":
            return True
    return False


def filtros_crecer(capa, ancho_capa, alto_capa):
    """La capa que llega creciendo (o se va encogiendo).

    `scale` no sirve —sus expresiones no avanzan con el tiempo, medido— así
    que el tamaño animado va como el Ken Burns: por `zoompan`. El truco es el
    acolchado: con el lienzo al doble, un zoom de 1 enseña la capa a media
    medida y uno de 2 la enseña entera, y la huella no cambia porque la salida
    se pide del tamaño de siempre.
    """
    partes = []
    for cual in ("entrada", "salida"):
        e = efecto_de(capa, cual)
        if e and e["tipo"] == "crecer":
            partes.append(rampa(capa, cual, e, var="it"))
    if not partes:
        return []
    #  Con las dos, manda la que esté más cerca de su borde: crece al entrar y
    #  encoge al salir sin pelearse en el medio, donde las dos valen 1.
    avance = partes[0] if len(partes) == 1 else "min(%s,%s)" % tuple(partes)
    return ["format=rgba",
            "pad=iw*%d:ih*%d:iw/2:ih/2:color=black@0" % (CRECE, CRECE),
            "zoompan=z='1+%.4f*%s':x='iw/2-iw/zoom/2':y='ih/2-ih/zoom/2':"
            "d=1:s=%dx%d:fps=25"
            % (CRECE - 1, avance, ancho_capa, alto_capa)]


#  Cuánto gira «girar», en grados.
GIRO = 20.0


def grados_efecto(capa):
    """Lo que suma el efecto «girar» al ángulo de la capa, o None."""
    partes = []
    for cual in ("entrada", "salida"):
        e = efecto_de(capa, cual)
        if e and e["tipo"] == "girar":
            partes.append("%.3f*(1-%s)" % (GIRO, rampa(capa, cual, e)))
    return "+".join(partes) if partes else None


def tamano_imagen(ruta):
    """(ancho, alto) leídos de la cabecera del fichero, o None.

    PNG y JPEG a mano —es leer unos bytes— y ffprobe de respaldo para lo
    demás. Hace falta para el Ken Burns: `zoompan` exige el tamaño de salida
    en números de verdad, no en expresiones.
    """
    try:
        with open(ruta, "rb") as f:
            cab = f.read(24)
            if cab[:8] == b"\x89PNG\r\n\x1a\n" and len(cab) >= 24:
                return (int.from_bytes(cab[16:20], "big"),
                        int.from_bytes(cab[20:24], "big"))
            if cab[:2] == b"\xff\xd8":
                #  JPEG: saltar de marca en marca hasta el SOF, que es quien
                #  lleva el tamaño. C4, C8 y CC parecen SOF y no lo son.
                f.seek(2)
                while True:
                    marca = f.read(4)
                    if len(marca) < 4 or marca[0] != 0xFF:
                        break
                    tipo = marca[1]
                    largo = int.from_bytes(marca[2:4], "big")
                    if 0xC0 <= tipo <= 0xCF and tipo not in (0xC4, 0xC8, 0xCC):
                        datos = f.read(5)
                        if len(datos) < 5:
                            break
                        return (int.from_bytes(datos[3:5], "big"),
                                int.from_bytes(datos[1:3], "big"))
                    f.seek(largo - 2, 1)
    except OSError:
        return None
    p = correr_sondeo(
        ["ffprobe"] + SIN_RED + ["-v", "error", "-select_streams", "v:0",
         "-show_entries", "stream=width,height", "-of", "csv=p=0", ruta],
        capture_output=True, text=True)
    partes = p.stdout.strip().split(",")
    if len(partes) == 2 and partes[0].isdigit() and partes[1].isdigit():
        return (int(partes[0]), int(partes[1]))
    return None


def kenburns_de(capa):
    """El Ken Burns de una capa de imagen, normalizado, o None.

    {desde, hasta}: cuánto zoom al empezar y al acabar su ventana, por DENTRO
    de la huella —la capa no cambia de tamaño, respira el contenido—. Acotado
    a 1..3: por debajo de 1 zoompan no sabe alejarse y por encima de 3 una
    foto normal ya es papilla.
    """
    kb = capa.get("kenburns") or {}
    if capa.get("tipo") != "imagen":
        return None
    z0 = encaja(float(kb.get("desde", 1.0) or 1.0), 1.0, 3.0)
    z1 = encaja(float(kb.get("hasta", 1.0) or 1.0), 1.0, 3.0)
    if abs(z1 - z0) < 0.01:
        return None
    return {"desde": z0, "hasta": z1}


def alfa_texto(capa):
    """La expresión de alfa de un rótulo con efectos, o None.

    Un rótulo no pasa por `fade`: lo dibuja `drawtext` directamente sobre el
    vídeo, así que su alfa es el parámetro `alpha`, que SÍ evalúa expresiones
    con `t`. La caja de detrás se funde con él.
    """
    partes = []
    for cual in ("entrada", "salida"):
        e = efecto_de(capa, cual)
        if e and e["tipo"] in ("desvanecer", "deslizar"):
            partes.append(rampa(capa, cual, e))
    return "*".join(partes) if partes else None


def estilo_texto(capa):
    """El estilo del rótulo: caja, contorno, sombra o limpio.

    Los planes de antes no llevan `estilo`: si tenían caja se quedan con su
    caja, y si no, limpios. `colorFondo` es el color SECUNDARIO del estilo,
    sea el que sea: la caja de detrás, el trazo del contorno o la sombra.
    """
    e = capa.get("estilo") or ""
    if e in ("caja", "contorno", "sombra", "limpio"):
        return e
    return "caja" if float(capa.get("fondo", 0.0)) > 0.001 else "limpio"


def ancho_texto(texto, tam):
    """Cuánto mide un rótulo en píxeles, con la MISMA fuente del render.

    Lo mide PIL sobre el mismo TTF que usa drawtext: es lo que permite anclar
    la máquina de escribir a la izquierda sin que el texto baile. Sin PIL se
    devuelve None y el efecto degrada a rótulo entero, que es peor que
    teclear pero mejor que mentir con un centrado que salta.
    """
    try:
        from PIL import ImageFont
        return ImageFont.truetype(FUENTE, tam).getlength(texto)
    except Exception:
        return None


def rama_maquina(n, capa, ent, tam, partes_comunes, carpeta, entra):
    """El rótulo tecleándose: un drawtext por prefijo, anclado a la izquierda.

    Centrar cada prefijo lo haría bailar —el centro se mueve con cada letra—
    así que se calcula UNA vez dónde empieza el texto completo y todos los
    prefijos arrancan ahí. Como mucho 60 pasos: en rótulos largos entran
    varias letras por paso y nadie lo nota.
    """
    texto = capa.get("texto", "")
    total = ancho_texto(texto, tam)
    if total is None or len(texto) < 2:
        return None

    t0, t1 = float(capa.get("t0", 0)), float(capa.get("t1", 0))
    dur = ent["dur"]
    pasos = min(60, len(texto))
    x_izq = "%.4f*w-%.1f" % (float(capa.get("x", 0.5)), total / 2.0)

    lineas = []
    for k in range(pasos):
        corte = int(round(len(texto) * (k + 1) / float(pasos)))
        ruta = os.path.join(carpeta, "texto-%d-%d.txt" % (capa["id"], k))
        with open(ruta, "w") as f:
            f.write(texto[:corte])
        ta = t0 + dur * k / float(pasos)
        #  El último paso se queda hasta el final de la capa: es el rótulo
        #  entero, ya tecleado.
        tb = t1 if k == pasos - 1 else t0 + dur * (k + 1) / float(pasos)
        partes = ["drawtext=fontfile=%s" % citar(FUENTE),
                  "textfile=%s" % citar(ruta),
                  "expansion=none",
                  "x=%s" % x_izq,
                  "enable='between(t,%.4f,%.4f)'" % (ta, tb)] + partes_comunes
        sale = "ov%dk%d" % (n, k)
        lineas.append("[%s]%s[%s]" % (entra, ":".join(partes), sale))
        entra = sale
    return lineas, entra


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
    _, dys_ef = efectos_video(capa)
    alfa = alfa_texto(capa)
    empuje = "".join("+" + d for d in dys_ef)

    #  Lo que comparten el rótulo entero y sus prefijos de la máquina de
    #  escribir: cuerpo, color, altura y estilo.
    comunes = [("fontsize='max(8,%s*h)'"
                % expresion_animada(capa, "tam", 0.06)
                if capa.get("keyframes") else "fontsize=%d" % tam),
               "fontcolor=%s" % color_ffmpeg(capa.get("color", "#ffffff")),
               ("y='(%s%s)*h-text_h/2'"
                % (expresion_animada(capa, "y", 0.85), empuje)
                if capa.get("keyframes") or empuje else
                "y=%.4f*h-text_h/2" % float(capa.get("y", 0.85)))]

    estilo = estilo_texto(capa)
    fondo = float(capa.get("fondo", 0.5))
    if estilo == "caja" and fondo > 0.001:
        # Una caja detrás, para que el texto se lea sobre cualquier cosa.
        comunes += ["box=1",
                    "boxcolor=%s" % color_ffmpeg(capa.get("colorFondo", "#000000"),
                                                 fondo),
                    "boxborderw=%d" % max(2, int(round(tam * 0.28)))]
    elif estilo == "contorno":
        #  Grosor con el cuerpo de letra: un contorno fijo se come las letras
        #  pequeñas y desaparece en las grandes.
        comunes += ["borderw=%d" % max(1, int(round(tam * 0.08))),
                    "bordercolor=%s"
                    % color_ffmpeg(capa.get("colorFondo", "#000000"))]
    elif estilo == "sombra":
        sombra = max(1, int(round(tam * 0.07)))
        comunes += ["shadowx=%d" % sombra, "shadowy=%d" % sombra,
                    "shadowcolor=%s"
                    % color_ffmpeg(capa.get("colorFondo", "#000000"), 0.65)]

    #  La máquina de escribir: si hay con qué medir, teclea; si no, rótulo
    #  entero de siempre, que es peor que teclear pero mejor que un centrado
    #  que baila.
    ent = efecto_de(capa, "entrada")
    if ent and ent["tipo"] == "maquina":
        hecho = rama_maquina(n, capa, ent, tam, comunes, carpeta, entra)
        if hecho:
            return hecho

    #  `expansion=none`: sin esto `drawtext` se cree que el texto lleva formato y
    #  un «50 %» acaba en «Stray %» y en un rótulo a medias. Probado.
    partes = ["drawtext=fontfile=%s" % citar(FUENTE),
              "textfile=%s" % citar(ruta),
              "expansion=none",
              #  Centrado en (x, y) como las demás capas: `text_w` y `text_h` son
              #  lo que mide el rótulo ya compuesto.
              ("x='%s*w-text_w/2'" % expresion_animada(capa, "x", 0.5)
               if capa.get("keyframes") else
               "x=%.4f*w-text_w/2" % float(capa.get("x", 0.5))),
              "enable='between(t,%.4f,%.4f)'"
              % (float(capa.get("t0", 0)), float(capa.get("t1", 0)))] + comunes
    if alfa:
        partes.append("alpha='%s'" % alfa)

    sale = "ov%d" % n
    return ["[%s]%s[%s]" % (entra, ":".join(partes), sale)], sale


#  ── el aspecto de una capa ────────────────────────────────────────
#
#  Lo que se le hace a una capa por ser ella y no por dónde está: darle la
#  vuelta, quitarle el color, redondearla, ponerle marco. Vale igual para una
#  imagen, un vídeo incrustado y una forma, así que vive en un sitio y lo usan
#  las tres ramas.
#
#  Va DESPUÉS de escalar y antes de la opacidad y los fundidos: el marco se mide
#  en píxeles de la capa ya escalada —si no, un logo pequeño tendría un marco
#  gordísimo— y el alfa que ponen máscara y fundido tiene que componerse en ese
#  orden o el fundido se comería el recorte.

FILTROS_COLOR = {
    "gris": "hue=s=0",
    #  La matriz clásica del sepia. En rgba porque una capa puede llevar alfa y
    #  `colorchannelmixer` sin `aa` lo respeta.
    "sepia": ("colorchannelmixer="
              "0.393:0.769:0.189:0:0.349:0.686:0.168:0:0.272:0.534:0.131"),
    "vivo": "eq=saturation=1.6:contrast=1.06",
    #  Medido sobre un gris neutro, no leído: `colortemperature` BAJA calienta
    #  (4000 K deja el gris en 128,103,83) y ALTA enfría (9000 K lo deja en
    #  105,111,128). Es al revés de como suena, y puestos al derecho los dos
    #  chips hacían lo contrario de lo que decían.
    "frio": "colortemperature=temperature=8500",
    "calido": "colortemperature=temperature=4800",
}


def expresion_redondeo(radio_expr, grosor, color):
    """Máscara redondeada —y su marco— en una sola pasada de `geq`.

    La cuenta es la distancia con signo a un rectángulo de esquinas redondeadas:
    se aparta el punto hacia la esquina más cercana y se mide contra el radio.
    Sirve igual para un círculo (radio = medio lado) y para unas esquinas
    suaves, que es la gracia de hacerlo así y no con dos filtros distintos.

    Fuera de la forma el alfa es cero; en la última franja, el color del marco;
    dentro, el píxel tal cual. El borde se suaviza un píxel: sin eso el círculo
    sale con dientes de sierra, que es lo primero que se ve.
    """
    dx = "max(abs(X-W/2)-(W/2-%s),0)" % radio_expr
    dy = "max(abs(Y-H/2)-(H/2-%s),0)" % radio_expr
    sd = "(hypot(%s,%s)-%s)" % (dx, dy, radio_expr)
    dentro = "(1-clip(%s+0.5,0,1))" % sd
    if grosor > 0.5:
        r, g, b = color
        marco = "gt(%s,-%.2f)" % (sd, grosor)
        canal = lambda f, v: "if(%s,%d,%s(X,Y))" % (marco, v, f)
        #  El alfa del anillo se pone a mano y no se hereda: el marco cae en el
        #  hueco que abre el `pad`, que es transparente, así que multiplicar por
        #  el alfa de origen dejaba el marco invisible —pintado y sin verse—.
        alfa = "if(%s,255*%s,alpha(X,Y)*%s)" % (marco, dentro, dentro)
        return ("geq=r='%s':g='%s':b='%s':a='%s'"
                % (canal("r", r), canal("g", g), canal("b", b), alfa))
    return ("geq=r='r(X,Y)':g='g(X,Y)':b='b(X,Y)':a='alpha(X,Y)*%s'" % dentro)


def filtros_aspecto(capa, ancho_capa):
    """Espejo, filtro de color, máscara y marco. Devuelve la lista de filtros.

    `ancho_capa` es el ancho ya escalado, en píxeles: de ahí salen el radio y el
    grosor del marco, que en el plan van en fracción para no depender de la
    resolución de salida.
    """
    salida = []
    if capa.get("espejo"):
        salida.append("hflip")
    filtro = FILTROS_COLOR.get(capa.get("filtro") or "")
    if filtro:
        salida.append(filtro)

    mascara = capa.get("mascara") or ""
    grosor_frac = float(capa.get("marco", 0.0) or 0.0)
    color = color_rgb(capa.get("colorMarco") or "#ffffff")
    grosor = round(ancho_capa * grosor_frac)

    #  El marco va POR FUERA, no comiéndose el borde de la imagen: se hace
    #  sitio con un `pad` y el marco ocupa ESE sitio. Pintarlo hacia dentro
    #  tapaba justo lo que se quiere enmarcar —lo primero que se ve al usarlo—.
    #  La capa crece el grosor por cada lado; su centro no se mueve, así que
    #  ni el sitio ni las claves de movimiento cambian.
    hueco = ("pad=iw+%d:ih+%d:%d:%d:color=black@0"
             % (2 * grosor, 2 * grosor, grosor, grosor))

    if mascara == "circulo":
        #  Un círculo de verdad y no una elipse: se recorta el cuadrado del
        #  centro y el radio es medio lado. Una cámara 16:9 «en círculo» es
        #  esto, no el vídeo entero aplastado.
        salida.append("crop=w='min(iw,ih)':h='min(iw,ih)'")
        salida.append("format=rgba")
        if grosor > 0.5:
            salida.append(hueco)
        salida.append(expresion_redondeo("W/2", grosor, color))
    elif mascara == "redonda":
        salida.append("format=rgba")
        if grosor > 0.5:
            salida.append(hueco)
            #  El radio de fuera es el de dentro más el grosor: así el anillo
            #  es concéntrico y no un redondeo distinto pegado encima.
            radio = "((min(W,H)-%d)*0.12+%d)" % (2 * grosor, grosor)
        else:
            radio = "min(W,H)*0.12"
        salida.append(expresion_redondeo(radio, grosor, color))
    elif grosor > 0.5:
        #  Sin máscara el marco es un recuadro, y para eso no hace falta pintar
        #  píxel a píxel: el propio `pad` lo da, del color que sea.
        salida.append("format=rgba")
        salida.append("pad=iw+%d:ih+%d:%d:%d:color=%s"
                      % (2 * grosor, 2 * grosor, grosor, grosor,
                         capa.get("colorMarco") or "#ffffff"))
    return salida


def filtros_sombra(capa, ancho_capa):
    """La sombra que proyecta una capa, y cuánto se sale de su huella.

    Devuelve (filtros, margen): el doble de la capa ennegrecido y difuminado, y
    los píxeles que hay que restar a su sitio para que la mancha quede centrada
    —se acolcha antes de difuminar, porque si no el desenfoque se corta contra
    el borde y la sombra sale con esquina—.

    Va sobre el alfa de la capa, así que una capa redonda proyecta una sombra
    redonda y un logo recortado proyecta su silueta, sin decirle nada a nadie.
    """
    fuerza = float(capa.get("sombra", 0.0) or 0.0)
    if fuerza <= 0.001:
        return [], 0
    #  Proporcional a la capa y no en píxeles fijos: la misma sombra tiene que
    #  valer para un logo de 200 px y para una cámara de 600.
    sigma = max(2.0, 0.045 * ancho_capa)
    margen = int(round(3 * sigma))
    return ([
        "format=rgba",
        #  Negro conservando la silueta: los tres canales a cero y el alfa a lo
        #  que pida la fuerza.
        "colorchannelmixer=rr=0:gg=0:bb=0:aa=%.3f" % (0.7 * fuerza),
        "pad=iw+%d:ih+%d:%d:%d:color=black@0" % (2 * margen, 2 * margen,
                                                 margen, margen),
        "gblur=sigma=%.2f:planes=15" % sigma,
    ], margen)


def desplazamiento_sombra(capa, ancho_capa):
    """Cuánto cae la sombra hacia abajo y a la derecha, en píxeles."""
    fuerza = float(capa.get("sombra", 0.0) or 0.0)
    return int(round(max(2.0, 0.045 * ancho_capa) * (0.5 + fuerza)))


def color_rgb(texto):
    """De «#rrggbb» a los tres números que quiere `geq`."""
    t = str(texto).lstrip("#")
    if len(t) != 6:
        return (255, 255, 255)
    try:
        return tuple(int(t[i:i + 2], 16) for i in (0, 2, 4))
    except ValueError:
        return (255, 255, 255)


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
    fades, dys_ef = efectos_video(capa)

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
    #  El giro de la capa y el que le añade el efecto «girar» son el MISMO
    #  filtro: dos `rotate` encadenados recortan las esquinas dos veces.
    giro_ef = grados_efecto(capa)
    hay_rotacion = abs(rotacion) > 0.01 or giro_ef is not None or any(
        abs(float(k.get("rotacion", 0))) > 0.01
        for k in (capa.get("keyframes") or []))
    if hay_rotacion:
        filtros.append("format=rgba")
        base = (expresion_animada(capa, "rotacion", rotacion)
                if capa.get("keyframes") else "%.6f" % rotacion)
        angulo = base if giro_ef is None else "(%s)+(%s)" % (base, giro_ef)
        filtros.append("rotate='%s*PI/180':fillcolor=none" % angulo)

    if capa.get("keyframes"):
        filtros.append("scale=w='round(%d*%s)':h=-1:eval=frame" % (ancho, escala_expr))
    else:
        filtros.append("scale=%d:-1" % ancho_capa)
    filtros.append("setsar=1")
    filtros += filtros_aspecto(capa, ancho_capa)
    if hay_crecer(capa):
        #  Aquí la proporción la da el recorte de la fuente, que es lo que se
        #  está viendo, y no el tamaño del fichero entero.
        alto_base = max(2, int(round(ancho_capa * al / max(1, an))))
        filtros += filtros_crecer(
            capa, *medida_pintada(capa, ancho_capa, alto_base))

    opacidad = float(capa.get("opacidad", 1.0))
    if opacidad < 0.999:
        filtros.append("format=rgba,colorchannelmixer=aa=%.3f" % opacidad)
    if fades:
        #  Sobre rgba y al final: `fade` con `alpha=1` solo toca el alfa. Sus
        #  tiempos van en la línea, y aquí el `setpts` de más arriba ya empujó
        #  el clip a su instante, así que cuadran.
        filtros.append("format=rgba")
        filtros += fades

    lineas.append("[%d:v]%s[%s]" % (idx, ",".join(filtros), et))

    sale = "ov%d" % n
    empuje = "".join("+" + d for d in dys_ef)

    #  La sombra va DEBAJO y con su propio overlay, no compuesta con la capa:
    #  así la mancha puede salirse de la huella —que es lo que hace que
    #  parezca sombra— sin agrandar la capa ni moverla de sitio.
    som, _margen = filtros_sombra(capa, ancho_capa)
    if som:
        salto = desplazamiento_sombra(capa, ancho_capa)
        xs = ("%s*W-w/2" % expresion_animada(capa, "x", 0.75)
              if (capa.get("keyframes") or empuje)
              else "%.4f*W-w/2" % float(capa.get("x", 0.75)))
        ys = ("(%s%s)*H-h/2" % (expresion_animada(capa, "y", 0.75), empuje)
              if (capa.get("keyframes") or empuje)
              else "%.4f*H-h/2" % float(capa.get("y", 0.75)))
        lineas.append("[%s]split[cp%d][sm%d]" % (et, n, n))
        lineas.append("[sm%d]%s[so%d]" % (n, ",".join(som), n))
        et = "cp%d" % n
        bajo = "sb%d" % n
        lineas.append("[%s][so%d]overlay=x='(%s)+%d':y='(%s)+%d':"
                      "enable='between(t,%.4f,%.4f)'%s[%s]"
                      % (entra, n, xs, salto, ys, salto,
                         float(capa.get("t0", 0.0)), float(capa.get("t1", 0.0)),
                         ':eof_action=pass', bajo))
        entra = bajo
    if capa.get("keyframes") or empuje:
        linea_overlay = (
            "[%s][%s]overlay=x='%s*W-w/2':y='(%s%s)*H-h/2':"
            "enable='between(t,%.4f,%.4f)':eof_action=pass[%s]"
            % (entra, et, expresion_animada(capa, "x", 0.75),
               expresion_animada(capa, "y", 0.75), empuje,
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
    fades, dys_ef = efectos_video(capa)

    filtros = []
    rotacion = float(capa.get("rotacion", 0.0))
    #  El giro de la capa y el que le añade el efecto «girar» son el MISMO
    #  filtro: dos `rotate` encadenados recortan las esquinas dos veces.
    giro_ef = grados_efecto(capa)
    hay_rotacion = abs(rotacion) > 0.01 or giro_ef is not None or any(
        abs(float(k.get("rotacion", 0))) > 0.01
        for k in (capa.get("keyframes") or []))
    if hay_rotacion:
        filtros.append("format=rgba")
        base = (expresion_animada(capa, "rotacion", rotacion)
                if capa.get("keyframes") else "%.6f" % rotacion)
        angulo = base if giro_ef is None else "(%s)+(%s)" % (base, giro_ef)
        filtros.append("rotate='%s*PI/180':fillcolor=none" % angulo)
    #  El Ken Burns: zoom por DENTRO de la huella, con zoompan, que es el
    #  único camino que de verdad anima un tamaño —las expresiones de `scale`
    #  están congeladas, ver arriba—. La capa no cambia de medida: se acerca
    #  su contenido, con el recorte centrado. Exige saber cuánto mide la
    #  imagen, porque `s=` solo acepta números; si no se puede medir, la capa
    #  se queda quieta y ya.
    kb = kenburns_de(capa)
    dim = tamano_imagen(capa.get("ruta", "")) if kb else None
    if kb and dim:
        iw, ih = dim
        hf = max(2, int(round(ancho_capa * ih / max(1, iw))))
        zmax = max(kb["desde"], kb["hasta"])
        t0, t1 = float(capa.get("t0", 0.0)), float(capa.get("t1", 0.0))
        progreso = "clip((it-%.4f)/%.4f,0,1)" % (t0, max(0.05, t1 - t0))
        if capa.get("suave"):
            progreso = "%s*%s*(3-2*%s)" % (progreso, progreso, progreso)
        #  Se escala ANTES a lo que pide el zoom máximo: zoompan recorta de su
        #  entrada, y recortar de una imagen justa es inventar píxeles.
        filtros.append("scale=%d:-1" % int(round(ancho_capa * zmax + 2)))
        filtros.append(
            "zoompan=z='%.4f+%.4f*%s':x='iw/2-iw/zoom/2':"
            "y='ih/2-ih/zoom/2':d=1:s=%dx%d:fps=25"
            % (kb["desde"], kb["hasta"] - kb["desde"], progreso,
               ancho_capa, hf))
    elif capa.get("keyframes"):
        filtros.append("scale=w='round(%d*%s)':h=-1:eval=frame" % (ancho, escala_expr))
    else:
        filtros.append("scale=%d:-1" % ancho_capa)
    filtros += filtros_aspecto(capa, ancho_capa)
    if hay_crecer(capa):
        #  El alto sale de la propia imagen: `zoompan` solo acepta números, y
        #  sin poder medirla el efecto se salta y la capa entra quieta.
        med = dim or tamano_imagen(capa.get("ruta", ""))
        if med:
            alto_base = max(2, int(round(ancho_capa * med[1] / max(1, med[0]))))
            filtros += filtros_crecer(
                capa, *medida_pintada(capa, ancho_capa, alto_base))
    opacidad = float(capa.get("opacidad", 1.0))
    if opacidad < 0.999:
        #  El alfa hay que tenerlo antes de poder tocarlo: un JPEG llega sin
        #  canal alfa y `colorchannelmixer=aa=` no haría nada, sin quejarse.
        filtros.append("format=rgba,colorchannelmixer=aa=%.3f" % opacidad)
    if fades:
        #  El fundido del efecto va el último y sobre rgba: `fade` con
        #  `alpha=1` solo toca el canal alfa, que es justo lo que se quiere.
        filtros.append("format=rgba")
        filtros += fades

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
    empuje = "".join("+" + d for d in dys_ef)

    #  La sombra va DEBAJO y con su propio overlay, no compuesta con la capa:
    #  así la mancha puede salirse de la huella —que es lo que hace que
    #  parezca sombra— sin agrandar la capa ni moverla de sitio.
    som, _margen = filtros_sombra(capa, ancho_capa)
    if som:
        salto = desplazamiento_sombra(capa, ancho_capa)
        xs = ("%s*W-w/2" % expresion_animada(capa, "x", 0.5)
              if (capa.get("keyframes") or empuje)
              else "%.4f*W-w/2" % float(capa.get("x", 0.5)))
        ys = ("(%s%s)*H-h/2" % (expresion_animada(capa, "y", 0.5), empuje)
              if (capa.get("keyframes") or empuje)
              else "%.4f*H-h/2" % float(capa.get("y", 0.5)))
        lineas.append("[%s]split[cp%d][sm%d]" % (et, n, n))
        lineas.append("[sm%d]%s[so%d]" % (n, ",".join(som), n))
        et = "cp%d" % n
        bajo = "sb%d" % n
        lineas.append("[%s][so%d]overlay=x='(%s)+%d':y='(%s)+%d':"
                      "enable='between(t,%.4f,%.4f)'%s[%s]"
                      % (entra, n, xs, salto, ys, salto,
                         float(capa.get("t0", 0.0)), float(capa.get("t1", 0.0)),
                         '', bajo))
        entra = bajo
    if capa.get("keyframes") or empuje:
        linea_overlay = (
            "[%s][%s]overlay=x='%s*W-w/2':y='(%s%s)*H-h/2':"
            "enable='between(t,%.4f,%.4f)'[%s]"
            % (entra, et, expresion_animada(capa, "x", 0.5),
               expresion_animada(capa, "y", 0.5), empuje,
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


def filtros_fundido(i, total, dur, plan, clip=None):
    """Los `fade` de vídeo y audio de un trozo, en tiempo LOCAL del trozo.

    Si el TROZO trae los suyos —`fundeEntra` y `fundeSale`— mandan esos y el
    ajuste global se ignora para él. Los fundidos eran de la línea entera: podías
    desvanecer el montaje al principio y al final, y nada más. Desvanecer UN
    trozo, que es lo que se pide el noventa por ciento de las veces, no se podía
    decir. Ahora se dice arrastrando la esquina del bloque.

    El ajuste global se queda para quien no toque nada: un montaje de antes sigue
    fundiendo exactamente igual, porque sin esos campos manda la regla de
    siempre.

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

    #  Y lo que diga el trozo, si lo dice. Cero es una respuesta válida —«este
    #  no funde»— así que se mira si el campo ESTÁ, no si vale algo.
    if clip:
        if clip.get("fundeEntra") is not None:
            ini = max(0.0, float(clip["fundeEntra"]))
        if clip.get("fundeSale") is not None:
            fin = max(0.0, float(clip["fundeSale"]))

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


#  Las formas de señalar: flecha, círculo y marco.
#
#  No son dibujos de ffmpeg: se pintan UNA vez con magick a un PNG con alfa
#  —como el anillo de los clics— y entran por la tubería de imagen, que es lo
#  que les regala el movimiento, los efectos, las claves y el trazado sin una
#  línea nueva. El nombre lleva el modo y el color: dos capas iguales
#  comparten fichero, y cambiar el color no puede reusar el viejo.
LADO_FORMA = 512


def nombre_forma(capa):
    modo = capa.get("modo") or "flecha"
    color = str(capa.get("color", "#ff453a")).lstrip("#").lower()
    return "forma-%s-%s.png" % (modo, color)


def dibujar_forma(carpeta, capa):
    """El PNG de una forma, dibujado si no estaba. La ruta, o "" si no pudo."""
    try:
        os.makedirs(carpeta, exist_ok=True)
    except OSError:
        return ""
    ruta = os.path.join(carpeta, nombre_forma(capa))
    if os.path.exists(ruta):
        return ruta

    color = str(capa.get("color", "#ff453a"))
    modo = capa.get("modo") or "flecha"
    L = LADO_FORMA
    grosor = L // 13
    orden = ["magick", "-size", "%dx%d" % (L, L), "xc:none"]
    if modo == "circulo":
        r = L / 2.0 - grosor
        orden += ["-fill", "none", "-stroke", color,
                  "-strokewidth", str(grosor),
                  "-draw", "circle %.1f,%.1f %.1f,%.1f"
                  % (L / 2.0, L / 2.0, L / 2.0, L / 2.0 - r)]
    elif modo == "marco":
        m = grosor
        orden += ["-fill", "none", "-stroke", color,
                  "-strokewidth", str(grosor),
                  "-draw", "rectangle %d,%d %d,%d" % (m, m, L - m, L - m)]
    else:
        #  La flecha apunta a la DERECHA y desde ahí se gira: el asta como
        #  línea gruesa y la punta como triángulo lleno.
        y = L / 2.0
        orden += ["-fill", "none", "-stroke", color,
                  "-strokewidth", str(int(grosor * 1.2)),
                  "-draw", "line %d,%.1f %d,%.1f" % (L // 16, y, L - L // 3, y),
                  "-fill", color, "-stroke", "none",
                  "-draw", "polygon %d,%.1f %d,%.1f %d,%.1f"
                  % (L - L // 16, y, L - L // 3 - 8, y - L // 5,
                     L - L // 3 - 8, y + L // 5)]
    orden.append(ruta)
    try:
        pr = subprocess.run(orden, capture_output=True, text=True)
    except OSError:
        return ""
    return ruta if pr.returncode == 0 and os.path.exists(ruta) else ""


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


def grafo(plan, sin_audio=False, carpeta=None, sonoridad=False,
          vertical=False):
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

    #  La transición de los cortes, si la hay. Con ella cada trozo entrega
    #  una COLA de más —material del fichero que viene después de su `hasta`,
    #  fotogramas que de todas formas existían— y el encadenado mezcla esa
    #  cola con la cabeza del siguiente. Así la línea dura EXACTAMENTE lo
    #  mismo que sin transición: un xfade a secas se comería el principio de
    #  cada trozo y descolocaría rótulos, zooms y capas, que es justo lo que
    #  este editor promete no hacer. Si el fichero no da más de sí, `tpad`
    #  clona el último fotograma: mejor medio segundo congelado que medio
    #  vídeo corrido.
    tr = transicion_de(plan) if len(tramos) > 1 else None
    D = duraciones_transicion(tramos, tr) if tr else []
    plan_fundidos = plan
    if tr:
        #  El fundido a negro «en los cortes» y la transición son respuestas a
        #  la misma pregunta: con transición puesta, manda la transición.
        f = dict(plan.get("fundidos") or {})
        f["entre"] = 0
        plan_fundidos = dict(plan, fundidos=f)

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

        ext = D[i] if tr and i < len(tramos) - 1 else 0.0
        fin = clip["hasta"] + ext * v
        tope = float(fuente.get("dur", fin)) or fin
        recorte_fin = min(fin, tope) if ext > 0 else clip["hasta"]
        faltan = (b - a) + ext - (recorte_fin - clip["desde"]) / v
        relleno = ("tpad=stop_mode=clone:stop_duration=%.4f" % faltan) \
            if ext > 0 and faltan > 0.001 else ""

        #  El color va DENTRO de la normalización de cada trozo, o sea antes del
        #  `concat`: es del trozo y no de la línea, que es lo que hace falta para
        #  juntar dos grabaciones que no casan.
        #
        #  Y el fundido, el último de la cadena y sobre la duración de LÍNEA:
        #  después del `setpts` de la velocidad, un trozo de 8 s a 2× ocupa 4 y
        #  el fundido tiene que caber en esos 4.
        color = filtro_color(clip)
        fv, fa = filtros_fundido(i, len(tramos), b - a, plan_fundidos, clip)
        cadena = ",".join(x for x in (pts, norma, relleno, color, fv) if x)

        lineas.append(
            "[%d:v]trim=start=%.4f:end=%.4f,%s[v%d]"
            % (idx, clip["desde"], recorte_fin, cadena, i))
        lineas += rama_audio(i, idx, clip, fuente, b - a, fa, ext=ext)

    # ── 2. pegarlos: concat a secas, o el encadenado de la transición
    if len(tramos) == 1:
        lineas.append("[v0]null[base]")
        lineas.append("[a0]anull[mez]")
    elif tr:
        #  Cadena de xfade: el desplazamiento de cada uno es la suma de las
        #  duraciones NORMALES, así que la mezcla cae exactamente sobre la
        #  cola extendida y el siguiente trozo empieza donde siempre. El
        #  audio va igual con acrossfade, que consume la cola por su cuenta.
        off = 0.0
        vprev, aprev = "v0", "a0"
        for i in range(1, len(tramos)):
            off += tramos[i - 1][1] - tramos[i - 1][0]
            vs = "base" if i == len(tramos) - 1 else "tv%d" % i
            as_ = "mez" if i == len(tramos) - 1 else "ta%d" % i
            lineas.append(
                "[%s][v%d]xfade=transition=%s:duration=%.4f:offset=%.4f[%s]"
                % (vprev, i, tr["tipo"], D[i - 1], off, vs))
            lineas.append(
                "[%s][a%d]acrossfade=d=%.4f:c1=tri:c2=tri[%s]"
                % (aprev, i, D[i - 1], as_))
            vprev, aprev = vs, as_
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
        if tipo == "forma":
            #  Su PNG se dibujó al montar las entradas; si no pudo dibujarse
            #  —sin magick, sin carpeta— la capa se salta y el render sale.
            ruta_f = os.path.join(carpeta, nombre_forma(capa))
            if capa["id"] not in idx_capa or not os.path.exists(ruta_f):
                continue
            nuevas, entra = rama_capa(n, idx_capa[capa["id"]],
                                      dict(capa, ruta=ruta_f),
                                      ancho, alto, entra)
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

    if vertical:
        #  La salida 9:16 para Shorts: recorte centrado y a 1080×1920. Y el
        #  centro no es conformismo: cuando el zoom trabaja, zoompan ya ha
        #  dejado el sujeto clavado en el centro del fotograma, así que el
        #  recorte vertical sigue a la cámara GRATIS; sin zoom, el centro es
        #  lo razonable que haría cualquiera.
        wv = int(round(alto * 9.0 / 32.0)) * 2
        lineas.append("[%s]crop=%d:%d:(iw-%d)/2:0,"
                      "scale=1080:1920:flags=lanczos,setsar=1,"
                      "format=yuv420p[v]" % (entra, wv, alto, wv))
    else:
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
        #  La sonoridad, lo último de todo: −14 LUFS es lo que YouTube espera,
        #  y normalizar antes de la censura taparía sus propios silencios.
        #  `loudnorm` sale a 192 kHz por dentro —es su manera de medir— y el
        #  `aresample` lo devuelve a los 48 de la norma.
        lineas.append("[%s]%s[a]"
                      % (fin, "loudnorm=I=-14:TP=-1.5:LRA=11,aresample=48000"
                         if sonoridad else "anull"))

    return ";\n".join(lineas), len(puntos)


def suena(ruta):
    """Si un fichero trae flujo de audio.

    Hace falta preguntarlo antes de pedirle `[N:a]` a ffmpeg: un vídeo mudo
    —una grabación de pantalla sin micro, un gif convertido— no tiene esa
    entrada y el `filter_complex` entero se cae con «matches no streams». Un
    ffprobe por fichero y a la caché, que un plan puede traer la misma cámara
    en diez trozos.
    """
    if ruta in _CON_SONIDO:
        return _CON_SONIDO[ruta]
    hay = correr_sondeo(
        ["ffprobe"] + SIN_RED + ["-v", "error", "-select_streams", "a:0",
         "-show_entries", "stream=codec_name", "-of", "csv=p=0", ruta],
        capture_output=True, text=True).stdout.strip() != ""
    _CON_SONIDO[ruta] = hay
    return hay


_CON_SONIDO = {}


def capas_que_suenan(plan):
    """Las capas que aportan sonido: las de audio y los vídeos que lo pidan.

    Un vídeo incrustado entraba MUDO —su audio se tiraba— y para oírlo había
    que añadir el mismo fichero otra vez como capa de audio y cuadrarlo a mano.
    Ahora es un interruptor de la capa. Sigue siendo opcional y apagado en los
    planes viejos: un montaje hecho antes de esto suena igual que sonaba.

    Las dos clases se tratan igual a partir de aquí —recorte, volumen, retardo—
    porque para el oído son lo mismo; lo único propio del vídeo es preguntar si
    de verdad trae sonido.
    """
    salida = []
    for c in capas_de(plan, "audio"):
        #  Callada por su interruptor: no entra. Es distinto de ponerle el
        #  volumen a cero —que también callaría— porque así el volumen se
        #  conserva y volver a encenderla lo devuelve donde estaba, que es lo
        #  que hace falta para comparar el micro con el sistema a oído.
        if c.get("mudo"):
            continue
        if c.get("ruta") and os.path.exists(c["ruta"]):
            salida.append(c)
    for c in capas_de(plan, "video"):
        if not c.get("sonido"):
            continue
        if c.get("ruta") and os.path.exists(c["ruta"]) and suena(c["ruta"]):
            salida.append(c)
    #  En el orden de las capas del plan, no primero unas y luego otras: así el
    #  grafo se lee al lado de la lista del editor.
    salida.sort(key=lambda c: (float(c.get("t0", 0.0)), c.get("id", 0)))
    return salida


def pistas_vivas_de(plan, capa):
    """De qué pistas del fichero sale el sonido de una capa, por su número
    dentro del fichero (el `N` de `0:a:N`).

    Hasta ahora una capa se mapeaba `[N:a]` a secas, y eso NO es «el audio del
    fichero»: ffmpeg lo resuelve a la primera pista y se queda tan ancho. En
    una grabación de la casa la primera es la Mezcla —sistema y micro ya
    sumados—, que es justo la que el editor se salta al listar las pistas. O
    sea que «separar el audio» te devolvía las dos cosas juntas por la puerta
    de atrás, y silenciar una pista no callaba nada porque lo que sonaba venía
    por otro lado. Medido: `[0:a]` da byte a byte lo mismo que `[0:a:0]`.

    Con la pista dicha —lo que hace «separar el audio»— es esa y solo esa, y
    si está silenciada no suena: un silencio tiene que valer venga de donde
    venga. Sin decir nada, las que no estén mudas, mezcladas. Y de un fichero
    que el plan no conoce —una canción, un vídeo de fuera— la primera, que es
    lo que se hacía antes pero dicho a las claras.
    """
    fuente = None
    for f in plan.get("fuentes", []):
        if f.get("ruta") and f["ruta"] == capa.get("ruta"):
            fuente = f
            break
    pistas = (fuente or {}).get("pistas") or []

    if capa.get("pista") is not None:
        n = int(capa["pista"])
        for p in pistas:
            if int(p["i"]) == n:
                return [] if p.get("mudo") else [n]
        return [n]

    if not pistas:
        return [0]
    return [int(p["i"]) for p in pistas if not p.get("mudo")]


def ramas_audio_extra(plan, idx_capa, sin_audio):
    """Las capas de audio, mezcladas con el sonido del vídeo.

    Cada una entra con su volumen y a partir de su instante, y todas se suman al
    audio de la base. Si el fotograma que se pide es suelto —una previa— no hay
    audio que mapear y todo va a un sumidero: en un `filter_complex` una etiqueta
    que se produce y no se consume no es «se ignora», es un error que tumba la
    orden entera.
    """
    extras = [c for c in capas_que_suenan(plan) if c["id"] in idx_capa]
    #  Y fuera las que no tienen de dónde sonar: una capa de una pista que
    #  acabas de silenciar no aporta nada, y una rama que no produce etiqueta
    #  tumba el `amix` del final. Silenciar la pista apaga su capa, que es lo
    #  que uno espera al pulsar un botón que dice «silencio».
    extras = [c for c in extras if pistas_vivas_de(plan, c)]

    if sin_audio:
        # Ni se molestan en entrar: nadie va a escucharlas.
        return ["[mez]anullsink"]
    if not extras:
        return ["[mez]anull[amez]"]

    #  El agachado: una capa que baja sola cuando suena otra.
    #
    #  La llave era SIEMPRE la mezcla del vídeo —ahí va la voz de quien grabó—
    #  y no se podía elegir otra cosa. Con una locución puesta DESPUÉS, en su
    #  propia capa, la música no la oía y no se agachaba jamás: el agachado
    #  servía para lo que se grabó y no para lo que se montó. Ahora cada capa
    #  dice con qué se agacha en `llave`: vacío es el vídeo, como siempre, y si
    #  no, el id de otra capa que suene.
    #
    #  La llave es SIEMPRE la señal CRUDA de quien manda —antes de su propio
    #  agachado—, y eso es lo que hace imposible un bucle: A puede agacharse
    #  con B y B con A a la vez, porque ninguna de las dos llaves depende del
    #  agachado de nadie. Importa porque un grafo con un bucle no da un error
    #  claro: ffmpeg se queda colgado sin decir nada.
    por_id = {}
    for k, c in enumerate(extras):
        por_id[c["id"]] = k

    #  Con qué se agacha cada una: "video", o el índice de otra capa. Una capa
    #  que se nombra a sí misma, o que nombra a una que no está sonando —muda,
    #  su pista silenciada, borrada—, cae al vídeo: es lo que hacía antes y no
    #  deja a nadie sin agachado por un id viejo.
    llaves = {}
    for k, c in enumerate(extras):
        if not c.get("agachar"):
            continue
        j = por_id.get(c.get("llave"))
        llaves[k] = j if j is not None and j != k else "video"

    lineas, etiquetas = [], ["[mez]"]

    #  Repartir [mez] en copias: una para la mezcla y una por cada capa que se
    #  agacha CON EL VÍDEO, porque en un grafo cada etiqueta se consume una vez.
    con_video = sorted(k for k, v in llaves.items() if v == "video")
    if con_video:
        lineas.append("[mez]asplit=%d[mezv]%s"
                      % (1 + len(con_video),
                         "".join("[llave%d]" % k for k in con_video)))
        etiquetas = ["[mezv]"]

    #  Y quién le sirve de llave a quién, para repartir también su señal.
    clientes = {}
    for k, v in llaves.items():
        if v != "video":
            clientes.setdefault(v, []).append(k)

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
        #  La escoba: quitarle el ruido de fondo a ESTA capa.
        #
        #  Las pistas del vídeo ya la tenían (ver `ramas_audio`, el `limpia` por
        #  pista); las capas no, y son justo las que más la piden: una locución
        #  grabada con el micro de mesa lleva el aire de la habitación, y el
        #  audio separado de un trozo hereda el mismo soplido.
        #
        #  Mismo filtro y mismos números que allí —`nr=12` quita el aire sin
        #  comerse la voz— para que la capa suene igual venga de donde venga. Y
        #  ANTES del volumen, por lo mismo: se limpia el original y luego se
        #  sube lo limpio, no al revés.
        limpiar = FILTRO_ESCOBA + "," if capa.get("limpia") else ""

        recorte = capa.get("recorte") or []
        idx = idx_capa[capa["id"]]
        recortar = ""
        if len(recorte) == 2 and float(recorte[1]) > float(recorte[0]):
            recortar = ("atrim=start=%.4f:end=%.4f,asetpts=PTS-STARTPTS,"
                        % (float(recorte[0]), float(recorte[1])))

        #  De qué pista sale, DICHO. Ver `pistas_vivas_de`: `[N:a]` a secas se
        #  llevaba siempre la primera del fichero, que en una grabación de la
        #  casa es la Mezcla.
        vivas = pistas_vivas_de(plan, capa)
        if len(vivas) == 1:
            partes = ["[%d:a:%d]%s%s" % (idx, vivas[0], recortar, limpiar)]
        else:
            #  Varias: cada una se recorta por su cuenta y se suman antes de
            #  nada, que es como lo hace la rama de un trozo. El volumen, el
            #  retardo y el relleno van luego sobre la suma y no por pista:
            #  aplicarlos a cada una los aplicaría dos veces.
            trozos = []
            for j, n in enumerate(vivas):
                sub = "axp%d_%d" % (k, j)
                #  Se limpia cada pista por su cuenta y ANTES de sumarlas:
                #  denoise sobre una mezcla ya hecha tiene menos con qué
                #  distinguir el aire de lo que no lo es.
                lineas.append("[%d:a:%d]%s%s%s[%s]" % (idx, n, recortar,
                                                       limpiar, NORMA_AUDIO,
                                                       sub))
                trozos.append("[%s]" % sub)
            #  `normalize=0` por lo de siempre: sumar sin repartir, que si no
            #  el micro baja al mezclarlo con el sistema.
            lineas.append("%samix=inputs=%d:normalize=0[axm%d]"
                          % ("".join(trozos), len(trozos), k))
            partes = ["[axm%d]" % k]
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

        #  Si esta capa le sirve de llave a alguien, su señal se reparte igual
        #  que la del vídeo: una copia para oírse y una por cada capa que se
        #  agacha con ella. Se reparte la CRUDA, antes de su propio agachado.
        mios = sorted(clientes.get(k, []))
        if mios:
            lineas.append("[%s]asplit=%d[axs%d]%s"
                          % (et, 1 + len(mios), k,
                             "".join("[llave%d]" % j for j in mios)))
            et = "axs%d" % k

        if k in llaves:
            #  Umbral bajo y soltura lenta: baja en cuanto alguien habla y
            #  vuelve con calma, que es como lo hace un técnico y no una
            #  puerta. La llave no suena: solo manda.
            lineas.append(
                "[%s][llave%d]sidechaincompress=threshold=0.02:ratio=8:"
                "attack=80:release=600[axa%d]" % (et, k, k))
            et = "axa%d" % k
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
    p = correr_sondeo(
        ["ffprobe"] + SIN_RED + ["-v", "error", "-select_streams", "a",
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
        #  La mezcla NO es una pista más: es las otras dos sumadas, y existe
        #  solo para que un reproductor cualquiera suene al abrir el fichero.
        #  Aquí estorbaría —saldría en la lista y se oiría todo dos veces— así
        #  que se salta. El índice de las demás es el REAL, no el de la
        #  enumeración: el grafo mapea `0:a:<i>` y saltarse una sin más
        #  desplazaría todas las siguientes.
        if titulo.strip().lower() == "mezcla":
            continue
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
    p = correr_sondeo(
        ["ffprobe"] + SIN_RED + ["-v", "error", "-select_streams", "v:0",
         "-show_entries", "stream=width,height,r_frame_rate,duration",
         "-show_entries", "format=duration", "-of", "json", video],
        capture_output=True, text=True)
    d = json.loads(p.stdout)
    s = d["streams"][0]
    num, den = s["r_frame_rate"].split("/")
    hay_audio = correr_sondeo(
        ["ffprobe"] + SIN_RED + ["-v", "error", "-select_streams", "a:0",
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
    p = correr_sondeo(
        ["ffprobe"] + SIN_RED + ["-v", "error", "-select_streams", "v:0",
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


def revisar_rutas(plan, deDonde=""):
    """Ninguna ruta de dentro del plan puede ser otra cosa que un fichero.

    Un `.k4v` es JSON y viaja: te lo pasan por Telegram como te pasan un vídeo.
    Si una de sus `ruta` fuese `http://…`, abrirlo haría que tu máquina pidiese
    esa dirección —comprobado: un servidor local registró el GET— y eso convierte
    «abrir un proyecto» en «visitar lo que diga quien lo escribió».

    Aquí no se exige que el fichero EXISTA: un proyecto con un vídeo movido de
    sitio se abre igual y ya avisa cada sitio a su manera. Lo que se exige es
    que sea una ruta, no un protocolo.
    """
    malas = []
    for f in plan.get("fuentes", []):
        if f.get("ruta") and not es_local(f["ruta"]):
            malas.append(f["ruta"])
    for c in plan.get("capas", []):
        if c.get("ruta") and not es_local(c["ruta"]):
            malas.append(c["ruta"])
    if malas:
        salir(ok=False, motivo="fuera-del-disco",
              detalle=", ".join(malas[:3]))
    return plan


def cargar(ruta):
    """El plan de un fichero, ya en el modelo de ahora.

    Si venía en el viejo se reescribe al vuelo: migrar cuesta dos ffprobe y no
    tiene ninguna gracia pagarlos en cada arrastre del ratón.
    """
    plan = json.load(open(ruta))
    revisar_rutas(plan, ruta)
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
    if args.guardar:
        migrar_nombre(args.guardar)
    #  Dónde vive el plan de verdad, que desde que se pueden renombrar los
    #  proyectos ya no se deduce del nombre del vídeo. Se devuelve SIEMPRE, para
    #  que el editor guarde donde toca y no en el nombre de fábrica.
    guardar_en = plan_de_video(args.video, args.guardar) if args.guardar else ""
    if guardar_en and os.path.exists(guardar_en):
        plan = cargar(guardar_en)
        salir(ok=True, plan=guardar_en, **plan)
    plan = plan_nuevo(args.video, args.rastro, camara=args.camara,
                      desfase=args.desfase)
    if guardar_en:
        guardar(plan, guardar_en)
    salir(ok=True, plan=guardar_en, **plan)


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
    p = correr_sondeo(
        ["ffprobe"] + SIN_RED + ["-v", "error", "-select_streams", "v:0",
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
        #  Y si trae sonido: un vídeo incrustado puede sonar, y el editor no
        #  debe ofrecer subirle el volumen a una grabación muda.
        salir(ok=True, dur=dur, w=int(s["width"]), h=int(s["height"]),
              audio=suena(args.fichero))
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


_OPCION_GRAFO = []


def opcion_grafo():
    """Cómo se le dice a ffmpeg que el grafo está en un fichero.

    Era `-filter_complex_script`, y **en ffmpeg 9 esa opción ya no existe**:
    n9.0.1 contesta «Unrecognized option 'filter_complex_script'» y detrás un
    «Error splitting the argument list», que no se parece en nada a lo que pasa.
    Su relevo es el prefijo `-/opt` —«el valor de esta opción está en ese
    fichero»—, que existe desde la 7.0. Pasó aquí el 20 ago 2026, al actualizar
    el sistema: el editor dejó de renderizar de un día para otro sin que nadie
    tocara el editor.

    Se le PREGUNTA a ffmpeg en vez de mirar el número de versión: lo que hay que
    saber es si entiende la opción, no qué número se ha puesto. Y se pregunta
    una sola vez —cuesta unos 50 ms— porque un render la usa varias veces.
    """
    if not _OPCION_GRAFO:
        try:
            p = subprocess.run(["ffmpeg"] + SIN_RED + ["-hide_banner", "-h", "full"],
                               capture_output=True, text=True)
            viejo = "filter_complex_script" in p.stdout
        except OSError:
            viejo = False
        _OPCION_GRAFO.append("-filter_complex_script" if viejo
                             else "-/filter_complex")
    return _OPCION_GRAFO[0]


def escribir_grafo(plan, ruta_plan, sin_audio=False, nombre="grafo.txt",
                   sonoridad=False, vertical=False):
    """El grafo a un fichero, y la ruta del fichero.

    En un fichero y no en la línea de órdenes: el límite no es `ARG_MAX` sino
    `MAX_ARG_STRLEN`, **128 KB por argumento suelto**, y con unos cientos de
    tramos en la expresión de la cámara eso se alcanza. Falla con un «Argument
    list too long» que no dice nada de lo que pasa de verdad. Cómo se le nombra
    el fichero a ffmpeg lo decide `opcion_grafo()`, que cambió en ffmpeg 9.

    De regalo, el grafo se queda en disco: cuando un render falle, ahí está lo
    que se le pidió a ffmpeg, tal cual.
    """
    #  El plan es `<vídeo>.k4v` y su carpeta adjunta es `<vídeo>.k4/`, así
    #  que solo hay que quitarle la última letra. Con `splitext` + ".k4" salía
    #  `<vídeo>.k4.k4`, que funcionaba pero era un sitio que nadie esperaba.
    carpeta = carpeta_de(ruta_plan)
    os.makedirs(carpeta, exist_ok=True)
    texto, nodos = grafo(plan, sin_audio, carpeta, sonoridad=sonoridad,
                         vertical=vertical)
    ruta = os.path.join(carpeta, nombre)
    with open(ruta, "w") as f:
        f.write(texto)
    return ruta, nodos


def a_linea(tramos, ts, id_fuente):
    """Un instante del FICHERO llevado a la línea, o None si quedó cortado."""
    for a, b, clip, fuente in tramos:
        if fuente["id"] != id_fuente:
            continue
        if clip["desde"] - 1e-6 <= ts <= clip["hasta"] + 1e-6:
            return a + (ts - clip["desde"]) / velocidad_de(clip)
    return None


def tiempo_srt(t):
    ms = int(round(max(0.0, t) * 1000))
    return "%02d:%02d:%02d,%03d" % (ms // 3600000, ms // 60000 % 60,
                                    ms // 1000 % 60, ms % 1000)


def escribir_srt(plan, ruta):
    """La transcripción a un SRT, en tiempo de LÍNEA. La ruta, o None.

    Los segmentos vienen en tiempo del fichero ORIGINAL, y el vídeo puede
    estar cortado, reordenado y acelerado: cada uno pasa por el mapa. El que
    cayó en un trozo quitado no sale — unos subtítulos de algo que ya no se
    dice serían mentira— y el que quedó a caballo de un corte sale solo si
    sus dos extremos siguen en pie, que es la regla que se puede predecir.
    """
    segs = plan.get("transcripcion") or []
    if not segs or not plan.get("fuentes"):
        return None
    tramos = mapa(plan)
    idf = plan["fuentes"][0]["id"]
    piezas, n = [], 0
    for s in segs:
        texto = str(s.get("texto", "")).strip()
        t0 = a_linea(tramos, float(s.get("t0", 0)), idf)
        t1 = a_linea(tramos, float(s.get("t1", 0)), idf)
        if not texto or t0 is None or t1 is None or t1 - t0 < 0.05:
            continue
        n += 1
        piezas.append("%d\n%s --> %s\n%s\n"
                      % (n, tiempo_srt(t0), tiempo_srt(t1), texto))
    if not piezas:
        return None
    with open(ruta, "w") as f:
        f.write("\n".join(piezas))
    return ruta


def orden_render(args):
    plan = cargar(args.plan)
    duracion = duracion_linea(plan)
    rutas, _, _, _ = entradas(plan, carpeta_de(args.plan))
    ruta_grafo, nodos = escribir_grafo(
        plan, args.plan, sonoridad=getattr(args, "sonoridad", False),
        vertical=getattr(args, "vertical", False))

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
        orden = (["ffmpeg"] + SIN_RED + ["-v", "error", "-y"] + abrir_entradas(plan, rutas)
                 + [opcion_grafo(), ruta_grafo, "-map", "[gif]",
                    "-loop", "0",
                    "-progress", "pipe:1", "-nostats", args.salida])
    elif formato == "webm":
        orden = (["ffmpeg"] + SIN_RED + ["-v", "error", "-y"] + abrir_entradas(plan, rutas)
                 + [opcion_grafo(), ruta_grafo,
                    "-map", "[v]", "-map", "[a]",
                    #  `row-mt` y `-cpu-used 4`: vp9 sin eso tarda tanto que
                    #  nadie espera a que acabe. La calidad se nota poco.
                    "-c:v", "libvpx-vp9", "-crf", "32", "-b:v", "0",
                    "-row-mt", "1", "-cpu-used", "4",
                    "-c:a", "libopus", "-b:a", "128k",
                    "-progress", "pipe:1", "-nostats", args.salida])
    else:
        orden = ["ffmpeg"] + SIN_RED + ["-v", "error", "-y"] + abrir_entradas(plan, rutas)
        orden += [opcion_grafo(), ruta_grafo,
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

    #  Si hay transcripción, el SRT sale AL LADO del fichero, con su mismo
    #  nombre: es lo que YouTube pide subir y nadie debería ir a buscarlo a
    #  la carpeta adjunta. Un GIF no lleva subtítulos que valgan.
    srt = None
    if formato != "gif":
        srt = escribir_srt(plan, args.salida.rsplit(".", 1)[0] + ".srt")
    salir(ok=True, estado="fin", ruta=args.salida, srt=srt or "")


def sacar_fotograma(plan, ruta_plan, t, destino):
    """Un fotograma de la LÍNEA a un PNG. True si salió."""
    carpeta = carpeta_de(ruta_plan)
    rutas, _, _, _ = entradas(plan, carpeta)
    ruta_grafo, _ = escribir_grafo(plan, ruta_plan, sin_audio=True,
                                   nombre="grafo-congelar.txt")
    orden = (["ffmpeg"] + SIN_RED + ["-v", "error", "-y"] + abrir_entradas(plan, rutas)
             + [opcion_grafo(), ruta_grafo, "-map", "[v]",
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


def orden_limpiar(args):
    """La copia del audio que oye la previa: sin ruido y/o amplificada.

    Existe porque hay dos cosas que Qt no sabe hacer mientras reproduce, y las
    dos hacen falta para poder DECIDIR oyendo:

    - filtrar (la escoba), y
    - **subir de 100 %**: `AudioOutput.volume` se recorta en 1 y por encima no
      sube ni un decibelio. Medido: pedirle 3,0 deja la propiedad en 1 y el
      sonido exactamente igual. Así que la ganancia que pasa del 100 % se mete
      aquí, en el fichero, y Qt reproduce esa copia a volumen 1.

    El render no usa esta copia: aplica `FILTRO_ESCOBA` y su `volume=` sobre el
    original. Los dos salen de la misma constante y de la misma cuenta, así que
    lo que oyes es lo que va a salir.

    Sale una pista sola —la que se pide— y por eso el fichero limpio se
    reproduce siempre por su pista 0: al reencodearlo, la numeración de dentro
    ya no es la del original.

    La duración NO cambia, y eso no es un detalle: la previa coloca el fichero
    por el instante de la línea, así que un limpio más corto o más largo que su
    original desharía el recorte y la colocación de la capa.
    """
    if not os.path.exists(args.fichero):
        salir(ok=False, motivo="sin-fichero")
    #  Antes de crear un solo directorio: el `makedirs` de abajo obedece a los
    #  `..` que traiga el nombre, así que comprobar después sería comprobar
    #  cuando ya has hecho carpetas donde no tocaba.
    if args.dentro:
        exigir_dentro(args.dentro, args.salida)
    carpeta = os.path.dirname(args.salida)
    if carpeta:
        os.makedirs(carpeta, exist_ok=True)
    #  FLAC y no AAC, y no es por purismo: lo que se va a juzgar oyendo esto
    #  es si el filtro deja bien la voz. Con un códec con pérdida encima, parte
    #  de lo que oirías serían sus artefactos y no los del filtro — estarías
    #  decidiendo sobre otra cosa. Sale unas tres veces más grande y se tarda
    #  la mitad en hacerlo, así que tampoco cuesta nada.
    #  El filtro: la escoba si se pide, y la ganancia si pasa de 1. Si no
    #  pasa, NO se mete: de 0 a 100 % lo hace Qt en el momento, que es
    #  instantáneo, y hacer una copia por cada tirón del deslizador sería
    #  cambiar algo que ya va bien por algo que tarda.
    cadena = []
    if args.escoba:
        cadena.append(FILTRO_ESCOBA)
    if float(args.ganancia) > 1.0:
        cadena.append("volume=%.3f" % float(args.ganancia))
    if not cadena:
        salir(ok=False, motivo="nada-que-hacer")

    orden = ["ffmpeg"] + SIN_RED + ["-v", "error", "-y", "-i", args.fichero,
             "-map", "0:a:%d" % max(0, int(args.pista)),
             "-af", ",".join(cadena), "-c:a", "flac",
             "-compression_level", "5", "-vn", args.salida]
    try:
        p = subprocess.run(orden, capture_output=True, text=True)
    except OSError:
        salir(ok=False, motivo="sin-ffmpeg")
    if p.returncode != 0 or not os.path.exists(args.salida):
        salir(ok=False, motivo=(p.stderr or "").strip()[:200] or "limpiar")

    #  Fuera las copias viejas de esta misma capa. Mover el deslizador del
    #  volumen hace una copia por cada valor que se suelte, y sin esto la
    #  carpeta del proyecto se llenaba de versiones que ya no oye nadie.
    #  Se borra DESPUÉS de que la nueva exista, no antes: si el ffmpeg falla,
    #  la de antes sigue ahí y se sigue oyendo algo.
    if args.prefijo:
        quedarse = os.path.basename(args.salida)
        for f in os.listdir(carpeta or "."):
            if f.startswith(args.prefijo) and f != quedarse:
                try:
                    os.remove(os.path.join(carpeta or ".", f))
                except OSError:
                    pass
    salir(ok=True, ruta=args.salida)


def orden_niveles(args):
    """Cuánto suena cada pista del vídeo: pico y media, en dB.

    Con `volumedetect`, pista a pista y sin vídeo: decodificar solo el audio
    va sobrado de rápido, y es lo que hace falta para saber si el micro
    satura ANTES de descubrirlo en el render.
    """
    salida = []
    for p in pistas_audio(args.video):
        pr = subprocess.run(
            ["ffmpeg"] + SIN_RED + ["-v", "info", "-i", args.video,
             "-map", "0:a:%d" % p["i"], "-af", "volumedetect",
             "-vn", "-f", "null", "-"],
            capture_output=True, text=True)
        pico, media = None, None
        for linea in pr.stderr.splitlines():
            if "max_volume:" in linea:
                try:
                    pico = float(linea.split("max_volume:")[1]
                                 .replace("dB", "").strip())
                except ValueError:
                    pass
            elif "mean_volume:" in linea:
                try:
                    media = float(linea.split("mean_volume:")[1]
                                  .replace("dB", "").strip())
                except ValueError:
                    pass
        if pico is not None:
            salida.append({"i": p["i"], "pico": pico, "media": media})
    salir(ok=True, pistas=salida)


def orden_miniatura(args):
    """El fotograma bajo el cabezal, a un PNG a resolución completa.

    Con todo puesto —zoom, capas, rótulos—, que para eso es el mismo grafo
    del render. Numerada si ya hay una: quien hace miniaturas suele hacer
    tres y quedarse con la mejor.
    """
    plan = cargar(args.plan)
    if not plan.get("fuentes"):
        salir(ok=False, motivo="sin-fuentes")
    base = plan["fuentes"][0]["ruta"].rsplit(".", 1)[0] + "-miniatura"
    destino, n = base + ".png", 2
    while os.path.exists(destino):
        destino = "%s-%d.png" % (base, n)
        n += 1
    if not sacar_fotograma(plan, args.plan, max(0.0, args.t), destino):
        salir(ok=False, motivo="fallo")
    salir(ok=True, ruta=destino)


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

    orden = ["ffmpeg"] + SIN_RED + ["-hide_banner", "-y"] + abrir_entradas(plan, rutas)
    #  Solo el audio: descodificar el vídeo para tirarlo es tiempo regalado, y
    #  aquí se está esperando a que conteste para poder cortar.
    orden += [opcion_grafo(), ruta_grafo, "-map", "[adet]",
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

    orden = ["ffmpeg"] + SIN_RED + ["-v", "error", "-y"] + abrir_entradas(plan, rutas)
    # `-ss` como opción de SALIDA, después del grafo. Delante del `-i` ffmpeg
    # pone los tiempos a cero y todas las expresiones, que van en tiempo de
    # línea, apuntarían al sitio equivocado.
    orden += [opcion_grafo(), ruta_grafo, "-map", "[v]",
              "-ss", str(args.t), "-frames:v", "1", args.salida]

    p = subprocess.run(orden, capture_output=True, text=True)
    if p.returncode != 0:
        salir(ok=False, motivo="fallo", detalle=p.stderr.strip()[:200])
    salir(ok=True, ruta=args.salida)


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="orden", required=True)

    e = sub.add_parser("abrir")
    e.add_argument("video")
    e.add_argument("--rastro", default="")
    e.add_argument("--guardar", default="")
    e.add_argument("--camara", default="")
    e.add_argument("--desfase", type=float, default=0.0)

    o = sub.add_parser("onda")
    o.add_argument("fichero")
    o.add_argument("--pista", type=int, default=0)
    o.add_argument("--puntos", type=int, default=400)

    r = sub.add_parser("renombrar")
    r.add_argument("plan")
    r.add_argument("nombre")

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
    b.add_argument("--sonoridad", action="store_true",
                   help="normalizar a -14 LUFS, lo que espera YouTube")
    b.add_argument("--vertical", action="store_true",
                   help="salida 9:16 a 1080x1920, para Shorts")

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

    mi = sub.add_parser("miniatura")
    mi.add_argument("plan")
    mi.add_argument("t", type=float)

    nv = sub.add_parser("niveles")
    nv.add_argument("video")

    lp = sub.add_parser("limpiar")
    lp.add_argument("fichero")
    lp.add_argument("salida")
    lp.add_argument("--pista", type=int, default=0)
    lp.add_argument("--escoba", action="store_true")
    lp.add_argument("--ganancia", type=float, default=1.0)
    lp.add_argument("--prefijo", default="")
    #  La carpeta de la que la salida no puede salir. Esta orden es la única
    #  cuyo destino NO elige una persona en un diálogo: lo compone el editor
    #  con el id de la capa dentro. Un id con `../` dentro sacaba el fichero
    #  de la carpeta del proyecto — comprobado. Quien llama dice aquí hasta
    #  dónde llega, y si el nombre se escapa, no se escribe.
    lp.add_argument("--dentro", default="")

    args = ap.parse_args()

    #  Todo lo que llega por la línea de órdenes y suena a ruta, revisado en un
    #  solo sitio. Repartir los `if` por las doce `orden_*` es como se olvida
    #  uno: aquí basta con no quitar el nombre de la lista.
    for cual in ("video", "fichero", "plan", "rastro", "camara"):
        v = getattr(args, cual, "")
        if v:
            exigir_local(v, cual)
    #  Las salidas todavía no existen, pero tampoco pueden ser un protocolo.
    for cual in ("salida", "guardar"):
        v = getattr(args, cual, "")
        if v and not es_local(v):
            salir(ok=False, motivo="no-es-local", que=cual, detalle=str(v))

    {"abrir": orden_abrir, "renombrar": orden_renombrar, "onda": orden_onda,
     "proponer": orden_proponer, "render": orden_render,
     "previa": orden_previa, "camara": orden_camara,
     "silencios": orden_silencios, "congelar": orden_congelar,
     "medir": orden_medir, "miniatura": orden_miniatura,
     "niveles": orden_niveles, "limpiar": orden_limpiar}[args.orden](args)


if __name__ == "__main__":
    try:
        main()
    except (KeyboardInterrupt, BrokenPipeError):
        sys.exit(0)
