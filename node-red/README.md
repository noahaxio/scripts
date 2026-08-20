# node-red

Node-RED runtime, its dashboard, and the chart/PDF renderers it calls out to.

| Script | What it does |
| --- | --- |
| `setup_npm_packages.sh` | Installs the canvas/cairo system dependencies and every npm package Node-RED needs, both in `~` and in `~/.node-red`, then fixes ownership. Run with sudo. |
| `update_renderers.sh` | Clones or force-updates `github.com/noahaxio/renderers` into `~/Renderers`, discarding local changes. Run with sudo. |
| `inject_updated_renderer_names.sh` | Registers the renderer scripts from `~/Renderers` in Node-RED's `settings.js` `functionGlobalContext`. Run with sudo after `update_renderers.sh`. |
| `disable_dashboard_offline_notification.sh` | Patches the Dashboard 2 service worker bundle to suppress the "offline ready" toast while keeping offline support working. |
