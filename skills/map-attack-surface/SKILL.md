---
name: map-attack-surface
description: Step 1 of offsec-hunter. Build or refresh a reusable, commit-stamped model of how a target works — entry points, trust boundaries, input flows, and the assumptions the code makes. Comprehension only — no vulnerability classes and no risk verdicts. Reuses a fresh map automatically. Use when starting an offsec-hunter run or refreshing a target's map.
context: fork
agent: general-purpose
background: false
---

# map-attack-surface — step 1

**Guard:** If `state.json` is absent, stop with "run the `offsec-hunter` orchestrator first".

Goal: a structured model of **how the target works** — how external input enters, where
it flows, what boundaries it crosses, and what the code assumes.

**You run in an isolated context, deliberately.** This step is forked so it cannot see the
orchestrator's conversation — including which vulnerability class the run is hunting. That
blindness is the point: the map is target-level and reused across classes, and an agent that
knows the class cannot produce a class-agnostic map. Your only inputs are `state.json`
(`target_root`, `output_root`) and the target code. `state.json` carries no `vuln` field at
this stage; if you find one, ignore it — it is not yours to read.

**Comprehension only.** Do not assign vulnerability classes, do not rank risk, and do
not judge whether a check can be bypassed. Record what the code *does* and what it
*assumes*. The security lens is applied by `locate-sinks` once a vuln class is
confirmed — forming verdicts here is premature, because the class is not chosen until
step 2.

Concretely, three things you must not do:

- **Do not search for execution, fetch, query, or deserialization primitives by name** in
  order to *find* interesting code. Start at entry points and follow input to wherever it
  lands. Pattern-hunting for dangerous calls is `locate-sinks`' job, and doing it here is
  what silently turns the map into a single-class map.
- **Never write a verdict word** — `critical`, `dangerous`, `vulnerable`, `exploitable`,
  `unsafe`, `injection` — or any vulnerability class name into the artifact.
- **`assumptions[]` records what the code relies on, never whether that reliance is safe.**
  "assumes the caller already validated `url`" is comprehension. "the regex is sufficient to
  prevent injection" is a verdict — the exact judgment `break-hypotheses` exists to make.

**Bound the stage by reachability.** Record only what external input can plausibly
reach, and stop there. Reachability is a factual property of the code, not a security
verdict, and it is what keeps this step from becoming an unbounded read of the whole
codebase.

**Assume nothing about the target's language, framework, or ecosystem.** Describe
operations by what they *do* — "issues an outbound network request", "constructs a query
from concatenated input", "starts a subprocess", "renders a template" — never by a
concrete API name. Paths and extensions in the schema are illustrative placeholders;
infer the target's real conventions from the target itself.

This step writes `surface-map.json` under the output root (see the offsec-hunter
artifacts guide). It has no input artifact — it is the first step. The map is
target-level and class-agnostic, so every vuln-class hunt against this commit reuses it.

## Procedure

1. Get the current commit: `git rev-parse HEAD`.
2. If `surface-map.json` exists and its `commit` equals `HEAD` → the map is **fresh**: load
   it and stop (downstream steps reuse it).
3. Otherwise build/refresh the map. Identify:
   - **Entry points** — HTTP routes, WebSocket handlers, RPC handlers, message consumers,
     scheduled jobs, parsed input files, CLIs, IPC/sockets, local services. Assign stable
     `ep-N` ids.
   - **Trust boundaries** — unauth ↔ session ↔ m2m; browser ↔ server; service ↔ service.
     Describe **how each gate works** and where it is enforced. Assign stable `tb-N` ids.
     Do not speculate about whether it can be bypassed.
   - **Input flows** — from an entry point: where external input travels, how it is
     transformed en route, and what validation is applied. Record where the flow ends as
     a `file:LINE` plus a factual one-line description of the operation there (e.g.
     "issues an outbound HTTP request with the supplied URL", "builds a SQL string by
     concatenation", "spawns a process"). Describe the operation; do not classify it.
   - **Assumptions** — preconditions and invariants the code relies on but does not
     itself enforce (e.g. "assumes `url` was already validated by its caller", "trusts
     the length field in the parsed header"). Assign stable `asm-N` ids; `locate-sinks`
     consumes them when deriving sinks.
4. **Self-check before writing.** Re-read every value you are about to emit. Rewrite or drop
   any that (a) names a vulnerability class, (b) contains a verdict word, or (c) asserts that
   a check is or is not sufficient. A fast way to catch your own drift: if a reader could
   tell which vulnerability class this run is hunting from the map alone, the map is
   contaminated — fix it before writing.
5. Write `surface-map.json` per the schema in `references/surface-map.md`, stamped with
   `commit` = current `HEAD`. Return a structured completion result to the orchestrator;
   do not write `state.json`.

Prioritize what is **reachable from crafted input** over reading everything.
