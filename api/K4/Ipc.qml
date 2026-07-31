//  Órdenes que llegan de fuera, normalmente de un atajo de teclado.
//
//  Es una reexportación y no un envoltorio, y a propósito: las funciones se
//  declaran dentro del propio objeto, así que no hay forma de reenviarlas una a
//  una. Lo que aporta es esconder de qué plataforma viene, que es justo el
//  motivo de que exista esta carpeta.
//
//  Ojo si tocas esto: a un IpcHandler NO se le puede adjuntar
//  `Component.onDestruction` —«Non-existent attached object»— y además la
//  caché compilada esconde el error hasta la primera recompilación fresca.
//  Quien desregistra los targets al destruir un plugin es el gestor, apagando
//  `enabled` antes del destroy.
//
//      K4.Ipc {
//          target: "k4.mimodulo"
//          function abrir(): void { ... }
//      }

import Quickshell.Io

IpcHandler {}
