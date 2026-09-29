# Event Capture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement and verify a single-buffer 2048-entry event capture block that preserves exactly 1024 pre-trigger samples, 1 trigger sample, and 1023 post-trigger samples.

**Architecture:** The block is a non-blocking tap on the aligned processing stream. It writes 72-bit aligned entries into a modulo-2048 circular buffer, records `trigger_ptr` on an eligible trigger sample, captures exactly 1023 later accepted samples, then freezes the event and exposes `start_ptr = trigger_ptr - 1024` for chronological readout.

**Tech Stack:** SystemVerilog, Vivado/XSim 2026.1, self-checking behavioral simulation.

**Spec:** `docs/superpowers/specs/2026-09-30-event-capture-design.md`

## Global Constraints

- Event entry width: 72 bits = `{sample_index[31:0], fault_flags[7:0], raw_sample[15:0], filtered_sample[15:0]}`.
- Buffer depth: 2048 entries.
- Event geometry: PRE=1024, TRIGGER=1, POST=1023.
- All counters and writes advance only on `sample_fire`.
- `EVENT_DONE` freezes event memory but must not backpressure the upstream stream.
- Trigger eligibility begins only after 1024 accepted history samples.
- New triggers are ignored during post capture and event-done states.

## Review Focus

- Off-by-one around the trigger sample and 1023rd post sample.
- Wrap-around when `trigger_ptr < 1024`.
- `sample_fire=0` must not advance any capture state.
- Event memory must remain unchanged after `event_done`.
- Chronological readout must place the trigger at event offset 1024.

---

### Task 1: Event Capture RED Testbench

**Files:**
- Create: `RTL project.srcs/sim_1/new/tb_event_capture.sv`

**Interfaces:**
- Consumes: planned `event_capture` module interface from Task 2.
- Produces: a self-checking RED test that fails because `event_capture` is not yet implemented.

- [ ] **Step 1: Write `tb_event_capture.sv`**
  - Drive one accepted sample per helper call.
  - Verify no event before 1024 history samples.
  - Verify exact trigger address after history becomes valid.
  - Insert idle cycles with `sample_fire=0` during POST and verify they do not count.
  - Verify `event_done` only after exactly 1023 accepted post samples.
  - Read all 2048 entries from `start_ptr` and compare sample indexes against the expected chronological sequence.
  - Verify trigger sample appears at readout offset 1024.
  - Continue presenting samples after `event_done` and verify frozen read data does not change.

- [ ] **Step 2: Run Behavioral Simulation and verify RED**
  - Expected failure: `event_capture` design unit/module is missing.
  - A syntax error in the testbench does not count as RED; fix the testbench until the only reason for failure is the missing DUT.

### Task 2: Minimal Event Capture RTL

**Files:**
- Create: `RTL project.srcs/sources_1/new/event_capture.sv`

**Interfaces:**
- Consumes:
  - `clk`, `rst`
  - `sample_fire`
  - aligned `sample_index[31:0]`, `fault_flags[7:0]`, signed `raw_sample[15:0]`, signed `filtered_sample[15:0]`
  - `trigger_pulse`
  - `read_addr[10:0]`
  - `readout_done`
- Produces:
  - `trigger_enable`
  - `event_done`
  - `trigger_ptr[10:0]`
  - `start_ptr[10:0]`
  - `read_data[71:0]`

- [ ] **Step 1: Implement circular recording**
  - Write aligned 72-bit entries only on `sample_fire` while not frozen.
  - Wrap write pointer modulo 2048.
  - Saturate pre-history count at 1024 and assert `trigger_enable` only when history is valid and state is circular-record.

- [ ] **Step 2: Implement trigger transition**
  - On `sample_fire && trigger_pulse && trigger_enable`, preserve the trigger sample normally, store the current write address as `trigger_ptr`, compute `start_ptr` by modulo-2048 subtraction of 1024, and enter post-capture.

- [ ] **Step 3: Implement post capture**
  - Count only accepted samples after the trigger sample.
  - Freeze after exactly 1023 accepted post-trigger samples and assert `event_done`.

- [ ] **Step 4: Implement readout/re-arm behavior**
  - Expose frozen memory through `read_addr/read_data`.
  - On `readout_done`, clear event state and pre-history validity so a new event requires a fresh 1024-sample history.

- [ ] **Step 5: Run `tb_event_capture` and verify GREEN**
  - Expected: `EVENT_CAPTURE_TEST_PASS`, `ERROR_COUNT = 0`.

### Task 3: Integration Preparation

**Files:**
- Modify later: `RTL project.srcs/sources_1/new/daq_dsp_top.sv`
- Test later: dedicated event-capture integration testbench.

**Interfaces:**
- Consumes: aligned raw/filter/index/flags stream and `trigger_detector` pulse.
- Produces: frozen event interface for future Packetizer/CRC/UART.

- [ ] **Step 1: Do not integrate until Task 2 is green standalone**
- [ ] **Step 2: Add sideband alignment path before connecting Event Capture**
- [ ] **Step 3: Preserve upstream ready/valid behavior; Event Capture remains a tap**
- [ ] **Step 4: Run prior CDC/FIR tests plus new integration test to catch regressions**
