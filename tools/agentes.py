#!/usr/bin/env python3
"""Los límites de los CLI de agentes, en un solo sitio.

Claude Code y Codex te cortan por ventanas de tiempo —las cinco horas, la
semana, y en Claude además un cupo aparte por modelo— y cada uno lo cuenta a
su manera y en su rincón del disco. Esto los lee a los dos y los deja en la
misma forma para que la barra los pinte iguales.

De dónde sale cada uno:

  · Claude → se le pregunta al servidor, con el token que Claude Code ya tiene
    en disco. Es una consulta de lectura de TU propia cuenta y no gasta cupo:
    la misma que hace la herramienta para pintar su `/usage`.
  · Codex  → el último `token_count` de los rollouts de `~/.codex/sessions`,
    donde viaja el `rate_limits` que devolvió la API. No hace falta más: eso
    se reescribe en cada turno, así que está fresco justo mientras lo usas.

Con Claude sí hacía falta. Su caché de disco —`cachedUsageUtilization` en
`~/.claude.json`— se refresca de tarde en tarde: midiendo en este equipo,
decía 6% cuando el servidor decía 24%, con 131 minutos de retraso y una
sesión trabajando por delante. Un módulo de límites que va dos horas por
detrás no sirve para lo único que sirve un módulo de límites, que es decidir
si te queda para lo siguiente.

La caché sigue ahí como respaldo, y esa es la regla: se pregunta, y si no se
puede —sin red, sin token, token caducado— se usa lo último que dejó escrito
la herramienta. Cada agente dice de cuándo es su cifra y por qué vía llegó
(`fuente`), porque un porcentaje viejo presentado como si fuera de ahora es
peor que no tenerlo. Con `--sin-red` no se pregunta nunca.

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
import time
import urllib.request
from datetime import datetime

#  Dónde guarda su estado cada herramienta. Las dos dejan mover su carpeta con
#  una variable de entorno, y quien la mueve suele ser justo quien tiene el
#  disco ordenado a su manera: dar por hecho `~/.claude.json` funcionaría en
#  este equipo y en ningún otro de esos. Se prueban por orden y gana la
#  primera que exista.
CLAUDE_JSONS = [
    os.path.join(os.environ["CLAUDE_CONFIG_DIR"], ".claude.json")
    if os.environ.get("CLAUDE_CONFIG_DIR") else None,
    os.path.expanduser("~/.claude.json"),
]

CODEX_SESIONES = [
    os.path.join(os.environ["CODEX_HOME"], "sessions")
    if os.environ.get("CODEX_HOME") else None,
    os.path.expanduser("~/.codex/sessions"),
]

CLAUDE_CREDENCIALES = [
    os.path.join(os.environ["CLAUDE_CONFIG_DIR"], ".credentials.json")
    if os.environ.get("CLAUDE_CONFIG_DIR") else None,
    os.path.expanduser("~/.claude/.credentials.json"),
]

CLAUDE_USO_URL = "https://api.anthropic.com/api/oauth/usage"

#  La barra sondea cada 20 s con el módulo abierto. Preguntar al servidor cada
#  vez sería maleducado y no serviría de nada: el porcentaje no se mueve tan
#  deprisa. Se guarda la última respuesta y se reusa mientras sea joven, así
#  que da igual cuántas veces se llame a esto — al servidor se va una vez por
#  minuto como mucho.
CLAUDE_CACHE = os.path.join(
    os.environ.get("XDG_STATE_HOME", os.path.expanduser("~/.local/state")),
    "k4", "agentes-uso.json")
CLAUDE_CACHE_SEGUNDOS = 60
CLAUDE_ESPERA = 6


def primero(rutas, comprueba=os.path.exists):
    """La primera ruta de la lista que exista de verdad."""
    for ruta in rutas:
        if ruta and comprueba(ruta):
            return ruta
    return None

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


def limites_claude(uso):
    """La lista `limits` de Claude, en la forma de la casa."""
    limites = []
    for lim in (uso or {}).get("limits") or []:
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
    return limites


def token_claude():
    """El token de Claude Code, si está en disco y no ha caducado.

    No se refresca aquí ni de lejos: refrescarlo ROTA el token, y el siguiente
    que lo intente —la propia herramienta, a mitad de una sesión tuya— se
    encuentra con que el suyo ya no vale. Caducado significa que hoy toca la
    caché, y ya lo renovará quien lo hizo.
    """
    ruta = primero(CLAUDE_CREDENCIALES)
    if not ruta:
        return None
    try:
        with open(ruta, encoding="utf-8") as f:
            oauth = (json.load(f) or {}).get("claudeAiOauth") or {}
    except (OSError, ValueError):
        return None

    caduca = oauth.get("expiresAt")
    if isinstance(caduca, (int, float)) and caduca / 1000 <= time.time():
        return None
    return oauth.get("accessToken") or None


def uso_en_vivo():
    """Le pregunta al servidor por el uso, con la última respuesta guardada.

    Devuelve `(utilization, instante)` o None. Nunca levanta: quedarse sin red
    tiene que degradar a la caché, no dejar el módulo en blanco.
    """
    #  Lo guardado, si todavía vale. Se mira antes que el token para no leer
    #  el fichero de credenciales sin necesidad.
    try:
        with open(CLAUDE_CACHE, encoding="utf-8") as f:
            guardado = json.load(f)
        if time.time() - guardado.get("cuando", 0) < CLAUDE_CACHE_SEGUNDOS:
            return guardado.get("uso"), guardado.get("cuando")
    except (OSError, ValueError):
        guardado = None

    tok = token_claude()
    if not tok:
        return None

    peticion = urllib.request.Request(CLAUDE_USO_URL, headers={
        "Authorization": "Bearer " + tok,
        "anthropic-beta": "oauth-2025-04-20",
        "User-Agent": "k4-agentes/1.0",
    })
    try:
        with urllib.request.urlopen(peticion, timeout=CLAUDE_ESPERA) as r:
            uso = json.loads(r.read().decode("utf-8"))
    except Exception:                                       # noqa: BLE001
        return None

    if not isinstance(uso, dict) or "limits" not in uso:
        return None

    cuando = time.time()
    try:
        os.makedirs(os.path.dirname(CLAUDE_CACHE), exist_ok=True)
        with open(CLAUDE_CACHE, "w", encoding="utf-8") as f:
            #  Se guarda la RESPUESTA, nunca el token: este fichero no tiene
            #  por qué estar tan protegido como el de credenciales.
            json.dump({"cuando": cuando, "uso": uso}, f)
    except OSError:
        pass
    return uso, cuando


def lee_claude(con_red=True):
    """Los límites de la suscripción: del servidor, y si no de la caché."""
    ruta = primero(CLAUDE_JSONS)
    if not ruta:
        return None

    try:
        with open(ruta, encoding="utf-8") as f:
            datos = json.load(f)
    except (OSError, ValueError):
        return None

    cuenta = datos.get("oauthAccount") or {}
    tier = cuenta.get("userRateLimitTier") or cuenta.get("organizationRateLimitTier")
    plan = PLANES_CLAUDE.get(tier, tier or "")

    if con_red:
        vivo = uso_en_vivo()
        if vivo:
            uso, cuando = vivo
            return {"plan": plan, "actualizado": cuando, "fuente": "vivo",
                    "limites": limites_claude(uso)}

    #  El respaldo: lo último que la herramienta dejó escrito. Se refresca de
    #  tarde en tarde, así que aquí importa más que nunca decir de cuándo es.
    cache = datos.get("cachedUsageUtilization")
    if not isinstance(cache, dict):
        return {"limites": [], "plan": plan, "razon": "sin datos todavía"}

    fetched = cache.get("fetchedAtMs")
    return {
        "plan": plan,
        "actualizado": fetched / 1000 if isinstance(fetched, (int, float)) else None,
        "fuente": "cache",
        "limites": limites_claude(cache.get("utilization") or {}),
    }


# ── Codex ────────────────────────────────────────────────────────────

def rollouts_recientes(carpeta):
    """Los rollouts de Codex, del más nuevo al más viejo."""
    encontrados = []
    for raiz, _, ficheros in os.walk(carpeta):
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
    carpeta = primero(CODEX_SESIONES, os.path.isdir)
    if not carpeta:
        return None

    hallazgo = None
    for ruta in rollouts_recientes(carpeta):
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


def mira(con_red=True):
    """Todos los agentes instalados, con lo que sepamos de cada uno."""
    salida = []
    for ident, nombre, binario, lector in AGENTES:
        #  Sin el programa no hay módulo: un agente que no está instalado no
        #  merece una tarjeta vacía diciendo que no tiene datos.
        if not shutil.which(binario):
            continue
        try:
            #  Solo el de Claude tiene a quién preguntar; los demás leen disco
            #  y no quieren saber nada de esto.
            datos = lector(con_red) if lector is lee_claude else lector()
        except Exception as e:                              # noqa: BLE001
            datos = {"limites": [], "razon": str(e)}
        if datos is None:
            continue

        datos["id"] = ident
        datos["nombre"] = nombre
        salida.append(datos)

    return {"agentes": salida}


if __name__ == "__main__":
    json.dump(mira("--sin-red" not in sys.argv), sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")
