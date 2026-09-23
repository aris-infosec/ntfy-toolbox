#!/usr/bin/env bash
# ntfy sender with live system-info triggers (Linux/Arch).
#
# Dependencies: curl (preinstalled almost everywhere)
#   sudo pacman -S lm_sensors && sudo sensors-detect   # for `temp`
#   sudo pacman -S acpi                                # for `battery` (laptops)
#
# Usage (interactive):
#   ./ntfy_send.sh
#
# Usage (non-interactive, for cron/systemd):
#   ./ntfy_send.sh --topic mytopic --trigger temp
#   ./ntfy_send.sh --topic mytopic --message "custom text"
#   NTFY_TOPIC=mytopic ./ntfy_send.sh --trigger disk

set -euo pipefail

NTFY_SERVER="${NTFY_SERVER:-https://ntfy.sh}"
MAX_RETRIES=3
RETRY_DELAY=2

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
topic="${NTFY_TOPIC:-}"
trigger=""
message=""
click_url=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --topic) topic="$2"; shift 2 ;;
        --trigger) trigger="$2"; shift 2 ;;
        --message) message="$2"; shift 2 ;;
        --click) click_url="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: $0 [--topic NAME] [--trigger KEY] [--message TEXT] [--click URL]"
            exit 0 ;;
        *) echo "Unknown argument: $1"; exit 1 ;;
    esac
done

# ---------------------------------------------------------------------------
# Sending (with retries)
# ---------------------------------------------------------------------------
send_ntfy() {
    local topic="$1" message="$2" title="$3" priority="${4:-default}" tags="$5" click="${6:-}"
    local attempt=1

    local -a headers=(-H "Title: ${title}" -H "Priority: ${priority}" -H "Tags: ${tags}")
    [[ -n "$click" ]] && headers+=(-H "Click: ${click}")

    while (( attempt <= MAX_RETRIES )); do
        if curl -sf "${headers[@]}" -d "${message}" "${NTFY_SERVER}/${topic}" > /dev/null; then
            echo "✅ Sent to '${topic}':"
            echo "${message}"
            return 0
        fi
        echo "⚠️  Attempt ${attempt} failed, retrying in ${RETRY_DELAY}s..." >&2
        sleep "$RETRY_DELAY"
        ((attempt++))
    done

    echo "❌ Failed to send after ${MAX_RETRIES} attempts." >&2
    return 1
}

# ---------------------------------------------------------------------------
# System-info trigger functions
# ---------------------------------------------------------------------------
get_temp() {
    if command -v sensors &>/dev/null; then
        sensors | grep -E "°C" | sed 's/  */ /g'
    else
        echo "lm-sensors not installed. Run: sudo pacman -S lm_sensors && sudo sensors-detect"
    fi
}

get_disk() {
    df -h / | awk 'NR==2 {print "Used: "$3" / "$2" ("$5" full, "$4" free)"}'
}

get_cpu() {
    top -bn1 | grep "Cpu(s)" | awk '{print "CPU load: "$2"%"}'
}

get_ram() {
    free -h | awk 'NR==2 {print "RAM: "$3" / "$2" used"}'
}

get_uptime() {
    uptime -p
}

get_battery() {
    if command -v acpi &>/dev/null; then
        acpi -b
    else
        echo "acpi not installed (sudo pacman -S acpi), or no battery present"
    fi
}

get_ip() {
    local local_ip public_ip
    local_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    public_ip=$(curl -s https://api.ipify.org)
    echo -e "Host: $(hostname)\nLocal IP: ${local_ip:-unknown}\nPublic IP: ${public_ip:-unreachable}"
}

run_trigger() {
    case "$1" in
        temp)    send_ntfy "$topic" "$(get_temp)"    "🌡️ Temperature" "default" "thermometer" "$click_url" ;;
        disk)    send_ntfy "$topic" "$(get_disk)"    "💽 Disk Space"  "default" "floppy_disk" "$click_url" ;;
        cpu)     send_ntfy "$topic" "$(get_cpu)"     "⚙️ CPU Load"    "default" "gear" "$click_url" ;;
        ram)     send_ntfy "$topic" "$(get_ram)"     "🧠 RAM Usage"   "default" "brain" "$click_url" ;;
        uptime)  send_ntfy "$topic" "$(get_uptime)"  "⏱️ Uptime"      "low"     "clock3" "$click_url" ;;
        battery) send_ntfy "$topic" "$(get_battery)" "🔋 Battery"     "default" "battery" "$click_url" ;;
        ip)      send_ntfy "$topic" "$(get_ip)"      "🌐 IP Info"     "low"     "globe_with_meridians" "$click_url" ;;
        done)    send_ntfy "$topic" "Task finished successfully." "✅ Done"  "default" "white_check_mark" "$click_url" ;;
        error)   send_ntfy "$topic" "Something went wrong!"       "🚨 Error" "urgent"  "rotating_light" "$click_url" ;;
        build)   send_ntfy "$topic" "Build finished."             "🛠️ Build" "default" "hammer_and_wrench" "$click_url" ;;
        backup)  send_ntfy "$topic" "Backup completed."           "💾 Backup" "low"    "floppy_disk" "$click_url" ;;
        *) echo "Unknown trigger: $1"; exit 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# Interactive fallback if --topic/--trigger/--message weren't passed
# ---------------------------------------------------------------------------
if [[ -z "$topic" ]]; then
    read -rp "Channel (topic) name: " topic
    [[ -z "$topic" ]] && { echo "No topic given, aborting."; exit 1; }
fi

if [[ -n "$trigger" ]]; then
    run_trigger "$trigger"
elif [[ -n "$message" ]]; then
    send_ntfy "$topic" "$message" "" "default" "" "$click_url"
else
    read -rp "Message (or trigger: temp, disk, cpu, ram, uptime, battery, ip, done, error, build, backup): " input
    if [[ "$input" =~ ^(temp|disk|cpu|ram|uptime|battery|ip|done|error|build|backup)$ ]]; then
        run_trigger "$input"
    else
        send_ntfy "$topic" "$input" "" "default" "" "$click_url"
    fi
fi
