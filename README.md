# projects_vlsi
BIST enabled SRAM,ECG (R-peak detection)
# BIST-Enabled SRAM with Assertion-Based Verification

<p align="center">
  <img src="docs/block_diagram.png" alt="Block Diagram" width="750"/>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Language-SystemVerilog-blue"/>
  <img src="https://img.shields.io/badge/FPGA-Intel%20MAX%2010-red"/>
  <img src="https://img.shields.io/badge/Tool-Quartus%20Prime%20Lite%2024.1-orange"/>
  <img src="https://img.shields.io/badge/Simulator-ModelSim-green"/>
  <img src="https://img.shields.io/badge/License-MIT-yellow"/>
</p>

---

## Overview

A **256×32-bit (1 KB) SRAM Memory Controller** designed in SystemVerilog with:
- **AHB-Lite** protocol interface
- **Built-In Self-Test (BIST)** implementing March-C, MATS+, Checkerboard, and Walking 1/0 algorithms
- **Multi-mode Power Management** (Active, Standby, Retention, Shutdown)
- **Assertion-Based Verification (ABV)** using SystemVerilog Assertions (SVA)

Synthesized and verified on **Intel MAX 10 FPGA (10M50DAF484C7G)** using Quartus Prime Lite 24.1.

> **Course:** ECE335 FPGA Architecture & Design  
> **Institution:** SASTRA Deemed to be University, Thanjavur  
> **Date:** May 2026

---

## Key Results

| Metric | Result |
|--------|--------|
| Overall Functional Coverage | 92.59% |
| SVA Assertions | 17 — All Passing |
| BIST Coverage | 100% |
| AHB Transaction Coverage | 77.78% |
| Power Coverage | 100% |
| Logic Elements Used | 11,003 / 49,760 (22%) |
| Total Registers | 8,283 |
| Total Pins Used | 213 / 360 (59%) |
| Total Thermal Power | 99.30 mW |
| Core Static Power | 89.95 mW |
| I/O Thermal Power | 9.36 mW |

---

## Architecture

The system is organized as **six functional modules** integrated in a top-level wrapper:
