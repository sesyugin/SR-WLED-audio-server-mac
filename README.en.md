<div align="center">

<img src="docs/icon.png" width="88" alt="">

# Auralis

**Music plays on the Mac — the LED strip across the room repeats its spectrum.**

No virtual audio driver. macOS 14.2+, strips running [WLED](https://github.com/wled/WLED).

[Русский](README.md) · [Download 0.3.0](https://github.com/sesyugin/SR-WLED-audio-server-mac/releases/latest) · [Changelog](CHANGELOG.md) · [Origin and licences](NOTICE)

<img src="docs/screens/window.jpg" width="880" alt="The main window: the spectrum stage and the control panel">

</div>

---

## What it does

The app listens to whatever is playing on the computer, splits the sound into 16
frequency bands every 10 milliseconds and sends them over the network to the strip.
A strip running WLED takes those 16 numbers and draws its own effects with them —
the equaliser, flashes on the beat, running waves.

<img src="docs/diagram-chain.svg" width="100%" alt="Signal path: system audio, CoreAudio process tap, a 2048-sample window with a 512 hop, FFT, 16 bands from the firmware table, a 44-byte packet, the strip">

Nothing gets installed underneath the system. The Windows version, and every
workaround on the Mac, needs a virtual audio driver such as BlackHole: it stands in
for the sound card so that the stream can be read from outside. Here the audio is
read through the mechanism macOS itself provides — a **CoreAudio process tap** — and
keeps going to the speakers exactly as before.

## What it looks like

The panel is needed twice: when setting up, and when working out why a strip is dark.
The rest of the time it takes a third of the width away from the thing the window was
opened for — so it hides, with the button under the stage or ⌘⌃S. After three seconds
of stillness the chrome over the stage goes too; any pointer movement brings it back.

<img src="docs/screens/watch-mode.jpg" width="880" alt="Watch mode: the panel is hidden and the stage fills the window">

Four scenes and four palettes, and the column hue comes from a slider — from the
palette or your own across the whole circle.

<p align="center">
  <img src="docs/screens/look-ice.jpg" width="290" alt="Ice palette">
  <img src="docs/screens/look-violet.jpg" width="290" alt="Violet palette">
  <img src="docs/screens/look-mono.jpg" width="290" alt="Mono palette">
</p>

**Sixteen languages** — in the app, in the command line version and in the system
permission dialog. Arabic and Urdu with the layout mirrored.

<img src="docs/screens/window-ru.jpg" width="880" alt="The same window in Russian">

## Diagnostics

There are four reasons a strip does not light up, and a person cannot tell them
apart: audio recording permission was not granted; no address is set; the strip is
not in receive mode; the processing is emitting zeroes. One general "not working"
indicator is useless here — what is needed is an answer about what to fix.

So each reason is checked separately, with its own verdict and its own advice, and
the button beside them puts the whole report on the clipboard — in the interface
language, so it can be sent to someone.

<img src="docs/screens/diagnostics.jpg" width="880" alt="The diagnostics tab: four axes with verdicts">

## How it differs from the Windows version

This is not a line-by-line port: no C# was carried over, everything was written
again in Swift. Along the way a few places turned up where the original disagrees with
what the firmware expects.

### Packet fields

The firmware expects 44 bytes, and a specific quantity in every field. The original
put **the ratio of the mid band to the loudest band** into the loudness fields — a
quantity that barely moves whether the music is quiet or loud. A 48 dB change in the
signal moved the value by less than 40 units out of 255 — and a dozen and a half WLED
effects feed on those fields.

<img src="docs/diagram-packet.svg" width="100%" alt="Packet layout: 6-byte header, pressure, sampleRaw, sampleSmth, peak, frame counter, 16 equaliser bands, zero crossings, magnitude, major peak">

Three more fields were computed in the wrong unit: sound pressure and the zero
crossing count are now converted to the firmware's own units, and the frame counter
no longer resets on silence — WLED-MM accepts a packet only if the counter has grown,
so by resetting it the original stopped driving the strip after the very first pause.

### The band table

The original built its bands on a logarithmic grid from 40 to 10000 Hz. An FFT,
meanwhile, has a constant step in frequency — 23.4 Hz at a 48 kHz sample
rate with a 2048-sample window. The three lowest bands of such a grid are narrower
than that step, which means each gets a single FFT bin for the whole band; the bass
had to be filled in by interpolating its neighbours.

<img src="docs/diagram-bands.svg" width="100%" alt="The firmware band table compared with a logarithmic 40–10000 Hz grid and with the FFT bin width">

The firmware's table solves this by being uneven: its lowest bands are wider than one
bin, and its highest are far wider, because resolution is not needed up there. Beyond
that, the GEQ, DJ Light, Blurz and Akemi effects were tuned by their authors against
this exact table — each channel lights its own colour at its own point on the
strip.

### Signal processing

| What | Original | Here | What you see on the strip |
|---|---|---|---|
| Analysis window | FlatTop | **Hann** | FlatTop's main lobe is four times wider, so a single bass tone lit several bands at once |
| Band smoothing | none | **25 ms up, 250 down** | the strip stops flickering where the sound is not changing |
| Folding a band | loudest bin | **by energy** | upper bands are no longer inflated just because they are wider |
| AGC on a beat | ducks | **hits the ceiling** | neighbouring bands drop by 1.2 dB instead of 7.5 |
| Latency | 21 ms | **10 ms** | a 512-sample analysis hop instead of 1024 |
| Band ceiling | 255 | **254** | WLED wraps anything above the limit: a bright peak turned into dim noise right on the beat |
| Send rate | unbounded | **≤ 50/s** | any faster and the firmware chokes; the limit is named in the WLED-MM documentation |
| On exit | strip freezes | **faded out** | neither vanilla nor MM clears the bands on its own |

Every difference can be switched off and judged by eye on the strip itself — a
checkbox in the settings or a flag in the command line version.

<img src="docs/screens/settings.jpg" width="880" alt="The settings tab: audio processing parameters">

## Capture rebuilds

Switch output to AirPods, change the sample rate, let the Mac sleep — capture
rebuilds itself. The packet stream does not break while it does: the frame counter
stays monotonic and the gap is about 100 ms against a 2.5 second signal-loss
threshold.

The sender is not recreated during a rebuild, and that is deliberate: the frame
counter belongs to it. Restarting the counter means being refused by WLED-MM, which
treats packets whose counter went backwards as duplicates and drops them.

## Installing

Download the archive from the [releases page](https://github.com/sesyugin/SR-WLED-audio-server-mac/releases/latest),
unpack it, move `Auralis.app` to Applications.

The bundle is **ad-hoc signed**, without an Apple Developer certificate. macOS puts a
quarantine flag on the download and refuses to open it, claiming the app is damaged.
Remove the flag:

```bash
xattr -dr com.apple.quarantine /Applications/Auralis.app
```

Or open it once via right click → **Open** and confirm. This is not a way around the
protection but the ordinary path for software without a paid developer signature: the
sources are all here and anyone can build their own copy.

On first launch macOS asks for two permissions: recording system audio and local
network access.

## Setting up the strip

In the WLED web interface: **Config → Usermods → AudioReactive**

- `Sync mode` — **Receive**
- `Port` — 11988 (the default)
- after changing the sync mode the strip needs a power cycle

To check that the strip is receiving the stream:

```bash
curl -s http://<strip-address>/json/info | grep -i "sound\|audio"
```

With the server running, the reply will contain `v2` and `receiving`. The firmware
sets the `v2` suffix only when a packet passed both of its checks — exactly 44 bytes
and the right header. That single line proves the format is correct.

## Building from source

Command Line Tools for Xcode are enough; the full Xcode is not needed.

```bash
./scripts/build-app.sh
open dist/Auralis.app
```

### Command line version

```bash
swift build -c release

# send to specific strips
.build/release/srwled --targets 192.168.1.50,192.168.1.51

# broadcast across the network
.build/release/srwled --mode broadcast
```

All the options are in `srwled --help`; the version is `srwled --version`. It speaks
the language of the system, the same sixteen as the app.

Comparing against the original:

```bash
srwled --targets 192.168.1.50 --original          # exactly like the Windows version
srwled --targets 192.168.1.50 --window flattop    # only the old window
srwled --targets 192.168.1.50 --bands custom      # only the old band grid
```

### Tests

```bash
./scripts/test.sh
```

No test touches an audio device or sends a packet to a real network — they run on
synthetic data and a stub transport. Xcode is not required: the project uses its own
runner, since XCTest and swift-testing ship only with Xcode.

### Diagrams and screenshots

The diagrams are drawn by code rather than by hand: a hand-drawn picture drifts away
from the code silently. The band table in the diagram is read straight out of
`Bucketizer.swift`.

```bash
python3 scripts/make-diagrams.py                     # diagrams into docs/
SRWLED_OUT=docs swift run -c release SRWLEDPreview   # scene frames and the mark
```

### Cutting a release

```bash
SRWLED_ARCHIVE=1 ./scripts/build-app.sh
```

Puts `dist/SR-WLED-Server-Auralis-macos-<version>.zip` next to the bundle. Only the
archive carries the long name, so that search finds it next to the original Windows
version; the app itself is named short. The version lives in one place,
`Sources/SRWLEDCore/Version.swift`.

## Privacy

Audio is never recorded, stored or transmitted. Only 44 bytes per frame go out over
the network: 16 equaliser values and a few level numbers. The content of the sound
cannot be reconstructed from them.

## Licence

Copyright © 2026 Zakhar Sesyugin. GPL-3.0, inherited from the original project
[SR-WLED-audio-server-win](https://github.com/Victoare/SR-WLED-audio-server-win),
whose behaviour is reproduced here. See [LICENSE](LICENSE) and [NOTICE](NOTICE).

Auralis is not affiliated with the WLED project, is not its official application and
is not endorsed by its authors. The WLED name is mentioned only to state
compatibility.
