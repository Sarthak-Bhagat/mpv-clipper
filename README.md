# mpv-clipper

Press **B** in mpv to mark where a clip starts, press **B** again to mark where
it ends, and you get an mp4 and a gif of that stretch, with the subtitles that
were on screen burned in. They land in one folder, named after the show,
episode and start time: `chainsmokercat-s01e12-10.32.mp4` / `.gif`.

I wrote this for me, and it changes when I feel like changing it. It is one Lua
file and a short config.

## Why it works the way it does

**Subtitles are burned in.** The clips get sent to people, and a line of
dialogue without its text on screen doesn't carry. Whatever sub track mpv is
showing is what goes into the clip. If subs are hidden, the clip has none.

**Subs are extracted to a temp file first, along with the file's fonts.**
ffmpeg's `subtitles` filter can read a sub track straight out of an mkv, but it
needs the path escaped inside a filter string, and Sonarr-style names are full
of `[`, `]`, `(` and `,`. Extracting to `/tmp/mpv-clipper.XXXXXX/subs.ass`
avoids that. Dumping the mkv's font attachments next to it means anime subs
render in their own typeface, not a fallback.

**`-ss` and `-t` both go before `-i`.** The gif is made in one pass with
`palettegen`, which emits nothing until its input ends. With `-t` as an output
option, ffmpeg kept reading to the end of the episode: 65 seconds of work for a
one-frame gif. As an input option it takes about a second.

**`-copyts` and `-start_at_zero`.** Seeking on the input resets timestamps to
zero, but the `subtitles` filter keeps reading the file's own clock, so the
burned subs came out ~22 minutes off. `-copyts` keeps the real timestamps
through the filter and `-start_at_zero` shifts the output back to zero.

**Cuts are exactly where you press.** No snapping to subtitle lines. When a clip
is wanted by timestamp, the subtitle file is the better guide to where lines
start and end. When you are pressing a key while watching, the press is the
intent.

## Requirements

- mpv (built with Lua)
- ffmpeg with libx264 and libass
- `sh`, `mktemp`, `mkdir`, `rm`

## Install

The script goes in mpv's `scripts` folder and its config in `script-opts`
beside it:

```fish
mkdir -p ~/.config/mpv/scripts ~/.config/mpv/script-opts
cp clipper.lua ~/.config/mpv/scripts/
cp -n clipper.conf ~/.config/mpv/script-opts/
```

`clipper.conf` is optional. The script runs on its defaults without one, and
`-n` means a later reinstall will not overwrite a config you have edited.

mpv only loads scripts at startup, so restart it afterwards. A press of B that
shows `clipper: start …` on screen means it loaded.

## Config

`clipper.conf`:

```
outdir=
mp4=yes
gif=yes
```

**An empty `outdir` asks the system.** The script runs `xdg-user-dir VIDEOS` and
writes to `<that>/clips`. That is the folder you set yourself, and it is
localised, so a hardcoded `~/Videos` is the wrong folder on a machine where it
is called `Vidéos`. This is xdg-user-dirs, not the XDG Base Directory spec,
which is for config and cache rather than for output you go looking for. Any
absolute path overrides it. `~` is expanded, and the folder is created on the
first clip.

**`mp4=no` and `gif=no` skip that encode.** The x264 pass is the slow one, so
turning it off is worth something if you only ever send gifs. With both off, B
marks a range and then says there is nothing to encode. Collision checking
follows whichever outputs are on, so turning mp4 off does not start overwriting
gifs.

To bind a different key, add a line to `input.conf`:

```
Ctrl+b script-binding clipper/clip
```

## What you get

| | |
|---|---|
| mp4 | 1280px wide, x264 CRF 18, AAC 192k, faststart. Off with `mp4=no` |
| gif | 600px wide, 15 fps, one-pass palette, loops. Off with `gif=no` |
| name | `<title>-<sXXeYY>-<m.ss>`, taken from the filename. A leading `[Group]` tag is dropped, and the title stops at the first `(year)`, `[tag]`, ` - ` or `SxxEyy` |
| collision | a second clip at the same second becomes `…-2`, never overwrites |

Encoding runs in the background. The OSD says when it starts and where it saved.
If a step fails the OSD says which one, and ffmpeg's error is in the console
(`` ` ``).

## Limits

- **Image subtitles (PGS, VobSub) are not burned in.** The `subtitles` filter
  only draws text. The script says so on the OSD and clips without them. That
  fallback has not been run against a real PGS file yet.
- Streams and URLs are refused. It needs a local file.
- There is no cancel key. Two presses closer than 0.1s apart clear the mark.

## Testing

```fish
./test.sh "/path/to/an/old/episode.mkv"          # clips 10:00.5 → 10:03.0
./test.sh "/path/to/an/old/episode.mkv" 60 64.5
```

It starts a headless mpv with your config and this repo's `clipper.lua`,
presses B, seeks, presses B, and prints what the script logged. Clips go to a
temp dir, not `outdir`. Exit status is 0 if a clip was saved. Use a file that
has been in the library for a while; recent downloads are deleted after
watching. The header of `test.sh` explains each isolation flag.

## Licence

MIT, in [`LICENSE`](LICENSE). Keep the copyright line, do what you like with
the rest.
