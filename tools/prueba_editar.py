#!/usr/bin/env python3
"""Las cuentas del editor, comprobadas sin tocar ffmpeg.

    python3 tools/prueba_editar.py

Aquí solo se prueba lo que es aritmética pura: el mapa entre los dos ejes de
tiempo y el grafo que sale de él. Es justo donde van a salir los fallos, y son
de los que no se ven mirando: un rótulo tres segundos corrido, un zoom que
apunta al trozo de al lado. Un render tarda un minuto y encima tapa el
problema; esto tarda cero.
"""
import sys, os, tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import editar


fallos = []

#  Ficheros de mentira para las capas.
#
#  `grafo()` comprueba que el fichero de una capa exista antes de meterla, así
#  que las pruebas necesitan que existan. Se los crea ella y en su propio sitio:
#  depender de que haya un PNG en /tmp haría que pasaran aquí y fallaran en
#  cualquier otra máquina, que es la peor clase de prueba.
BORRADOR = tempfile.mkdtemp(prefix="k4-prueba-")


def fichero(nombre):
    ruta = os.path.join(BORRADOR, nombre)
    if not os.path.exists(ruta):
        open(ruta, "wb").close()
    return ruta


def igual(que, es, deberia):
    if es != deberia:
        fallos.append("%s\n      es: %r\n  debería: %r" % (que, es, deberia))


def cerca(que, es, deberia, tol=0.001):
    if abs(es - deberia) > tol:
        fallos.append("%s\n      es: %r\n  debería: %r" % (que, es, deberia))


def plan(clips, fuentes=None):
    """Un plan de mentira, sin ficheros de verdad detrás."""
    return {
        "version": 2, "w": 1920, "h": 1080, "fps": 30.0,
        "fuentes": fuentes or [
            {"id": 1, "ruta": "/tmp/a.mp4", "rastro": "", "w": 1920, "h": 1080,
             "fps": 30.0, "dur": 20.0,
             "pistas": [{"i": 0, "titulo": "Sistema", "volumen": 1.0,
                         "mudo": False}]}],
        "clips": clips, "momentos": [], "capas": []}


# ── el mapa ───────────────────────────────────────────────────────
def prueba_mapa_simple():
    tramos = editar.mapa(plan([{"id": 1, "fuente": 1, "desde": 0, "hasta": 8}]))
    igual("un clip entero: un tramo", len(tramos), 1)
    cerca("empieza en cero", tramos[0][0], 0.0)
    cerca("dura lo que dura", tramos[0][1], 8.0)


def prueba_mapa_cortado_y_reordenado():
    """El caso que da nombre a la etapa: cortar y mover un trozo al final."""
    p = plan([{"id": 1, "fuente": 1, "desde": 0,  "hasta": 5},
              {"id": 3, "fuente": 1, "desde": 12, "hasta": 14},
              {"id": 2, "fuente": 1, "desde": 5,  "hasta": 9}])
    tramos = editar.mapa(p)

    igual("tres trozos", len(tramos), 3)
    cerca("la línea dura la suma", tramos[-1][1], 5 + 2 + 4)

    # Los tramos van pegados: sin huecos y sin solapes.
    for i in range(1, len(tramos)):
        cerca("tramo %d pegado al anterior" % i, tramos[i][0], tramos[i - 1][1])

    # Y ahora lo que de verdad importa: qué se ve en cada instante.
    casos = [
        (0.0,  0.0),      # principio del primer trozo
        (4.9,  4.9),      # justo antes del primer corte
        (5.0,  12.0),     # el segundo trozo empieza en el 12 del fichero
        (6.9,  13.9),     # justo antes del segundo corte
        (7.0,  5.0),      # el tercero empieza en el 5
        (10.9, 8.9),      # último instante
    ]
    for t, esperado in casos:
        _, ts = editar.donde(tramos, t)
        cerca("línea %.1f cae en fuente %.1f" % (t, esperado), ts, esperado)


def prueba_mapa_pasado_el_final():
    """Preguntar más allá del final no puede reventar: el cabezal llega ahí."""
    tramos = editar.mapa(plan([{"id": 1, "fuente": 1, "desde": 2, "hasta": 6}]))
    _, ts = editar.donde(tramos, 99.0)
    cerca("pasado el final se queda en el último fotograma", ts, 6.0)

    igual("sin clips no hay tramos", editar.mapa(plan([])), [])
    igual("sin tramos no hay fuente", editar.donde([], 3.0)[0], None)


def prueba_mapa_clip_vacio():
    """Un corte justo en el borde deja un clip de duración cero."""
    p = plan([{"id": 1, "fuente": 1, "desde": 0, "hasta": 4},
              {"id": 2, "fuente": 1, "desde": 4, "hasta": 4},
              {"id": 3, "fuente": 1, "desde": 4, "hasta": 7}])
    tramos = editar.mapa(p)
    igual("el clip vacío no entra", len(tramos), 2)
    cerca("y no deja hueco", tramos[-1][1], 7.0)


def prueba_velocidad_encoge_la_linea():
    p = plan([{"id": 1, "fuente": 1, "desde": 0, "hasta": 8, "velocidad": 2.0}])
    tramos = editar.mapa(p)
    cerca("8 s a 2x ocupan 4 de línea", tramos[0][1], 4.0)
    cerca("y el segundo 1 de línea es el 2 del fichero",
          editar.donde(tramos, 1.0)[1], 2.0)


def prueba_velocidad_estira_la_linea():
    p = plan([{"id": 1, "fuente": 1, "desde": 0, "hasta": 8, "velocidad": 0.5}])
    tramos = editar.mapa(p)
    cerca("8 s a la mitad ocupan 16", tramos[0][1], 16.0)
    cerca("el segundo 4 de línea es el 2 del fichero",
          editar.donde(tramos, 4.0)[1], 2.0)


def prueba_velocidad_mezclada():
    """Lo que de verdad se rompería: velocidades distintas y un corte en medio."""
    p = plan([{"id": 1, "fuente": 1, "desde": 0,  "hasta": 4},
              {"id": 2, "fuente": 1, "desde": 10, "hasta": 14, "velocidad": 4.0},
              {"id": 3, "fuente": 1, "desde": 4,  "hasta": 6,  "velocidad": 0.5}])
    tramos = editar.mapa(p)
    cerca("la línea suma 4 + 1 + 4", tramos[-1][1], 9.0)
    for i in range(1, len(tramos)):
        cerca("tramo %d pegado" % i, tramos[i][0], tramos[i - 1][1])

    casos = [(0.0, 0.0), (3.9, 3.9),          # el primero, a velocidad normal
             (4.0, 10.0), (4.5, 12.0),        # el segundo va cuatro veces más
             (5.0, 4.0), (7.0, 5.0)]          # el tercero, a la mitad
    for t, esperado in casos:
        cerca("línea %.1f → fichero %.1f" % (t, esperado),
              editar.donde(tramos, t)[1], esperado)


def prueba_velocidad_ida_y_vuelta():
    """donde() tiene que ser la inversa exacta de mapa(), no una aproximación."""
    p = plan([{"id": 1, "fuente": 1, "desde": 2, "hasta": 9, "velocidad": 1.7}])
    tramos = editar.mapa(p)
    a, b, clip, _ = tramos[0]
    for k in range(11):
        t = a + (b - a) * k / 10.0
        ts = editar.donde(tramos, min(t, b - 1e-6))[1]
        # De vuelta a la línea a mano, que es lo que hace mapa() al revés.
        vuelta = a + (ts - clip["desde"]) / editar.velocidad_de(clip)
        cerca("ida y vuelta en %.2f" % t, vuelta, min(t, b - 1e-6), tol=0.01)


def prueba_velocidad_disparatada_no_rompe():
    for v, espera in ((0, 1.0), (-3, 0.25), (99, 4.0), ("x", 1.0), (None, 1.0)):
        igual("velocidad %r se acota" % v,
              editar.velocidad_de({"velocidad": v}), espera)


def prueba_atempo_se_encadena_por_debajo_de_medio():
    igual("1x no pone nada", editar.cadena_atempo(1.0), "")
    igual("0,5x cabe en uno", editar.cadena_atempo(0.5), "atempo=0.500000")
    #  Una sola instancia solo baja a 0,5: con 0,25 ffmpeg contesta «Numerical
    #  result out of range» y se lleva por delante la orden entera.
    igual("0,25x necesita dos", editar.cadena_atempo(0.25),
          "atempo=0.500000,atempo=0.500000")
    for v in (0.25, 0.3, 0.4, 0.75, 1.5, 4.0):
        producto = 1.0
        for trozo in editar.cadena_atempo(v).split(","):
            if trozo:
                producto *= float(trozo.split("=")[1])
        cerca("la cadena de %.2f multiplica a %.2f" % (v, v), producto, v)


def prueba_velocidad_en_el_grafo():
    p = plan([{"id": 1, "fuente": 1, "desde": 0, "hasta": 8, "velocidad": 2.0}])
    g, _ = editar.grafo(p)
    igual("el vídeo divide los PTS",
          "setpts=(PTS-STARTPTS)/2.000000" in g, True)
    igual("el audio pasa por atempo", "atempo=2.000000" in g, True)
    igual("y no por asetrate, que cambiaría el tono", "asetrate" in g, False)

    normal, _ = editar.grafo(plan([{"id": 1, "fuente": 1,
                                    "desde": 0, "hasta": 8}]))
    igual("sin velocidad no se ensucia el grafo", "atempo" in normal, False)
    igual("y el setpts se queda como estaba",
          "setpts=PTS-STARTPTS," in normal, True)


def prueba_dos_fuentes():
    p = plan([{"id": 1, "fuente": 1, "desde": 0, "hasta": 3},
              {"id": 2, "fuente": 2, "desde": 1, "hasta": 5}],
             fuentes=[
                 {"id": 1, "ruta": "/tmp/a.mp4", "rastro": "", "w": 1920,
                  "h": 1080, "fps": 30.0, "dur": 20.0, "pistas": []},
                 {"id": 2, "ruta": "/tmp/b.mp4", "rastro": "", "w": 1280,
                  "h": 720, "fps": 25.0, "dur": 10.0, "pistas": []}])
    tramos = editar.mapa(p)
    igual("el primer tramo es de la fuente 1", tramos[0][3]["id"], 1)
    igual("el segundo, de la 2", tramos[1][3]["id"], 2)

    f, ts = editar.donde(tramos, 4.0)
    igual("el segundo 4 de la línea es de la fuente 2", f["id"], 2)
    cerca("y es el segundo 2 de ese fichero", ts, 2.0)


# ── llevar el rastro al lienzo ────────────────────────────────────
def prueba_a_lienzo():
    misma = {"w": 1920, "h": 1080}
    x, y = editar.a_lienzo(misma, 800, 400, 1920, 1080)
    cerca("misma resolución: no se toca (x)", x, 800.0)
    cerca("misma resolución: no se toca (y)", y, 400.0)

    #  Un 720p dentro de un lienzo 1080p: escala 1,5 y sin banda, porque la
    #  proporción coincide.
    menor = {"w": 1280, "h": 720}
    x, y = editar.a_lienzo(menor, 640, 360, 1920, 1080)
    cerca("centro de un 720p va al centro (x)", x, 960.0)
    cerca("centro de un 720p va al centro (y)", y, 540.0)

    #  Un 4:3 dentro de un 16:9: entra por altura y sobra banda a los lados.
    cuadrado = {"w": 1440, "h": 1080}
    x, y = editar.a_lienzo(cuadrado, 0, 0, 1920, 1080)
    cerca("la banda negra desplaza la esquina", x, 240.0)
    cerca("pero no en vertical", y, 0.0)


# ── el grafo ──────────────────────────────────────────────────────
def prueba_grafo_una_entrada_por_fichero():
    p = plan([{"id": 1, "fuente": 1, "desde": 0,  "hasta": 5},
              {"id": 2, "fuente": 1, "desde": 12, "hasta": 14}])
    rutas, idx, _, _ = editar.entradas(p)
    igual("el mismo fichero se abre una vez", rutas, ["/tmp/a.mp4"])
    igual("y todos los clips apuntan a esa entrada", idx[1], 0)


def prueba_grafo_concatena():
    p = plan([{"id": 1, "fuente": 1, "desde": 0,  "hasta": 5},
              {"id": 2, "fuente": 1, "desde": 12, "hasta": 14},
              {"id": 3, "fuente": 1, "desde": 5,  "hasta": 9}])
    texto, _ = editar.grafo(p)

    # `]trim=` y no `trim=` a secas: `atrim=` también lo contiene.
    igual("un trim de vídeo por trozo", texto.count("]trim=start="), 3)
    igual("y un atrim por trozo", texto.count("]atrim=start="), 3)
    igual("concat de tres", "concat=n=3:v=1:a=1[base][mez]" in texto, True)
    igual("el zoom va sobre lo ya pegado", "[base]zoompan=" in texto, True)
    igual("y las capas irían después", texto.index("concat=") < texto.index("zoompan="), True)
    igual("salen las dos etiquetas finales",
          "[v]" in texto and "[a]" in texto, True)


def prueba_grafo_rellena_el_silencio():
    """Una fuente sin pistas tiene que traer su silencio, o concat no arranca."""
    p = plan([{"id": 1, "fuente": 1, "desde": 0, "hasta": 4},
              {"id": 2, "fuente": 2, "desde": 0, "hasta": 3}],
             fuentes=[
                 {"id": 1, "ruta": "/tmp/a.mp4", "rastro": "", "w": 1920,
                  "h": 1080, "fps": 30.0, "dur": 20.0,
                  "pistas": [{"i": 0, "titulo": "", "volumen": 1.0,
                              "mudo": False}]},
                 {"id": 2, "ruta": "/tmp/b.mp4", "rastro": "", "w": 1920,
                  "h": 1080, "fps": 30.0, "dur": 10.0, "pistas": []}])
    texto, _ = editar.grafo(p)
    igual("hay relleno de silencio", "anullsrc" in texto, True)
    igual("y dura lo que el trozo", "atrim=0:3.0000" in texto, True)


def prueba_grafo_pista_muda():
    p = plan([{"id": 1, "fuente": 1, "desde": 0, "hasta": 4}],
             fuentes=[
                 {"id": 1, "ruta": "/tmp/a.mp4", "rastro": "", "w": 1920,
                  "h": 1080, "fps": 30.0, "dur": 20.0,
                  "pistas": [{"i": 0, "titulo": "S", "volumen": 1.0,
                              "mudo": False},
                             {"i": 1, "titulo": "M", "volumen": 0.5,
                              "mudo": True}]}])
    texto, _ = editar.grafo(p)
    igual("la muda no entra", "[0:a:1]" in texto, False)
    igual("y la que queda no se mezcla consigo misma",
          "amix" in texto, False)


def prueba_grafo_volumen():
    p = plan([{"id": 1, "fuente": 1, "desde": 0, "hasta": 4}],
             fuentes=[
                 {"id": 1, "ruta": "/tmp/a.mp4", "rastro": "", "w": 1920,
                  "h": 1080, "fps": 30.0, "dur": 20.0,
                  "pistas": [{"i": 0, "titulo": "S", "volumen": 0.4,
                              "mudo": False},
                             {"i": 1, "titulo": "M", "volumen": 1.6,
                              "mudo": False}]}])
    texto, _ = editar.grafo(p)
    igual("cada pista con su volumen", "volume=0.400" in texto
          and "volume=1.600" in texto, True)
    igual("y se mezclan sin normalizar", "amix=inputs=2:normalize=0" in texto, True)


# ── las capas ─────────────────────────────────────────────────────
def capa(**campos):
    d = {"id": 1, "tipo": "imagen", "ruta": fichero("logo.png"), "t0": 2.0,
         "t1": 4.0, "x": 0.5, "y": 0.5, "escala": 0.25, "opacidad": 1.0, "banda": 1}
    d.update(campos)
    return d


def con_capas(capas):
    p = plan([{"id": 1, "fuente": 1, "desde": 0, "hasta": 8}])
    p["capas"] = capas
    return p


def prueba_capas_van_despues_del_zoom():
    """Si fueran antes, el zoom ampliaría también el logo y se lo comería."""
    p = con_capas([capa()])
    texto, _ = editar.grafo(p)
    igual("hay overlay", "overlay=" in texto, True)
    igual("y va después del zoompan",
          texto.index("zoompan=") < texto.index("overlay="), True)


def prueba_capas_en_orden_de_lista():
    """Dentro de una banda, el orden de la lista es el de apilado."""
    p = con_capas([capa(id=2, ruta=fichero("abajo.png")),
                   capa(id=1, ruta=fichero("arriba.png"))])
    texto, _ = editar.grafo(p)
    igual("la primera de la lista se encadena primero",
          texto.index("ov0") < texto.index("ov1"), True)
    rutas, _, de_capa, _ = editar.entradas(p)
    igual("y es la de abajo", rutas[de_capa[2]], fichero("abajo.png"))

    # Y al revés, para que no pase por casualidad.
    q = con_capas([capa(id=1, ruta=fichero("arriba.png")),
                   capa(id=2, ruta=fichero("abajo.png"))])
    rutas, _, de_capa, _ = editar.entradas(q)
    igual("dando la vuelta a la lista, cambia quién va debajo",
          rutas[de_capa[1]], fichero("arriba.png"))


def prueba_bandas_manda_la_banda():
    """La banda pesa más que el orden de la lista: es lo que se apila."""
    p = con_capas([capa(id=1, banda=3, ruta=fichero("arriba.png")),
                   capa(id=2, banda=1, ruta=fichero("abajo.png"))])
    orden = [c["id"] for c in editar.capas_de(p)]
    igual("la banda 1 va debajo aunque esté después en la lista", orden, [2, 1])

    rutas, _, de_capa, _ = editar.entradas(p)
    igual("y es la que se abre primero",
          rutas[de_capa[2]], fichero("abajo.png"))


def prueba_bandas_conserva_el_orden_dentro():
    """Dos en la misma banda: manda la lista, porque `sorted` es estable."""
    p = con_capas([capa(id=7, banda=2, ruta=fichero("abajo.png")),
                   capa(id=8, banda=2, ruta=fichero("arriba.png")),
                   capa(id=9, banda=1, ruta=fichero("logo.png"))])
    igual("primero la banda 1 y luego la 2 en su orden",
          [c["id"] for c in editar.capas_de(p)], [9, 7, 8])


def prueba_bandas_los_planes_viejos_no_se_mueven():
    """Sin `banda` todas caen en la 1, y ahí manda el orden de la lista.

    Es lo que hace que no haya que migrar nada: un plan de antes de que
    existieran las bandas se apila exactamente igual que antes.
    """
    viejas = [capa(id=1, ruta=fichero("abajo.png")),
              capa(id=2, ruta=fichero("logo.png")),
              capa(id=3, ruta=fichero("arriba.png"))]
    for c in viejas:
        del c["banda"]
    igual("el apilado es el de la lista, como siempre",
          [c["id"] for c in editar.capas_de(con_capas(viejas))], [1, 2, 3])


def prueba_capa_centro_y_tamano():
    p = con_capas([capa(x=0.8, y=0.1, escala=0.25)])
    texto, _ = editar.grafo(p)
    # 0,25 de 1920 son 480 px de ancho.
    igual("se escala en píxeles del lienzo", "scale=480:-1" in texto, True)
    # x/y son el CENTRO, así que overlay resta medio ancho.
    igual("y se coloca por el centro",
          "overlay=x=0.8000*W-w/2:y=0.1000*H-h/2" in texto, True)


def prueba_capa_ventana_de_tiempo():
    p = con_capas([capa(t0=2.5, t1=4.25)])
    texto, _ = editar.grafo(p)
    igual("solo se ve en su tramo",
          "enable='between(t,2.5000,4.2500)'" in texto, True)
    #  Nada de `eof_action`: una imagen es un flujo de un fotograma, y con
    #  `pass` el overlay deja pasar el vídeo en cuanto se acaba —o sea desde el
    #  principio— y la capa no se ve nunca. Medido.
    igual("sin eof_action, que es lo que la deja verse",
          "eof_action" in texto, False)


def prueba_capa_opacidad():
    igual("opaca: no se toca el alfa",
          "colorchannelmixer" in editar.grafo(con_capas([capa()]))[0], False)
    texto, _ = editar.grafo(con_capas([capa(opacidad=0.5)]))
    igual("translúcida: primero rgba y luego el alfa",
          "format=rgba,colorchannelmixer=aa=0.500" in texto, True)


def prueba_grafo_sin_audio_no_deja_nada_colgando():
    """Un fotograma suelto no mapea el audio, y eso no es «se ignora».

    En un filter_complex toda etiqueta que se produce hay que consumirla: dejar
    `[a]` sin conectar tumba la orden entera con «has output 1 unconnected». Es
    lo que tenía rota la previa desde que existe el grafo.
    """
    p = plan([{"id": 1, "fuente": 1, "desde": 0, "hasta": 4}])
    texto, _ = editar.grafo(p, sin_audio=True)
    igual("el audio va a un sumidero", "[mez]anullsink" in texto, True)
    igual("y no queda etiqueta [a] suelta", texto.endswith("[a]"), False)


# ── separar el audio ──────────────────────────────────────────────
def prueba_clip_mudo_va_por_el_silencio():
    """Un trozo mudo usa la misma rama que un vídeo sin audio."""
    p = plan([{"id": 1, "fuente": 1, "desde": 0, "hasta": 4, "mudo": True},
              {"id": 2, "fuente": 1, "desde": 4, "hasta": 8}])
    g, _ = editar.grafo(p)
    igual("el mudo se rellena con silencio", "anullsrc" in g, True)
    #  Y el otro no: solo hay UNA rama de audio de verdad.
    igual("el que suena sigue sonando", g.count("[0:a:0]atrim"), 1)


def prueba_capa_de_audio_con_recorte():
    """Sin recorte, el audio separado sonaría desde el principio del fichero."""
    p = con_capas([{"id": 1, "tipo": "audio", "banda": 2,
                    "ruta": fichero("v.mp4"), "t0": 3.0, "t1": 6.0,
                    "recorte": [3.0, 6.0], "volumen": 1.0}])
    g, _ = editar.grafo(p)
    igual("recorta el trozo que toca",
          "atrim=start=3.0000:end=6.0000" in g, True)
    igual("y lo coloca donde toca", "adelay=delays=3000:all=1" in g, True)


def prueba_capa_de_audio_sin_recorte_sigue_igual():
    """Una música añadida no lleva recorte y no puede cambiar de forma."""
    p = con_capas([{"id": 1, "tipo": "audio", "banda": 2,
                    "ruta": fichero("m.mp3"), "t0": 2.0, "volumen": 0.5}])
    g, _ = editar.grafo(p)
    igual("no aparece atrim", "atrim=start" in g.split("[mez]")[-1], False)
    igual("y el volumen sigue ahí", "volume=0.500" in g, True)


#  Una fuente con las dos pistas de una grabación de la casa: la Mezcla no
#  entra —`pistas_audio` la salta— así que los números empiezan en 1.
DOS_PISTAS = [{"i": 1, "titulo": "Sistema", "volumen": 1.0, "mudo": False},
              {"i": 2, "titulo": "Micrófono", "volumen": 1.0, "mudo": False}]


def plan_multipista(pistas, capa_audio):
    """Un plan con el trozo MUDO y una capa de audio, que es como queda un
    vídeo después de «separar el audio»."""
    ruta = fichero("multipista.mp4")
    p = plan([{"id": 1, "fuente": 1, "desde": 0, "hasta": 8, "mudo": True}],
             fuentes=[{"id": 1, "ruta": ruta, "rastro": "", "w": 1920,
                       "h": 1080, "fps": 30.0, "dur": 20.0, "pistas": pistas}])
    d = {"id": 5, "tipo": "audio", "ruta": ruta, "t0": 0.0, "t1": 4.0,
         "volumen": 1.0, "banda": 2}
    d.update(capa_audio)
    p["capas"] = [d]
    return p


def prueba_capa_de_audio_no_se_lleva_la_mezcla():
    """`[N:a]` a secas NO es «el audio del fichero»: ffmpeg lo resuelve a la
    primera pista, y en una grabación de la casa esa es la Mezcla —sistema y
    micro ya sumados—, justo la que el editor se salta al listar. Separar el
    audio devolvía las dos cosas juntas por la puerta de atrás."""
    g, _ = editar.grafo(plan_multipista(DOS_PISTAS, {}))
    igual("ninguna rama pide el audio sin decir cuál", ":a]" in g, False)
    igual("entra el sistema", ":a:1]" in g, True)
    igual("y el micro", ":a:2]" in g, True)
    igual("sumados antes del volumen", "axp0_0" in g, True)


def prueba_capa_de_audio_con_su_pista():
    """La que sale de «separar el audio» dice de qué pista es, y es esa."""
    g, _ = editar.grafo(plan_multipista(DOS_PISTAS, {"pista": 2}))
    igual("solo el micro", ":a:2]" in g, True)
    igual("el sistema no entra", ":a:1]" in g, False)


def prueba_pista_muda_apaga_su_capa():
    """Un silencio vale venga de donde venga. Antes la capa seguía sonando
    —traía la mezcla— y el botón de silencio no callaba nada."""
    pistas = [DOS_PISTAS[0], dict(DOS_PISTAS[1], mudo=True)]
    g, _ = editar.grafo(plan_multipista(pistas, {"pista": 2}))
    igual("el micro no suena", ":a:2]" in g, False)
    igual("y el grafo sigue en pie", "[mez]anull[amez]" in g, True)


def prueba_capa_de_fichero_de_fuera_coge_la_primera():
    """Una canción añadida no es de ninguna fuente del plan: se coge su primera
    pista, que es lo que se hacía antes, pero dicho."""
    p = plan_multipista(DOS_PISTAS, {"ruta": fichero("cancion.m4a")})
    g, _ = editar.grafo(p)
    igual("la primera del fichero", ":a:0]" in g, True)
    igual("y tampoco a secas", ":a]" in g, False)


# ── el vídeo es la banda 1 ────────────────────────────────────────
def prueba_migracion_sube_las_capas():
    """La banda 1 pasa a ser del vídeo, así que las capas suben una."""
    viejo = {"version": 2, "capas": [{"id": 1, "banda": 1},
                                     {"id": 2, "banda": 2},
                                     {"id": 3}]}
    nuevo = editar.subir_capas(viejo)
    igual("la 1 sube a la 2", nuevo["capas"][0]["banda"], 2)
    igual("la 2 sube a la 3", nuevo["capas"][1]["banda"], 3)
    igual("y la que no la traía va a la 2", nuevo["capas"][2]["banda"], 2)


def prueba_migracion_conserva_el_orden():
    """Renumerar no puede cambiar qué tapa a qué: solo dónde se dibuja."""
    p = plan([{"id": 1, "fuente": 1, "desde": 0, "hasta": 8}])
    p["version"] = 2
    p["capas"] = [{"id": 1, "tipo": "imagen", "banda": 1,
                   "ruta": fichero("abajo.png"), "t0": 0, "t1": 8,
                   "x": 0.5, "y": 0.5, "escala": 0.3},
                  {"id": 2, "tipo": "imagen", "banda": 2,
                   "ruta": fichero("arriba.png"), "t0": 0, "t1": 8,
                   "x": 0.5, "y": 0.5, "escala": 0.2}]
    antes = [c["id"] for c in editar.capas_de(p)]
    editar.subir_capas(p)
    igual("el orden de apilado no cambia",
          [c["id"] for c in editar.capas_de(p)], antes)


def prueba_capas_por_defecto_a_la_dos():
    """Una capa sin banda ya no cae en la del vídeo."""
    p = con_capas([{"id": 1, "tipo": "imagen", "ruta": fichero("x.png"),
                    "t0": 0, "t1": 4, "x": 0.5, "y": 0.5, "escala": 0.2}])
    igual("sin banda va a la 2", editar.capas_de(p)[0].get("banda", 2), 2)


# ── la cámara ─────────────────────────────────────────────────────
def prueba_croma_va_antes_de_escalar():
    """Escalar primero deja un halo: los píxeles inventados en el borde ya no
    son ni verde ni piel, y recortarlos después no los quita."""
    p = con_capas([{"id": 1, "tipo": "video", "banda": 1,
                    "ruta": fichero("cam.mp4"), "t0": 0, "t1": 5,
                    "recorte": [0, 5], "w": 640, "h": 480,
                    "x": 0.8, "y": 0.8, "escala": 0.25,
                    "croma": {"color": "#00ff00", "tolerancia": 0.25}}])
    g, _ = editar.grafo(p)
    igual("hay chromakey", "chromakey=" in g, True)
    igual("y va antes del scale",
          g.index("chromakey=") < g.index("scale=480"), True)
    igual("con despill detrás", "despill=type=green" in g, True)


def prueba_sin_croma_no_se_toca():
    p = con_capas([{"id": 1, "tipo": "video", "banda": 1,
                    "ruta": fichero("cam.mp4"), "t0": 0, "t1": 5,
                    "recorte": [0, 5], "w": 640, "h": 480,
                    "x": 0.8, "y": 0.8, "escala": 0.25}])
    g, _ = editar.grafo(p)
    igual("no hay chromakey", "chromakey" in g, False)


# ── clips de imagen ───────────────────────────────────────────────
def con_imagen():
    """Un plan con un trozo de vídeo y otro que es una imagen fija."""
    p = plan([{"id": 1, "fuente": 1, "desde": 0, "hasta": 4},
              {"id": 2, "fuente": 2, "desde": 0, "hasta": 2}])
    p["fuentes"].append({"id": 2, "ruta": fichero("congelado.png"),
                         "rastro": "", "tipo": "imagen", "w": 1920, "h": 1080,
                         "fps": 30.0, "dur": 2.0, "pistas": []})
    return p


def prueba_imagen_es_un_clip_mas():
    tramos = editar.mapa(con_imagen())
    igual("dos tramos", len(tramos), 2)
    cerca("la línea suma los dos", tramos[-1][1], 6.0)


def prueba_imagen_entra_en_bucle():
    p = con_imagen()
    rutas, _, _, _ = editar.entradas(p)
    args = editar.abrir_entradas(p, rutas)
    igual("la imagen se repite", "-loop" in args, True)
    #  Con un segundo de propina sobre el clip más largo: si se queda corta, el
    #  trozo sale más breve de lo que dice el plan y descoloca la línea.
    igual("y con duración de sobra", "3.000" in args, True)
    #  El vídeo no: ponerle `-loop` a un mp4 lo dejaría girando sin fin.
    igual("un solo -loop", args.count("-loop"), 1)


def prueba_imagen_no_trae_audio():
    """Sin pistas, la rama de silencio que ya existe se encarga."""
    g, _ = editar.grafo(con_imagen())
    igual("hay un anullsrc", "anullsrc" in g, True)
    igual("y el concat sigue teniendo sus dos ramas",
          "concat=n=2:v=1:a=1" in g, True)


def prueba_es_imagen():
    for r in ("/x/a.png", "/x/A.JPG", "/x/b.webp", "/x/c.gif"):
        igual("%s es imagen" % r, editar.es_imagen(r), True)
    for r in ("/x/a.mp4", "/x/a.mkv", "/x/pngs/v.webm", "/x/sin"):
        igual("%s no lo es" % r, editar.es_imagen(r), False)


# ── censura ───────────────────────────────────────────────────────
def prueba_censura_calla_el_tramo():
    p = con_capas([{"id": 1, "tipo": "censura", "modo": "silencio",
                    "banda": 1, "t0": 3.0, "t1": 5.0}])
    g, _ = editar.grafo(p)
    igual("baja el volumen a cero en su ventana",
          "volume=0:enable='between(t,3.0000,5.0000)'" in g, True)
    igual("y sin pitido", "sine=" in g, False)


def prueba_censura_pitido():
    p = con_capas([{"id": 1, "tipo": "censura", "modo": "pitido",
                    "banda": 1, "t0": 3.0, "t1": 5.0}])
    g, _ = editar.grafo(p)
    igual("calla igual", "volume=0:enable=" in g, True)
    igual("y encima pone el tono", "sine=f=1000:d=2.0000" in g, True)
    igual("colocado en su sitio", "adelay=delays=3000:all=1" in g, True)


def prueba_censura_va_despues_de_la_mezcla():
    """Si fuera antes, la música añadida sonaría encima de lo censurado."""
    p = con_capas([
        {"id": 1, "tipo": "audio", "banda": 1, "ruta": fichero("m.mp3"),
         "t0": 0, "volumen": 1.0},
        {"id": 2, "tipo": "censura", "modo": "silencio", "banda": 2,
         "t0": 3.0, "t1": 5.0}])
    g, _ = editar.grafo(p)
    igual("la mezcla primero",
          g.index("amix=inputs=2") < g.index("volume=0:enable="), True)


def prueba_censura_al_reves_no_cuenta():
    """Un bloque arrastrado hasta cruzarse no puede dar un `sine` negativo."""
    p = con_capas([{"id": 1, "tipo": "censura", "modo": "pitido",
                    "banda": 1, "t0": 5.0, "t1": 3.0}])
    g, _ = editar.grafo(p)
    igual("no entra en el grafo", "volume=0:enable=" in g, False)


def prueba_sin_censura_no_ensucia():
    g, _ = editar.grafo(plan([{"id": 1, "fuente": 1, "desde": 0, "hasta": 8}]))
    igual("no hay volume=0", "volume=0:" in g, False)
    igual("y el audio sale por [a]", "[a]" in g, True)


# ── fundidos y color ──────────────────────────────────────────────
def prueba_color_solo_sale_si_se_toca():
    limpio = plan([{"id": 1, "fuente": 1, "desde": 0, "hasta": 8}])
    g, _ = editar.grafo(limpio)
    igual("sin color no hay eq", "eq=" in g, False)

    p = plan([{"id": 1, "fuente": 1, "desde": 0, "hasta": 8,
               "color": {"brillo": 0.2}}])
    g, _ = editar.grafo(p)
    igual("con color sí", "eq=brightness=0.2000" in g, True)


def prueba_color_saturacion_cero():
    """El cero es falso en python: `x or 1` lo convertía en 1 y no hacía nada."""
    f = editar.filtro_color({"color": {"saturacion": 0.0}})
    igual("saturación cero llega al filtro", "saturation=0.0000" in f, True)
    #  Y lo mismo con el contraste, que también tiene el uno por defecto.
    f = editar.filtro_color({"color": {"contraste": 0.0}})
    igual("contraste cero también", "contrast=0.0000" in f, True)


def prueba_color_se_acota():
    f = editar.filtro_color({"color": {"brillo": 9, "contraste": -4,
                                       "saturacion": 99}})
    igual("brillo al tope", "brightness=1.0000" in f, True)
    igual("contraste al suelo", "contrast=0.0000" in f, True)
    igual("saturación al tope", "saturation=3.0000" in f, True)
    igual("un color con basura no rompe",
          editar.filtro_color({"color": {"brillo": "x"}}), "")


def prueba_color_va_por_clip():
    """Dos trozos, uno tocado: el otro no se entera."""
    p = plan([{"id": 1, "fuente": 1, "desde": 0, "hasta": 4,
               "color": {"saturacion": 0.0}},
              {"id": 2, "fuente": 1, "desde": 4, "hasta": 8}])
    g, _ = editar.grafo(p)
    igual("solo un eq", g.count("eq=brightness"), 1)


def prueba_fundido_primero_y_ultimo():
    p = plan([{"id": 1, "fuente": 1, "desde": 0, "hasta": 4},
              {"id": 2, "fuente": 1, "desde": 4, "hasta": 8}])
    p["fundidos"] = {"entrada": 1.0, "salida": 0.5, "entre": 0}
    g, _ = editar.grafo(p)
    igual("entra por el primero", "fade=t=in:st=0:d=1.0000" in g, True)
    igual("y sale por el último", "fade=t=out:st=3.5000:d=0.5000" in g, True)
    igual("el audio también", "afade=t=in:st=0:d=1.0000" in g, True)
    igual("dos fundidos de vídeo y ya", g.count("fade=t=") - g.count("afade=t="), 2)


def prueba_fundido_entre_reparte_a_los_dos_lados():
    p = plan([{"id": 1, "fuente": 1, "desde": 0, "hasta": 4},
              {"id": 2, "fuente": 1, "desde": 4, "hasta": 8}])
    p["fundidos"] = {"entrada": 0, "salida": 0, "entre": 0.4}
    v0, _ = editar.filtros_fundido(0, 2, 4.0, p)
    v1, _ = editar.filtros_fundido(1, 2, 4.0, p)
    igual("el primero solo se va", "t=in" in v0, False)
    igual("y se va con medio «entre»", "d=0.2000" in v0, True)
    igual("el segundo entra", "t=in:st=0:d=0.2000" in v1, True)
    igual("y no sale", "t=out" in v1, False)


def prueba_fundido_no_cabe_en_un_trozo_corto():
    """Un trozo de 0,2 s con un segundo de fundido se quedaría negro entero."""
    p = plan([{"id": 1, "fuente": 1, "desde": 0, "hasta": 1}])
    p["fundidos"] = {"entrada": 1.0, "salida": 1.0, "entre": 0}
    v, _ = editar.filtros_fundido(0, 1, 0.2, p)
    igual("se reparte a la mitad", "d=0.1000" in v, True)
    igual("y no se solapan", v.count("d=0.1000"), 2)


def prueba_fundido_sobre_la_duracion_de_linea():
    """Con velocidad, el fundido va sobre lo que OCUPA, no sobre el original."""
    p = plan([{"id": 1, "fuente": 1, "desde": 0, "hasta": 8, "velocidad": 2.0}])
    p["fundidos"] = {"entrada": 0, "salida": 1.0, "entre": 0}
    g, _ = editar.grafo(p)
    # 8 s a 2× son 4 de línea, así que la salida empieza en el 3.
    igual("el fundido de salida cuenta desde los 4 s",
          "fade=t=out:st=3.0000:d=1.0000" in g, True)


def prueba_sin_fundidos_no_ensucia():
    g, _ = editar.grafo(plan([{"id": 1, "fuente": 1, "desde": 0, "hasta": 8}]))
    igual("sin fundidos no hay fade", "fade" in g, False)


# ── clics ─────────────────────────────────────────────────────────
def con_rastro(clips, clics_t, activo=True):
    """Un plan con un rastro de mentira en disco y clics en instantes dados."""
    ruta = os.path.join(BORRADOR, "r%s.jsonl" % "-".join(map(str, clics_t)))
    if not os.path.exists(ruta):
        import json as _j
        with open(ruta, "w") as f:
            f.write(_j.dumps({"meta": {"w": 1920, "h": 1080}}) + "\n")
            t = 0.0
            while t < 20.0:
                # el cursor va en diagonal, así que cada instante tiene su sitio
                f.write(_j.dumps({"t": round(t, 3), "x": t * 50, "y": t * 30})
                        + "\n")
                t += 0.1
            for tc in clics_t:
                f.write(_j.dumps({"t": tc, "tipo": "clic", "boton": 272}) + "\n")
    p = plan(clips)
    p["fuentes"][0]["rastro"] = ruta
    p["clics"] = {"activo": activo, "color": "#ffd60a"}
    return p


def prueba_clics_a_tiempo_de_linea():
    p = con_rastro([{"id": 1, "fuente": 1, "desde": 0, "hasta": 10}],
                   [2.0, 5.0])
    c = editar.clics_de(p)
    igual("los dos clics", len(c), 2)
    cerca("el primero en su sitio", c[0][0], 2.0)
    cerca("el segundo también", c[1][0], 5.0)
    #  La posición sale del rastro: en t=2 el cursor iba por (100, 60).
    cerca("y con la posición del cursor", c[0][1], 100.0, tol=6)
    cerca("en las dos coordenadas", c[0][2], 60.0, tol=6)


def prueba_clics_apagados():
    p = con_rastro([{"id": 1, "fuente": 1, "desde": 0, "hasta": 10}],
                   [2.0], activo=False)
    igual("apagado no devuelve nada", editar.clics_de(p), [])


def prueba_clics_de_un_trozo_cortado_desaparecen():
    """Es lo que se quiere y sale gratis del mapa: si quitas el trozo, se va."""
    p = con_rastro([{"id": 1, "fuente": 1, "desde": 0, "hasta": 3},
                    {"id": 2, "fuente": 1, "desde": 6, "hasta": 10}],
                   [2.0, 5.0, 7.0])
    c = editar.clics_de(p)
    igual("el del trozo quitado no está", len(c), 2)
    cerca("el primero se queda donde estaba", c[0][0], 2.0)
    #  El de t=7 del fichero cae en el segundo trozo, que empieza en el 3 de la
    #  línea: 3 + (7 - 6) = 4.
    cerca("y el otro se recoloca", c[1][0], 4.0)


def prueba_clics_con_velocidad():
    p = con_rastro([{"id": 1, "fuente": 1, "desde": 0, "hasta": 10,
                     "velocidad": 2.0}], [4.0])
    c = editar.clics_de(p)
    cerca("un clip a 2x adelanta el clic", c[0][0], 2.0)


def prueba_clics_sin_rastro():
    """Un vídeo abierto del disco no tiene clics, y eso no es un fallo."""
    p = plan([{"id": 1, "fuente": 1, "desde": 0, "hasta": 8}])
    p["clics"] = {"activo": True}
    igual("sin rastro, ningún clic", editar.clics_de(p), [])


def prueba_clics_en_el_grafo():
    p = con_rastro([{"id": 1, "fuente": 1, "desde": 0, "hasta": 10}],
                   [2.0, 5.0])
    lineas, sale = editar.ramas_clics(p, 3, "zoom")
    igual("un overlay por clic", len(lineas), 2)
    igual("encadenados", "[clic0][3:v]overlay" in lineas[1], True)
    igual("y la salida es el último", sale, "clic1")
    igual("cada uno en su ventana",
          "enable='between(t,2.0000,2.3500)'" in lineas[0], True)

    #  Sin anillo no se pinta nada: el destello es un PNG y si no se pudo
    #  dibujar, el render tiene que salir igual sin él.
    igual("sin anillo, sin ramas", editar.ramas_clics(p, -1, "zoom"),
          ([], "zoom"))


# ── zonas ─────────────────────────────────────────────────────────
def zona(**campos):
    d = {"id": 9, "tipo": "zona", "modo": "desenfoque", "banda": 1,
         "t0": 2.0, "t1": 6.0, "x": 0.3, "y": 0.4, "an": 0.3, "al": 0.25,
         "fuerza": 0.5}
    d.update(campos)
    return d


def prueba_zona_recorta_donde_toca():
    p = con_capas([zona()])
    g, _ = editar.grafo(p)
    #  1920x1080: an 0.3 → 576, al 0.25 → 270, y la esquina en el centro menos
    #  medio: 0.3*1920 - 288 = 288, 0.4*1080 - 135 = 297 (par → 296).
    igual("recorta la caja pedida", "crop=576:270:288:296" in g, True)
    igual("y la vuelve a pegar en el mismo sitio",
          "overlay=x=288:y=296" in g, True)
    igual("en su ventana de tiempo",
          "enable='between(t,2.0000,6.0000)'" in g, True)


def prueba_zona_va_despues_del_zoom():
    """Como toda capa: si fuera antes, el zoom ampliaría el desenfoque."""
    g, _ = editar.grafo(con_capas([zona()]))
    igual("el zoom primero", g.index("zoompan=") < g.index("crop="), True)


def prueba_zona_modos():
    difu, _ = editar.grafo(con_capas([zona(modo="desenfoque")]))
    igual("el desenfoque usa gblur", "gblur=sigma=" in difu, True)

    pixel, _ = editar.grafo(con_capas([zona(modo="pixelado")]))
    igual("el pixelado usa pixelize", "pixelize=w=" in pixel, True)
    igual("y no gblur", "gblur" in pixel, False)

    #  El foco es al revés: se estropea TODO menos la zona, así que lo que se
    #  recorta se pega intacto encima de un fondo oscurecido.
    foco, _ = editar.grafo(con_capas([zona(modo="foco")]))
    igual("el foco oscurece con eq", "eq=brightness=-" in foco, True)
    igual("y no toca la región", "gblur" in foco or "pixelize" in foco, False)


def prueba_zona_fuerza():
    for f, espera in ((0.0, 2.0), (0.5, 21.0), (1.0, 40.0)):
        cerca("desenfoque con fuerza %.1f" % f,
              editar.fuerza_zona("desenfoque", f), espera)
    igual("pixelado mínimo de 4", editar.fuerza_zona("pixelado", 0.0), 4)
    igual("pixelado a tope", editar.fuerza_zona("pixelado", 1.0), 64)
    for f in (-3, 2, "x" if False else 1.5):
        # Fuera de rango se acota en vez de salir un filtro imposible.
        v = editar.fuerza_zona("desenfoque", f)
        igual("fuerza %r acotada" % f, 2.0 <= v <= 40.0, True)


def prueba_zona_no_se_sale_del_fotograma():
    """Arrastrada al borde, un crop negativo no es un aviso: tumba el render."""
    for x, y in ((0.0, 0.0), (1.0, 1.0), (0.99, 0.02), (-0.5, 1.7)):
        an, al, cx, cy = editar.caja_zona(zona(x=x, y=y), 1920, 1080)
        igual("(%.2f,%.2f) x dentro" % (x, y), 0 <= cx and cx + an <= 1920, True)
        igual("(%.2f,%.2f) y dentro" % (x, y), 0 <= cy and cy + al <= 1080, True)
        igual("(%.2f,%.2f) anchura par" % (x, y), an % 2, 0)
        igual("(%.2f,%.2f) altura par" % (x, y), al % 2, 0)


def prueba_zona_no_necesita_fichero():
    """Es la única capa que se hace con la propia imagen, sin abrir nada."""
    p = con_capas([zona()])
    rutas, _, de_capa, _ = editar.entradas(p)
    igual("no añade una entrada", len(rutas), 1)
    igual("ni le toca índice", 9 in de_capa, False)


def prueba_capa_sin_fichero():
    """Borrar el PNG meses después no puede impedirte reexportar el vídeo."""
    p = con_capas([capa(ruta=os.path.join(BORRADOR, "esto-no-existe.png"))])
    texto, _ = editar.grafo(p)
    igual("la capa se salta", "overlay=" in texto, False)
    igual("pero el vídeo sale igual", "[zoom]format=yuv420p[v]" in texto, True)


# ── vídeo dentro de vídeo ─────────────────────────────────────────
def pip(**campos):
    d = {"id": 1, "tipo": "video", "banda": 1, "ruta": fichero("camara.mp4"),
         "t0": 2.0, "t1": 5.0, "dur": 6.0, "recorte": [1.0, 4.0],
         "x": 0.76, "y": 0.74, "escala": 0.3, "opacidad": 1.0,
         "w": 1280, "h": 720}
    d.update(campos)
    return d


def prueba_pip_se_coloca_en_su_instante():
    """`setpts` es lo que lo pone donde toca; sin él saldría congelado.

    Sin el desplazamiento, el clip empieza en el segundo cero del vídeo grande y
    lo único que hace el `enable` es taparlo hasta su tramo: cuando aparece, ya
    ha pasado y se queda en su último fotograma.
    """
    texto, _ = editar.grafo(con_capas([pip()]), carpeta=BORRADOR)
    igual("recorta el trozo del fichero",
          "trim=start=1.0000:end=4.0000" in texto, True)
    igual("y lo empuja hasta su instante de la línea",
          "setpts=PTS-STARTPTS+2.0000/TB" in texto, True)


def prueba_pip_no_trunca_el_video():
    """Un clip se acaba antes que el vídeo, y eso no puede cortar la salida.

    Medido con las cuatro opciones de `eof_action`: con `endall` el vídeo entero
    se queda en 0,03 s.
    """
    texto, _ = editar.grafo(con_capas([pip()]), carpeta=BORRADOR)
    igual("eof_action=pass", "eof_action=pass" in texto, True)


def prueba_pip_escala_y_centro():
    texto, _ = editar.grafo(con_capas([pip(escala=0.4, x=0.3, y=0.6)]),
                            carpeta=BORRADOR)
    # 0,4 de 1920 son 768
    igual("escala en píxeles del lienzo", "scale=768:-1" in texto, True)
    igual("y centrado como las demás capas",
          "x=0.3000*W-w/2:y=0.6000*H-h/2" in texto, True)


def prueba_pip_no_trae_su_audio():
    """Meterlo sería otra decisión —a qué volumen, mezclado con qué—, y para eso
    ya está una capa de audio."""
    texto, _ = editar.grafo(con_capas([pip()]), carpeta=BORRADOR)
    igual("no toca el audio de la capa", ":a]" in texto.split("[pip0]")[0], False)


# ── el audio añadido ──────────────────────────────────────────────
def pista_audio(**campos):
    d = {"id": 1, "tipo": "audio", "banda": 1, "ruta": fichero("musica.mp3"),
         "t0": 3.0, "t1": 8.0, "dur": 6.0, "volumen": 0.6}
    d.update(campos)
    return d


def prueba_audio_entra_con_retardo_y_volumen():
    texto, _ = editar.grafo(con_capas([pista_audio()]), carpeta=BORRADOR)
    igual("su volumen", "volume=0.600" in texto, True)
    #  `all=1` y no `delays=N|N`: con un valor por canal hay que saber cuántos
    #  canales trae el fichero, y un mp3 mono y un wav estéreo no traen los mismos.
    igual("retardo en milisegundos y a todos los canales",
          "adelay=delays=3000:all=1" in texto, True)
    #  Sin `apad` la pista más corta manda en el amix y el vídeo se queda sin
    #  sonido a partir de donde se acabe la música.
    igual("con relleno al final", "apad" in texto, True)


def prueba_audio_se_suma_sin_bajar_lo_de_debajo():
    texto, _ = editar.grafo(con_capas([pista_audio()]), carpeta=BORRADOR)
    igual("se mezcla con el audio de la base",
          "[mez][ax0]amix=inputs=2" in texto, True)
    #  `normalize=0`: sin esto amix reparte el volumen entre las entradas y añadir
    #  música bajaría la voz sin que nadie lo pida. `duration=first`: sin esto el
    #  `apad` alargaría el vídeo hasta el infinito.
    igual("sin normalizar y con la duración del vídeo",
          "normalize=0:duration=first" in texto, True)


def prueba_audio_sin_retardo_no_pone_adelay():
    texto, _ = editar.grafo(con_capas([pista_audio(t0=0)]), carpeta=BORRADOR)
    igual("empezando en cero no hace falta retrasar",
          "adelay" in texto, False)


def prueba_audio_en_una_previa_no_entra():
    """Un fotograma suelto no lleva sonido, así que ni se abre el fichero."""
    texto, _ = editar.grafo(con_capas([pista_audio()]), sin_audio=True,
                            carpeta=BORRADOR)
    igual("nada de amix", "amix" in texto, False)
    igual("y el audio de la base a un sumidero",
          "[mez]anullsink" in texto, True)


def prueba_audio_no_pinta_nada():
    """Una capa de audio no es una capa de imagen: no lleva overlay."""
    texto, _ = editar.grafo(con_capas([pista_audio()]), carpeta=BORRADOR)
    igual("sin overlay", "overlay=" in texto, False)


# ── el fichero del proyecto ───────────────────────────────────────
def prueba_carpeta_adjunta_de_los_dos_nombres():
    """`.k4v` es el nombre de hoy y `.k4.json` el de ayer: los dos proyectos
    tienen que apuntar a la MISMA carpeta adjunta, o los recortes y las formas
    de un montaje viejo se buscarían donde no están."""
    igual("del nombre nuevo", editar.carpeta_de("/tmp/v.k4v"), "/tmp/v.k4")
    igual("y del viejo", editar.carpeta_de("/tmp/v.k4.json"), "/tmp/v.k4")


def prueba_el_proyecto_viejo_se_renombra_al_abrirlo():
    import json as _json
    viejo = os.path.join(BORRADOR, "migra.k4.json")
    nuevo = os.path.join(BORRADOR, "migra.k4v")
    for f in (viejo, nuevo):
        if os.path.exists(f):
            os.remove(f)
    _json.dump({"marca": 1}, open(viejo, "w"))
    editar.migrar_nombre(nuevo)
    igual("el nuevo existe", os.path.exists(nuevo), True)
    igual("y el viejo ya no", os.path.exists(viejo), False)
    igual("con lo que tenía dentro",
          _json.load(open(nuevo)).get("marca"), 1)


def prueba_migrar_no_pisa_un_proyecto_ya_migrado():
    import json as _json
    viejo = os.path.join(BORRADOR, "dos.k4.json")
    nuevo = os.path.join(BORRADOR, "dos.k4v")
    _json.dump({"marca": "viejo"}, open(viejo, "w"))
    _json.dump({"marca": "nuevo"}, open(nuevo, "w"))
    editar.migrar_nombre(nuevo)
    igual("manda el que ya estaba migrado",
          _json.load(open(nuevo)).get("marca"), "nuevo")


def prueba_un_proyecto_renombrado_se_encuentra_por_su_video():
    """Desde que un proyecto se puede llamar como su dueño quiera, `<vídeo>.k4v`
    ya no es la única respuesta: abrir el vídeo tiene que encontrar su plan
    LEYÉNDOLOS, o cada apertura crearía un montaje nuevo en blanco y el trabajo
    de ayer quedaría en un fichero que nadie vuelve a abrir."""
    import json as _json
    casa = os.path.join(BORRADOR, "nombrado")
    if os.path.isdir(casa):
        for n in os.listdir(casa):
            os.remove(os.path.join(casa, n))
    else:
        os.makedirs(casa)
    video = os.path.join(casa, "grabacion.mp4")
    open(video, "w").close()
    plan = os.path.join(casa, "Mi tutorial.k4v")
    _json.dump({"fuentes": [{"id": 1, "ruta": video}]}, open(plan, "w"))

    defecto = os.path.join(casa, "grabacion.k4v")
    igual("lo encuentra por dentro", editar.plan_de_video(video, defecto), plan)

    #  Y si existe el de fábrica, ese manda: es el más barato de comprobar y
    #  además es el que se acaba de escribir.
    _json.dump({"fuentes": []}, open(defecto, "w"))
    igual("pero manda el de fábrica si está",
          editar.plan_de_video(video, defecto), defecto)

    #  Un `.k4v` de otro vídeo no se cuela.
    os.remove(defecto)
    ajeno = os.path.join(casa, "otro.k4v")
    _json.dump({"fuentes": [{"id": 1, "ruta": "/no/existe.mp4"}]},
               open(ajeno, "w"))
    igual("y el de otro vídeo no se cuela",
          editar.plan_de_video(video, defecto), plan)


def prueba_renombrar_no_pisa_un_proyecto_que_ya_existe():
    """Reusar un nombre no puede llevarse por delante el montaje de otro: eso no
    se deshace. Se aparta con un `(2)` y se avisa por el nombre devuelto."""
    casa = os.path.join(BORRADOR, "choque")
    if not os.path.isdir(casa):
        os.makedirs(casa)
    ocupado = os.path.join(casa, "Tomado.k4v")
    open(ocupado, "w").close()
    igual("se aparta", editar.nombre_libre(casa, "Tomado"),
          os.path.join(casa, "Tomado (2).k4v"))
    igual("y libre es libre", editar.nombre_libre(casa, "Suelto"),
          os.path.join(casa, "Suelto.k4v"))


def prueba_un_nombre_con_barras_no_se_sale_de_la_carpeta():
    """El nombre lo escribe una persona en un campo de texto, así que puede
    traer cualquier cosa. `../../algo` tiene que quedarse dentro."""
    casa = os.path.join(BORRADOR, "escape")
    if not os.path.isdir(casa):
        os.makedirs(casa)
    igual("no sube de carpeta",
          os.path.dirname(editar.nombre_libre(casa, "../../fuera")), casa)
    igual("y vacío tiene apaño",
          editar.nombre_libre(casa, "   "), os.path.join(casa, "proyecto.k4v"))


# ── el aspecto de una capa ────────────────────────────────────────
def prueba_espejo_y_filtro_de_color():
    texto, _ = editar.grafo(con_capas([capa(espejo=True, filtro="gris")]),
                            carpeta=BORRADOR)
    igual("da la vuelta", "hflip" in texto, True)
    igual("y quita el color", "hue=s=0" in texto, True)


def prueba_filtro_desconocido_no_ensucia_el_grafo():
    """Un plan con un filtro que ya no existe tiene que renderizar igual."""
    texto, _ = editar.grafo(con_capas([capa(filtro="inventado")]),
                            carpeta=BORRADOR)
    igual("la capa sigue saliendo", "overlay=" in texto, True)
    igual("sin filtro ninguno", "hue=" in texto, False)


def prueba_circulo_recorta_el_cuadrado_del_centro():
    """«En círculo» es el cuadrado del centro redondeado, no el vídeo aplastado."""
    texto, _ = editar.grafo(con_capas([capa(mascara="circulo")]),
                            carpeta=BORRADOR)
    igual("al cuadrado", "crop=w='min(iw,ih)':h='min(iw,ih)'" in texto, True)
    igual("y con alfa por geq", "geq=" in texto and "alpha(X,Y)" in texto, True)


def prueba_marco_sin_mascara_es_un_recuadro():
    """Por fuera y con `pad`: pintado hacia dentro se comía la imagen."""
    texto, _ = editar.grafo(
        con_capas([capa(marco=0.05, colorMarco="#ff0000")]), carpeta=BORRADOR)
    igual("hace sitio alrededor", "pad=iw+" in texto, True)
    igual("de su color", "color=#ff0000" in texto, True)
    igual("y sin pintar píxel a píxel", "geq=" in texto, False)


def prueba_marco_con_mascara_va_en_la_misma_pasada():
    """Un marco redondo no lo puede pintar drawbox: sale con esquinas."""
    texto, _ = editar.grafo(
        con_capas([capa(mascara="redonda", marco=0.05, colorMarco="#ff0000")]),
        carpeta=BORRADOR)
    igual("una sola geq", texto.count("geq="), 1)
    igual("con el color del marco dentro", "if(gt(" in texto, True)
    #  El anillo cae en el hueco que abre el `pad`, no sobre la imagen.
    igual("y sitio alrededor para él", "pad=iw+" in texto, True)


def prueba_aspecto_va_antes_de_la_opacidad():
    """Si fuera después, el alfa de la máscara pisaría al de la opacidad."""
    texto, _ = editar.grafo(
        con_capas([capa(mascara="circulo", opacidad=0.5)]), carpeta=BORRADOR)
    igual("primero la máscara",
          texto.index("geq=") < texto.index("colorchannelmixer=aa="), True)


def prueba_capa_sin_aspecto_no_cambia():
    """Lo de siempre tiene que salir exactamente como salía."""
    texto, _ = editar.grafo(con_capas([capa()]), carpeta=BORRADOR)
    for f in ("hflip", "geq=", "drawbox=", "hue=", "colortemperature"):
        igual("sin %s" % f, f in texto, False)


def prueba_sombra_va_debajo_y_desplazada():
    """Con su propio overlay y no compuesta con la capa: así la mancha puede
    salirse de la huella, que es lo que hace que parezca sombra."""
    texto, _ = editar.grafo(con_capas([capa(sombra=0.8)]), carpeta=BORRADOR)
    igual("se saca un doble de la capa", "split[cp0][sm0]" in texto, True)
    igual("ennegrecido conservando la silueta",
          "colorchannelmixer=rr=0:gg=0:bb=0:aa=0.560" in texto, True)
    igual("con sitio para que el desenfoque no se corte",
          "pad=iw+" in texto and "gblur=sigma=" in texto, True)
    igual("y va DEBAJO de la capa",
          texto.index("[so0]overlay") < texto.index("[cp0]overlay"), True)


def prueba_sombra_cae_hacia_abajo_y_a_la_derecha():
    texto, _ = editar.grafo(con_capas([capa(sombra=0.8)]), carpeta=BORRADOR)
    #  El overlay ya centra el doble por su propio ancho —que es mayor por el
    #  acolchado—, así que el desplazamiento es solo la caída. Restarle el
    #  margen la mandaba arriba y a la izquierda, detrás de la capa.
    #  Una capa de 480 px de ancho: sigma 21,6 y caída 28 px.
    igual("la caída es positiva en las dos",
          "+28':y='(0.5000*H-h/2)+28'" in texto, True)


def prueba_sin_sombra_no_hay_doble():
    texto, _ = editar.grafo(con_capas([capa()]), carpeta=BORRADOR)
    igual("ni split ni gblur",
          "split" in texto or "gblur" in texto, False)


# ── el sonido del vídeo incrustado ────────────────────────────────
#
#  Aquí sí hacen falta ficheros de VERDAD: si el vídeo trae sonido o no se
#  pregunta con ffprobe, y a un fichero vacío le contesta que no. Se fabrican
#  una vez y se quedan en el borrador.
def video_de_prueba(nombre, con_sonido):
    ruta = os.path.join(BORRADOR, nombre)
    if os.path.exists(ruta) and os.path.getsize(ruta) > 0:
        return ruta
    orden = ["ffmpeg", "-y", "-v", "error",
             "-f", "lavfi", "-i", "color=c=red:s=320x240:r=25:d=2"]
    if con_sonido:
        orden += ["-f", "lavfi", "-i", "sine=frequency=440:duration=2",
                  "-shortest"]
    orden += ["-pix_fmt", "yuv420p", ruta]
    import subprocess
    subprocess.run(orden, capture_output=True)
    return ruta


def pip_sonoro(**campos):
    #  Sobre el mismo ayudante que el resto de PIP —`pip()`, más arriba— pero
    #  con un fichero que existe y suena de verdad.
    d = pip(ruta=video_de_prueba("pip.mp4", True), t0=3.0, t1=5.0, dur=2.0,
            w=320, h=240, recorte=[0, 2.0], sonido=True, volumen=0.5)
    d.update(campos)
    return d


def prueba_pip_con_sonido_entra_en_la_mezcla():
    texto, _ = editar.grafo(con_capas([pip_sonoro()]), carpeta=BORRADOR)
    igual("se mezcla con el audio de la base",
          "[mez][ax0]amix=inputs=2" in texto, True)
    igual("a su volumen", "volume=0.500" in texto, True)
    igual("colocado en su instante de la línea",
          "adelay=delays=3000:all=1" in texto, True)
    #  El mismo recorte que se ve: si el bloque enseña del 0 al 2 del fichero,
    #  eso es lo que tiene que sonar.
    igual("y recortado como la imagen",
          "atrim=start=0.0000:end=2.0000" in texto, True)


def prueba_pip_mudo_por_defecto_en_planes_viejos():
    """Sin el campo, un montaje de antes suena exactamente igual que sonaba."""
    p = con_capas([pip_sonoro(sonido=False)])
    texto, _ = editar.grafo(p, carpeta=BORRADOR)
    igual("no entra en la mezcla", "amix" in texto, False)
    igual("pero se sigue viendo", "overlay=" in texto, True)


def prueba_pip_sin_pista_de_audio_no_tumba_el_grafo():
    """Pedirle `[N:a]` a un vídeo mudo revienta el filter_complex entero."""
    editar._CON_SONIDO.clear()
    p = con_capas([pip_sonoro(ruta=video_de_prueba("pip-mudo.mp4", False))])
    texto, _ = editar.grafo(p, carpeta=BORRADOR)
    igual("se queda fuera de la mezcla", "amix" in texto, False)
    igual("y la imagen sale igual", "overlay=" in texto, True)


# ── los rótulos ───────────────────────────────────────────────────
def rotulo(**campos):
    d = {"id": 1, "tipo": "texto", "banda": 1, "t0": 1.0, "t1": 4.0,
         "texto": 'Ñandú: 50% "prueba" con : dos puntos',
         "x": 0.5, "y": 0.85, "tam": 0.09,
         "color": "#ffffff", "fondo": 0.0, "colorFondo": "#000000"}
    d.update(campos)
    return d


def prueba_rotulo_el_texto_va_a_un_fichero():
    """Nunca `text=`: lo escribe el usuario y un `:` rompería el grafo entero.

    No el rótulo: el GRAFO, o sea el render completo. Con el texto en un fichero
    su contenido no pasa por el parseo de filtros y da igual lo que lleve.
    """
    texto, _ = editar.grafo(con_capas([rotulo()]), carpeta=BORRADOR)
    igual("va por textfile", "textfile=" in texto, True)
    igual("y no por text=", ":text=" in texto, False)
    igual("el texto no aparece en el grafo",
          "Ñandú" in texto, False)

    guardado = open(os.path.join(BORRADOR, "texto-1.txt")).read()
    igual("está entero en su fichero",
          guardado, 'Ñandú: 50% "prueba" con : dos puntos')


def prueba_rotulo_sin_expansion():
    """`drawtext` se cree que el texto lleva formato y se come los `%`.

    Sin `expansion=none` sale «Stray %» por consola y el rótulo a medias. Pasó.
    """
    texto, _ = editar.grafo(con_capas([rotulo()]), carpeta=BORRADOR)
    igual("expansion=none puesto", "expansion=none" in texto, True)


def prueba_rotulo_tamano_y_centro():
    texto, _ = editar.grafo(con_capas([rotulo(tam=0.09, x=0.25, y=0.7)]),
                            carpeta=BORRADOR)
    # 0,09 del ALTO: 1080 * 0,09 = 97
    igual("el cuerpo va en fracción del alto", "fontsize=97" in texto, True)
    #  Centrado como las demás capas. Ojo: `text_h` de drawtext es alto de línea,
    #  así que el centro VISIBLE queda algo más arriba; la previa copia la misma
    #  fórmula para que coincida.
    #  x e y por separado: desde la máquina de escribir ya no van pegadas en
    #  la cadena —el orden de opciones de drawtext da igual—.
    igual("y se coloca por el centro",
          "x=0.2500*w-text_w/2" in texto
          and "y=0.7000*h-text_h/2" in texto, True)


def prueba_rotulo_caja():
    igual("sin fondo no hay caja",
          "box=1" in editar.grafo(con_capas([rotulo(fondo=0)]),
                                  carpeta=BORRADOR)[0], False)
    texto, _ = editar.grafo(con_capas([rotulo(fondo=0.55)]), carpeta=BORRADOR)
    igual("con fondo sí", "box=1" in texto, True)
    igual("y con su color y alfa", "boxcolor=0x000000@0.550" in texto, True)


def prueba_color_a_ffmpeg():
    igual("de #rrggbb", editar.color_ffmpeg("#ff2d55"), "0xff2d55@1.000")
    # QML puede dar ocho dígitos, y ahí el alfa va DELANTE.
    igual("de #aarrggbb", editar.color_ffmpeg("#80ff2d55"), "0xff2d55@0.502")
    igual("con opacidad aparte",
          editar.color_ffmpeg("#000000", 0.55), "0x000000@0.550")


def prueba_citar():
    """Las rutas salen del nombre del vídeo, que lo pone el usuario."""
    igual("comillas simples", editar.citar("/tmp/a.txt"), "'/tmp/a.txt'")
    igual("una comilla dentro se escapa",
          editar.citar("/tmp/o'brien.txt"), r"'/tmp/o\'brien.txt'")


# ── el zoom, en tiempo de línea ───────────────────────────────────
def prueba_zoom_en_tiempo_de_linea():
    """Un momento colocado en la línea no se mueve al reordenar los trozos.

    Es la promesa del modelo: `momentos` va en tiempo de línea. Si esto se
    rompiera, cortar por delante correría todos los zooms.
    """
    momento = {"id": 1, "t0": 6.0, "t1": 8.0, "cx": 800, "cy": 400,
               "z": 2.0, "seguir": False}

    p = plan([{"id": 1, "fuente": 1, "desde": 0, "hasta": 11}])
    p["momentos"] = [momento]
    a = editar.trayectoria(p)

    # Los mismos once segundos, pero partidos en tres y reordenados.
    q = plan([{"id": 1, "fuente": 1, "desde": 0,  "hasta": 5},
              {"id": 2, "fuente": 1, "desde": 12, "hasta": 14},
              {"id": 3, "fuente": 1, "desde": 5,  "hasta": 9}])
    q["momentos"] = [momento]
    b = editar.trayectoria(q)

    igual("misma duración, mismos pasos", len(a), len(b))
    # Como el momento no sigue al cursor, la cámara sale idéntica.
    distintos = sum(1 for x, y in zip(a, b) if abs(x[1] - y[1]) > 1e-9)
    igual("y la cámara no se entera de los cortes", distintos, 0)

    # El zoom está donde se puso, no antes ni después.
    def zoom_en(puntos, t):
        return min(puntos, key=lambda p: abs(p[0] - t))[1]

    cerca("antes del momento no hay zoom", zoom_en(b, 5.0), 1.0, 0.01)
    cerca("en medio sí lo hay", zoom_en(b, 7.0), 2.0, 0.05)
    cerca("y después se ha ido", zoom_en(b, 9.5), 1.0, 0.05)


# ── la transcripción ──────────────────────────────────────────────
def prueba_srt_se_parsea():
    """El SRT de whisper, a segmentos con números.

    Se parsea en python y no en el QML porque el formato es un detalle de
    whisper: así el editor recibe tiempos y texto, y si algún día cambia el
    formato solo cambia un fichero.
    """
    import transcribir
    ruta = os.path.join(BORRADOR, "t.srt")
    open(ruta, "w").write(
        "1\n00:00:00,000 --> 00:00:02,480\n Hola, esto es una prueba.\n\n"
        "2\n00:00:02,480 --> 00:00:05,120\n Con acentos: ñ, ú\n"
        " y sigue en la siguiente.\n\n"
        "3\n00:01:05,120 --> 00:01:07,000\n Y 50% de descuento.\n")
    segs = transcribir.leer_srt(ruta)

    igual("tres segmentos", len(segs), 3)
    cerca("los milisegundos cuentan", segs[0]["t1"], 2.480)
    igual("las líneas continuadas se juntan",
          segs[1]["texto"], "Con acentos: ñ, ú y sigue en la siguiente.")
    cerca("los minutos también", segs[2]["t0"], 65.120)
    igual("el número de orden no es texto",
          segs[0]["texto"], "Hola, esto es una prueba.")
    igual("y el porcentaje no se toca",
          "50%" in segs[2]["texto"], True)


def prueba_srt_que_no_existe():
    """No transcribir todavía no es un error: es no haber transcrito."""
    import transcribir
    igual("sin fichero, sin segmentos",
          transcribir.leer_srt(os.path.join(BORRADOR, "no-hay.srt")), [])


def prueba_efecto_desvanecer_es_fade_de_alfa():
    """El alfa animado va por `fade`, no por una expresión en
    colorchannelmixer: ese filtro no evalúa expresiones, se las traga como
    error y tumbaba el render entero."""
    texto, _ = editar.grafo(con_capas(
        [capa(entrada={"tipo": "desvanecer", "dur": 0.4})]))
    igual("el fundido de entrada, pegado a t0",
          "fade=t=in:st=2.0000:d=0.4000:alpha=1" in texto, True)
    texto, _ = editar.grafo(con_capas(
        [capa(salida={"tipo": "desvanecer", "dur": 0.5})]))
    igual("el de salida acaba clavado en t1",
          "fade=t=out:st=3.5000:d=0.5000:alpha=1" in texto, True)


def prueba_efecto_dur_acotada_a_media_ventana():
    """Una entrada de 5 s en una capa de 2 no es un efecto: es la capa entera
    apareciendo, y encima pisaría a la salida."""
    texto, _ = editar.grafo(con_capas(
        [capa(entrada={"tipo": "desvanecer", "dur": 5.0})]))
    igual("la rampa queda en media ventana (1 s)",
          "fade=t=in:st=2.0000:d=1.0000:alpha=1" in texto, True)


def imagen_de_prueba(nombre="cuadro.png", lado=200):
    """Un PNG de verdad: `zoompan` necesita el alto en números, y eso se lee de
    la cabecera del fichero. Con los ficheros vacíos del resto de pruebas la
    capa se queda quieta a propósito, que es justo lo que comprueba
    `prueba_efecto_crecer_sin_poder_medir_no_anima`.

    Lo pinta `png_de_prueba` y no magick: aquí solo importan los números de la
    cabecera —de qué color sea da igual—, y el resto de la suite ya se cuida
    de no depender de magick (se siembra el fichero, se suplanta al dibujante).
    Esta era la única que sí, y por eso se caía donde no está instalado."""
    return png_de_prueba(nombre, lado, lado)


def prueba_efecto_crecer_va_por_zoompan():
    """`scale` no sirve —sus expresiones no avanzan con el tiempo, medido—:
    el tamaño animado va acolchando la capa y recorriéndola con zoompan."""
    texto, _ = editar.grafo(con_capas(
        [capa(ruta=imagen_de_prueba(), entrada={"tipo": "crecer", "dur": 0.4})]),
        carpeta=BORRADOR)
    igual("acolcha al doble con transparente",
          "pad=iw*2:ih*2:iw/2:ih/2:color=black@0" in texto, True)
    igual("y el zoom recorre de media a entera",
          "zoompan=z='1+1.0000*(clip((it-2.0000)/0.4000,0,1))'" in texto, True)
    igual("sin fundir, que ya se ve entera", "fade=" in texto, False)


def prueba_efecto_crecer_sin_poder_medir_no_anima():
    """Un fichero que no se puede medir no puede tumbar el render: la capa
    entra quieta y el resto sale."""
    texto, _ = editar.grafo(con_capas(
        [capa(entrada={"tipo": "crecer", "dur": 0.4})]), carpeta=BORRADOR)
    igual("sin zoompan de la capa", "pad=iw*2" in texto, False)
    igual("pero la capa sale igual", "overlay=" in texto, True)


def prueba_efecto_girar_se_suma_al_giro_de_la_capa():
    """Dos `rotate` encadenados recortan las esquinas dos veces."""
    texto, _ = editar.grafo(con_capas(
        [capa(rotacion=15.0, entrada={"tipo": "girar", "dur": 0.4})]),
        carpeta=BORRADOR)
    igual("un solo rotate", texto.count("rotate="), 1)
    igual("con el giro de la capa y el del efecto",
          "(15.000000)+(20.000*(1-(clip((t-2.0000)/0.4000,0,1))))" in texto, True)


def prueba_curva_del_efecto():
    """La duración dice cuánto tarda; la curva, cómo reparte ese tiempo."""
    suave, _ = editar.grafo(con_capas(
        [capa(entrada={"tipo": "deslizar", "dur": 0.4, "curva": "suave"})]),
        carpeta=BORRADOR)
    igual("la suave es la smoothstep de siempre",
          "(3-2*(clip((t-2.0000)/0.4000,0,1)))" in suave, True)
    #  `fade` no sabe curvar, así que el alfa curvado tiene que ir por geq.
    igual("y el alfa deja de ir por fade", "fade=" in suave, False)
    igual("y va por geq con el instante en T",
          "a='alpha(X,Y)*" in suave and "(T-2.0000)" in suave, True)

    recta, _ = editar.grafo(con_capas(
        [capa(entrada={"tipo": "deslizar", "dur": 0.4})]), carpeta=BORRADOR)
    igual("con rampa recta manda fade, que es más barato",
          "fade=t=in" in recta and "geq=" not in recta, True)


def prueba_efecto_deslizar_empuja_y_funde():
    texto, _ = editar.grafo(con_capas(
        [capa(entrada={"tipo": "deslizar", "dur": 0.4})]))
    igual("la y del overlay lleva el empujón",
          "+0.080*(1-(clip((t-2.0000)/0.4000,0,1))))*H-h/2" in texto, True)
    igual("y además se funde", "fade=t=in" in texto, True)


def prueba_efecto_en_rotulo_va_por_alpha():
    """Un rótulo lo dibuja drawtext, que no pasa por fade: su alfa es el
    parámetro `alpha`, que sí evalúa expresiones."""
    texto, _ = editar.grafo(con_capas(
        [capa(tipo="texto", texto="Hola", tam=0.06,
              entrada={"tipo": "desvanecer", "dur": 0.4})]))
    igual("drawtext lleva alpha con la rampa",
          "alpha='(clip((t-2.0000)/0.4000,0,1))'" in texto, True)


def prueba_efecto_anima_la_entrada_de_la_imagen():
    """Una imagen de capa entra en bucle SOLO si está animada: sin efectos ni
    claves sigue siendo un fotograma suelto, que es más barato."""
    quieta = con_capas([capa()])
    rutas, _, _, _ = editar.entradas(quieta)
    igual("quieta: sin bucle",
          "-loop" in " ".join(editar.abrir_entradas(quieta, rutas)), False)
    animada = con_capas([capa(entrada={"tipo": "desvanecer", "dur": 0.4})])
    rutas, _, _, _ = editar.entradas(animada)
    args = " ".join(editar.abrir_entradas(animada, rutas))
    igual("animada: en bucle hasta t1+1",
          "-loop 1 -t 5.000" in args, True)


def prueba_efecto_no_toca_una_capa_quieta():
    """Sin efectos, el grafo de siempre: ni fade, ni max(), ni expresiones."""
    texto, _ = editar.grafo(con_capas([capa()]))
    igual("ni rastro de fade", "fade=" in texto, False)
    igual("la escala sigue siendo un número", "scale=480:-1" in texto, True)


def png_de_prueba(nombre, ancho, alto):
    """Un PNG mínimo de verdad, para lo que necesita leer cabeceras."""
    import struct, zlib
    def bloque(tipo, datos):
        return (struct.pack(">I", len(datos)) + tipo + datos
                + struct.pack(">I", zlib.crc32(tipo + datos)))
    ihdr = struct.pack(">IIBBBBB", ancho, alto, 8, 2, 0, 0, 0)
    idat = zlib.compress((b"\x00" + b"\x7f\x7f\x7f" * ancho) * alto)
    ruta = os.path.join(BORRADOR, nombre)
    with open(ruta, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + bloque(b"IHDR", ihdr)
                + bloque(b"IDAT", idat) + bloque(b"IEND", b""))
    return ruta


def prueba_tamano_imagen():
    ruta = png_de_prueba("medible.png", 200, 100)
    igual("el PNG se mide por su cabecera",
          editar.tamano_imagen(ruta), (200, 100))
    igual("un fichero vacío no es una imagen",
          editar.tamano_imagen(fichero("vacio.bin")), None)


def prueba_kenburns_mete_zoompan():
    """El zoom por dentro va con zoompan, que es lo único que anima un tamaño
    de verdad; conserva la huella (s=an×al de la capa) y su rampa recorre la
    ventana."""
    ruta = png_de_prueba("kb.png", 200, 100)
    texto, _ = editar.grafo(con_capas(
        [capa(ruta=ruta, kenburns={"desde": 1.0, "hasta": 1.25})]))
    igual("zoompan con la rampa de la ventana",
          "zoompan=z='1.0000+0.2500*clip((it-2.0000)/2.0000,0,1)'" in texto,
          True)
    igual("la huella no cambia: 480×240 de un PNG 2:1",
          "s=480x240" in texto, True)
    igual("y se escala de más antes de recortar", "scale=602:-1" in texto, True)


def prueba_kenburns_sin_tamano_se_queda_quieto():
    """Una imagen que no se puede medir no puede respirar: capa quieta, y el
    render sale igual que siempre en vez de caerse."""
    texto, _ = editar.grafo(con_capas(
        [capa(kenburns={"desde": 1.0, "hasta": 1.25})]))
    #  Ojo: el zoompan de la CÁMARA siempre está; lo que no puede aparecer es
    #  el del Ken Burns, que se reconoce por su rampa con `it`.
    igual("sin tamaño no hay zoompan de capa", "*clip((it-" in texto, False)
    igual("la escala de siempre", "scale=480:-1" in texto, True)


def prueba_kenburns_suave_lleva_smoothstep():
    ruta = png_de_prueba("kb2.png", 100, 100)
    texto, _ = editar.grafo(con_capas(
        [capa(ruta=ruta, suave=True,
              kenburns={"desde": 1.25, "hasta": 1.0})]))
    igual("la rampa del zoom también se suaviza",
          "*(3-2*clip((it-2.0000)/2.0000,0,1))'" in texto, True)


def prueba_pista_limpia_mete_afftdn():
    """La limpieza va por pista y ANTES del volumen: se quita el soplido del
    original y luego se sube lo limpio."""
    p = plan([{"id": 1, "fuente": 1, "desde": 0, "hasta": 8}])
    p["fuentes"][0]["pistas"][0]["limpia"] = True
    texto, _ = editar.grafo(p)
    igual("afftdn delante del volumen",
          "afftdn=nr=12:nf=-25,volume=" in texto, True)
    p["fuentes"][0]["pistas"][0]["limpia"] = False
    texto, _ = editar.grafo(p)
    igual("apagada no filtra nada", "afftdn" in texto, False)


def prueba_capa_de_audio_que_se_agacha():
    """La música con `agachar` pasa por sidechaincompress con la voz del
    vídeo de llave, y la llave sale de un asplit de la mezcla."""
    p = plan([{"id": 1, "fuente": 1, "desde": 0, "hasta": 8}])
    p["capas"] = [{"id": 1, "tipo": "audio", "ruta": fichero("musica.mp3"),
                   "t0": 0.0, "t1": 8.0, "volumen": 0.8, "banda": 2,
                   "agachar": True}]
    texto, _ = editar.grafo(p)
    igual("la mezcla se reparte en copias", "[mez]asplit=2[mezv][llave0]"
          in texto, True)
    igual("y la música pasa por el compresor con su llave",
          "[ax0][llave0]sidechaincompress=" in texto, True)
    p["capas"][0]["agachar"] = False
    texto, _ = editar.grafo(p)
    igual("sin agachar no hay compresor", "sidechaincompress" in texto, False)


def prueba_capa_de_audio_con_escoba():
    """`limpia` en una capa de audio mete `afftdn` ANTES del volumen, igual
    que en una pista del vídeo: se limpia el original y luego se sube."""
    p = plan([{"id": 1, "fuente": 1, "desde": 0, "hasta": 8}])
    p["capas"] = [{"id": 1, "tipo": "audio", "ruta": fichero("voz.m4a"),
                   "t0": 0.0, "t1": 8.0, "volumen": 0.5, "banda": 2,
                   "limpia": True}]
    texto, _ = editar.grafo(p)
    igual("la capa se limpia", "afftdn=nr=12:nf=-25" in texto, True)
    igual("y la escoba va delante del volumen",
          texto.index("afftdn=nr=12:nf=-25") < texto.index("volume=0.500"),
          True)
    p["capas"][0]["limpia"] = False
    texto, _ = editar.grafo(p)
    igual("apagada no filtra nada", "afftdn" in texto, False)


def prueba_agacharse_con_otra_capa():
    """Con `llave` apuntando a otra capa, la que manda es ESA y no el vídeo:
    su señal se reparte con un asplit y la mezcla del vídeo no se toca."""
    p = plan([{"id": 1, "fuente": 1, "desde": 0, "hasta": 8}])
    #  La 1 es la música que se agacha; la 2, la locución que la manda.
    p["capas"] = [{"id": 1, "tipo": "audio", "ruta": fichero("musica.mp3"),
                   "t0": 0.0, "t1": 8.0, "volumen": 0.8, "banda": 2,
                   "agachar": True, "llave": 2},
                  {"id": 2, "tipo": "audio", "ruta": fichero("locucion.m4a"),
                   "t0": 0.0, "t1": 8.0, "volumen": 1.0, "banda": 3}]
    texto, _ = editar.grafo(p)
    igual("la locución se reparte para servir de llave",
          "[ax1]asplit=2[axs1][llave0]" in texto, True)
    igual("y la música se agacha con ella",
          "[ax0][llave0]sidechaincompress=" in texto, True)
    igual("la mezcla del vídeo no se reparte: no manda nadie desde ahí",
          "[mez]asplit" in texto, False)
    igual("y la locución entra en la mezcla por su copia, no por la cruda",
          "[axs1]" in texto, True)


def prueba_llave_que_no_existe_cae_al_video():
    """Un id de llave que ya no está —capa borrada, pista silenciada— no deja
    a la capa sin agachado: vuelve a la mezcla del vídeo, que es lo de antes."""
    p = plan([{"id": 1, "fuente": 1, "desde": 0, "hasta": 8}])
    p["capas"] = [{"id": 1, "tipo": "audio", "ruta": fichero("musica.mp3"),
                   "t0": 0.0, "t1": 8.0, "volumen": 0.8, "banda": 2,
                   "agachar": True, "llave": 99}]
    texto, _ = editar.grafo(p)
    igual("cae al vídeo", "[mez]asplit=2[mezv][llave0]" in texto, True)
    #  Y consigo misma tampoco: una capa no puede mandarse a sí misma.
    p["capas"][0]["llave"] = 1
    texto, _ = editar.grafo(p)
    igual("con su propio id, también al vídeo",
          "[mez]asplit=2[mezv][llave0]" in texto, True)


def prueba_agachado_cruzado_no_hace_bucle():
    """A se agacha con B y B con A a la vez. La llave es la señal CRUDA de cada
    una, así que ninguna depende del agachado de la otra: hay dos compresores
    y ningún bucle —que en un grafo de ffmpeg no es un error, es un cuelgue—."""
    p = plan([{"id": 1, "fuente": 1, "desde": 0, "hasta": 8}])
    p["capas"] = [{"id": 1, "tipo": "audio", "ruta": fichero("a.mp3"),
                   "t0": 0.0, "t1": 8.0, "volumen": 1.0, "banda": 2,
                   "agachar": True, "llave": 2},
                  {"id": 2, "tipo": "audio", "ruta": fichero("b.mp3"),
                   "t0": 0.0, "t1": 8.0, "volumen": 1.0, "banda": 3,
                   "agachar": True, "llave": 1}]
    texto, _ = editar.grafo(p)
    igual("las dos se reparten", "[ax0]asplit=2[axs0][llave1]" in texto, True)
    igual("las dos, de verdad", "[ax1]asplit=2[axs1][llave0]" in texto, True)
    igual("y las dos se agachan",
          texto.count("sidechaincompress="), 2)
    igual("cada una se agacha sobre su copia, no sobre la cruda",
          "[axs0][llave0]sidechaincompress=" in texto, True)


def prueba_sonoridad_pone_loudnorm_al_final():
    """El −14 LUFS de YouTube es lo último de todo, y devuelve la frecuencia
    a la norma: loudnorm sale a 192 kHz por dentro."""
    p = plan([{"id": 1, "fuente": 1, "desde": 0, "hasta": 8}])
    texto, _ = editar.grafo(p, sonoridad=True)
    igual("loudnorm cerrando el audio",
          "loudnorm=I=-14:TP=-1.5:LRA=11,aresample=48000[a]" in texto, True)
    texto, _ = editar.grafo(p)
    igual("sin pedirlo no toca el volumen de nadie",
          "loudnorm" in texto, False)


def prueba_maquina_de_escribir():
    """El rótulo se teclea: un drawtext por prefijo, todos anclados en el
    MISMO x de la izquierda —centrar cada prefijo lo haría bailar— y el
    último se queda hasta el final de la capa.

    Se suplanta la medida —65 px, que es lo que PIL da para «Hola» a este
    cuerpo— igual que `prueba_forma_sin_dibujo_no_tumba` suplanta al dibujante.
    Medir de verdad pide PIL y el TTF de Adwaita en su sitio, y donde no están
    `ancho_texto` devuelve None y el efecto degrada a rótulo entero a
    propósito: la prueba veía un solo drawtext y cantaba un fallo que no era.
    Lo que aquí se comprueba es el reparto en pasos y el ancla común, y eso no
    depende de cuánto mida la fuente."""
    de_verdad = editar.ancho_texto
    editar.ancho_texto = lambda texto, tam: 65.0
    try:
        texto, _ = editar.grafo(con_capas(
            [capa(tipo="texto", texto="Hola", tam=0.06, x=0.5,
                  entrada={"tipo": "maquina", "dur": 0.4})]), carpeta=BORRADOR)
    finally:
        editar.ancho_texto = de_verdad
    igual("cuatro letras, cuatro pasos", texto.count("drawtext"), 4)
    #  Lo importante es que el ancla sea LA MISMA en todos los pasos.
    anclas = [l.split("x=")[1].split(":")[0]
              for l in texto.split(";") if "drawtext" in l]
    igual("todos los prefijos arrancan del mismo sitio",
          len(set(anclas)), 1)
    igual("el último paso llega al final de la capa",
          "enable='between(t,2.3000,4.0000)'" in texto, True)
    igual("y el primero empieza con la capa",
          "enable='between(t,2.0000,2.1000)'" in texto, True)


def prueba_transicion_conserva_la_linea():
    """El encadenado NO mueve la línea: cada trozo entrega una cola de más y
    el desplazamiento del xfade cae en la suma de duraciones normales."""
    p = plan([{"id": 1, "fuente": 1, "desde": 0,  "hasta": 4},
              {"id": 2, "fuente": 1, "desde": 6,  "hasta": 8},
              {"id": 3, "fuente": 1, "desde": 10, "hasta": 12}])
    p["transicion"] = {"tipo": "encadenado", "dur": 0.5}
    texto, _ = editar.grafo(p)
    igual("el primer trozo entrega su cola: recorta hasta 4,5",
          "trim=start=0.0000:end=4.5000" in texto, True)
    igual("el xfade del primer corte cae en el 4, no antes",
          "xfade=transition=fade:duration=0.5000:offset=4.0000" in texto, True)
    igual("y el segundo en el 6",
          "offset=6.0000" in texto, True)
    igual("el audio va con acrossfade y la misma cola",
          texto.count("acrossfade=d=0.5000:c1=tri:c2=tri"), 2)
    igual("el último trozo no entrega cola",
          "trim=start=10.0000:end=12.0000" in texto, True)
    igual("y sin concat: la cadena es el pegamento",
          "concat=n=" in texto, False)


def prueba_transicion_corta_se_acota_y_rellena():
    """Con trozos cortos la transición se acota a los vecinos, y si el
    fichero no da más de sí, tpad clona el último fotograma."""
    p = plan([{"id": 1, "fuente": 1, "desde": 19, "hasta": 20},
              {"id": 2, "fuente": 1, "desde": 0, "hasta": 1}])
    p["transicion"] = {"tipo": "barrido", "dur": 1.0}
    texto, _ = editar.grafo(p)
    #  45 % del trozo más corto (1 s) = 0,45; y la fuente acaba en 20, así
    #  que la cola entera sale de clonar.
    igual("la duración se acota al 45 % del corto",
          "xfade=transition=wipeleft:duration=0.4500:offset=1.0000" in texto,
          True)
    igual("y el relleno clona lo que el fichero no da",
          "tpad=stop_mode=clone:stop_duration=0.4500" in texto, True)


def prueba_transicion_apaga_el_fundido_entre():
    """Transición y fundido a negro en los cortes responden a la misma
    pregunta: con transición puesta, manda la transición."""
    p = plan([{"id": 1, "fuente": 1, "desde": 0, "hasta": 4},
              {"id": 2, "fuente": 1, "desde": 6, "hasta": 8}])
    p["fundidos"] = {"entrada": 0, "salida": 0, "entre": 0.5}
    sin_tr, _ = editar.grafo(p)
    igual("sin transición el fundido entre está",
          "fade=t=out" in sin_tr, True)
    p["transicion"] = {"tipo": "encadenado", "dur": 0.3}
    con_tr, _ = editar.grafo(p)
    igual("con transición, el fundido entre calla",
          "fade=t=out" in con_tr, False)


def prueba_forma_entra_por_la_tuberia_de_imagen():
    """Una forma es un PNG dibujado que entra como imagen: mismo overlay,
    mismos efectos, mismas claves. Se siembra el fichero en la carpeta para
    que la caché acierte y la prueba no dependa de magick."""
    import tempfile
    carpeta = tempfile.mkdtemp(prefix="k4-forma-")
    f = capa(tipo="forma", modo="flecha", color="#ff453a", ruta=None)
    del f["ruta"]
    open(os.path.join(carpeta, editar.nombre_forma(f)), "wb").close()

    p = con_capas([f])
    rutas, _, de_capa, _ = editar.entradas(p, carpeta)
    igual("el PNG dibujado está entre las entradas",
          any(r.endswith("forma-flecha-ff453a.png") for r in rutas), True)
    igual("y la capa sabe cuál es el suyo", 1 in de_capa, True)

    texto, _ = editar.grafo(p, carpeta=carpeta)
    igual("la forma pasa por la rama de imagen",
          "[%d:v]" % de_capa[1] in texto and "overlay" in texto, True)

    #  Animada, su PNG entra en bucle como cualquier imagen viva.
    f["entrada"] = {"tipo": "desvanecer", "dur": 0.4}
    rutas, _, _, _ = editar.entradas(p, carpeta)
    args = " ".join(editar.abrir_entradas(p, rutas))
    igual("animada va en bucle hasta su t1+1", "-loop 1 -t 5.000" in args, True)


def prueba_forma_sin_dibujo_no_tumba():
    """Si el dibujo falla —sin magick, disco lleno— la capa se salta y el
    render sale. Se fuerza el fallo suplantando el dibujante."""
    p = con_capas([dict(capa(tipo="forma", modo="marco"), ruta=None)])
    del p["capas"][0]["ruta"]
    de_verdad = editar.dibujar_forma
    editar.dibujar_forma = lambda *a: ""
    try:
        texto, _ = editar.grafo(p)
    finally:
        editar.dibujar_forma = de_verdad
    igual("el grafo sale sin la forma y sin caerse",
          "[base]" in texto and "overlay" not in texto, True)


def prueba_estilos_de_rotulo():
    """Caja, contorno y sombra en el grafo, con colorFondo de color
    secundario; y los planes viejos sin `estilo` conservan su caja."""
    base = {"tipo": "texto", "texto": "Hola", "tam": 0.06,
            "colorFondo": "#102030"}
    texto, _ = editar.grafo(con_capas(
        [capa(**dict(base, estilo="contorno"))]))
    igual("contorno con su trazo al cuerpo de letra",
          "borderw=5:bordercolor=0x102030@1.000" in texto, True)
    texto, _ = editar.grafo(con_capas(
        [capa(**dict(base, estilo="sombra"))]))
    igual("sombra desplazada y translúcida",
          "shadowx=5:shadowy=5:shadowcolor=0x102030@0.650" in texto, True)
    texto, _ = editar.grafo(con_capas(
        [capa(**dict(base, estilo="limpio", fondo=0.5))]))
    igual("limpio no lleva nada", "box=1" in texto or "borderw" in texto
          or "shadowx" in texto, False)
    texto, _ = editar.grafo(con_capas([capa(**dict(base, fondo=0.5))]))
    igual("un plan viejo con fondo sigue con su caja",
          "box=1:boxcolor=0x102030@0.500" in texto, True)


def prueba_a_linea_deshace_el_mapa():
    """Del tiempo del fichero al de la línea, con cortes, reorden y
    velocidad; lo que cayó en un trozo quitado devuelve None."""
    p = plan([{"id": 1, "fuente": 1, "desde": 0,  "hasta": 4},
              {"id": 2, "fuente": 1, "desde": 10, "hasta": 14, "velocidad": 2.0}])
    tramos = editar.mapa(p)
    cerca("dentro del primero", editar.a_linea(tramos, 1.0, 1), 1.0)
    cerca("el 12 del fichero cae en 5: 4 + 2/2x",
          editar.a_linea(tramos, 12.0, 1), 5.0)
    igual("el 7 se quitó al cortar", editar.a_linea(tramos, 7.0, 1), None)
    igual("otra fuente no es este fichero", editar.a_linea(tramos, 1.0, 9), None)


def prueba_srt_sigue_el_mapa():
    """El SRT sale en tiempo de LÍNEA: los segmentos pasan por el mapa y el
    que cayó en un trozo quitado no sale."""
    p = plan([{"id": 1, "fuente": 1, "desde": 0,  "hasta": 4},
              {"id": 2, "fuente": 1, "desde": 10, "hasta": 14}])
    p["transcripcion"] = [
        {"t0": 1.0, "t1": 2.5, "texto": "Se queda"},
        {"t0": 6.0, "t1": 7.0, "texto": "Se fue con el corte"},
        {"t0": 11.0, "t1": 12.0, "texto": "Reaparece movido"}]
    ruta = editar.escribir_srt(p, os.path.join(BORRADOR, "sub.srt"))
    contenido = open(ruta).read()
    igual("el primero, tal cual",
          "00:00:01,000 --> 00:00:02,500\nSe queda" in contenido, True)
    igual("el del trozo quitado no sale", "Se fue" in contenido, False)
    igual("el movido sale en su sitio de línea (11 → 5)",
          "00:00:05,000 --> 00:00:06,000\nReaparece movido" in contenido, True)
    igual("y la numeración no salta", "\n2\n00:00:05,000" in contenido, True)


def prueba_srt_sin_transcripcion_no_escribe():
    p = plan([{"id": 1, "fuente": 1, "desde": 0, "hasta": 4}])
    igual("sin segmentos no hay fichero",
          editar.escribir_srt(p, os.path.join(BORRADOR, "no.srt")), None)
    igual("y no lo ha creado",
          os.path.exists(os.path.join(BORRADOR, "no.srt")), False)


def prueba_keyframes_suaves():
    """`suave: true` mete la smoothstep u²(3−2u) en la expresión; sin él la
    recta de siempre, intacta."""
    ks = [{"t": 1.0, "x": 0.2}, {"t": 3.0, "x": 0.8}]
    recta = editar.expresion_animada({"keyframes": ks}, "x", 0.5)
    igual("recta: pendiente por tramo", "(0.200000+(0.300000)*(t-1.000000))"
          in recta, True)
    suave = editar.expresion_animada({"keyframes": ks, "suave": True}, "x", 0.5)
    igual("suave: la smoothstep con su rampa acotada",
          "*(3-2*clip((t-1.000000)/2.000000,0,1))" in suave, True)
    # En los extremos las dos valen lo mismo: suavizar no mueve los rombos.
    igual("y la recta no lleva smoothstep", "3-2" in recta, False)


def prueba_duracion_manda_el_flujo():
    """En una grabación el audio sigue tras el último fotograma: el contenedor
    dura más que el vídeo, y la línea tiene que medirse por los fotogramas."""
    cerca("el flujo de vídeo manda",
          editar.duracion_sonda("7.400000", "8.047000"), 7.4)


def prueba_duracion_sin_flujo_vale_el_contenedor():
    """webm y mkv no declaran la duración por flujo: ffprobe contesta N/A o
    directamente nada, y entonces el contenedor es lo único que hay."""
    cerca("N/A cae al contenedor",
          editar.duracion_sonda("N/A", "8.047000"), 8.047)
    cerca("sin campo también",
          editar.duracion_sonda(None, "8.047000"), 8.047)


def main():
    pruebas = [v for k, v in sorted(globals().items()) if k.startswith("prueba_")]
    for p in pruebas:
        p()

    if fallos:
        print("%d de %d comprobaciones fallan:\n" % (len(fallos), len(pruebas)))
        for f in fallos:
            print("  " + f + "\n")
        return 1
    print("%d pruebas, todas pasan." % len(pruebas))
    return 0


if __name__ == "__main__":
    sys.exit(main())
