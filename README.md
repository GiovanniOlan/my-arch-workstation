# my-arch-workstation

Aprovisionamiento de mi estación de trabajo Arch Linux. Toma una máquina en
blanco y la deja lista para trabajar.

Son dos partes independientes, que se corren una tras otra:

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
zona horaria, disco, hostname, usuario, contraseñas, swap y si debe clonar este
repositorio— y a partir de la confirmación destructiva no vuelve a pedir nada.

Termina en una instalación mínima booteable. Los dotfiles **no** se aplican solos:
el instalador sólo te ahorra el clonado, y al terminar te imprime el comando de la
Parte 2, que es el mismo de la sección siguiente.

## Los dotfiles

Sobre la instalación recién hecha, o sobre cualquier Arch existente:

```
bash <(curl -fsSL https://github.com/GiovanniOlan/my-arch-workstation/raw/main/dotfiles/bootstrap.sh)
```

O, si el repositorio ya está clonado —el caso de venir de la Parte 1—:

```
bash ~/workspaces/my-arch-workstation/dotfiles/bootstrap.sh
```

`bootstrap.sh` hace cuatro cosas y le entrega el control a chezmoi: valida que la
máquina sea Arch con red, instala chezmoi, clona el repositorio si falta y corre
`chezmoi init --apply`. De ahí en adelante todo es chezmoi: paquetes, servicios,
archivos y sesión. Pregunta una sola cosa, el perfil de la máquina (`desktop` o
`laptop`), que es lo único que no puede deducir.

Es el único paso manual, y es deliberado: hay alguien frente al teclado —acaba de
escribir la frase de LUKS y su contraseña—, así que un disparador automático sólo
agregaría maquinaria para ahorrar un comando.

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

## Si algo falla al aplicar

Vuelve a correr `bootstrap.sh`, o directamente `chezmoi apply` si chezmoi ya quedó
inicializado. Ambos son idempotentes y retoman desde donde quedó: los paquetes ya
instalados se saltan y los archivos ya escritos no se reescriben.

La corrida completa queda en `~/.local/state/dotfiles-bootstrap.log`.

Si el fallo fue por falta de red, conéctate con `nmtui` y vuelve a correrlo.

Mientras el escritorio no esté completo, iniciar sesión te deja en una consola de
texto en vez de intentar arrancar un compositor que no existe.

## Desarrollo

`arch-install/dev/` levanta una VM QEMU+OVMF contra la ISO oficial verificada:

```
arch-install/dev/run.sh          # instalar desde la ISO
arch-install/dev/run.sh --boot   # arrancar lo ya instalado
arch-install/dev/vm-check.sh     # revisar una máquina ya aprovisionada
```
