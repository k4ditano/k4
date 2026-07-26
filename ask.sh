#!/usr/bin/env bash
# Consulta rápida a Codex desde la island.
#   uso: ask.sh <prompt> [imagen] [session_id]
#
# Sin session_id arranca una sesión NUEVA. Con session_id continúa esa y solo esa:
# nunca se usa `--last`, que engancharía con la última sesión de Codex que hubiera
# por ahí (la del terminal, la de la app) y mezclaría contextos.
#
# Detalles que no son evidentes:
#   - `codex exec resume` no acepta `--sandbox` ni `-C`, así que el sandbox va como
#     override de config y el directorio de trabajo lo hereda de la sesión original.
#   - `--image` es multi-valor en `exec`, así que un prompt posicional detrás lo
#     absorbe como si fuera otra imagen; por eso el prompt va por stdin con `-`.
#   - `codex exec` bloquea esperando EOF en stdin cuando no es una tty, y Quickshell
#     le deja el pipe abierto; alimentarlo y cerrarlo lo resuelve.
set -u

prompt=${1:-}
image=${2:-}
session=${3:-}
workdir=${ASK_DIR:-/tmp/k4-ask}

mkdir -p "$workdir"

common=(--json
        --skip-git-repo-check
        -c 'model_reasoning_effort="low"'
        -c 'sandbox_mode="read-only"')

if [ -n "$session" ]; then
    args=(exec resume "${common[@]}")
    [ -n "$image" ] && args+=(--image "$image")
    args+=("$session" -)
else
    args=(exec "${common[@]}" -C "$workdir")
    [ -n "$image" ] && args+=(--image "$image")
    args+=(-)
fi

printf '%s' "$prompt" | codex "${args[@]}"
