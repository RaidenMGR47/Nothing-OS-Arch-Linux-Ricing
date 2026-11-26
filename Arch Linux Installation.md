# Guía de Instalación de Arch Linux (BIOS y UEFI)

Esta guía organiza y explica paso a paso el proceso de instalación de Arch Linux, diferenciando entre sistemas **BIOS (Legacy)** y **UEFI**. Está pensada para ser usada como referencia en **Obsidian** (formato Markdown).

> **📝 Notas de esta revisión**: se corrigieron varios problemas del borrador original: la tabla de particiones no especificaba GPT vs MBR (lo cual dejaba roto `grub-install` en BIOS+GPT sin partición BIOS boot), el paso de montaje mezclaba `/boot` y `/boot/efi` sobre la misma partición, faltaba instalar `os-prober` para que el dual-boot funcionara, y la contraseña de root aparecía marcada como "opcional" cuando en realidad es importante tenerla.
> 
> **🔄 Actualización (12 de noviembre de 2026)**: revisada contra los repositorios y las noticias de Arch a esa fecha. Resumen de cambios:
> 
> - `linux-firmware` ahora es un metapaquete (dividido en `linux-firmware-amdgpu`, `-intel`, `-nvidia`, `-realtek`…).
> - El microcódigo (`intel-ucode` / `amd-ucode`) se instala ya en el `pacstrap`, y si se instala después hay que regenerar también `grub.cfg`.
> - El ISO ya ejecuta `reflector` solo al arrancar; el paso manual quedó como opcional (y con `--protocol https`).
> - `grub-install` para BIOS ahora lleva `--target=i386-pc` explícito.
> - Usuario: basta el grupo `wheel`; corregida la línea de `sudoers` (`%wheel ALL=(ALL:ALL) ALL`).
> - `pacman -Sy archlinux-keyring` a secas era una actualización parcial; ahora va seguido de `-Su`.
> - Drivers de GPU: eliminados los `xf86-video-*`, `libva-mesa-driver` ahora lo trae `mesa`, y NVIDIA pasó a `nvidia-open` (ver la sección de GPU).
> - Eliminada la instalación manual de Xorg para sesiones de escritorio: Plasma 6.8 y GNOME 50+ solo usan Wayland.
> - Las secciones de escritorio se reducen a **terminal + Firefox** (con `sddm` para Plasma, `gdm` para GNOME y `lightdm` para otros entornos).
> 
> **🔄 Actualización (14–15 de noviembre de 2026)**: reescrita la nota extra del monitor (BenQ G925HDA + R5 430) para trabajar desde el tty, añadido el script `monitor-benq-r5430.sh`, fijado **SDDM clásico** para Plasma (en lugar de `plasma-login-manager`, para conservar la personalización con temas), añadida la opción de **LightDM** para cualquier otro entorno, y corregidos detalles menores (`sudo` en chroot, nota sobre `radeon`/`amdgpu` en Oland).
>
> **🔄 Actualización (22 de noviembre de 2026)**: añadido el script `hora-teclado-chroot.sh`, que automatiza dentro del chroot la sincronización de hora (NTP) y el teclado de consola y X11, para que SDDM/LightDM/GDM reconozcan el teclado desde el primer arranque. La sección de idioma y teclado se separó en **idioma**, **zona horaria** y **teclado y hora** (el idioma y la zona horaria siguen siendo manuales), y la sección posterior al arranque pasó a ser solo de comprobación.
>
> **🔄 Actualización (25 de noviembre de 2026)**: añadida la **Opción D: Hyprland + Glyph (estilo Nothing OS)**, un único rice en este repositorio con un instalador adaptado para Arch. El instalador **detecta solo el teclado** (y lo escribe en `user.lua`; se puede forzar con `--keyboard latam`), **detecta el monitor** (y permite fijarlo con `--monitor`), trae atajos adaptados para `latam` y un `uninstall.sh`. Reutiliza la **Base común**, los **Controladores de GPU**, `noto-fonts` y el teclado/hora del chroot, y no toca Plymouth, GRUB, `HOOKS` ni el initramfs.

---

## 🔧 Herramientas y conceptos previos

### Comandos útiles para explorar el sistema

- `fdisk -l` – Muestra las tablas de particiones de todos los discos.
- `lsblk` – Lista los dispositivos de bloque (discos y particiones) de forma jerárquica.
- `lsblk -f` – Muestra los sistemas de archivos y UUIDs.
- `free -h` – Muestra el uso de memoria RAM y swap en formato legible.
- `df -h` – Muestra el espacio usado y disponible en sistemas de archivos montados.
- `blkid` – Lista los UUID y tipos de cada partición.
- `Ctrl+d` – Cierra la terminal o sesión actual.
- `Ctrl+l` – Limpia la pantalla de la terminal.
- `>` – Redirige la salida sobrescribiendo el archivo.
- `>>` – Redirige la salida añadiendo al final del archivo.

### Sistemas de archivos recomendados

- **XFS** – Moderno, escalable, con soporte de _reflinks_ (clonación _copy‑on‑write_ entre archivos). Ideal para compilaciones (ej. Gentoo). **No se puede reducir** de tamaño. Tamaño mínimo recomendado: 300 MiB.
- **EXT2** – Predecesor de ext4, sin _journaling_ (registro de transacciones). Bajo overhead, por eso a veces se usa en particiones `/boot` pequeñas.
- **EXT4** – Fiable y probado, con journaling, pero sin características modernas como reflinks. Buena opción por defecto para `/` y `/home`.
- **FAT32 (VFAT)** – Obligatorio para la partición EFI en sistemas UEFI. No soporta permisos UNIX.
- **Btrfs** – Un sistema de archivos moderno que incluye características avanzadas como la creación de instantáneas (_snapshots_) y la autorreparación de datos.
- **Swap** – No almacena archivos de usuario, sino que funciona como memoria virtual de apoyo cuando la memoria RAM física se llena por completo.

---

## 🚀 Instalación – Paso a paso

### 1. Configuración inicial del teclado e idioma

```bash
loadkeys la-latin1
```

Establece el mapa de teclado en latinoamericano (puedes usar `es` para español de España).

```bash
nano /etc/locale.gen
```

Busca y descomenta las líneas de tu localidad (ej. `es_VE.UTF-8` o `es_ES.UTF-8`). Luego:

```bash
locale-gen
export LANG=es_VE.UTF-8
```

### 2. Conectar a Internet

```bash
ping -c 3 ping.archlinux.org
```

- Si usas **cable Ethernet**, normalmente ya tienes conexión automática (el ISO de Arch activa DHCP por defecto).
- Si usas **WiFi**, conéctate con `iwctl`:

```bash
iwctl
# Dentro de la consola de iwctl:
station list                                # Ver el nombre de tu adaptador (ej. wlan0)
station wlan0 scan
station wlan0 get-networks
station wlan0 connect "Nombre_De_Tu_Red"
exit
```

### 3. Borrar firmas y tablas de particiones del disco (opcional, pero recomendado)

```bash
wipefs -a /dev/sda        # Elimina firmas de sistemas de archivos
sgdisk --zap-all /dev/sda # Borra cualquier tabla de particiones
```

### 4. (Opcional) Sobrescribir o descartar el disco

Elige **una** de las siguientes opciones según tu tipo de disco, no es necesario ejecutar ambas:

```bash
# HDD: sobrescribir con ceros (lento, puede tardar horas en discos grandes)
dd if=/dev/zero of=/dev/sda bs=1M status=progress
```

```bash
# SSD / NVMe: descarta (TRIM) todos los bloques; es rápido y recomendable en vez de dd,
# que en SSD no aporta nada y solo desgasta las celdas de memoria.
# OJO: no es un borrado criptográfico garantizado; si necesitas eliminar datos sensibles de
# verdad, usa el "secure erase" del fabricante (nvme format / hdparm --security-erase).
blkdiscard /dev/sda
```

### 5. Crear particiones con `cfdisk`

```bash
cfdisk /dev/sda
```

Dentro de `cfdisk`, selecciona la tabla de particiones **`gpt`** (recomendada tanto para BIOS como para UEFI: no tiene el límite de 2 TiB ni el de 4 particiones primarias de una tabla MBR/DOS).

> **📌 Alternativa para BIOS**: si prefieres simplicidad y tu disco es menor a 2 TiB, puedes usar una tabla `dos` (MBR) solo para el modo BIOS; en ese caso NO necesitas la partición "BIOS boot" que se explica abajo. Esta guía usa GPT de forma unificada para ambos modos.

**Esquema de particiones — Opción A: UEFI**

|Partición|Tamaño|Tipo|Formato|Punto de montaje|
|---|---|---|---|---|
|`/dev/sda1`|512 MiB – 1 GiB|`EFI System`|FAT32|`/boot/efi`|
|`/dev/sda2`|4–8 GiB (según tu RAM)|`Linux swap`|swap|—|
|`/dev/sda3`|Resto del disco|`Linux filesystem`|ext4|`/` (raíz)|
|`/dev/sda4` (opcional)|Según necesidades|`Linux filesystem`|ext4|`/home`|

**Esquema de particiones — Opción B: BIOS (Legacy)**

|Partición|Tamaño|Tipo|Formato|Punto de montaje|
|---|---|---|---|---|
|`/dev/sda1`|2 MiB|`BIOS boot`|**Sin formato**|(no se monta)|
|`/dev/sda2`|4–8 GiB (según tu RAM)|`Linux swap`|swap|—|
|`/dev/sda3`|Resto del disco|`Linux filesystem`|ext4|`/` (raíz)|
|`/dev/sda4` (opcional)|Según necesidades|`Linux filesystem`|ext4|`/home`|

> **⚠️ Importante para BIOS + GPT**: la partición `BIOS boot` de 2 MiB es obligatoria en este caso. GRUB la necesita para incrustar su `core.img`, ya que GPT no deja el "hueco" al inicio del disco que sí dejaba una tabla MBR. Sin ella, `grub-install` fallará más adelante con _"this GPT partition label contains no BIOS Boot Partition"_. No la formatees ni la montes, solo créala con ese tipo en `cfdisk`.
> 
> **📌 Nota**: en el modo BIOS ya no hace falta una partición `/boot` separada — el propio directorio `/boot` vive dentro de la partición raíz. Lo mismo ocurre en UEFI: solo `/boot/efi` (la ESP) es una partición aparte; `/boot` en sí es simplemente un directorio dentro de la raíz.

### 6. Formatear las particiones

```bash
# Si usas UEFI, formatea la ESP:
mkfs.fat -F32 /dev/sda1

# Si usas BIOS, NO formatees /dev/sda1: es la partición BIOS boot, va sin sistema de archivos.

# En ambos modos:
mkfs.ext4 /dev/sda3   # Raíz
mkfs.ext4 /dev/sda4   # /home (si creaste esta partición)
mkswap /dev/sda2      # Swap
```

### 7. Montar las particiones

```bash
# Montar la raíz
mount /dev/sda3 /mnt
mkdir -p /mnt/boot

# Solo si usas UEFI: monta la ESP en /boot/efi
mkdir -p /mnt/boot/efi
mount /dev/sda1 /mnt/boot/efi

# Si usas BIOS: no hay nada que montar en /boot, GRUB usará directamente
# la partición BIOS boot (/dev/sda1) más adelante, sin punto de montaje.

# /home (si la creaste)
mkdir -p /mnt/home
mount /dev/sda4 /mnt/home

# Activar swap (hazlo ANTES de generar el fstab en el paso 10, para que quede registrado)
swapon /dev/sda2
```

### 8. Actualizar los mirrors (opcional)

```bash
reflector --verbose --latest 20 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
```

El ISO ya ejecuta `reflector` automáticamente al arrancar y deja una lista de mirrors razonable, así que este paso solo hace falta si las descargas van lentas o fallan. Elige los 20 mirrors HTTPS más rápidos.

### 9. Instalar el sistema base

```bash
# Elige UNO de los dos microcódigos según tu CPU: intel-ucode (Intel) o amd-ucode (AMD)
pacstrap -K /mnt base linux linux-firmware intel-ucode sudo networkmanager grub nano
```

- `base` – paquetes esenciales del sistema.
- `linux` – kernel.
- `linux-firmware` – firmware para dispositivos. Desde junio de 2025 es un _metapaquete_ que arrastra los subpaquetes por fabricante (`linux-firmware-amdgpu`, `-intel`, `-nvidia`, `-realtek`, `-mediatek`…). Déjalo así: es lo más seguro. (Puedes ahorrar espacio instalando solo los de tu hardware, pero si te falta alguno, ese dispositivo —Wi‑Fi, GPU, Bluetooth…— dejará de funcionar.)
- `intel-ucode` / `amd-ucode` – actualizaciones de microcódigo de la CPU. Instalarlas aquí (y no después) hace que el hook `microcode` de mkinitcpio las incluya desde el primer initramfs y que `grub-mkconfig` las detecte.
- `sudo` – para privilegios de administración.
- `networkmanager` – gestión de redes.
- `grub` – gestor de arranque.
- `nano` – editor de texto.

> **📌 Según tu caso**: si usas **UEFI**, añade también `efibootmgr` a la lista; si vas a hacer **dual‑boot**, añade `os-prober`.

### 10. Generar el archivo fstab

```bash
genfstab -U /mnt >> /mnt/etc/fstab
```

Esto crea `/etc/fstab` con los puntos de montaje según UUID. Puedes comprobar su contenido:

```bash
cat /mnt/etc/fstab
```

---

## 🔁 Entrar al sistema recién instalado (chroot)

```bash
arch-chroot /mnt
```

A partir de aquí, todos los comandos se ejecutan **dentro** del nuevo sistema (ya eres `root`, no hace falta `sudo`).

> **📌 Si vas a usar los scripts de esta guía** (`hora-teclado-chroot.sh` y, si aplica, `monitor-benq-r5430.sh`), cópialos **antes** de entrar al chroot, desde el ISO live. Quedan en `/root/` del sistema nuevo:
>
> ```bash
> mkdir -p /tmp/usb && mount /dev/sdb1 /tmp/usb     # comprueba el nombre con lsblk -f
> cp /tmp/usb/hora-teclado-chroot.sh /mnt/root/
> cp /tmp/usb/monitor-benq-r5430.sh /mnt/root/      # solo si lo vas a usar
> arch-chroot /mnt
> ```
>
> Si ya entraste y olvidaste copiarlos, haz `exit`, copia los archivos y vuelve a entrar con `arch-chroot /mnt`: no se pierde nada de lo hecho.

---

## ⚙️ Configuración dentro del chroot

### Activar servicios de red

```bash
systemctl enable NetworkManager.service
```

NetworkManager ya trae su propio manejo de WiFi (usa `wpa_supplicant` por defecto), así que con esto es suficiente para la mayoría de los casos.

**(Opcional) Usar `iwd` como backend de WiFi en vez de `wpa_supplicant`:**

```bash
pacman -S iwd
```

```bash
nano /etc/NetworkManager/conf.d/wifi_backend.conf
```

```ini
[device]
wifi.backend=iwd
```

> **📌 Importante**: **no actives `iwd.service`** manualmente (`systemctl enable iwd` NO se debe hacer en este caso). Con esta configuración, NetworkManager arranca y gestiona `iwd` internamente por su cuenta; si además activas el servicio por separado, ambos competirán por controlar la misma interfaz de red.

### Configurar idioma

```bash
nano /etc/locale.gen
# Descomenta tu localidad (ej. es_VE.UTF-8)
locale-gen
echo LANG=es_VE.UTF-8 > /etc/locale.conf
```

### Configurar zona horaria

```bash
ln -sf /usr/share/zoneinfo/America/Caracas /etc/localtime   # Ejemplo para Venezuela
hwclock --systohc
date   # Verifica que la hora sea correcta
```

> **📌 Hazlo antes del siguiente paso:** sin zona horaria, la sincronización NTP dejaría el reloj en UTC. El script de abajo te avisa si no encuentra `/etc/localtime`.

### Configurar teclado y sincronización de hora

Dentro del chroot no hay systemd ni D‑Bus en ejecución, así que `timedatectl` y `localectl` no pueden comunicarse con sus servicios (`systemd-timedated`, `systemd-localed`) y **no escriben nada**. Para dejarlo listo en el primer arranque hay dos caminos: el script (recomendado) o crear los archivos a mano.

**⚡ Camino rápido: `hora-teclado-chroot.sh` (recomendado)**

El script hace por escrito lo que, con el sistema ya arrancado, harían estos comandos:

|Comando (solo en el sistema arrancado)|Lo que hace el script en el chroot|
|---|---|
|`timedatectl set-ntp true`|Habilita `systemd-timesyncd.service`.|
|`localectl set-x11-keymap latam`|Escribe `/etc/X11/xorg.conf.d/00-keyboard.conf` (`XkbLayout "latam"` y `XkbModel "pc105"`), que es lo que leen **Xorg, SDDM y LightDM** en la pantalla de login.|
|`localectl set-keymap la-latin1`|Pone `KEYMAP=la-latin1` y `XKBLAYOUT=latam` en `/etc/vconsole.conf` (consola `tty` y **GDM**) y conserva otras líneas que ya hubiera, como `FONT=`.|
|`mkinitcpio -P`|Regenera el initramfs para que el teclado correcto esté disponible desde el arranque temprano (útil si escribes una contraseña de LUKS).|

Además:

- Es **idempotente**: puedes ejecutarlo varias veces sin duplicar nada.
- Deja una copia `.bak-teclado` de `/etc/vconsole.conf` y de `00-keyboard.conf` la primera vez que los modifica (solo si ya existían).
- Al terminar **relee los archivos** y comprueba que `systemd-timesyncd` quedó habilitado; si algo no coincide, aborta con un error.
- Avisa (sin abortar) si falta la zona horaria, el paquete `kbd`, el layout X11 (llega con `xkeyboard-config`, que instalan `xorg-server` y el gestor de login) o si tu `HOOKS` de mkinitcpio no incluye `keymap` ni `sd-vconsole` (en ese caso el arranque temprano usaría teclado US).
- **No instala ni habilita** ningún escritorio ni gestor de login: puedes ejecutarlo antes o después de instalarlos. Los gestores de login leen la configuración cuando arrancan.

**Qué automatiza y qué sigue siendo manual:**

|Paso|¿Lo hace el script?|
|---|---|
|Idioma (`locale.gen`, `locale-gen`, `locale.conf`)|No, es manual (ver arriba).|
|Zona horaria y `hwclock --systohc`|No, es manual (ver arriba).|
|`loadkeys la-latin1` y `export LANG=...` del principio|No: solo valen para la sesión del ISO live.|
|Sincronización de hora (NTP)|Sí.|
|Teclado de consola y X11|Sí.|
|`mkinitcpio -P` tras cambiar el teclado|Sí.|

**Cómo ejecutarlo** (ya dentro del chroot, con idioma y zona horaria configurados; ahí eres root, no hace falta `sudo`):

```bash
bash /root/hora-teclado-chroot.sh
```

Si no lo copiaste antes de entrar, mira el recuadro de la sección del chroot. Si lo lanzas desde el ISO live, el script se niega y te explica cómo hacerlo bien. Verás `[OK]` por cada paso y, al final, `Listo`.

**Opciones del script:**

|Opción|Para qué sirve|
|---|---|
|`--check`|Solo comprueba el resultado, con el sistema ya reiniciado (ver la sección posterior al arranque).|
|`--layout NOMBRE`|Layout X11 distinto de `latam` (ej. `es`).|
|`--keymap NOMBRE`|Mapa de consola distinto de `la-latin1` (ej. `es`). Lista: `localectl list-keymaps`.|
|`--model NOMBRE`|Modelo X11 distinto de `pc105`; con `""` no se escribe `XkbModel`.|
|`--no-initramfs`|No ejecuta `mkinitcpio -P` (útil si lo vas a regenerar después, por ejemplo con el script del monitor).|

Ejemplo para un teclado español de España: `bash /root/hora-teclado-chroot.sh --layout es --keymap es`.

**🛠️ Alternativa manual (sin script)**

Hace lo mismo escribiendo los archivos tú mismo. Habilita la sincronización de hora (`systemctl enable` sí funciona en el chroot, porque solo crea el enlace del servicio):

```bash
systemctl enable systemd-timesyncd.service
```

Consola (`tty`) y layout para **GDM**:

```bash
cat > /etc/vconsole.conf <<'EOF'
KEYMAP=la-latin1
XKBLAYOUT=latam
EOF
```

X11, que es lo que leen **SDDM** y **LightDM** al mostrar la pantalla de login:

```bash
install -d /etc/X11/xorg.conf.d

cat > /etc/X11/xorg.conf.d/00-keyboard.conf <<'EOF'
Section "InputClass"
        Identifier "system-keyboard"
        MatchIsKeyboard "on"
        Option "XkbLayout" "latam"
        Option "XkbModel" "pc105"
EndSection
EOF
```

> **📌 Por qué hacen falta los dos archivos:** `KEYMAP=la-latin1` configura la consola (`tty`) y `XKBLAYOUT=latam` en `/etc/vconsole.conf` es lo que lee **GDM** en Wayland. Por su parte, `XkbLayout "latam"` en `00-keyboard.conf` configura Xorg, que es sobre lo que corren por defecto **SDDM** y **LightDM**. Dentro del escritorio (Plasma o GNOME en Wayland), cada entorno usa además su propia configuración de teclado. **Hyprland no lee ninguno de los dos archivos**: usa `~/.config/hypr/hyprland/input.lua`, con overrides en `~/.config/hypr/user.lua` (ver **D4**).

Regenera el initramfs para que el hook `sd-vconsole` incluya el mapa correcto desde el arranque temprano:

```bash
mkinitcpio -P
```

> **📌 Con la alternativa manual** el `cat >` sobrescribe `/etc/vconsole.conf` entero. Si ya tenías ahí otras líneas (como `FONT=`), añádelas de nuevo; el script, en cambio, las conserva.

**↩️ Para deshacer lo del script:**

```bash
systemctl disable systemd-timesyncd.service
mv /etc/vconsole.conf.bak-teclado /etc/vconsole.conf                          # si existe la copia; si no, borra /etc/vconsole.conf
mv /etc/X11/xorg.conf.d/00-keyboard.conf.bak-teclado /etc/X11/xorg.conf.d/00-keyboard.conf   # si existe la copia; si no, borra 00-keyboard.conf
mkinitcpio -P
```

**Archivos que toca el script:**

- `/etc/systemd/system/sysinit.target.wants/systemd-timesyncd.service` — enlace que crea `systemctl enable`.
- `/etc/X11/xorg.conf.d/00-keyboard.conf` — layout X11 (copia previa en `.bak-teclado` si ya existía).
- `/etc/vconsole.conf` — `KEYMAP` y `XKBLAYOUT` (copia previa en `.bak-teclado` si ya existía).
- `/boot/initramfs-*.img` — regenerados con `mkinitcpio -P`.

### Mejorar los mirrors (opcional)

```bash
pacman -S reflector
reflector --verbose --latest 20 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
```

### Editar `/etc/pacman.conf` (opcional)

Puedes habilitar repositorios como `multilib` descomentando las líneas correspondientes.

### Nombre del equipo (hostname)

```bash
echo "mi-pc" > /etc/hostname   # Reemplaza "mi-pc" con el nombre deseado
```

### Configurar `/etc/hosts`

Edita `/etc/hosts` con `nano /etc/hosts` y añade estas líneas (cambia `mi-pc` si elegiste otro hostname):

```text
127.0.0.1   localhost
::1         localhost
127.0.1.1   mi-pc.localdomain mi-pc
```

---

## 👤 Crear usuario y contraseñas

### Contraseña de root

```bash
passwd   # Asigna la contraseña para el usuario root
```

> **📌 No te la saltes**: aunque técnicamente el sistema arrancará sin ella, dejar la cuenta root sin contraseña te puede dejar sin forma de recuperar el sistema si algo sale mal con `sudo` o con la configuración del usuario normal.

### Crear usuario normal (OBLIGATORIO)

```bash
useradd -c "Tu Nombre Completo" -m -G wheel -s /bin/bash nombre_usuario
```

- `-c` – comentario con el nombre completo.
- `-m` – crea el directorio `/home/nombre_usuario`.
- `-G` – grupos adicionales. `wheel` es el que permite usar `sudo`. Los grupos `audio`, `video`, `storage` y `power` que antes se añadían aquí son herencia de la época previa a systemd: en un escritorio normal `systemd-logind`, udev y polkit ya dan acceso a audio, vídeo, montaje de discos y apagado a quien tiene sesión local. Añádelos solo si algún programa concreto lo pide.
- `-s` – shell de inicio.

### Asignar contraseña al usuario

```bash
passwd nombre_usuario
```

### Permitir uso de `sudo` (descomentar wheel)

```bash
EDITOR=nano visudo
```

Busca la línea `# %wheel ALL=(ALL:ALL) ALL` y descoméntala (elimina el `#`). Para ver los asteriscos al escribir la contraseña en sudo, añade al final del archivo:

```text
Defaults pwfeedback
```

---

## 🖥️ Instalación y configuración de GRUB

### Si usas **BIOS (Legacy)**

```bash
grub-install --target=i386-pc /dev/sda
```

Esto usará automáticamente la partición `BIOS boot` (`/dev/sda1`) creada en el Paso 5.

### Si usas **UEFI**

```bash
pacman -S efibootmgr   # solo si no lo tienes instalado
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
```

### Configuración adicional (opcional)

- **Dual‑Boot**: primero instala el detector de otros sistemas operativos, que no viene incluido por defecto:
    
    ```bash
    pacman -S os-prober
    ```
    
    Luego edita `/etc/default/grub` y descomenta `#GRUB_DISABLE_OS_PROBER=false`.
    
- **Resolución de pantalla**: Si usas monitor VGA, añade `GRUB_GFXMODE=1024x768,auto` en `/etc/default/grub`.
    

### Generar el archivo de configuración de GRUB

```bash
grub-mkconfig -o /boot/grub/grub.cfg
```

**Cada vez que modifiques `/etc/default/grub` o agregues otro sistema, debes ejecutar este comando.**

---

## 🚪 Salir del chroot y reiniciar

```bash
exit
umount -R /mnt
swapoff -a
reboot
```

---

## 🖥️ Post‑instalación (dentro del sistema ya arrancado)

### Probar conexión a Internet

```bash
ping -c 3 ping.archlinux.org
```

### Actualizar el sistema

Arch es _rolling release_: antes de instalar nada más, ponte al día.

```bash
sudo pacman -Syu
```

### Si pacman da errores de llaves

```bash
# 1. Actualiza primero el llavero y enseguida el resto del sistema
#    (nunca ejecutes `pacman -Sy` y te quedes ahí: es una actualización parcial; con `-Su` a continuación equivale a `-Syu`)
sudo pacman -Sy archlinux-keyring && sudo pacman -Su

# 2. Si siguen apareciendo errores de firma, reinicias el llavero
sudo rm -r /etc/pacman.d/gnupg
sudo pacman-key --init
sudo pacman-key --populate archlinux
```

### Si hay problemas con los mirrors

```bash
sudo pacman -S reflector
sudo reflector --verbose --latest 20 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
```

### Configurar hora y teclado (persistente)

> **📌 Si en el chroot usaste `hora-teclado-chroot.sh` (o creaste los archivos a mano), esto ya está hecho:** aquí solo tienes que comprobar que quedó bien.

**Comprobar** (el script quedó en `/root/` porque lo copiaste a `/mnt/root/` antes de entrar al chroot):

```bash
sudo bash /root/hora-teclado-chroot.sh --check
```

Muestra `[OK]` o `[XX]` por cada punto y termina con un código de salida distinto de cero si algo falla. Consulta a `timedatectl` y `localectl`, es decir, al propio systemd, así que confirma lo que verán los gestores de login. Lo mismo, a mano:

```bash
timedatectl
localectl status
```

Deberías ver:

- En `timedatectl`: `NTP service: active` y, pasados unos segundos con red, `System clock synchronized: yes`.
- En `localectl status`: `VC Keymap: la-latin1` y `X11 Layout: latam`.

**Si te saltaste el paso del chroot o ya habías arrancado el sistema**, puedes ejecutar el script desde aquí con `sudo bash RUTA/hora-teclado-chroot.sh` (también funciona en el sistema arrancado: además de escribir los archivos, arranca la sincronización de hora al momento). O bien usar los comandos:

```bash
sudo timedatectl set-ntp true
sudo localectl set-keymap la-latin1
sudo localectl set-x11-keymap latam
```

> **📌 `localectl` solo funciona con el sistema ya arrancado**, porque necesita comunicarse con `systemd-localed` a través de D‑Bus. En el chroot falla y no escribe nada; por eso allí se usa el script (o se crean los archivos a mano). Usa estos comandos si olvidaste el paso del chroot o si ya habías arrancado el sistema. Si los ejecutas ahora y quieres que el `tty` temprano también quede bien, termina con `sudo mkinitcpio -P`.

---

## 🧠 Microcódigo (CPU)

Si ya incluiste `intel-ucode` o `amd-ucode` en el `pacstrap` (Paso 9) no tienes que hacer nada más. Si te lo saltaste, instálalo ahora y regenera tanto el initramfs como la configuración de GRUB (sin lo segundo GRUB no carga el microcódigo):

```bash
sudo pacman -S intel-ucode   # para Intel
sudo pacman -S amd-ucode     # para AMD

sudo mkinitcpio -P
sudo grub-mkconfig -o /boot/grub/grub.cfg
```

> **📌 Servidor gráfico**: antes aquí se instalaban `xorg-server` y `xorg-xinit` manualmente. Para Plasma y GNOME en Wayland ya no hace falta instalarlos por separado; si usas **SDDM** o **LightDM**, `pacman` instalará `xorg-server` automáticamente como dependencia del propio gestor de inicio de sesión.

---

## 🎮 Controladores de GPU

> **📌 Qué cambió respecto a versiones anteriores de esta guía**:
> 
> - Los controladores de Xorg (`xf86-video-amdgpu`, `xf86-video-ati`, `xf86-video-intel`, `xf86-video-nouveau`) ya no se instalan: Plasma y GNOME usan sesión Wayland, y en el resto de casos basta el driver *modesetting* integrado en el kernel + Mesa.
> - `libva-mesa-driver` dejó de ser un paquete aparte: ahora lo incluye `mesa` (junto con la aceleración de vídeo VA‑API). Para la aceleración de vídeo en Firefox basta VA‑API; no necesitas `mesa-vdpau`.
> - NVIDIA: desde el driver 590 (diciembre de 2025) los paquetes oficiales son solo de módulos abiertos: `nvidia-open` reemplazó a `nvidia` y `nvidia-open-dkms` a `nvidia-dkms`. Las GPU Maxwell, Pascal y Volta quedaron fuera de los repos oficiales.

### AMD / ATI (open‑source)

```bash
sudo pacman -S --needed mesa vulkan-radeon
```

El firmware (`linux-firmware-amdgpu`) ya viene incluido con `linux-firmware`.

### NVIDIA

- **GPU Turing o más nuevas (GTX 16xx, RTX 20xx en adelante) — módulos abiertos, recomendado**:
    
    ```bash
    sudo pacman -S --needed nvidia-open
    ```
    
    `nvidia-open` ya viene compilado para el kernel `linux` y arrastra `nvidia-utils`, así que **no necesitas `dkms` ni `linux-headers`**. Si usas otro kernel: `nvidia-open-lts` para `linux-lts`, o `nvidia-open-dkms` (más los headers de ese kernel) para cualquier otro. Opcional, para aceleración de vídeo por hardware en el navegador: `libva-nvidia-driver`.
    
- **Maxwell / Pascal / Volta (GTX 750 y 9xx/10xx, Titan V)**: el driver oficial 590 ya no las soporta. Puedes usar Nouveau (siguiente punto) o el driver heredado `nvidia-580xx-dkms` (junto con `nvidia-580xx-utils`) desde el **AUR**: necesita `base-devel`, `git` y `linux-headers`, y se compila con `makepkg -si` o con un ayudante del AUR. Revisa siempre el `PKGBUILD` antes de compilar (el AUR sufrió una oleada de paquetes maliciosos en junio de 2026).
    
- **Nouveau (open‑source)**:
    
    ```bash
    sudo pacman -S --needed mesa vulkan-nouveau
    ```
    

> No mezcles drivers: si instalas `nvidia-open`, no dejes Nouveau como driver activo, y viceversa.

### Intel (open‑source)

```bash
sudo pacman -S --needed mesa vulkan-intel intel-media-driver
```

`intel-media-driver` (VA‑API) es para GPU Intel de la generación Broadwell (≈2014) en adelante; para las anteriores usa `libva-intel-driver`.

### Máquina Virtual (VirtualBox)

```bash
sudo pacman -S --needed virtualbox-guest-utils
sudo systemctl enable --now vboxservice.service
```

El kernel `linux` ya incluye los módulos de invitado (`vboxguest`, `vboxsf`), así que no hace falta DKMS ni `linux-headers`. En los ajustes de la VM usa el controlador gráfico **VMSVGA**. Si no vas a usar entorno gráfico, instala `virtualbox-guest-utils-nox`.

---

## 🖥️ Escritorio mínimo: terminal + Firefox

Plasma (desde la 6.8) y GNOME (desde la 50) **solo ofrecen sesión Wayland**; las aplicaciones X11 antiguas funcionan igualmente a través de XWayland, que se instala solo como dependencia.

Lo de abajo es lo mínimo para tener un escritorio funcional con **terminal + Firefox**: red, sonido, pantalla, ajustes y permisos gráficos. Todo lo demás (visor de imágenes, reproductor, calculadora…) se queda fuera; lo añades cuando lo necesites.

Para el gestor de inicio de sesión, esta guía usa **3 gestores y 4 opciones**: **SDDM** para KDE Plasma (muy personalizable con temas) y para Hyprland con el rice Glyph (Opción D), **GDM** para GNOME, y **LightDM** para cualquier otro escritorio o gestor de ventanas.

### Base común (sonido, fuentes y Firefox)

```bash
sudo pacman -S --needed pipewire-pulse wireplumber noto-fonts firefox
```

- `pipewire-pulse` + `wireplumber` – sonido (PipeWire con compatibilidad PulseAudio). Nombrar `wireplumber` explícitamente evita que pacman te pregunte qué gestor de sesión quieres.
- `noto-fonts` – fuente base. Firefox necesita «alguna» fuente TTF y, si no hay ninguna instalada, pacman te obliga a elegir entre varias.
- `firefox` – el Firefox de toda la vida.

> **📌 Si usas KDE Plasma**, instala también `kde-gtk-config` (ya está incluido en el comando de la Opción A). Sin ese paquete, Firefox en Wayland puede mostrar solo el botón de cerrar, sin minimizar ni maximizar.

Opcionales (instala solo lo que necesites):

```bash
sudo pacman -S --needed noto-fonts-cjk       # japonés / chino / coreano (sin esto salen cuadros vacíos)
sudo pacman -S --needed noto-fonts-emoji     # emojis en color
sudo pacman -S --needed firefox-i18n-es-es   # Firefox en español (también existen es-mx, es-ar y es-cl)
sudo pacman -S --needed sof-firmware         # si en un portátil reciente no suena nada
```

### Opción A: **KDE Plasma** (solo Wayland + **SDDM clásico**)

```bash
sudo pacman -S --needed plasma-desktop sddm sddm-kcm breeze kscreen powerdevil polkit-kde-agent plasma-nm plasma-pa xdg-desktop-portal-kde konsole kde-gtk-config

# Activar el gestor de inicio de sesión
sudo systemctl enable sddm.service
sudo systemctl start sddm.service   # o reinicia con `reboot`
```

- `plasma-desktop` – el escritorio (arrastra `plasma-workspace`, `kwin`, XWayland, etc.).
- `sddm` + `sddm-kcm` – la pantalla de inicio de sesión clásica y su módulo en **Preferencias del sistema** de KDE para instalar y gestionar temas de SDDM. (Se usa SDDM en lugar de `plasma-login-manager` porque SDDM permite personalizar la pantalla con temas QML; si descargas algún tema antiguo hecho en Qt5, instala también `qt5-declarative`).
- `konsole` – el terminal.
- `breeze` (tema), `kscreen` (ajustes de pantallas), `powerdevil` (energía), `polkit-kde-agent` (ventana de contraseña al pedir permisos de administrador), `plasma-nm` (applet de red para NetworkManager), `plasma-pa` (volumen) y `xdg-desktop-portal-kde` (diálogos de archivos y compartir pantalla en Firefox).
- `kde-gtk-config` – integración GTK de KDE. Es lo que hace que Firefox en Wayland muestre los botones de minimizar y maximizar; sin él puede quedarse solo con el de cerrar.

> **📌 ¿Y un gestor de archivos?** No es imprescindible, pero `sudo pacman -S dolphin` te lo da.

### Opción B: **GNOME** (solo Wayland + **GDM**)

```bash
sudo pacman -S --needed gnome-shell gnome-session gnome-settings-daemon gdm gnome-control-center gnome-console xdg-desktop-portal-gnome

# Activar el gestor de inicio de sesión
sudo systemctl enable gdm.service
sudo systemctl start gdm.service   # o reinicia con `reboot`
```

- `gnome-shell`, `gnome-session`, `gnome-settings-daemon` – el escritorio en sí (algunos ya llegan como dependencia; con `--needed` no pasa nada).
- `gdm` – la pantalla de inicio de sesión.
- `gnome-control-center` – Ajustes (red, Wi‑Fi, pantalla, sonido, teclado…).
- `gnome-console` – el terminal.
- `xdg-desktop-portal-gnome` – diálogos de archivos y compartir pantalla para Firefox.

> **📌 ¿Y un gestor de archivos?** No es imprescindible, pero `sudo pacman -S nautilus` te lo da. `gnome-tweaks` ya no forma parte del grupo `gnome` (está en `gnome-extra`); instálalo solo si lo quieres.

### Opción C: **Cualquier otro escritorio o Window Manager** (**LightDM**)

Si vas a instalar otro entorno distinto de KDE Plasma y GNOME (por ejemplo XFCE, Cinnamon, MATE, LXQt, i3, Openbox, etc.), usa **LightDM** junto con un *greeter* (interfaz gráfica de login; sin *greeter* no mostrará pantalla de inicio de sesión):

```bash
sudo pacman -S --needed lightdm lightdm-gtk-greeter

# Opcional: herramienta gráfica para personalizar fondo, tema, iconos y fuente de LightDM
sudo pacman -S --needed lightdm-gtk-greeter-settings

# Activar el gestor de inicio de sesión (cuando ya tengas instalado tu escritorio/WM)
sudo systemctl enable lightdm.service
sudo systemctl start lightdm.service   # o reinicia con `reboot`
```

> **📌 Alternativa estética para LightDM:** Si quieres una pantalla de login más moderna sin configurarla desde cero, puedes instalar `lightdm-slick-greeter` en lugar de `lightdm-gtk-greeter`, y editar `/etc/lightdm/lightdm.conf` en la sección `[Seat:*]` poniendo `greeter-session=lightdm-slick-greeter`.

> **📌 Hyprland no va aquí:** para Hyprland con el rice Glyph (estilo Nothing OS) usa la **Opción D**, que emplea **SDDM** y no LightDM.

### Opción D: **Hyprland + Glyph (estilo Nothing OS)** (**SDDM**)

Un escritorio con el aspecto de Nothing OS sobre Hyprland: barra flotante, launcher, panel de control, deck, widgets y una pantalla de login a juego, todo hecho con **Quickshell**. [**Glyph**](https://github.com/Nebelung-cloud/glyph-rice) es un rice único y autocontenido que trae sus propias configuraciones de Hyprland, Quickshell, kitty, fish, fastfetch, btop, cava, fuentes y el tema de SDDM. En este repositorio se usa la copia adaptada con el instalador para Arch.

- Repo: `https://github.com/RaidenMGR47/Nothing-OS-Arch-Linux-Ricing.git` (tu copia adaptada; upstream: `https://github.com/Nebelung-cloud/glyph-rice`)
- Requisitos: Arch con la **Base común** y los **Controladores de GPU** de esta guía, Internet y **Hyprland 0.56+**; el instalador pone el resto (`quickshell` 0.3.1+, SDDM 0.21+, kitty, fish…).
- Lo que esta guía ya hizo y no se repite: teclado de consola/X11 y hora del chroot, `pacman -Syu`, usuario con `sudo`, `nano`, NetworkManager, PipeWire/WirePlumber, `noto-fonts`, Firefox y los drivers de GPU.

> **📌 El instalador se encarga de los archivos existentes:** mueve cualquier configuración previa en `~/.config` a `~/.dots-backup-<fecha>/` antes de crear sus enlaces. No hace falta limpiar nada a mano; basta con ejecutar el instalador como tu usuario.

#### D1. Dependencias base: `git` y `base-devel`

El `pacstrap` de esta guía no trae `git` ni `base-devel`, y el instalador los necesita para compilar `yay` y los paquetes del AUR:

```bash
sudo pacman -Syu --needed git base-devel
```

No hace falta instalar `yay` a mano: `install.sh` lo compila si no lo encuentra. Si prefieres revisarlo antes (recomendado por el aviso del AUR de la sección de NVIDIA), instálalo tú:

```bash
git clone https://aur.archlinux.org/yay-bin.git ~/yay-bin
cd ~/yay-bin
less PKGBUILD
makepkg -si
cd ~ && rm -rf ~/yay-bin
```

#### D2. Preparar el sistema

Antes de ejecutar el instalador:

1. **Un solo gestor de login.** Glyph usa **SDDM**. Si habías instalado otro gestor, desactívalo:
   ```bash
   sudo systemctl disable gdm lightdm 2>/dev/null || true
   ```
   El instalador habilita `sddm.service` y, si hace falta, te pregunta antes de desactivar otros gestores.
2. **Shell:** Glyph usa **fish** en kitty (`shell fish` en `kitty.conf`), así que no necesitas cambiar tu shell de login. Si quieres fish también fuera de kitty: `chsh -s /usr/bin/fish`.

#### D3. Clonar e instalar Glyph

Clónalo en la ruta que usa el README y ejecútalo **como tu usuario, nunca con `sudo`** (el script llama a `sudo` solo donde hace falta):

```bash
git clone https://github.com/RaidenMGR47/Nothing-OS-Arch-Linux-Ricing.git ~/.local/share/raidenmgr47
cd ~/.local/share/raidenmgr47
chmod +x install.sh uninstall.sh
./install.sh --check    # opcional: detecta teclado/monitores y muestra versiones; no cambia nada
./install.sh
```

> **📌 Si descargaste el ZIP desde GitHub**, la carpeta se llama `Nothing-OS-Arch-Linux-Ricing-main` (y si la descomprimiste dos veces, verás una carpeta anidada con el mismo nombre). El nombre **no importa**: entra en la carpeta que contiene `install.sh` y copia su contenido como `~/.local/share/raidenmgr47`. Con `git clone`, además, obtienes el historial para actualizar con `git pull`.

Sin argumentos te pregunta qué extras quieres: `telegram` (`Super+D`), `spotify` con Spicetify (`Super+M`) y `clash` para el panel VPN (`Super+P`). También puedes elegirlos de antemano:

```bash
./install.sh --with telegram,spotify
./install.sh --with ""          # solo el rice, sin extras
./install.sh --keyboard latam   # forzar el layout (o "latam,us")
./install.sh --monitor DVI-I-1:1366x768@60   # forzar el modo del BenQ
./install.sh --links            # solo enlaces + user.lua, sin paquetes
```

Qué hace, en orden:

1. `sudo pacman -Syu --needed` con su lista de paquetes: Hyprland, `quickshell`, SDDM, PipeWire, NetworkManager, bluez, kitty, fish, fuentes, `grim`/`slurp`, `cliphist`, etc. Es una actualización completa, no parcial.
2. Instala `yay` si falta y los paquetes del AUR: `qtengine`, `darkly-bin`, `bibata-cursor-theme-bin` y `zen-browser-bin` (el navegador por defecto del rice), más los extras si los pediste. **El AUR es opcional**: si un paquete falla, el script sigue con los servicios y los enlaces.
3. Habilita `NetworkManager`, `bluetooth`, `power-profiles-daemon`, `pipewire-pulse.socket`, `wireplumber` y `ydotool`; añade tu usuario al grupo `video` y crea la regla udev de `/dev/uinput` para `ydotool`.
4. Mueve las configuraciones que ya existieran a `~/.dots-backup-<fecha>/` y crea enlaces simbólicos desde `~/.local/share/raidenmgr47/config/...` a `~/.config/...` (Hyprland, Quickshell, kitty, fish, starship, fastfetch, btop, cava, GTK/Qt y fuentes).
5. **Detecta el teclado** (un `user.lua` previo, Hyprland en marcha, `localectl`, `/etc/vconsole.conf`, `00-keyboard.conf`, `setxkbmap`, `/etc/default/keyboard` o el locale, por ese orden) y escribe el bloque gestionado en `~/.config/hypr/user.lua`; si no existe, lo crea desde `user.lua.example`. Salvo `--no-system-keyboard`, sincroniza también la consola y X11 con `localectl`.
6. **Detecta los monitores** en `/sys/class/drm`, imprime cada salida conectada con su modo preferido y avisa si una salida conectada no reporta modos (EDID/DDC). Con `--monitor OUTPUT:MODO[:POSICIÓN[:ESCALA]]` escribe reglas `hl.monitor()` en `user.lua` (se puede repetir para varias pantallas).
7. Copia el tema de login a `/usr/share/sddm/themes/glyph`, lo fija en `/etc/sddm.conf.d/zz-glyph.conf` y habilita `sddm` si no hay otro gestor de login activo.

Al terminar, comprueba el gestor de login y reinicia:

```bash
systemctl is-enabled sddm.service     # debe decir "enabled"
sudo systemctl enable sddm.service    # solo si dijo "disabled"
sudo reboot
```

> **📌 Si el instalador avisa de que `/etc/sddm.conf` fija otro `Current=`**, edítalo y pon `Current=glyph` (o borra esa línea): `/etc/sddm.conf` tiene prioridad sobre `sddm.conf.d`.

#### D4. Primer arranque y teclado latinoamericano

En SDDM elige la sesión **Hyprland** y entra. La terminal del rice es **kitty** con `Super+Q`. El instalador ya detectó el teclado y escribió el resultado en `~/.config/hypr/user.lua`; comprueba que Hyprland lo aplica:

```bash
hyprctl version | head -1                 # necesitas 0.56 o superior
hyprctl devices | grep -A2 -i keyboard    # "layout" debe decir latam
```

Si no es tu layout, no edites los archivos del repo: vuelve a lanzar el instalador con el layout forzado.

```bash
cd ~/.local/share/raidenmgr47
./install.sh --keyboard latam              # o "latam,us" para alternar con Alt+Shift
# si no quieres tocar paquetes ni servicios:
./install.sh --links --keyboard latam
hyprctl reload
```

**Cómo lo hace:** **Hyprland no lee `/etc/vconsole.conf` ni `/etc/X11/xorg.conf.d/00-keyboard.conf`**; usa `~/.config/hypr/hyprland/input.lua` (upstream: `kb_layout = "us,ru"`) y, al final, `~/.config/hypr/user.lua`. El instalador busca el layout en un `user.lua` previo, Hyprland en marcha, `XKB_DEFAULT_LAYOUT`, `localectl`, `00-keyboard.conf`, `/etc/vconsole.conf`, `setxkbmap`, `/etc/default/keyboard` y el locale (en ese orden), y escribe solo el bloque gestionado:

```lua
-- >>> glyph:keyboard
hl.config({
    input = {
        kb_layout = "latam",
        kb_options = "",
    },
})
-- <<< glyph:keyboard
```

Si el archivo no existe, lo crea desde `user.lua.example`. En una reinstalación copia tu `user.lua` anterior desde `~/.dots-backup-*` y reescribe únicamente ese bloque: lo que pongas fuera se conserva. Si lo editas a mano, mantén las marcas `-- >>> glyph:keyboard` / `-- <<< glyph:keyboard` para que el instalador sepa qué reemplazar.

**Consola y X11 (SDDM y TTY):** salvo que uses `--no-system-keyboard`, el instalador también ejecuta `localectl set-keymap la-latin1` y `localectl set-x11-keymap latam`, guardando copias `.glyph-backup-*`. Comprueba:

```bash
localectl status
# VC Keymap: la-latin1
# X11 Layout: latam
```

Si instalaste con `--links` o `--no-system-keyboard`, ejecuta `./install.sh` (sin `--links`) o los dos `localectl` a mano. Si vienes del chroot, estos valores ya estaban puestos y el instalador solo los reafirma. `sudo mkinitcpio -P` solo hace falta si usas LUKS y quieres el teclado correcto al desbloquear.

> **📌 El login de SDDM:** Glyph no activa el greeter Wayland de SDDM. Si tu SDDM usa el greeter X11 (lo habitual), el login lee `00-keyboard.conf` (layout `latam`); si usa Wayland, el teclado lo pone el compositor del greeter. Si aun así sale en inglés, revisa `localectl status` y que `/etc/vconsole.conf` tenga `KEYMAP=la-latin1`.

#### D5. Atajos cómodos para teclado latinoamericano

Las letras, números, flechas y teclas de función están en la misma posición física que en un teclado US, así que los atajos de Glyph funcionan tal cual. Los únicos incómodos son los que usan **barra invertida** (`\`), que en `latam` suele requerir `AltGr`. Deja las alternativas en `~/.config/hypr/user.lua`:

|Acción|Atajo original|Alternativa en latam|
|---|---|---|
|Centrar ventana|`Ctrl+Super+\`|**`Super+Alt+C`**|
|Redimensionar al 55 % × 70 % y centrar|`Ctrl+Super+Alt+\`|**`Super+Alt+X`**|
|Ventana flotante tipo PIP|`Super+Alt+\`|**`Super+Alt+P`**|

Una instalación nueva incluye estas alternativas porque el instalador crea `user.lua` desde `user.lua.example`. Si vienes de una configuración anterior que no las tiene, añádelas así:

```lua
local fn = require("hyprland.functions")

hl.bind("SUPER + ALT + C", hl.dsp.window.center())
hl.bind("SUPER + ALT + X", hl.dsp.window.resize(fn.resize_by_screen(55, 70)))
hl.bind("SUPER + ALT + X", hl.dsp.window.center())   -- el original también centra

hl.bind("SUPER + ALT + P", function()
    local a = hl.get_active_window()
    if not a then return end
    local pip = fn.move_actions(a) or {}
    if not a.floating then table.insert(pip, 1, hl.dsp.window.float()) end
    table.insert(pip, hl.dsp.window.pin({ action = "on", window = "address:" .. a.address }))
    for _, action in ipairs(pip) do hl.dispatch(action) end
end)
```

Atajos de referencia del rice:

|Acción|Atajo|
|---|---|
|Launcher|tocar `Super` (sin combinación)|
|Terminal|`Super+Q`|
|Navegador|`Super+W`|
|Archivos|`Super+E`|
|Quick settings|`Super+A`|
|Ajustes del rice|`Super+I`|
|Deck (dashboard)|`Super+Space`|
|Portapapeles|`Super+V`|
|Emojis/símbolos|`Super+.`|
|Wallpapers|`Super+Shift+W`|
|Captura|`Print` o `Super+Shift+S`|
|Bloquear|`Super+L`|
|Apagar/menú de energía|`Super+Esc`|
|Workspaces 1–0|`Super+1` … `Super+0`|
|Mover ventana a workspace|`Super+Alt+1` … `Super+Alt+0`|
|Cerrar ventana|`Super+C`|
|Pantalla completa|`Super+F`|
|Flotante|`Super+Alt+Space`|
|Mover/redimensionar con ratón|`Super+Z` / `Super+X`|

> **📌 Sobre los atajos con `=`:** además de los de barra invertida, el rice usa `Super+=`, `Super+Shift+=` y `Ctrl+Super+=` para redimensionar. En `latam` la `=` puede estar bajo Shift+0 y no disparar. `hyprctl binds | grep Equal` solo confirma que el bind existe, no que la tecla llegue: pruébalos pulsándolos o usa `wev` para ver el keysym; si fallan, añade alternativas en `user.lua`.

> **📌 Todos los overrides van en `~/.config/hypr/user.lua`**, no en los archivos del repo: así `git pull` actualiza el rice sin pisar tus cambios.

#### D6. Ajustes posteriores (monitor, fondos, clima y apps)

- **Monitor:** el instalador imprime las salidas conectadas y su modo preferido; antes de arrancar puedes verlo con `./install.sh --check`. Si la resolución o la posición no son correctas (o una salida conectada no reporta modos porque un adaptador DVI→VGA pierde el EDID), fíjala con el instalador:
  ```bash
  ./install.sh --monitor DVI-I-1:1366x768@60
  # opcional: OUTPUT:MODO:XxY:ESCALA, p. ej.
  ./install.sh --monitor DVI-I-1:1366x768@60:0x0:1
  ```
  En el equipo de la nota del BenQ el conector es `DVI-I-1` y la resolución 1366x768. El instalador escribe el bloque `-- >>> glyph:monitor` en `user.lua` y avisa si no hay EDID; `./install.sh --links --monitor ...` basta si solo quieres actualizar `user.lua`. También puedes añadir la regla a mano:
  ```lua
  hl.monitor({ output = "DVI-I-1", mode = "1366x768@60", position = "0x0", scale = 1 })
  ```
- **Fondos:** el selector (`Super+Shift+W`) lee `~/Pictures/Wallpapers`; los GIF del widget del gato, `~/Pictures/Gifs`. Crea ambas si no existen.
- **Clima:** se obtiene por IP; si quieres fijar la ubicación, añade a `user.lua`:
  ```lua
  hl.env("DEMONSHOT_LATLON", "19.43,-99.13")   -- Ciudad de México; pon tus coordenadas
  ```
- **Apps:** los programas de los workspaces especiales se cambian en `user.lua`:
  ```lua
  local apps = require("variables").apps
  apps.editor = "codium"           -- Super+Shift+K
  apps.todo   = "planify"          -- Super+R
  apps.music  = "spotify-launcher" -- Super+M
  ```
- **Tema de SDDM:** comprueba que no haya otro `Current=` ganando:
  ```bash
  grep -rn 'Current=' /etc/sddm.conf /etc/sddm.conf.d/ 2>/dev/null
  ```
  Debe decir `Current=glyph`. Puedes previsualizarlo desde Hyprland con `sddm-greeter-qt6 --test-mode --theme /usr/share/sddm/themes/glyph`.

#### D7. Si algo no funciona

- **Diagnóstico sin cambios:** `./install.sh --check` imprime el teclado detectado y su origen, las salidas de vídeo y las versiones instaladas. No instala ni escribe nada.
- **`quickshell` se cae o da errores QML:** comprueba `pacman -Q quickshell` (debe ser 0.3.1 o superior) y que no tengas `quickshell-git` instalado a la vez. Actualiza con `sudo pacman -Syu`.
- **Un paquete del AUR falla:** instálalo a mano con `yay -S --needed qtengine darkly-bin bibata-cursor-theme-bin zen-browser-bin` y vuelve a ejecutar `./install.sh --links` (solo enlaces, sin paquetes).
- **El tema de login no es Glyph:** revisa que no haya otro `Current=` en `/etc/sddm.conf` compitiendo con `/etc/sddm.conf.d/zz-glyph.conf` (debe decir `Current=glyph`). El instalador avisa si encuentra ese conflicto.
- **El teclado sigue en US dentro de Hyprland:** confirma que `~/.config/hypr/user.lua` existe, que `hyprctl reload` no da errores y que `hyprctl devices` muestra `latam`. Vuelve a ejecutar `./install.sh --keyboard latam` (o `./install.sh --links --keyboard latam`, que no toca paquetes). Como último recurso, edita el bloque `-- >>> glyph:keyboard` de `user.lua`, o `~/.config/hypr/hyprland/input.lua` cambiando `kb_layout = "us,ru"` por `kb_layout = "latam"` (pero entonces un `git pull` puede pedirte resolver el conflicto).
- **El login sale en inglés:** `localectl status`, `/etc/vconsole.conf` con `KEYMAP=la-latin1` y `00-keyboard.conf` con `XkbLayout "latam"`. Si tu SDDM usa Wayland, el teclado del greeter se configura en el compositor; Glyph no lo activa por defecto.
- **Resolución rara en el BenQ:** comprueba `./install.sh --check`; si el conector no reporta modos, fíjalo con `./install.sh --monitor DVI-I-1:1366x768@60` como en D6; el resto de la nota del monitor sigue aplicando (EDID, `amdgpu`, GRUB).
- **Actualizas el repo:** `cd ~/.local/share/raidenmgr47 && git pull`. Los archivos de `config/` son enlaces simbólicos, así que los cambios se aplican solos; tus overrides en `user.lua` no se tocan (solo se reescriben los bloques `-- >>> glyph:...`). Si el upstream añadió archivos, vuelve a ejecutar `./install.sh --links`. Después, `hyprctl reload`.

#### D8. Cómo deshacer Glyph

Glyph incluye `uninstall.sh`, que revierte la instalación de forma segura. Ejecútalo **como tu usuario, nunca con `sudo`**:

```bash
cd ~/.local/share/raidenmgr47
./uninstall.sh --dry-run    # previsualiza los cambios sin tocar nada
./uninstall.sh              # quita los enlaces y restaura la copia más reciente
```

Qué hace, en orden:

1. Quita solo los enlaces simbólicos que apuntan dentro de `~/.local/share/raidenmgr47`; deja cualquier archivo que no sea suyo.
2. Restaura las configuraciones antiguas desde el `~/.dots-backup-<fecha>/` más reciente (Hyprland, Quickshell, kitty, fish, fuentes, etc.).
3. Restaura `/etc/vconsole.conf` y `/etc/X11/xorg.conf.d/00-keyboard.conf` desde sus copias `.glyph-backup-*`.
4. Borra `/usr/share/sddm/themes/glyph`, `/etc/sddm.conf.d/zz-glyph.conf` y la regla udev `70-glyph-uinput.rules` de `ydotool`.
5. Borra el marcador `~/.local/state/rice/shell`.

Opciones: `--no-restore` (no restaurar configuraciones), `--keep-sddm` (dejar tema y configuración de SDDM), `--packages` (ofrecer quitar solo los paquetes AUR opcionales — `zen-browser-bin` es tu navegador) y `--yes` (no preguntar).

**No deshabilita SDDM, no desinstala Hyprland/Quickshell/SDDM y no borra el repo.** Si además quieres borrar el repo y las fuentes, hazlo a mano al terminar:

```bash
rm -rf ~/.local/share/raidenmgr47 ~/.local/share/fonts/glyph
# Solo paquetes que ya no uses (NO borres sddm si lo usas para otro escritorio):
sudo pacman -Rns qtengine darkly-bin bibata-cursor-theme-bin zen-browser-bin
```

**Archivos que toca la Opción D:**

- `~/.config/` — Hyprland, Quickshell, kitty, fish, starship, fastfetch, btop, cava, GTK/Qt (copias previas en `~/.dots-backup-<fecha>/`).
- `~/.local/bin/rice` — lanzador del shell.
- `~/.local/share/raidenmgr47/` — el repo clonado.
- `~/.local/share/fonts/glyph/` — fuentes del rice.
- `~/.config/demonshot/` y `~/.local/state/rice/` — estado del rice y del selector de fondos.
- `~/.local/share/icons/Rice/` — tema de iconos que crea `rice` al cambiar de shell o de color de carpetas.
- `gsettings` de GNOME: `color-scheme=prefer-dark`, `gtk-theme=adw-gtk3-dark` e `icon-theme=Rice` (`uninstall.sh` no los revierte).
- `~/Pictures/Wallpapers/` — carpeta del selector de fondos (no la vacía).
- `~/Pictures/Gifs/` — GIF del widget del gato (no la vacía).
- `/etc/sddm.conf.d/zz-glyph.conf` y `/usr/share/sddm/themes/glyph` — tema de login.
- `/etc/udev/rules.d/70-glyph-uinput.rules` — regla de `ydotool`.
- **No toca** `/etc/default/grub`, `grub.cfg`, `HOOKS` ni el initramfs: Glyph no instala Plymouth ni cambia el arranque.

---

> 📌 **Consejos finales:**
> 
> - Siempre revisa la [wiki oficial de Arch Linux](https://wiki.archlinux.org/) para detalles específicos de tu hardware.
> - Si usas WiFi, después del reinicio puedes conectarte con `nmtui` (interfaz gráfica en terminal), `nmcli`, o desde el entorno de escritorio.
> - Arch es _rolling release_: antes de actualizar con `sudo pacman -Syu` echa un vistazo a [https://archlinux.org/news/](https://archlinux.org/news/), porque de vez en cuando hay avisos que piden una intervención manual.
> - Nunca instales paquetes con `pacman -Sy paquete`: actualiza siempre el sistema completo (`-Syu`).
> - Recuerda que esta guía es un punto de partida; adapta las particiones y paquetes a tus necesidades.

¡Disfruta tu sistema Arch Linux! 🐧

---

## 🧩 Nota extra: configuración de vídeo para este equipo (BenQ G925HDA + R5 430)

> **📌 Cuándo aplicarla:** con GRUB ya instalado y **antes de instalar ningún entorno gráfico**. Sirve dentro del `chroot` (antes de salir) y también desde el sistema ya arrancado en el **tty**. Todo lo de esta nota se puede hacer sin interfaz gráfica.

Esta nota reproduce la configuración que quedó funcionando en **este equipo concreto**. No es una receta universal:

- Monitor **BenQ G925HDA** analógico, 1366x768@59.79, EDID `BNQ7843`.
- GPU **AMD Radeon R5 430 OEM** (Oland/SI).
- Monitor conectado al conector **`DVI-I-1`** mediante un adaptador **DVI-I → VGA sin DDC**.
- Arranque **BIOS/legacy**.

El adaptador no pasa la línea DDC, así que el kernel no puede leer el EDID del monitor. GRUB tampoco puede usar 1366x768 porque el VBIOS de la R5 430 no lo expone por VBE. La solución es inyectar el EDID al kernel, cargar el driver DRM temprano y forzar el conector.

Resultado final: GRUB sigue a 1024x768, pero el kernel, el `tty`, el gestor de login y el escritorio usan 1366x768. Solo queda un parpadeo breve al cambiar de 1024 a 1366; es normal.

**Resumen:** crear el EDID → añadir `amdgpu` y el EDID al initramfs → ajustar GRUB → regenerar initramfs y `grub.cfg` → reiniciar y comprobar.

> **📌 Nota técnica sobre `radeon` vs `amdgpu` en la R5 430 (Oland / Southern Islands):**
> Las GPU *Southern Islands* (GCN 1.0, como Oland) usan por defecto el módulo del kernel **`radeon`**, no `amdgpu`, salvo que se fuerce con los parámetros `radeon.si_support=0 amdgpu.si_support=1` en GRUB. Como `drm.edid_firmware`, `video=...` y `fbcon=nodefer` pertenecen al subsistema DRM general, la solución de 1366x768 funciona igual con cualquiera de los dos; pero si quieres usar **Vulkan (`vulkan-radeon`)** necesitas que esté activo **`amdgpu`**.
>
> Puedes comprobar cuál está usando realmente tu sistema con `lspci -k | grep -A3 -E 'VGA|Display'` (mira la línea `Kernel driver in use:`). Si dice `radeon` y quieres pasar a `amdgpu`, prueba añadir `radeon.si_support=0 amdgpu.si_support=1` en `GRUB_CMDLINE_LINUX_DEFAULT` y regenera `grub.cfg`.

### ⚡ Camino rápido: script desde un pendrive (recomendado)

`monitor-benq-r5430.sh` hace todos los pasos de esta nota. Es pensado para el tty: no hay que teclear el EDID (200 caracteres de base64) ni editar archivos a mano. Además:

- Verifica el tamaño (128 bytes) y el hash del EDID antes de instalarlo.
- Es **idempotente**: puedes ejecutarlo varias veces sin duplicar parámetros.
- Conserva los parámetros de kernel que ya tuvieras en GRUB y deja una copia en `/etc/default/grub.bak-monitor`.
- No toca `GRUB_CMDLINE_LINUX`, y se niega a continuar si `/boot` figura en `/etc/fstab` pero no está montado (así no escribe el initramfs ni `grub.cfg` en el sitio equivocado).
- Comprueba que `amdgpu` y el EDID **entraron de verdad** en el initramfs y en `grub.cfg`; si no, aborta con un error.

**Desde el sistema instalado (tty):**

```bash
lsblk -f                                  # localiza el pendrive (ej. /dev/sdb1)
sudo mkdir -p /mnt/usb
sudo mount /dev/sdb1 /mnt/usb
sudo bash /mnt/usb/monitor-benq-r5430.sh
sudo umount /mnt/usb
sudo reboot
```

> **📌 Pendrive y teclado:** FAT32, exFAT y ext4 se montan tal cual (para NTFS usa `mount -t ntfs3`). Se ejecuta con `bash RUTA`, así que no importa que el pendrive esté montado sin permiso de ejecución. Si `/` o `-` no salen donde esperas, ejecuta antes `loadkeys la-latin1`.

**Durante la instalación (ISO live, sistema montado en `/mnt`):** copia el script **antes** del primer `arch-chroot /mnt` y, cuando GRUB ya esté instalado, ejecútalo dentro (ahí ya eres root, no hace falta `sudo`):

```bash
mkdir -p /tmp/usb && mount /dev/sdb1 /tmp/usb     # comprueba el nombre con lsblk -f
cp /tmp/usb/monitor-benq-r5430.sh /mnt/root/
arch-chroot /mnt

# ...instala GRUB (sección de GRUB) y después, dentro del chroot:
bash /root/monitor-benq-r5430.sh
```

**Opciones del script:**

|Opción|Para qué sirve|
|---|---|
|`--check`|Solo comprueba el resultado, con el sistema ya reiniciado (ver más abajo).|
|`--edid-only`|Solo crea y verifica `/usr/lib/firmware/edid/benq-g925hda.bin`.|
|`--connector NOMBRE`|Usa otro conector distinto de `DVI-I-1`.|
|`--force`|Sigue aunque el conector no exista en este equipo.|

Si el conector `DVI-I-1` no existe (cambiaste de GPU, de salida o de adaptador), el script se detiene y te muestra los conectores que sí ve.

### 🔍 Diagnóstico desde el tty

Para ver cómo está el vídeo antes (o después) de aplicar nada:

```bash
ls /sys/class/drm/                          # conectores, p. ej. card0-DVI-I-1
grep -H . /sys/class/drm/card*-*/status     # connected / disconnected de cada uno
wc -c < /sys/class/drm/card*-DVI-I-1/edid   # bytes de EDID que leyó el kernel (0 = no pudo leerlo)
cat /sys/class/graphics/fb0/virtual_size    # resolución real de la consola, p. ej. 1024,768
stty size                                   # filas y columnas de la consola
lspci -k | grep -A3 -E 'VGA|Display'        # driver activo en el kernel (radeon o amdgpu)
sudo journalctl -k -b | grep -i edid        # qué dijo el kernel sobre el EDID
```

Conector `connected`, EDID de 0 bytes y consola a 1024x768 es justo lo esperable cuando el adaptador no pasa DDC, que es lo que arregla esta nota.

### 🛠️ Camino manual (sin portapapeles)

Solo si no quieres usar el script. Son comandos cortos y no hace falta abrir `nano`. Si estás en el chroot, quita los `sudo`.

**1. Crear el EDID.** Usa el propio script en modo reducido, que lo genera y lo verifica:

```bash
sudo bash /mnt/usb/monitor-benq-r5430.sh --edid-only
wc -c /usr/lib/firmware/edid/benq-g925hda.bin
sha256sum /usr/lib/firmware/edid/benq-g925hda.bin
```

Debe dar **128 bytes** y este hash:

```text
857d5dcd1913f1f7d936b70783cb7e23795a6a64baeba096d8d395bf6be05c4a
```

> **📌 Si ya tienes una copia del EDID** de la instalación que funcionó, puedes copiarla directamente a `/usr/lib/firmware/edid/benq-g925hda.bin` y comprobar el hash.

**2. Incluir `amdgpu` y el EDID en el initramfs.** En vez de editar `/etc/mkinitcpio.conf`, se usa un _drop-in_ en `/etc/mkinitcpio.conf.d/`, que mkinitcpio lee después del archivo principal. Con `+=` se **añade** a lo que ya hubiera en `MODULES` y `FILES`, sin pisarlo:

```bash
sudo mkdir -p /etc/mkinitcpio.conf.d
sudo tee /etc/mkinitcpio.conf.d/10-monitor-benq.conf >/dev/null <<'EOF'
MODULES+=(amdgpu)
FILES+=(/usr/lib/firmware/edid/benq-g925hda.bin)
EOF

sudo mkinitcpio -P
lsinitcpio /boot/initramfs-linux.img | grep -E 'amdgpu\.ko|benq-g925hda\.bin'
```

Deben aparecer `amdgpu.ko.zst` y `benq-g925hda.bin`.

- `MODULES+=(amdgpu)` hace que el driver se cargue desde el initramfs, antes de montar la raíz (si tras comprobar con `lspci -k` ves que tu sistema usa `radeon` sin forzar `si_support`, puedes usar `radeon` aquí o forzar `amdgpu` en el paso de GRUB).
- `FILES+=(...)` mete el EDID dentro del initramfs para que el kernel lo tenga disponible al arrancar.
- **No cambies `HOOKS`**: el hook `kms` por defecto ya se encarga de KMS; `MODULES` solo adelanta el driver.
- Los drop-ins no se leen si llamas a `mkinitcpio` con `-c`, ni si un preset **antiguo** de `/etc/mkinitcpio.d/` tiene una línea `ALL_config=` sin comentar. En una instalación nueva no pasa. Si pasara, comenta esa línea. Si lo prefieres, puedes poner las dos líneas directamente en `/etc/mkinitcpio.conf`.

**3. Configurar GRUB con `sed`.** Haz primero una copia. **El primer `sed` solo se ejecuta una vez**: si lo repites, los parámetros se duplican (si pasa, restaura la copia y empieza de nuevo).

```bash
sudo cp /etc/default/grub /etc/default/grub.bak-monitor

sudo sed -i -E 's|^GRUB_CMDLINE_LINUX_DEFAULT="(.*)"|GRUB_CMDLINE_LINUX_DEFAULT="\1 drm.edid_firmware=DVI-I-1:edid/benq-g925hda.bin video=DVI-I-1:1366x768@60e fbcon=nodefer"|' /etc/default/grub

sudo sed -i -E 's|^#?GRUB_GFXMODE=.*|GRUB_GFXMODE=1024x768,auto|; s|^#?GRUB_GFXPAYLOAD_LINUX=.*|GRUB_GFXPAYLOAD_LINUX=keep|; s|^#?GRUB_TERMINAL_OUTPUT=.*|GRUB_TERMINAL_OUTPUT="gfxterm"|' /etc/default/grub

grep -E '^GRUB_(CMDLINE_LINUX_DEFAULT|GFXMODE|GFXPAYLOAD_LINUX|TERMINAL_OUTPUT)=' /etc/default/grub
```

Debes ver algo así (tus parámetros previos, como `loglevel=3 quiet`, se conservan; son opcionales y solo controlan cuánto texto muestra el arranque):

```ini
GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet drm.edid_firmware=DVI-I-1:edid/benq-g925hda.bin video=DVI-I-1:1366x768@60e fbcon=nodefer"
GRUB_GFXMODE=1024x768,auto
GRUB_GFXPAYLOAD_LINUX=keep
GRUB_TERMINAL_OUTPUT="gfxterm"
```

> **⚠️ `nomodeset`:** si tu línea de GRUB lo trae, desactiva KMS y anula todo esto. Quítalo.

Qué hace cada cosa:

- `drm.edid_firmware=DVI-I-1:edid/benq-g925hda.bin`: le dice al kernel que use ese EDID para el conector `DVI-I-1`, en vez de intentar leerlo por DDC.
- `video=DVI-I-1:1366x768@60e`: fuerza el conector y el modo 1366x768. La `e` final **no es un error**: significa “forzar el conector encendido” y evita que se quede apagado esperando a Xorg.
- `fbcon=nodefer`: hace que la consola de framebuffer tome el control de inmediato. Sin esto, el kernel puede quedarse varios segundos sin consola activa y el monitor muestra “no cable connected”.
- `GRUB_GFXMODE=1024x768,auto`: en este equipo GRUB **no puede** usar 1366x768 porque el VBIOS no lo ofrece por VBE. Si pones 1366, cae igualmente a 1024. Dejarlo en 1024 evita el intento fallido y mantiene el menú legible.
- `GRUB_GFXPAYLOAD_LINUX=keep`: mantiene el modo de GRUB hasta que el driver de Linux lo cambia.
- `GRUB_TERMINAL_OUTPUT="gfxterm"`: usa el menú gráfico de GRUB.

> **📌 `DVI-I-1` es el nombre del conector en este equipo.** Si cambias de GPU o de adaptador, compruébalo con `ls /sys/class/drm/` y ajusta las dos apariciones (`drm.edid_firmware` y `video`).

**4. Regenerar `grub.cfg`.** Si aún no habías instalado GRUB, hazlo antes con los comandos de la sección de GRUB (BIOS o UEFI).

```bash
sudo grub-mkconfig -o /boot/grub/grub.cfg
grep -E 'edid_firmware|fbcon=nodefer' /boot/grub/grub.cfg
```

> **📌 Gestor de login:** el vídeo no depende de él. Cuando instales el escritorio, habilita **uno solo** (`sddm.service`, `gdm.service` o `lightdm.service`, según el caso), nunca varios.

### ✅ Comprobar en el primer arranque (solo tty)

Lo más cómodo es repetir el script en modo comprobación:

```bash
sudo bash /mnt/usb/monitor-benq-r5430.sh --check
```

Muestra `[OK]` o `[XX]` por cada punto y termina con un código de salida distinto de cero si algo falla. Lo mismo, a mano:

```bash
cat /proc/cmdline
cat /sys/class/graphics/fb0/virtual_size
stty size

for d in /sys/class/drm/card*-DVI-I-1; do
    echo "== $d =="
    cat "$d/status" "$d/enabled" "$d/dpms"
    wc -c < "$d/edid"
    head -3 "$d/modes"
done
```

Deberías ver:

- En `/proc/cmdline`: `drm.edid_firmware=DVI-I-1:edid/benq-g925hda.bin`, `video=DVI-I-1:1366x768@60e` y `fbcon=nodefer`.
- En `fb0/virtual_size`: `1366,768`.
- En `stty size`: más columnas que antes (la consola ocupa ahora toda la pantalla de 1366 píxeles de ancho).
- El conector `DVI-I-1` como `connected`, `enabled` y `On`.
- El EDID con **128 bytes**.
- El primer modo listado: `1366x768`.

El parpadeo de 1024 a 1366 al principio es esperado: es el único cambio de modo que queda.

> **📌 Con Plasma ya instalado**, además puedes mirar `kscreen-doctor -o | grep -E 'Output|Modes|Geometry'`; debe aparecer `1366x768@59.79`. Es un extra: en el tty no existe.

### Si algo no funciona

- **No hay señal o pantalla negra al arrancar:** desde el menú de GRUB pulsa `e`, añade `nomodeset` al final de la línea que empieza por `linux`, y arranca (`Ctrl+x`) para entrar en modo de recuperación. Luego revisa el EDID y las líneas de GRUB. Ojo: el menú de GRUB usa teclado en inglés, y en un teclado latinoamericano algunas teclas cambian de sitio.
- **El script dice que el conector no existe:** mira `ls /sys/class/drm/` y repite con `--connector NOMBRE`. Si el driver aún no cargó y no hay lista, usa `--force`.
- **El tty sigue a 1024x768:** comprueba que `video=DVI-I-1:1366x768@60e` esté en `/proc/cmdline` y que no haya otro `video=DVI-I-1:1024x768@60e` más.
- **El EDID no carga:** verifica que el archivo tenga 128 bytes y el hash correcto; revisa `sudo journalctl -k -b | grep -i edid` y que no aparezca `EDID err`.
- **El driver de vídeo no se carga:** comprueba que `linux-firmware` (o `linux-firmware-amdgpu`) esté instalado y verifica con `lspci -k | grep -A3 -E 'VGA|Display'` si está usando `radeon` o `amdgpu`.
- **El script falla al verificar el initramfs:** mira la última viñeta del paso 2 (preset antiguo con `ALL_config=`).
- **Actualizas el kernel:** `mkinitcpio` se regenera solo y el EDID sigue en `/usr/lib/firmware/edid/`; si tocas `/etc/default/grub`, vuelve a ejecutar `grub-mkconfig`.

**Para deshacerlo todo:**

```bash
sudo cp /etc/default/grub.bak-monitor /etc/default/grub
sudo rm /etc/mkinitcpio.conf.d/10-monitor-benq.conf
sudo mkinitcpio -P
sudo grub-mkconfig -o /boot/grub/grub.cfg
```

> **📌 La copia es la de la primera ejecución del script.** Si después cambiaste algo más en `/etc/default/grub`, edítalo a mano en vez de restaurar la copia.

### ¿Por qué GRUB no puede usar 1366x768?

Porque GRUB no usa el EDID que inyectamos: usa los modos **VBE** que le da el VBIOS de la tarjeta. El VBIOS de la R5 430 no lista 1366x768, y 1366x768 no es un modo VESA estándar. La R5 430 sí puede con esa resolución —Linux lo demuestra—, pero el límite está en el entorno pre‑arranque.

Un adaptador DVI-I→VGA que sí pase DDC, o un emulador de EDID, podrían hacer que el VBIOS leyera el EDID del BenQ y quizá expusiera 1366x768. No está garantizado. Mientras tanto, el parpadeo 1024→1366 es el compromiso que funciona.

### Referencia: el EDID en base64

Solo para consulta o para generarlo desde otra máquina. **En el tty usa el script.** Son 128 bytes y deben dar el hash de arriba:

```bash
base64 -d > benq-g925hda.bin <<'EOF'
AP///////wAJ0UN4RVQAAAMWAQMOKRd4Lj2FplZKmiQSUFSlaoBxAAEBAQEBAQEBAQEBAQEBZiFW
qlEAHjBGjzMAmuYQAAAeAAAA/wBNMUMwMTY3M1NMMAoKAAAA/QAyTB4/DgAKICAgICAgAAAA/ABC
ZW5RIEc5MjVIREEKAM0=
EOF
```

### Archivos que toca esta nota

- `/usr/lib/firmware/edid/benq-g925hda.bin` — EDID nuevo.
- `/etc/mkinitcpio.conf.d/10-monitor-benq.conf` — `MODULES+=(amdgpu)` y `FILES+=(...)` (no se modifica `/etc/mkinitcpio.conf`).
- `/etc/default/grub` — parámetros del kernel y `GRUB_GFXMODE` (copia previa en `/etc/default/grub.bak-monitor`).
- `/boot/initramfs-*.img` — regenerados con `mkinitcpio -P`.
- `/boot/grub/grub.cfg` — regenerado con `grub-mkconfig`.

El script `monitor-benq-r5430.sh` automatiza todo lo anterior; guárdalo en el pendrive junto a esta guía.