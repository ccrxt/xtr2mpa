# xtr2mpa

Extract a selected audio stream from a video file, normalize it for playback,
and save it as MPA (default) or optional FLAC.

## Requirements

- Bash
- FFmpeg and FFprobe

Run the setup script to install FFmpeg on supported systems:

```sh
./setup.sh
```

`setup.sh` supports macOS through Homebrew and Ubuntu/Debian through `apt-get`.
For other systems, install FFmpeg with your platform package manager.

## Usage

```sh
./extract.sh [options] input-video [output-audio.mpa]
```

Examples:

```sh
./extract.sh movie.mp4
./extract.sh movie.mkv audio.mpa
./extract.sh --stream 1 --target-lufs -18 -o voice.flac movie.mov
```

If no output path is provided, the script writes a `.mpa` file next to the
input using the input basename. For example, `movie.mp4` becomes `movie.mpa`.

## Options

| Option | Description | Default |
| --- | --- | --- |
| `-o, --output PATH` | Output path. Must end in `.mpa` or `.flac`. | Input basename + `.mpa` |
| `-s, --stream INDEX` | Audio stream index to extract. | `0` |
| `--target-lufs VALUE` | Target integrated loudness. | `-16` |
| `--true-peak VALUE` | Target true peak. | `-1.5` |
| `--lra VALUE` | Target loudness range. | `11` |
| `-f, --force` | Overwrite an existing output file. | Disabled |
| `-h, --help` | Show command help. | |

## What It Does

`extract.sh` performs a two-pass FFmpeg loudness normalization:

1. Analyze the selected audio stream with FFmpeg's `loudnorm` filter.
2. Re-run FFmpeg with the measured values to write normalized MPA or FLAC audio.

The script preserves the source sample rate when compatible, excludes
video, subtitles, and data streams, and refuses to overwrite existing output
unless `--force` is provided.
