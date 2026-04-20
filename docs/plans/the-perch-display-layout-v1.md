# The Perch Display Layout v1

## Product thesis
The Perch Display is not a dashboard full of modules.
It is a **calm room surface** that answers what matters now, what is next, and what to offload.

## Design rules
- Landscape first
- Readable from across the room
- No tabs in v1
- Max 4 primary content blocks on screen
- Weather and clocks are persistent context rails, not cards
- Voice is always available, but never always-listening
- Text should feel brief, legible, and alive

## Primary target
- **First host:** Meta Portal
- **Assumed posture:** landscape, docked, always visible
- **Secondary hosts later:** browser kiosk, old iPad, Android tablet

## Screen anatomy

```text
┌──────────────────────────────────────────────────────────────────────────────┐
│ 16:29 Lisbon                      Today 19° / 13° ☁   Tomorrow 21° / 14° ☀ │
│ Mon Apr 13                        08:29 SF              12:29 Vitória       │
├──────────────────────────────────────────────────────────────────────────────┤
│ NOW / BRIEFING                    │ NEXT                                    │
│                                   ├──────────────────────────────────────────│
│ Design review in 28m              │ GUIDANCE                                │
│ Context: review Liquid Glass      │ “Protein is light today. Dinner can     │
│ options before call               │ still recover the day cleanly.”         │
│                                   ├──────────────────────────────────────────│
│ Open loop: alpha lane wording     │ AGENT NOTE (conditional)                │
│ still needs approval              │ Claudinho: “I already drafted the       │
│                                   │ summary. Want me to send it?”           │
│ Suggested action: ask Claudinho   │ [ Play voice ] [ Show transcript ]      │
│ for the 30-second prep brief      │ [ Dismiss ]                             │
│                                   │                                          │
│ Watchout: protein is light        │                                          │
│ dinner needs intention            │                                          │
├──────────────────────────────────────────────────────────────────────────────┤
│ [ Talk to Claudinho ]                        [ Talk to SideQuest ]           │
└──────────────────────────────────────────────────────────────────────────────┘
```

## Zone-by-zone spec

### 1. Header rail
Persistent, always visible.

**Left**
- local time, large
- current date, smaller

**Right**
- weather today
- weather tomorrow
- secondary clocks: SF + Vitória

**Rules**
- do not rotate this area
- do not hide it during interaction
- secondary clocks should be smaller and quieter than the main clock
- use city names, not generic labels like “Brazil”

### 2. Now / Briefing block
The screen’s anchor and the most important area after the header rail.

This should answer:
- what is the next time-sensitive thing?
- why does it matter?
- what context should I know before it happens?
- what one action would help right now?

**Recommended contents**
1. next calendar event / focus item
2. short context note or meeting brief
3. one actionable insight or open loop
4. macros status or SideQuest watchout, whichever is more urgent

Examples of useful context:
- who is in the meeting
- what decision is needed
- one open loop to resolve before it starts
- one note from SideQuest or Claudinho that changes how you should approach it

**Rule**
This block should have enough vertical space for 4 meaningful lines plus one highlighted action. Do not compress it into a tiny status list.

### 3. Right rail
The right side is the secondary rail. It should stack three smaller modules:
- **Next**
- **Guidance**
- **Agent Note**

This keeps the left side focused on briefing depth while the right side handles supporting context.

### 4. Next block
The upcoming runway for the day.

**Contents**
- next 2-4 meaningful day items
- top Things items
- one waiting-for if important

**Rule**
This is not a full task list. It is the next useful slice.

### 5. Guidance block
One sentence or short paragraph that helps steer the day.

Examples:
- “Protein is light today. Dinner can fix it.”
- “You have a gap after 15:00. Good slot for admin.”
- “Rain tonight. If you want a walk, go before 18:00.”

**Why this name**
It is clearer than “Nudge” and calmer than something bossy like “Action” or “Directive”.

**Rule**
Exactly one guidance message at a time.
No carousel.
No stack of tips.

### 6. Agent Note block
This should not be a permanent fixture. It is a **conditional continuity card**.

**What goes here**
- the latest useful reply from Claudinho or SideQuest
- a proactive agent note that is fresh and relevant
- the result of the most recent voice interaction

**Contents**
- source: Claudinho or SideQuest
- latest reply preview
- play voice action
- show transcript action
- dismiss action

**Rule**
Show this only when there is something fresh, unread, or recently requested. On a quiet day, this block can disappear entirely and give the screen more breathing room.

### 7. Voice dock
Persistent bottom action row.

**Buttons**
- Talk to Claudinho
- Talk to SideQuest

**Interaction**
- tap to start recording
- show listening state clearly
- show transcript immediately after capture
- reply appears in the Agent Note block when relevant
- replay belongs inside the Agent Note block, not as a third permanent dock action

## Interaction states

### Idle state
Default.
Everything calm, ambient, readable.

### Listening state
Voice dock expands slightly.
Show:
- active target
- recording state
- cancel affordance

### Thinking state
Show subtle feedback only.
No giant spinner wall.
Suggested copy:
- “Claudinho is thinking”
- “SideQuest is checking that”

### Reply state
Latest Reply block updates.
If the request started in voice, auto-play voice reply unless muted.

## Content constraints

### Maximum visible facts rule
The screen should not ask the user to parse more than about 7 distinct facts at once.

### Summarization rule
If a source has more than 3 items worth showing, the source must summarize before rendering.

### Emotional tone
The display should feel:
- calm
- competent
- lightly warm
- never noisy

## Non-goals for v1
- full chat interface
- browsing the full calendar
- browsing all Things tasks
- editing macros directly from the Portal
- generic widget customization
- multiple tabs or pages
- a permanent always-visible reply panel when there is nothing fresh to show

## Questions to iterate with the user
1. Does the Nudge block deserve full width, or should Latest Reply be larger than Nudge?
2. Should the voice dock be icon-first or text-first?
3. Should “Read latest aloud” be a separate action or part of the Latest Reply card?
4. Do we want a small photo/avatar treatment for Claudinho and SideQuest, or keep the surface text-only and quiet?
5. Is weather best at top-right, or should it become a slim left-to-right strip under the clock rail?

## Current recommendation
Keep the layout above, with three strong priorities:
- a full-height left-side Now / Briefing block with real room for context notes
- a stacked right rail for Next, Guidance, and Agent Note
- only two permanent voice actions in the dock

That gives the product the right center of gravity:
- context rail at the top
- deep briefing on the left
- supporting context on the right
- voice capture at the bottom
