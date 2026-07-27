#!/usr/bin/env python3
"""Vigía de gasto en agentes de IA.

Vigila lo que Claude Code y Codex dejan escrito en disco y va anunciando por
la salida estándar cuántos tokens nuevos se han gastado. El juego de la island
lo usa como combustible: si no escribes código con la IA, tu grupo no pelea.

Cada herramienta guarda su historial en JSONL y solo añade al final, así que
basta recordar por qué byte iba cada fichero y leer lo nuevo. Nada de releer
megas en cada vuelta.

Se publican dos cifras por cada trozo nuevo:

  · `tokens`, la cuenta cruda. Es la que se enseña y con la que uno presume.
  · `chispa`, la misma ponderada por lo que cuesta cada clase de token, que es
    lo que mueve el juego. Generar es caro y leer de caché casi gratis: el
    combate debe premiar el trabajo, no tener un contexto enorme.

La primera vez recorre todo el historial y lo manda marcado como `historico`.
Eso llena la estadística con lo que ya habías gastado sin regalar meses de
combate: el depósito solo se llena con lo que gastes de ahora en adelante.

    {"fuentes": {"claude": {"chispa": 1200, "tokens": 9000}},
     "dias": {"2026-07-27": {"chispa": 1200, "tokens": 9000}}}
"""

import json
import os
import sys
import time

ESTADO = os.path.expanduser("~/.local/state/k4/tokens-vigia.json")
INTERVALO = 3.0

# Peso de cada clase de token, en proporción a lo que cuesta.
PESO_SALIDA = 5.0
PESO_ENTRADA = 1.0
PESO_CACHE_ESCRITA = 1.25
PESO_CACHE_LEIDA = 0.1


def mide(entrada=0, salida=0, cache_escrita=0, cache_leida=0):
    """Devuelve (chispa, tokens) para un reparto de tokens."""
    chispa = (entrada * PESO_ENTRADA + salida * PESO_SALIDA
              + cache_escrita * PESO_CACHE_ESCRITA + cache_leida * PESO_CACHE_LEIDA)
    return chispa, entrada + salida + cache_escrita + cache_leida


# ── lectores, uno por herramienta ────────────────────────────────────
#
#  Cada uno recibe un registro ya parseado y devuelve (clave, chispa, tokens),
#  donde la clave sirve para descartar repetidos. Añadir una herramienta nueva
#  es escribir una función y una entrada en FUENTES.

def lee_claude(reg):
    """~/.claude/projects/<proyecto>/<sesión>.jsonl

    Cada mensaje del asistente trae su propio `usage`. El mismo mensaje puede
    aparecer más de una vez —reanudaciones, ramas de subagente—, así que se
    descarta por el id del mensaje.
    """
    msg = reg.get("message")
    if not isinstance(msg, dict):
        return None

    uso = msg.get("usage")
    if not isinstance(uso, dict):
        return None

    chispa, tokens = mide(
        entrada=uso.get("input_tokens", 0),
        salida=uso.get("output_tokens", 0),
        cache_escrita=uso.get("cache_creation_input_tokens", 0),
        cache_leida=uso.get("cache_read_input_tokens", 0),
    )
    return (msg.get("id") or reg.get("uuid"), chispa, tokens)


def lee_codex(reg):
    """~/.codex/sessions/<a>/<m>/<d>/rollout-*.jsonl

    Codex publica un evento `token_count` por turno con dos cifras: el total
    acumulado de la sesión y el del último turno. Vale la del último, que ya
    es el incremento.
    """
    if reg.get("type") != "event_msg":
        return None

    pago = reg.get("payload") or {}
    if pago.get("type") != "token_count":
        return None

    uso = ((pago.get("info") or {}).get("last_token_usage")) or {}
    entrada = uso.get("input_tokens", 0)
    cacheada = uso.get("cached_input_tokens", 0)

    chispa, tokens = mide(
        # `input_tokens` ya incluye lo cacheado: se separa para no cobrar caro
        # lo que se leyó de caché.
        entrada=max(0, entrada - cacheada),
        salida=uso.get("output_tokens", 0),
        cache_escrita=uso.get("cache_write_input_tokens", 0),
        cache_leida=cacheada,
    )
    return (None, chispa, tokens)


FUENTES = [
    {
        "nombre": "claude",
        "raiz": os.path.expanduser("~/.claude/projects"),
        "sufijo": ".jsonl",
        "lector": lee_claude,
    },
    {
        "nombre": "codex",
        "raiz": os.path.expanduser("~/.codex/sessions"),
        "sufijo": ".jsonl",
        "lector": lee_codex,
    },
]


# ── estado entre arranques ───────────────────────────────────────────

def carga_estado():
    try:
        with open(ESTADO) as f:
            return json.load(f).get("offsets", {})
    except Exception:
        return None


def guarda_estado(offsets):
    try:
        os.makedirs(os.path.dirname(ESTADO), exist_ok=True)
        tmp = ESTADO + ".tmp"
        with open(tmp, "w") as f:
            json.dump({"offsets": offsets}, f)
        os.replace(tmp, ESTADO)
    except Exception:
        pass


def ficheros(fuente):
    raiz = fuente["raiz"]
    if not os.path.isdir(raiz):
        return

    for base, _, nombres in os.walk(raiz):
        for n in nombres:
            if n.endswith(fuente["sufijo"]):
                yield os.path.join(base, n)


def suma(acc, clave, chispa, tokens):
    d = acc.setdefault(clave, {"chispa": 0.0, "tokens": 0})
    d["chispa"] += chispa
    d["tokens"] += tokens


def cosecha(fuente, offsets, vistos, fuentes, dias):
    """Lee lo añadido desde la última vuelta y acumula en `fuentes` y `dias`."""
    for ruta in ficheros(fuente):
        try:
            tam = os.path.getsize(ruta)
        except OSError:
            continue

        desde = offsets.get(ruta)

        if desde is None:
            desde = 0
        elif desde > tam:
            # rotado o truncado
            desde = 0

        if desde >= tam:
            offsets[ruta] = tam
            continue

        try:
            with open(ruta, "rb") as f:
                f.seek(desde)
                bruto = f.read(tam - desde)
        except OSError:
            continue

        # Si la última línea va a medias se deja para la vuelta siguiente.
        corte = bruto.rfind(b"\n")
        if corte < 0:
            continue
        offsets[ruta] = desde + corte + 1

        for linea in bruto[:corte].split(b"\n"):
            if not linea.strip():
                continue
            try:
                reg = json.loads(linea)
            except Exception:
                continue

            r = fuente["lector"](reg)
            if not r:
                continue

            clave, chispa, tokens = r
            if tokens <= 0:
                continue

            if clave is not None:
                # Sin esto la cuenta se dispara: una sesion reanudada copia los
                # mensajes anteriores a un fichero nuevo, y el historial de este
                # equipo pasaba de 431M de tokens a 835M cobrando repetidos.
                # Se guarda el hash, que ocupa una fraccion del id.
                marca = hash(fuente["nombre"] + ":" + str(clave))
                if marca in vistos:
                    continue
                vistos.add(marca)

            suma(fuentes, fuente["nombre"], chispa, tokens)

            ts = reg.get("timestamp") or ""
            suma(dias, ts[:10] if len(ts) >= 10 else "", chispa, tokens)


def redondea(acc):
    return {k: {"chispa": round(v["chispa"]), "tokens": v["tokens"]}
            for k, v in acc.items() if k}


def vuelta(offsets, vistos):
    fuentes, dias = {}, {}
    for fuente in FUENTES:
        cosecha(fuente, offsets, vistos, fuentes, dias)

    # Los ids vistos viven solo en memoria y no paran de crecer. Como los
    # offsets ya impiden releer los mismos bytes, vaciarlos de vez en cuando
    # no cuesta nada: lo unico que protegen es el mismo mensaje apareciendo
    # en dos ficheros distintos a la vez.
    if len(vistos) > 400000:
        vistos.clear()

    return redondea(fuentes), redondea(dias)


def main():
    offsets = carga_estado()
    primera_vez = offsets is None
    if offsets is None:
        offsets = {}
    vistos = set()

    if primera_vez:
        # Repaso de todo lo que ya habías gastado. Va marcado para que el juego
        # lo sume a la estadística y no al depósito: la historia se enseña,
        # pero el combustible se gana.
        fuentes, dias = vuelta(offsets, vistos)
        if fuentes:
            print(json.dumps({"historico": True, "fuentes": fuentes, "dias": dias}),
                  flush=True)
        guarda_estado(offsets)

    while True:
        fuentes, dias = vuelta(offsets, vistos)

        if fuentes:
            print(json.dumps({"fuentes": fuentes, "dias": dias}), flush=True)
            guarda_estado(offsets)

        time.sleep(INTERVALO)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(0)
