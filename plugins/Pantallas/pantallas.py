#!/usr/bin/env python3
"""Puente pequeño y auditable entre K4 y la configuración Lua de Hyprland."""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any


def run(args: list[str], *, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(args, text=True, capture_output=True, timeout=12, check=check)


def hypr_json(*args: str) -> Any:
    return json.loads(run(["hyprctl", "-j", *args]).stdout)


def status() -> dict[str, Any]:
    monitors = hypr_json("monitors", "all")
    workspaces = hypr_json("workspaces")
    rules = hypr_json("workspacerules")
    assignments = {str(i): "" for i in range(1, 11)}

    for rule in rules:
        workspace = str(rule.get("workspaceString", ""))
        monitor = str(rule.get("monitor", ""))
        if workspace in assignments and monitor:
            assignments[workspace] = monitor

    # La sesión viva manda sobre una regla antigua.
    for workspace in workspaces:
        name = str(workspace.get("name", ""))
        monitor = str(workspace.get("monitor", ""))
        if name in assignments and monitor:
            assignments[name] = monitor

    return {
        "monitors": monitors,
        "assignments": assignments,
    }


def lua_string(value: str) -> str:
    # Las cadenas JSON dobles son también cadenas Lua válidas.
    return json.dumps(value, ensure_ascii=False)


def clean_payload(raw: dict[str, Any]) -> dict[str, Any]:
    live = {m["name"]: m for m in hypr_json("monitors", "all")}
    monitors: list[dict[str, Any]] = []

    for candidate in raw.get("monitors", []):
        name = str(candidate.get("name", ""))
        if name not in live:
            raise ValueError(f"Monitor desconocido: {name}")

        allowed_modes = set(live[name].get("availableModes", []))
        mode = str(candidate.get("mode", "preferred"))
        if mode != "preferred" and mode not in allowed_modes:
            raise ValueError(f"Modo no disponible para {name}: {mode}")

        scale = float(candidate.get("scale", 1))
        transform = int(candidate.get("transform", 0))
        x = int(candidate.get("x", 0))
        y = int(candidate.get("y", 0))
        if not 0.5 <= scale <= 4:
            raise ValueError(f"Escala fuera de rango para {name}")
        if transform not in (0, 1, 2, 3):
            raise ValueError(f"Rotación no válida para {name}")
        if abs(x) > 32768 or abs(y) > 32768:
            raise ValueError(f"Posición fuera de rango para {name}")

        monitors.append({
            "name": name,
            "mode": mode,
            "x": x,
            "y": y,
            "scale": scale,
            "transform": transform,
        })

    if not monitors:
        raise ValueError("No hay monitores que aplicar")

    known = {m["name"] for m in monitors}
    primary = str(raw.get("primary", monitors[0]["name"]))
    if primary not in known:
        primary = monitors[0]["name"]

    assignments: dict[str, str] = {}
    source = raw.get("assignments", {})
    for number in range(1, 11):
        monitor = str(source.get(str(number), ""))
        if monitor in known:
            assignments[str(number)] = monitor

    return {
        "monitors": monitors,
        "primary": primary,
        "assignments": assignments,
        "persist": bool(raw.get("persist", False)),
    }


def monitor_lua(monitor: dict[str, Any]) -> str:
    scale = f"{monitor['scale']:.2f}".rstrip("0").rstrip(".")
    return (
        "hl.monitor({ output = " + lua_string(monitor["name"])
        + ", mode = " + lua_string(monitor["mode"])
        + ", position = " + lua_string(f"{monitor['x']}x{monitor['y']}")
        + ", scale = " + scale
        + ", transform = " + str(monitor["transform"]) + " })"
    )


def workspace_lua(number: str, monitor: str) -> str:
    return (
        "hl.workspace_rule({ workspace = " + lua_string(number)
        + ", monitor = " + lua_string(monitor)
        + ", default = true, persistent = true })"
    )


def atomic_write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=path.name + ".", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(text)
        if path.exists():
            os.chmod(temporary, path.stat().st_mode & 0o777)
        os.replace(temporary, path)
    except Exception:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        raise


def persist(config: dict[str, Any]) -> None:
    hypr = Path.home() / ".config" / "hypr"
    entry = hypr / "hyprland.lua"
    vars_file = hypr / "config" / "k4-displays-vars.lua"
    displays_file = hypr / "config" / "k4-displays.lua"
    backup = hypr / "hyprland.lua.k4-displays.bak"

    if not backup.exists():
        shutil.copy2(entry, backup)

    ordered = [config["primary"]] + [
        m["name"] for m in config["monitors"] if m["name"] != config["primary"]
    ]
    while len(ordered) < 3:
        ordered.append("")

    variables = (
        "-- Generado por K4 · plugin Pantallas.\n"
        "-- Define los nombres antes de que binds y reglas creen sus objetos.\n\n"
        f"MONITOR1 = {lua_string(ordered[0])}\n"
        f"MONITOR2 = {lua_string(ordered[1])}\n"
        f"MONITOR3 = {lua_string(ordered[2])}\n"
        f"PRIMARY_MONITOR = {lua_string(config['primary'])}\n"
    )
    body = [
        "-- Generado por K4 · plugin Pantallas.",
        "-- Se carga al final para que esta distribución sea la efectiva.",
        "",
    ]
    body.extend(monitor_lua(monitor) for monitor in config["monitors"])
    body.append("")
    body.extend(
        workspace_lua(number, monitor)
        for number, monitor in config["assignments"].items()
    )
    body.append("")
    atomic_write(vars_file, variables)
    atomic_write(displays_file, "\n".join(body))

    text = entry.read_text(encoding="utf-8")
    early_pattern = re.compile(
        r"\n?-- k4-pantallas: variables\n.*?-- /k4-pantallas: variables\n?",
        re.DOTALL,
    )
    late_pattern = re.compile(
        r"\n?-- k4-pantallas: distribución\n.*?-- /k4-pantallas: distribución\n?",
        re.DOTALL,
    )
    text = early_pattern.sub("\n", text)
    text = late_pattern.sub("\n", text).rstrip() + "\n"
    anchor = 'require("config.variables")'
    early = (
        "\n\n-- k4-pantallas: variables\n"
        'require("config.k4-displays-vars")\n'
        "-- /k4-pantallas: variables"
    )
    if anchor not in text:
        raise ValueError("No encuentro config.variables en hyprland.lua")
    text = text.replace(anchor, anchor + early, 1)
    text = text.rstrip() + (
        "\n\n-- k4-pantallas: distribución\n"
        'require("config.k4-displays")\n'
        "-- /k4-pantallas: distribución\n"
    )
    atomic_write(entry, text)


def apply(raw: dict[str, Any]) -> dict[str, Any]:
    config = clean_payload(raw)
    statements = [monitor_lua(monitor) for monitor in config["monitors"]]
    statements.extend(
        workspace_lua(number, monitor)
        for number, monitor in config["assignments"].items()
    )
    result = run(["hyprctl", "eval", "\n".join(statements)], check=False)
    if result.returncode != 0 or "error:" in result.stdout.lower():
        raise RuntimeError((result.stdout + result.stderr).strip() or "Hyprland rechazó la configuración")

    # Mover también los escritorios ya creados. Las reglas gobiernan los nuevos.
    for number, monitor in config["assignments"].items():
        code = (
            "hl.dispatch(hl.dsp.workspace.move({ workspace = "
            + lua_string(number) + ", monitor = " + lua_string(monitor) + " }))"
        )
        run(["hyprctl", "eval", code], check=False)

    if config["persist"]:
        persist(config)

    errors = run(["hyprctl", "configerrors"], check=False).stdout.strip()
    return {
        "ok": not errors,
        "saved": config["persist"],
        "message": errors or ("Guardado y aplicado" if config["persist"] else "Aplicado en esta sesión"),
    }


def main() -> int:
    try:
        if len(sys.argv) < 2 or sys.argv[1] == "status":
            print(json.dumps(status(), ensure_ascii=False))
            return 0
        if sys.argv[1] == "apply" and len(sys.argv) == 3:
            payload = json.loads(sys.argv[2])
            print(json.dumps(apply(payload), ensure_ascii=False))
            return 0
        raise ValueError("Uso: pantallas.py status | apply '<json>'")
    except Exception as exc:
        print(json.dumps({"ok": False, "message": str(exc)}, ensure_ascii=False))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
