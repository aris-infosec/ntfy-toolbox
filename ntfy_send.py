#!/usr/bin/env python3
"""
ntfy sender with live system-info triggers.

Dependencies: pip install requests psutil
  (or on Arch: sudo pacman -S python-requests python-psutil)
Linux temp readings need lm-sensors: sudo pacman -S lm_sensors && sudo sensors-detect
Windows temp readings need LibreHardwareMonitor running with its web server on localhost:8085.

Usage (interactive):
    python3 ntfy_send.py

Usage (non-interactive, for cron/systemd/scripts):
    python3 ntfy_send.py --topic mytopic --trigger temp
    python3 ntfy_send.py --topic mytopic --message "custom text"
    NTFY_TOPIC=mytopic python3 ntfy_send.py --trigger disk
"""

import argparse
import os
import platform
import socket
import sys
import time

import requests

try:
    import psutil
except ImportError:
    psutil = None

NTFY_SERVER = os.environ.get("NTFY_SERVER", "https://ntfy.sh")
MAX_RETRIES = 3
RETRY_DELAY_SECONDS = 2


# ---------------------------------------------------------------------------
# System-info trigger functions
# ---------------------------------------------------------------------------

def get_temp():
    system = platform.system()
    if system == "Linux":
        if psutil is None:
            return "psutil not installed"
        temps = psutil.sensors_temperatures()
        if not temps:
            return "No sensors found (install/configure lm-sensors: sudo pacman -S lm_sensors && sudo sensors-detect)"
        lines = []
        for name, entries in temps.items():
            for e in entries:
                label = e.label or name
                lines.append(f"{label}: {e.current:.1f}°C")
        return "\n".join(lines)
    elif system == "Windows":
        try:
            r = requests.get("http://localhost:8085/data.json", timeout=2)
            data = r.json()

            def walk(node, out):
                if "temperature" in node.get("Text", "").lower() and "Value" in node:
                    out.append(f"{node['Text']}: {node['Value']}")
                for child in node.get("Children", []):
                    walk(child, out)
                return out

            results = walk(data, [])
            return "\n".join(results) if results else "No temp sensors reported"
        except Exception:
            return "Unavailable — install/run LibreHardwareMonitor with its web server enabled (localhost:8085)"
    else:
        return f"Temp reading not implemented for {system}"


def get_disk():
    if psutil is None:
        return "psutil not installed"
    usage = psutil.disk_usage("/" if platform.system() != "Windows" else "C:\\")
    return (f"Used: {usage.used / (1024**3):.1f} GB / {usage.total / (1024**3):.1f} GB "
            f"({usage.percent}% full, {usage.free / (1024**3):.1f} GB free)")


def get_cpu():
    if psutil is None:
        return "psutil not installed"
    return f"CPU load: {psutil.cpu_percent(interval=1)}%"


def get_ram():
    if psutil is None:
        return "psutil not installed"
    mem = psutil.virtual_memory()
    return f"RAM: {mem.percent}% used ({mem.used / (1024**3):.1f} GB / {mem.total / (1024**3):.1f} GB)"


def get_uptime():
    if psutil is None:
        return "psutil not installed"
    seconds = time.time() - psutil.boot_time()
    hours, rem = divmod(int(seconds), 3600)
    minutes, _ = divmod(rem, 60)
    return f"Uptime: {hours}h {minutes}m"


def get_battery():
    if psutil is None:
        return "psutil not installed"
    batt = psutil.sensors_battery()
    if batt is None:
        return "No battery detected (desktop?)"
    status = "charging" if batt.power_plugged else "on battery"
    return f"Battery: {batt.percent}% ({status})"


def get_ip():
    hostname = socket.gethostname()
    try:
        local_ip = socket.gethostbyname(hostname)
    except Exception:
        local_ip = "unknown"
    try:
        public_ip = requests.get("https://api.ipify.org", timeout=3).text
    except Exception:
        public_ip = "unreachable"
    return f"Host: {hostname}\nLocal IP: {local_ip}\nPublic IP: {public_ip}"


# Shortcut triggers: type/pass the keyword instead of a full message.
# "fn" triggers call a function to build the live message at send time.
TRIGGERS = {
    "temp":    {"title": "🌡️ Temperature", "priority": "default", "tags": "thermometer", "fn": get_temp},
    "disk":    {"title": "💽 Disk Space",   "priority": "default", "tags": "floppy_disk", "fn": get_disk},
    "cpu":     {"title": "⚙️ CPU Load",     "priority": "default", "tags": "gear",        "fn": get_cpu},
    "ram":     {"title": "🧠 RAM Usage",    "priority": "default", "tags": "brain",       "fn": get_ram},
    "uptime":  {"title": "⏱️ Uptime",       "priority": "low",     "tags": "clock3",      "fn": get_uptime},
    "battery": {"title": "🔋 Battery",      "priority": "default", "tags": "battery",     "fn": get_battery},
    "ip":      {"title": "🌐 IP Info",      "priority": "low",     "tags": "globe_with_meridians", "fn": get_ip},
    "done":    {"title": "✅ Done",         "priority": "default", "tags": "white_check_mark", "message": "Task finished successfully."},
    "error":   {"title": "🚨 Error",        "priority": "urgent",  "tags": "rotating_light",   "message": "Something went wrong!"},
    "build":   {"title": "🛠️ Build",        "priority": "default", "tags": "hammer_and_wrench","message": "Build finished."},
    "backup":  {"title": "💾 Backup",       "priority": "low",     "tags": "floppy_disk",      "message": "Backup completed."},
}


# ---------------------------------------------------------------------------
# Sending
# ---------------------------------------------------------------------------

def send_ntfy(topic, message, title=None, priority="default", tags=None,
              click=None, actions=None):
    """POST a message to ntfy, retrying a couple of times on network errors."""
    url = f"{NTFY_SERVER}/{topic}"
    headers = {}
    if title:
        headers["Title"] = title
    if priority:
        headers["Priority"] = priority
    if tags:
        headers["Tags"] = tags
    if click:
        headers["Click"] = click          # tapping the notification opens this URL
    if actions:
        headers["Actions"] = actions      # e.g. "view, Open Dashboard, https://example.com"

    last_error = None
    for attempt in range(1, MAX_RETRIES + 1):
        try:
            response = requests.post(url, data=message.encode("utf-8"), headers=headers, timeout=10)
            if response.status_code == 200:
                print(f"✅ Sent to '{topic}':\n{message}")
                return True
            last_error = f"HTTP {response.status_code}: {response.text}"
        except requests.RequestException as exc:
            last_error = str(exc)

        if attempt < MAX_RETRIES:
            print(f"⚠️  Attempt {attempt} failed ({last_error}), retrying in {RETRY_DELAY_SECONDS}s...")
            time.sleep(RETRY_DELAY_SECONDS)

    print(f"❌ Failed after {MAX_RETRIES} attempts: {last_error}")
    return False


# ---------------------------------------------------------------------------
# CLI / interactive entry point
# ---------------------------------------------------------------------------

def parse_args():
    parser = argparse.ArgumentParser(description="Send an ntfy notification, optionally with a live system-info trigger.")
    parser.add_argument("--topic", default=os.environ.get("NTFY_TOPIC"),
                         help="ntfy topic/channel name (or set NTFY_TOPIC env var)")
    parser.add_argument("--trigger", choices=sorted(TRIGGERS.keys()),
                         help="use a preset trigger instead of a custom message")
    parser.add_argument("--message", help="custom message text (ignored if --trigger is set)")
    parser.add_argument("--click", help="URL to open when the notification is tapped")
    return parser.parse_args()


def main():
    args = parse_args()

    topic = args.topic or input("Channel (topic) name: ").strip()
    if not topic:
        print("No topic given, aborting.")
        sys.exit(1)

    if args.trigger:
        key = args.trigger
    elif args.message:
        key = None
        user_input = args.message
    else:
        trigger_list = ", ".join(TRIGGERS.keys())
        user_input = input(f"Message (or trigger: {trigger_list}): ").strip()
        key = user_input.lower() if user_input.lower() in TRIGGERS else None

    if key:
        preset = TRIGGERS[key]
        message = preset["fn"]() if "fn" in preset else preset["message"]
        ok = send_ntfy(topic, message, preset["title"], preset["priority"], preset["tags"], click=args.click)
    else:
        ok = send_ntfy(topic, user_input, click=args.click)

    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
