# integrations

Third-party hardware and service integrations that feed data into the device.

| Script | What it does |
| --- | --- |
| `setup_sienergy2mqtt.sh` | Installs or updates the Sigenergy inverter → MQTT bridge as a Docker Compose stack under `~/sigenergy-mqtt`. Re-running it against an existing install performs an update. Requires Docker; run with sudo. |
