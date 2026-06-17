# headphone-keepalive

A tiny macOS utility that stops the **static / crackle / pop** some Bluetooth
headphones (e.g. Bose QuietComfort) make every time audio starts or stops.

## The problem

Many Bluetooth headphones power down their amp/DAC when no audio is playing. The
next time something plays — or stops — that circuit wakes or idles, and you hear a
crackle or pop. macOS makes it worse by tearing down the audio stream the instant
playback ends.

## How it works

`keepalive` plays a continuous, **inaudible** audio stream to your Bluetooth output
so the headphones' amp/DAC never idles — that idling is what makes them crackle when
audio starts or stops. The stream is **pure digital silence** by default (inaudible
by definition — it's exactly what a "silent" keepalive video plays).

Two things make it reliable:

- **It plays through `AVAudioPlayer`** — the high-level media-player API that music,
  podcast, and browser playback use — rather than a hand-managed audio engine. That's
  what lets it ride through audio-device / Bluetooth reconfigurations without dropping
  out (a raw engine gets knocked offline by them and pops).
- **It only runs on a Bluetooth output.** On built-in speakers, wired output, etc. it
  goes dormant automatically, and resumes when you switch back to Bluetooth.

A sub-audible ~20 Hz tone is available via `--db` if you ever want real signal instead
of silence, but it isn't normally needed.

### Sleep-friendly (with a grace window)

An always-on audio stream would stop macOS from idle-sleeping (it treats active
audio as "media playing"). So `keepalive` runs while your display is awake, and
keeps running for a **grace window (default 5 min) after the display sleeps** —
because the screen often sleeps while you're still around (e.g. listening while
working on another machine). If you wake the screen within that window, it never
paused; only after the screen stays off for the full window does it pause, letting
the Mac idle-sleep. Manual sleep and closing the lid pause it immediately.

Note: the grace window delays idle sleep by that long on battery (on AC the Mac
doesn't auto-sleep anyway). Use `--grace 0` to pause the instant the screen sleeps.

## Install

Requires the Xcode Command Line Tools (`swiftc`).

```sh
./install.sh          # compile, install a LaunchAgent, start at login
```

## Uninstall

```sh
./uninstall.sh
```

## Control

`install.sh` puts a short `hpk` command on your PATH:

```sh
hpk on            # start now, and at every login
hpk off           # stop now (until 'hpk on' or next login)
hpk toggle        # flip on/off
hpk status        # show ON/OFF + current settings

hpk grace <sec>   # keep running this long after the display sleeps (0 = at once)
hpk db <dBFS>     # signal level, e.g. -50  (or 'hpk db silence' for pure zeros)
hpk freq <Hz>     # tone frequency (default 20)
hpk config        # settings + file paths
```

Settings persist in `~/.config/headphone-keepalive.conf`, apply live (it reloads if
running), and survive logins.

## Options

| Flag | Default | Meaning |
|------|---------|---------|
| `--grace <sec>` | `300` | Keep running this long after the display sleeps before pausing (`0` = pause immediately) |
| `--db <dBFS>` | off | Emit a sub-audible tone at this level instead of pure silence |
| `--freq <Hz>` | `20` | Tone frequency when `--db` is used |
| `--quiet` | — | Suppress the periodic heartbeat log line |

## Prior art

Not a new idea — see [antipopd](https://github.com/mttrb/antipopd) (periodic
speech-synth nudge) and [speaker-awake](https://github.com/subhande/speaker-awake)
(interval silent pings). This one differs by holding a *continuous, gapless* stream
rather than periodic nudges, and by being idle-aware so it doesn't block sleep.

## Tested on

macOS 26.5, Bose QC Headphones.
