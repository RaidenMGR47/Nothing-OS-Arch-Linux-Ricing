# Guía Avanzada de Instalación de Arch Linux con Cifrado (LUKS + LVM) - BIOS y UEFI

Esta guía está diseñada para ser **extremadamente explícita** y cubre tanto sistemas **BIOS (Legacy)** como **UEFI**. Incluye cifrado de disco completo mediante LUKS y gestión de volúmenes lógicos (LVM). Sigue cada paso al pie de la letra.

> **📝 Notas de esta revisión**: Esta versión corrige varios errores que tenía el borrador original: sintaxis incorrecta de `rd.luks.name=`, ambos bloques `sed` de GRUB ejecutándose a la vez (dejaba siempre la sintaxis equivocada), falta del paquete `cryptsetup` en el `pacstrap`, y falta de la partición BIOS boot requerida por GRUB en discos GPT con arranque BIOS Legacy.
> 
> **Actualización**: se añadió soporte opcional para desbloqueo automático con una llave USB (con passphrase como respaldo si el USB no está conectado) — ver el Paso 4 y el Paso 11.2.
> 
> **Actualización (14 de noviembre de 2026)**: la nota extra del monitor (BenQ G925HDA + R5 430) se reescribió para trabajar desde el tty, con el mismo procedimiento que la guía normal, y se añadió el script `monitor-benq-r5430.sh`, que aplica toda la solución respetando los parámetros de LUKS.
>
> **Actualización (22 de noviembre de 2026)**: se añadió el script `hora-teclado-chroot.sh`, que automatiza dentro del chroot la sincronización de hora (NTP) y el teclado de consola y X11 (Paso 9.3), igual que en la guía normal. Aquí se ejecuta con `--no-initramfs`, porque el Paso 10 regenera el initramfs con los hooks de LUKS/LVM. El teclado salió del Paso 9.2 (que ahora es solo idioma) y pasó al 9.3; la sección posterior al arranque (Paso 13) pasó a ser de comprobación.
> **Actualización (27 de noviembre de 2026)**: se añadió la **Opción D: Hyprland + Glyph (estilo Nothing OS)** en la sección 16, con el instalador adaptado para Arch (`--check`, `--keyboard`, `--monitor`, `--links`, `--yes` y `uninstall.sh`). Glyph detecta teclado y monitores, respeta el cifrado y **no toca GRUB, los `HOOKS` de LUKS/LVM ni el initramfs**. También se actualizaron los controladores de GPU (Paso 15.2): ya no se instalan los `xf86-video-*`, `libva-mesa-driver` viene dentro de `mesa` y NVIDIA usa `nvidia-open`.

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

- **XFS** – Moderno, escalable, con _copy‑on‑write_ y reflinks. Ideal para compilaciones (ej. Gentoo). **No se puede reducir** de tamaño. Tamaño mínimo recomendado: 300 MiB.
- **EXT2** – Predecesor de ext4, sin _journaling_ (registro de transacciones). Bajo overhead, por eso a veces se usa en particiones `/boot` pequeñas.
- **EXT4** – Fiable y probado, con journaling, pero sin características modernas como reflinks. Buena opción por defecto para `/` y `/home`.
- **FAT32 (VFAT)** – Obligatorio para la partición EFI en sistemas UEFI. No soporta permisos UNIX.
- **Btrfs**  – Un sistema de archivos moderno que incluye características avanzadas como la creación de instantáneas (_snapshots_) y la autorreparación de datos.
- **Swap** – No almacena archivos de usuario, sino que funciona como memoria virtual de apoyo cuando la memoria RAM física se llena por completo.

---

## 🔧 1. Configuración del Entorno Live

Arranca desde la ISO de Arch Linux.

```bash
# Configurar distribución de teclado (Latinoamérica)
loadkeys la-latin1

# Editar y generar la localización (locale)
# Busca y descomenta (quita el #) estas líneas:
# es_VE.UTF-8 UTF-8
# es_ES.UTF-8 UTF-8
nano /etc/locale.gen
locale-gen
export LANG=es_VE.UTF-8

# Adicionalmente también puedes usar este comando directamente
sed -i 's/^#\s*es_VE.UTF-8 UTF-8/es_VE.UTF-8 UTF-8/' /etc/locale.gen && locale-gen && export LANG=es_VE.UTF-8
```

### 🌐 (Si usas WiFi) Conectar a una red inalámbrica

Si tu equipo se conecta por cable no necesitas esto. Si usas WiFi:

```bash
iwctl
# Dentro de la consola de iwctl:
station list                                   # Ver el nombre de tu adaptador (ej. wlan0)
station wlan0 scan
station wlan0 get-networks
station wlan0 connect "Nombre_De_Tu_Red"
exit
```

```bash
# Verificar conexión a Internet
ping -c 3 google.com
```

---

## 🧹 2. Preparación del Disco (Borrado completo)

**¡ADVERTENCIA!** Los siguientes comandos borran **TODOS** los datos del disco. Asegúrate de que `/dev/sda` es el disco correcto (puede ser `/dev/nvme0n1` o `/dev/vda` según tu sistema). Usa `lsblk` para confirmar.

```bash
# Eliminar información de dispositivo de almacenamiento
wipefs -a /dev/sda

# Borrar tablas de particiones (GPT) y registros (MBR)
sgdisk --zap-all /dev/sda
```

**(Opcional) Sobrescritura segura del disco — elige SOLO UNA de las dos opciones siguientes, no ejecutes ambas:**

```bash
# Opción 1 — HDD: sobrescribir con ceros. Es LENTO (puede tardar HORAS en discos grandes).
# Si el disco ya es nuevo o vas a reciclarlo, puedes omitir este paso por completo.
dd if=/dev/zero of=/dev/sda bs=1M status=progress
```

```bash
# Opción 2 — SSD/NVMe: borrado seguro y rápido a nivel de firmware (recomendado para SSD/NVMe).
blkdiscard /dev/sda
```

---

## 🗂️ 3. Particionado del Disco (`cfdisk`)

**IMPORTANTE**: Elige tu modo de arranque (BIOS o UEFI) y sigue la estructura de particiones correspondiente. **El número de particiones difiere entre ambas opciones**, así que presta atención a los números de partición en el resto de la guía.

```bash
cfdisk /dev/sda
```

- Dentro de `cfdisk`, selecciona `gpt` (Recomendado para ambos modos).
- Crea las particiones **en este orden** según tu caso:

### 🖥️ Opción A: Sistema UEFI (Recomendado para equipos modernos)

|Partición|Tamaño|Tipo|Formato|Punto de montaje|
|:--|:--|:--|:--|:--|
|`/dev/sda1`|**1 GiB**|`EFI System`|FAT32|`/boot`|
|`/dev/sda2`|Resto del espacio|`Linux LVM`|(Será cifrado)|—|

### 🖥️ Opción B: Sistema BIOS (Legacy)

|Partición|Tamaño|Tipo|Formato|Punto de montaje|
|:--|:--|:--|:--|:--|
|`/dev/sda1`|**2 MiB**|`BIOS boot`|**Sin formato**|(no se monta)|
|`/dev/sda2`|**300 MiB**|`Linux filesystem`|ext4|`/boot`|
|`/dev/sda3`|Resto del espacio|`Linux LVM`|(Será cifrado)|—|

> **⚠️ Importante para BIOS + GPT**: la partición `BIOS boot` de 2 MiB es obligatoria en este escenario. GRUB necesita ese espacio sin sistema de archivos para incrustar su `core.img`, porque GPT no deja el "hueco" que MBR sí dejaba al inicio del disco. Si la omites, `grub-install` fallará más adelante con el error _"this GPT partition label contains no BIOS Boot Partition"_. **No la formatees ni la montes**, solo créala con ese tipo.

> **📌 ¿Por qué SÍ hace falta además una partición `/boot` separada aquí?** La partición `BIOS boot` de arriba y `/boot` son cosas distintas: una es solo para que `grub-install` incruste su `core.img`, la otra es donde viven el kernel y el initramfs. En una instalación **sin cifrar** `/boot` podría vivir dentro de la raíz sin problema. Pero aquí la raíz está dentro de LVM dentro de LUKS: si `/boot` viviera ahí, **GRUB mismo** tendría que descifrar el LUKS solo para leer el kernel y el `grub.cfg`. Eso es más fràgil (el soporte de GRUB para LUKS2/Argon2 varía según versión) y, sobre todo, **GRUB no sabe leer la llave USB** que prepararás en el Paso 4 — solo sabe pedir la passphrase escrita. Si `/boot` estuviera cifrado, tendrías que teclear la passphrase en la pantalla de GRUB en cada arranque aunque el USB esté puesto, anulando la comodidad de la llave. Por eso `/boot` se queda siempre en su propia partición sin cifrar: así el descifrado (con o sin USB) ocurre una sola vez, dentro del initramfs, que sí sabe usar la llave.

> **📌 Nota para UEFI**: Aunque montemos la partición EFI en `/boot`, recuerda que su formato debe ser **FAT32** para que el firmware la reconozca.

> **📌 De aquí en adelante**: cuando la guía diga "partición cifrada", usa `/dev/sda2` si elegiste **UEFI**, o `/dev/sda3` si elegiste **BIOS**. Cuando diga "partición `/boot`", usa `/dev/sda1` (UEFI) o `/dev/sda2` (BIOS).

---

## 🔐 4. Cifrado y Configuración LVM

```bash
# Seleccionar la partición grande para cifrar: /dev/sda2 (UEFI) o /dev/sda3 (BIOS)
# Se recomienda LUKS2 con cifrado AES-256 (XTS usa dos claves, de ahí --key-size 512) y hash SHA-512
# Si usas UEFI
cryptsetup luksFormat --type luks2 --cipher aes-xts-plain64 --key-size 512 --hash sha512 /dev/sda2
# Te pedirá escribir SÍ (mayúsculas) y luego tu contraseña segura.

# Si usas BIOS
cryptsetup luksFormat --type luks2 --cipher aes-xts-plain64 --key-size 512 --hash sha512 /dev/sda3
# Te pedirá escribir SÍ (mayúsculas) y luego tu contraseña segura.

# Abrir (desbloquear) la partición y mapearla como "ArchLock"
# Si usas UEFI
cryptsetup open --type luks2 /dev/sda2 ArchLock

# Abrir (desbloquear) la partición y mapearla como "ArchLock"
# Si usas BIOS
cryptsetup open --type luks2 /dev/sda3 ArchLock

# Crear el Volumen Físico (PV) sobre el mapeo cifrado
pvcreate /dev/mapper/ArchLock

# Crear el Grupo de Volúmenes (VG) llamado "arch"
vgcreate arch /dev/mapper/ArchLock

# Crear los Volúmenes Lógicos (LV)
lvcreate -L 8G arch -n swap    # 8 GB de Swap (ajusta según tu RAM)
lvcreate -L 64G arch -n root   # 64 GB para la raíz (ajusta según necesidad)
lvcreate -l 100%FREE arch -n home  # El resto del espacio para /home
```

> **💡 Tip opcional**: si vas a formatear `/home` con ext4 (como en esta guía), el ArchWiki recomienda dejar al menos 256 MiB libres en el grupo de volúmenes para poder usar `e2scrub`. Si quieres seguir esa recomendación, reduce `home` justo después de crearlo: `lvreduce -L -256M arch/home`.

### 🔑 (Opcional pero recomendado) Preparar una llave USB para desbloqueo automático

Puedes añadir una memoria USB como un segundo método de desbloqueo: si está conectada al arrancar, el sistema se desbloquea solo; si no está, te pide la passphrase normalmente, como respaldo. Necesitas un USB conectado ahora mismo, aquí en el entorno live (no hace falta que sea exclusivo para esto, con una particioncita pequeña alcanza).

```bash
# Identifica tu USB (cuidado de no confundirlo con /dev/sda, tu disco principal)
lsblk

# Crea una partición pequeña dedicada (con 32 MiB sobra) en el USB
cfdisk /dev/sdX   # sustituye sdX por tu USB, NUNCA por /dev/sda

# Fórmatea esa partición como ext4: el driver ext4 ya va a estar garantizado
# en tu initramfs (porque tu raíz también es ext4), así que no hace falta
# añadir módulos extra a mkinitcpio para poder leerla
mkfs.ext4 /dev/sdX1
```

```bash
# Genera un keyfile aleatorio de 4 KB
dd if=/dev/urandom of=/root/archlock.key bs=4096 count=1
chmod 600 /root/archlock.key

# Añádelo como un keyslot NUEVO de tu partición cifrada (sda2 UEFI / sda3 BIOS)
# NO reemplaza tu passphrase, se suma como una forma adicional de desbloqueo
cryptsetup luksAddKey /dev/sda2 /root/archlock.key
# Te pedirá una passphrase EXISTENTE (la que ya pusiste en luksFormat) para autorizar el nuevo keyslot.
```

```bash
# Copia el keyfile al USB
mkdir -p /mnt/usbkey
mount /dev/sdX1 /mnt/usbkey
cp /root/archlock.key /mnt/usbkey/archlock.key
chmod 600 /mnt/usbkey/archlock.key
umount /mnt/usbkey

# Borra la copia local; la única copia "viva" queda en el USB + tu passphrase
shred -u /root/archlock.key

# Anota el UUID de la partición del USB, lo necesitarás en el Paso 11
blkid /dev/sdX1
```

> **⚠️ Nunca elimines tu passphrase original.** El USB es una comodidad adicional, no un reemplazo — si lo pierdes o se daña, la passphrase sigue siendo tu única forma de entrar al sistema.
> 
> **🔒 Nota de seguridad**: quien tenga este USB puede desbloquear tu disco sin saber tu passphrase. Guárdalo en un lugar separado del equipo (llavero aparte, no en la misma mochila) si quieres que siga aportando seguridad real y no solo comodidad.

---

## 💽 5. Formateo de Particiones

```bash
# --- Formateo de /boot (NO cifrado) ---
# Si usas UEFI:
mkfs.fat -F32 /dev/sda1

# Si usas BIOS (Legacy):
mkfs.ext2 /dev/sda2
# (No formatees /dev/sda1 en este caso: es la partición BIOS boot, va sin sistema de archivos)

# --- Formateo de volúmenes lógicos ---
mkfs.ext4 /dev/mapper/arch-root
mkfs.ext4 /dev/mapper/arch-home
mkswap /dev/mapper/arch-swap

# Activar el SWAP (hazlo ANTES de genfstab en el paso 7, para que quede registrado en el fstab)
swapon /dev/mapper/arch-swap
```

---

## 📂 6. Montaje de las Particiones

```bash
# Montar la raíz
mount /dev/mapper/arch-root /mnt

# Crear directorios para boot y home
mkdir -p /mnt/{boot,home}

# Montar /boot: /dev/sda1 (UEFI) o /dev/sda2 (BIOS)
mount /dev/sda1 /mnt/boot

# Montar /home
mount /dev/mapper/arch-home /mnt/home
```

**Esquema final de montaje:**

- `/dev/sda1` (UEFI) o `/dev/sda2` (BIOS) → `/mnt/boot` (FAT32 si UEFI, ext2 si BIOS)
- `/dev/mapper/arch-swap` → SWAP
- `/dev/mapper/arch-root` → `/mnt`
- `/dev/mapper/arch-home` → `/mnt/home`

---

## 📦 7. Instalación Base del Sistema (Pacstrap)

```bash
# (Opcional) Actualizar mirrors con reflector antes de instalar
reflector --verbose --latest 20 --sort rate --save /etc/pacman.d/mirrorlist

# Instalar el sistema base
# cryptsetup y lvm2 son OBLIGATORIOS aquí: mkinitcpio los necesita para construir el
# initramfs con los hooks encrypt/sd-encrypt y lvm2 del paso 10.
# linux-headers se usa más adelante si instalas drivers DKMS (NVIDIA propietario, VirtualBox, etc.)
pacstrap -K /mnt base linux linux-firmware linux-headers cryptsetup lvm2 sudo networkmanager grub nano

# Generar el archivo fstab (tabla de sistemas de archivos)
genfstab -U /mnt >> /mnt/etc/fstab

# (Opcional) Verifica que el fstab se haya generado correctamente
cat /mnt/etc/fstab
```

---

## 🐚 8. Entrar al Sistema (Arch-chroot)

> **📌 ¿Vas a usar los scripts de la guía?** Cópialos a `/mnt/root/` **antes** de este comando, desde el ISO live:
>
> ```bash
> mkdir -p /tmp/usb && mount /dev/sdb1 /tmp/usb     # comprueba el nombre con lsblk -f
> cp /tmp/usb/hora-teclado-chroot.sh /mnt/root/
> cp /tmp/usb/monitor-benq-r5430.sh /mnt/root/      # solo si lo vas a usar
> umount /tmp/usb
> ```
>
> Después ejecuta `hora-teclado-chroot.sh` en el Paso 9.3 y, si aplica, `monitor-benq-r5430.sh` cuando GRUB ya esté instalado (Paso 11.4; ver la nota extra del monitor, al final). Si ya entraste al chroot y olvidaste copiarlos, haz `exit`, copia los archivos y vuelve a entrar con `arch-chroot /mnt`: no se pierde nada de lo hecho.

```bash
arch-chroot /mnt
```

**¡A partir de ahora, todos los comandos se ejecutan dentro del chroot!**

---

## ⚙️ 9. Configuración Básica del Sistema

### 9.1. Red y Servicios

```bash
# Activar NetworkManager
systemctl enable NetworkManager.service
```

> **📌 Sobre WiFi**: NetworkManager ya trae su propio manejo de WiFi (usa `wpa_supplicant` por defecto), así que en la mayoría de los casos **no necesitas activar `iwd` por separado**. Si activas `iwd.service` sin configurar NetworkManager para que lo use como backend, ambos servicios competirán por controlar la misma interfaz y puedes tener problemas de conexión. Si prefieres usar `iwd` como backend, configúralo explícitamente en `/etc/NetworkManager/conf.d/wifi_backend.conf` con `[device] wifi.backend=iwd` antes de activarlo.

```bash
sudo pacman -S iwd
```

```bash
nano /etc/NetworkManager/conf.d/wifi_backend.conf
```

```ini
[device]
wifi.backend=iwd
```
### 9.2. Localización e Idioma

```bash
# Editar locale.gen
# Descomenta #es_VE.UTF-8 o #es_ES.UTF-8
nano /etc/locale.gen
locale-gen

# Adicionalmente también puedes usar este comando directamente
sed -i 's/^#\s*es_VE.UTF-8 UTF-8/es_VE.UTF-8 UTF-8/' /etc/locale.gen && locale-gen

echo LANG=es_VE.UTF-8 > /etc/locale.conf
```

> **📌 El teclado y la sincronización de hora se configuran en el Paso 9.3**, justo después de la zona horaria.

### 9.3. Zona Horaria, Hora y Teclado

```bash
# Ejemplo para Caracas/Venezuela o Madrid/España
ln -sf /usr/share/zoneinfo/America/Caracas /etc/localtime
# Alternativa: ln -sf /usr/share/zoneinfo/Europe/Madrid /etc/localtime

hwclock -w   # Sincronizar el reloj del hardware
date         # Verificar que la hora sea correcta
```

> **📌 Hazlo antes del teclado y la hora de abajo:** sin zona horaria, la sincronización NTP dejaría el reloj en UTC. El script te avisa si no encuentra `/etc/localtime`.

**Teclado y sincronización de hora**

Dentro del chroot no hay systemd ni D‑Bus en ejecución, así que `timedatectl` y `localectl` no pueden comunicarse con sus servicios (`systemd-timedated`, `systemd-localed`) y **no escriben nada**. Para dejarlo listo en el primer arranque hay dos caminos: el script (recomendado) o crear los archivos a mano.

**⚡ Camino rápido: `hora-teclado-chroot.sh` (recomendado)**

El script hace por escrito lo que, con el sistema ya arrancado, harían estos comandos:

|Comando (solo en el sistema arrancado)|Lo que hace el script en el chroot|
|---|---|
|`timedatectl set-ntp true`|Habilita `systemd-timesyncd.service`.|
|`localectl set-x11-keymap latam`|Escribe `/etc/X11/xorg.conf.d/00-keyboard.conf` (`XkbLayout "latam"` y `XkbModel "pc105"`), que es lo que lee **SDDM** (usa Xorg) en la pantalla de login.|
|`localectl set-keymap la-latin1`|Pone `KEYMAP=la-latin1` y `XKBLAYOUT=latam` en `/etc/vconsole.conf` (consola `tty`; `localectl` guarda ahí también el layout X11) y conserva otras líneas que ya hubiera, como `FONT=`.|
|`mkinitcpio -P`|Regenera el initramfs. **En esta guía se omite aquí** con `--no-initramfs`: el Paso 10 lo hace después, con los hooks de LUKS/LVM.|

Además:

- Es **idempotente**: puedes ejecutarlo varias veces sin duplicar nada.
- Deja una copia `.bak-teclado` de `/etc/vconsole.conf` y de `00-keyboard.conf` la primera vez que los modifica (solo si ya existían).
- Al terminar **relee los archivos** y comprueba que `systemd-timesyncd` quedó habilitado; si algo no coincide, aborta con un error.
- Avisa (sin abortar) si falta la zona horaria, el paquete `kbd` o el layout X11 (llega con `xkeyboard-config`, que instalan `xorg-server` y el gestor de login).
- **No instala ni habilita** ningún escritorio ni gestor de login, y **no toca `/etc/mkinitcpio.conf`**: los `HOOKS` de LUKS/LVM del Paso 10 quedan intactos.
- Con LUKS el teclado importa dos veces: es el que se usará al escribir tu passphrase en el arranque, siempre que el Paso 10 incluya `keymap` (Opción A) o `sd-vconsole` (Opción B).

**Qué automatiza y qué sigue siendo manual:**

|Paso|¿Lo hace el script?|
|---|---|
|Idioma (`locale.gen`, `locale-gen`, `locale.conf`, Paso 9.2)|No, es manual.|
|Zona horaria y `hwclock -w` (arriba)|No, es manual.|
|`loadkeys la-latin1` y `export LANG=...` del Paso 1|No: solo valen para la sesión del ISO live.|
|Sincronización de hora (NTP)|Sí.|
|Teclado de consola y X11|Sí.|
|`mkinitcpio -P` tras cambiar el teclado|No en este paso (lo hace el Paso 10).|

**Cómo ejecutarlo** (ya dentro del chroot, con idioma y zona horaria configurados; ahí eres root, no hace falta `sudo`):

```bash
bash /root/hora-teclado-chroot.sh --no-initramfs
```

Si no lo copiaste antes de entrar, mira el recuadro del Paso 8. Si lo lanzas desde el ISO live, el script se niega y te explica cómo hacerlo bien. Verás `[OK]` por cada paso y, al final, `Listo`.

> **📌 ¿Por qué `--no-initramfs`?** En el Paso 9.3 el initramfs todavía no tiene los hooks de LUKS/LVM (se configuran en el Paso 10). Regenerarlo ahora sería trabajo doble. Si ejecutas el script **después** del Paso 10 (por ejemplo, porque lo olvidaste), quita la opción: el script regenerará el initramfs conservando tus hooks.

**Opciones del script:**

|Opción|Para qué sirve|
|---|---|
|`--check`|Solo comprueba el resultado, con el sistema ya reiniciado (ver el Paso 13).|
|`--layout NOMBRE`|Layout X11 distinto de `latam` (ej. `es`).|
|`--keymap NOMBRE`|Mapa de consola distinto de `la-latin1` (ej. `es`). Lista: `localectl list-keymaps`.|
|`--model NOMBRE`|Modelo X11 distinto de `pc105`; con `""` no se escribe `XkbModel`.|
|`--no-initramfs`|No ejecuta `mkinitcpio -P`. Recomendada en el Paso 9.3.|

Ejemplo para un teclado español de España: `bash /root/hora-teclado-chroot.sh --layout es --keymap es --no-initramfs`.

**🛠️ Alternativa manual (sin script)**

Hace lo mismo escribiendo los archivos tú mismo. Habilita la sincronización de hora (`systemctl enable` sí funciona en el chroot, porque solo crea el enlace del servicio):

```bash
systemctl enable systemd-timesyncd.service
```

Consola (`tty`):

```bash
cat > /etc/vconsole.conf <<'EOF'
KEYMAP=la-latin1
XKBLAYOUT=latam
EOF
```

X11, que es lo que lee **SDDM** antes de mostrar la pantalla de login:

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

> **📌 Por qué hacen falta los dos archivos:** `KEYMAP=la-latin1` configura la consola (`tty`). `XkbLayout "latam"` configura Xorg, y SDDM usa Xorg. Plasma en Wayland usa su propia configuración de KDE, por eso el teclado funciona dentro del escritorio aunque SDDM estuviera en inglés.

> **📌 Con la alternativa manual** el `cat >` sobrescribe `/etc/vconsole.conf` entero. Si ya tenías ahí otras líneas (como `FONT=`), añádelas de nuevo; el script, en cambio, las conserva.

> **📌 Initramfs:** no hace falta regenerarlo aquí. El Paso 10 ya ejecuta `mkinitcpio -P` después de configurar los hooks, y tanto `keymap` (Opción A) como `sd-vconsole` (Opción B) leen `/etc/vconsole.conf`. Si decides saltarte el Paso 10, ejecuta `mkinitcpio -P` ahora.

**↩️ Para deshacer lo del script:**

```bash
systemctl disable systemd-timesyncd.service
mv /etc/vconsole.conf.bak-teclado /etc/vconsole.conf                          # si existe la copia; si no, borra /etc/vconsole.conf
mv /etc/X11/xorg.conf.d/00-keyboard.conf.bak-teclado /etc/X11/xorg.conf.d/00-keyboard.conf   # si existe la copia; si no, borra 00-keyboard.conf
mkinitcpio -P
```

(`mkinitcpio -P` conserva los hooks de LUKS/LVM del Paso 10, porque el script nunca modificó `/etc/mkinitcpio.conf`.)

**Archivos que toca el script:**

- `/etc/systemd/system/sysinit.target.wants/systemd-timesyncd.service` — enlace que crea `systemctl enable`.
- `/etc/X11/xorg.conf.d/00-keyboard.conf` — layout X11 (copia previa en `.bak-teclado` si ya existía).
- `/etc/vconsole.conf` — `KEYMAP` y `XKBLAYOUT` (copia previa en `.bak-teclado` si ya existía).
- `/boot/initramfs-*.img` — solo si lo ejecutas sin `--no-initramfs`.

### 9.4. Actualizar Mirrors (dentro del chroot)

```bash
pacman -S reflector
reflector --verbose --latest 20 --sort rate --save /etc/pacman.d/mirrorlist
# (Opcional) nano /etc/pacman.d/mirrorlist para revisar
# (Opcional) nano /etc/pacman.conf para ajustes (ej. activar multilib)
```

### 9.5. Nombre del Equipo (Hostname)

```bash
echo "mi-arch-pc" > /etc/hostname   # Cambia "mi-arch-pc" por el nombre que quieras
```

### 9.6. Archivo `/etc/hosts`

```bash
nano /etc/hosts
echo "127.0.1.1        mi-arch-pc.localdomain  mi-arch-pc" >> /etc/hosts
# Asegúrate de que tenga este contenido (ajusta "mi-arch-pc"):
127.0.0.1   localhost
::1         localhost
127.0.1.1   mi-arch-pc.localdomain  mi-arch-pc
```

### 9.7. Creación de Usuarios y Contraseñas

```bash
# Establecer contraseña para ROOT (OBLIGATORIO)
passwd

# Crear usuario regular (OBLIGATORIO)
# Se añaden los grupos storage y power para montar dispositivos y apagar/reiniciar
useradd -c "Tu Nombre Completo" -m -G wheel,audio,video,storage,power -s /bin/bash nombre_usuario

# Establecer contraseña para el usuario (OBLIGATORIO)
passwd nombre_usuario

# Configurar sudo para el grupo wheel
EDITOR=nano visudo
# Adicionalmente también puedes usar este comando directamente
sed -i 's/^#\s*%wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers && echo "Defaults pwfeedback" >> /etc/sudoers

# Busca la línea: # %wheel ALL=(ALL) ALL
# Descoméntala (quita el #) para que quede: %wheel ALL=(ALL) ALL

# (Opcional) Para ver asteriscos al escribir la contraseña en sudo:
# Dentro de /etc/sudoers (con visudo), añade: Defaults pwfeedback
```

---

## 🧩 10. Configuración de `mkinitcpio` (Imagen de arranque) - **¡ELIGE UNA OPCIÓN!**

```bash
nano /etc/mkinitcpio.conf
```

**Opción A (Busybox/udev - Estilo tradicional, más probado):** Busca la línea `HOOKS=(...)` y asegúrate de que contenga los hooks en **ESTE ORDEN** exacto:

```bash
HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block encrypt lvm2 filesystems fsck)
```

**Opción B (Systemd - Moderno, recomendado para sistemas con systemd):**

```bash
HOOKS=(base systemd autodetect microcode modconf kms keyboard sd-vconsole block sd-encrypt lvm2 filesystems fsck)
```

> **📌 Explicación**:
> 
> - El hook `encrypt` (o `sd-encrypt`) debe ir **antes** que `lvm2` y `filesystems`. Esto permite desbloquear el LUKS antes de activar LVM y montar los sistemas de archivos.
> - `keyboard` y `keymap` deben ir **antes** de `encrypt` para que el teclado funcione correctamente al introducir la contraseña.
> - Si usas **systemd** (Opción B), **debes** usar `sd-encrypt` y `sd-vconsole` en lugar de `encrypt` y `keymap`/`consolefont` respectivamente.
> - **Recuerda cuál opción elegiste**: la necesitarás para configurar GRUB correctamente en el Paso 11.

```bash
# Regenerar las imágenes de arranque
mkinitcpio -P
```

---

## 🖥️ 11. Instalación y Configuración de GRUB

### 11.1. Obtener los UUIDs necesarios

```bash
# UUID de la partición cifrada: /dev/sda2 (UEFI) o /dev/sda3 (BIOS)
UUID_CRYPT=$(blkid -s UUID -o value /dev/sda2)

# UUID del root (dentro del LV ya desbloqueado)
UUID_ROOT=$(blkid -s UUID -o value /dev/mapper/arch-root)

# UUID de la partición del USB — SOLO si preparaste la llave USB en el Paso 4
UUID_USB=$(blkid -s UUID -o value /dev/sdX1)   # sustituye sdX1 por la partición real de tu USB
```

### 11.2. Configurar `/etc/default/grub`

```bash
# Habilitar GRUB_ENABLE_CRYPTODISK=y (necesario en ambos casos, ver nota más abajo)
sed -i 's/^#\s*GRUB_ENABLE_CRYPTODISK=y/GRUB_ENABLE_CRYPTODISK=y/' /etc/default/grub
# También puedes hacerlo manualmente
nano /etc/default/grub
```

> **⚠️ IMPORTANTE: ejecuta SOLO UNO de los siguientes CUATRO bloques**, según el hook que elegiste en el Paso 10 **y** si preparaste la llave USB en el Paso 4. Si ejecutas más de uno, el último sobrescribirá a los anteriores y el sistema puede no arrancar.

**Si preparaste la llave USB** (recomendado — te ahorra escribir la passphrase cada vez que el USB está conectado; si no lo está, cae de vuelta a la passphrase normal):

```bash
# --- sd-encrypt + llave USB ---
sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"rd.luks.name=${UUID_CRYPT}=ArchLock rd.luks.key=${UUID_CRYPT}=/archlock.key:UUID=${UUID_USB} rd.luks.options=${UUID_CRYPT}=keyfile-timeout=10s root=UUID=${UUID_ROOT}\"|" /etc/default/grub
```

```bash
# --- encrypt clásico + llave USB ---
sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"cryptdevice=UUID=${UUID_CRYPT}:ArchLock cryptkey=/dev/disk/by-uuid/${UUID_USB}:ext4:/archlock.key root=UUID=${UUID_ROOT}\"|" /etc/default/grub
```

**Si NO preparaste la llave USB** (solo passphrase manual):

```bash
# --- sd-encrypt, solo passphrase ---
sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"rd.luks.name=${UUID_CRYPT}=ArchLock root=UUID=${UUID_ROOT}\"|" /etc/default/grub
```

```bash
# --- encrypt clásico, solo passphrase ---
sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"cryptdevice=UUID=${UUID_CRYPT}:ArchLock root=UUID=${UUID_ROOT}\"|" /etc/default/grub
```

```bash
# Verificar que quede bien el parámetro del kernel
grep GRUB_CMDLINE_LINUX /etc/default/grub

# Verificar que quede descomentado el permiso de LUKS/LVM
grep GRUB_ENABLE_CRYPTODISK /etc/default/grub
```

Ejemplo de cómo debería verse con sd-encrypt + llave USB:

```
GRUB_CMDLINE_LINUX="rd.luks.name=1f099ea8-31a7-4d65-b604-b25fa0825469=ArchLock rd.luks.key=1f099ea8-31a7-4d65-b604-b25fa0825469=/archlock.key:UUID=a1b2c3d4-e5f6-7890-abcd-ef1234567890 rd.luks.options=1f099ea8-31a7-4d65-b604-b25fa0825469=keyfile-timeout=10s root=UUID=bbd4edc0-4043-4175-95a2-ec174ec4ec0c"
```

> **📌 Sobre `GRUB_ENABLE_CRYPTODISK`**: en esta guía `/boot` **nunca** está dentro del contenedor LUKS (siempre es una partición aparte, sin cifrar — ver la nota del Paso 3 sobre por qué esto es justo lo que hace posible que la llave USB funcione). Así que esta opción en la práctica no hace nada en este setup concreto. No causa ningún daño dejarla activada, pero no es estrictamente necesaria aquí.
> 
> **📌 Sobre `root=`**: también podrías usar `root=/dev/mapper/arch-root` en lugar de `root=UUID=...`; ambas funcionan igual de bien. Esta guía usa UUID por consistencia con el resto de los comandos.
> 
> **📌 Sobre la llave USB**: `/archlock.key` es el archivo que copiaste al USB en el Paso 4 (queda en la raíz de esa partición). `keyfile-timeout=10s` es cuánto espera el sistema a que aparezca el USB antes de rendirse y pedirte la passphrase — si tu USB tarda más en enumerarse, sube ese valor. Si el USB no está conectado, el arranque simplemente espera esos 10 segundos y luego pide la passphrase con normalidad, no se queda colgado.

### 11.3. (Opcional) Detectar otros SO para Dual Boot

```bash
# El paquete os-prober NO viene instalado por defecto y es necesario para la detección
pacman -S os-prober
```

Luego, ve al final del archivo `/etc/default/grub`, busca `#GRUB_DISABLE_OS_PROBER=false` y descoméntala.

### 11.4. Instalar GRUB (Elige tu arquitectura)

#### Opción A: **UEFI**

```bash
# Instalar el paquete efibootmgr (si no está instalado)
pacman -S efibootmgr

# Instalar GRUB para UEFI (apunta al directorio donde montaste /boot)
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
```

#### Opción B: **BIOS (Legacy)**

```bash
# Instalar GRUB en el Master Boot Record (MBR) del disco
# Usará automáticamente la partición BIOS boot (/dev/sda1) creada en el Paso 3
grub-install /dev/sda
```

### 11.5. Generar el archivo de configuración de GRUB

**Siempre** que modifiques `/etc/default/grub` o añadas scripts, ejecuta esto:

```bash
grub-mkconfig -o /boot/grub/grub.cfg
```

---

## 🚪 12. Salir, Desmontar y Reiniciar

```bash
# Salir del chroot
exit

# Desmontar todo de forma recursiva
umount -R /mnt

# Desactivar el SWAP
swapoff -a

# Reiniciar el sistema
reboot
```

> **⚠️ Al reiniciar, el sistema te pedirá la contraseña de cifrado (LUKS) para desbloquear la partición cifrada.**

> **✅ Si configuraste la llave USB**: prueba primero **con el USB puesto** (debería arrancar sin pedir nada) y luego reinicia **sin el USB** (debería seguir pidiendo la passphrase con normalidad). Repite la prueba un par de veces antes de confiar plenamente en el mecanismo — y no olvides guardar el USB en un lugar distinto al equipo.

---

## 🌐 13. Configuración Post-Instalación (Dentro del sistema ya instalado)

Una vez que hayas iniciado sesión en tu nuevo Arch Linux (con tu usuario y contraseña), ejecuta:

```bash
# Verificar internet
ping -c 3 google.com

# Si pacman falla por llaves GPG
sudo rm -r /etc/pacman.d/gnupg
sudo pacman-key --init
sudo pacman-key --populate archlinux

# Si necesitas actualizar mirrors
sudo pacman -S reflector
sudo reflector --verbose --latest 20 --sort rate --save /etc/pacman.d/mirrorlist
sudo pacman -Syu   # Actualizar sistema
```

**Hora y teclado:**

> **📌 Si en el chroot usaste `hora-teclado-chroot.sh` (Paso 9.3) o creaste los archivos a mano, esto ya está hecho:** aquí solo tienes que comprobar que quedó bien.

Comprobar (el script quedó en `/root/` porque lo copiaste a `/mnt/root/` antes de entrar al chroot):

```bash
sudo bash /root/hora-teclado-chroot.sh --check
```

Muestra `[OK]` o `[XX]` por cada punto y termina con un código de salida distinto de cero si algo falla. Consulta a `timedatectl` y `localectl`, es decir, al propio systemd. Lo mismo, a mano:

```bash
timedatectl
localectl status
```

Deberías ver:

- En `timedatectl`: `NTP service: active` y, pasados unos segundos con red, `System clock synchronized: yes`.
- En `localectl status`: `VC Keymap: la-latin1` y `X11 Layout: latam`.

**Si te saltaste el Paso 9.3 o ya habías arrancado el sistema**, puedes ejecutar el script desde aquí con `sudo bash RUTA/hora-teclado-chroot.sh` (sin `--no-initramfs`: regenerará el initramfs conservando tus hooks de LUKS/LVM, y además arranca la sincronización de hora al momento). O bien usar los comandos:

```bash
sudo timedatectl set-ntp true
sudo localectl set-keymap la-latin1
sudo localectl set-x11-keymap latam
```

> **📌 `localectl` solo funciona con el sistema ya arrancado**, porque necesita comunicarse con `systemd-localed` a través de D‑Bus. En el chroot falla y no escribe nada; por eso allí se usa el script (o se crean los archivos a mano) en el Paso 9.3. Usa estos comandos si olvidaste ese paso o si ya habías arrancado el sistema. Si los ejecutas ahora y quieres que el `tty` temprano también quede bien, termina con `sudo mkinitcpio -P` (esto conserva los hooks de LUKS/LVM que configuraste en el Paso 10).

---

## 🔑 14. Proteger GRUB con Contraseña (Opcional pero Recomendado)

Esto evita que alguien edite los parámetros de arranque o entre al recovery sin autorización.

```bash
# Generar el hash de la contraseña con USER
sudo grub-mkpasswd-pbkdf2

# Generar el hash de la contraseña con ROOT
grub-mkpasswd-pbkdf2

# Introduce la contraseña que quieras para GRUB y copia el hash generado (empieza por "grub.pbkdf2...").

# Crear el archivo de usuarios
sudo nano /etc/grub.d/01_users
```

Pega este contenido, sustituyendo `AQUÍ_EL_HASH` por el hash que copiaste:

```bash
#!/bin/sh
cat << EOF
set superusers="nombre_usuario, root"
password_pbkdf2 nombre_usuario AQUÍ_EL_HASH_USER
password_pbkdf2 root AQUÍ_EL_HASH_ROOT
EOF
```

```bash
# Dar permisos de ejecución al script
sudo chmod +x /etc/grub.d/01_users

# Regenerar la configuración de GRUB (siempre al modificar)
sudo grub-mkconfig -o /boot/grub/grub.cfg
```

> **📌 Consejo**: Ahora, al arrancar, si presionas `e` para editar, te pedirá usuario (`nombre_usuario o root`) y la contraseña que pusiste.

---

## 🎮 15. Drivers de GPU y CPU

### 15.1. Drivers de CPU (microcódigo)

```bash
sudo pacman -S intel-ucode   # Para Intel
sudo pacman -S amd-ucode     # Para AMD

# Buena práctica: regenerar el initramfs para asegurar que el microcódigo quede incluido
# (normalmente ocurre automático vía un hook de pacman, pero no está de más confirmarlo)
sudo mkinitcpio -P
```

### 15.2. Drivers de GPU

> **📌 Qué cambió respecto a versiones anteriores de esta guía**:
> 
> - Los controladores de Xorg (`xf86-video-amdgpu`, `xf86-video-ati`, `xf86-video-intel`, `xf86-video-nouveau`) ya no se instalan: Plasma y GNOME usan sesión Wayland, y en el resto de casos basta el driver *modesetting* integrado en el kernel + Mesa.
> - `libva-mesa-driver` dejó de ser un paquete aparte: ahora lo incluye `mesa` (junto con la aceleración de vídeo VA‑API). Para la aceleración de vídeo en Firefox basta VA‑API; no necesitas `mesa-vdpau`.
> - NVIDIA: desde el driver 590 (diciembre de 2025) los paquetes oficiales son solo de módulos abiertos: `nvidia-open` reemplazó a `nvidia` y `nvidia-open-dkms` a `nvidia-dkms`. Las GPU Maxwell, Pascal y Volta quedaron fuera de los repos oficiales.

#### AMD / ATI (open‑source)

```bash
sudo pacman -S --needed mesa vulkan-radeon
```

El firmware (`linux-firmware-amdgpu`) ya viene incluido con `linux-firmware`.

#### NVIDIA

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

#### Intel (open‑source)

```bash
sudo pacman -S --needed mesa vulkan-intel intel-media-driver
```

`intel-media-driver` (VA‑API) es para GPU Intel de la generación Broadwell (≈2014) en adelante; para las anteriores usa `libva-intel-driver`.

### 15.3. Máquina Virtual (VirtualBox)

```bash
sudo pacman -S virtualbox-guest-utils
sudo systemctl enable vboxservice.service
sudo systemctl start vboxservice.service
```

### 15.4. Base para Entorno de Escritorio (Xorg)

```bash
sudo pacman -S xorg-server xorg-xinit mesa mesa-demos
```

---

## 🖥️ 16. Instalar Entorno de Escritorio

### Opción A: **KDE Plasma**

```bash
sudo pacman -S plasma-meta plasma-workspace sddm dolphin konsole kate vlc gwenview okular noto-fonts-cjk

# Activar e iniciar SDDM
sudo systemctl enable sddm.service
sudo systemctl start sddm.service
# (Luego puedes reiniciar con: reboot)
```

### Opción B: **GNOME**

```bash
sudo pacman -S gnome gnome-tweaks noto-fonts-cjk

# Activar e iniciar GDM
sudo systemctl enable gdm.service
sudo systemctl start gdm.service
# (Luego puedes reiniciar con: reboot)
```

> **📌 Hyprland no va en las opciones A ni B:** para Hyprland con el rice Glyph (estilo Nothing OS) usa la **Opción D** de más abajo, que emplea **SDDM** y no cambia el arranque cifrado.

### Opción D: **Hyprland + Glyph (estilo Nothing OS)** (**SDDM**)

Un escritorio con el aspecto de Nothing OS sobre Hyprland: barra flotante, launcher, panel de control, deck, widgets y una pantalla de login a juego, todo hecho con **Quickshell**. [**Glyph**](https://github.com/Nebelung-cloud/glyph-rice) es un rice único y autocontenido que trae sus propias configuraciones de Hyprland, Quickshell, kitty, fish, fastfetch, btop, cava, fuentes y el tema de SDDM. En este repositorio se usa la copia adaptada con el instalador para Arch.

- Repo: `https://github.com/RaidenMGR47/Nothing-OS-Arch-Linux-Ricing.git` (tu copia adaptada; upstream: `https://github.com/Nebelung-cloud/glyph-rice`)
- Requisitos: Arch cifrado ya arrancado (Paso 13) con los **Controladores de GPU** actualizados del Paso 15.2, Internet y **Hyprland 0.56+**; el instalador pone el resto (`quickshell` 0.3.1+, SDDM 0.21+, kitty, fish…).
- Lo que esta guía ya hizo y no se repite: teclado de consola/X11 y hora del chroot (Paso 9.3), `pacman -Syu` (Paso 13), usuario con `sudo`, `nano`, NetworkManager, Firefox y los drivers de GPU (Paso 15.2). El instalador se encarga de PipeWire/WirePlumber, `noto-fonts` y el resto.

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
./install.sh --yes --with ""    # desatendido: sin extras y sin preguntas
./install.sh --keyboard latam   # forzar el layout (o "latam,us")
./install.sh --monitor DVI-I-1:1366x768@60   # forzar el modo del BenQ
./install.sh --links            # solo enlaces + user.lua, sin paquetes
```

Con `--yes` no se pregunta nada: si no pasas `--with`, no instala extras.

> **📌 PulseAudio:** si ya tenías PulseAudio, con `--yes` se elimina antes de instalar PipeWire (con `--noconfirm`, pacman rechazaría el conflicto). Si la eliminación normal falla, se reintenta con `pacman -Rdd`, que salta la comprobación de dependencias; revisa si algún paquete de terceros necesitaba `pulseaudio`.

Qué hace, en orden:

1. `sudo pacman -Syu` y después `sudo pacman -S --needed` con su lista de paquetes: Hyprland, `quickshell`, SDDM, PipeWire, NetworkManager, bluez, kitty, fish, fuentes, `grim`/`slurp`, `cliphist`, etc. Es una actualización completa, no parcial.
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
- **Resolución rara en el BenQ:** comprueba `./install.sh --check`; si el conector no reporta modos, fíjalo con `./install.sh --monitor DVI-I-1:1366x768@60` como en D6; el resto de la nota del monitor sigue aplicando (EDID, `amdgpu` y los parámetros de vídeo en `GRUB_CMDLINE_LINUX_DEFAULT`, sin tocar los de LUKS).
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
3. Restaura `/etc/vconsole.conf` y `/etc/X11/xorg.conf.d/00-keyboard.conf` desde la **más antigua** de sus copias `.glyph-backup-*` (la original de antes de Glyph).
4. Borra `/usr/share/sddm/themes/glyph`, `/etc/sddm.conf.d/zz-glyph.conf` y la regla udev `70-glyph-uinput.rules` de `ydotool`.
5. Borra el marcador `~/.local/state/rice/shell`.

Opciones: `--no-restore` (no restaurar configuraciones), `--keep-sddm` (dejar tema y configuración de SDDM), `--packages` (ofrecer quitar solo los paquetes AUR opcionales — `zen-browser-bin` es tu navegador; con `--yes` los quita sin preguntar) y `--yes` (no preguntar).

**No deshabilita SDDM, no desinstala Hyprland/Quickshell/SDDM y no borra el repo.** Si además quieres borrar el repo y las fuentes, hazlo a mano al terminar:

```bash
rm -rf ~/.local/share/raidenmgr47 ~/.local/share/fonts/glyph
# Solo paquetes que ya no uses (NO borres sddm si lo usas para otro escritorio):
sudo pacman -Rns qtengine darkly-bin bibata-cursor-theme-bin zen-browser-bin
```

**Archivos que toca la Opción D:**

- `~/.config/` — Hyprland, Quickshell, kitty, fish, starship, fastfetch, btop, cava, GTK/Qt (copias previas en `~/.dots-backup-<fecha>/`; el desinstalador restaura solo la más reciente y deja las demás intactas).
- `~/.local/bin/rice` — lanzador del shell.
- `~/.local/share/raidenmgr47/` — el repo clonado.
- `~/.local/share/fonts/glyph/` — fuentes del rice.
- `~/.config/demonshot/` y `~/.local/state/rice/` — estado del rice y del selector de fondos.
- `~/.local/share/icons/Rice/` — tema de iconos que crea `rice` al cambiar de shell o de color de carpetas (`uninstall.sh` no lo borra).
- `gsettings` de GNOME: `color-scheme=prefer-dark`, `gtk-theme=adw-gtk3-dark` e `icon-theme=Rice` (`uninstall.sh` no los revierte).
- `~/Pictures/Wallpapers/` — carpeta del selector de fondos (no la vacía).
- `~/Pictures/Gifs/` — GIF del widget del gato (no la vacía).
- `/etc/sddm.conf.d/zz-glyph.conf` y `/usr/share/sddm/themes/glyph` — tema de login.
- `/etc/udev/rules.d/70-glyph-uinput.rules` — regla de `ydotool`.
- **No toca** `/etc/default/grub`, `grub.cfg`, `HOOKS` ni el initramfs: Glyph no instala Plymouth ni cambia el arranque.

### Navegador web (Firefox)

```bash
sudo pacman -S firefox
```

Si usas **KDE Plasma**, instala también la integración GTK de KDE:

```bash
sudo pacman -S kde-gtk-config
```

Es lo que hace que Firefox en Wayland muestre los botones de minimizar y maximizar; sin él puede mostrar solo el de cerrar. En GNOME no hace falta.

---

## ✅ Fin de la Guía

¡Tu sistema Arch Linux con disco completamente cifrado, LVM y entorno gráfico está listo! Recuerda siempre hacer backup de tus datos importantes antes de manipular particiones.

---

## 🧩 Nota extra: configuración de vídeo para este equipo (BenQ G925HDA + R5 430)

> **📌 Cuándo aplicarla:** con GRUB ya instalado (Paso 11.4) y **antes de instalar ningún entorno gráfico**. Sirve dentro del `chroot` (antes de salir, Paso 12) y también desde el sistema ya arrancado en el **tty**, una vez desbloqueado LUKS. Todo lo de esta nota se puede hacer sin interfaz gráfica.
>
> Esta nota es **independiente del cifrado**: no cambia LUKS, LVM ni los parámetros de desbloqueo (`GRUB_CMDLINE_LINUX`); solo añade configuración de vídeo.

Esta nota reproduce la configuración que quedó funcionando en **este equipo concreto**. No es una receta universal:

- Monitor **BenQ G925HDA** analógico, 1366x768@59.79, EDID `BNQ7843`.
- GPU **AMD Radeon R5 430 OEM** (Oland/SI).
- Monitor conectado al conector **`DVI-I-1`** mediante un adaptador **DVI-I → VGA sin DDC**.
- Arranque **BIOS/legacy**.

El adaptador no pasa la línea DDC, así que el kernel no puede leer el EDID del monitor. GRUB tampoco puede usar 1366x768 porque el VBIOS de la R5 430 no lo expone por VBE. La solución es inyectar el EDID al kernel, cargar `amdgpu` temprano y forzar el conector.

Resultado final: GRUB sigue a 1024x768, pero el kernel, el `tty`, el gestor de login y el escritorio usan 1366x768. Solo queda un parpadeo breve al cambiar de 1024 a 1366; es normal.

**Resumen:** crear el EDID → añadir `amdgpu` y el EDID al initramfs → ajustar GRUB (sin tocar LUKS) → regenerar initramfs y `grub.cfg` → reiniciar y comprobar.

### ⚡ Camino rápido: script desde un pendrive (recomendado)

`monitor-benq-r5430.sh` hace todos los pasos de esta nota. Es pensado para el tty: no hay que teclear el EDID (200 caracteres de base64) ni editar archivos a mano. Además:

- Verifica el tamaño (128 bytes) y el hash del EDID antes de instalarlo.
- Es **idempotente**: puedes ejecutarlo varias veces sin duplicar parámetros.
- Conserva los parámetros de kernel que ya tuvieras en `GRUB_CMDLINE_LINUX_DEFAULT` y deja una copia de `/etc/default/grub` en `/etc/default/grub.bak-monitor`.
- **No toca `GRUB_CMDLINE_LINUX`** (donde viven `rd.luks.name=`/`cryptdevice=`, `rd.luks.key=`/`cryptkey=` y `root=`). Al terminar comprueba que siguen idénticos en el archivo y que llegaron a `grub.cfg`; si no, aborta.
- Se niega a continuar si `/boot` figura en `/etc/fstab` pero no está montado, porque el initramfs y `grub.cfg` acabarían escritos en el sitio equivocado y el sistema no arrancaría.
- Comprueba que `amdgpu` y el EDID **entraron de verdad** en el initramfs y en `grub.cfg`.

**Desde el sistema instalado (tty), ya desbloqueado:**

```bash
lsblk -f                                  # localiza el pendrive (ej. /dev/sdb1)
sudo mkdir -p /mnt/usb
sudo mount /dev/sdb1 /mnt/usb
sudo bash /mnt/usb/monitor-benq-r5430.sh
sudo umount /mnt/usb
sudo reboot
```

> **⚠️ No confundas el pendrive del script con la llave USB del Paso 4.** Son dispositivos distintos: identifica cada uno con `lsblk -f` (la llave tiene la partición ext4 pequeña cuyo UUID anotaste como `UUID_USB`). Monta el del script en `/mnt/usb` y no escribas nada en la llave.
>
> **📌 Pendrive y teclado:** FAT32, exFAT y ext4 se montan tal cual (para NTFS usa `mount -t ntfs3`). Se ejecuta con `bash RUTA`, así que no importa que el pendrive esté montado sin permiso de ejecución. Si `/` o `-` no salen donde esperas, ejecuta antes `loadkeys la-latin1`.

**Durante la instalación (ISO live, sistema montado en `/mnt`, con `/boot` ya montado en el Paso 6):** copia el script **antes** del `arch-chroot /mnt` del Paso 8 y, cuando GRUB ya esté instalado (Paso 11.4), ejecútalo dentro del chroot (ahí ya eres root, no hace falta `sudo`):

```bash
mkdir -p /tmp/usb && mount /dev/sdb1 /tmp/usb     # comprueba el nombre con lsblk -f
cp /tmp/usb/monitor-benq-r5430.sh /mnt/root/
umount /tmp/usb
arch-chroot /mnt

# ...Pasos 9 a 11.4 y, después, dentro del chroot:
bash /root/monitor-benq-r5430.sh
```

El script ya ejecuta `mkinitcpio -P` y `grub-mkconfig`, así que no hace falta volver a lanzar esos dos comandos (Pasos 10 y 11.5) después de usarlo. Eso sí: los `HOOKS` del Paso 10 y los parámetros de LUKS del Paso 11.2 deben estar hechos **antes**.

> **📌 Parpadeo antes del prompt de LUKS:** como `amdgpu` se carga desde el initramfs, el cambio a 1366x768 puede ocurrir antes de que aparezca la petición de passphrase. Es normal ver un parpadeo en ese punto; espera unos segundos si el prompt tarda. No afecta al desbloqueo, ni con la llave USB ni sin ella.

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

- `MODULES+=(amdgpu)` hace que el driver se cargue desde el initramfs, antes de montar la raíz.
- `FILES+=(...)` mete el EDID dentro del initramfs para que el kernel lo tenga disponible al arrancar.
- **No cambies `HOOKS`**: en esta guía ya elegiste la Opción A o B en el Paso 10, y esos hooks son los que permiten desbloquear LUKS y activar LVM. Añadir `amdgpu` a `MODULES` no altera su orden ni su funcionamiento.
- Los drop-ins no se leen si llamas a `mkinitcpio` con `-c`, ni si un preset **antiguo** de `/etc/mkinitcpio.d/` tiene una línea `ALL_config=` sin comentar. En una instalación nueva no pasa. Si pasara, comenta esa línea. Si lo prefieres, puedes poner las dos líneas directamente en `/etc/mkinitcpio.conf`.

**3. Configurar GRUB con `sed` (sin tocar los parámetros de LUKS).** Haz primero una copia. **El primer `sed` solo se ejecuta una vez**: si lo repites, los parámetros se duplican (si pasa, restaura la copia y empieza de nuevo).

> **⚠️ Muy importante:** en esta guía, `GRUB_CMDLINE_LINUX` contiene los parámetros de desbloqueo (`rd.luks.name=...` o `cryptdevice=...`) y `root=UUID=...`. Estos comandos solo tocan `GRUB_CMDLINE_LINUX_DEFAULT`, que GRUB concatena con la otra línea al arrancar. **No los borres ni los reemplaces.**

```bash
sudo cp /etc/default/grub /etc/default/grub.bak-monitor

sudo sed -i -E 's|^GRUB_CMDLINE_LINUX_DEFAULT="(.*)"|GRUB_CMDLINE_LINUX_DEFAULT="\1 drm.edid_firmware=DVI-I-1:edid/benq-g925hda.bin video=DVI-I-1:1366x768@60e fbcon=nodefer"|' /etc/default/grub

sudo sed -i -E 's|^#?GRUB_GFXMODE=.*|GRUB_GFXMODE=1024x768,auto|; s|^#?GRUB_GFXPAYLOAD_LINUX=.*|GRUB_GFXPAYLOAD_LINUX=keep|; s|^#?GRUB_TERMINAL_OUTPUT=.*|GRUB_TERMINAL_OUTPUT="gfxterm"|' /etc/default/grub

grep -E '^GRUB_(CMDLINE_LINUX(_DEFAULT)?|GFXMODE|GFXPAYLOAD_LINUX|TERMINAL_OUTPUT)=' /etc/default/grub
```

Debes ver algo así (tus parámetros previos, como `loglevel=3 quiet`, se conservan; son opcionales y solo controlan cuánto texto muestra el arranque). La línea `GRUB_CMDLINE_LINUX` debe quedar **exactamente como estaba**:

```ini
GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet drm.edid_firmware=DVI-I-1:edid/benq-g925hda.bin video=DVI-I-1:1366x768@60e fbcon=nodefer"
GRUB_CMDLINE_LINUX="rd.luks.name=... root=UUID=..."   # NO tocar: LUKS/LVM
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

> **📌 Si prefieres añadir los parámetros de vídeo a `GRUB_CMDLINE_LINUX`**, puedes hacerlo al final de esa misma línea, pero **sin quitar** `rd.luks.name=`/`cryptdevice=` ni `root=`. El script y estos `sed` usan `GRUB_CMDLINE_LINUX_DEFAULT` precisamente para no arriesgarse a tocar esa línea.

> **📌 `DVI-I-1` es el nombre del conector en este equipo.** Si cambias de GPU o de adaptador, compruébalo con `ls /sys/class/drm/` y ajusta las dos apariciones (`drm.edid_firmware` y `video`).

**4. Regenerar `grub.cfg`.** Con `/boot` montado (en el chroot, el del Paso 6):

```bash
sudo grub-mkconfig -o /boot/grub/grub.cfg
```

Comprueba que la configuración quedó escrita y que LUKS sigue intacto:

```bash
grep -E '^GRUB_CMDLINE_LINUX(_DEFAULT)?=' /etc/default/grub
grep -E 'edid_firmware|fbcon=nodefer' /boot/grub/grub.cfg
grep -E 'rd\.luks|cryptdevice' /boot/grub/grub.cfg
```

La primera y la tercera deben mostrar tus parámetros de desbloqueo; la segunda, que el vídeo quedó escrito.

> **📌 Gestor de login:** el vídeo no depende de él. Cuando instales el escritorio (Paso 16), habilita **uno solo** (`sddm.service` o `gdm.service`), nunca ambos. Si instalas el escritorio desde el chroot, ejecuta los mismos `pacman -S` del Paso 16 (sin `sudo`) y habilita el servicio antes de salir.
>
> **📌 GDM y teclado:** si usas GDM, el greeter puede arrancar en Wayland y no leer `/etc/X11/xorg.conf.d/00-keyboard.conf`. La configuración del Paso 9.3 está pensada para SDDM/X11 y para la consola. Si el teclado del greeter de GDM sale en inglés, configúralo desde GNOME o usa SDDM.

### ✅ Comprobar en el primer arranque (solo tty)

Lo más cómodo es repetir el script en modo comprobación:

```bash
sudo bash /mnt/usb/monitor-benq-r5430.sh --check
```

Muestra `[OK]` o `[XX]` por cada punto (incluidos los parámetros de LUKS de `GRUB_CMDLINE_LINUX`, que deben estar en `/proc/cmdline`) y termina con un código de salida distinto de cero si algo falla. Lo mismo, a mano:

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

- En `/proc/cmdline`: `drm.edid_firmware=DVI-I-1:edid/benq-g925hda.bin`, `video=DVI-I-1:1366x768@60e`, `fbcon=nodefer` y tus parámetros de LUKS (`rd.luks.name=` o `cryptdevice=`).
- En `fb0/virtual_size`: `1366,768`.
- En `stty size`: más columnas que antes (la consola ocupa ahora toda la pantalla de 1366 píxeles de ancho).
- El conector `DVI-I-1` como `connected`, `enabled` y `On`.
- El EDID con **128 bytes**.
- El primer modo listado: `1366x768`.

El parpadeo de 1024 a 1366 al principio es esperado: es el único cambio de modo que queda.

> **📌 Con Plasma ya instalado**, además puedes mirar `kscreen-doctor -o | grep -E 'Output|Modes|Geometry'`; debe aparecer `1366x768@59.79`. Es un extra: en el tty no existe.

### Teclado en SDDM/X11

El teclado latinoamericano del greeter se configura en el **Paso 9.3**, con `hora-teclado-chroot.sh` (o creando a mano `/etc/vconsole.conf` y `/etc/X11/xorg.conf.d/00-keyboard.conf`). Si olvidaste ese paso, ya arrancado puedes ejecutar el script o los `localectl` del **Paso 13**.

### Si algo no funciona

- **No arranca o no pide la contraseña de LUKS:** desde el menú de GRUB pulsa `e` y revisa que la línea `linux` conserve `rd.luks.name=` o `cryptdevice=` y `root=`. Si el problema apareció tras añadir el vídeo, elimina temporalmente `drm.edid_firmware`, `video=` y `fbcon=nodefer` para confirmar que el arranque cifrado sigue bien.
- **No hay señal o pantalla negra al arrancar:** desde el menú de GRUB pulsa `e`, añade `nomodeset` al final de la línea que empieza por `linux`, y arranca (`Ctrl+x`) para entrar en modo de recuperación. Luego revisa el EDID y las líneas de GRUB. Ojo: el menú de GRUB usa teclado en inglés, y en un teclado latinoamericano algunas teclas cambian de sitio. Si protegiste GRUB con contraseña (Paso 14), te pedirá usuario y contraseña antes de dejarte editar.
- **El script dice que `/boot` no está montado:** móntalo (`mount /boot`; desde el ISO, `mount /dev/sda1 /mnt/boot` en UEFI o `mount /dev/sda2 /mnt/boot` en BIOS) y repite.
- **El script dice que el conector no existe:** mira `ls /sys/class/drm/` y repite con `--connector NOMBRE`. Si el driver aún no cargó y no hay lista, usa `--force`.
- **El tty sigue a 1024x768:** comprueba que `video=DVI-I-1:1366x768@60e` esté en `/proc/cmdline` y que no haya otro `video=DVI-I-1:1024x768@60e` más.
- **El EDID no carga:** verifica que el archivo tenga 128 bytes y el hash correcto; revisa `sudo journalctl -k -b | grep -i edid` y que no aparezca `EDID err`.
- **`amdgpu` no se carga:** comprueba que `linux-firmware` (o `linux-firmware-amdgpu`) esté instalado y que `lsinitcpio /boot/initramfs-linux.img | grep amdgpu` lo encuentre.
- **El script falla al verificar el initramfs:** mira la última viñeta del paso 2 (preset antiguo con `ALL_config=`).
- **Actualizas el kernel:** `mkinitcpio` se regenera solo y el EDID sigue en `/usr/lib/firmware/edid/`; si tocas `/etc/default/grub`, vuelve a ejecutar `grub-mkconfig`. Si regeneras el initramfs a mano, `mkinitcpio -P` conserva los hooks de LUKS/LVM.

**Para deshacerlo todo:**

```bash
sudo cp /etc/default/grub.bak-monitor /etc/default/grub
sudo rm /etc/mkinitcpio.conf.d/10-monitor-benq.conf
sudo mkinitcpio -P
sudo grub-mkconfig -o /boot/grub/grub.cfg
```

> **📌 La copia es la de la primera ejecución del script.** Si después cambiaste algo más en `/etc/default/grub` (por ejemplo los parámetros de LUKS del Paso 11.2), edítalo a mano en vez de restaurar la copia.

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
- `/etc/mkinitcpio.conf.d/10-monitor-benq.conf` — `MODULES+=(amdgpu)` y `FILES+=(...)` (no se modifica `/etc/mkinitcpio.conf`, así que los `HOOKS` de LUKS/LVM del Paso 10 quedan intactos).
- `/etc/default/grub` — parámetros de vídeo en `GRUB_CMDLINE_LINUX_DEFAULT`, sin tocar los de LUKS en `GRUB_CMDLINE_LINUX` (copia previa en `/etc/default/grub.bak-monitor`).
- `/boot/initramfs-*.img` — regenerados con `mkinitcpio -P`.
- `/boot/grub/grub.cfg` — regenerado con `grub-mkconfig`.

Los archivos de teclado `/etc/vconsole.conf` y `/etc/X11/xorg.conf.d/00-keyboard.conf` los creas en el Paso 9.3 (con `hora-teclado-chroot.sh` o a mano); esta nota y el script del monitor no los tocan.

El script `monitor-benq-r5430.sh` automatiza todo lo anterior; guárdalo en el pendrive junto a esta guía.
