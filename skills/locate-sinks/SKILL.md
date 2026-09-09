---
name: locate-sinks
description: Step 3 of offsec-hunter. Turn the class-agnostic map plus the confirmed threat model into the hunt's task queue — the sinks worth attacking for this vuln class, each with a stable id. This is where security judgment begins. Use when a vuln class and threat model are confirmed and the hunt needs its sink list.
---

# locate-sinks — step 3

**Guard:** If `state.json` is absent, stop with "run the `offsec-hunter` orchestrator first".

This is where **security judgment begins**. Steps 1–2 describe how the target works and
what we are hunting for; this step decides **what is worth attacking** for the confirmed
vuln class, and gives each one a stable id the rest of the hunt traces back to.

Writes `hunts/<VULN>/sinks.json` under the output root.

## Gate

Read `surface-map.json` (target-level) and `hunts/<VULN>/target.md`. If `target.md` is
missing or stale, stop: **"no fresh `target.md` — run scope-target first."**

## Procedure

1. Read the confirmed **vuln class** and **threat model** (attacker position, delivery
   vector, win condition, scope notes) from `target.md`. Everything below is scoped to
   them — a sink that cannot serve the confirmed win condition is not a sink for this
   hunt.
2. Derive candidate sinks from the map:
   - From `flows[]` — each flow's `reaches` location and its `operation`. Classify the
     operation against the confirmed vuln class by **what it does**, not by which API it
     calls: outbound network request → `ssrf`, command or dynamic-code execution → `rce`,
     query construction from concatenated input → `sqli`, template rendering → `ssti`,
     plus deserialization, authz checks, and untrusted parsing. These behaviours exist in
     every language; do not pattern-match on one ecosystem's function names.
   - From `assumptions[]` — an assumption the code relies on but does not enforce is a
     sink when violating it serves the win condition. Record the `asm-N` it came from.
3. Search the target for sinks of the confirmed class that the map's flows did not
   reach. The map is bounded by reachability; this step may widen within the class.
   Record these too — `break-hypotheses` decides whether they are actually reachable.
4. **Dependency sinks (conditional)** — **if** the target vendors its dependencies,
   index high-risk code in them as sinks too, marked `"origin": "dependency"`. Reaching
   the win condition may require chaining a target bug with a dependency bug. The rule is
   "the target ships third-party source in-tree", whatever that looks like in its
   ecosystem — `third_party/`, `vendor/`, `node_modules/`, `deps/`, or a lockfile-declared
   tree are **examples of the pattern, not an exhaustive list**. If no vendored deps are
   present, skip this — emit no dependency sinks and no error.
5. Assign each sink a **stable id** (`sink-1`, `sink-2`, …), globally unique across the
   hunt, so `hypotheses.jsonl`, `survivors.jsonl`, and `findings.json` can reference it.
   Ids are assigned here, never by a subagent.
6. Write `hunts/<VULN>/sinks.json` per the schema in `references/sinks.md`. Return a
   structured completion result to the orchestrator — including the combined
   `surface-map.json` + `target.md` input hash — without writing `state.json`.

This step runs **once per hunt**, not once per round — it re-runs when `surface-map.json`
or `target.md` changes (a rebuilt map, or a steer that redirects the class or threat model).
