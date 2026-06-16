# headphone-keepalive

A tiny macOS utility that stops the **static / crackle / pop** some Bluetooth
headphones (e.g. Bose QuietComfort) make every time audio starts or stops.

## The problem

Many Bluetooth headphones power down their amp/DAC when no audio is playing. The
next time something plays — or stops — that circuit wakes or idles, and you hear a
crackle or pop. macOS makes it worse by tearing down the audio stream the instant
playback ends.

## How it works

`keepalive` keeps a single, continuous, **inaudible** audio stream flowing to the
default output device, so the link never idles and there's no wake/idle transition
to pop. By default it outputs **pure digital silence** (literal zeros) — inaudible
by definition. If your headphones need actual signal energy to stay awake, there's
a fallback to a sub-audible ~20 Hz tone at the noise floor (`--db -90`), still
inaudible on two counts (level below your headphones' own hiss, frequency where the
ear barely responds).

### Idle-aware — it won't block sleep

An always-on audio stream would stop macOS from idle-sleeping (it treats active
audio as "media playing"). So `keepalive` watches the system idle timer and
**releases the stream after a period of inactivity** (default 120s), letting your
Mac sleep on its normal schedule, then resumes the instant you're active again.
Manual sleep and closing the lid are never affected.

Tradeoff: if the headphones idled while you were away, the *first* sound after you
return may pop once — versus a pop on every start/stop.

## Install

Requires the Xcode Command Line Tools (`swiftc`).

```sh
./install.sh          # compile, install a LaunchAgent, start at login
./install.sh 90       # optional: pause after 90s idle instead of 120s
```

## Uninstall

```sh
./uninstall.sh
```

## Manual control

```sh
# stop now (and at login)
launchctl bootout gui/$(id -u)/com.$(whoami).headphone-keepalive
# start again
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.$(whoami).headphone-keepalive.plist
```

## Options

| Flag | Default | Meaning |
|------|---------|---------|
| `--idle-stop <sec>` | `120` | Pause after this many seconds idle (`0` = never; always on) |
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
