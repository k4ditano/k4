#!/usr/bin/env python3
"""Genera los sonidos del Digivice.

    python3 tools/digivice_sonidos.py

Son ondas CUADRADAS sintetizadas aqui, no grabaciones: un juguete de LCD no
tiene altavoz para mas que eso, asi que la fidelidad y la honestidad legal
apuntan al mismo sitio. Nada de esto viene del emulador ni de ningun juego.

WAV sin comprimir a proposito: K4.Sonido carga los WAV con SoundEffect, que
los tiene en memoria y los dispara sin latencia. Lo demas pasa por MediaPlayer
y llega tarde, que en un golpe de combate se nota.

Salen en plugins/Digivice/sonidos/. Pesan unos pocos KB cada uno.
"""
import math
import os
import struct
import wave

RITMO = 22050          # de sobra para pitidos; la mitad de peso que 44100
AMPLITUD = 0.22        # bajo: esto suena en la barra de alguien que trabaja
HERE = os.path.dirname(os.path.abspath(__file__))
DESTINO = os.path.join(HERE, "..", "plugins", "Digivice", "sonidos")


def cuadrada(frecuencia, ms, volumen=1.0, ciclo=0.5):
    """Un tono cuadrado con sus bordes suavizados.

    Sin el suavizado, empezar y cortar de golpe mete un chasquido en cada
    nota que se oye mas que la nota.
    """
    n = int(RITMO * ms / 1000)
    borde = max(1, int(RITMO * 0.004))     # 4 ms de subida y de bajada
    fuera = []
    for i in range(n):
        fase = (i * frecuencia / RITMO) % 1.0
        v = 1.0 if fase < ciclo else -1.0
        env = min(1.0, i / borde, (n - i) / borde)
        fuera.append(v * env * volumen * AMPLITUD)
    return fuera


def silencio(ms):
    return [0.0] * int(RITMO * ms / 1000)


def ruido(ms, volumen=1.0):
    """Pseudoaleatorio con semilla fija: el mismo golpe cada vez."""
    n = int(RITMO * ms / 1000)
    borde = max(1, int(RITMO * 0.004))
    x = 12345
    fuera = []
    for i in range(n):
        x = (1103515245 * x + 12345) & 0x7FFFFFFF
        v = (x / 0x3FFFFFFF) - 1.0
        env = min(1.0, i / borde, (n - i) / borde) * (1 - i / n)
        fuera.append(v * env * volumen * AMPLITUD)
    return fuera


def escribir(nombre, muestras):
    os.makedirs(DESTINO, exist_ok=True)
    ruta = os.path.join(DESTINO, nombre + ".wav")
    with wave.open(ruta, "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RITMO)
        datos = b"".join(
            struct.pack("<h", max(-32767, min(32767, int(m * 32767))))
            for m in muestras)
        w.writeframes(datos)
    return os.path.getsize(ruta)


#  Las notas, en Hz. Una escala corta basta: los aparatos tenian un zumbador
#  de una sola voz y tiraban de arpegios para todo.
DO, RE, MI, SOL, LA, DO2, MI2, SOL2 = 523, 587, 659, 784, 880, 1047, 1319, 1568

SONIDOS = {
    # los tres botones
    "boton":     cuadrada(1200, 28),
    "elegir":    cuadrada(SOL, 40) + cuadrada(DO2, 55),
    "atras":     cuadrada(SOL, 40) + cuadrada(RE, 55),

    # cuidar
    "comer":     cuadrada(DO2, 45) + cuadrada(MI2, 45) + cuadrada(SOL2, 70),
    "mimar":     cuadrada(MI2, 55) + cuadrada(SOL2, 80),
    "curar":     cuadrada(LA, 60) + cuadrada(DO2, 60) + cuadrada(MI2, 110),

    # el momento grande
    "evolucion": (cuadrada(DO, 70) + cuadrada(MI, 70) + cuadrada(SOL, 70)
                  + cuadrada(DO2, 70) + cuadrada(MI2, 70) + cuadrada(SOL2, 240)),

    # combate
    "golpe":     ruido(60, 0.9) + cuadrada(330, 45),
    "recibido":  cuadrada(180, 130, ciclo=0.25),
    "victoria":  (cuadrada(DO2, 60) + cuadrada(MI2, 60) + cuadrada(SOL2, 60)
                  + silencio(30) + cuadrada(SOL2, 180)),
    "derrota":   (cuadrada(MI, 90) + cuadrada(RE, 90) + cuadrada(DO, 220,
                                                                 ciclo=0.3)),

    #  Recoger: un barrido corto de agudo a grave, que es lo que suena a
    #  escoba sin tener que grabar una escoba.
    "limpiar":   (cuadrada(SOL2, 35) + cuadrada(MI2, 35) + cuadrada(DO2, 35)
                  + cuadrada(LA, 55)),

    #  La llamada en combate: un barrido de grave a agudo, al reves que la
    #  escoba. Es un golpe de poder y tiene que sonar a que sube.
    "invocar":   (cuadrada(DO, 40) + cuadrada(SOL, 40) + cuadrada(DO2, 45)
                  + cuadrada(SOL2, 120)),

    #  Comprar y cobrar: dos notas cortas que suben, como una caja
    #  registradora de juguete. Corta a propósito —se pulsa muchas veces
    #  seguidas en el mercado— y distinta de «acierto», que es de acertar.
    "moneda":    (cuadrada(DO2, 35) + cuadrada(SOL2, 70)),

    #  Un estado que prende: veneno, parálisis o debilidad. Baja en vez de
    #  subir —lo que sube celebra— y lleva un poco de ruido para que suene
    #  sucio. Es el aviso de que algo se te ha quedado pegado encima.
    "estado":    (ruido(35, 0.5) + cuadrada(MI2, 45) + cuadrada(DO2, 45)
                  + cuadrada(SOL, 110, ciclo=0.3)),

    # entrenamiento
    "acierto":   cuadrada(SOL2, 55),
    "fallo":     cuadrada(300, 90, ciclo=0.2),

    #  La llamada: el bicho reclamando. Dos pitidos y silencio, como el
    #  aparato. Va apagada por defecto —hacer ruido sin permiso en la barra
    #  de alguien es pasarse— y se enciende en Ajustes.
    "llamada":   (cuadrada(DO2, 90) + silencio(60) + cuadrada(DO2, 90)),
}

if __name__ == "__main__":
    total = 0
    for nombre, muestras in sorted(SONIDOS.items()):
        peso = escribir(nombre, muestras)
        total += peso
        print(f"  {nombre:10} {peso // 1024:3} KB")
    print(f"{len(SONIDOS)} sonidos, {total // 1024} KB en total")
