"""Dice QUÉ DIBUJA cada glifo del Digivice, por su nombre real en la fuente.

    python3 tools/digivice_glifos.py

Existe por un fallo que ningún validador podía cazar. Los códigos que había
elegido a ojo **existían todos** en la Nerd Font, así que no faltaba ninguno y
nada daba error; simplemente dibujaban otra cosa:

    ración          U+F1006  ->  md-piggy_bank      (un cerdo)
    ración grande   U+F0F4B  ->  md-file_cabinet    (un archivador)
    carne           U+F0567  ->  md-video_account   (una cámara)
    fruta omni      U+F0E29  ->  md-file_check      (un documento)
    en mal estado   U+F0E1B  ->  md-car_...         (un coche)
    rastro          U+F0BC0  ->  md-rollupjs        (el logo de Rollup.js)
    atacar          U+F0919  ->  md-video_account   (otra cámara)

Un glifo equivocado no rompe nada, no sale en ningún registro y solo se ve
mirando la pantalla, que es justo lo que no se hace en cada cambio. Esto lo
convierte en algo que se lee de un vistazo.

Sale con 1 si algún código NO está en la fuente. Lo demás es para ojos: la
tabla de abajo empareja cada uso con su nombre, y un nombre que no pegue con
la columna «para qué» es un error aunque el programa diga que todo va bien.
"""
import os
import re
import subprocess
import sys

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

#  Para qué se usa cada uno, según el propio código. Se rellena a mano porque
#  es EXACTAMENTE lo que hay que comparar: la intención contra el dibujo.
PARA_QUE = {
    0xF05F2: "comida · ración",
    0xF025A: "comida · ración grande",
    0xF141F: "comida · carne (y el vigor)",
    0xF025B: "comida · fruta omni",
    0xF068C: "comida · en mal estado",
    0xF00A7: "estado · veneno",
    0xF0241: "estado · parálisis (y cargar)",
    0xF0533: "estado · debilidad",
    0xF03E9: "menú · cazar, y los rastros",
    0xF0159: "caza · rastro descartado",
    0xF04E5: "combate · atacar",
    0xF0498: "combate · defender",
    0xF02D1: "corazón lleno · entreno de PV",
    0xF02D5: "corazón vacío",
    0xF04B8: "entreno · pelota (VEL)",
    0xF0A70: "menú · comer",
    0xF10F1: "menú · mimar",
    0xF01E6: "menú · entrenar",
    0xF06EF: "menú · curar",
    0xF00E2: "menú · limpiar",
    0xF0684: "menú · evolución",
    0xF014D: "menú · estado",
    0xF034D: "menú · mapa",
    0xF0AAF: "menú · huevos",
    0xF0827: "menú · guardería",
    0xF05DA: "menú · vistos",
    0xF0156: "menú · salir",
    0xF012C: "requisito cumplido",
    0xF0766: "requisito pendiente",
    0xF0415: "fusión · más",
    0xF0054: "flecha derecha",
    0xF004D: "flecha izquierda",
    0xF02D3: "encuentro visto",
    0xF057E: "ajustes · sonido",
    0x221E: "infinito (ración)",
    0xF1130: "objeto · vitamina",
    0xF0473: "objeto · cinta de correr",
    0xF0391: "objeto · anticuerpo X",
    0xF113B: "objeto · digimental",
    0xF0830: "moneda · bits",
    0xF0538: "menú · objetivos",
    0xF04DC: "menú · mercado",
    0xF02DC: "menú · casa",
    0xF0D2E: "menú · bolsa",
    0xF0787: "menú · duelo (PVP)",
}


def fuente():
    """La misma que usa el tema: core/Theme.qml manda."""
    tema = os.path.join(RAIZ, "core", "Theme.qml")
    nombre = "MesloLGS Nerd Font Mono"
    try:
        with open(tema, encoding="utf-8") as f:
            m = re.search(r'iconFont:\s*"([^"]+)"', f.read())
            if m:
                nombre = m.group(1)
    except OSError:
        pass
    try:
        ruta = subprocess.check_output(
            ["fc-match", "-f", "%{file}", nombre], text=True).strip()
    except (OSError, subprocess.CalledProcessError):
        return nombre, None
    return nombre, ruta or None


def mapa(ruta):
    from fontTools.ttLib import TTFont
    cmap = {}
    for tabla in TTFont(ruta)["cmap"].tables:
        for cp, n in tabla.cmap.items():
            cmap.setdefault(cp, n)
    return cmap


def usados():
    """Los códigos que aparecen en el Digivice, con dónde salen."""
    donde = {}
    objetivos = [
        os.path.join(RAIZ, "services", "DigiviceReglas.js"),
        os.path.join(RAIZ, "services", "Digivice.qml"),
    ]
    dirp = os.path.join(RAIZ, "plugins", "Digivice")
    for n in sorted(os.listdir(dirp)):
        if n.endswith(".qml"):
            objetivos.append(os.path.join(dirp, n))

    for ruta in objetivos:
        try:
            with open(ruta, encoding="utf-8") as f:
                txt = f.read()
        except OSError:
            continue
        rel = os.path.relpath(ruta, RAIZ)
        #  Las dos formas que se usan: "\u{F0123}" y 0xF0123.
        for m in re.finditer(r'\\u\{([0-9A-Fa-f]{4,6})\}', txt):
            donde.setdefault(int(m.group(1), 16), set()).add(rel)
        for m in re.finditer(r'glifo:\s*0x([0-9A-Fa-f]{4,6})', txt):
            donde.setdefault(int(m.group(1), 16), set()).add(rel)
    return donde


def main():
    nombre, ruta = fuente()
    if not ruta or not os.path.exists(ruta):
        print("no encuentro la fuente de iconos (%s)" % nombre)
        return 0                      # sin fuente no se puede juzgar
    try:
        cmap = mapa(ruta)
    except ImportError:
        print("hace falta fontTools para mirar la fuente; me lo salto")
        return 0

    print("fuente: %s\n        %s\n" % (nombre, ruta))
    print("%-9s %-28s %-30s %s" % ("código", "dibuja", "para qué", "dónde"))

    faltan = []
    for cp in sorted(usados()):
        n = cmap.get(cp)
        if n is None:
            faltan.append(cp)
            n = "NO ESTÁ EN LA FUENTE"
        archivos = sorted(usados()[cp])
        print("%-9s %-28s %-30s %s"
              % ("U+%X" % cp, n, PARA_QUE.get(cp, ""),
                 ", ".join(a.split("/")[-1] for a in archivos[:2])))

    if faltan:
        print("\n%d glifos NO están en la fuente: %s"
              % (len(faltan), ", ".join("U+%X" % c for c in faltan)))
        return 1
    print("\nlos %d glifos existen. Comprueba a ojo que «dibuja» y «para qué»"
          "\npeguen: un código válido puede dibujar cualquier otra cosa."
          % len(usados()))
    return 0


if __name__ == "__main__":
    sys.exit(main())
