# RISC-V CPU Architecture Analysis & Modularity Plan

## Current 5-Stage Pipeline Architecture
```
IF → ID → EXE → MEM → WB
      ↑                 ↓
      └─── Branch Redirect ───┘
      ← Forwarding Paths ←
```

### Pipeline Stages and Modules

#### 1. **IF Stage (if_stage.sv)**
- **Single Fetch Unit**: One instruction stream per cycle
- **Branch Predictor**: 64-entry bimodal (singleton)
  - PC computation: exception → branch → predicted → sequential
  - BP update from EXE stage
- **Outputs**: `fs_to_ds_bus` = {inst, pc, bp_hit, bp_pred_taken, bp_pred_target}

#### 2. **ID Stage (id_stage.sv)**
- **Instruction Decode**: Single decoder per cycle
- **Register File**: `regfiles.sv` (singleton for correctness)
  - Combinational read: 2 read ports (rs1, rs2) + 1 write port
  - Width: 32 × 32-bit registers
  - 0-cycle latency: read result available same cycle as address
- **CSR Register File**: `regfile_csr.sv` (singleton)
- **Hazard Detection**:
  - Load-use hazard detection (stalls pipeline if load → ALU use in next cycle)
  - Forwarding path decision: determines which forwarding to use (EXE, MEM, WB)
- **Data Flow Analysis** for operand forwarding (address-based)
- **Outputs**: `ds_to_es_bus` = packed all control & operand info (314 bits with bitman disabled)

#### 3. **EXE Stage (exe_stage.sv)**
- **ALU Execution**: Combinational
- **Multiplier (mul.sv)**: 6-cycle pipeline
  - Stall generation when busy
  - Multiplier can span into next cycle (es_ready_go gates on !mul_stall)
- **Branch Resolution & Update BP**
- **CSR Read/Write Operations**
- **Data Selection** (forwarding): 2-bit `src1_fwd`, `src2_fwd` → MUX to pick between:
  - `reg_src1/reg_src2` (from ID)
  - `exe_result_reg` (from EXE-stage latch)
  - `mem_result_reg` (from MEM-stage latch)
- **Memory Address Calculation** (for loads/stores)
- **Outputs**: `es_to_ms_bus` = {pc, result, load_inst, rd_addr, regfile_wen, ...} (123 bits)

#### 4. **MEM Stage (mem_stage.sv)**
- **Data Load Processing**: Byte/halfword sign/zero extension
- **Outputs**: `ms_to_ws_bus` = {pc, result, rd_addr, regfile_wen} (70 bits)

#### 5. **WB Stage (wb_stage.sv)**
- **Register File Write**: Drives all register writes

### Critical Constraints for Dual-Issue

#### **Combinational vs. Sequential Read Timing**
- **Combinational (0-cycle)**:
  - Register file ports in ID stage
  - Address → immediately available result
  - No stall needed for initial read
- **Sequential (1-cycle)**:
  - Instruction memory (XPM BRAM LATENCY=1)
  - Data memory (XPM BRAM LATENCY=1)
  - Address → next cycle result

**⚠️ INVARIANT**: Must preserve separate combinational and sequential read semantics in any refactoring.

#### **Data Flow Packet Structure** (Inter-Stage Communication)

All control info packed into fixed-width buses for clean stage boundaries:

| Packet | Width | Contents |
|--------|-------|----------|
| `ALU_PACKET` | 10 | alu_op (one-hot) |
| `MUL_PACKET` | 6 | mul_op[3:0] + src1_signed + src2_signed |
| `MEM_PACKET` | 38 | mem_imm[31:0] + mem_op[4:0] + is_store |
| `CSR_PACKET` | 82 | csr_rdata + csr_imm + csr_waddr + csr_op + csr_imm_sel + csr_rdata_fwd + csr_wen |
| `BR_JMP_PACKET` | 78 | bp_pred_hit + bp_pred_taken + bp_pred_target + br_jmp_target + br_jmp_imm + br_jmp_opcode + is_jal + is_jalr |
| `CTRL_PACKET` | 32/31 | pc + exe_result_sel + [is_bitman] + is_alu + is_mul + is_mem + is_csr + is_br_jmp + rd_addr + regfile_wen + is_multicycle |
| `SRC_PACKET` | 66 | reg_src1 + reg_src2 + src1_fwd[1:0] + src2_fwd[1:0] |
| **DS_ES_WIDTH** | **~314** | All packets concatenated |

#### **Forwarding Architecture**

Three forwarding sources:
1. **EXE forwarding** (`src1_fwd[0]` or `src2_fwd[0]`): From exe_result (EXE-stage latch)
2. **MEM forwarding** (`src1_fwd[1]` or `src2_fwd[1]`): From mem_result (MEM-stage latch)
3. **No forwarding** (both 0): Use `reg_src1/reg_src2` from register file

**Address-based decision** in ID stage:
- Compare register addresses (rs1, rs2) vs. (exe_dest_addr, mem_dest_addr, wb_dest_addr)
- Generate `src1_fwd`, `src2_fwd` bits
- **Data selection** happens in EXE stage (MUX tree)

#### **Register File Write**

- Single write port in WB stage
- **Serialized** across cycle boundary (only one register written per cycle)
- On dual-issue: TWO instructions may reach WB in same cycle → **write conflict**
  - Need priority arbitration (e.g., first instruction wins, second stalls)
  - Or: wider write port + dual-register file design (breaks current singleton)

---

## Modularity Refactoring Strategy

### Phase 1: Packet Abstraction Layer
**Goal**: Encapsulate all packet packing/unpacking logic

**Changes**:
1. Create `alu_packet_pkg.sv` — ALU opcode, packing/unpacking macros
2. Create `mul_packet_pkg.sv` — Multiplier control, packing/unpacking
3. Create `mem_packet_pkg.sv` — Memory op, packing/unpacking
4. Create `csr_packet_pkg.sv` — CSR control, packing/unpacking
5. Create `br_jmp_packet_pkg.sv` — Branch/jump control, packing/unpacking
6. Create `ctrl_packet_pkg.sv` — Control signal bundle, packing/unpacking
7. Create `src_packet_pkg.sv` — Operand & forwarding info, packing/unpacking
8. Create `pipeline_pkg.sv` — Bus width macro calculations

**Benefit**: 
- Single source of truth for packet formats
- Easier to extend for dual-issue (e.g., two ALU_PACKETs in pipeline)
- Reusable packing/unpacking macros

### Phase 2: Hazard Detection & Forwarding Extraction
**Goal**: Separate hazard detection logic from ID stage for dual-issue reuse

**Changes**:
1. Create `hazard_unit.sv` module:
   - Inputs: rs1_addr, rs2_addr, exe_dest_addr, exe_regfile_wen, mem_dest_addr, mem_regfile_wen, wb_dest_addr, wb_regfile_wen, prev_load_dest
   - Outputs: need_rs1, need_rs2, src1_fwd[1:0], src2_fwd[1:0], load_use_hazard
   - Combinational logic (no clock)

2. Create `forwarding_unit.sv` module:
   - Inputs: exe_result_reg, mem_result_reg, src1_fwd, src2_fwd, reg_src1, reg_src2
   - Outputs: src1, src2 (forwarded operands)
   - Combinational MUX tree

**Benefit**:
- Reusable for both dual-issue execution paths
- Cleaner ID stage (delegate hazard logic)
- Testable in isolation

### Phase 3: Functional Unit Interfaces
**Goal**: Modularize ALU, multiplier, divider for duplication

**Changes**:
1. **ALU Wrapper** (`alu_wrapper.sv`):
   - Inputs: alu_op, src1, src2
   - Outputs: alu_result
   - Combinational (already minimal logic in exe_stage)

2. **Multiplier Wrapper** (enhance existing `mul.sv`):
   - Already isolated; ensure clean interface for instantiation ×2

3. **Divider Wrapper** (extract from `mul.sv` if not already):
   - Isolate divide/modulo logic
   - Can be shared (not duplicated on dual-issue)

**Benefit**:
- Clear functional unit contract
- Easy to parameterize for dual-issue (e.g., `alu_0`, `alu_1`)

### Phase 4: Control Flow Unification
**Goal**: Abstract branch redirect and control flow logic

**Changes**:
1. Create `branch_controller.sv`:
   - Inputs: br_taken, br_target, exception_flag, exception_addr (from EXE)
   - Outputs: br_redirect, br_redirect_target (to IF)
   - Logic: Priority mux (exception > branch > normal)

2. Keep IF stage's branch predictor singleton (one per pipeline)

**Benefit**:
- Clear separation: prediction vs. resolution
- Supports future multi-issue redirect arbitration

### Phase 5: Data Hazard Arbitration (Dual-Issue Ready)
**Goal**: Prepare infrastructure for dual-issue register write conflicts

**Changes**:
1. Create `write_port_arbiter.sv`:
   - Inputs: wb_wen_0, wb_addr_0, wb_data_0, wb_wen_1, wb_addr_1, wb_data_1
   - Outputs: regfile_wen, regfile_waddr, regfile_wdata, stall_1 (second instruction stalls if conflict)
   - Logic: Priority (0 > 1 on collision)

2. Modify WB stage to use arbiter (no change to register file itself)

**Benefit**:
- Singleton register file preserved
- Conflict resolution logic isolated
- Ready for dual-issue transition

---

## Modularity Checklist

### Phase 1 ✅ (Packet Abstraction)
- [ ] Create `rtl/packets/` subdirectory
- [ ] Implement `alu_packet_pkg.sv`
- [ ] Implement `mul_packet_pkg.sv`
- [ ] Implement `mem_packet_pkg.sv`
- [ ] Implement `csr_packet_pkg.sv`
- [ ] Implement `br_jmp_packet_pkg.sv`
- [ ] Implement `ctrl_packet_pkg.sv`
- [ ] Implement `src_packet_pkg.sv`
- [ ] Update `defines.svh` to use packet packages
- [ ] Refactor `id_stage.sv` to use packet packages
- [ ] Refactor `exe_stage.sv` to use packet packages
- [ ] Refactor `mem_stage.sv` to use packet packages
- [ ] Verify: xvlog clean, regression 49/49 pass

### Phase 2 ✅ (Hazard Detection)
- [ ] Create `hazard_unit.sv`
- [ ] Create `forwarding_unit.sv`
- [ ] Refactor `id_stage.sv` to instantiate hazard_unit
- [ ] Refactor `exe_stage.sv` to instantiate forwarding_unit
- [ ] Verify: xvlog clean, regression 49/49 pass

### Phase 3 ✅ (Functional Units)
- [ ] Create `alu_wrapper.sv`
- [ ] Refactor `exe_stage.sv` to use alu_wrapper
- [ ] Extract multiplier/divider into standalone `mul_wrapper.sv` (if needed)
- [ ] Verify: xvlog clean, regression 49/49 pass

### Phase 4 ✅ (Control Flow)
- [ ] Create `branch_controller.sv`
- [ ] Refactor `cpu_top.sv` redirect logic to use branch_controller
- [ ] Verify: xvlog clean, regression 49/49 pass

### Phase 5 ✅ (Write Port Arbiter)
- [ ] Create `write_port_arbiter.sv`
- [ ] Refactor `wb_stage.sv` to use write_port_arbiter
- [ ] Verify: xvlog clean, regression 49/49 pass

---

## Preserved Invariants

1. ✅ **Combinational register read** (IF-stage operands): Untouched regfiles.sv
2. ✅ **Sequential memory latency**: Unchanged from BRAM (LATENCY=1)
3. ✅ **Single instruction fetch per cycle**: If stage unchanged
4. ✅ **Single register file** (singleton write port serialization)
5. ✅ **Packet-based stage communication** (same bus widths during Phase 1-5)

---

## Dual-Issue Foundation (Post-Modularity)

Once modularity refactoring complete, dual-issue can be achieved by:

1. **IF stage**: Fetch 2 instructions (separate PC paths for each)
2. **ID stage**: Instantiate 2× hazard_unit, 2× instruction decoders
3. **EXE stage**: Instantiate 2× ALU, 2× forwarding_unit, shared multiplier (1 per pipeline)
4. **MEM stage**: Dual memory ports (BRAM supports 2 read/write)
5. **WB stage**: Use write_port_arbiter for dual writes to singleton register file

**No changes to**:
- Register file (stays single write port + serialization in arbiter)
- Branch predictor (single BP, but resolves both branch paths)
- Memory system (BRAM already supports dual ports)
