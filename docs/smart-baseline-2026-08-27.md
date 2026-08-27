# SMART baseline — 2026-08-27, pre-provisioning

Captured from the Arch live ISO before any partitioning, with the pool empty.
This is the zero point that `tools/smart-snapshot.sh` deltas against once the
host is running. The interesting attributes are cumulative lifetime counters
that never reset, so a single reading says almost nothing — but a *first*
reading is what makes every later one meaningful.

## Machine

| | |
|---|---|
| CPU | Intel Core i3-2120 @ 3.30GHz, 2c/4t (Sandy Bridge) |
| RAM | 7.7 GiB |
| Firmware | **Legacy BIOS** — GPT + 1 MiB `ef02` BIOS boot partition |
| NIC | `enp4s0`, 192.168.4.21/22 (worth a DHCP reservation) |

Note: prior planning documents record this CPU as an i3-2320. The machine
actually reports an **i3-2120**. Same generation, same 3.3 GHz, same 2c/4t —
no design consequence, but the docs were corrected so the fact table stays
trustworthy.

## Drives

| Serial | Model | Size | Hours | Role |
|---|---|---|---|---|
| `154593406196` | SanDisk SDSSDA120G | 111.8 G | 2,463 | ssd — `archroot` |
| `Z4Z971E6` | ST2000DM006-2DM164 | 1.8 T | 60,827 | parity — `PARITY1` |
| `Z4Z972VW` | ST2000DM006-2DM164 | 1.8 T | 60,829 | data — `DISK1` |
| `Z4Z9739G` | ST2000DM006-2DM164 | 1.8 T | 60,825 | data — `DISK2` |
| `WD-WCC4MLEVP674` | WDC WD10EZRX-00D8PB0 | 931.5 G | 40,462 | data — `DISK3` |

All five report SMART overall-health `PASSED`.

## Watched counters at baseline

| Attribute | `Z4Z971E6` | `Z4Z972VW` | `Z4Z9739G` | `WD-…674` | SSD |
|---|---|---|---|---|---|
| 5 Reallocated_Sector_Ct | 0 | 0 | 0 | 0 | 0 |
| 10 Spin_Retry_Count | 0 | 0 | 0 | 0 | — |
| 187 Reported_Uncorrect | **1** | 0 | 0 | — | 0 |
| 188 Command_Timeout | 0 | **1 1 7313** | 0 | — | — |
| 197 Current_Pending_Sector | 0 | 0 | 0 | 0 | — |
| 198 Offline_Uncorrectable | 0 | 0 | 0 | 0 | — |
| 199 UDMA_CRC_Error_Count | 0 | **137,840** | 7 | 0 | 0 |

Media health across all four spinning drives is clean: no reallocated
sectors, no pending sectors, no offline-uncorrectables, no spin retries, on
seven-year-old drives. The platters are fine.

## The one finding: `Z4Z972VW`

`UDMA_CRC_Error_Count = 137,840` is not the "elevated count" the proposal
anticipated, and it should not be handled the way the proposal planned.

**What the number means.** UDMA CRC errors are *link* errors — a frame
arrived over the SATA cable with a bad checksum and had to be retransmitted.
They say nothing about the platters, which is consistent with every media
attribute on this drive reading zero. `Command_Timeout` on the same drive
reading `1 1 7313` while both its siblings read `0 0 0` corroborates a link
that is failing and retrying, not a disk that is dying.

**Why the magnitude does not settle it.** A first reading of this file argued
that six figures was too large to be a historical cabling event. That argument
assumed a *single* event, and it is wrong for these drives. They have 60,829
power-on hours across seven years and have been moved through a variety of
configurations — cables, controllers, enclosures — in that time, and attribute
199 never resets. A sustained bad-link period years ago accumulates a six-figure
count just as readily as an ongoing fault does; at ~19 errors per day averaged
over the drive's life, it does not even require a dramatic one. The same applies
to attribute 188: `1 1 7313` is a lifetime count, not a recent one.

So the reading is consistent with both a closed historical problem and a live
one, and **only the rate distinguishes them** — which is exactly what the
proposal said. The count is a number to watch, not a verdict.

**Why "PASSED" is not reassurance here.** Seagate normalises attribute 199 to
200 with a threshold of 0, so the value never falls and never trips the
overall-health assessment no matter how high the raw count climbs. This drive
would report `PASSED` at ten million.

**What it actually costs.** SATA CRC is detected and the transfer retried, so
this is not silent corruption — it is throughput loss and, at the far end,
link resets that drop the drive out of the array. That makes it a reliability
and performance problem rather than a data-integrity emergency, but on a
member of a SnapRAID array it becomes both: a drive that drops mid-sync
leaves the array degraded, and sync times stretch badly under constant
retransmission.

## Decision: build the pool, collect the delta, act on the trend

**Provisioning proceeds. The value to watch is 137,840, recorded here as the
zero point.** Hardware isolation is deferred until after the build-out.

The reasoning is that the build-out *is* the test, and a better one than a
bench check would be. Two things fall out of the design at no extra cost:

- **`smartd` with persistent state files** (`bootstrap/60-alerting.sh`) catches
  any movement in attribute 199 as it happens and pushes it to ntfy. The
  persistent state files are load-bearing for exactly this: without them smartd
  re-baselines on every restart and would not report a change that occurred
  across a reboot.
- **`tools/smart-snapshot.sh`** writes full `smartctl -A` output weekly and
  reports deltas against both the previous snapshot and the oldest retained
  one, so two weeks produces the rate directly.

And the load profile is right. Nightly SnapRAID sync plus weekly scrub keeps
real traffic on that link, which exercises it harder than an idle bench would.
A fault that only appears under sustained transfer shows up here and would not
show up in a `dd` sweep on an otherwise idle machine.

**The risk of proceeding is small and bounded.** CRC errors are detected and
retransmitted, so this is not silent corruption. The failure mode if the link
*is* live — the drive dropping out mid-sync — leaves a degraded array, which is
the case SnapRAID exists to absorb, and `Z4Z972VW` is a data member rather than
parity precisely so that a drop costs the least. The pool starts empty, so the
first weeks are also the cheapest weeks for it to happen.

**What to do when the delta lands (roughly 2026-09-10).**

- *Counter static across two weeks of sync and scrub* → historical. Close the
  item, note the closure here, and stop thinking about it.
- *Counter climbing* → isolate in order of cost, one change at a time, since
  swapping several parts at once destroys the evidence of which was at fault:
  1. Reseat or replace that drive's SATA data cable and power lead. An external
     tower plus an add-on card puts several connectors in the path; this is the
     highest-probability cause and the cheapest fix.
  2. Watch another week. Still climbing → move it to a different port on the
     add-on card. Watch again.
  3. Still climbing on a known-good cable and a different port → the drive's own
     SATA interface is the remaining suspect. Demote it; the pool tolerates one
     failure, and continuing to spend that tolerance on a known-bad link is a
     choice rather than an accident.

This item was carried forward from the previous build as "needs a SATA cable
reseat". It stays open — but now with a recorded baseline and an automatic
mechanism collecting the evidence, which is what it lacked before.

## Closed by this capture

- **Firmware mode**: legacy BIOS. `01-partition.sh` takes the GPT + `ef02`
  branch; `/boot` is a directory inside the root subvolume.
- **TRIM**: supported. `/dev/sdi` reports `DISC-GRAN 512B`, `DISC-MAX 2G`, so
  **p3 takes the full remainder** (~61.8 GiB) and the 8 GiB overprovisioning
  fallback is not needed.
- **Serials**: all five populated in `drives.conf`.
- **Parity**: assigned to `Z4Z971E6` — reasoning recorded in `drives.conf`.

## Incidental

The machine presents a USB multi-card reader as four zero-byte devices
(`sde`–`sdh`) that all share the serial `058F63626420`. `serial_to_dev()` in
`lib/common.sh` matches only `ata-*_<serial>` and `nvme-*_<serial>` by-id
links, and skips `-partN` links, specifically so a duplicate or partial
serial match can never resolve to one of these.
