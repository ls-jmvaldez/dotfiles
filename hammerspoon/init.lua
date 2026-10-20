-- Whisper dictation: toggle recording with a hotkey, transcribe with mlx-whisper,
-- type the result into whatever's focused (terminal, Claude Code, etc).
-- Runbook (failure modes, PATH bug explanation, diagnostic commands): ~/whisper/README.md

hs.allowAppleScript(true)
require("hs.ipc")

local rec = {
  isRecording = false,
  task = nil,
  wavPath = "/tmp/whisper-dictation.wav",
}

local function toggleDictation()
  if not rec.isRecording then
    os.remove(rec.wavPath)
    rec.task = hs.task.new("/opt/homebrew/bin/sox", nil, {"-d", "-q", "-c", "1", "-r", "16000", rec.wavPath})
    rec.task:start()
    rec.isRecording = true
    hs.alert.show("Recording...", 2)
  else
    if rec.task then
      rec.task:terminate()
    end
    rec.isRecording = false
    hs.alert.show("Transcribing...", 3)

    -- give sox a moment to flush the wav file to disk before reading it
    hs.timer.doAfter(0.3, function()
      local transcribeTask = hs.task.new(
        "/Users/valdezjm/whisper/transcribe.sh",
        function(exitCode, stdOut, stdErr)
          local trimmed = (stdOut or ""):match("^%s*(.-)%s*$")
          if exitCode == 0 and #trimmed > 0 then
            hs.eventtap.keyStrokes(trimmed)
            hs.pasteboard.setContents(trimmed)
          elseif exitCode == 0 then
            hs.alert.show("No speech detected", 2)
          else
            print("Whisper transcription failed (exit " .. exitCode .. "): " .. (stdErr or ""))
            local snippet = (stdErr or "unknown error"):sub(1, 120)
            hs.alert.show("Whisper transcription failed: " .. snippet, 4)
          end
        end,
        {rec.wavPath}
      )
      transcribeTask:start()
    end)
  end
end

-- keyboard-only fallback: plain F6, unbound by default on non-Apple keyboards, single keypress
hs.hotkey.bind({}, "F6", toggleDictation)
-- program the Logitech G915 G5 key (via Logi Options+/G HUB) to emit F13
hs.hotkey.bind({}, "F13", toggleDictation)

hs.alert.show("Whisper dictation loaded")
