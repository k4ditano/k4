#!/usr/bin/env python3
"""Pasar a texto lo que se dice en un vídeo, con whisper.cpp.

    transcribir.py comprobar
    transcribir.py hacer <video> [--modelo M] [--idioma es] [--salida DIR]

Sirve para dos cosas: subtitular, y —más útil de lo que parece— sacar rótulos
de lo que ya has dicho en voz alta mientras grababas. De ahí que devuelva
segmentos con sus tiempos y no un churro de texto.

**No instala nada.** whisper.cpp son 1,4 GB entre binario y modelo, y descargar
eso sin preguntar no se le hace a nadie: `comprobar` dice qué falta y el editor
enseña el mandato exacto para que lo pongas tú.

Los motivos y las claves son en español pero NO son texto para el usuario: el
QML los traduce con Idioma.t().
"""
import argparse, json, os, re, shutil, subprocess, sys

#  Cómo se llama el binario, por orden de probabilidad.
#
#  whisper.cpp renombró `main` a `whisper-cli` en 2024 y las distribuciones lo
#  empaquetan con uno o con otro según cuándo lo cogieran. Buscar los tres sale
#  más barato que acertar.
BINARIOS = ["whisper-cli", "whisper-cpp", "whisper.cpp", "main"]

#  Dónde suelen estar los modelos. El paquete no trae ninguno: hay que
#  descargarlo aparte, y cada quien lo deja en su sitio.
CARPETAS = [
    os.path.expanduser("~/.cache/whisper"),
    os.path.expanduser("~/.local/share/whisper"),
    os.path.expanduser("~/.local/share/whisper.cpp/models"),
    "/usr/share/whisper.cpp/models",
    "/usr/share/whisper.cpp",
]

# Lo que hay que ejecutar para tenerlo, que es lo que el editor enseña.
COMO = ("sudo pacman -S whisper-cpp && mkdir -p ~/.cache/whisper && "
        "curl -L -o ~/.cache/whisper/ggml-medium.bin "
        "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/"
        "ggml-medium.bin")


def salir(**d):
    print(json.dumps(d, ensure_ascii=False), flush=True)
    sys.exit(0 if d.get("ok", True) else 1)


def buscar_binario():
    for nombre in BINARIOS:
        ruta = shutil.which(nombre)
        if ruta:
            return ruta
    return ""


def buscar_modelos():
    """Los modelos que haya, del más grande al más pequeño.

    Del más grande primero porque en whisper el tamaño ES la calidad, y quien se
    ha descargado el grande lo ha hecho para usarlo.
    """
    vistos = []
    for carpeta in CARPETAS:
        if not os.path.isdir(carpeta):
            continue
        for nombre in sorted(os.listdir(carpeta)):
            if not nombre.endswith(".bin") or "ggml" not in nombre:
                continue
            ruta = os.path.join(carpeta, nombre)
            vistos.append({"ruta": ruta, "nombre": nombre,
                           "bytes": os.path.getsize(ruta)})
    vistos.sort(key=lambda m: -m["bytes"])
    return vistos


def orden_comprobar(args):
    binario = buscar_binario()
    modelos = buscar_modelos()
    falta = "" if (binario and modelos) else ("binario" if not binario
                                              else "modelo")
    salir(ok=True, binario=binario, modelos=modelos, falta=falta, como=COMO)


# ── el SRT que escupe whisper ─────────────────────────────────────
TIEMPO = re.compile(
    r"(\d\d):(\d\d):(\d\d)[,.](\d\d\d)\s*-->\s*(\d\d):(\d\d):(\d\d)[,.](\d\d\d)")


def segundos(h, m, s, ms):
    return int(h) * 3600 + int(m) * 60 + int(s) + int(ms) / 1000.0


def leer_srt(ruta):
    """Los segmentos de un SRT: [{t0, t1, texto}].

    Se parsea aquí y no en el QML por lo de siempre: el formato es un detalle de
    whisper y no tiene por qué salir de este fichero. Y así el editor recibe ya
    números.
    """
    if not os.path.exists(ruta):
        return []
    segmentos = []
    actual = None
    for linea in open(ruta, encoding="utf-8", errors="replace"):
        linea = linea.rstrip("\n")
        m = TIEMPO.search(linea)
        if m:
            if actual:
                segmentos.append(actual)
            actual = {"t0": round(segundos(*m.groups()[0:4]), 3),
                      "t1": round(segundos(*m.groups()[4:8]), 3),
                      "texto": ""}
            continue
        if actual is None:
            continue
        if linea.strip() == "":
            segmentos.append(actual)
            actual = None
            continue
        # Los números de orden del SRT no son texto: se saltan.
        if linea.strip().isdigit() and actual["texto"] == "":
            continue
        actual["texto"] = (actual["texto"] + " " + linea.strip()).strip()
    if actual:
        segmentos.append(actual)
    return [s for s in segmentos if s["texto"]]


def orden_hacer(args):
    if not os.path.exists(args.video):
        salir(ok=False, motivo="sin-video")

    binario = buscar_binario()
    if not binario:
        salir(ok=False, motivo="sin-whisper", como=COMO)

    modelo = args.modelo
    if not modelo:
        modelos = buscar_modelos()
        if not modelos:
            salir(ok=False, motivo="sin-modelo", como=COMO)
        modelo = modelos[0]["ruta"]

    #  Antes de tocar el disco: la carpeta de abajo sale del nombre del propio
    #  vídeo, así que comprobarlo después sería comprobar cuando ya has creado
    #  un directorio a cuenta de lo que dijera el fichero.
    if re.match(r"^[A-Za-z][A-Za-z0-9+.-]*://", args.video or "") \
            or not os.path.exists(args.video):
        salir(ok=False, motivo="no-es-local", detalle=str(args.video))

    carpeta = args.salida or os.path.dirname(os.path.abspath(args.video))
    os.makedirs(carpeta, exist_ok=True)
    base = os.path.join(carpeta, "transcripcion")
    wav = base + ".wav"

    print(json.dumps({"estado": "extrayendo"}), flush=True)
    #  16 kHz y mono porque es lo único que acepta whisper.cpp. Y con `-vn`: el
    #  vídeo aquí no aporta nada y decodificarlo cuesta lo mismo que todo lo
    #  demás junto.
    p = subprocess.run(
        #  Sin red: `args.video` sale del editor, pero el editor lo saca de un
        #  proyecto, y un proyecto puede venir de cualquiera. Un `http://…` aquí
        #  haría que transcribir se trajera lo que dijese el fichero.
        ["ffmpeg", "-protocol_whitelist", "file,crypto,data",
         "-v", "error", "-y", "-i", args.video, "-vn",
         "-ac", "1", "-ar", "16000", "-c:a", "pcm_s16le", wav],
        capture_output=True, text=True)
    if p.returncode != 0 or not os.path.exists(wav):
        salir(ok=False, motivo="sin-audio", detalle=p.stderr.strip()[:200])

    print(json.dumps({"estado": "transcribiendo", "modelo": modelo}), flush=True)
    #  `-osrt` y no la salida por pantalla: el SRT trae los tiempos ya formados y
    #  sirve además para quemar subtítulos más adelante.
    orden = [binario, "-m", modelo, "-f", wav, "-l", args.idioma,
             "-osrt", "-of", base, "--no-prints"]
    r = subprocess.run(orden, capture_output=True, text=True)
    if r.returncode != 0:
        salir(ok=False, motivo="fallo-whisper",
              detalle=(r.stderr or r.stdout).strip()[-300:])

    segmentos = leer_srt(base + ".srt")
    #  El wav es grande y ya no hace falta; el SRT se queda, que pesa nada y
    #  sirve para quemar subtítulos.
    try:
        os.remove(wav)
    except OSError:
        pass

    salir(ok=True, estado="fin", srt=base + ".srt", segmentos=segmentos)


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="orden", required=True)

    sub.add_parser("comprobar")

    h = sub.add_parser("hacer")
    h.add_argument("video")
    h.add_argument("--modelo", default="")
    h.add_argument("--idioma", default="es")
    h.add_argument("--salida", default="")

    args = ap.parse_args()
    {"comprobar": orden_comprobar, "hacer": orden_hacer}[args.orden](args)


if __name__ == "__main__":
    try:
        main()
    except (KeyboardInterrupt, BrokenPipeError):
        sys.exit(0)
