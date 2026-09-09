---
name: break-hypotheses
description: Step 5 of offsec-hunter. Deep adversarial validation — dispatch stronger-model subagents that try to break each hypothesis, not confirm it. Keeps only candidates that survive every guard and are reachable per the confirmed threat model. Use when validating and filtering vulnerability hypotheses through adversarial testing.
---

# break-hypotheses — step 5

**Guard:** If `state.json` is absent, stop with "run the `offsec-hunter` orchestrator first".

Adversarially validate each candidate. The job is to **try to break the claim**, not to
confirm it. Produces candidates for `hunts/<VULN>/survivors.jsonl` (the orchestrator writes
the file).

## Gate

Read `hunts/<VULN>/hypotheses.jsonl`. If it is missing, stop:
**"no `hypotheses.jsonl` — run raise-hypotheses first."**

## Procedure

Process only **this round's** hypotheses — lines where `line.round == state.round`; earlier
rounds' hypotheses were already broken (or already survived) in their own round.

For each current-round candidate, dispatch a **stronger-model subagent** (see the offsec-hunter platform
guide) to trace it across files and attempt to refute it:

- Is the source **actually** attacker-controlled?
- Does it **survive every guard/gate** between source and sink?
- Is it reachable **per the confirmed threat model** (the attacker position and delivery
  vector in `target.md`)?
- Does the result meet the **confirmed win condition** (so a DoS or memory-safety crash
  counts when the user scoped it in)?
- Is it **chainable** — does it look like it could chain with another candidate or a
  **dependency bug** (when dependency sinks exist — sinks with `origin: dependency`, see locate-sinks) to reach the
  win condition? A survivor may be part of a multi-step chain (e.g. auth-bypass → RCE).
  **Flag** chainability; the orchestrator assembles the actual chain from the round's
  candidates.

Because a break subagent sees only its prompt, **inject its context** — pass `output_root`,
`target_root`, the exact artifact paths to read (`sinks.json`, `target.md`,
`hypotheses.jsonl`), and the **full fields of the specific candidate** being refuted
(`id`, `sink`, `suspected_source`, `path`, `mechanism`).

Drop anything that fails any check. Each subagent returns its verdict **untagged** — no
`id`, no built `chain`: it keys the survivor by `hypothesis` and `sink`, carrying the
guards examined and why they hold/fail, `severity` + `confidence`, and a **chainability
flag** (which other candidate(s), if any, it looks chainable with, and why) — a subagent
sees only its own candidate, never the round's full set, so it cannot build an ordered
chain. Subagents never assign `id` or `chain` — the **orchestrator is the sole id
authority**: at synthesis it assembles the ordered `chain` (hypothesis ids) from the
round's full candidate set, then writes the survivor line to
`hunts/<VULN>/survivors.jsonl`, assigning the globally-unique `id` (`s-N`) and stamping the
current `"round": N`:

```json
{"id":"s-2","hypothesis":"h-4","sink":"sink-3","chain":["h-7","h-4"],"round":2,"severity":"high","confidence":"medium","guards":"nonce check bypassed via ..."}
```

**Dedup at orchestrator write**: the orchestrator writes survivors during synthesis, after
the `chain` is assembled from the round's full candidate set — so all three key parts
(`hypothesis`, `sink`, `chain`) are known at write time. Before appending, it checks the
survivor key (`hypothesis` + `sink` + `chain`) against existing lines in `survivors.jsonl`.
If a survivor with the same key already exists (e.g. re-confirmed after a redirect, or
reached via more than one route in the same round), skip the append — de-duplicate rather
than write a second line for the same underlying bug. Dedup never happens inside the
isolated break subagent; it can't see other candidates or the assembled chain.

Return a structured completion result to the orchestrator; do not write `state.json`.
