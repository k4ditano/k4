#!/usr/bin/env python3
"""Capturas de pantalla para k4.

    captura.py foto --ambito pantalla|region|ventana [--geometria "X,Y WxH"]
                    [--salida DP-3] [--cursor] [--destino fichero|portapapeles|ambos|anotar]
    captura.py carpeta --que fotos|videos
    captura.py nombre  --que foto|video

Imprime SIEMPRE una sola línea JSON, y ese es el punto: quien llama distingue
«el usuario canceló» de «grim ha fallado». En el módulo Ask, que fue lo primero
que hubo en este repo, todo el manejo de error es `code === 0`, así que cancelar
una selección y que reviente la captura son indistinguibles.

Los motivos son CLAVES, no frases: los guiones de Python no pasan por el
traductor, así que el texto que lee el usuario lo pone el QML con Idioma.t().
"""
import argparse, json, os, shutil, subprocess, sys, time

TRABAJO = "/tmp/k4-captura"


def salir(**datos):
    print(json.dumps(datos, ensure_ascii=False), flush=True)
    sys.exit(0 if datos.get("ok") else 1)


def carpeta(que):
    """Dónde van fotos y vídeos, según lo que diga el escritorio."""
    clave = "PICTURES" if que == "fotos" else "VIDEOS"
    base = ""
    if shutil.which("xdg-user-dir"):
        base = subprocess.run(["xdg-user-dir", clave],
                              capture_output=True, text=True).stdout.strip()
    if not base or not os.path.isdir(base):
        base = os.path.expanduser("~")
    destino = os.path.join(base, "Capturas")
    os.makedirs(destino, exist_ok=True)
    return destino


def nombre(que):
    """Nombre con sello de fecha, en ASCII y sin espacios.

    No es manía: esta ruta acaba pasando por ffmpeg, por satty y por algún
    `sh -c`, y cualquiera de los tres se atraganta con un espacio o un acento
    en cuanto alguien olvida unas comillas.
    """
    sello = time.strftime("%Y%m%d-%H%M%S")
    if que == "foto":
        ruta = os.path.join(carpeta("fotos"), "captura-%s.png" % sello)
    else:
        ruta = os.path.join(carpeta("videos"), "grabacion-%s.mp4" % sello)

    # El sello llega al segundo, y disparar dos capturas dentro del mismo
    # segundo es de lo más normal —encadenar dos pantallazos seguidos—. Sin
    # esto, la segunda se come a la primera sin decir nada.
    if not os.path.exists(ruta):
        return ruta
    raiz, ext = os.path.splitext(ruta)
    for n in range(2, 100):
        candidata = "%s-%d%s" % (raiz, n, ext)
        if not os.path.exists(candidata):
            return candidata
    return ruta


def region_con_slurp():
    """La región, preguntada con slurp.

    Es el camino de reserva: k4 trae su propio selector, pero si por lo que sea
    no está disponible, más vale una ventana ajena que no poder recortar.
    """
    p = subprocess.run(["slurp", "-d"], capture_output=True, text=True)
    if p.returncode != 0 or not p.stdout.strip():
        return None
    return p.stdout.strip()


def ventana_activa():
    """Geometría de la ventana con el foco, tal y como la ve Hyprland."""
    p = subprocess.run(["hyprctl", "-j", "activewindow"],
                       capture_output=True, text=True)
    if p.returncode != 0:
        return None
    try:
        d = json.loads(p.stdout)
    except json.JSONDecodeError:
        return None
    at, size = d.get("at"), d.get("size")
    if not at or not size:
        return None
    return "%d,%d %dx%d" % (at[0], at[1], size[0], size[1])


def recorte_magick(geometria):
    """De "X,Y WxH" (lo que habla grim) a "WxH+X+Y" (lo que habla magick)."""
    posicion, tamano = geometria.split(" ", 1)
    x, y = posicion.split(",")
    return "%s+%s+%s" % (tamano, x.strip(), y.strip())


def hacer_foto(args):
    geometria = args.geometria

    if args.ambito == "region" and not geometria:
        geometria = region_con_slurp()
        if not geometria:
            salir(ok=False, motivo="cancelado")

    if args.desde and not geometria:
        salir(ok=False, motivo="fallo", detalle="sin-geometria")

    if args.ambito == "ventana" and not geometria:
        geometria = ventana_activa()
        if not geometria:
            salir(ok=False, motivo="fallo", detalle="sin-ventana-activa")

    ruta = args.ruta or nombre("foto")
    os.makedirs(os.path.dirname(ruta), exist_ok=True)

    if args.desde:
        # Recortar de un fotograma ya congelado, en vez de volver a capturar.
        # Es lo que hace que lo que sale sea exactamente lo que veías al
        # encuadrar, y no lo que hubiera en pantalla al soltar el ratón.
        if not os.path.exists(args.desde):
            salir(ok=False, motivo="fallo", detalle="congelado-perdido")
        orden = ["magick", args.desde, "-crop", recorte_magick(geometria),
                 "+repage", ruta]
    else:
        orden = ["grim"]
        if args.cursor:
            orden.append("-c")
        if geometria:
            orden += ["-g", geometria]
        elif args.salida:
            orden += ["-o", args.salida]
        orden.append(ruta)

    p = subprocess.run(orden, capture_output=True, text=True)
    if p.returncode != 0:
        salir(ok=False, motivo="fallo", detalle=p.stderr.strip()[:200])
    if not os.path.exists(ruta) or os.path.getsize(ruta) == 0:
        salir(ok=False, motivo="fallo", detalle="fichero-vacio")

    ancho, alto = medir(ruta)

    # ── a dónde va ────────────────────────────────────────────────
    copiada = False
    if args.destino in ("portapapeles", "ambos"):
        # El `-t` explícito no sobra: sin él, una imagen pegada en otra
        # aplicación se degrada a lo que el portapapeles decida.
        with open(ruta, "rb") as f:
            subprocess.run(["wl-copy", "-t", "image/png"], stdin=f)
        copiada = True

    #  «anotar» sigue aceptándose por si quedó guardado en unos ajustes de
    #  antes, pero ya solo significa «guardar»: el anotador NO se abre solo.
    #  Se abre desde el botón de la tarjeta, cuando se pide. Un programa que
    #  aparece sin que nadie lo llame es un susto, no un atajo.
    guardada = args.destino in ("fichero", "ambos", "anotar")
    if not guardada:
        # Solo al portapapeles: el fichero era un medio, no un fin.
        try:
            os.remove(ruta)
        except OSError:
            pass
        ruta = ""

    salir(ok=True, ruta=ruta, w=ancho, h=alto,
          copiada=copiada, guardada=guardada)


def medir(ruta):
    """Ancho y alto leídos de la cabecera PNG, sin abrir la imagen entera."""
    try:
        with open(ruta, "rb") as f:
            cabecera = f.read(24)
        if len(cabecera) >= 24 and cabecera[:8] == b"\x89PNG\r\n\x1a\n":
            return (int.from_bytes(cabecera[16:20], "big"),
                    int.from_bytes(cabecera[20:24], "big"))
    except OSError:
        pass
    return 0, 0


def etiqueta_audio(d):
    """El nombre que se puede leer, de entre los que trae el dispositivo.

    `description` sería el bueno, pero el pactl de PipeWire lo entrega como la
    cadena «(null)» en los sinks —literalmente esas letras—, así que se mira
    también en las propiedades. Y se recorta: en Ajustes esto va en un chip, y
    «Familia de controladoras de audio de alta definición» no cabe en ninguno.
    """
    p = d.get("properties", {}) or {}
    for candidata in (p.get("node.nick"), p.get("device.description"),
                      d.get("description"), d.get("name")):
        if candidata and candidata != "(null)":
            return candidata[:26] + "…" if len(candidata) > 27 else candidata
    return "?"


def listar_audios():
    """Los micrófonos y las salidas de sonido, para elegirlos en Ajustes.

    Por pactl y no por /sys: aquí lo que importa es lo que ve el servidor de
    sonido, que es a quien wf-recorder y ffmpeg le van a pedir el dispositivo.
    Los monitores no se listan como micrófonos: grabar el sistema ya tiene su
    propio interruptor y su propio camino.
    """
    def pedir(que):
        p = subprocess.run(["pactl", "-f", "json", "list", que],
                           capture_output=True, text=True)
        try:
            return json.loads(p.stdout)
        except (json.JSONDecodeError, ValueError):
            return []

    micros = [{"nombre": s["name"], "etiqueta": etiqueta_audio(s)}
              for s in pedir("sources")
              if (s.get("properties", {}) or {}).get("device.class") != "monitor"]
    salidas = [{"nombre": s["name"], "etiqueta": etiqueta_audio(s)}
               for s in pedir("sinks")]

    #  Y CUÁL es el de por defecto, que es lo que se graba cuando el ajuste
    #  está en «automático». Sin esto, Ajustes decía «automático» a secas y no
    #  había forma de ver que iba a grabar del micro de unos cascos en vez del
    #  de mesa: se descubría al abrir el vídeo y no oír nada.
    def por_defecto(que):
        p = subprocess.run(["pactl", que], capture_output=True, text=True)
        return p.stdout.strip()

    salir(ok=True, microfonos=micros, salidas=salidas,
          micro_defecto=por_defecto("get-default-source"),
          salida_defecto=por_defecto("get-default-sink"))


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="orden", required=True)

    f = sub.add_parser("foto")
    f.add_argument("--ambito", default="pantalla",
                   choices=["pantalla", "region", "ventana"])
    f.add_argument("--geometria", default="")
    f.add_argument("--salida", default="")
    f.add_argument("--ruta", default="")
    f.add_argument("--cursor", action="store_true")
    f.add_argument("--desde", default="",
                   help="recortar de este fotograma en vez de capturar de nuevo")
    f.add_argument("--destino", default="ambos",
                   choices=["fichero", "portapapeles", "ambos", "anotar"])

    c = sub.add_parser("carpeta")
    c.add_argument("--que", default="fotos", choices=["fotos", "videos"])

    n = sub.add_parser("nombre")
    n.add_argument("--que", default="foto", choices=["foto", "video"])

    sub.add_parser("audios")

    args = ap.parse_args()
    os.makedirs(TRABAJO, exist_ok=True)

    if args.orden == "foto":
        hacer_foto(args)
    elif args.orden == "carpeta":
        salir(ok=True, ruta=carpeta(args.que))
    elif args.orden == "nombre":
        salir(ok=True, ruta=nombre(args.que))
    elif args.orden == "audios":
        listar_audios()


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        salir(ok=False, motivo="cancelado")
