# The Perch Display Voice Flows v1

## Product rule
Voice is the superpower, not the default mode.
The display should feel quiet until Fábio explicitly asks for help.

## Core principles
- Push-to-talk only
- Transcript first, voice second
- One clear target per interaction
- Fast feedback at every step
- No open-ended chat log on the main screen

## Primary actions
- **Talk to Claudinho**
- **Talk to SideQuest**

## Flow 1: Send a voice message to Claudinho

```text
Tap “Talk to Claudinho”
  -> listening state
  -> capture audio
  -> show transcript preview
  -> send to Claudinho bridge
  -> show “Claudinho is thinking”
  -> receive reply text
  -> optionally auto-play spoken reply
  -> update Latest Reply block
```

## Flow 2: Send a voice message to SideQuest

```text
Tap “Talk to SideQuest”
  -> listening state
  -> capture audio
  -> show transcript preview
  -> send to SideQuest bridge
  -> show “SideQuest is checking that”
  -> receive reply text
  -> optionally auto-play spoken reply
  -> update Latest Reply block
```

## Flow 3: Replay the latest agent note

```text
A fresh agent note appears
  -> user taps play inside the Agent Note card
  -> if audio reply exists, play it
  -> else synthesize speech from latest reply text
  -> keep playback controls inside the Agent Note card
```

## Visual states

### Idle
- three actions visible in the voice dock
- latest reply card visible if present

### Listening
- active button highlighted
- waveform or pulse feedback
- cancel action visible
- no other motion on screen

### Transcript review
- show transcript immediately
- allow quick resend if transcription is wrong
- optional tiny “retry” action, not a big edit screen

### Thinking
- compact status only
- no giant assistant takeover state

### Reply
- Agent Note card updates when there is something fresh to show
- source badge visible
- play / replay action visible inside the card
- dismiss action available so the screen can go back to calm mode

## Autoplay policy
**Recommended default:**
- if interaction started with voice, auto-play response voice
- if interaction started with tap/text later, do not auto-play

## Failure states
- transcription failed
- bridge unavailable
- target unavailable
- no audio output available

In all cases:
- preserve the transcript if available
- show a short human error
- offer a retry action

## Non-goals for v1
- wake word
- background listening
- multi-turn conversation history on-screen
- interruptible barge-in playback
- speaker diarization or fancy assistant voices

## Recommendation
Start with two extremely reliable paths only:
1. talk to Claudinho
2. talk to SideQuest

Everything else can layer on later.
