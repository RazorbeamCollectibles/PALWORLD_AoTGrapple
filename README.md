# AoTGrapple

UE4SS Lua mod for Palworld.

AoTGrapple plays a bundled audio file when any grappling gun is fired.

Behavior:

- Plays `grapple.wav` when a grappling gun cable is fired.
- Stops quickly if the shot misses.
- Continues while the player is being pulled by the grapple.
- Stops when grappling ends.
- If the glider is deployed during or just after the grapple, audio continues.
- Stops after gliding ends, the player stops moving, lands, climbs, or stands still.
- Prevents overlapping audio on rapid fire.

Supported items:

- Grappling Gun
- Mega Grappling Gun
- Giga Grappling Gun
- Hyper Grappling Gun

Requirements:

- Palworld
- UE4SS
- Windows

Install:

1. Extract `AoTGrapple` into:
   `Palworld\Pal\Binaries\Win64\ue4ss\Mods`
2. Confirm this file exists:
   `Palworld\Pal\Binaries\Win64\ue4ss\Mods\AoTGrapple\Scripts\main.lua`
3. Start Palworld.

Custom audio:

Replace `grapple.wav` with another WAV file using the same filename.

Test keys:

- `F9`: play audio test
- `F10`: stop audio test
- `F11`: quit audio server safety valve

Notes:

- Audio playback is client-side.
- The mod uses a small hidden PowerShell/.NET audio helper.
- If Palworld hangs while closing, press `F11` before quitting or run `quit.ps1`.
