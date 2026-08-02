#!/usr/bin/env python3
"""Parte una hoja de sprites generada con Codex en PNG sueltos y transparentes.

    python3 tools/spritesheet.py hoja.png plugins/Medabots/assets/robots/poses --filas 2 --columnas 4 --lado 96 --colores 32

Las hojas se generan fuera de este script, con una herramienta visual o a mano,
y deben llevar fondo de color plano. El fondo NO se quita buscando ese color
por toda la imagen: eso se come los sprites que lo llevan encima —una oruga
morada sobre magenta pierde el cuerpo—. Se rellena por inundación desde los
bordes de cada celda, que es donde el fondo siempre está y el bicho nunca. Así
da igual de qué color sea el personaje.

Después se escala con vecino más próximo y se cuantiza la paleta: lo que
devuelve el generador es un render suave de ~280 px, no pixel art, y al bajarlo
a tamaño de juego sin cuantizar se ve emborronado.
"""
import argparse
import pathlib
from collections import deque

import numpy as np
from PIL import Image


def fondo_por_inundacion(arr, tolerancia):
    """Máscara de fondo: lo que se alcanza desde el borde sin cambiar de color."""
    alto, ancho = arr.shape[:2]
    rgb = arr[:, :, :3].astype(int)

    # color de referencia: la mediana del marco, que es fondo casi seguro
    marco = np.concatenate([rgb[0, :], rgb[-1, :], rgb[:, 0], rgb[:, -1]])
    referencia = np.median(marco, axis=0)

    parecido = np.sqrt(((rgb - referencia) ** 2).sum(axis=2)) < tolerancia

    visto = np.zeros((alto, ancho), dtype=bool)
    cola = deque()

    for x in range(ancho):
        for y in (0, alto - 1):
            if parecido[y, x] and not visto[y, x]:
                visto[y, x] = True
                cola.append((y, x))
    for y in range(alto):
        for x in (0, ancho - 1):
            if parecido[y, x] and not visto[y, x]:
                visto[y, x] = True
                cola.append((y, x))

    while cola:
        y, x = cola.popleft()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < alto and 0 <= nx < ancho and not visto[ny, nx] and parecido[ny, nx]:
                visto[ny, nx] = True
                cola.append((ny, nx))

    return visto


def limar_halo(arr, fondo, referencia, tolerancia):
    """Quita el borde antialiaseado que quedó a medio camino del fondo.

    El relleno se para en esos píxeles porque ya no son del color del fondo,
    pero siguen teniéndolo mezclado y se ven como un halo de color alrededor
    del sprite. Solo se tocan los que tocan el fondo, para no comerse detalles
    del interior del bicho.
    """
    rgb = arr[:, :, :3].astype(int)
    dist = np.sqrt(((rgb - referencia) ** 2).sum(axis=2))
    sospechoso = dist < tolerancia * 2.2

    vecino_fondo = np.zeros_like(fondo)
    vecino_fondo[1:, :] |= fondo[:-1, :]
    vecino_fondo[:-1, :] |= fondo[1:, :]
    vecino_fondo[:, 1:] |= fondo[:, :-1]
    vecino_fondo[:, :-1] |= fondo[:, 1:]

    return fondo | (sospechoso & vecino_fondo)


def procesar(celda, lado, colores, tolerancia):
    arr = np.array(celda.convert("RGBA"))
    fondo = fondo_por_inundacion(arr, tolerancia)

    marco = np.concatenate([arr[0, :, :3], arr[-1, :, :3], arr[:, 0, :3], arr[:, -1, :3]])
    referencia = np.median(marco.astype(int), axis=0)

    # Huecos encerrados: el fondo que queda entre las alas de un dragón o los
    # cuellos de una hidra no se alcanza desde el borde. Se barren aparte, con
    # tolerancia estrecha para no comerse un aura del mismo tono que el fondo.
    dist = np.sqrt(((arr[:, :, :3].astype(int) - referencia) ** 2).sum(axis=2))
    fondo = fondo | (dist < tolerancia * 0.55)

    for _ in range(2):          # dos pasadas: el halo suele tener 1-2 px
        fondo = limar_halo(arr, fondo, referencia, tolerancia)

    filas = np.where(~fondo.all(axis=1))[0]
    cols = np.where(~fondo.all(axis=0))[0]
    if len(filas) == 0 or len(cols) == 0:
        return None

    arr = arr[filas[0]:filas[-1] + 1, cols[0]:cols[-1] + 1]
    fondo = fondo[filas[0]:filas[-1] + 1, cols[0]:cols[-1] + 1]
    arr[fondo] = [0, 0, 0, 0]
    sprite = Image.fromarray(arr, "RGBA")

    escala = lado / max(sprite.width, sprite.height)
    nuevo = (max(1, round(sprite.width * escala)), max(1, round(sprite.height * escala)))
    sprite = sprite.resize(nuevo, Image.NEAREST)

    lienzo = Image.new("RGBA", (lado, lado), (0, 0, 0, 0))
    # pegado abajo: los bichos se apoyan en el suelo, no flotan centrados
    lienzo.paste(sprite, ((lado - nuevo[0]) // 2, lado - nuevo[1]))

    alfa = np.array(lienzo)[:, :, 3]
    rgb = lienzo.convert("RGB").quantize(colors=colores, method=Image.MEDIANCUT).convert("RGB")
    salida = np.dstack([np.array(rgb), np.where(alfa > 128, 255, 0).astype(np.uint8)])
    return Image.fromarray(salida, "RGBA")


def main():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("hoja")
    p.add_argument("destino")
    p.add_argument("--filas", type=int, default=4)
    p.add_argument("--columnas", type=int, default=5)
    p.add_argument("--lado", type=int, default=48, help="tamaño final del sprite")
    p.add_argument("--colores", type=int, default=24)
    p.add_argument("--tolerancia", type=int, default=70)
    p.add_argument("--prefijo", default="s")
    args = p.parse_args()

    hoja = Image.open(args.hoja).convert("RGBA")
    destino = pathlib.Path(args.destino)
    destino.mkdir(parents=True, exist_ok=True)

    ancho = hoja.width / args.columnas
    alto = hoja.height / args.filas
    hechos = 0

    for f in range(args.filas):
        for c in range(args.columnas):
            celda = hoja.crop((round(c * ancho), round(f * alto),
                               round((c + 1) * ancho), round((f + 1) * alto)))
            sprite = procesar(celda, args.lado, args.colores, args.tolerancia)
            if sprite is None:
                print(f"   celda {f},{c} vacía, se salta")
                continue
            sprite.save(destino / f"{args.prefijo}{f * args.columnas + c:02d}.png")
            hechos += 1

    print(f"{hechos} sprites · {args.lado}x{args.lado} · ≤{args.colores} colores → {destino}")


if __name__ == "__main__":
    main()
