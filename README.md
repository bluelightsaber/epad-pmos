# postmarketOS for the Eewrite E-PAD (Epad_PRO)

Mainline Linux and [postmarketOS](https://postmarketos.org) for the **Eewrite E-PAD**, a 10.3" E Ink
tablet (1872×1404 panel) built around the MediaTek **MT6797** (Helio X20/X25, 10 cores) with an MT6351 PMIC, a
T1000 E Ink timing controller, a Cypress TT21000 touch panel and a Wacom-style HID pen. The goal is a working,
publishable system: mainline kernel, standard postmarketOS userspace, and [KOReader](https://koreader.rocks) as
the reading UI.

> **Status: work in progress.** It boots and is usable for reading, but it has only been tested on one unit, and
> only booted from RAM (nothing written to the internal storage except the recovery slot used for test kernels).

## What works

| Area | State |
|---|---|
| Kernel | Linux **7.2.11** + 20 patches (`kernel/patches`), all 10 CPUs, cpufreq (3 clusters), thermal |
| Display | E Ink panel via the T1000 controller (own driver, `/dev/t1000` refresh ioctl), simple framebuffer |
| Touch | cyttsp5 (TT21000), multitouch |
| Pen | HID pen with pressure; contact decided from `ABS_PRESSURE` in the KOReader port |
| Power key | MT6351 press/release interrupts (`mt6351-pwrkey`): short and long press |
| Power off | MT6351 RTC (`system-power-controller`) |
| Battery | MT6351 fuel gauge (voltage/capacity estimate), bq24296 charger (charge status) |
| WiFi | MT6797 CONNSYS (MT6631) WLAN driver, WPA2, ~36 Mbit/s; NetworkManager |
| Bluetooth | CONNSYS STP driver (HCI comes up; little tested) |
| Front light | Cold/warm PWM LEDs (`/sys/class/leds/frontlight-{cold,warm}`) |
| eMMC, USB gadget, RTC | yes |
| **Suspend to RAM** | **no** (the MT6797 SPM firmware interface is not solved yet) |
| Audio, camera, sensors | no / not attempted |

## Repository layout

- `kernel/patches/` — patch series on top of v7.2.11 (one commit per subsystem). `kernel/dts/` has the board DTS
  (also in the last patch).
- `kernel/configs/` — config fragments merged on top of `defconfig`: `solo-mediatek.config` (drop other SoCs),
  `reducir.config`, `epad.config` (board drivers) and `pmos.config` (postmarketOS `kconfig check --categories
  community` requirements, generated with `tools/kconfig-frag.py`).
- `pmaports/` — postmarketOS packages: `device/testing/{device,linux,firmware}-eewrite-epad`,
  `device/testing/koreader-epad-session` (systemd unit that starts KOReader on the panel) and `temp/koreader`
  (Alpine's package rebuilt with `CI=1`, plus the E-PAD port).
- `koreader-port/` — the KOReader device port (framebuffer refresh through `/dev/t1000`, evdev input, power,
  front light, battery, WiFi through wpa_supplicant).
- `tools/` — helper scripts.

## Firmware

`firmware-eewrite-epad` only contains the APKBUILD: the WiFi/BT firmware, the per-unit WiFi NVRAM (it holds the
MAC address) and the SPM programs are proprietary and are **not** distributed here. Extract them from your own
tablet's Android (`/vendor/firmware`, `/system/etc/firmware` and the `nvdata` partition) and put them next to
the APKBUILD.

## Building

Copy `pmaports/device/testing/*` and `pmaports/temp/koreader` into your pmaports checkout, then:

    pmbootstrap init          # device: eewrite-epad, UI: console
    pmbootstrap build linux-eewrite-epad device-eewrite-epad koreader koreader-epad-session
    pmbootstrap install

Notes:
- The bootloader (MediaTek lk) prepends `slub_debug=OFZPU slub_max_order=0` to the kernel command line. That
  combination triggers a slab/memcg bug in 7.2 (memory corruption as soon as systemd creates cgroups; also
  reproducible in QEMU), so the deviceinfo appends `slub_debug=-`.
- The `boot` and `recovery` partitions are 16 MiB, hence `deviceinfo_create_initfs_extra`.
- KOReader from Alpine's aarch64 repository is built with `-march=native` on the builders and dies with SIGILL on
  ARMv8.0 cores; the package here rebuilds it with `CI=1`.

## Safety

This is a device with a locked-down MediaTek boot chain. **Never** write the preloader, and never touch the
`nvram`, `nvdata`, `protect*` or `proinfo` partitions: they hold calibration and identity data that cannot be
recreated. Test kernels can be booted from the `recovery` slot while Android stays untouched in `boot`. Use at
your own risk.

## Licenses

Kernel patches: GPL-2.0 (as the kernel). KOReader port: AGPL-3.0 (as KOReader). Packaging files: MIT (as
pmaports).

## Related

- [epad-AOSP](https://github.com/bluelightsaber/epad-AOSP) — the parallel effort to run a modern Android.
