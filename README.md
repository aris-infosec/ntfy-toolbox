# ntfy-toolbox

![license](https://img.shields.io/badge/license-MIT-blue.svg)
![python](https://img.shields.io/badge/python-3.8%2B-blue.svg)
![platforms](https://img.shields.io/badge/platforms-Linux%20%7C%20Arch%20%7C%20Windows-lightgrey.svg)

Copy-paste scripts (Python, Bash, PowerShell) to send [ntfy](https://ntfy.sh) push notifications with live system triggers — temp, disk, CPU, RAM, uptime, battery, IP. Works on Linux, Arch, and Windows.

## Table of Contents

- [Quickstart](#quickstart)
- [How ntfy works](#how-ntfy-works-quick-version)
- [Dependencies](#dependencies--what-you-need-to-install)
- [Script 1: Python](#script-1-python-linux--arch--windows)
- [Script 2: Bash](#script-2-bash-linux--arch)
- [Script 3: PowerShell](#script-3-powershell--for-windows-terminal-users)
- [Trigger reference](#trigger-reference)
- [Automating it (cron / systemd)](#automating-it-cron--systemd)
- [Click actions & buttons](#click-actions--buttons)
- [Contributing](#contributing)
- [License](#license)

---

## Quickstart

```bash
git clone https://github.com/yourname/ntfy-toolbox.git
cd ntfy-toolbox

# Python
pip install -r requirements.txt
python3 ntfy_send.py --topic mytopic --trigger temp

# or Bash (Linux/Arch, no install needed)
chmod +x ntfy_send.sh
./ntfy_send.sh --topic mytopic --trigger disk
```

Then subscribe to `mytopic` in the [ntfy app](https://ntfy.sh) or at `https://ntfy.sh/mytopic` to receive it.

---

## How ntfy works (quick version)

1. Pick any topic name, e.g. `my-arch-alerts-83hd` (make it hard to guess — topics are public unless you self-host or use auth).
2. Subscribe to it:
   - Phone: install the ntfy app → add subscription → enter topic name
   - Desktop/browser: go to `https://ntfy.sh/my-arch-alerts-83hd`
3. Send a message:
   ```bash
   curl -d "Hello from my script" ntfy.sh/my-arch-alerts-83hd
   ```
   That's it — it arrives on every subscribed device instantly.

### Self-hosting / privacy note

The public `ntfy.sh` server is unauthenticated by default — anyone who knows/guesses the topic name can read or post to it. For anything sensitive, use a long random topic name, or self-host (`docker run -p 80:80 binwiederhier/ntfy serve`) and set `NTFY_SERVER` (see below) to your own server.

---

## Dependencies — what you need to install

### Python script (cross-platform: Linux, Arch, Windows)

Everything is pinned in [`requirements.txt`](./requirements.txt):

```bash
pip install -r requirements.txt
```

| Package    | Purpose                                              |
|------------|--------------------------------------------------------|
| `requests` | send the HTTP POST to ntfy                              |
| `psutil`   | CPU / RAM / disk / uptime / battery, cross-platform      |

**Arch Linux (recommended, via pacman instead of pip):**
```bash
sudo pacman -S python-requests python-psutil
```

### Temperature sensors — the tricky one

`psutil.sensors_temperatures()` only works on **Linux**, and even there it just reads what `lm-sensors` exposes.

**Arch Linux:**
```bash
sudo pacman -S lm_sensors
sudo sensors-detect   # answer YES to the prompts, safe defaults are fine
sensors               # test it — should print CPU/board temps
```

**Debian/Ubuntu:**
```bash
sudo apt install lm-sensors
sudo sensors-detect
```

**Windows:**
There's no built-in equivalent to `lm-sensors`, and `psutil` cannot read temperatures on Windows at all. Realistic options:
- Install **[LibreHardwareMonitor](https://github.com/LibreHardwareMonitor/LibreHardwareMonitor)** (maintained fork of OpenHardwareMonitor), run it, enable "Remote Web Server" in Options, and the scripts here will read `http://localhost:8085/data.json`.
- Or use the `wmi` Python package (`pip install wmi`) with LibreHardwareMonitor running, exposing sensors over WMI (`root\LibreHardwareMonitor`).

### Bash script (Linux / Arch only — Bash isn't native on Windows)

| Package      | Purpose        | Arch install |
|--------------|----------------|--------------|
| `curl`       | send to ntfy   | preinstalled on almost every Arch system |
| `lm_sensors` | `temp` trigger | `sudo pacman -S lm_sensors && sudo sensors-detect` |
| `acpi`       | `battery` trigger (laptops) | `sudo pacman -S acpi` |
| `coreutils`  | `df`, `free`, `uptime` | preinstalled by default |

If you're on Windows and want a terminal-native option instead of Python, use **PowerShell** (`ntfy_send.ps1`).

---

## Script 1: Python (Linux / Arch / Windows)

[`ntfy_send.py`](./ntfy_send.py) — full source in this repo. Highlights:

- **Interactive mode**: just run it, it asks for topic + message/trigger.
- **CLI mode** for automation:
  ```bash
  python3 ntfy_send.py --topic mytopic --trigger temp
  python3 ntfy_send.py --topic mytopic --message "custom text"
  python3 ntfy_send.py --topic mytopic --trigger error --click "https://example.com/logs"
  ```
- **Env vars** so you don't retype the topic every time:
  ```bash
  export NTFY_TOPIC=mytopic
  export NTFY_SERVER=https://ntfy.sh   # or your self-hosted server
  python3 ntfy_send.py --trigger disk
  ```
- **Retries**: failed sends are retried automatically (3 attempts, 2s apart) before giving up, so a brief network blip doesn't silently drop a notification.
- **Triggers**: `temp`, `disk`, `cpu`, `ram`, `uptime`, `battery`, `ip` (all live system data), plus static ones — `done`, `error`, `build`, `backup`.

Run it with `-h` for the full option list.

---

## Script 2: Bash (Linux / Arch)

[`ntfy_send.sh`](./ntfy_send.sh) — same feature set as the Python version (CLI args, env vars, retries), but only needs `curl` — nothing to install on a stock Arch system.

```bash
chmod +x ntfy_send.sh
./ntfy_send.sh                                   # interactive
./ntfy_send.sh --topic mytopic --trigger cpu      # scriptable
NTFY_TOPIC=mytopic ./ntfy_send.sh --trigger disk  # via env var
```

---

## Script 3: PowerShell — for Windows terminal users

[`ntfy_send.ps1`](./ntfy_send.ps1). Covers `disk`, `ram`, `uptime` natively; `temp` needs LibreHardwareMonitor's web server (see Dependencies) running on `localhost:8085`.

```powershell
.\ntfy_send.ps1
.\ntfy_send.ps1 -Topic mytopic -Trigger disk
.\ntfy_send.ps1 -Topic mytopic -Message "custom text"
```

---

## Trigger reference

| Trigger    | What it sends                              | Linux/Arch                     | Windows |
|------------|---------------------------------------------|---------------------------------|---------|
| `temp`     | Live sensor temperatures                     | `lm_sensors`                    | LibreHardwareMonitor + web server |
| `disk`     | Disk usage of root/C: drive                  | built-in (`df`) / psutil        | built-in (psutil / PowerShell) |
| `cpu`      | Current CPU load %                           | `top` / psutil                  | psutil (Python only) |
| `ram`      | RAM used vs total                            | `free` / psutil                 | built-in / psutil |
| `uptime`   | System uptime                                | `uptime` / psutil                | built-in / psutil |
| `battery`  | Battery % and charging status                | `acpi` / psutil                  | psutil |
| `ip`       | Hostname, local IP, public IP                | built-in + `curl`                | built-in + `Invoke-RestMethod` |
| `done`     | Static "task finished" message               | —                                | — |
| `error`    | Static urgent error message                  | —                                | — |
| `build`    | Static "build finished" message              | —                                | — |
| `backup`   | Static "backup completed" message            | —                                | — |

Add more triggers by copying the pattern in `ntfy_send.py` / `ntfy_send.sh` — e.g. a `login` trigger reading `/var/log/auth.log`, or a `ping <host>` trigger.

---

## Automating it (cron / systemd)

Once you're happy with a trigger interactively, wire it up so it fires on its own — no prompts, fully non-interactive via the CLI flags above.

**Cron (e.g. temp check every hour):**
```cron
0 * * * * NTFY_TOPIC=mytopic /usr/bin/python3 /path/to/ntfy_send.py --trigger temp
```

**systemd timer (Arch-friendly alternative to cron):**

`/etc/systemd/system/ntfy-temp.service`
```ini
[Unit]
Description=Send ntfy temperature check

[Service]
Type=oneshot
Environment=NTFY_TOPIC=mytopic
ExecStart=/usr/bin/python3 /path/to/ntfy_send.py --trigger temp
```

`/etc/systemd/system/ntfy-temp.timer`
```ini
[Unit]
Description=Run ntfy temperature check hourly

[Timer]
OnCalendar=hourly
Persistent=true

[Install]
WantedBy=timers.target
```

Enable it:
```bash
sudo systemctl enable --now ntfy-temp.timer
```

**Pacman hook (notify on every system update):**

`/etc/pacman.d/hooks/ntfy-update.hook`
```ini
[Trigger]
Operation = Upgrade
Type = Package
Target = *

[Action]
Description = Sending ntfy notification for system update
When = PostTransaction
Exec = /usr/bin/bash -c 'NTFY_TOPIC=mytopic /path/to/ntfy_send.sh --trigger done'
```

---

## Click actions & buttons

ntfy notifications can do more than just show text — two useful headers, already wired up in these scripts via `--click`:

- **`Click`**: tapping the notification opens a URL (e.g. link straight to a dashboard, log file, or Grafana panel).
  ```bash
  python3 ntfy_send.py --topic mytopic --trigger error --click "https://mydashboard.example.com/logs"
  ```
- **`Actions`**: adds actual button(s) to the notification (e.g. "Open Dashboard", "Acknowledge"). Not exposed as a flag here to keep the scripts simple, but you can add it the same way `Click` is added — see the [ntfy docs on actions](https://docs.ntfy.sh/publish/#action-buttons) for the header format.

---

## Contributing

PRs adding new triggers are welcome. To add one:

1. Write a `get_x()` function that returns a string (Python/Bash/PowerShell — ideally all three for consistency).
2. Register it in the `TRIGGERS` dict/case-statement with a title, priority, and an [emoji tag](https://docs.ntfy.sh/emojis/).
3. Add a row to the [Trigger reference](#trigger-reference) table.

## License

[MIT](./LICENSE) — do whatever you want with it.
