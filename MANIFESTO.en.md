# Why I wrote Rubis

One evening I wanted to hear an album. The whole thing, in order, the way it was released.

I opened my player and the album wasn't there. What was there: a big "keep listening" tile, a mix built out of my last week, rows of covers picked for me. The album itself was three screens away, behind a search field.

I closed the player and opened an editor.

I did finish the album that evening. Much later than I planned.

## The record is already mixed

An engineer I will never meet sat with this file and made a thousand decisions. What to cut, what to keep, how long to hold the silence before the last track. He did it in a room that took years to tune, on gear I don't own.

Everything that happens to the file after that is someone else's opinion on top of his work. Usually someone who never heard the session.

Rubis has no opinion. The device follows the track's sample rate instead of bending the track to fit. The system mixer is taken out of the way wherever the hardware allows it. Volume turns the knob on the DAC itself, so no sample is ever multiplied by a number. Between the file and the converter there is nothing I can't name.

And when something is there, the player says so. The bar at the bottom states what is actually happening: the file's rate, the device's rate, exclusive access or a shared output where your mail notification will land next. No green checkmarks, no "HD" badge painted over a resample.

There is a setting that makes the player refuse to play at all rather than play something altered. It ships off, because it is inconvenient. I turn it on when I sit down to listen for real.

## Lying to yourself is the easy part

Write "bit-perfect" in the interface, look at your own label, feel good. I know I'm capable of that, so the proof lives outside the interface.

Twenty-four test files — 44.1 through 192 kHz, sixteen and twenty-four bit, sine and white noise — go out through a loopback device and come back into the machine, and the recording is compared with the original sample by sample. The rule is simple and fairly punishing: until the check passes in full, no line of the audio engine counts as written. Right now it is twenty-four out of twenty-four, and the tool that proves it ships inside the app.

Second, the receipt. On any playing track the player writes out, in plain text, exactly what stands between the file and the DAC, and signs it with a key belonging to this install. That isn't for a forum thread. It's so that a year from now, after I touch the engine at one in the morning, I don't take my own word for it.

## Nothing leaves the machine

There is no telemetry here. Not because I promise it, but because there is nothing to collect with: the code that would do it doesn't exist in the project.

Promises are cheap, so there is a ledger. Every outgoing connection: where, why, how it ended, how many bytes. On a clean install it says that nothing has left the machine. That is the only privacy claim I'll defend, because the code writes it, not me.

Album notes stay silent until you switch them on. The player does fetch its own updates — that one is my call, and it shows up in the same ledger, first line.

## The disk you unplug

Pull the external drive and the tracks go grey. They don't disappear. History stays, playlists stay, nothing gets tidied away "for consistency." Plug it back in and everything returns. A server that stops answering behaves the same way: its music dims and waits.

No album on this shelf vanishes overnight because of somebody else's licensing dispute.

## What isn't here

A feed. A "made for you" section. Play counts in your face. Red dots on the icon. A polite suggestion to listen a little longer while I'm here anyway.

Nothing on screen exists to keep me in the app. A good tool disappears: it opens in a fifth of a second, remembers where I stopped, hands the audio to the DAC I picked, and shuts up.

## Who this is for

Me. No pricing, no roadmap, no target audience. The player was written around one library and one DAC, and half of its decisions are the residue of specific evenings. Seventy-eight source folders that dictated the window layout. A night spent on an AppKit exception that only fired against a live library. A startup measurement that meant reaching into my own window from inside the process — 208–219 ms, if you're curious.

The code is open for one reason: the signal path is one of the few things in this field worth reading with your eyes instead of taking on faith. If it's useful to someone else, good. If not, the album still sounds the way it was mixed.

## Check my work

Every claim above is checkable in the code. Here's where to look.

| Claim | Where in the code |
| --- | --- |
| The device follows the track's rate; the mixer steps aside under exclusive access | `PlaybackEngine/Player.prepareDevice`, SPEC §4.2 |
| Volume is hardware, not software | `Player.deviceVolume` / `setDeviceVolume`, SPEC §4.4 |
| The badge and popover report the real path, resampling and shared output included | `App/Scenes/TransportBar.swift`, `OutputStatus` |
| Refusing to play instead of altering the audio, off by default | `SampleRatePolicy`, `rateFallback = .refuse` |
| 24 fixtures: 44.1–192 kHz × 16/24 bit × sine and noise | `Tools/make-fixtures.sh`, `Tools/audio-verify` |
| The signal path receipt is signed with a per-install Ed25519 key | D-012, `EscapementCore/ReceiptSigning`, verify with `audio-verify --verify-receipt` |
| The ledger of outgoing connections | Settings → Network, `EscapementCore/NetworkLedger` |
| Album notes are off by default | Settings → General → Album notes |
| A missing file dims but survives in playlists and history | D-004, `track.unavailable` |
| A silent server dims only its own tracks | SPEC §6.3, `TrackRepository.setUnavailable` |
| Startup in 208–219 ms | measured on a MacBook Pro M5 Max, SPEC §12 |
