#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./extract.sh [options] input-video [output-audio.flac]

Extract the selected audio stream, analyze loudness, normalize for playback,
and save lossless FLAC audio.

Options:
  -o, --output PATH       Output path. Defaults to input basename + .flac
  -s, --stream INDEX      Audio stream index. Defaults to 0
  --target-lufs VALUE     Target integrated loudness. Defaults to -16
  --true-peak VALUE       Target true peak. Defaults to -1.5
  --lra VALUE             Target loudness range. Defaults to 11
  -f, --force             Overwrite existing output file
  -h, --help              Show this help

Examples:
  ./extract.sh movie.mp4
  ./extract.sh movie.mkv audio.flac
  ./extract.sh --stream 1 --target-lufs -18 -o voice.flac movie.mov
EOF
}

fail() {
  printf 'Error: %s\n' "$1" >&2
  exit 1
}

need_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1. Run ./setup.sh first."
}

json_value() {
  local key="$1"
  local file="$2"

  sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$file" | tail -n 1
}

input=""
output=""
stream_index="0"
target_lufs="-16"
true_peak="-1.5"
lra="11"
overwrite="-n"

while [ "$#" -gt 0 ]; do
  case "$1" in
    -o|--output)
      [ "$#" -ge 2 ] || fail "$1 requires a path"
      output="$2"
      shift 2
      ;;
    -s|--stream)
      [ "$#" -ge 2 ] || fail "$1 requires an audio stream index"
      stream_index="$2"
      shift 2
      ;;
    --target-lufs)
      [ "$#" -ge 2 ] || fail "$1 requires a loudness value"
      target_lufs="$2"
      shift 2
      ;;
    --true-peak)
      [ "$#" -ge 2 ] || fail "$1 requires a true-peak value"
      true_peak="$2"
      shift 2
      ;;
    --lra)
      [ "$#" -ge 2 ] || fail "$1 requires a loudness-range value"
      lra="$2"
      shift 2
      ;;
    -f|--force)
      overwrite="-y"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      while [ "$#" -gt 0 ]; do
        if [ -z "$input" ]; then
          input="$1"
        elif [ -z "$output" ]; then
          output="$1"
        else
          fail "Unexpected extra argument: $1"
        fi
        shift
      done
      break
      ;;
    -*)
      fail "Unknown option: $1"
      ;;
    *)
      if [ -z "$input" ]; then
        input="$1"
      elif [ -z "$output" ]; then
        output="$1"
      else
        fail "Unexpected extra argument: $1"
      fi
      shift
      ;;
  esac
done

[ -n "$input" ] || {
  usage >&2
  exit 1
}

[ -f "$input" ] || fail "Input file not found: $input"

need_command "ffmpeg"
need_command "ffprobe"

case "$stream_index" in
  ''|*[!0-9]*)
    fail "Audio stream index must be a non-negative integer"
    ;;
esac

audio_count="$(
  ffprobe -v error \
    -select_streams a \
    -show_entries stream=index \
    -of csv=p=0 \
    "$input" | wc -l | tr -d ' '
)"

[ "$audio_count" -gt 0 ] || fail "No audio stream found in input file"
[ "$stream_index" -lt "$audio_count" ] || fail "Audio stream index $stream_index not found. Input has $audio_count audio stream(s)."

sample_rate="$(
  ffprobe -v error \
    -select_streams "a:${stream_index}" \
    -show_entries stream=sample_rate \
    -of default=noprint_wrappers=1:nokey=1 \
    "$input" | sed -n '1p'
)"

case "$sample_rate" in
  ''|*[!0-9]*)
    sample_rate=""
    ;;
esac

if [ -z "$output" ]; then
  input_dir="$(dirname "$input")"
  input_name="$(basename "$input")"
  output="${input_dir}/${input_name%.*}.flac"
fi

case "${output##*.}" in
  flac|FLAC)
    ;;
  *)
    fail "Output must use .flac for lossless FLAC audio: $output"
    ;;
esac

if [ -e "$output" ] && [ "$overwrite" = "-n" ]; then
  fail "Output already exists: $output. Use --force to overwrite."
fi

analysis_log="$(mktemp "${TMPDIR:-/tmp}/xtr2mpa_loudnorm.XXXXXX")"
trap 'rm -f "$analysis_log"' EXIT

printf 'Analyzing audio stream %s...\n' "$stream_index"
ffmpeg -hide_banner -nostats \
  -i "$input" \
  -map "0:a:${stream_index}" \
  -vn -sn -dn \
  -af "loudnorm=I=${target_lufs}:TP=${true_peak}:LRA=${lra}:print_format=json" \
  -f null - \
  >"$analysis_log" 2>&1 || {
    sed -n '1,120p' "$analysis_log" >&2
    fail "Audio analysis failed"
  }

input_i="$(json_value "input_i" "$analysis_log")"
input_tp="$(json_value "input_tp" "$analysis_log")"
input_lra="$(json_value "input_lra" "$analysis_log")"
input_thresh="$(json_value "input_thresh" "$analysis_log")"
target_offset="$(json_value "target_offset" "$analysis_log")"

[ -n "$input_i" ] || fail "Could not read measured integrated loudness from FFmpeg output"
[ -n "$input_tp" ] || fail "Could not read measured true peak from FFmpeg output"
[ -n "$input_lra" ] || fail "Could not read measured loudness range from FFmpeg output"
[ -n "$input_thresh" ] || fail "Could not read measured loudness threshold from FFmpeg output"
[ -n "$target_offset" ] || fail "Could not read target offset from FFmpeg output"

printf 'Measured level:\n'
printf '  Integrated loudness: %s LUFS\n' "$input_i"
printf '  True peak:           %s dBTP\n' "$input_tp"
printf '  Loudness range:      %s LU\n' "$input_lra"
printf 'Normalizing target:\n'
printf '  Integrated loudness: %s LUFS\n' "$target_lufs"
printf '  True peak:           %s dBTP\n' "$true_peak"
printf '  Loudness range:      %s LU\n' "$lra"
[ -z "$sample_rate" ] || printf '  Sample rate:         %s Hz\n' "$sample_rate"

filter="loudnorm=I=${target_lufs}:TP=${true_peak}:LRA=${lra}:measured_I=${input_i}:measured_TP=${input_tp}:measured_LRA=${input_lra}:measured_thresh=${input_thresh}:offset=${target_offset}:linear=true:print_format=summary"

printf 'Saving normalized lossless FLAC: %s\n' "$output"
ffmpeg_args=(
  "$overwrite" -hide_banner
  -i "$input"
  -map "0:a:${stream_index}"
  -vn -sn -dn
  -af "$filter"
  -c:a flac
  -compression_level 8
)

if [ -n "$sample_rate" ]; then
  ffmpeg_args+=(-ar "$sample_rate")
fi

ffmpeg_args+=("$output")

ffmpeg "${ffmpeg_args[@]}"

printf 'Done: %s\n' "$output"
