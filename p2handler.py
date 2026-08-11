#!/usr/bin/env python3
from evdev import InputDevice, list_devices, ecodes
import os
import subprocess
import time

DEVICE_NAME = "GETAC MPMD programmable buttons"
DEBOUNCE_SECONDS = 2.0
COMMAND = os.environ.get("P2_COMMAND", "spectacle").split()

def find_device():
    while True:
        for path in list_devices():
            dev = InputDevice(path)
            if dev.name == DEVICE_NAME:
                return dev
        time.sleep(1)  # device not up yet (boot race) — keep waiting instead of crashing

dev = find_device()
last_trigger = 0
for event in dev.read_loop():
    if event.type == ecodes.EV_KEY and event.value == 1:
        now = time.monotonic()
        if now - last_trigger < DEBOUNCE_SECONDS:
            continue
        last_trigger = now
        subprocess.Popen(COMMAND)
