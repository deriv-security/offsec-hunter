---
name: scope-target
description: Step 2 of offsec-hunter. Read the attack-surface map and define the hunting goal — the target vuln class plus a confirmed threat model (attacker position, delivery vector, win condition, scope). Interactive runs confirm with the user; headless runs accept and log the proposal. Use when selecting a vulnerability class and threat model for a target run.
---

# scope-target — step 2

**Guard:** If `state.json` is absent, stop with "run the `offsec-hunter` orchestrator first".

Define the **hunting goal** for this run: the target vuln class plus a confirmed threat
model. Writes `hunts/<VULN>/target.md` under the output root.

## Gate

Read `surface-map.json` (target-level). If it is missing or stale, stop:
**"no fresh `surface-map.json` — run map-attack-surface first."** Do not proceed on a
missing or stale map.

## Procedure

The map now tells you what an exploit plausibly looks like for **this** target — use it
instead of assuming the web default.

1. **Pick the vuln class.** Use the vuln class the user provided when invoking this skill
   (or `broad` if none). If none
   was given: interactive → ask which class (`SSRF`, `RCE`, `SQLi`, `SSTI`, `auth-bypass`,
   `IDOR`, … or `broad`); headless → default to `broad` and log it.

2. **Propose a threat model** inferred from the map, across four dimensions:
   - **Attacker position** — e.g. `remote-unauth`, `remote-normal-user`, `local-user`,
     `input-file-supplier`, `adjacent-service`.
   - **Delivery vector** — e.g. HTTP request/chain, WebSocket message, CLI args, a parsed
     input file/format, IPC/socket, environment.
   - **Win condition** — what counts as a successful exploit here. Includes
     RCE/SSRF/data-exfil/auth-bypass **and** non-web wins: DoS / "render the target
     incapable", memory-safety crash.
   - **In/out-of-scope notes** — boundaries explicitly excluded (e.g. m2m-only paths
     unless an auth bypass reaches them) and target-specific assumptions.

   Start from the default Scope in the orchestrator; where the map shows a non-web target,
   propose the fitting model instead.

3. **Confirm by mode:**
   - **interactive** — stop and ask the user to confirm or edit the proposal, **even when
     it equals the web default**. Do not auto-proceed. This is the nudge.
   - **headless** — accept the proposed model, and **log the assumption loudly** so it is
     auditable.

4. Write the confirmed goal to `hunts/<VULN>/target.md` as prose, with the four dimensions
   and the chosen vuln class as headings. Return a structured completion result to the
   orchestrator — including the chosen `vuln` and `surface-map.json` input hash — without
   writing `state.json`.
