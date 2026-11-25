#!/usr/bin/env bash
# Glyph: packages and the repo-path -> $HOME path map.
# Sourced by install.sh and uninstall.sh. Keep in sync with the rice.
# shellcheck disable=SC2034 # the arrays are consumed by the scripts that source this file

PACMAN=(
    # base
    base-devel git curl jq python
    # session
    hyprland hypridle hyprsunset hyprpicker xdg-desktop-portal-hyprland xdg-desktop-portal-gtk
    sddm quickshell polkit-gnome gnome-keyring geoclue upower xdg-user-dirs xdg-utils
    # sound, network, bluetooth
    pipewire pipewire-pulse pipewire-alsa wireplumber networkmanager bluez bluez-utils blueman power-profiles-daemon
    # utilities called by the binds and the shell
    brightnessctl playerctl wl-clipboard cliphist grim slurp swappy imagemagick libvips libqalculate
    gpu-screen-recorder ydotool libnotify trash-cli
    # terminal and console
    kitty fish starship fastfetch btop cava eza zoxide direnv
    # apps from variables.lua
    thunar pavucontrol
    # fonts (cjk for the kaomoji in Charms), icons (Papirus-Dark is the base for the Rice folder theme),
    # dark base for gtk.css
    ttf-jetbrains-mono-nerd noto-fonts noto-fonts-cjk noto-fonts-emoji papirus-icon-theme adw-gtk-theme
)

AUR=(
    qtengine darkly-bin bibata-cursor-theme-bin
    zen-browser-bin
)

# Optional, like caelestia's optional components. The special-workspace binds read apps from hypr/variables.lua.
declare -A EXTRA=(
    [telegram]="telegram-desktop"                                        # Super+D
    [spotify]="spotify-launcher spicetify-cli spicetify-marketplace-bin" # Super+M
    [clash]="clash-verge-rev-bin"                                        # VPN panel, Super+P
)

# Packages installed by --packages on uninstall. Only the optional AUR ones: the rest is shared with
# the rest of the system and removing it can break other desktops.
PACKAGES_AUR=(
    qtengine darkly-bin bibata-cursor-theme-bin zen-browser-bin
)

G=config/quickshell/glyph
# repo path -> $HOME path
LINKS=(
    "config/hypr                                .config/hypr"
    "$G                                         .config/quickshell/glyph"
    "config/quickshell/rice                     .config/quickshell/rice"
    "config/quickshell/rice/rice                .local/bin/rice"
    "config/kitty                               .config/kitty"
    "config/qtengine                            .config/qtengine"
    "$G/term/qtengine.colors                    .config/qtengine.colors"
    "$G/term/starship.toml                      .config/starship.toml"
    "$G/term/fastfetch                          .config/fastfetch"
    "$G/term/btop                               .config/btop"
    "$G/term/cava                               .config/cava"
    "$G/term/gtk-3.0/gtk.css                    .config/gtk-3.0/gtk.css"
    "$G/term/gtk-4.0/gtk.css                    .config/gtk-4.0/gtk.css"
    "config/fish/config.fish                    .config/fish/config.fish"
    "config/fish/functions/fish_greeting.fish   .config/fish/functions/fish_greeting.fish"
    "config/fonts                               .local/share/fonts/glyph"
)
