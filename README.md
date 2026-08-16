# COM Bridge

Share a single Windows COM port between Windows and WSL / Linux VMs **simultaneously**, with hotplug detection. No drivers, no virtual COM port software, no Windows configuration changes.

```
┌──────────────┐   TCP:12345   ┌──────────────┐   /dev/ttyVIRTUAL   ┌─────────┐
│  PuTTY Raw   │◄─────────────►│   COM Bridge  │◄───────────────────►│  WSL /  │
│  (Windows)   │   (multi-     │   (Python)    │      (socat)        │  Linux  │
└──────────────┘    client)    └──────┬───────┘                     │   VM    │
                                      │ COM4                         └─────────┘
                                      ▼
                                 ┌──────────┐
                                 │  Device  │
                                 └──────────┘
```

The bridge opens the real COM port on Windows and exposes it as a raw TCP server. Any number of clients can connect at once — Windows tools (PuTTY, custom apps) via `localhost:12345`, and Linux (WSL/VM) via a socat-created virtual tty. All clients see the device output; any client input reaches the device.

## Why this approach?

| | **COM Bridge** | com0com / virtual COM port drivers |
|---|---|---|
| Driver installation | ❌ None | ✅ Required (modifies system) |
| Windows config changes | ❌ None | ✅ Yes |
| Simultaneous access | ✅ Any number of clients | ⚠️ Usually one app |
| Hotplug detection | ✅ Auto-reconnect | ⚠️ Often manual |
| Portability | Copy folder, done | Reinstall per machine |

## Features

- **Simultaneous access** — broadcast to all TCP clients, input from any client
- **Hotplug detection** — unplug the USB serial adapter and the bridge auto-detects, reconnects when re-plugged (no restart)
- **Portable** — single folder, works on any PC with Python 3 + pyserial installed
- **No drivers** — pure user-space TCP bridge
- **Multi-platform clients** — PuTTY, netcat, socat, WSL, VMware VMs, anything that speaks TCP

## Requirements

- **Windows**: Python 3.x + pyserial (`com_bridge_win_setup.bat` installs both automatically)
- **Linux (WSL/VM)**: socat (`com_bridge_linux_client.sh install` installs it automatically)

## Quick Start

### 1. Windows — install & start the bridge

```bat
com_bridge_win_setup.bat           REM installs Python 3 + pyserial (first run only)
com_bridge_win_server.bat          REM starts bridge: COM4 @ 115200 -> TCP :12345
```

Custom port/baud/port number:

```bat
com_bridge_win_server.bat COM5 9600 12346
```

### 2. Connect from Windows — PuTTY (recommended)

```
PuTTY:
  Connection type: Raw
  Host: localhost
  Port: 12345
  Terminal → Line discipline:
      Local echo: Force off
      Local line editing: Force off
  Save Session: com-bridge
```

> The **Line discipline** setting is important: with it enabled PuTTY intercepts keys (e.g. Tab) for local line editing instead of passing them through raw.

Or raw-connect with anything else: `nc localhost 12345`, Python `socket`, etc.

### 3. Connect from WSL / Linux VM

```bash
sudo ./com_bridge_linux_client.sh install   # installs socat (first run only)
sudo ./com_bridge_linux_client.sh start     # creates /dev/ttyVIRTUAL
picocom -b 115200 /dev/ttyVIRTUAL           # or minicom -D /dev/ttyVIRTUAL
```

The client script auto-detects the Windows host IP on WSL2 (NAT/Host-only VMware too). For **VMware bridged mode**, point it manually:

```bash
export WINDOWS_HOST=192.168.1.100
sudo ./com_bridge_linux_client.sh start
```

Status / stop:

```bash
sudo ./com_bridge_linux_client.sh status
sudo ./com_bridge_linux_client.sh stop
```

## Usage Notes

- Start the Windows bridge **before** plugging the device — it waits and reconnects automatically when the COM port appears.
- All clients receive the same data; when two clients type at once, input is mixed (same as two humans on one keyboard — inherent to shared serial).
- The first time on a new PC, if Windows Firewall prompts — allow it. On **VMware** you must add an inbound rule for TCP 12345 (WSL2 is exempt via its virtual network):

```powershell
New-NetFirewallRule -DisplayName "COM Bridge" -Direction Inbound -Protocol TCP -LocalPort 12345 -Action Allow
```

## How the hotplug detection works

The bridge tracks a health flag on every serial read/write. On failure it closes the COM port, disconnects all clients (so they don't hold stale connections), and retries every 2 seconds. When the device is re-plugged, the bridge reopens the port automatically.

## Files

| File | Purpose |
|------|---------|
| `com_bridge.py` | The bridge itself (Windows side) |
| `com_bridge_win_server.bat` | Windows launcher (finds Python, installs pyserial if missing) |
| `com_bridge_win_setup.bat` | One-click Windows dependency installer |
| `com_bridge_linux_client.sh` | Linux/WSL client — creates `/dev/ttyVIRTUAL` via socat |
| `README.md` | This file |

## License

[MIT](LICENSE)
