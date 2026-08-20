# Axio Debix Scripts

Provisioning and maintenance scripts for Axio Debix devices.

`setup_debix.sh` stays at the top level: it is the full first-boot provisioning
script that turns a fresh Debix image into a working kiosk device. Everything
else is grouped by area below and is meant to be run afterwards, on a device
that has already been set up.

| Folder | Contents |
| --- | --- |
| [`kiosk-display/`](kiosk-display/) | Chromium kiosk service and GNOME desktop tweaks — watchdog updates, nightly restart, overview/zoom fixes. |
| [`node-red/`](node-red/) | Node-RED packages, dashboard patches, and the chart/PDF renderers in `~/Renderers`. |
| [`influxdb-backup/`](influxdb-backup/) | InfluxDB token setup and the scheduled backup that pushes to the device's GitHub repo. |
| [`remote-access/`](remote-access/) | Authelia auth gateway, its user management, and headless GNOME Remote Desktop (RDP). |
| [`integrations/`](integrations/) | Third-party device integrations — currently the Sigenergy → MQTT bridge. |
| [`system-maintenance/`](system-maintenance/) | Device rename, permission repair, cleanup, and updating this repo on the device. |

`TODO_gnome_kiosk.txt` tracks the planned move from full GNOME Shell to the
`gnome-kiosk` compositor; it sits next to `setup_debix.sh` because it refers to
that script's sections directly.

Each folder has its own README describing what every script does and whether it
needs sudo.
