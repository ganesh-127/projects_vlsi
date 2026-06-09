# ECG Signal Processor with Arrhythmia Detection on FPGA

<p align="center">
  <img src="docs/block_diagram.png" alt="Block Diagram" width="750"/>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Language-SystemVerilog-blue"/>
  <img src="https://img.shields.io/badge/FPGA-Intel%20MAX%2010-red"/>
  <img src="https://img.shields.io/badge/Application-Biomedical-brightgreen"/>
  <img src="https://img.shields.io/badge/License-MIT-yellow"/>
</p>

---

## Overview

A **real-time ECG Signal Processor** implemented in SystemVerilog
and deployed on FPGA, capable of:
- **ECG Signal Acquisition** — capturing raw ECG input
- **Digital Filtering** — removing baseline wander and noise
- **Heart Rate Detection** — identifying QRS complexes
- **Arrhythmia Detection** — flagging abnormal heart rhythms

---

## System Architecture
