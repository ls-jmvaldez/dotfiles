#!/bin/bash
set -euo pipefail

export PATH="/opt/homebrew/bin:$PATH"
export HF_HUB_OFFLINE=1

WAV_FILE="$1"
VENV="/Users/valdezjm/whisper/.venv"

"$VENV/bin/python" -c "
import sys
import mlx_whisper

result = mlx_whisper.transcribe('$WAV_FILE', path_or_hf_repo='mlx-community/whisper-large-v3-turbo')
sys.stdout.write(result['text'].strip())
"
