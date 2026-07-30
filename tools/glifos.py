#!/usr/bin/env python3
"""Comprueba que cada icono es el icono que dice ser.

    python3 tools/glifos.py            revisa el proyecto entero
    python3 tools/glifos.py blur       busca por nombre y da el codepoint

Los iconos de la interfaz son glifos de la Nerd Font, y en el código van como
números: `0x000F02E9` con un comentario al lado que dice qué son. El número y el
comentario pueden discrepar y nadie se entera hasta que en la barra aparece un
tenedor donde debía haber un desenfoque. Me ha pasado tres veces.

La fuente trae los nombres de sus propios glifos, así que no hay que fiarse de
la memoria de nadie: se leen y se comparan con lo que dice el comentario.

Solo se revisan los codepoints que llevan comentario con nombre —del estilo
`// md-blur`—; los demás no se pueden comprobar porque no afirman nada.
"""
import os
import re
import sys

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

#  `0x000F02E9   // md-image` y también `0xF0190), // md-content_cut`.
#  El comentario puede ir tras coma, paréntesis o nada.
RE_ICONO = re.compile(
    r"0x0*([0-9A-Fa-f]{4,6})\s*[,)\]]*\s*//\s*([a-z]{2,5}-[a-z0-9_]+)")


def fuente():
    """El fichero de la Nerd Font, preguntándoselo a fontconfig."""
    import subprocess
    for familia in ("MesloLGS Nerd Font Mono", "MesloLGS Nerd Font",
                    "Symbols Nerd Font"):
        p = subprocess.run(["fc-match", "-f", "%{file}", familia],
                           capture_output=True, text=True)
        ruta = p.stdout.strip()
        if ruta and "Nerd" in ruta:
            return ruta
    return ""


def nombres():
    from fontTools.ttLib import TTFont
    ruta = fuente()
    if not ruta:
        print("No encuentro la Nerd Font. ¿Está ttf-meslo-nerd instalado?")
        sys.exit(2)
    f = TTFont(ruta, fontNumber=0)
    return ruta, f.getBestCmap()


def ficheros():
    for base, dirs, hojas in os.walk(RAIZ):
        dirs[:] = [d for d in dirs if d not in (".git", "traducciones")]
        for h in hojas:
            if h.endswith(".qml"):
                yield os.path.join(base, h)


def revisar():
    ruta, cmap = nombres()
    print("Fuente: %s\n" % ruta)

    revisados = malos = 0
    for f in sorted(ficheros()):
        for n, linea in enumerate(open(f, encoding="utf-8"), 1):
            m = RE_ICONO.search(linea)
            if not m:
                continue
            cp = int(m.group(1), 16)
            dice = m.group(2)
            real = cmap.get(cp)
            revisados += 1
            if real == dice:
                continue
            malos += 1
            print("  %s:%d" % (os.path.relpath(f, RAIZ), n))
            print("      dice: %s" % dice)
            print("        es: %s" % (real or "(ningún glifo en ese hueco)"))
            #  Y de paso, dónde está el que quería: es el 90 % del arreglo.
            for c, nombre in cmap.items():
                if nombre == dice:
                    print("     está en: 0x%06X" % c)
                    break

    print("\n%d iconos con nombre, %d mal." % (revisados, malos))
    return 1 if malos else 0


def buscar(texto):
    ruta, cmap = nombres()
    hits = sorted((n, c) for c, n in cmap.items() if texto.lower() in n.lower())
    if not hits:
        print("Nada con «%s»." % texto)
        return 1
    for nombre, cp in hits[:40]:
        print("  0x%06X   %s" % (cp, nombre))
    if len(hits) > 40:
        print("  … y %d más." % (len(hits) - 40))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(buscar(sys.argv[1]) if len(sys.argv) > 1 else revisar())
    except (KeyboardInterrupt, BrokenPipeError):
        sys.exit(0)
