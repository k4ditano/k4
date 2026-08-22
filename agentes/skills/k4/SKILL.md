---
name: k4
description: >
  Use this whenever the user is on a machine running k4 — the Dynamic
  Island-style bar for Hyprland — and wants to change what the bar does, write
  a plugin for it, or debug one. Triggers: k4, the island, the bar, a k4
  plugin, plugin.json, K4.Plugin, quickshell ipc call k4, pluginReload,
  pluginStatus, ~/.config/k4/plugins, the k4 launcher, the k4 control center,
  the k4 capture tool or its video editor, k4 shortcuts. Also use it when the
  user says "make me a widget/plugin for my bar" and the bar is k4.
---

# k4

[k4](https://github.com/k4ditano/k4) is an extensible bar for Hyprland, built
on Quickshell. It sits collapsed at one edge of the screen and expands when it
has something to show.

**Everything in it is a plugin**, including the parts that look built in: the
clock, the launcher, the control center, the capture tool. There is no
privileged inner circle — the API a stranger's plugin gets is the API the
launcher uses. That is the single most useful thing to know before writing
one, because it means anything you can see the bar do, a plugin can do.

## Where things are

```
~/.config/quickshell/k4/          the bar itself (the repository)
~/.config/k4/plugins/<id>/        plugins the user installed or wrote
~/.local/state/k4/plugins.json    which plugins are on
~/.local/state/k4/k4.log          the log — read this first when something breaks
```

## Read the right guide

- [`plugins.md`](plugins.md) — writing a plugin: the fastest path, the API, permissions, testing it without touching the running bar, publishing it.
- [`barra.md`](barra.md) — driving and debugging the bar itself: IPC, the log, restarting, shortcuts, translations.

## Three things to get right from the start

**Read the log before guessing.** `~/.local/state/k4/k4.log` has the QML
errors, and `quickshell ipc -p ~/.config/quickshell/k4/shell.qml call k4
pluginStatus` tells you which plugins failed and why. A plugin that does not
appear almost always has an error waiting there.

**Never restart the bar to test a plugin.** `python3 tools/plugins.py --test
<id>` opens it in a separate instance with no bar, no services and no
notifications. If it hangs, it hangs alone. Restarting the user's bar loses
whatever they had open.

**Declare what you use.** A plugin lists its permissions in `plugin.json`, and
`tools/plugins.py` checks that list against what the QML actually calls. Using
something you did not declare does not warn — it makes the plugin refuse to
load. That is deliberate, and it is also the fastest way to find out you
forgot one.
