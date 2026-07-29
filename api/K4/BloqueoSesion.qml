//  Bloquear la sesión de verdad.
//
//  Reexporta WlSessionLock, que habla el protocolo `ext-session-lock`: el
//  compositor dibuja la superficie por encima de todo y le da el teclado en
//  exclusiva, y ninguna ventana puede pintar encima ni escuchar lo que
//  escribes. Eso es lo que separa un bloqueo de una ventana que tapa la
//  pantalla.
//
//  Dos avisos que cuestan caros:
//
//  1. Se abre y se cierra escribiendo `locked`. El `unlock()` que aparece en la
//     documentación existe en C++ pero no está expuesto a QML.
//  2. Si el proceso muere con el bloqueo puesto, el compositor se queda con uno
//     huérfano y cualquier bloqueo posterior es un error de protocolo que mata
//     la conexión del cliente nuevo. No hay arreglo sin cerrar sesión.

import Quickshell.Wayland

WlSessionLock {}
