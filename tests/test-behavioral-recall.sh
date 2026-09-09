#!/usr/bin/env bash
# Tier 2 — behavioral recall: assert the agent describes the workflow correctly.
# Opt-in (LLM calls): RUN_BEHAVIORAL=1 bash tests/run-skill-tests.sh
#
# Runs against either platform, since the skills target both:
#   AGENT=claude (default)  RUN_BEHAVIORAL=1 bash tests/run-skill-tests.sh
#   AGENT=codex             RUN_BEHAVIORAL=1 bash tests/run-skill-tests.sh
#
# Codex note: `codex exec` echoes the loaded skill body into its transcript, so grepping
# raw stdout would match the SKILL.md text instead of the agent's answer — a false pass.
# `-o FILE` writes only the final message, which is what we assert against.
set -uo pipefail
TIMEOUT="${CLAUDE_PROMPT_TIMEOUT:-120}"
AGENT="${AGENT:-claude}"
fail=0

run_agent() {
  case "$AGENT" in
    claude) timeout "$TIMEOUT" claude -p "$1" 2>&1 ;;
    codex)
      local out; out="$(mktemp)"
      timeout "$TIMEOUT" codex exec --skip-git-repo-check -o "$out" "$1" </dev/null >/dev/null 2>&1
      cat "$out"; rm -f "$out" ;;
    *) echo "unknown AGENT: $AGENT" >&2; exit 2 ;;
  esac
}
run_claude() { run_agent "$1"; }   # back-compat alias

check() { # haystack pattern label
  if echo "$1" | grep -Eiq "$2"; then echo "  [PASS] $3";
  else echo "  [FAIL] $3"; fail=1; fi
}

echo "=== Behavioral recall (agent: $AGENT) ==="
out="$(run_claude 'Describe the offsec-hunter skill: list its steps in order and how it gates between them. Be brief.')"

check "$out" 'map.?attack.?surface' "names step 1"
check "$out" 'scope.?target'        "names step 2"
check "$out" 'locate.?sinks'        "names step 3"
check "$out" 'raise.?hypotheses'    "names step 4"
check "$out" 'break.?hypotheses'    "names step 5"
check "$out" 'prove.?exploit'       "names step 6"
check "$out" 'artifact|gate|state\.json' "describes artifact-gating"

out2="$(run_claude 'In offsec-hunter, what is the difference between interactive and headless mode? Be brief.')"
check "$out2" 'headless' "explains headless mode"
check "$out2" 'confirm|ask|interactive' "explains interactive mode"

# Steps must be USED as skills, never inlined by the orchestrator. Asked as its own
# prompt — a question about steps and gating does not elicit how they are invoked.
out4="$(run_claude 'In offsec-hunter, how does the orchestrator carry out each step — does it do the work itself? Be brief.')"
check "$out4" 'skill'                    "says the steps are skills"
check "$out4" 'use|invoke'               "says the orchestrator uses them"
check "$out4" 'not|never|rather than|instead' "says it does not do the work itself"

# Decision eval, not recall. A live run described step 1 correctly and then hunted RCE
# sinks inside it anyway, so pose the situation and grade the judgment.
out5="$(run_agent 'You are running offsec-hunter step 1 (map-attack-surface) on a target, and the run is hunting RCE. You find a function that passes a request parameter into a dynamic-code-execution call behind a weak regex guard. What exactly do you record in surface-map.json, and what do you refrain from doing? Be brief.')"
check "$out5" 'record|flow|entry|assumes' "records the flow factually"
check "$out5" 'not|never|refrain|avoid|don.t' "states what it refrains from"
check "$out5" 'class|verdict|rank|judg|RCE' "knows the class/verdict boundary applies"
check "$out5" 'locate.?sinks|step 3|break.?hypotheses|later step' "defers the judgment to a later step"

out3="$(run_claude 'In offsec-hunter, when does the hunt stop launching new rounds, and what is a family registry? Be brief.')"
check "$out3" 'dry|two rounds|2 rounds' "explains the dry-round stop rule"
check "$out3" 'famil' "explains the family registry"
check "$out3" 'block|redirect' "explains blocked/redirect behaviour"

# State ownership: steps return results; the orchestrator is the sole state writer.
stateStepOut="$(run_agent 'When an offsec-hunter step finishes its artifact, what does it do with state.json? Be brief.')"
check "$stateStepOut" 'orchestrator' "step returns completion to the orchestrator"
check "$stateStepOut" 'return|structured result' "step returns a structured result"
check "$stateStepOut" '(does not|doesn.t|not|never|no).*(write|modify|update|mutate)' "step does not write state.json"

stateWriterOut="$(run_agent 'In offsec-hunter, who is the sole writer and control plane for state.json? Include the exact temporary-file, JSON-validation, and atomic-replacement update protocol. Be brief.')"
check "$stateWriterOut" 'orchestrator' "orchestrator owns state.json"
check "$stateWriterOut" 'temporary|temp file' "state update starts from a temporary file"
check "$stateWriterOut" 'valid' "state update validates JSON"
check "$stateWriterOut" 'atomic' "state update is atomic"

stateConcurrencyOut="$(run_agent 'If two offsec-hunter step completions arrive close together, how should state.json be updated? Be brief.')"
check "$stateConcurrencyOut" 'orchestrator' "only the orchestrator updates state"
check "$stateConcurrencyOut" 'serial|one at a time|sequence|merge' "concurrent results are serialized or merged"
check "$stateConcurrencyOut" '(not|never|no).*(write|update|direct|concurrent|in parallel)|concurrent.*not|parallel.*not' "steps do not write state concurrently"

[ "$fail" -eq 0 ] && echo "  ---- behavioral PASS ----" || { echo "  ---- behavioral FAIL ----"; exit 1; }
