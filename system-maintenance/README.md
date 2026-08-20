# system-maintenance

Housekeeping for the device itself — identity, permissions, and keeping this
Scripts repo current.

| Script | What it does |
| --- | --- |
| `update_all_scripts.sh` | Clones or force-updates this repo into `~/Scripts`, then makes every `.sh` executable and hands ownership back to the real user. Run with sudo. |
| `rename_debix.sh` | Renames the device end to end: prompts for a new name, then updates `/etc/axio-device-name`, `/etc/machine-info` (systemd-hostnamed), the Nginx `server_name`, and the Tailscale hostname. Run with sudo. |
| `fix_perms.sh` | Repairs ownership and executable bits across `~/Scripts`, `~/Renderers`, the browser autorun script, the autostart entry, and `~/.node-red`. Run with sudo. |
| `delete_unecessary_files.sh` | Removes unused home directories (Video, Videos, Music, Pictures, Templates). |
