# Whisper Dictation Runbook

Press F6 (or G5 on the Logitech G915) to start recording. Press again to stop and transcribe. The result is typed into whatever app has focus.

---

## Pipeline

```
F6 / F13 (G915 G5 key)
  → toggleDictation() in ~/.hammerspoon/init.lua
  → sox records mic to /tmp/whisper-dictation.wav
  → ~/whisper/transcribe.sh runs mlx_whisper in the venv
  → hs.eventtap.keyStrokes() types the result into the focused app
```

**Key paths:**

| Component | Path |
|---|---|
| Hammerspoon config | `~/.hammerspoon/init.lua` |
| Transcribe script | `~/whisper/transcribe.sh` |
| Python venv | `/Users/valdezjm/whisper/.venv` (Python 3.11.15) |
| Model cache | `~/.cache/huggingface/hub/models--mlx-community--whisper-large-v3-turbo` (1.5 GB) |
| Audio temp file | `/tmp/whisper-dictation.wav` |

sox and python are invoked by absolute path. ffmpeg is not (see failure mode 2 below).

Error alerts surface at `~/.hammerspoon/init.lua` line 36.

---

## Known Failure Modes

### 1. Nothing happens on keypress

Hammerspoon is not running. Launch it from Applications. "Launch at Login" is enabled, so this should not recur unless the preference is reset.

### 2. `FileNotFoundError: [Errno 2] No such file or directory: 'ffmpeg'`

**This was the root cause fixed on 2026-10-20. It is the most likely failure class going forward.**

Hammerspoon launches with a stripped PATH: `/usr/bin:/bin:/usr/sbin:/sbin`. That is enough for sox and python because both are invoked by absolute path in the script. `mlx_whisper` shells out to a bare `ffmpeg`, which lives at `/opt/homebrew/bin/ffmpeg` and is not on that path.

The fix is `export PATH="/opt/homebrew/bin:$PATH"` at the top of `transcribe.sh`. That line is there now.

This class of bug will recur any time a new Homebrew binary is added anywhere in the pipeline and invoked by name rather than absolute path.

The pre-fix script is at `~/whisper/transcribe.sh.bak` for reference.

### 3. Missing permissions

Check System Settings > Privacy & Security for all three:

- **Accessibility**: required for `hs.eventtap.keyStrokes()` to type the result
- **Input Monitoring**: required for the hotkey to fire
- **Microphone**: required for sox to capture audio

Without Accessibility or Input Monitoring, failure is silent. Without Microphone, sox captures nothing and the empty recording hits failure mode 4.

To check: open System Settings > Privacy & Security > each category and confirm Hammerspoon is listed and enabled.

### 4. Empty recording treated the same as a crash

An empty recording exits 0 with empty stdout. The callback in init.lua treats this as a failed transcription and shows the error alert. This is a known sharp edge that is not yet fixed.

If you see the "Whisper transcription failed" alert but suspect you just did not speak, check whether `/tmp/whisper-dictation.wav` exists and has content above 44 bytes (the WAV header size). If it is 44 bytes, sox captured nothing. See permissions above.

### 5. Stale or garbled audio

`/tmp/whisper-dictation.wav` is overwritten on each run. After a failed transcription, inspect this file before reloading anything. Play it back to confirm the audio is intelligible.

---

## Diagnostic Commands

**Reproduce under Hammerspoon's exact PATH** (the key technique: this surfaces PATH-dependent failures that work fine in a login shell):

```bash
env -i HOME="$HOME" PATH=/usr/bin:/bin:/usr/sbin:/sbin ~/whisper/transcribe.sh /tmp/whisper-dictation.wav; echo "exit=$?"
```

**Check what PATH Hammerspoon is actually running with:**

```bash
# Get the pid first
pgrep -x Hammerspoon
# Then inspect its environment (replace <pid>)
ps -E <pid>
```

**Test mic capture alone** (captures 2 seconds, then check file size):

```bash
/opt/homebrew/bin/sox -d -q -c 1 -r 16000 /tmp/miccheck.wav trim 0 2
ls -lh /tmp/miccheck.wav
# Should be well above 44 bytes; 44 bytes means sox captured nothing
```

**Reload Hammerspoon config without restarting the app:**

```bash
/opt/homebrew/bin/hs -c 'hs.reload()'
```

**Open the Hammerspoon console:**

```bash
/opt/homebrew/bin/hs -c 'hs.openConsole()'
```

`hs.ipc` is loaded in init.lua, so both commands work without any additional setup.

---

## Config Reference

### transcribe.sh

The script now exports two variables before anything runs:

```bash
export PATH="/opt/homebrew/bin:$PATH"
export HF_HUB_OFFLINE=1
```

`HF_HUB_OFFLINE=1` suppresses a tqdm progress bar that mlx_whisper writes to stderr on every run, including successful ones. Without it, that output bleeds into the error alert text and masks the actual error.

### Hammerspoon config

`hs.pathwatcher` is NOT configured. Edits to `~/.hammerspoon/init.lua` require a manual reload (see diagnostic commands above).

The `hs.alert.show` error surface is at **line 36** of `~/.hammerspoon/init.lua`.

### Model

Model: `mlx-community/whisper-large-v3-turbo`  
Cache: `~/.cache/huggingface/hub/models--mlx-community--whisper-large-v3-turbo` (1.5 GB)  
`HF_HUB_OFFLINE=1` means no network call is attempted on each transcription. If the model cache is missing or corrupted, remove that env var temporarily to allow a re-download.

---

## Not Relevant

macOS built-in Dictation is NOT part of this pipeline. On 2026-10-20, during debugging, the following system preferences were enabled:

- `DictationIMMasterDictationEnabled`
- `DictationIMUseOnlyOfflineDictation`
- `Dictation Enabled`

These are inert with respect to this Whisper setup. Do not go down that road when debugging.
