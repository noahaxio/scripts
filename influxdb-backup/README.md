# influxdb-backup

Backing up the local InfluxDB instance to the device's own GitHub repo.

| Script | What it does |
| --- | --- |
| `setup_influxdb_backup.sh` | One-time setup: prompts for the InfluxDB token and stores it at `/etc/axio-influx-token` as `root:debix` mode 640. |
| `backup_influxdb.sh` | Runs the backup: reads the token and `/etc/axio-device-name`, dumps InfluxDB, and pushes it to the `influxdb` branch of `git@github.com:noahaxio/<device-name>.git`. Run manually or from a cron entry — nothing here schedules it for you. |

Run `setup_influxdb_backup.sh` first — `backup_influxdb.sh` exits if the token
file is missing.
