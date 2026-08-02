# Medabots como plugin

El primer corte jugable vive en `services/Medabots.qml` y
`plugins/Medabots/`. Se ha construido como una adaptación original para k4:
no carga la ROM, no depende de sus gráficos y no copia código ni recursos del
juego original.

## Qué funciona ahora

- Partida persistente en el estado propio del plugin.
- Recuperación de progreso offline con límite de ocho horas.
- Cinco pestañas: base, robattle, medabots, datos y hangar visual.
- Dos Medabots iniciales seleccionables.
- Medallas con afinidad, objetivo y tres Medafuerces de prueba.
- Medapartes separadas en Head, Right Arm, Left Arm y Legs.
- Robattle por turnos con atacar, cubrirse, victoria, derrota y recompensas.
- Acciones diferenciadas para cabeza, brazo, guardia y carga de Medaforce.
- Créditos, piezas, medallas, misiones y récord.
- Indicador en la píldora cuando hay partida o progreso pendiente.
- Primera lámina visual original generada para fijar la dirección de arte.

## IPC

Con k4 en marcha:

```sh
quickshell ipc -p ~/.config/quickshell/k4/shell.qml call k4.medabots toggle
quickshell ipc -p ~/.config/quickshell/k4/shell.qml call k4.medabots robattle
quickshell ipc -p ~/.config/quickshell/k4/shell.qml call k4.medabots atacar
quickshell ipc -p ~/.config/quickshell/k4/shell.qml call k4.medabots cubrirse
quickshell ipc -p ~/.config/quickshell/k4/shell.qml call k4.medabots brazo
quickshell ipc -p ~/.config/quickshell/k4/shell.qml call k4.medabots medaforce
quickshell ipc -p ~/.config/quickshell/k4/shell.qml call k4.medabots estado
```

En la vista también se puede usar `1–4` para cambiar de pestaña, `A` para
atacar y `D` para cubrirse.

## Siguiente bloque

La siguiente iteración debe sustituir las cifras provisionales por los datos y
reglas verificadas en Edinot: combate 3 contra 3, cabeza del líder, carga y
radiación, objetivo, compatibilidad, rotaciones, zonas, encuentros y
progresión narrativa. Los gráficos y nombres que
se incorporen al plugin deberán ser originales o contar con una licencia que
permita usarlos.
