# How the ROSA Score Will Be Calculated — A Plain-Language Walkthrough

This explains the logic behind the ROSA (Rapid Office Strain Assessment) score
this app will calculate from a single photo of someone at their desk. It's
written for someone who isn't building the code, but wants to genuinely
understand *how* and *why* the score comes out the way it does — so you can
sanity-check results, explain them to others, or notice when something looks
off.

---

## 1. What is ROSA, and why are we using it?

ROSA ("Rapid Office Strain Assessment") is a published, peer-reviewed method
(Sonne, Villalta & Andrews, 2012) that ergonomists use to quickly estimate how
risky an office desk setup is for someone's body — chair, monitor, keyboard,
mouse, all of it. Normally, a trained person watches someone work for a while,
fills out a checklist by hand, and arrives at a single risk number from
**1 (lowest risk) to 10 (highest risk)**.

This app automates that process: instead of a human watching and scoring by
hand, it takes one photo of the person at their desk, automatically finds the
key points on their body (nose, ears, shoulders, elbows, wrists, hips, knees,
ankles — this is called "pose detection"), and then runs the *same kind of
scoring logic* an ergonomist would use — based on geometry measured from that
photo, plus a few questions the person answers beforehand (how many hours they
sit, what kind of mouse/monitor setup they have, etc.).

The scoring logic we're following is a faithful mirror of a method that has
been checked against 71 real reference photos and matched verified expert
scores (within 1 point) on every one of them — so this isn't a rough
approximation, it's a tested, established calculation.

---

## 2. The big picture: four stages from photo to score

Think of the whole calculation as a pipeline with four stages:

```
 PHOTO + ANSWERS
       │
       ▼
 ① MEASURE   →   ② RATE   →   ③ COMBINE   →   ④ INTERPRET
       │              │              │                │
  raw angles      1–3 risk      official          final 1–10
  & distances     ratings per   lookup-table      number +
                  body part     cascade           risk label
```

1. **Measure** — From the detected body points, work out some basic geometric
   facts: how bent is the knee, how far does the back lean, how far forward
   does the head poke, and so on.
2. **Rate** — Turn each raw measurement into a small risk rating — usually
   **1 (fine), 2 (somewhat risky), or 3 (quite risky)** — for that one part of
   the body, using fixed threshold values.
3. **Combine** — This is the part that makes ROSA *ROSA* rather than just
   "add some numbers up." The individual ratings are run through a cascade of
   official reference tables (published lookup charts from the original
   research) that combine them into section scores, and then combine those
   section scores into one final number. This matters because certain
   *combinations* of issues are riskier together than the sum of their parts —
   the tables encode that relationship.
4. **Interpret** — The final number (1–10) is translated into a plain-English
   risk label — Low / Medium / High / Very High Risk — plus a flag for whether
   the setup needs to change.

Let's walk through each stage.

---

## 3. Stage 1 — What gets measured

The app will look at where eight body points sit in the photo — **nose, ear,
shoulder, elbow, wrist, hip, knee, ankle** — all taken from whichever side of
the body the camera can see best. (If the person is angled slightly, the app
automatically figures out which side is more clearly visible and measures from
that side, rather than guessing from a half-hidden one.)

From those points, it works out things like:

- **How bent is the knee?** (the angle formed at the knee, between the hip and
  the ankle) — tells us whether the chair height looks about right.
- **How far does the back lean** away from straight-up-and-down? — tells us
  whether the person looks supported by their backrest, or is leaning/slouching.
- **Is the head tipped back, or hanging forward/down?** — several separate
  measurements compare the relative positions of the nose, ear and shoulder to
  work out *which kind* of neck posture issue (if any) is happening: tipped
  back, poking forward ("turtle-necking"), or hunched down.
- **Are the shoulders hiked up toward the ears?** — a sign the person isn't
  resting their arms on armrests.
- **Is the wrist bent upward relative to the elbow?** — a sign of an awkward
  typing position (called "wrist extension").
- **Is the hand reaching sideways, away from the body?** — a sign the mouse
  sits somewhere uncomfortable to reach.

All of this is pure measurement — angles in degrees, or how far apart two
points sit as a share of the photo's size (so, roughly speaking, "0.05" means
"about 5% of the image's height/width apart"). Nothing judgmental happens yet;
that's the next stage.

---

## 4. Stage 2 — Turning measurements into risk ratings

Each raw measurement from Stage 1 gets compared against fixed threshold values
— taken from the validated reference, not invented for this app — and turned
into a small risk rating. Here's what that looks like, body part by body part:

### Chair — seat height
Based on how bent the knee looks:
- Looks neutral → **rating 1**
- A bit too bent (chair sits low) *or* a bit too straight (chair sits high) →
  **rating 2**
- Legs almost fully extended, as if the feet can't reach the floor →
  **rating 3**

*Backup plan:* if the knee or ankle isn't clearly visible in the photo (say,
hidden behind a desk), the app falls back to a rougher estimate based on how
far above or below the hip the knee sits — so a partially-blocked photo
doesn't produce a wild, meaningless reading.

### Chair — backrest support
Based on how far the back leans from upright:
- Fairly upright → **rating 1**
- Leaning noticeably (more than roughly 28°) → **rating 2** — suggests the
  backrest isn't doing its job

### Chair — armrests
Based on whether the shoulders sit hiked up close to the ears:
- Shoulders relaxed and down → **rating 1**
- Shoulders visibly raised → **rating 2** — suggests the arms aren't resting
  on armrests properly

### Monitor — neck posture
This one weighs several signals together, checked in this order, to identify
*which* problem (if any) best describes what's happening:
1. Head tipped noticeably backward → **rating 3**
2. Head pulled down close to the shoulders *and* looking down →
   **rating 3** (a more severe hunch)
3. Just looking down at the screen by a fair amount → **rating 2** (mild)
4. Head poking forward of the shoulders ("turtle neck") → **rating 2**
5. None of the above → **rating 1** (neutral)

### Keyboard — wrist position
Based on whether the wrist sits noticeably higher than the elbow (known as
"wrist extension" — a recognised strain risk while typing):
- Wrist level with, or below, the elbow → **rating 1**
- Wrist somewhat raised → **rating 2**
- Wrist clearly raised → **rating 3**

### Mouse — how far the hand reaches
Based on how far sideways the hand sits from the shoulder:
- Comfortably close → **rating 1**
- Noticeably reaching → **rating 2**

A couple of adjustments apply here: if the person doesn't use a mouse at all
(say, they work on a laptop trackpad), this check is skipped and a neutral
rating is used instead; and if they use a dual-monitor setup, the rating is
nudged up by one notch — because dual-monitor setups typically involve more
reaching and turning toward one screen or the other.

> **Note on "phone usage":** the original ROSA checklist also includes a
> rating for how a person handles their *desk phone* (e.g. cradling a handset
> between ear and shoulder). We're intentionally leaving that out — it's a
> *behavioural habit* observed over time, not something a single photo can
> show. (This is a completely different "phone" from the device used to take
> the assessment photo itself — that one's positioning is handled separately,
> by the tilt/rotation/height checks that run before the photo is captured.)

---

## 5. Stage 3 — Combining ratings via official reference tables

This is the part that's easy to misread if you've only seen simple "add up the
points" scoring systems: **ROSA does not add these small ratings together.**
Instead, it looks them up in a sequence of pre-published reference tables —
think of them like a tax bracket chart or a BMI chart, where you find your row
and column and read off the answer. The original researchers built these
tables specifically because *certain combinations of issues compound risk* in
ways a simple sum wouldn't capture.

Here's the sequence the calculation will follow:

1. **Chair section** — the seat-height rating and the combined armrest +
   backrest rating are looked up together in "Table A," producing a chair
   section score. A small adjustment is then folded in based on how long the
   person typically works at this desk (see below).
2. **Monitor section** — the neck-posture rating is looked up in "Table B,"
   producing a monitor section score.
3. **Keyboard & mouse section** — the mouse rating and keyboard rating are
   looked up together in "Table C," producing a peripherals-input section
   score.
4. **Peripherals combined** — the monitor section score and the
   keyboard/mouse section score are combined via "Table D," which simply takes
   *whichever of the two is worse*. The reasoning: if either your monitor setup
   or your keyboard/mouse setup is risky, that's the thing dragging your
   overall peripherals experience down — averaging it together with the better
   score would just hide the problem.
5. **Final score** — the chair section score and the combined peripherals
   score are combined the same way, via "Table E" — again, whichever one is
   worse "wins" and becomes the headline number.

So the final number is best read as: *"how bad is your worst area, once you
account for how the smaller issues within it interact?"* — not an average, and
not a simple total.

### The "how long do you work like this" adjustment
Before any of this runs, the person answers a couple of quick questions: how
many hours a day they're at their desk, and how often they take breaks. If they
report long stretches with infrequent breaks, a small risk bump gets folded
into the section scoring — reflecting the well-established idea that
*sustained* awkward posture is riskier than brief, occasional awkward posture.
If they report shorter sessions with regular breaks, no bump is applied.

---

## 6. Stage 4 — What the final number means

The final score will land somewhere from **1 to 10**, and will be translated
into a plain-English label:

| Score | Risk Level | What it suggests |
|---|---|---|
| 1–2 | **Low Risk** | Setup looks fine — no action needed |
| 3–4 | **Medium Risk** | Some room for improvement |
| 5–6 | **High Risk** | Changes recommended |
| 7–10 | **Very High Risk** | Changes strongly recommended, ideally soon |

A score of **5 or higher** also raises a simple "this needs attention" flag
that the app can use to prompt the person toward making changes.

Alongside the final number, the app will keep every intermediate measurement
and rating (knee angle, back lean, neck-posture readings, and so on) — so the
person, or whoever reviews their results, can see *exactly which* part of their
setup is driving the score, rather than being handed a mystery number.

---

## 7. A few things worth knowing about this approach

- **It judges a single photo, not a working session.** The original ROSA
  method is meant to be filled in by someone watching a person work over time —
  which lets a human assessor notice *habits* (for example, does this person
  often cradle a desk phone between their ear and shoulder?). A single photo
  can only capture a snapshot of posture, not a behavioural habit — so the
  calculation deliberately leaves out anything that genuinely can't be judged
  from a still image (see the phone-usage note above).
- **The body side is chosen automatically.** If the person is angled toward
  the camera, the app works out which side of their body is more clearly
  visible and bases every measurement on that side, rather than trying — and
  failing — to measure a half-hidden limb.
- **It tries to stay sensible with an imperfect photo.** When a body part is
  partly hidden (say, the ankle is behind a desk), the calculation has fallback
  logic so it still produces a reasonable estimate instead of an obviously
  wrong one.
