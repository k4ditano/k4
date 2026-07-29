#!/usr/bin/env python3
"""Las cuentas del editor, comprobadas sin tocar ffmpeg.

    python3 tools/prueba_editar.py

Aquí solo se prueba lo que es aritmética pura: el mapa entre los dos ejes de
tiempo y el grafo que sale de él. Es justo donde van a salir los fallos, y son
de los que no se ven mirando: un rótulo tres segundos corrido, un zoom que
apunta al trozo de al lado. Un render tarda un minuto y encima tapa el
problema; esto tarda cero.
"""
import sys, os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import editar


fallos = []


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
    rutas, idx = editar.entradas(p)
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
