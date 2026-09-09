---
name: raise-hypotheses
description: Step 4 of offsec-hunter. Cheap, wide fan-out — dispatch many shallow subagents on a fast model to generate vulnerability hypotheses tied to the target vuln class and the mapped sinks. Optimizes recall, not precision. Use when generating vulnerability hypotheses for a specific target and vuln class.
---

# raise-hypotheses — step 4

**Guard:** If `state.json` is absent, stop with "run the `offsec-hunter` orchestrator first".

Generate many candidate vulnerabilities. Optimize for **recall, not precision** — a later
step breaks them. Produces candidates for `hunts/<VULN>/hypotheses.jsonl` (the orchestrator
writes the file).

## Gate

Read `hunts/<VULN>/sinks.json` and `hunts/<VULN>/target.md`. If `sinks.json` is missing
or stale, stop: **"no fresh `sinks.json` — run locate-sinks first."**

## Procedure

Dispatch **many shallow subagents on a cheap/fast model** (see the offsec-hunter platform
guide), each chasing **one** hypothesis tied to the target vuln class, a sink from `sinks.json`, and
the **confirmed delivery vector + attacker position** from `target.md` — e.g. "does any
handler fetch a user-supplied URL without an allowlist?", or "does the file parser trust a
length field from the input file?".

Each subagent returns a **candidate**, not a verdict, and returns it **untagged**: keyed by
`sink`, with the suspected attacker-controlled source, the path/mechanism between them, and
a rationale. Subagents never assign `id` or `family` — under subagent isolation, parallel
subagents can't see each other's ids and would collide. The **orchestrator is the sole id
authority**: it takes each returned candidate and writes the line to
`hunts/<VULN>/hypotheses.jsonl`, assigning the globally-unique `id` (`h-N`) and `family`,
and stamping the current `"round": N`:

```json
{"id": "h-1", "family": "f-ssrf-fetch", "sink": "sink-3", "round": 2, "mechanism": "http.get sink without URL allowlist guard", "suspected_source": "body.url", "path": "POST /fetch -> validate() -> http.get()", "rationale": "no allowlist visible"}
```

This step is **round-aware**: on each round the orchestrator tells you which families to
expand and which mapped sinks are still uncovered. Because a dispatched subagent sees only
its prompt, **inject its context** — pass `output_root`, `target_root`, the exact artifact
paths to read (`hunts/<VULN>/sinks.json`, `hunts/<VULN>/target.md`), the assigned `sink-N` id and
family, and a one-line threat-model summary.

Return a structured completion result to the orchestrator, including the `input_hash` of
`sinks.json`; do not write `state.json`.
