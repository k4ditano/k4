-- Generado por el instalador de k4. NO LO EDITES: se reescribe al actualizar.
--
-- Todo lo que k4 necesita de Hyprland: los atajos y el arranque.
--
-- Para revertirlo: borra este fichero y la línea `require("config.k4")` de
-- hyprland.lua. No hay nada más que deshacer; el instalador no toca ningún
-- otro fichero tuyo.
--
-- Si alguno de estos atajos choca con uno tuyo, gana el tuyo si lo defines
-- después. La forma limpia de quitar uno es comentarlo en TU configuración y
-- volver a atar la tecla a lo que quieras.

local mod = "SUPER"
local raiz = "@RAIZ@"

-- Las tres llamadas de IPC. `k4` es el objetivo general, que se mantiene por
-- compatibilidad; los módulos nuevos publican el suyo propio.
local k4 = "quickshell ipc -p " .. raiz .. "/shell.qml call k4 "
local captura = "quickshell ipc -p " .. raiz .. "/shell.qml call k4.captura "
local editor = "quickshell ipc -p " .. raiz .. "/shell.qml call k4.editor "

----------------------------------------------------------------------------
-- Arranque
----------------------------------------------------------------------------
-- Se lanza `arrancar` y no `quickshell` a secas a propósito: es quien pone
-- QML_IMPORT_PATH para que los plugins puedan escribir `import K4`. Lanzando
-- quickshell directamente la barra no levanta.
hl.on("hyprland.start", function()
    hl.exec_cmd(raiz .. "/arrancar --no-duplicate -d")
end)

----------------------------------------------------------------------------
-- La island
----------------------------------------------------------------------------
hl.bind(mod .. " + Space",       hl.dsp.exec_cmd(k4 .. "toggleLauncher"))
hl.bind(mod .. " + I",           hl.dsp.exec_cmd(k4 .. "togglePanel"))
hl.bind(mod .. " + X",           hl.dsp.exec_cmd(k4 .. "togglePanel"))
hl.bind(mod .. " + N",           hl.dsp.exec_cmd(k4 .. "toggleNotifications"))
hl.bind(mod .. " + A",           hl.dsp.exec_cmd(k4 .. "toggleNotifications"))
hl.bind(mod .. " + Z",           hl.dsp.exec_cmd(k4 .. "settings"))
hl.bind(mod .. " + Tab",         hl.dsp.exec_cmd(k4 .. "windows"))
hl.bind(mod .. " + SHIFT + W",   hl.dsp.exec_cmd(k4 .. "theme"))
hl.bind(mod .. " + V",           hl.dsp.exec_cmd(k4 .. "clipboard"))
hl.bind(mod .. " + B",           hl.dsp.exec_cmd(k4 .. "files"))
hl.bind(mod .. " + K",           hl.dsp.exec_cmd(k4 .. "keys"))
hl.bind(mod .. " + L",           hl.dsp.exec_cmd(k4 .. "lock"))
hl.bind(mod .. " + ALT + C",     hl.dsp.exec_cmd(k4 .. "session"))

----------------------------------------------------------------------------
-- El asistente
----------------------------------------------------------------------------
-- El texto seleccionado no se adjunta solo: se ofrece en la cabecera y se
-- adjunta con Tab, con un clic en el chip, o abriendo con la última de estas.
hl.bind(mod .. " + G",           hl.dsp.exec_cmd(k4 .. "ask"))
hl.bind(mod .. " + SHIFT + G",   hl.dsp.exec_cmd(k4 .. "askScreen"))
hl.bind(mod .. " + ALT + G",     hl.dsp.exec_cmd(k4 .. "askRegion"))
hl.bind(mod .. " + CONTROL + G", hl.dsp.exec_cmd(k4 .. "askSelection"))

----------------------------------------------------------------------------
-- Multimedia
----------------------------------------------------------------------------
-- `locked` es lo que hace que funcionen con la pantalla bloqueada.
hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd(k4 .. "togglePlay"), { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd(k4 .. "togglePlay"), { locked = true })
hl.bind("XF86AudioNext",  hl.dsp.exec_cmd(k4 .. "nextTrack"),  { locked = true })
hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd(k4 .. "prevTrack"),  { locked = true })

----------------------------------------------------------------------------
-- Capturas y grabación
----------------------------------------------------------------------------
hl.bind(mod .. " + C",           hl.dsp.exec_cmd(captura .. "region"))
hl.bind(mod .. " + CONTROL + C", hl.dsp.exec_cmd(captura .. "anotar"))
hl.bind(mod .. " + Print",       hl.dsp.exec_cmd(captura .. "menu"))
hl.bind("Print",                 hl.dsp.exec_cmd(captura .. "region"))
hl.bind("SHIFT + Print",         hl.dsp.exec_cmd(captura .. "pantalla"))
hl.bind("CONTROL + Print",       hl.dsp.exec_cmd(captura .. "ventana"))
-- Nada de ALT + Print: con Alt pulsado el kernel convierte esa tecla en SysRq y
-- Hyprland ya no ve un "Print", así que la combinación no llega nunca. Probado.

-- La misma tecla arranca y para la grabación: no hay que acordarse de otra.
hl.bind(mod .. " + SHIFT + C",   hl.dsp.exec_cmd(captura .. "grabarAlternar"))

----------------------------------------------------------------------------
-- El editor de vídeo
----------------------------------------------------------------------------
-- Nada de SUPER + E a secas: esa es el gestor de ficheros desde siempre.
hl.bind(mod .. " + SHIFT + E",   hl.dsp.exec_cmd(editor .. "abrir"))
hl.bind(mod .. " + ALT + E",     hl.dsp.exec_cmd(editor .. "retomar"))

----------------------------------------------------------------------------
-- Los clics
----------------------------------------------------------------------------
-- Para que el zoom automático del editor sepa dónde estabas mirando.
-- `non_consuming` es lo que hace que el clic siga llegando a la aplicación: sin
-- eso el ratón dejaría de funcionar en cuanto se cargara esta configuración.
hl.bind("mouse:272", hl.dsp.global("k4:clic"),        { non_consuming = true })
hl.bind("mouse:273", hl.dsp.global("k4:clicDerecho"), { non_consuming = true })
