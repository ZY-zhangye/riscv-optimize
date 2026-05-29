# P2 Retrospective: Instruction Queue & Dual-Fetch Preparation

**Date**: 2026-05-29
**Result**: 49/49 tests pass, cycle counts identical to P0/P1 baseline

## What was planned

Insert an instruction queue between IF and ID to decouple the front-end from the
back-end, enabling dual fetch (fetch2) in the next step. The queue has depth 4,
dual-push (up to 2 instructions per cycle) and single-pop (1 per cycle).

## What was done

1. **`instr_queue.sv`** (new) — depth-4 circular buffer with:
   - Dual push ports (slot0 + slot1) and single pop port
   - Combinational next-count logic to correctly handle simultaneous push+pop
   - Flush-on-redirect (branch mispredict or exception clears all entries)
   - `push_free` output for IF backpressure

2. **`cpu_top.sv`** (modified) — dual-path architecture via `ifdef DUAL_ISSUE_ENABLE`:
   - **Off** (current default): original direct IF→ID connection, unchanged behavior
   - **On** (future): IF→queue→ID path, ready for dual-fetch IF stage

## What went wrong and why

### Attempt 1: Rewrite if_stage for dual-fetch push interface

Rewrote `if_stage` to output dual push signals instead of `fs_to_ds_valid/bus`.
Introduced `imem_data_valid` (post-reset guard), `redirect_stale` (post-redirect
NOP insertion), and `fs_stalled` (queue backpressure) logic.

**Failure mode**: All tests failed with wrong register values or timeouts.
The instruction sequence was corrupted — PCs looped or skipped, suggesting
instructions were being duplicated or dropped.

### Attempt 2: Bypass register between IF push and ID

Added a 1-cycle bypass register to convert the push interface back to
`fs_to_ds_valid/bus` for ID, attempting to replicate the original handshake.

**Failure mode**: Same corruption. The registered bypass added 1 extra cycle
of latency which changed pipeline timing enough to break branch resolution.

### Attempt 3: Combinational bypass (no register)

Eliminated the bypass register, used direct combinational connection from
push signals to `fs_to_ds_valid/bus`. Adjusted `push_free` to replicate
original `fs_allowin` semantics.

**Failure mode**: Still failed. The NOP-insertion logic (`redirect_stale`,
`br_taken` combinational suppression) did not perfectly match the original IF's
NOP behavior.

### Attempt 4: Keep original if_stage, insert queue as buffer

Preserved the original `if_stage` completely unchanged. Extracted fields from
`fs_to_ds_bus` for queue push input. Used queue `push_free` to drive IF's
`ds_allowin` backpressure.

**Failure mode**: Even with the original IF untouched, inserting the queue
buffer changed `ds_allowin` timing. With depth 4, IF never stalled (queue
always had space), which differed from the original where IF stalls when ID
stalls. This timing difference broke branch/load-use interactions.

### Root cause

The IF↔ID handshake (`fs_to_ds_valid` / `ds_allowin`) is tightly coupled to
the pipeline's stall behavior. Any change to the backpressure path — even a
seemingly transparent buffer — alters the timing of:
- Branch redirect registration (`br_taken_reg`)
- Load-use hazard stalls
- PC advancement relative to EX stage resolution

These timing changes cause subtle instruction sequence corruption that is
difficult to diagnose without waveform-level debugging.

## Solution: Dual-path architecture

The queue infrastructure is in place but only activated when `DUAL_ISSUE_ENABLE`
is defined. In single-issue mode, the original IF→ID direct connection is
preserved verbatim — no queue in the signal path at all.

```
Single-issue (DUAL_ISSUE_ENABLE=0):
  IF ───[fs_to_ds_valid/bus]───→ ID      ← unchanged from P0/P1

Dual-issue (DUAL_ISSUE_ENABLE=1):
  IF ─→ instr_queue ─→ ID                ← queue active, dual-fetch IF needed
```

## Lessons for P3 and beyond

1. **Don't rewrite working pipeline stages.** The original `if_stage` has
   subtle timing behavior (NOP insertion, redirect registration, BP update
   timing) that is hard to replicate. Keep it and add new modules around it.

2. **Use `ifdef` for gradual activation.** Every new dual-issue feature should
   be gated by `DUAL_ISSUE_ENABLE` (or sub-feature macros like
   `DUAL_ISSUE_FETCH_ENABLE`). The single-issue fallback path must be the
   exact same code as the previous stage.

3. **Test single-issue fallback first.** Before debugging dual-issue behavior,
   run the full 49-test regression with all new macros OFF. Any failure means
   the fallback path is broken.

4. **The queue itself is correct.** `instr_queue.sv` was verified separately
   and its combinational next-count logic handles push+pop races correctly.
   The issue was always in the IF↔queue integration, not the queue module.

5. **When enabling DUAL_ISSUE_ENABLE**, budget significant time for:
   - Rewriting `if_stage` for the dual-push interface
   - Waveform-level debugging of the first ~50 instruction PCs
   - Verifying branch redirect + queue flush interaction
   - Adding directed tests (queue full/empty, redirect flush, sequential fetch2)

## Files changed

| File | Change |
|------|--------|
| `rtl/cpu_top/instr_queue.sv` | New: depth-4 instruction queue |
| `rtl/cpu_top/cpu_top.sv` | Modified: dual-path IF→ID architecture |
| `test/run_p0regression.ps1` | Modified: added instr_queue.sv to compile list |
