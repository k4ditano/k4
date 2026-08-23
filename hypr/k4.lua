-- Generado por el instalador de k4. NO LO EDITES: se reescribe al actualizar.
--
-- Todo lo que k4 necesita de Hyprland: los atajos y el arranque.
--
-- Para revertirlo: borra este fichero y la línea `require("config.k4")` de
-- hyprland.lua. Al actualizar, el instalador puede retirar líneas antiguas de
-- k4 de tus ficheros de Hyprland; antes deja una copia *.k4.bak al lado.
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
local apps = "quickshell ipc -p " .. raiz .. "/shell.qml call k4.apps "
local term = "quickshell ipc -p " .. raiz .. "/shell.qml call k4.term "
local ssh = "quickshell ipc -p " .. raiz .. "/shell.qml call k4.ssh "

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
-- El cajón de aplicaciones de la barra: lo que la propia k4 sabe abrir.
-- Justo al lado del lanzador y a propósito: Space lanza las aplicaciones del
-- escritorio, SHIFT+Space las de la barra. (SUPER+D, que era lo primero que
-- se me ocurrió, ya es «pantalla completa» en la configuración de CachyOS.)
hl.bind(mod .. " + SHIFT + Space", hl.dsp.exec_cmd(apps .. "toggle"))
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
-- Modo dual: la barra se parte en dos, baja por los bordes y se hace dock.
-- Va por atajo global y no por IPC porque no hace falta levantar un proceso
-- para alternarla: la barra recibe la señal del compositor.
--
-- SHIFT y no SUPER+D a secas: esa ya es «pantalla completa» en la
-- configuración de CachyOS, y pisarla no es cosa nuestra.
hl.bind(mod .. " + SHIFT + D",   hl.dsp.global("k4:dual"))

----------------------------------------------------------------------------
-- La terminal
----------------------------------------------------------------------------
-- Nada de SUPER+T a secas: esa abre tu terminal de siempre y no se toca. La
-- de la island va con SHIFT, como el editor con SHIFT+E: misma letra, y la
-- que lleva SHIFT es la de la casa.
--
-- Son la misma sesión vista de dos maneras, y por eso el par tiene sentido:
-- SHIFT la asoma en la island para lo rápido, ALT la MUDA a una ventana
-- grande cuando la cosa se alarga —con lo que esté corriendo dentro, que no
-- se entera de nada.
--
-- Y ALT vale en los dos sentidos: pulsado sobre una ventana de k4term, la
-- sesión se vuelve a la island. Un gesto, no dos.
hl.bind(mod .. " + SHIFT + T",   hl.dsp.exec_cmd(term .. "isla"))
hl.bind(mod .. " + ALT + T",     hl.dsp.exec_cmd(term .. "mudar"))

-- Y los servidores de uno, a dos golpes: se abre, se escriben tres letras y
-- se entra. Los hosts salen de ~/.ssh/config, así que lo que guardes aquí lo
-- aprovechan también ssh, scp y git.
--
-- Va con ALT y no con SHIFT porque SUPER+SHIFT+S ya es tuyo de antes —mandar
-- la ventana al espacio especial—, y quitártelo por esto sería una faena.
hl.bind(mod .. " + ALT + S",     hl.dsp.exec_cmd(ssh .. "abrir"))

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
