//  Un fichero de texto que se lee y se escribe.
//
//  Reexporta el FileView de Quickshell. No se envuelve porque su API ya es la
//  que uno querría —`path`, `text()`, `setText()`, `blockLoading`, `onLoaded`—
//  y reenviarla a mano solo añadiría sitios donde equivocarse.
//
//  `blockLoading` merece una nota: lee de golpe al crearse, sin esperar. Vale
//  para lo pequeño que hace falta ya —un ajuste, un estado— y no para nada que
//  pueda tardar, porque bloquea el hilo de dibujo.

import Quickshell.Io

FileView {}
