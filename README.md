# 🧠 2-Stage Pipelined RISC-V (RV32I) CPU in SystemVerilog (Vivado)


This repository contains my **University of Moratuwa (UOM) – Assignment 4** work: converting a provided **single-cycle RV32I CPU** into a **2-stage pipelined CPU**, verifying using Vivado simulation, and comparing performance and timing.

✅ **Test Program:** Fibonacci (n = 12)  
✅ **Final Output:** `a0 (x10) = 144 (0x00000090)`  

---

## 📝 Overview
**RISC-V** is an **open Instruction Set Architecture (ISA)**. An ISA defines the instructions a processor understands (e.g., `add`, `addi`, `lw`, `sw`, `beq`, `jal`).  
This project implements a basic **RV32I** processor and upgrades it from **single-cycle** to a **2-stage pipelined** datapath to improve throughput.

---

## 🧠 System Architecture

### Single-Cycle CPU Diagram
![Single-Cycle CPU Diagram](<Single Cycle CPU Diagram.jpeg>)

### Converting Single-Cycle ➜ 2-Stage Pipelined CPU Diagram
![2-Stage Pipeline Diagram](<Converting Single-Cycle CPU into a 2-Stage Pipelined CPU Diagram.jpeg>)

---

## ⚙️ Implementation Details

### ✅ Single-Cycle CPU (Baseline)
- Executes **one instruction per clock cycle**
- Simple control flow
- Clock period limited by the **longest** instruction path

### ✅ 2-Stage Pipelined CPU
Pipeline stages:
- **Stage 1:** IF / ID / EX  
- **Stage 2:** MEM / WB  

What I added:
- Pipeline registers (Stage-1 ➜ Stage-2)
- Control + data signal separation across stages
- Hazard handling using software scheduling (NOP insertion)

### ⭐ Optional: Data Forwarding (Bypassing)
- Added forwarding logic to reduce **RAW (Read-After-Write)** hazards
- Forwards Stage-2 writeback value directly into Stage-1 operands
- Allows the program to run **without extra software NOPs** (for many cases)

---

## 🧪 Verification (Vivado Simulation)

### What I checked in the waveform
Recommended signals to capture:
- `clock`, `reset`
- `pc` / `next_pc`
- instruction (`ins`)
- `rs1`, `rs2`, `rd`, `imm`
- ALU signals: `src1`, `src2`, `aluOp`, `aluOut`
- writeback: `regWriteEn`, `regDataIn`
- final output: `a0 (x10)` should be **144**

## 🧾 Programs + Conversion

### Program format
The testbench reads a hex file where:
- **each line is one byte**
- stored in **little-endian** order

Convert `.txt` program → `.hex`:
```bash
python3 programs/convert.py programs/program.txt programs/program.hex
