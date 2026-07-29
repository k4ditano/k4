#!/usr/bin/env python3
"""Ratón virtual por uinput, para comprobar lo que necesita un ratón de verdad.

    raton.py mueve 960 540      # a esa posición de pantalla
    raton.py clic               # izquierdo donde esté
    raton.py clic 960 540       # mover y pulsar
    raton.py derecho 960 540
    raton.py donde              # dónde está ahora
    raton.py rueda 3            # tres muescas arriba (negativo, abajo)
    raton.py arrastra 100 200 400 200      # arrastre de verdad, en tramos
    raton.py guion "mueve 900 17" "espera 1" "arrastra 900 300 1100 300"

Compañero de teclas.py: el compositor no acepta eventos sintéticos por Wayland,
pero un dispositivo del kernel lo ve como cualquier ratón enchufado.

Se mueve en RELATIVO y no en absoluto a propósito. Un dispositivo absoluto lo
trata libinput como una tableta o una pantalla táctil, con su propio mapeado y
sus sorpresas; con movimiento relativo basta con irse a una esquina —el cursor
se queda pegado al borde— y contar desde ahí. La posición se comprueba luego
preguntándosela a Hyprland, así que no hay que fiarse de la cuenta.
"""
import fcntl, os, socket, struct, sys, time

UI = ord('U')


def _iow(nr, size):
    return (1 << 30) | (size << 16) | (UI << 8) | nr


def _io(nr):
    return (UI << 8) | nr


UI_DEV_CREATE = _io(1)
UI_DEV_DESTROY = _io(2)
UI_DEV_SETUP = _iow(3, 92)
UI_SET_EVBIT = _iow(100, 4)
UI_SET_KEYBIT = _iow(101, 4)
UI_SET_RELBIT = _iow(102, 4)

EV_KEY, EV_REL, EV_SYN = 0x01, 0x02, 0x00
REL_X, REL_Y, REL_WHEEL = 0x00, 0x01, 0x08
BTN_LEFT, BTN_RIGHT, BTN_MIDDLE = 0x110, 0x111, 0x112
SYN_REPORT = 0

BOTONES = {"clic": BTN_LEFT, "izquierdo": BTN_LEFT,
           "derecho": BTN_RIGHT, "medio": BTN_MIDDLE}


def donde():
    """Dónde está el cursor según Hyprland, o None."""
    firma = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", "")
    runtime = os.environ.get("XDG_RUNTIME_DIR", "/run/user/%d" % os.getuid())
    ruta = "%s/hypr/%s/.socket.sock" % (runtime, firma)
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(0.3)
        s.connect(ruta)
        s.sendall(b"cursorpos")
        d = s.recv(256).decode()
        s.close()
        x, y = d.split(",")
        return int(x.strip()), int(y.strip())
    except (OSError, ValueError):
        return None


class Raton:
    def __init__(self):
        self.fd = os.open("/dev/uinput", os.O_WRONLY | os.O_NONBLOCK)
        fcntl.ioctl(self.fd, UI_SET_EVBIT, EV_KEY)
        for b in (BTN_LEFT, BTN_RIGHT, BTN_MIDDLE):
            fcntl.ioctl(self.fd, UI_SET_KEYBIT, b)
        fcntl.ioctl(self.fd, UI_SET_EVBIT, EV_REL)
        for r in (REL_X, REL_Y, REL_WHEEL):
            fcntl.ioctl(self.fd, UI_SET_RELBIT, r)

        nombre = b"k4-raton-de-pruebas"
        nombre += b"\0" * (80 - len(nombre))
        fcntl.ioctl(self.fd, UI_DEV_SETUP,
                    struct.pack("HHHH80sI", 0x03, 0x1234, 0x5679, 1, nombre, 0))
        fcntl.ioctl(self.fd, UI_DEV_CREATE)
        # Al compositor le lleva un momento darse cuenta del dispositivo nuevo.
        time.sleep(1.2)

    def evento(self, tipo, codigo, valor):
        os.write(self.fd, struct.pack("llHHi", 0, 0, tipo, codigo, valor))

    def sync(self):
        self.evento(EV_SYN, SYN_REPORT, 0)

    def paso(self, dx, dy):
        # En trozos: un salto de miles de píxeles de golpe se lo puede comer la
        # aceleración de puntero, y el destino sale corrido.
        while dx or dy:
            px = max(-100, min(100, dx))
            py = max(-100, min(100, dy))
            if px:
                self.evento(EV_REL, REL_X, px)
            if py:
                self.evento(EV_REL, REL_Y, py)
            self.sync()
            dx -= px
            dy -= py
            time.sleep(0.002)

    def ir_a(self, x, y):
        """A una posición de pantalla, corrigiendo con lo que diga Hyprland."""
        #  Si se sabe dónde está, se va en relativo desde ahí. Irse antes a la
        #  esquina parece más seguro y es peor: saca el puntero de lo que
        #  estuviera señalando, y cualquier cosa que reaccione al ratón —la
        #  island se despliega al pasar por encima— se cierra por el camino.
        #  Entonces no se puede pulsar nada que solo exista mientras señalas.
        p = donde()
        if p is not None:
            self.paso(x - p[0], y - p[1])
        else:
            self.paso(-6000, -6000)
            time.sleep(0.08)
            self.paso(x, y)
        time.sleep(0.08)

        # Y se afina, porque la aceleración puede haber desviado la cuenta.
        for _ in range(4):
            p = donde()
            if p is None:
                return
            dx, dy = x - p[0], y - p[1]
            if abs(dx) <= 1 and abs(dy) <= 1:
                return
            self.paso(dx, dy)
            time.sleep(0.06)

    def abajo(self, boton=BTN_LEFT):
        self.evento(EV_KEY, boton, 1)
        self.sync()
        time.sleep(0.04)

    def arriba(self, boton=BTN_LEFT):
        self.evento(EV_KEY, boton, 0)
        self.sync()
        time.sleep(0.05)

    def pulsar(self, boton):
        self.abajo(boton)
        self.arriba(boton)

    def rueda(self, muescas):
        self.evento(EV_REL, REL_WHEEL, muescas)
        self.sync()
        time.sleep(0.05)

    def arrastrar(self, x0, y0, x1, y1, tramos=12):
        """Un arrastre de verdad, en tramos.

        Los tramos no son por realismo: un salto único no genera posiciones
        intermedias, y la mitad de los gestos de QML —que reaccionan a
        onPositionChanged— no llegan a dispararse. Con doce tramos y una pausa
        corta entre ellos, cualquier interfaz se entera.
        """
        self.ir_a(x0, y0)
        self.abajo()
        for i in range(1, tramos + 1):
            objetivo_x = round(x0 + (x1 - x0) * i / tramos)
            objetivo_y = round(y0 + (y1 - y0) * i / tramos)
            # Se mira dónde está de verdad en cada tramo: la aceleración de
            # puntero desvía la cuenta, y en un arrastre el desvío se acumula
            # hasta soltar en otro sitio. Preguntarlo cuesta 0,02 ms.
            p = donde()
            if p is None:
                break
            self.paso(objetivo_x - p[0], objetivo_y - p[1])
            time.sleep(0.02)

        p = donde()
        if p is not None:
            self.paso(x1 - p[0], y1 - p[1])
        time.sleep(0.05)
        self.arriba()

    def cerrar(self):
        fcntl.ioctl(self.fd, UI_DEV_DESTROY)
        os.close(self.fd)


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1

    orden = sys.argv[1]

    if orden == "donde":
        print(donde())
        return 0

    r = Raton()
    try:
        if orden == "guion":
            #  Una secuencia con UN solo dispositivo. Hace falta porque crear
            #  un ratón nuevo por cada paso pierde lo que estuvieras señalando,
            #  y hay cosas —las cápsulas de la island, los menús— que solo
            #  existen mientras señalas.
            #
            #      raton.py guion "mueve 900 17" "espera 1.5" "clic 1217 31"
            for paso in sys.argv[2:]:
                trozos = paso.split()
                if trozos[0] == "mueve":
                    r.ir_a(int(trozos[1]), int(trozos[2]))
                elif trozos[0] == "espera":
                    time.sleep(float(trozos[1]))
                elif trozos[0] == "abajo":
                    if len(trozos) >= 3:
                        r.ir_a(int(trozos[1]), int(trozos[2]))
                    r.abajo()
                elif trozos[0] == "arriba":
                    if len(trozos) >= 3:
                        r.ir_a(int(trozos[1]), int(trozos[2]))
                    r.arriba()
                elif trozos[0] == "rueda":
                    r.rueda(int(trozos[1]))
                elif trozos[0] == "arrastra":
                    r.arrastrar(int(trozos[1]), int(trozos[2]),
                                int(trozos[3]), int(trozos[4]),
                                int(trozos[5]) if len(trozos) > 5 else 12)
                elif trozos[0] in BOTONES:
                    if len(trozos) >= 3:
                        r.ir_a(int(trozos[1]), int(trozos[2]))
                    r.pulsar(BOTONES[trozos[0]])
                print(trozos[0], donde(), flush=True)
        elif orden == "mueve":
            r.ir_a(int(sys.argv[2]), int(sys.argv[3]))
        elif orden == "rueda":
            r.rueda(int(sys.argv[2]))
        elif orden == "arrastra":
            r.arrastrar(int(sys.argv[2]), int(sys.argv[3]),
                        int(sys.argv[4]), int(sys.argv[5]),
                        int(sys.argv[6]) if len(sys.argv) > 6 else 12)
        elif orden in BOTONES:
            if len(sys.argv) >= 4:
                r.ir_a(int(sys.argv[2]), int(sys.argv[3]))
            r.pulsar(BOTONES[orden])
        else:
            print("orden desconocida: %s" % orden, file=sys.stderr)
            return 1
        time.sleep(0.15)
        print(donde())
    finally:
        r.cerrar()
    return 0


if __name__ == "__main__":
    sys.exit(main())
