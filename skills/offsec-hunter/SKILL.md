---
name: offsec-hunter
description: Use when hunting for externally reachable, exploitable vulnerabilities in a codebase — triggered by an HTTP request, a chain of HTTP requests, or a WebSocket message from an unauth or normal-user session (the default threat model, with non-web targets scoped in at the scope-target checkpoint). Covers SSRF, RCE, SQLi, SSTI, auth-bypass, IDOR and other high-impact classes. Triggered by /offsec-hunter with a vuln-type argument.
---

# offsec-hunter — orchestrator

This is part of an **authorized** security task: identify vulnerabilities that are
**externally reachable and exploitable** per the target model confirmed in `scope-target`.

**The goal is not code review. The goal is to break the target.**

This skill is the **orchestrator**. It runs six composable skills, each gated on the
previous one's file artifact:

1. **REQUIRED SUB-SKILL:** Use the `map-attack-surface` skill → `surface-map.json`
   — **comprehension only: no vuln classes, no risk verdicts, no guard analysis, no sink hunting.**
2. **REQUIRED SUB-SKILL:** Use the `scope-target` skill → `hunts/<VULN>/target.md`
   — confirm the vuln class and threat model; interactive asks, headless logs.
3. **REQUIRED SUB-SKILL:** Use the `locate-sinks` skill → `hunts/<VULN>/sinks.json`
   — **security judgment begins here**; sole assigner of `sink-N` ids.
4. **REQUIRED SUB-SKILL:** Use the `raise-hypotheses` skill → `hunts/<VULN>/hypotheses.jsonl`
   — cheap wide fan-out, optimise recall not precision.
5. **REQUIRED SUB-SKILL:** Use the `break-hypotheses` skill → `hunts/<VULN>/survivors.jsonl`
   — adversarial: try to refute each claim, not confirm it.
6. **REQUIRED SUB-SKILL:** Use the `prove-exploit` skill → `hunts/<VULN>/findings.{md,json}` + `pocs/`
   — no PoC, no finding.

User-facing mental model: **understand → goal → hunt → exploit**.

Steps 1–2 are comprehension and scoping and carry no security verdicts. **Security
judgment begins at `locate-sinks`.**

## How this skill runs

Instruction-driven and platform-neutral. Map every action ("use a step skill", "dispatch a
subagent", "select a model where the platform allows it") to your platform's tools per the
**offsec-hunter platform guide** (`references/platform-tools.md`). Artifact layout, the
two roots, `state.json`, and the gating/staleness rules are defined in the **offsec-hunter
artifacts guide** (`references/artifacts.md`).

### Enforcement — read this first

Reliability comes from **artifact-gating**, not trust:

1. **Before step 1**, resolve the two roots and the run mode, then write `state.json`.
   Every later step reads them from there. Do this before any other action. Write it
   **without a `vuln` field** — `scope-target` adds that in step 2. `state.json` is step 1's
   only input channel, so leaving the class out of it is what keeps step 1 class-blind.
   The orchestrator is the **sole writer and control plane for `state.json`**. Each step
   reads state when needed and returns a structured completion result; it never updates
   state itself.
2. **Before step 1, also read the artifacts guide and the platform guide**
   (`references/artifacts.md`, `references/platform-tools.md`). The first defines
   `state.json`, the artifact tree, and the gating rules; the second maps this skill's
   actions onto your platform's real capabilities. Neither is optional.
3. **Each step is a separate skill — use it, do not do its work yourself.** The step list
   above gives each step's name and its single hardest constraint; the skill itself carries
   the procedure, the gate, and the schema. Never execute a step from the one-line summary.
   Announce each one as you start it: "Using `<skill>` to <purpose>".
4. Create one task/todo per step and complete them in order.
5. Each step writes a file artifact; the next step begins by reading it. Never start a
   step whose input artifact is missing or stale.

### Roots — resolve once

Resolve two roots and record them in `state.json`; every step reads them from there:

- **Target root** — the code being hunted. All artifact paths are relative to it. Never
  assume it equals the current directory — confirm it.
- **Output root** — where `.offsec-hunter/` is written. Default
  `<target-root>/.offsec-hunter/` (gitignored). Override with an explicit out-dir, or fall
  back to `~/.offsec-hunter/<target-id>/` when the target tree is read-only.

### Mode — interactive or headless

Declare the run mode and record it in `state.json`:

- **interactive** (a human is present): `scope-target` stops and asks the user to
  confirm/edit the target model.
- **headless** (autonomous/agent run): `scope-target` accepts its proposed model and logs
  the assumption loudly. No step blocks on input.

### Progress

Print a compact progress line read from `state.json` (e.g. `✅ 1–2  ▶ 3`) so a returning
human or a resuming agent knows the next action.

## Round loop (steps 4–5)

Steps 1 (map), 2 (scope) and 3 (locate) run once. Steps 4 (raise) and 5 (break) are the
body of a **round loop**. Step 6 (prove) runs once at loop exit. With a single productive
round this is exactly the old single-pass flow.

**Initialization:** Before the first `raise-hypotheses` run, the orchestrator initializes
`round=1`, `dry_streak=0`, `families=[]`, and `round_log=[]` in `state.json`.

The loop **drives raise/break by round**, independent of staleness. They re-run every
round regardless of whether `target.md` changed; the staleness gate applies only to
steering (user-driven redirects).

Each round:

1. **Read `state.json`** for the resume point (`round`, `dry_streak`, `families`). This is
   what makes the loop **resumable** — a fresh or compacted orchestrator continues instead
   of restarting. The orchestrator records every step completion in `state.json` with a
   `status` field and, for loop steps, `last_round`; re-running a step for a round it
   already recorded is a **no-op** (already recorded in `last_round`), so crashes and
   resume never double-append.
2. Run `raise-hypotheses` then `break-hypotheses` for this round.
3. **Synthesize** (orchestrator, reading only compact summaries + this round's jsonl —
   never full subagent transcripts):
   - Count new survivors and new families.
   - **Assemble chains** from the round's candidate set: for each chainable survivor, the
     orchestrator constructs the ordered `chain` field (a list of hypothesis ids) by
     matching it with other survivors that can chain together. Break subagents only flag
     chainability; the orchestrator assembles the multi-step chain.
   - Mark any family that produced nothing new as **blocked** (materially-new means a
     **distinct sink** or a **distinct guard-bypass mechanism**, not a distinct label). A
     blocked family reopens **only when** a hypothesis names a guard or step absent from
     that family's recorded mechanisms — synthesis makes this determination by comparing
     the `mechanism` field machine-to-machine, never by comparing prose or labels.
   - **Redirect**: pull agents off crowded/blocked families and point them at sinks in
     `sinks.json` no family covers yet; keep at least one agent on each still-productive incompatible
     route so routes stay alive across rounds.
   - Append a one-line entry to `state.json.round_log`. Increment
     `dry_streak` on a dry round; reset it to 0 on a productive round (one that produced a
     new survivor or a materially-new family).
4. **Stop rule**: exit after **2 consecutive dry rounds** (a dry round = no new survivor
   AND no materially-new family). Soft backstop: log a loud warning when `round > 6` (the dry-round
   rule still governs; the warning is auditability, not a hard cap).

### Context-injection contract (critical)

A subagent sees only its delegation prompt plus whatever always-on project context the
platform auto-loads (`CLAUDE.md` on Claude Code, `AGENTS.md` on Codex) — not the orchestrator's invoked
skills, conversation, or files already read. Every raise/break delegation prompt MUST
**inject**: `output_root` and `target_root`, the exact artifact paths to read, the assigned
`sink-N` id + its family, and a one-line threat-model summary. The family registry stays
orchestrator-only; a subagent receives only its slice in-prompt.

**Step 1 is the inverse case: delegated and deliberately class-blind.** On platforms where
the skill forks its own context, that isolation is automatic. Where it does not, dispatch
`map-attack-surface` to a subagent explicitly. Its prompt carries `target_root`,
`output_root`, and the artifact path — and **must not contain the vuln class, the threat
model, or any word naming a vulnerability category.** Do not put the class in step 1's
todo or plan label either; "Fresh RCE hunt" as a heading is itself contamination.

Why isolation rather than instruction: the map is target-level and reused by every
vuln-class hunt against the same commit. An agent that knows the class cannot produce a
class-agnostic map — it will select the flows that class cares about and frame boundaries as
defences against it, while believing it is doing comprehension. Withholding the class is the
mechanism; asking the agent not to think about it is not.

**The orchestrator is the sole id authority.** Under subagent isolation, parallel raise/break
subagents cannot see each other's ids and would collide if left to invent their own. So
subagents never assign `h-N`, `family`, or `chain`: they return untagged judgments keyed
by `sink` — `mechanism`/`rationale` (raise) or `severity`/`confidence` + a chainability
flag (break), never a built chain. Only the orchestrator assigns globally-unique `h-N`
ids and `family` ids, assembles the ordered `chain` from the round's full candidate set,
dedups, and writes the line to `hypotheses.jsonl` or `survivors.jsonl`.

### run.md dashboard

The orchestrator **regenerates** `run.md` from `state.json` + `findings.json` on **any** step-6
completion (loop exit or steered re-run). The dashboard shows: rounds executed, the family
registry (open/blocked + counts), the per-round lines, and the final findings with their
trace ids. This single-owner regenerate ensures consistency across steered re-runs (idempotent,
no appending).

## Vuln class

Hunt for: **the vuln class the user provided when invoking this skill (or `broad` if none)**

The chosen class is confirmed inside `scope-target` and written into `target.md` and
`state.json`. If no class was provided: interactive → `scope-target` asks; headless →
default to `broad` and log it.

**Hold the class out of step 1.** Note where this section sits: everything above it — the
map — is built before the class is recorded anywhere step 1 can reach. Keep it that way.

## Scope — the default threat model (a proposal, not a fixed rule)

The default `scope-target` starts from; confirmed or overridden per target there, never
assumed silently:

- Default attacker position: **unauthenticated or normal-user**.
- Default delivery vector: an external request — **HTTP, a chain of HTTP requests, or a
  WebSocket message**.
- Default impact: high-impact classes (RCE / SSRF / SQLi / SSTI / auth-bypass / IDOR / …).

Held regardless of target and **not** softened at the checkpoint:

- **m2m-auth-gated** calls are **out of scope** — UNLESS an auth bypass lets an outsider
  reach them. That bypass is itself the finding.
- Do **not** lean on memory artifacts or other projects' data. Build the model from, and
  validate against, this target's actual current code.

## Budget orchestration

Cap concurrent subagents. Where the platform supports per-task model selection, use a
cheap/fast model for breadth (`raise-hypotheses`) and escalate to a stronger model only on
survivors (`break-hypotheses`), reserving the strongest model for `prove-exploit`. Where it
does not — see the platform guide — every step runs on the session model, and control comes
from artifact gating and the dry-round stop rule rather than from cost tiering. The biggest
saving on any platform is reusing a fresh map (`map-attack-surface` skip).

## Steering — redirecting a run

A completed run is not the end. If the user is unsatisfied, redirect by editing the
artifact at the right level and re-running only the steps that go stale:

| Dissatisfaction | Edit | Re-runs |
|---|---|---|
| Missed an entry point or flow | `surface-map.json` | 1 → 2–6 |
| Wrong goal / class / attacker position | `target.md` | 3–6 |
| Missed a sink | `sinks.json` | 4–6 |
| Add or restore a lead | `hypotheses.jsonl` | 5–6 |
| Wrongly killed a candidate | annotate the dropped candidate | 5–6 (that one) |
| PoC doesn't fire | the finding | 6 (that finding) |

After step 6: interactive → offer "not satisfied? tell me how to redirect"; headless →
accept a feedback string. Map the feedback to the artifact level above, edit/annotate that
artifact (so the staleness check fires), append the steer to the `state.json` steer log,
and re-run from there. Steered re-runs **merge additively** (see `prove-exploit`); they
never overwrite a confirmed finding.
