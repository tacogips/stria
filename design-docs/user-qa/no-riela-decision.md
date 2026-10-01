# riela Is Not Used

## Status

Answered (user decision).

## Question

The original request asked to use tacogips/riela and tacogips/agent-gateway
as libraries, with riela running the OCR flow and keeping workflow and log
data in a stria-dedicated data space. Should stria depend on riela?

## Answer

No. The user clarified: "riela's memory features etc. are not needed. I only
wanted to use part of riela to have an agent run the Swift image -> OCR flow.
If riela is not needed, do not use it."

## Decision

- stria has no riela dependency, no riela workflow files, and no `riela/`
  directory in the data root.
- The image -> OCR flow and the agent Q&A flow are implemented directly in
  Swift in `StriaCore` (`../specs/design-agent-integration.md`), behind the
  `OCRService` and `AgentService` protocols.
- `agent-gateway` is the only AI library. It is consumed by URL with revision
  `c7f269753ec36aca92d429ec13316ba033128967`.
- Per-call logging, which riela would have provided, is covered by the
  `agent_runs` table and `<root>/logs/agent-runs-YYYY-MM-DD.jsonl`.

## Supporting Reasons

- The only riela capability that was wanted (running an agent over a page
  image) is a single agent-gateway call. A workflow engine adds no behaviour
  for it.
- riela's root manifest declares a local path dependency
  (`Packages/RielaMemory`), which SwiftPM rejects for a package required by
  revision, so riela cannot be consumed by URL plus revision.
- riela pulls in many heavy gateway dependencies that stria does not need.

## Revisit When

Revisit this if stria later needs multi-step agent workflows with
persistence or resumption beyond the per-page OCR retry state machine.
