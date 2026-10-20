#!/bin/bash
# Instala onedrive-linux-sync para el usuario actual. Pide sudo solo para lo
# que lo necesita (binarios en /usr/local, sudoers, fuse.conf).
set -eu
cd "$(dirname "$0")"
[ "$(id -u)" -ne 0 ] || { echo "Ejecutalo como tu usuario normal, no como root."; exit 1; }

echo "== Comprobando dependencias"
falta=0
for c in rclone inotifywait gio xdotool xprop zenity notify-send flock python3 fusermount3; do
    command -v "$c" >/dev/null || { echo "  falta: $c"; falta=1; }
done
[ "$falta" -eq 0 ] || { echo "Instala lo que falta. En Ubuntu/Debian: sudo apt install rclone inotify-tools xdotool x11-utils zenity libnotify-bin fuse3"; exit 1; }
rclone listremotes | grep -qx "onedrive:" || { echo "Falta el remoto de rclone llamado 'onedrive'. Crealo con:  rclone config   (tipo onedrive, nombre: onedrive)"; exit 1; }

echo "== Binarios"
sudo install -m 755 bin/* /usr/local/bin/
sudo install -m 755 sbin/onedrive-bind /usr/local/sbin/
sed "s/__USER__/$USER/" sudoers.d/onedrive-bind | sudo install -m 440 /dev/stdin /etc/sudoers.d/onedrive-bind
sudo visudo -cf /etc/sudoers.d/onedrive-bind >/dev/null
grep -q "^user_allow_other" /etc/fuse.conf 2>/dev/null || echo user_allow_other | sudo tee -a /etc/fuse.conf >/dev/null

echo "== Servicios de usuario"
mkdir -p ~/.config/systemd/user ~/.config/autostart ~/.config/onedrive-sync ~/OneDrive ~/.onedrive-local
install -m 644 systemd/* ~/.config/systemd/user/
install -m 644 autostart/onedrive-marcas-vivas.desktop ~/.config/autostart/
systemctl --user daemon-reload
systemctl --user enable --now onedrive.service onedrive-cola.service onedrive-delta.service onedrive-local.timer onedrive-sync.timer onedrive-salud.timer
sudo loginctl enable-linger "$USER"   # para que arranque sin iniciar sesion grafica

echo "== Menu del boton derecho"
if command -v nemo >/dev/null; then
    mkdir -p ~/.local/share/nemo/actions; install -m 644 nemo-actions/* ~/.local/share/nemo/actions/; echo "  Nemo: listo"
fi
if command -v thunar >/dev/null; then
    if [ -f ~/.config/Thunar/uca.xml ]; then
        echo "  Thunar: ya tenes acciones propias en ~/.config/Thunar/uca.xml. Agrega a mano las de thunar/uca.xml."
    else
        mkdir -p ~/.config/Thunar; install -m 644 thunar/uca.xml ~/.config/Thunar/; echo "  Thunar: listo"
    fi
    xfconf-query -c thunar -p /misc-window-title-style -s THUNAR_WINDOW_TITLE_STYLE_FULL_PATH_WITH_THUNAR_SUFFIX 2>/dev/null || true
fi
if command -v nemo >/dev/null && command -v gsettings >/dev/null; then
    # Lo que necesitan las marcas: el titulo con la ruta completa (lo lee el
    # demonio de marcas) e iconos "standard" en la vista de lista (con iconos
    # mas chicos Nemo no dibuja los emblemas).
    gsettings set org.nemo.preferences show-full-path-titles true
    gsettings set org.nemo.list-view default-zoom-level standard
    # Para no bajar archivos de la nube solo por mirar una carpeta:
    gsettings set org.nemo.preferences show-directory-item-counts never
    gsettings set org.nemo.preferences show-image-thumbnails never
fi
nohup /usr/local/bin/onedrive-marcas-vivas >/dev/null 2>&1 &

echo
echo "Listo. OneDrive esta en ~/OneDrive. Boton derecho sobre una carpeta de ahi -> 'Mantener siempre en esta PC'."
