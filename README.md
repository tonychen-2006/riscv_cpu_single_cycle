# RISC-V Single-Cycle CPU

A single-cycle RISC-V (RV32I subset) CPU implemented in SystemVerilog, targeting Intel DE-series FPGA boards. Based on the design from *Digital Design and Computer Architecture: RISC-V Edition* (Harris & Harris).

## Architecture Overview

The CPU is a classic single-cycle implementation: every instruction completes in exactly one clock cycle. There is no pipelining or caching.

```
         ┌──────────┐      ┌────────────┐
clk ────►│  flopr   │      │  imem      │
         │  (PC reg)│─PC──►│ (instr mem)│─Instr──►┐
         └──────────┘      └────────────┘          │
                                                    ▼
                                          ┌──────────────────┐
                                          │    controller    │
                                          │  (maindec +      │
                                          │   aludec)        │
                                          └────────┬─────────┘
                                                   │ control signals
                                                   ▼
                                          ┌──────────────────┐
                                          │     datapath     │
                                          │  (regfile, ALU,  │
                                          │   extend, muxes) │
                                          └────────┬─────────┘
                                                   │
                                          ┌────────▼─────────┐
                                          │  dmem / MMIO     │
                                          └──────────────────┘
```

## Supported Instructions

| Type   | Instructions                        |
|--------|-------------------------------------|
| R-type | `add`, `sub`, `and`, `or`, `slt`    |
| I-type | `lw`, `addi`, `andi`, `ori`, `slti` |
| S-type | `sw`                                |
| B-type | `beq`                               |
| J-type | `jal`                               |

## ALU Operations

| `ALUControl` | Operation   |
|:---:|-------------|
| `000` | ADD         |
| `001` | SUB         |
| `010` | AND         |
| `011` | OR          |
| `100` | XOR         |
| `101` | SLT (signed less-than) |
| `110` | SLL (logical shift left) |
| `111` | SRL (logical shift right) |

## Module Hierarchy

```
top
├── riscvsingle
│   ├── controller
│   │   ├── maindec   (main decoder — opcode → control signals)
│   │   └── aludec    (ALU decoder — funct3/funct7 → ALUControl)
│   └── datapath
│       ├── flopr      (PC register)
│       ├── adder      (PC+4 and branch target)
│       ├── mux2       (PC mux)
│       ├── regfile    (32 × 32-bit register file, x0 = 0)
│       ├── extend     (immediate sign-extension)
│       ├── mux2       (ALU src-B mux)
│       ├── alu        (arithmetic/logic unit)
│       └── mux3       (result mux)
├── imem               (instruction memory — 64 words, from imem.txt)
└── dmem               (data memory — 64 words, from dmem.txt)
```

## Memory Map (FPGA I/O)

The top-level module exposes DE-board peripherals via memory-mapped I/O.

| Address        | Peripheral           | Direction |
|----------------|----------------------|-----------|
| `0xFF200000`   | `LEDR[9:0]` — 10 LEDs | Write    |
| `0xFF200020`   | `HEX3HEX0` — 4 hex displays | Write |
| `0xFF200030`   | `HEX5HEX4` — 2 hex displays | Write |
| `0xFF200040`   | `SW[9:0]` — 10 switches | Read   |

`KEY[0]` is an active-low asynchronous reset.

## Demo Program (`asm.s`)

The included assembly program loops forever, reading the slide switches and mirroring their value to the LEDs and HEX displays:

```asm
lw  t0, BASE_PTR(zero)   # load MMIO base address (0xFF200000)
loop:
  lw  t1, SW_OFFSET(t0)    # read switches
  sw  t1, LEDR_OFFSET(t0)  # drive LEDs
  sw  t1, HEX3_OFFSET(t0)  # drive HEX3–HEX0
  sw  t1, HEX5_OFFSET(t0)  # drive HEX5–HEX4
  j   loop
```

## Simulation

The testbench (`testbench.sv`) drives the design with a 10 ns clock. It monitors memory writes and prints **"Simulation succeeded"** when address `100` is written with the value `25`.

Simulate with any SystemVerilog-compatible tool, e.g. ModelSim / QuestaSim:

```bash
vlog riscv.sv testbench.sv
vsim -c testbench -do "run -all"
```

The instruction and data memories are loaded from plain hex files at simulation start:

- `imem.txt` — assembled program (one 32-bit word per line, hex)
- `dmem.txt` — initial data memory contents

## Files

| File | Description |
|------|-------------|
| `riscv.sv` | Full CPU implementation (all modules) |
| `testbench.sv` | Self-checking simulation testbench |
| `asm.s` | Demo RISC-V assembly program |
