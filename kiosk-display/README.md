# kiosk-display

Everything that controls the Chromium kiosk browser and the GNOME desktop it
runs on. `setup_debix.sh` creates the kiosk service initially; these scripts
patch, restart or tweak it afterwards on an already-provisioned device.

| Script | What it does |
| --- | --- |
| `add_reload_conjob.sh` | Installs cron and adds a 3 AM user crontab entry that restarts `kiosk.service` daily. Run as the normal user, **not** with sudo. |
| `add_restart_desktop_command.sh` | Adds a `restartdesktop` alias (`sudo systemctl restart gdm`) to the user's `~/.bashrc`. |
| `fix_desktop_zoom.sh` | Installs the `no-overview@fthx` GNOME extension so a swipe/hot-corner can't drop the kiosk into the Activities overview. Run as the normal user. |
| `fix_kiosk_watchdog.sh` | Rewrites the user-level `kiosk.service` watchdog unit and reloads it. Run as the normal user. |
| `update_kiosk_service.sh` | Same patch applied with sudo on behalf of the `debix` user — makes the unit display-aware so it can't crash-loop when headless. |

See `../TODO_gnome_kiosk.txt` for the planned migration to the `gnome-kiosk`
compositor, which would retire most of the workarounds here.
