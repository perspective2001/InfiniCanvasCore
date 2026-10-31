# Engineering playbook — reliable, faster AI-assisted application work

Use with [AGENTS.md](../AGENTS.md) and the project-specific release gates. This is a working protocol, not a model upgrade or a promise of zero defects. The measurable goal is fewer regressions per accepted feature, less repeated context gathering, and fewer wasted paid builds.

## Read once, implement once, verify repeatedly
1. **Establish the live state**: inspect default branch, latest commit/tag, current workflow, known bugs, device feedback and recent build failures. Read only the files touched by the requested behavior plus direct dependencies.
2. **Define the contract first**: describe the visible before/after behavior, preconditions, persistence invariants and failure cases. For a bug, reproduce its failure in a test when practical. No cosmetic refactor in the same patch as a gesture/persistence fix.
3. **Design a narrow change**: name the subsystem that owns the behavior; keep one event stream/one source of truth, stable bundle IDs, backwards-compatible stored data and native API compatibility.
4. **Use a cheap-to-expensive verification ladder**: Python/static contract checks -> geometry/pure unit tests -> compile -> simulator app-root and native API tests -> real hardware/restore/latency acceptance. Stop on the first failure; don't repeat a paid macOS build for every small edit.
5. **Review actual evidence**: compare diff and test results for the exact proposed SHA. A mock UI screenshot, simulator pass and actual Apple Pencil/Playgrounds build are distinct levels of evidence.
6. **Release with rollback**: only after latest-SHA CI and requested device-level tests. Preserve a last device-confirmed version separately from the newest source tag; never silently reinstall, change app IDs or erase local data.
7. **Capture useful learning**: add a small deterministic regression test for each confirmed recurring bug. Update only the relevant scoped AGENTS rule and known-limits note. Don't accumulate generic superprompts that increase context cost without changing outcomes.

## CI cost and latency
- For InfiniCanvas, the lightweight Linux host-contract preflight runs before Xcode 27 and iOS 26 macOS jobs. A failed contract check prevents both costly jobs from starting.
- Keep doc-only commits out of native builds, cancel superseded runs, and limit the full release matrix to one coherent candidate. Read existing logs before rerunning.
- For Reader (private Actions quota), retain its working IPA distribution until parity is confirmed; do not run speculative app rebuilds merely to change process documentation.
- Avoid undocumented dependency upgrades and dynamic behavior changes hidden inside large refactors.

## Non-negotiable evidence vocabulary
- **Implemented**: code exists on a named commit or PR.
- **Compiled**: compiler build completed for the named target and SDK.
- **Simulator-tested**: named tests passed on a specific CI run.
- **Device-verified**: user tested the named version on the physical iPad.
- **Released**: signed/distributed/installable build is available to the user. Repository push alone is not an app install.
Never substitute one for another.

## Research basis
- OpenAI, *Custom Code Review rules for Codex* (2026): concise, scoped AGENTS rules for meaningful invariants, deterministic rules in CI.
  https://developers.openai.com/blog/custom-code-review-rules-for-codex
- OpenAI, *Iterating Development Workflows with Codex* (2026): current-state discovery, phase-specific evidence and durable repo conventions.
  https://developers.openai.com/cookbook/examples/codex/iterating-development-workflows-with-codex
- Google Research, *Grounding AI Agents in Contracts* (SpecOps '26): specifying preconditions, postconditions and undefined behavior before generating tests improved bug detection in their evaluation.
  https://research.google/pubs/grounding-ai-agents-in-contracts-an-empirical-evaluation-of-spec-driven-test-generation/
- GitHub Actions docs on concurrency and runner costs:
  https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-workflow-concurrency

## Scope of persistence
These files are stored with the repository, so a new coding session can reload them even if a conversation fails. They do **not** change the underlying ChatGPT model, install permanent account-wide agent instructions or silently transfer themselves to unrelated repositories.
