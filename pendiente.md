# Pendiente

Cosas que quedaron fuera de alcance a propósito y hay que retomar después.

## Dotfiles

- **Handy (transcripción) no se instala.** El keybind `SUPER+D` sí queda en
  `hypr/keybinds.lua` y apunta al AppImage, pero nada lo descarga ni lo coloca en
  su ruta. Falta decidir cómo se aprovisiona el binario (candidato:
  `.chezmoiexternal.toml` con la versión pineada) y con qué URL de release.
  Mientras tanto, el atajo existe pero no hace nada hasta que el AppImage esté
  puesto a mano.

- **Brave no se instala.** El keybind `SUPER+SHIFT+T` abre monkeytype con
  `brave --app=...` y hay una window rule para esa ventana, pero `brave` no está
  en `packages.toml`. Mismo caso que Handy: el atajo existe, el binario no. Hay
  que decidir si entra a la lista de paquetes (AUR) o si el atajo se va.

- **La window rule `monkeytype-app` usa otra notación de tamaño.** Declara
  `size = { 1000, 650 }` (tabla de Lua) mientras que el resto de las reglas usa
  `size = "1000 650"` (cadena). Se migró tal cual, sin corregir. Hay que
  verificar cuál acepta Hyprland y unificar.

- **wl-kbptr no se instala: está roto contra Arch actual.** El paquete del AUR
  (`wl-kbptr 0.4.1-2`) compila contra `opencv4`, y Arch ya migró a `opencv 5.0.0`,
  que solo provee `opencv5.pc`. El build falla con `Dependency "opencv4" not
  found`, y una copia ya instalada deja de funcionar tras la actualización
  (`libopencv_core.so.413 => not found`) — de hecho así está hoy en el desktop.
  Se quitó de `packages.toml`; la config de `~/.config/wl-kbptr` y los keybinds
  `SUPER+S` / `SUPER+SHIFT+S` se siguen desplegando. Opciones a evaluar: esperar
  a que el paquete se porte a opencv 5, empaquetar un `opencv4` de compatibilidad,
  o cambiar a otra herramienta de control del puntero por teclado. Volver a
  ponerlo es agregar una línea a `packages.aur.common`.

- **Wallpaper.** Sigue sin haber un setter de fondo de pantalla que persista
  entre reinicios y arranque desde el autostart de Hyprland (candidatos: `swww`,
  `hyprpaper`). Ya estaba pendiente antes de la migración a chezmoi.

- **Monitores del desktop.** `machines.toml` tiene el perfil `desktop` con la
  disposición genérica de catch-all. Hay que reemplazarla con la salida real de
  `hyprctl monitors` en esa máquina.

## Integración entre partes

- **Encadenado Parte 1 → Parte 2.** El instalador de Arch termina en un sistema
  mínimo booteable y no invoca nada de los dotfiles. Conectar su primer arranque
  con `dotfiles/bootstrap.sh` es un change aparte.

- **El loop de desarrollo en la VM contra el encadenado.** Hoy la Parte 2 se
  prueba en la VM montando el share 9p (`/repo`) y corriendo `bootstrap.sh` a
  mano, así que se ejerce el working tree tal cual está, sin commitear. Cuando
  la Parte 1 encadene, el repo dentro de la VM va a ser un clon de GitHub en
  `$HOME`, no el share: la corrida encadenada sólo prueba lo que ya está
  pusheado, y iterar sobre cambios sin commitear exigiría reinstalar la VM
  completa. Hay que decidir si `run.sh --boot` se queda como la vía manual
  contra `/repo` (y la cadena sólo se prueba en corridas completas) o si el
  aprovisionamiento de la VM se apunta al share de alguna forma. Sin resolver:
  no bloquea el encadenado, pero sí afecta la velocidad de iteración.
