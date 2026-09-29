# Event Capture Subsystem Design

## Goal
Build the first event-capture subsystem for the FPGA DAQ platform. The subsystem continuously records aligned streaming samples, detects a trigger on the filtered signal, preserves exactly 1024 pre-trigger samples + 1 trigger sample + 1023 post-trigger samples, then freezes the event for later packetization/UART readout.

## Position in the Data Path

```text
Sensor / ADC / PRBS
        |
    Source MUX
        |
    Async FIFO
        |
       FIR
        |
        +------------------------------+
        | aligned sample bundle        |
        | {sample_index, fault_flags,  |
        |  raw_sample, filtered_sample}|
        +------------------------------+
           |                    |
           |                    +--> Trigger Detector
           |                              |
           +------------------------------+ trigger_pulse
                           |
                           v
               Event Capture / Circular Buffer
                           |
                      event_done
                           |
                      Packetizer
                           |
                         CRC16
                           |
                          UART
```

The Trigger Detector is a side observer. Sample data does not pass through it before reaching the Event Capture block.

## Aligned Event Entry
Each accepted sample is represented by one 72-bit event entry:

```text
sample_index     32 bits
fault_flags       8 bits
raw_sample       16 bits
filtered_sample  16 bits
------------------------
total            72 bits
```

`raw_sample` and `filtered_sample` must refer to the same logical sample index. FIR latency must therefore be matched by delaying the raw sample and sideband information using the same ready/valid acceptance semantics.

## Handshake Rule
A sample is real only when the streaming transfer occurs:

```text
sample_fire = valid && ready
```

All Event Capture state changes tied to sample arrival must use `sample_fire`, not raw clock cycles. This includes write pointer movement, pre-trigger history count, and post-trigger count.

## Buffer Geometry
The first implementation uses a single 2048-entry circular buffer, each entry 72 bits wide.

```text
PRE      = 1024 samples
TRIGGER  =    1 sample
POST     = 1023 samples
---------------------
TOTAL    = 2048 samples
```

The write address wraps modulo 2048.

## Pre-trigger Policy
At reset, no valid history exists. The circular buffer begins accepting samples immediately, but the trigger is not eligible to create an event until 1024 accepted samples have been collected.

`pre_count` saturates at 1024. Once saturated, capture trigger eligibility is enabled.

The Trigger Detector itself still consumes threshold crossings while trigger eligibility is disabled. A disabled HIGH crossing disarms the detector, preventing a false event if trigger eligibility becomes enabled while the signal is already above the HIGH threshold.

## Trigger Semantics
The address containing the trigger sample is stored as `trigger_ptr`.

On the accepted sample that produces `trigger_pulse`:
- that sample is written normally into the circular buffer;
- its write address becomes `trigger_ptr`;
- the capture state transitions from circular recording to post-trigger capture.

## Post-trigger Capture
After the trigger sample, exactly 1023 additional accepted samples are stored.

The counter advances only on `sample_fire`. Stalls or idle clock cycles do not count.

After the 1023rd post-trigger sample has been written:
- Event Capture stops modifying the event memory;
- `event_done` asserts;
- the frozen event remains available for readout.

## Event Ordering and Read Start
The chronological first sample of the frozen event is:

```text
start_ptr = trigger_ptr - 1024  (mod 2048)
```

Reading 2048 entries from `start_ptr`, with modulo-2048 address wrap, reconstructs the event in chronological order. The trigger sample appears at offset 1024 in that reconstructed sequence.

## Capture State Machine
The first implementation uses three conceptual states:

```text
CIRCULAR_RECORD
      |
      | eligible trigger
      v
POST_CAPTURE
      |
      | 1023 accepted post samples
      v
EVENT_DONE
```

### CIRCULAR_RECORD
- continuously write accepted samples;
- preserve a rolling history;
- accept a trigger only after pre-history is valid.

### POST_CAPTURE
- continue writing accepted samples;
- count exactly 1023 post-trigger samples;
- ignore any new trigger pulses.

### EVENT_DONE
- freeze event memory and event metadata;
- ignore new events until explicit readout completion/re-arm;
- do not backpressure or stop the upstream FIFO/FIR pipeline.

## Non-blocking Tap Policy
The Event Capture subsystem is a tap on the processing stream, not a backpressure-generating sink in the first implementation.

When the event buffer is frozen in `EVENT_DONE`, the upstream acquisition/CDC/FIR path continues operating. New events are missed during this interval. This is intentional dead time for the single-buffer MVP.

Ping-pong buffering is a future extension and is not part of this first implementation.

## Readout Interface Scope
The first Event Capture block must expose enough information for the later Packetizer/UART block to read the frozen event in order. The read path may use a simple synchronous or combinational read interface depending on inferred memory behavior, but the capture-side requirements above must not change.

Minimum externally visible event metadata:
- `event_done`
- `trigger_ptr`
- `start_ptr`

A later `readout_done`/re-arm input will return the block to circular recording after transmission.

## Verification Requirements
The self-checking testbench must prove at least the following:

1. Fewer than 1024 accepted history samples cannot create an event.
2. After 1024 history samples, the first valid trigger is captured at the exact trigger sample address.
3. Trigger hysteresis chatter does not create duplicate events before re-arm.
4. Exactly 1023 accepted post-trigger samples are stored; idle/stalled clocks do not advance the post counter.
5. Circular wraparound produces the correct chronological 2048-entry event when read from `start_ptr`.
6. In `EVENT_DONE`, event memory remains frozen while upstream samples may continue to arrive.
7. For every stored entry, `sample_index`, `raw_sample`, `filtered_sample`, and `fault_flags` remain aligned.

## Out of Scope for This Step
- Packetizer implementation
- CRC16 implementation
- UART transmitter/readout protocol
- PRBS source-mux integration
- Ping-pong event buffers
- Final BRAM optimization or post-route timing closure

Those are subsequent stages after the single-buffer Event Capture block and its verification are closed.
