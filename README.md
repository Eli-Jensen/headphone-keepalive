# headphone-keepalive

**Stop Bluetooth headphones from crackling and popping on a Mac.**

Some Bluetooth headphones (Bose QuietComfort especially) make a burst of static, a
crackle, or a pop every time audio *starts* or *stops*: a notification chime, pausing
a video, the gap between songs, unmuting on a call. `headphone-keepalive` is a tiny
background tool that makes that go away by never letting the audio go quiet in the
first place. You can't hear it, it doesn't block sleep, and it only runs while
Bluetooth headphones are the active output.

```sh
git clone https://github.com/Eli-Jensen/headphone-keepalive.git
cd headphone-keepalive
./install.sh        # builds it, starts it now and at every login
```

That's the whole setup. Put your headphones on and the pops should stop.

## Is this for you?

It probably is if you're on macOS with Bluetooth headphones and:

- you hear a click, pop or hiss **right when** a sound starts or a video pauses,
- the noise is worst after a few seconds of silence, then fine while audio plays,
- it happens in every app (Slack, Safari, Music, Zoom), not just one, and
- playing a "silent video" in a background tab makes it disappear (the usual
  workaround; this tool does the same job without a browser tab).

It won't help with dropouts caused by weak signal, codec switching when a mic turns on
(the AAC → SCO "phone call quality" switch), or pops from **multipoint** headphones
switching between two devices. Those happen for different reasons.

## Why this exists

My Bose QC headphones crackled every time a sound started or stopped. The cause is
common: to save battery, the headphones power down their amplifier/DAC whenever no
audio arrives, and macOS tears down the audio stream the moment playback ends. Every
start and stop then wakes or idles that circuit, and you hear it.

The folk fix is to leave a "silent" YouTube video playing all day. It works, but
it's a browser tab you have to keep open forever. So I measured one of those videos:
it's **pure digital silence**, not a hidden tone. The content was never what mattered.
What mattered was that a *media player* kept a stream open and rode through macOS's
audio-device changes without stopping.

My first attempt used a low-level audio engine and still popped, because Bluetooth
reconfigurations quietly knocked it offline. Rebuilding it on `AVAudioPlayer`, the same
high-level playback API music and video apps use, fixed it. Then I made it polite:
Bluetooth-only, and out of the way when the Mac wants to sleep.

## How it works

`keepalive` loops a short, silent audio file through `AVAudioPlayer` to the current
output device, so the headphones always see an open stream and never idle.

- **Inaudible by construction.** The default stream is all zeros, so there is nothing
  to hear. A sub-audible ~20 Hz tone is available (`hpk db -50`) if your headphones
  turn out to need real signal, but that's rarely needed.
- **Bluetooth only.** It watches the default output device. On built-in speakers,
  wired headphones or AirPlay it pauses itself, and it resumes when you switch back.
- **Sleep-friendly.** Playing audio normally stops a Mac from idle-sleeping. So
  `keepalive` keeps playing for a **grace window after the display sleeps**
  (5 minutes by default, because the screen often sleeps while you're still listening),
  then pauses so the Mac can sleep. Waking the screen resumes it. Closing the lid or
  choosing Sleep pauses it immediately.
- **Out of the way.** It runs as a background LaunchAgent with no Dock icon and no
  menu-bar item, and launchd restarts it if it ever exits.

## Requirements

- macOS (tested on macOS 26.5 with Bose QC Headphones)
- Xcode Command Line Tools, for `swiftc`: run `xcode-select --install` if you don't
  have them

## Install

```sh
./install.sh
```

This compiles `keepalive.swift`, installs a per-user LaunchAgent so it starts at login,
starts it right away, and links a short control command, `hpk`, into the first writable
directory among `/opt/homebrew/bin`, `/usr/local/bin` and `~/.local/bin`.

## Everyday use

You don't need to do anything day to day; it starts at login. `hpk` is there when you
want to check on it or change something:

```sh
hpk status        # is it on, and with what settings?
hpk off           # stop it (stays off until 'hpk on' or your next login)
hpk on            # start it, and at every login
hpk toggle        # flip on/off

hpk grace 60      # pause 60 s after the display sleeps (0 = immediately)
hpk db -50        # use a sub-audible tone at -50 dBFS instead of silence
hpk db silence    # back to pure silence (the default)
hpk freq 20       # tone frequency in Hz, when a tone is used
hpk config        # current settings and file locations
hpk help
```

Settings are saved to `~/.config/headphone-keepalive.conf`, apply immediately (it
reloads if running), and survive restarts.

## Troubleshooting

- **Still hearing pops?** Run `hpk status` and confirm it says `ON` while your
  headphones are the output. If pops remain, try a faint tone instead of silence:
  `hpk db -50`.
- **Pops only when switching between your Mac and phone/another computer?** That's
  multipoint handoff, which no keepalive can prevent.
- **Mac not sleeping when you expect?** Lower the grace window, e.g. `hpk grace 0`.
- **Logs:** `keepalive.log` in the repo folder records when playback turns on or off
  and why.

## Uninstall

```sh
./uninstall.sh
```

This stops it, removes the LaunchAgent and the `hpk` link. The source folder is left
in place; delete it if you like.

## Running it by hand

`hpk` manages everything, but the binary takes flags directly:

| Flag | Default | Meaning |
|------|---------|---------|
| `--grace <sec>` | `300` | Keep running this long after the display sleeps before pausing (`0` = pause immediately) |
| `--db <dBFS>` | off | Emit a sub-audible tone at this level instead of pure silence |
| `--freq <Hz>` | `20` | Tone frequency when `--db` is used |
| `--silence` | on | Pure digital silence (the default) |
| `--quiet` | — | Suppress the periodic heartbeat log line |

## Prior art

Not a new idea. [antipopd](https://github.com/mttrb/antipopd) nudges the output with
periodic speech synthesis, and [speaker-awake](https://github.com/subhande/speaker-awake)
sends silent pings on an interval. This one holds a *continuous, gapless* stream
instead of periodic nudges, only runs on Bluetooth, and steps aside so the Mac can
sleep.

## License

[MIT](LICENSE)
