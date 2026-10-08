# Ride Audio: music and communications priority

Status: design requirements only. No playback or Bluetooth integrations are implemented.

## User story
As a rider, I can listen to my own music through a paired helmet headset. When my intercom receives speech, the app automatically reduces ("ducks") music; when the conversation ends it fades music back to normal. Emergency announcements always take precedence.

## Audio priority
1. SOS, critical safety announcements and active emergency call
2. Phone calls / system call audio (subject to operating-system routing)
3. Ride intercom / push-to-talk (active speech)
4. Spoken navigation prompts
5. Music / podcasts / audiobooks

Navigation versus intercom concurrency, emergency alert volume and channel override must be tested on physical devices.

## Features
- Play owned/local media, podcasts and audiobooks using approved OS media APIs.
- Integrate with existing phone audio sessions and compatible third-party music services where their SDKs and terms permit; do **not** intercept, retransmit, record or mix protected streams.
- "Ride mode" controls: music play/pause, previous/next, intercom on/off, push-to-talk, mute mic, return-to-music.
- Adjustable ducking levels (for example -12 dB, -20 dB, pause) and fade-in/out; sensible default is -18 dB while voice is active.
- Voice activity detection with hysteresis so wind noise does not continuously pump volume; show mic status; optionally require push-to-talk.
- Respect iOS audio-session interruption/ducking and Android audio-focus APIs. Other apps' audio may be ducked or paused via OS coordination, not by arbitrary volume manipulation.
- Headset compatibility: Bluetooth HFP for microphone, A2DP for higher-quality playback where hardware/OS permits. Some headsets fall to mono telephony quality for simultaneous mic + audio. Test Sena, Cardo, generic units.
- On intercom disconnection, safely restore music audio state; don't leave audio permanently muted.
- Wired headsets / phone speaker fallback; avoid surprise speaker output in public.
- User volume controls, hearing-safety defaults and clear indication when audio is active.
- No always-on microphone until user explicitly enters a voice session.

## Acceptance tests
- Music playing -> remote member speaks -> music ducks within an acceptable latency -> fades back after speech.
- Push-to-talk works with screen locked on supported devices; test Apple/Android OS limitations.
- Incoming phone call interrupts ride audio and restores correctly.
- Headset unplug/disconnect during ride; graceful device rerouting.
- No cellular connectivity: music continues locally, intercom reports disconnected (never claims to work offline).
- Safety alert is delivered prominently without pretending receipt or emergency-service dispatch.
- Cross-platform test matrix across iOS, Android, headset vendors, and Bluetooth codecs.

## Legal & UX
Streaming services require licensed APIs and compliance with DRM and terms. Riders should operate controls through voice or large stopped-state controls; never encourage screen use while moving.
