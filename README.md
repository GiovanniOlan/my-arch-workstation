# my-arch-workstation

Aprovisionamiento de mi estación de trabajo Arch Linux. Toma una máquina en
blanco y la deja lista para trabajar.

Son dos partes que se pueden correr por separado o encadenadas:

- **Parte 1 — Instalación de Arch** (`arch-install/`). Instalación desatendida con
  UEFI, LUKS2, BTRFS con subvolúmenes, swap y snapshots atados a las
  transacciones de pacman. Deja un sistema mínimo booteable.
- **Parte 2 — Dotfiles** (`dotfiles/`). Gestionados con chezmoi. Convierte esa
  instalación mínima en el escritorio de uso diario: paquetes, servicios,
  configuración y sesión.

## Máquina en blanco

Arranca la ISO oficial de Arch y, **antes que nada, conéctate a la red**:

```
iwctl station wlan0 connect <SSID>     # WiFi
```

Con cable no hace falta hacer nada. Esa conexión no se desperdicia: si es WiFi, el
instalador la traslada al NetworkManager del sistema instalado, para que el primer
arranque tenga red.

Después, una sola línea:

```
bash <(curl -fsSL https://github.com/GiovanniOlan/my-arch-workstation/raw/main/arch-install/install.sh)
```

Se usa `bash <(curl …)` y no `curl … | bash` a propósito: con una tubería el script
llega por la entrada estándar y los prompts de contraseña leerían la tubería en vez
del teclado.

El instalador hace todas sus preguntas en un solo bloque al principio —teclado,
zona horaria, disco, hostname, usuario, contraseñas, swap y si debe aplicar los
dotfiles en el primer arranque— y a partir de la confirmación destructiva no vuelve
a pedir nada.

Si aceptas el encadenado, al reiniciar e iniciar sesión los dotfiles se aplican
solos: clona este repositorio en `~/workspaces/my-arch-workstation`, instala
paquetes, habilita servicios y deja el escritorio puesto. Tarda un rato y no
necesita que estés ahí.

## Arch que ya está instalada

Si sólo quieres los dotfiles sobre una Arch existente:

```
bash <(curl -fsSL https://github.com/GiovanniOlan/my-arch-workstation/raw/main/dotfiles/bootstrap.sh)
```

Clona el repositorio si falta, instala chezmoi y aplica. No requiere que esa Arch
venga de la Parte 1.

## Trabajar con los dotfiles

El clon en `~/workspaces/my-arch-workstation` es un clon de Git normal, y es el
mismo que chezmoi tiene registrado como su directorio fuente. El ciclo entre
máquinas es el de siempre:

```
chezmoi edit ~/.config/algo     # editar
chezmoi apply                   # probar en esta máquina
git -C ~/workspaces/my-arch-workstation commit -am "..."
git -C ~/workspaces/my-arch-workstation push
```

Y en las demás estaciones:

```
chezmoi update                  # = git pull + apply
```

**Credenciales de Git:** el clon queda con `origin` en HTTPS, así que la primera vez
que publiques desde una máquina nueva te pedirá usuario y token. Configurar un
credential helper o cambiar el remoto a SSH es un paso manual, a propósito: no hay
forma de automatizarlo sin meter un secreto en el repositorio.

## Si algo falla en el primer arranque

El aprovisionamiento deja una nota en `~/.local/state/first-boot-pending` que sólo
se borra cuando todo termina bien. Si falla, la nota sobrevive y el siguiente
inicio de sesión reintenta desde donde quedó, en vez de arrancar un escritorio a
medias. La corrida completa queda en `~/.local/state/first-boot.log`.

El reintento sí pide contraseña: el primer intento es desatendido por diseño, y la
elevación temporal que lo permite se revoca en cuanto el proceso termina, salga
bien o mal.

Si el fallo fue por falta de red, conéctate con `nmtui` y vuelve a iniciar sesión.

## Desarrollo

`arch-install/dev/` levanta una VM QEMU+OVMF contra la ISO oficial verificada:

```
arch-install/dev/run.sh          # instalar desde la ISO
arch-install/dev/run.sh --boot   # arrancar lo ya instalado
arch-install/dev/vm-check.sh     # revisar una máquina ya aprovisionada
```
