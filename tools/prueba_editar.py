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
    rutas, idx, _ = editar.entradas(p)
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
    rutas, _, de_capa = editar.entradas(p)
    igual("y es la de abajo", rutas[de_capa[2]], fichero("abajo.png"))

    # Y al revés, para que no pase por casualidad.
    q = con_capas([capa(id=1, ruta=fichero("arriba.png")),
                   capa(id=2, ruta=fichero("abajo.png"))])
    rutas, _, de_capa = editar.entradas(q)
    igual("dando la vuelta a la lista, cambia quién va debajo",
          rutas[de_capa[1]], fichero("arriba.png"))


def prueba_bandas_manda_la_banda():
    """La banda pesa más que el orden de la lista: es lo que se apila."""
    p = con_capas([capa(id=1, banda=3, ruta=fichero("arriba.png")),
                   capa(id=2, banda=1, ruta=fichero("abajo.png"))])
    orden = [c["id"] for c in editar.capas_de(p)]
    igual("la banda 1 va debajo aunque esté después en la lista", orden, [2, 1])

    rutas, _, de_capa = editar.entradas(p)
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


def prueba_capa_sin_fichero():
    """Borrar el PNG meses después no puede impedirte reexportar el vídeo."""
    p = con_capas([capa(ruta=os.path.join(BORRADOR, "esto-no-existe.png"))])
    texto, _ = editar.grafo(p)
    igual("la capa se salta", "overlay=" in texto, False)
    igual("pero el vídeo sale igual", "[zoom]format=yuv420p[v]" in texto, True)


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
    igual("y se coloca por el centro",
          "x=0.2500*w-text_w/2:y=0.7000*h-text_h/2" in texto, True)


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
