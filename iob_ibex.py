# SPDX-FileCopyrightText: 2024 IObundle
#
# SPDX-License-Identifier: MIT


def setup(py_params_dict):
    attributes_dict = {
        "version": "0.1",
        "confs": [
            {
                "name": "AXI_ID_W",
                "descr": "AXI ID bus width",
                "type": "P",
                "val": 0,
                "min": 0,
                "max": 32,
            },
            {
                "name": "AXI_ADDR_W",
                "descr": "AXI address bus width",
                "type": "P",
                "val": 0,
                "min": 0,
                "max": 32,
            },
            {
                "name": "AXI_DATA_W",
                "descr": "AXI data bus width",
                "type": "P",
                "val": 0,
                "min": 0,
                "max": 32,
            },
            {
                "name": "AXI_LEN_W",
                "descr": "AXI burst length width",
                "type": "P",
                "val": 0,
                "min": 0,
                "max": 4,
            },
        ],
        "ports": [
            {
                "name": "Clock and Reset",
                "descr": "Clock Signal",
                "signals": [
                    {
                        "name": "clk_i",
                        "descr": "clock",
                        "width": "1",
                    },
                    {
                        "name": "rst_ni",
                        "descr": "CPU synchronous reset",
                        "width": "1",
                    },
                    {
                        "name": "test_en_i",
                        "descr": "enable all clock gates for testing",
                        "width": "1",
                    },
                    {
                        "name": "ram_cfg_i", #this is meant to be prim_ram_1p_pkg::ram_1p_cfg_t
                        "descr": "---",
                        "width": "1",
                    },
                    {
                        "name": "hart_id_i",
                        "descr": "RiscV Core identifier",
                        "width": "32",
                    },
                    {
                        "name": "boot_addr_i",
                        "descr": "Boot Address",
                        "width": "32",
                    },
                ],
            },
            {
                "name": "Instruction Memory Interface",
                "descr": "---",
                "signals": [
                    {
                        "name": "instr_req_o", #output
                        "descr": "---",
                        "width": "1",
                    },
                    {
                        "name": "instr_gnt_i",
                        "descr": "---",
                        "width": "1",
                    },
                    {
                        "name": "instr_rvalid_i",
                        "descr": "---",
                        "width": "1",
                    },
                    {
                        "name": "instr_addr_o", #output
                        "descr": "---",
                        "width": "32",
                    },
                    {
                        "name": "instr_rdata_i",
                        "descr": "---",
                        "width": "32",
                    },
                    {
                        "name": "instr_rdata_intg_i",
                        "descr": "---",
                        "width": "7",
                    },
                    {
                        "name": "instr_err_i",
                        "descr": "---",
                        "width": "1",
                    },
                ],
            },
            {
                "name": "Data Memory Interface",
                "descr": "---",
                "signals": [
                    {
                        "name": "data_req_o", #output
                        "descr": "---",
                        "width": "1",
                    },
                    {
                        "name": "data_gnt_i",
                        "descr": "---",
                        "width": "1",
                    },
                    {
                        "name": "data_rvalid_i",
                        "descr": "---",
                        "width": "1",
                    },
                    {
                        "name": "data_we_o", #output
                        "descr": "---",
                        "width": "1",
                    },
                    {
                        "name": "data_be_o", #output
                        "descr": "---",
                        "width": "4",
                    },
                    {
                        "name": "data_addr_o", #output
                        "descr": "---",
                        "width": "32",
                    },
                    {
                        "name": "data_wdata_o", #output
                        "descr": "---",
                        "width": "32",
                    },
                    {
                        "name": "data_wdata_intg_o",
                        "descr": "---",
                        "width": "7",
                    },
                    {
                        "name": "data_rdata_i",
                        "descr": "---",
                        "width": "32",
                    },
                    {
                        "name": "data_rdata_intg_i",
                        "descr": "---",
                        "width": "7",
                    },
                    {
                        "name": "data_err_i",
                        "descr": "---",
                        "width": "1",
                    },
                ],
            },
            {
                "name": "Interrupt Inputs",
                "descr": "---",
                "signals": [
                    {
                        "name": "irq_software_i",
                        "descr": "---",
                        "width": "1",
                    },
                    {
                        "name": "irq_timer_i",
                        "descr": "---",
                        "width": "1",
                    },
                    {
                        "name": "irq_external_i",
                        "descr": "---",
                        "width": "1",
                    },
                    {
                        "name": "irq_fast_i",
                        "descr": "---",
                        "width": "15",
                    },
                    {
                        "name": "irq_nm_i",
                        "descr": "non-maskeable interrupt",
                        "width": "1",
                    }
                ],
            },
            {
                "name": "Scrambling Interface",
                "descr": "---",
                "signals": [
                    {
                        "name": "scramble_key_valid_i",
                        "descr": "---",
                        "width": "1",
                    },
                    {
                        "name": "scramble_key_i",
                        "descr": "---",
                        "width": "1", #[SCRAMBLE_KEY_W-1:0]
                    },
                    {
                        "name": "scramble_nonce_i",
                        "descr": "---",
                        "width": "1",#[SCRAMBLE_NONCE_W-1:0]
                    },
                    {
                        "name": "scramble_req_o",
                        "descr": "---",
                        "width": "1", #output
                    },
                ],
            },
            {
                "name": "Debug Interface",
                "descr": "---",
                "signals": [
                    {
                        "name": "debug_req_i",
                        "descr": "---",
                        "width": "1",
                    },
                    {
                        "name": "crash_dump_o", #type=crash_dump_t
                        "descr": "---",
                        "width": "1",
                    },
                    {
                        "name": "double_fault_seen_o",
                        "descr": "---",
                        "width": "1",
                    },
                ],
            },
            {
                "name": "CPU Control Signals",
                "descr": "---",
                "signals": [
                    {
                        "name": "fetch_enable_i", #type=ibex_mubi_t
                        "descr": "---",
                        "width": "1",
                    },
                    {
                        "name": "alert_minor_o",
                        "descr": "---",
                        "width": "1",
                    },
                    {
                        "name": "alert_major_internal_o",
                        "descr": "---",
                        "width": "1",
                    },
                    {
                        "name": "alert_major_bus_o",
                        "descr": "---",
                        "width": "1",
                    },
                    {
                        "name": "core_sleep_o",
                        "descr": "---",
                        "width": "1",
                    }
                ],
            },
            {
                "name": "DFT Control Signals",
                "descr": "---",
                "signals": [
                    {
                        "name": "scan_rst_ni",
                        "descr": "---",
                        "width": "1",
                    },
                ],
            },
        ],
        "wires": [
            {
                "name": "cpu_reset",
                "descr": "cpu reset signal",
                "signals": [
                    {"name": "cpu_reset", "width": "1"},
                ],
            },
            
        ],
        "blocks": [
            {
                "core_name": "iob_iob2axil",
                "instance_name": "clint_iob2axil",
                "instance_description": "Convert IOb to AXI lite for CLINT",
                "parameters": {
                    "AXIL_ADDR_W": 16 - 2,
                    "AXIL_DATA_W": "AXI_DATA_W",
                },
                "connect": {
                    "iob_s": "clint_cbus_s",
                    "axil_m": "clint_cbus_axil",
                },
            },
            {
                "core_name": "iob_iob2axil",
                "instance_name": "plic_iob2axil",
                "instance_description": "Convert IOb to AXI lite for PLIC",
                "parameters": {
                    "AXIL_ADDR_W": 22 - 2,
                    "AXIL_DATA_W": "AXI_DATA_W",
                },
                "connect": {
                    "iob_s": "plic_cbus_s",
                    "axil_m": "plic_cbus_axil",
                },
            },
        ],
        "snippets": [
            {
                "verilog_code": """

  // Instantiation of VexRiscv, Plic, and Clint
    ibex_top CPU (
        // Clock and reset
        .clk_i                  (clk_i),
        .rst_ni                 (cpu_reset),
        .test_en_i              (),
        .scan_rst_ni            (),
        .ram_cfg_i              (),

        // Configuration
        .hart_id_i              (),
        .boot_addr_i            (),

        // Instruction memory interface
        .instr_req_o            (),
        .instr_gnt_i            (),
        .instr_rvalid_i         (),
        .instr_addr_o           (),
        .instr_rdata_i          (),
        .instr_rdata_intg_i     (),
        .instr_err_i            (),

        // Data memory interface
        .data_req_o             (),
        .data_gnt_i             (),
        .data_rvalid_i          (),
        .data_we_o              (),
        .data_be_o              (),
        .data_addr_o            (),
        .data_wdata_o           (),
        .data_wdata_intg_o      (),
        .data_rdata_i           (),
        .data_rdata_intg_i      (),
        .data_err_i             (),

        // Interrupt inputs
        .irq_software_i         (),
        .irq_timer_i            (),
        .irq_external_i         (),
        .irq_fast_i             (),
        .irq_nm_i               (),

        // Debug interface
        .debug_req_i            (),
        .crash_dump_o           (),

        // Special control signals
        .fetch_enable_i         (),
        .alert_minor_o          (),
        .alert_major_internal_o (),
        .alert_major_bus_o      (),
        .core_sleep_o           ()
    );


   assign cpu_reset = rst_i | arst_i;

"""
            }
        ],
    }

    return attributes_dict
