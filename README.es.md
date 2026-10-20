# onedrive-linux-sync

OneDrive en Linux como lo hacen los clientes oficiales de Windows y macOS:

- **Archivos a demanda**: todo tu OneDrive aparece en `~/OneDrive`, y nada se descarga hasta que lo abrís.
- **«Mantener siempre en esta PC»** desde el botón derecho: la carpeta se baja de verdad y queda sincronizada **en los dos sentidos**.
- **Subidas al instante**: un archivo que guardás dentro de una carpeta fijada está en la nube en segundos.
- **Marcas de estado** en el explorador, como en Windows: tilde verde (está en esta PC), nube (solo en línea), flechas (sincronizando).
- **Una sola carpeta.** Las carpetas fijadas se montan encima de su lugar en `~/OneDrive`, así que no hay un segundo árbol «local».

Son unos pocos scripts de bash y unidades de systemd sobre [rclone](https://rclone.org). Sin demonio propio, sin base de datos, sin tocar archivos que no hayas fijado.

## Por qué

El cliente oficial de OneDrive no existe para Linux. Las alternativas habituales o descargan todo (clientes de sincronización completa) o dejan todo en la nube sin forma de decir «esta carpeta la quiero de verdad, y mantenela al día» (`rclone mount` pelado). Esto combina las dos cosas y agrega lo que más se extraña de Windows: la opción del botón derecho y los tildes verdes.

## Cómo funciona

Tres procesos separados, así ninguno traba a los otros:

| Proceso | Qué hace | Cuándo |
|---|---|---|
| `rclone mount` (`onedrive.service`) | Muestra la nube en `~/OneDrive`. Los archivos se bajan al abrirlos y quedan en caché en disco. | siempre |
| **Cola rápida** (`onedrive-cola.service`) | Vigila las carpetas fijadas con inotify. Cada archivo guardado es un «papelito» en una sala de espera; un repartidor los sube de a 4 con `rclone copyto`. Lo que falla se reintenta cada 15 s, así que trabajar sin internet no es problema. | siempre |
| **Revisión** (`onedrive-local.timer`) | `rclone bisync` sobre cada carpeta fijada, cada minuto. Baja lo que cambió en otro lado, resuelve conflictos (gana el más nuevo) y se recupera solo si una corrida abortó. | cada minuto |

Fijar una carpeta (`onedrive-local --fijar`) hace primero un `rclone sync` nube → disco, que compara y descarga a la vez (`bisync`, en cambio, lista todo antes de bajar nada), y después un `bisync --resync` para dejar armada la sincronización en los dos sentidos. Las descargas van de a una carpeta con 16 transferencias en paralelo y un tope de 12 pedidos por segundo: pasarse del cupo de Microsoft frena *todas* las descargas por minutos, así que quedarse justo debajo es más rápido que poner más hilos.

Las marcas son metadatos GIO (`metadata::emblems`), que Nemo y Thunar dibujan. Un pequeño demonio (`onedrive-marcas-vivas`) marca **solo la carpeta que tenés abierta**, así que recorrer un OneDrive de 100 000 archivos no cuesta nada.

## Requisitos

- Linux con systemd y sesión de usuario (probado en Ubuntu 26.04 con XFCE).
- **rclone ≥ 1.66** con un remoto llamado `onedrive` (`rclone config`, tipo `onedrive`).
- `fuse3`, `inotify-tools`, `xdotool`, `x11-utils`, `zenity`, `libnotify-bin`, `python3`.
- Un explorador que dibuje emblemas GIO: **Nemo** (recomendado) o **Thunar**. Nautilus no los dibuja.
- X11 (el demonio de marcas lee el título de la ventana activa con `xdotool`).

## El explorador de archivos

**Nemo** es el explorador recomendado: dibuja los emblemas GIO, tiene barra de ruta editable y pestañas, e `install.sh` lo deja configurado (ruta completa en el título de la ventana, íconos "standard" en la vista de lista —con íconos más chicos no muestra los emblemas— y sin conteo de elementos ni miniaturas, que bajarían archivos de la nube solo por mirar una carpeta). Son claves de `gsettings` normales; se pueden volver a cambiar cuando quieras.

**Thunar** también anda: las acciones van en `~/.config/Thunar/uca.xml` y el instalador pone la ruta completa en el título.

**Nautilus** (Archivos de GNOME) no dibuja emblemas: tenés las opciones del botón derecho pero no los tildes.

Emblemas usados: `emblem-default` (tilde verde), `emblem-web` (nube, solo en línea), `emblem-synchronizing` (flechas). Se ven bien con los temas de íconos Adwaita, Papirus y WhiteSur; otros temas pueden dibujarlos distinto.

## Instalación

```bash
git clone https://github.com/danoddo88/onedrive-linux-sync
cd onedrive-linux-sync
./install.sh
```

El instalador copia los scripts a `/usr/local`, activa las unidades de usuario, agrega las opciones del botón derecho para Nemo y/o Thunar, permite que tu usuario haga el montaje bind con sudo (lo único que necesita root) y activa *lingering* para que la sincronización siga sin sesión gráfica.

## Uso

Botón derecho sobre una carpeta dentro de `~/OneDrive`:

| Opción | Hace |
|---|---|
| **Mantener siempre en esta PC** | La baja y la mantiene sincronizada en los dos sentidos |
| **Sincronizar esta copia ahora** | Corre la revisión ya |
| **Dejar de guardar en esta PC** | Deja de sincronizar. Conserva la copia local y la de la nube |
| **Actualizar los tildes de estado** | Repinta todas las marcas |

Botón derecho sobre una carpeta **fuera** de OneDrive para subirla y mantenerla subida (un solo sentido, lo local manda, cada 10 minutos): **Mantener sincronizada con OneDrive**.

Lo mismo desde la terminal:

```bash
onedrive-local --fijar ~/OneDrive/proyectos/foo   # fijar
onedrive-local --lista                             # qué está fijado, y dónde
onedrive-local --ahora                             # sincronizar todo ya
onedrive-local --soltar ~/OneDrive/proyectos/foo  # soltar
onedrive-sincronizar --registrar ~/Imágenes        # subir una carpeta local y mantenerla
```

Los registros están en `~/.config/onedrive-sync/`.

## Ajustes

- `ONEDRIVE_HILOS` (16 por defecto): transferencias en paralelo al fijar una carpeta.
- `ONEDRIVE_TPS` (12 por defecto): tope de pedidos por segundo al fijar, para quedar debajo del cupo de Microsoft.
- `onedrive-local.timer`: cada cuánto se revisa (1 min por defecto).
- `onedrive.service`: opciones del montaje de rclone (`--vfs-cache-max-size`, `--dir-cache-time`, …).

## Reglas de seguridad

- **Siempre gana el más nuevo.** La revisión usa `--conflict-resolve newer`; la resincronización al fijar usa `--resync-mode newer` (por defecto rclone haría ganar a la copia *local*, que puede pisar en silencio cambios hechos en otro lado entre la descarga y la resincronización). La cola rápida sube con `--update`, así que nunca reemplaza un archivo de la nube más nuevo que el local.
- **Lo borrado en otro lado mientras se bajaba no resucita.** El primer paso al fijar deja el disco igual a la nube (`rclone sync`, no `copy`): un archivo que se borra desde otro dispositivo a mitad de la descarga no se queda en esta PC para que la resincronización lo vuelva a subir. Tampoco se borra: se aparta a `~/.local/share/onedrive-sync/apartados/<carpeta>/<fecha>`, fuera de OneDrive. Lo que esta PC tiene más nuevo se conserva (`--update`) y sube.
- Fijar una carpeta nunca borra nada en la nube. El modo «mantener subida» de un solo sentido mueve lo reemplazado o borrado a `_reemplazados-<máquina>/` en vez de borrarlo.
- OneDrive guarda historial de versiones por archivo; si algo sale mal, ahí está la vuelta atrás.

## Lo que no es

- **No es instantáneo desde la nube.** Un cambio hecho en otro dispositivo llega a la carpeta fijada en la próxima revisión (≤ 1 min). Linux → nube es cuestión de segundos.
- **No reemplaza a un cliente real en árboles enormes de archivos chicos.** Cada archivo es un pedido a Microsoft; un `node_modules` de 40 000 archivos tarda, se haga lo que se haga.
- **Soltar una carpeta no borra nada en la nube.** La sincronización en dos sentidos *sí* propaga los borrados que hagas vos, como cualquier sincronización.

## Desinstalar

```bash
./uninstall.sh
```

Conserva `~/.onedrive-local` (tus copias locales) y `~/.config/onedrive-sync` (listas y registros).

## Licencia

MIT.
