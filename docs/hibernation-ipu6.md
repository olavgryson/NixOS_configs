# Hibernation on dragonflyg4, and why the IPU6 camera breaks it

Investigated 2026-07-30. Status: **cause identified, fix applied, not yet
proven.** The reboot has happened and `lsmod | grep -E "ipu6|hi556"` is now
empty, so the blacklist is in effect — but no hibernate attempt has been made
since. The waybar hibernate button was put back on the same date on the strength
of the diagnosis alone. Section 8 is still the outstanding test.

---

## 1. The symptom as experienced

Close the lid in the evening, and by morning the laptop is dead — not asleep,
flat. Plug it in, open the lid, and it "pops to life" instantly showing the
lock screen, but:

- the clock on the lock screen still reads the time the lid was closed
- nothing responds — no key, no click, no touchpad
- the only way out is holding the power button until it powers off
- power it back on, log in, and every application is still open where you left it

That last point is what makes the behaviour so misleading. It looks like
hibernation working. It is the exact opposite: it is hibernation *failing* in a
way that never lets go of RAM.

## 2. What actually happens

`suspend-then-hibernate` was on the lid switch, with `HibernateDelaySec=30min`.
So 30 minutes after the lid closed, the machine woke itself on an RTC alarm and
tried to hibernate. That attempt does the following:

1. Freezes userspace — fine.
2. Snapshots memory into RAM (~4-6 GB) — fine.
3. Suspends devices, then resumes them so the image can be written to disk.
4. **A device fails to resume, the kernel discards the image, and hibernation is
   aborted.** Not one byte is written to swap.
5. The machine does not power off, and does not return to a usable state either.
   It sits there with every task frozen and the hardware powered until the lid
   is opened — draining the battery to zero.

The session survives the eventual forced power-cycle only because the
applications restore themselves, and because RAM was never actually released.
There is no hibernate image involved at any point.

## 3. The failing device

```
PM: hibernation: Normal pages needed: 936264 + 1024, available pages: 3146445
sof-audio-pci-intel-tgl 0000:00:1f.3: IMR restore failed, trying to cold boot
intel-ipu6 0000:00:05.0: Unexpected magic number 0xffffffeb
intel-ipu6 0000:00:05.0: FW authentication failed(-110)
PM: hibernation: Basic memory bitmaps freed
Restarting tasks: Starting
Restarting tasks: Done
PM: hibernation: hibernation exit
```

`intel-ipu6` is the IPU6 MIPI camera block (PCI `0000:00:05.0`, sensor
`INT3537` / `hi556`). After the memory snapshot it has to re-authenticate its
firmware with the CSE (Intel's Converged Security Engine) and times out —
`-110` is `ETIMEDOUT`. The abort follows immediately, with no image write and no
error message of the kernel's own.

`sof-audio` (the audio DSP) also complains in the same window, but it says
`trying to cold boot` and recovers itself, and the same line appears on ordinary
resumes that succeed. It is the secondary suspect, not the primary one.

## 4. Proof that no hibernation ever occurred

Measured across the 2026-07-30 13:25 attempt:

| Check | Result |
| --- | --- |
| boot id before / after | `58f819e2-...` / `58f819e2-...` — identical |
| `uptime -s` | unbroken since 13:16:45 |
| fresh kernel boots during the attempt | 0 |
| bytes written to the swap partition | 0 B |
| `systemd-hibernate-resume` restoring an image | never, on any boot |

A real hibernation always ends in a power-off followed by a fresh kernel boot
that reads the image back. Neither has ever happened on this host.

Three observed attempts, all identical in outcome:

| When | Trigger | Frozen for | Outcome |
| --- | --- | --- | --- |
| 2026-07-29 01:58 | `suspend-then-hibernate` RTC wake, 30 min after lid close | 8 h 07 min | battery flat, forced power-off |
| 2026-07-30 03:10 | waybar hibernate button | 9 h 42 min | battery flat, forced power-off |
| 2026-07-30 13:25 | `systemctl hibernate`, `HibernateMode=shutdown` | ~2 min | aborted back to life |

## 5. What was ruled out

**It is not the ACPI S4 platform transition.** The first theory was that the
firmware botches S4, because attempts under the default `HibernateMode=platform`
showed the kernel entering and instantly leaving S4:

```
ACPI: PM: Preparing to enter system sleep state S4
ACPI: PM: Waking up from system sleep state S4
```

Setting `HibernateMode = "shutdown"` skips ACPI S4 entirely — the kernel writes
the image itself and does a plain poweroff. Verified applied
(`/sys/power/disk` showed `platform [shutdown]`), and hibernation **still**
aborted at exactly the same point with the same `intel-ipu6` error. So the S4
lines were a symptom of the snapshot phase, not the cause.

**It is not swap sizing or the resume device.** RAM 15 GiB, swap partition
`/dev/nvme0n1p2` 17 GiB and empty, image ~4-6 GB,
`resume=/dev/disk/by-label/SWAP` resolves to `259:2` on the kernel command line.
zram is separate (priority 5) and systemd correctly excludes it as an image
target. All fine.

**Deep S3 suspend is not an escape route either.** The firmware advertises real
S3 (`ACPI: PM: (supports S0 S3 S4 S5)`, and `deep` is listed in
`/sys/power/mem_sleep`), which would have cut idle drain enough to survive a
night on suspend alone. Tested 2026-07-30 via
`systemd.sleep.settings.Sleep.MemorySleepMode = "deep"`:

```
2026-07-30T13:14:34 kernel: PM: suspend entry (deep)
```

That is the last line ever written. The fans spin back up on a power button
press, the panel stays black, input is dead, and only a forced power-off
recovers it. **Do not set `MemorySleepMode = "deep"` on this machine.** Suspend
stays on the kernel default, s2idle.

## 6. Why disabling the camera is the right trade

Making the IPU6 camera *work* would not fix hibernation. The failure is firmware
re-authentication after a memory snapshot; a fully working camera pipeline still
has to survive that same re-auth, and having more of the stack live during the
snapshot gives more to break, not less. They are unrelated problems.

And there is nothing to give up here — the camera does not work on this host
anyway:

- the kernel side loads and binds the `hi556` sensor, producing ~32 raw ISYS
  `/dev/video*` nodes that no ordinary application can open
- a usable camera needs `hardware.ipu6.enable = true` (which pulls in
  `v4l2-relayd` + `icamerasrc`), and that is **not** set in this config
- so browsers, Zoom and friends currently see no camera at all

## 7. Current configuration

In `configuration.nix`:

```nix
boot.blacklistedKernelModules = [
  "intel_ipu6_isys"
  "intel_ipu6"
  "ipu_bridge"
  "hi556"
];

systemd.sleep.settings.Sleep = {
  HibernateDelaySec = "30min";
  HibernateMode = "shutdown";   # never "platform"; never set MemorySleepMode = "deep"
};

services.logind.settings.Login.HandleLidSwitch = "suspend";   # NOT suspend-then-hibernate
```

In `home/desktop.nix`: the hypridle 15-minute action is `systemctl suspend`, and
`custom/hibernate` is left out of the waybar power drawer (its definition is
kept, so re-enabling is a one-line change).

Battery level is logged either side of every sleep, so overnight s2idle drain can
be measured after the fact — plain suspend has never actually been measured here,
because every previous overnight loss was the failed hibernate sitting powered:

```
journalctl -u sleep-actions
```

## 8. How to finish this

1. ~~Reboot.~~ Done 2026-07-30 21:13.
2. ~~Confirm the modules are gone: `lsmod | grep -E "ipu6|hi556"`.~~ Verified empty.
3. `systemctl hibernate`. **← still to do.**
4. **Success looks like:** the machine writes ~4-6 GB to `/dev/nvme0n1p2` and
   powers fully off — fans stopped, no lights. Press power, and it boots fresh
   and restores the session.
5. Verify it was real, not another abort:

```bash
journalctl -k | grep -iE "Image saving|hibernation: Image|systemd-hibernate-resume"
uptime -s                              # should be the new boot
cat /proc/sys/kernel/random/boot_id    # should have changed
```

If it worked, put `HandleLidSwitch = "suspend-then-hibernate"` back and re-add
`custom/hibernate` to the waybar drawer.

If it still aborts, the next suspect is `sof-audio-pci-intel-tgl`. Failing that,
this laptop cannot hibernate on Linux and the answer is suspend-only, judged on
the drain numbers from `journalctl -u sleep-actions`.

## 9. If the webcam is ever wanted back

The trade is explicit: either give up hibernation again, or try unloading the
modules only for the hibernate cycle via
`powerManagement.powerDownCommands` instead of blacklisting them. Note that
`intel_ipu6_isys` was observed at refcount 3 while idle, so `modprobe -r` may
simply refuse — which is why the blacklist was chosen for the test.

## 10. Environment these findings apply to

HP Dragonfly G4, i7-1355U (Raptor Lake-U), Intel Iris Xe, NixOS 26.11,
kernel 7.1.5, systemd 261.
