# remote-access

Getting into the device from outside: web authentication in front of the
dashboard, and a remote desktop session.

| Script | What it does |
| --- | --- |
| `authelia_setup.sh` | Installs Authelia + Nginx via Docker as the auth gateway for the dashboard. Reads the device name from `/etc/axio-device-name`. Run with sudo. |
| `authelia_change_password.sh` | Updates an existing user in `/opt/authelia/users_database.yml`: pick a user, change username / display name / email / password, regenerate the Argon2 hash and restart Authelia. Backs up the file first. Run with sudo, after `authelia_setup.sh`. |
| `setup_remote_desktop.sh` | Configures headless GNOME Remote Desktop (RDP) on Wayland, including TLS certificates and credentials. Run as the normal user, **not** with sudo. |
