# getac-mpmd

[![License: GPL v2](https://img.shields.io/badge/License-GPLv2-blue.svg)](LICENSE)

Linux driver + installer that makes the programmable buttons on GETAC rugged
laptops (P1/P2/etc.) work as real input events, and wires the P2 button to
launch a screenshot tool.

GETAC laptops expose these buttons through an ACPI device named `MPMD`
(hardware ID `MTC0303`). The embedded controller raises `Notify(MPMD, code)`
on button activity, but with no driver bound to `MTC0303` these notifies are
silently dropped — the buttons appear dead under Linux. `getac-mpmd.c` binds
that device and forwards the notifies as `KEY_PROG1` input events via a
sparse keymap.

The ACPI notify code for the same physical P2 button differs per model:

| Model | Notify code | BIOS tested |
|-------|-------------|-------------|
| S410  | `0x97`      | R1.25.070520 |
| B360  | `0x92`      | — |

If your model isn't listed, `install.sh` still installs the driver — press
the button, check `dmesg \| grep getac_mpmd` for a line like
`unknown notify event 0xNN`, add `{ KE_KEY, 0xNN, { KEY_PROG1 } }` to
`getac_mpmd_keymap` in `getac-mpmd.c`, and re-run the script. PRs welcome for
other models.

Origin: this driver started from an unmerged `platform/x86` patch posted to
the LKML `platform-driver-x86` list by chubukou <chubukou@gmail.com>
(`upstream/0001-platform-x86-add-getac-mpmd-driver.patch`), extended here
with the B360 notify code and a screenshot-launcher handler.

## What `install.sh` sets up

1. Kernel headers + DKMS, so the module rebuilds itself on every future
   kernel upgrade instead of silently going stale.
2. The `getac_mpmd` module, loaded now and on every boot.
3. A udev rule granting the active seat user direct access to the button's
   input device (no group membership or re-login required).
4. `p2handler.py` — a small daemon that watches for `KEY_PROG1` presses
   (debounced, since the EC repeats the notify at ~3 Hz while held) and
   launches a screenshot command — installed as a per-user systemd service
   that starts on login.

## Install

```sh
sudo ./install.sh
```

By default this targets whichever user is currently logged into the seat
and launches `spectacle` on P2. Override either:

```sh
sudo ./install.sh --user alice --screenshot-cmd "spectacle -r"
```

## Uninstall

```sh
sudo ./uninstall.sh
```

## Manual build (no DKMS)

```sh
make
sudo insmod getac-mpmd.ko
```
