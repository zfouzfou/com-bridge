#!/usr/bin/env python3
"""
COM TCP Bridge -- Windows side
Expose a COM port over TCP, allowing simultaneous access from Windows and WSL.
Supports hotplug: auto-reconnect when the COM port is re-plugged.

Usage:  python com_bridge.py [COM_PORT] [BAUD] [TCP_PORT]
Default: COM4  115200  12345
Depends: pyserial (pip install pyserial)
"""

import sys
import socket
import threading
import time
import logging

try:
    import serial
except ImportError:
    print("Requires pyserial: pip install pyserial")
    sys.exit(1)

# ── Config ───────────────────────────────────────
COM_PORT = "COM4"
BAUD = 115200
TCP_PORT = 12345

if len(sys.argv) > 1:
    COM_PORT = sys.argv[1].upper()
if len(sys.argv) > 2 and sys.argv[2].isdigit():
    BAUD = int(sys.argv[2])
if len(sys.argv) > 3 and sys.argv[3].isdigit():
    TCP_PORT = int(sys.argv[3])

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("bridge")


# ── Bridge class ─────────────────────────────────

class ComBridge:
    """COM <-> TCP bridge with multi-client support and hotplug detection."""

    def __init__(self):
        self.ser: serial.Serial | None = None
        self.server: socket.socket | None = None
        self.clients: dict[int, socket.socket] = {}
        self.client_lock = threading.Lock()
        self.running = True
        self._next_id = 0
        self._com_ok = False

    # ── COM port management ────────────────

    def open_com(self) -> bool:
        try:
            if self.ser and self.ser.is_open:
                return True
            self.ser = serial.Serial(
                port=COM_PORT, baudrate=BAUD,
                bytesize=serial.EIGHTBITS, parity=serial.PARITY_NONE,
                stopbits=serial.STOPBITS_ONE, timeout=0.01, write_timeout=2,
            )
            self._com_ok = True
            log.info(f"Opened {COM_PORT} @ {BAUD} baud")
            return True
        except serial.SerialException as e:
            self.ser = None
            self._com_ok = False
            log.debug(f"{COM_PORT} unavailable: {e}")
            return False

    def close_com(self):
        if self.ser and self.ser.is_open:
            try:
                self.ser.close()
            except Exception:
                pass
            log.info(f"Closed {COM_PORT}")
        self.ser = None
        self._com_ok = False

    def write_com(self, data: bytes) -> bool:
        if not self.ser or not self.ser.is_open:
            return False
        try:
            self.ser.write(data)
            return True
        except serial.SerialException:
            self._com_ok = False
            return False

    def read_com(self) -> bytes:
        if not self.ser or not self.ser.is_open:
            return b""
        try:
            return self.ser.read(4096)
        except serial.SerialException:
            self._com_ok = False
            return b""

    def monitor_com(self):
        """Background thread: detect COM disconnect, auto-reconnect."""
        while self.running:
            if self.ser and self.ser.is_open:
                if self._com_ok:
                    time.sleep(2)
                    continue
                log.warning(f"{COM_PORT} unhealthy, reconnecting...")
                self.close_com()
                self.disconnect_all()
            else:
                if self.open_com():
                    log.info(f"{COM_PORT} reconnected")
                else:
                    time.sleep(2)
        self.close_com()

    # ── TCP client management ──────────────

    def start_server(self):
        self.server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.server.bind(("0.0.0.0", TCP_PORT))
        self.server.listen(5)
        self.server.settimeout(1.0)
        log.info(f"TCP listening on port {TCP_PORT}")

        while self.running:
            try:
                client, addr = self.server.accept()
                client.settimeout(5.0)
                cid = self._next_id
                self._next_id += 1
                with self.client_lock:
                    self.clients[cid] = client
                log.info(f"Client [{cid}] connected: {addr[0]}:{addr[1]}")
                threading.Thread(target=self._handle_client, args=(cid,), daemon=True).start()
            except socket.timeout:
                continue
            except OSError:
                break

    def _handle_client(self, cid: int):
        client = self.clients.get(cid)
        if not client:
            return
        try:
            while self.running:
                try:
                    chunk = client.recv(4096)
                except socket.timeout:
                    continue
                if not chunk:
                    break
                if not self.write_com(chunk):
                    break
        except (ConnectionResetError, ConnectionAbortedError, OSError):
            pass
        finally:
            self._remove_client(cid)

    def _remove_client(self, cid: int):
        with self.client_lock:
            client = self.clients.pop(cid, None)
        if client:
            try:
                client.close()
            except OSError:
                pass

    def disconnect_all(self):
        with self.client_lock:
            for cid in list(self.clients.keys()):
                self._remove_client(cid)

    def _broadcast(self, data: bytes):
        dead = []
        with self.client_lock:
            for cid, client in list(self.clients.items()):
                try:
                    client.sendall(data)
                except (OSError, BrokenPipeError):
                    dead.append(cid)
        for cid in dead:
            self._remove_client(cid)

    def com_reader(self):
        """Background thread: read from COM, broadcast to all TCP clients."""
        while self.running:
            if self.ser and self.ser.is_open and self._com_ok:
                data = self.read_com()
                if data:
                    self._broadcast(data)
                else:
                    time.sleep(0.01)
            else:
                time.sleep(0.1)

    # ── Main loop ──────────────────────────

    def run(self):
        print(f"\n=== COM Bridge ===")
        print(f"  {COM_PORT} @ {BAUD} -> TCP :{TCP_PORT}")
        print(f"  Stop: Ctrl+C\n")

        self.open_com()
        threading.Thread(target=self.monitor_com, daemon=True, name="monitor").start()
        threading.Thread(target=self.com_reader, daemon=True, name="reader").start()

        try:
            self.start_server()
        except KeyboardInterrupt:
            log.info("Stopped by user")
        finally:
            self.running = False
            self.close_com()
            self.disconnect_all()
            if self.server:
                self.server.close()
            log.info("Shutdown complete")


if __name__ == "__main__":
    ComBridge().run()