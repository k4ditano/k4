#!/usr/bin/env python3
"""Los límites de los CLI de agentes, en un solo sitio.

Claude Code y Codex te cortan por ventanas de tiempo —las cinco horas, la
semana, y en Claude además un cupo aparte por modelo— y cada uno lo cuenta a
su manera y en su rincón del disco. Esto los lee a los dos y los deja en la
misma forma para que la barra los pinte iguales.

La cifra no se le pide a nadie por la red: ambos programas ya guardan lo que
el servidor les contestó la última vez, así que aquí solo se lee lo que hay.

  · Claude → `~/.claude.json`, campo `cachedUsageUtilization`. Trae los tres
    límites ya calculados, con su porcentaje y cuándo reinicia cada uno.
  · Codex  → el último `token_count` de los rollouts de `~/.codex/sessions`,
    donde viaja el `rate_limits` que devolvió la API.

Eso tiene una consecuencia que hay que enseñar y no esconder: **el dato es de
la última vez que corrió la herramienta**. Por eso cada agente sale con su
`actualizado`, y la vista dice de cuándo es. Un porcentaje viejo presentado
como si fuera de ahora es peor que no tenerlo.

Salida, un JSON por vuelta:

    {"agentes": [{"id": "claude", "nombre": "Claude Code", "plan": "Max 5×",
                  "actualizado": 1785677652,
                  "limites": [{"id": "sesion", "nombre": "5 horas",
                               "pct": 6.0, "reinicia": 1785695999,
                               "activo": true}]}]}

Añadir una herramienta nueva es escribir su lector y una entrada en AGENTES.
"""

import json
import os
import shutil
import sys
from datetime import datetime

CLAUDE_JSON = os.path.expanduser("~/.claude.json")
CODEX_SESIONES = os.path.expanduser("~/.codex/sessions")

#  Cuántos rollouts recientes se miran antes de rendirse. Una sesión recién
#  abierta todavía no ha recibido ningún `rate_limits`, así que el más nuevo
#  no siempre es el que lo trae.
CODEX_ROLLOUTS = 8

#  El final del fichero basta: el `rate_limits` que vale es el último, y un
#  rollout largo son megas que no hace falta parsear enteros.
CODEX_COLA = 256 * 1024


def epoca(iso):
    """Un instante ISO-8601 en segundos desde la época, o None."""
    if not isinstance(iso, str) or not iso:
        return None
    try:
        #  Python no traga la Z hasta 3.11; sustituirla sale más barato que
        #  depender de la versión del intérprete que haya en el equipo.
        return datetime.fromisoformat(iso.replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None


# ── Claude Code ──────────────────────────────────────────────────────

#  El nombre del plan viene como identificador de facturación; lo que el
#  usuario reconoce es «Max 5×», no «default_claude_max_5x».
PLANES_CLAUDE = {
    "default_claude_pro": "Pro",
    "default_claude_max_5x": "Max 5×",
    "default_claude_max_20x": "Max 20×",
}

#  Cómo se llama cada clase de límite. `weekly_scoped` no está aquí porque su
#  nombre lo pone el modelo al que se aplica: hoy Fable, mañana otro.
NOMBRES_CLAUDE = {
    "session": ("sesion", "5 horas"),
    "weekly_all": ("semanal", "Semanal"),
}


def lee_claude():
    """`~/.claude.json` → los tres límites de la suscripción.

    El fichero es el estado entero de Claude Code —proyectos, banderas,
    historial— y el trozo que interesa es `cachedUsageUtilization`, que la
    herramienta refresca cada vez que habla con el servidor.
    """
    try:
        with open(CLAUDE_JSON, encoding="utf-8") as f:
            datos = json.load(f)
    except (OSError, ValueError):
        return None

    cache = datos.get("cachedUsageUtilization")
    if not isinstance(cache, dict):
        return {"limites": [], "razon": "sin datos todavía"}

    uso = cache.get("utilization") or {}
    cuenta = datos.get("oauthAccount") or {}
    tier = cuenta.get("userRateLimitTier") or cuenta.get("organizationRateLimitTier")

    limites = []
    for lim in uso.get("limits") or []:
        if not isinstance(lim, dict):
            continue

        clase = lim.get("kind")
        if clase in NOMBRES_CLAUDE:
            ident, nombre = NOMBRES_CLAUDE[clase]
        else:
            #  Un cupo con dueño: el de un modelo concreto. El nombre que se
            #  enseña es el suyo, que es como lo llama quien lo gasta.
            ambito = lim.get("scope") or {}
            modelo = (ambito.get("modelo") or ambito.get("model") or {})
            titulo = modelo.get("display_name") or modelo.get("id")
            if not titulo:
                continue
            ident = str(titulo).lower().replace(" ", "-")
            nombre = titulo

        limites.append({
            "id": ident,
            "nombre": nombre,
            "pct": float(lim.get("percent") or 0),
            "reinicia": epoca(lim.get("resets_at")),
            "activo": bool(lim.get("is_active")),
        })

    fetched = cache.get("fetchedAtMs")
    return {
        "plan": PLANES_CLAUDE.get(tier, tier or ""),
        "actualizado": fetched / 1000 if isinstance(fetched, (int, float)) else None,
        "limites": limites,
    }


# ── Codex ────────────────────────────────────────────────────────────

def rollouts_recientes():
    """Los rollouts de Codex, del más nuevo al más viejo."""
    encontrados = []
    for raiz, _, ficheros in os.walk(CODEX_SESIONES):
        for nombre in ficheros:
            if nombre.startswith("rollout-") and nombre.endswith(".jsonl"):
                ruta = os.path.join(raiz, nombre)
                try:
                    encontrados.append((os.path.getmtime(ruta), ruta))
                except OSError:
                    continue
    encontrados.sort(reverse=True)
    return [ruta for _, ruta in encontrados[:CODEX_ROLLOUTS]]


def ultimo_limite(ruta):
    """El último `rate_limits` de un rollout, con su instante."""
    try:
        with open(ruta, "rb") as f:
            f.seek(0, os.SEEK_END)
            tamano = f.tell()
            f.seek(max(0, tamano - CODEX_COLA))
            #  Si se ha cortado por el medio, la primera línea del trozo está
            #  mutilada; se descarta sin más.
            trozo = f.read().decode("utf-8", "replace")
    except OSError:
        return None

    lineas = trozo.split("\n")
    if len(lineas) > 1 and trozo and not trozo.startswith("{"):
        lineas = lineas[1:]

    for linea in reversed(lineas):
        if '"rate_limits"' not in linea:
            continue
        try:
            reg = json.loads(linea)
        except ValueError:
            continue
        info = ((reg.get("payload") or {}).get("rate_limits"))
        if isinstance(info, dict):
            return info, epoca(reg.get("timestamp"))
    return None


def ventana(datos, ident):
    """Una ventana de Codex —`primary` o `secondary`— en la forma de la casa.

    El nombre lo pone la duración, que es lo que el usuario entiende: Codex
    dice «10080 minutos» donde uno piensa «la semana». Y no siempre publica
    las dos: en un plan con una sola ventana, `secondary` viene vacío.
    """
    if not isinstance(datos, dict):
        return None

    minutos = datos.get("window_minutes") or 0
    if minutos >= 10080:
        nombre = "Semanal"
    elif minutos >= 1440:
        nombre = "%d días" % round(minutos / 1440)
    elif minutos >= 60:
        nombre = "%d horas" % round(minutos / 60)
    else:
        nombre = "%d min" % minutos

    return {
        "id": ident,
        "nombre": nombre,
        "pct": float(datos.get("used_percent") or 0),
        "reinicia": datos.get("resets_at"),
        # Codex no dice cuál está en curso: cuenta la que va más apurada.
        "activo": True,
    }


def lee_codex():
    """El `rate_limits` que Codex dejó escrito en su último turno."""
    if not os.path.isdir(CODEX_SESIONES):
        return None

    hallazgo = None
    for ruta in rollouts_recientes():
        hallazgo = ultimo_limite(ruta)
        if hallazgo:
            break

    if not hallazgo:
        return {"limites": [], "razon": "sin datos todavía"}

    info, cuando = hallazgo
    limites = [v for v in (ventana(info.get("primary"), "primaria"),
                           ventana(info.get("secondary"), "secundaria")) if v]

    plan = info.get("plan_type") or ""
    creditos = info.get("credits") or {}

    agente = {
        "plan": plan.title(),
        "actualizado": cuando,
        "limites": limites,
    }
    #  Los créditos solo se enseñan si los hay: una fila con un cero eterno
    #  ocupa sitio y no dice nada.
    if creditos.get("unlimited"):
        agente["creditos"] = "sin límite"
    elif creditos.get("has_credits"):
        agente["creditos"] = str(creditos.get("balance") or "")
    return agente


# ── el registro ──────────────────────────────────────────────────────

AGENTES = [
    ("claude", "Claude Code", "claude", lee_claude),
    ("codex", "Codex", "codex", lee_codex),
]


def mira():
    """Todos los agentes instalados, con lo que sepamos de cada uno."""
    salida = []
    for ident, nombre, binario, lector in AGENTES:
        #  Sin el programa no hay módulo: un agente que no está instalado no
        #  merece una tarjeta vacía diciendo que no tiene datos.
        if not shutil.which(binario):
            continue
        try:
            datos = lector()
        except Exception as e:                              # noqa: BLE001
            datos = {"limites": [], "razon": str(e)}
        if datos is None:
            continue

        datos["id"] = ident
        datos["nombre"] = nombre
        salida.append(datos)

    return {"agentes": salida}


if __name__ == "__main__":
    json.dump(mira(), sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")
