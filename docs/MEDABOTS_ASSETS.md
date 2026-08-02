# Plan de assets de Medabots

El juego será nuevo y tendrá una dirección visual propia. No se reutilizarán
los PNG de `plugins/Game/assets`, no se extraerán sprites de la ROM para el
runtime y no se usarán nombres de fichero ni gráficos de la copia original.

La ROM queda restringida a análisis de comportamiento y datos necesarios para
una reimplementación independiente. Los assets de producción serán generados
o dibujados para este proyecto y llevarán una ficha de procedencia.

## Dirección visual

- Pixel-art moderno de alta legibilidad, con siluetas grandes y detalles
  luminosos para que funcione dentro de una island de 760–900 px.
- Robots modulares: cuerpo, cabeza, brazo derecho, brazo izquierdo y piernas
  deben poder mostrarse por separado.
- Arena con capas: fondo, suelo, plataformas, unidades y efectos.
- Efectos breves pero visibles: carga, impacto, destrucción de pieza,
  Medaforce, victoria y derrota.
- UI propia del juego, no un conjunto de tarjetas de k4 con texto añadido.

## Paquetes previstos

```text
plugins/Medabots/assets/
├── robots/       sprites ensamblados y poses de combate
├── parts/        iconos o sprites de Head/Arms/Legs
├── arenas/       fondos y capas de escenario
├── effects/      impactos, carga, Medaforce y estados
├── ui/           marcos, insignias, medallas y botones
└── manifest.json procedencia, licencia y uso de cada asset
```

La primera entrega visual ya cubre una dirección de estilo, un robot jugador,
un rival y una arena de Robattle. El siguiente paquete cubrirá seis piezas
modulares y cuatro efectos. Después se amplía por familias, no generando una
colección enorme de imágenes sin integrarlas en juego.

## Pipeline

1. Generar una hoja de estilo original para fijar silueta, escala, paleta y
   lectura a tamaño pequeño.
2. Generar hojas de poses o piezas sobre un color plano, con una cuadrícula
   explícita y el mismo sujeto/escala en todas las celdas.
3. Partirlas con el utilitario que ya trae k4:

   ```bash
   python3 tools/spritesheet.py hoja-poses.png \
     plugins/Medabots/assets/robots/poses-v1 \
     --filas 2 --columnas 4 --lado 96 --colores 32 \
     --tolerancia 70 --prefijo pose-
   ```

   El script detecta el fondo desde los bordes de cada celda, conserva los
   colores interiores del robot, elimina halos, recorta la caja útil y deja
   todos los frames apoyados en el mismo suelo. Después escala con vecino y
   cuantiza la paleta para evitar sprites borrosos.
4. Retirar fondos de croma en assets individuales cuando se necesite alpha y
   validar bordes.
5. Exportar PNG/WebP para runtime y mantener las hojas fuente fuera del árbol
   cargado por Quickshell; solo entran los frames procesados.
6. Integrar cada paquete en una pantalla real antes de producir el siguiente.

La generación de la hoja no está dentro de `tools`: `spritesheet.py` es el
procesador determinista. La imagen de origen puede venir de ImageGen, de un
dibujo propio o de una herramienta externa, pero siempre se registra su
procedencia y no se incorporan fuentes de la ROM.

### Convención de hojas

- fondo completamente plano, preferiblemente verde croma (`#00ff00`) o un
  color que no aparezca en el personaje;
- sin líneas de cuadrícula, texto, sombras fuera del sujeto ni marcos entre
  celdas;
- todas las celdas con el mismo tamaño y una pose por celda;
- orden de frames documentado en el manifiesto, por ejemplo:
  `idle`, `attack`, `recoil`, `guard`, `charge`, `hit`, `win`, `defeat`;
- el `--lado` será el tamaño de runtime, no el tamaño de la hoja fuente.

## Restricciones

- Sin sprites, fondos, logos, tipografías ni efectos extraídos de la ROM.
- Sin imitar una pantalla concreta del juego original.
- Sin prompts que pidan reproducir un personaje o asset protegido existente.
- Cada asset debe poder sustituirse sin tocar la simulación.
