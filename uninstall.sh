#!/bin/bash
# Quita onedrive-linux-sync. NO borra ~/.onedrive-local (tus copias locales)
# ni ~/.config/onedrive-sync (la lista de carpetas y los registros).
set -u
systemctl --user disable --now onedrive-local.timer onedrive-sync.timer onedrive-delta.service onedrive-cola.service onedrive.service 2>/dev/null
for p in $(pgrep -x onedrive-marcas 2>/dev/null); do kill "$p"; done
rm -f ~/.config/systemd/user/onedrive{,-cola,-delta,-local,-sync}.{service,timer} ~/.config/autostart/onedrive-marcas-vivas.desktop
rm -f ~/.local/share/nemo/actions/*onedrive*.nemo_action
systemctl --user daemon-reload
sudo rm -f /usr/local/bin/onedrive-{local,cola,delta,subir-uno,tildes,marcas-vivas,sincronizar} /usr/local/sbin/onedrive-bind /etc/sudoers.d/onedrive-bind
echo "Quitado. Quedan ~/.onedrive-local y ~/.config/onedrive-sync por si los queres."
