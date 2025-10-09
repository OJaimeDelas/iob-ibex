#!/usr/bin/env python3

# =============================================================
# select_tmr.py
#
# made by: Jaime Aguiar - IST Master's Student
# =============================================================
#
# This script selects registers from JSON descriptions for
# Triple Modular Redundancy (TMR) and outputs a file with
# macros that enables it for those registers.
# It enables said registers based on a provided percentage,
# provided/random seed, and json constraints. 
# It can handle three types of JSON input files:


# ----------------------------------------------------------------
# 1) Register List JSON (--json) [wrapped_registers.json]
# * Mandatory
# ----------------------------------------------------------------
#  States which registers exist in the architecture.
#  Registers can be:
#   - Simple strings
#   - Objects with "name", optional "indexes", and optional "disable"
#
# Example:
#
# {
#   "ibex_csr.sv": [
#     "shadow",
#     { "name": "mstatus", 
#       "disable": "dis_flag"},
#     { "name": "irq",
#       "indexes": [ {"default_min": 0, "default_max": 3},
#                    {"default_min": 0, "default_max": 1} ] 
#     } 
#   ],
#   "ibex_decoder.sv": [ "opcode" ]
# }
#
# This enables: {shadow, mstatus, irq_0_0..irq_3_0..irq_0_1..irq_3_1}
# from ibex_csr.sv;
# and {opcode} from ibex_decoder.sv


# ----------------------------------------------------------------
# 2) Disable Flags JSON (--dis_flags) [dis_flags.json]
# * Optional
# ----------------------------------------------------------------
#  Provides a map of flags used to disable specific registers.
#  Any register object that includes `"disable": "<flag>"` will
#  be skipped if the flag is set to 1 in this file.
#
# Example:
#
# { 
# "dis_flag": 1, 
# "DISABLE_MSTATUS": 0 
# }
#
# If a register definition has `"disable": "dis_flag"`,
# it will be excluded.


# ----------------------------------------------------------------
# 3) File Enable JSON (--file_enable) [forced_enabled_files.json]
# * Optional
# ----------------------------------------------------------------
#  Used to force-enable entire files or specific registers.
#
#  Accepted formats:
#       - "filename": []   → enable ALL registers from file
#       - "filename": ["regA", "regB"] → enable ONLY those
#
# Example: 
#
# {
#   "ibex_cs_registers.sv": [],
#   "ibex_csr.sv": ["shadow"]
# }
# 
# Force-enable all regs from ibex_cs_registers.sv
# and only "shadow" from ibex_csr.sv.
#


# ----------------------------------------------------------------
# Notes:
#  * Forced registers are always enabled (TMR_EN=1).
#  * Other registers in the same file remain eligible for random
#    selection unless explicitly listed.
#  * Option --file_enable_include decides if forced registers
#    count toward the target percentage.
#
# ================================================================


import json
import argparse
import datetime
import random
import os

# =============================================================================
# Function: flatten_registers
# Purpose : Recursively expands register definitions into a flat list.
#           Handles indexed registers and disables based on flags.
# =============================================================================
def flatten_registers(data, dis_flags=None, verbose=False):
    """Flatten JSON register definitions into dict {file: [reg1, reg2,...]}."""

    # -------------------------------------------------------------------------
    # Helper: expand_register
    # Purpose: Expand a single register, including index expansion if needed
    # -------------------------------------------------------------------------
    def expand_register(reg_item):
        """Expand indexed registers into full names."""
        name = reg_item.get("name")  # Base register name
        indexes = reg_item.get("indexes", [])  # List of index dicts (optional)

        # ------------------------
        # Check for disable flags
        # ------------------------
        disable_flag = reg_item.get("disable")
        if disable_flag and dis_flags and dis_flags.get(disable_flag, 0) == 1:
            if verbose:
                print(f"[INFO] Skipping register {name} due to disable flag '{disable_flag}'")
            return []  # Skip disabled register entirely

        # ------------------------
        # No indexes: just return name
        # ------------------------
        if not indexes:
            return [name]

        # ------------------------
        # Fill missing default_min/max with 0 if indexes exist
        # ------------------------
        for idx in indexes:
            idx.setdefault("default_min", 0)
            idx.setdefault("default_max", 0)

        # ------------------------
        # Recursive generator for index combinations
        # ------------------------
        def generate(idx_list, prefix=[]):
            if not idx_list:
                yield "_".join(str(p) for p in prefix)
            else:
                idx_range = idx_list[0]
                for i in range(idx_range["default_min"], idx_range["default_max"] + 1):
                    yield from generate(idx_list[1:], prefix + [i])

        # ------------------------
        # Combine base name with index suffixes
        # ------------------------
        expanded_names = [f"{name}_{suffix}" for suffix in generate(indexes)]
        return expanded_names

    # ------------------------
    # Main flattening loop
    # ------------------------
    result = {}
    for file_name, regs in data.items():
        regs_list = []
        for item in regs:
            if isinstance(item, str):
                regs_list.append(item)  # Already a simple register
            elif isinstance(item, dict) and "name" in item:
                regs_list.extend(expand_register(item))
            else:
                raise ValueError(f"Unexpected register format in {file_name}: {item}")
        if verbose:
            print(f"[DEBUG] Found file {file_name} with {len(regs_list)} registers after applying disable flags")
        result[file_name] = regs_list

    return result

# =============================================================================
# Function: select_tmr_exact
# Purpose : Randomly enable registers to match exact percentage
# =============================================================================
def select_tmr_exact(registers_by_file, percentage, verbose=False):
    """Randomly select registers to enable TMR based on exact percentage."""
    all_regs = [reg for regs in registers_by_file.values() for reg in regs]
    total_regs = len(all_regs)
    num_enabled = round(total_regs * percentage / 100)
    enabled_regs = set(random.sample(all_regs, num_enabled))
    tmr_selection = {reg: (1 if reg in enabled_regs else 0) for reg in all_regs}
    if verbose:
        for reg, val in tmr_selection.items():
            print(f"[DEBUG] Register {reg} TMR={'ENABLED' if val else 'DISABLED'}")
    return tmr_selection

# =============================================================================
# Function: apply_forced_files
# Purpose : Handle forced-enable JSON
#           Supports enabling entire files or specific registers in a file
# Notes   : Accepts either:
#           - a list (e.g. ["file1.sv", {"file2.sv": ["regA"]}])
#           - OR a dict at top-level (e.g. {"file1.sv": [], "file2.sv": ["regA"]})
#           Semantics:
#            - string filename  -> enable ALL registers from that file
#            - filename: []     -> enable ALL registers from that file (explicit)
#            - filename: [regs] -> enable ONLY the listed registers (others remain eligible for random selection)
# =============================================================================
def apply_forced_files(registers_by_file, forced_files_json=None, include_forced=False, percentage=50, verbose=False):
    """Pre-process forced-enabled files and calculate remaining registers to randomly select.
    
    Supports two formats in forced_files_json:
    1. Simple list of file names and/or dict entries: all registers in those files are enabled (if file entry is string or empty list).
    2. Dictionary (or list of dict entries) with file as key and list of registers as value: only those registers are enabled.
    """
    import os
    import json

    all_regs = [reg for regs in registers_by_file.values() for reg in regs]
    total_regs = len(all_regs)

    # Initialize TMR selection dict (0=disabled)
    tmr_selection = {reg: 0 for reg in all_regs}
    forced_entries = []

    # Load the forced-enable JSON if provided and file exists
    if forced_files_json:
        if os.path.isfile(forced_files_json):
            with open(forced_files_json, 'r') as f:
                forced_entries = json.load(f)

            # ---------------------------------------------------------------------
            # Accept either a top-level dict or a list:
            # - If user provided a dict (mapping file -> list), convert it into a
            #   normalized list of entries to process below. This avoids the earlier
            #   ambiguity where iterating a dict yielded only filenames (keys) and
            #   caused whole-file enablement when the user actually intended per-register.
            # - If user provided a list already, keep it as-is.
            # ---------------------------------------------------------------------
            if isinstance(forced_entries, dict):
                # Convert top-level dict to list of entries preserving per-file lists
                normalized = []
                for fname, val in forced_entries.items():
                    # If val is falsy (e.g. [] or None), treat as "enable whole file"
                    if not val:
                        normalized.append(fname)  # string entry -> enable all regs in file
                    else:
                        # keep as dict entry -> enable only the provided regs
                        normalized.append({fname: val})
                forced_entries = normalized
        else:
            # File not found; print only if verbose
            if verbose:
                print(f"[INFO] No forced-enable file found at {forced_files_json}, continuing without forced registers.")

    forced_regs = set()

    # ------------------------
    # Process each normalized entry
    # ------------------------
    for entry in forced_entries:
        if isinstance(entry, str):
            # Simple filename entry: force-enable all registers from that file
            if entry in registers_by_file:
                forced_regs.update(registers_by_file[entry])
                if verbose:
                    print(f"[INFO] Forced enabling all {len(registers_by_file[entry])} registers from {entry}")
        elif isinstance(entry, dict):
            # entry is a mapping like { "file.sv": ["regA", "regB"] }
            # We must ENABLE ONLY the listed registers from that file.
            # Crucially: we must NOT give the other registers in that file any extra priority
            # (they remain eligible for random selection just like any other non-forced register).
            for f, regs_to_enable in entry.items():
                if f in registers_by_file:
                    # If user provides an empty list here (should have been normalized earlier),
                    # it would have been turned into a filename string above. But double-check:
                    if not regs_to_enable:
                        # treat as "enable all" for backward compatibility
                        forced_regs.update(registers_by_file[f])
                        if verbose:
                            print(f"[INFO] Forced enabling all {len(registers_by_file[f])} registers from {f} (empty list)")
                    else:
                        # Only enable those registers explicitly listed and present in the file
                        valid_regs = [r for r in regs_to_enable if r in registers_by_file[f]]
                        forced_regs.update(valid_regs)
                        if verbose:
                            print(f"[INFO] Forced enabling {len(valid_regs)} specific registers from {f}: {valid_regs}")
        else:
            # Unknown entry type: ignore but warn if verbose
            if verbose:
                print(f"[WARNING] Ignoring unsupported forced-enable entry: {entry}")

    # Mark forced registers as enabled in the selection map
    for reg in forced_regs:
        tmr_selection[reg] = 1

    # Remaining registers for random selection are those NOT forced
    remaining_regs = [reg for reg in all_regs if reg not in forced_regs]

    # Compute how many additional registers we should enable:
    # - If include_forced is True: forced regs count toward global percentage.
    #   So we need to enable (percentage * total) - len(forced_regs) more (clamped >=0).
    # - If include_forced is False: we apply the percentage only to the remaining regs.
    if include_forced:
        num_enabled = max(round(total_regs * percentage / 100) - len(forced_regs), 0)
    else:
        num_enabled = round(len(remaining_regs) * percentage / 100)

    # Return:
    #  - tmr_selection: dict with forced regs already set to 1
    #  - remaining_regs: list of regs eligible for random selection
    #  - num_enabled: number of additional regs to randomly enable from remaining_regs
    return tmr_selection, remaining_regs, num_enabled


# =============================================================================
# Function: write_svh_file
# Purpose : Output the SVH file with TMR defines and register lists
# =============================================================================
def write_svh_file(output_file, tmr_selection, json_file, folder, percentage, seed, registers_by_file):
    enabled_by_file = {file: [] for file in registers_by_file}
    disabled_by_file = {file: [] for file in registers_by_file}

    for file, regs in registers_by_file.items():
        for reg in regs:
            if tmr_selection.get(reg, 0):
                enabled_by_file[file].append(reg)
            else:
                disabled_by_file[file].append(reg)

    with open(output_file, 'w') as f:
        f.write("// =============================================================\n")
        f.write("// Auto-generated by tmr_select.py\n")
        f.write(f"// Source JSON   : {json_file}\n")
        f.write(f"// Folder        : {folder}\n")
        f.write(f"// Percentage    : {percentage}%\n")
        f.write(f"// Seed          : {seed}\n")
        f.write(f"// Generated on  : {datetime.datetime.now().strftime('%d/%m/%Y %H:%M')}\n")
        f.write("// =============================================================\n")
        f.write("// made by: Jaime Aguiar - IST Master's Student\n")
        f.write("// =============================================================\n\n")

        f.write("// =============================================================\n")
        f.write("// TMR Register Defines:\n")
        f.write("//\n") 
        f.write("// Each register in the fatori-v design can be selectively\n") 
        f.write("// triplicated for Triple Modular Redundancy (TMR) protection.\n") 
        f.write("// The <reg>_TMR_EN macros indicate whether TMR is enabled (1)\n") 
        f.write("// or disabled (0) for that specific register. These defines\n") 
        f.write("// allow the RTL code to conditionally instantiate triplicated\n") 
        f.write("// logic only for the registers that require redundancy.\n") 
        f.write("// These condition can be configured by the user.\n") 
        f.write("// =============================================================\n\n")

        f.write("\n\n// =============================================================\n") 
        f.write("// MACRO's Definitions:\n")
        f.write("// * Reg List after\n")
        f.write("// -------------------------------------------------------------\n\n")

        # In order for all the files access the macros, they need to be included.
        # To ease work, the include was added to the macro itself, in prim_assert.sv
        # Now, there is the possibility to over-include it.
        # For that, we use "ifndef"

        f.write("`ifndef FATORI_TMR_CONFIG_SVH\n")
        f.write("`define FATORI_TMR_CONFIG_SVH\n\n")



        for file, regs in registers_by_file.items():
            f.write(f"// From {file}\n")
            for reg in regs:
                val = tmr_selection[reg]
                f.write(f"`define {reg}_TMR_EN {val}\n")
            f.write("\n")

        f.write("\n\n// =============================================================\n") 
        f.write("// Register List:\n\n") 

        f.write("// -------------------------------------------------------------\n") 
        f.write("// Enabled Registers:\n") 
        f.write("// -------------------------------------------------------------\n\n")

        # Enabled/Disabled Register Lists
        for file, regs in enabled_by_file.items():
            if regs:
                f.write(f"// {file}:\n")
                for reg in sorted(regs):
                    f.write(f"//   {reg}\n")
                f.write("\n")

        f.write("// -------------------------------------------------------------\n") 
        f.write("// Disabled Registers:\n") 
        f.write("// -------------------------------------------------------------\n\n")
        for file, regs in disabled_by_file.items():
            if regs:
                f.write(f"// {file}:\n")
                for reg in sorted(regs):
                    f.write(f"//   {reg}\n")
                f.write("\n")

        f.write("\n`endif\n")

# =============================================================================
# Function: main
# Purpose : Parse arguments, read JSONs, generate TMR selections, write SVH
# =============================================================================
def main():
    parser = argparse.ArgumentParser(description="TMR register selector")
    parser.add_argument('--json', required=True, help="Input JSON file with register list")
    parser.add_argument('--percentage', type=int, default=50, help="Percentage of registers to TMR")
    parser.add_argument('--out', required=True, help="Output SVH file")
    parser.add_argument('--verbose', action='store_true', help="Verbose debug output")
    parser.add_argument('--seed', type=int, help="Optional random seed")
    parser.add_argument('--file_enable', help="JSON list of files to forcibly enable")
    parser.add_argument('--file_enable_include', action='store_true', help="Include forced files in percentage count")
    parser.add_argument('--dis_flags', help="JSON file with disable flags")
    args = parser.parse_args()

    # ------------------------
    # Setup random seed
    # ------------------------
    seed = args.seed or random.randint(0, 1_000_000)
    random.seed(seed)
    print(f"[INFO] Starting TMR selection with JSON={args.json} Seed={seed}")

    # ------------------------
    # Load disable flags (optional, safe)
    # ------------------------
    dis_flags = {}
    if args.dis_flags:
        if os.path.isfile(args.dis_flags):
            with open(args.dis_flags, 'r') as f:
                dis_flags = json.load(f)
            if args.verbose:
                print(f"[INFO] Loaded disable flags from {args.dis_flags}")
        else:
            if args.verbose:
                print(f"[INFO] No disable flags file found at {args.dis_flags}, continuing without flags.")

    # ------------------------
    # Apply forced-enable files (optional, safe)
    # ------------------------
    forced_file_arg = args.file_enable if args.file_enable and os.path.isfile(args.file_enable) else None
    if args.file_enable and not os.path.isfile(args.file_enable) and args.verbose:
        print(f"[INFO] No forced-enable file found at {args.file_enable}, continuing without forced registers.")


    # ------------------------
    # Load register JSON
    # ------------------------
    with open(args.json, 'r') as f:
        json_data = json.load(f)

    # ------------------------
    # Flatten register definitions
    # ------------------------
    registers_by_file = flatten_registers(json_data, dis_flags=dis_flags, verbose=args.verbose)

    # ------------------------
    # Apply forced-enable files
    # ------------------------
    tmr_selection, remaining_regs, num_enabled = apply_forced_files(
        registers_by_file,
        forced_files_json=forced_file_arg,
        include_forced=args.file_enable_include,
        percentage=args.percentage,
        verbose=args.verbose
    )

    # ------------------------
    # Randomly enable remaining registers to meet percentage
    # ------------------------
    if num_enabled > 0 and remaining_regs:
        enabled_remaining = set(random.sample(remaining_regs, min(num_enabled, len(remaining_regs))))
        for reg in enabled_remaining:
            tmr_selection[reg] = 1
        if args.verbose:
            print(f"[INFO] Randomly enabled {len(enabled_remaining)} additional registers")

    # ------------------------
    # Write the SVH output
    # ------------------------
    folder = os.path.dirname(os.path.abspath(args.out))
    write_svh_file(args.out, tmr_selection, args.json, folder, args.percentage, seed, registers_by_file)

    # ------------------------
    # Print summary
    # ------------------------
    total_regs = len(tmr_selection)
    enabled_regs = sum(tmr_selection.values())
    print(f"[INFO] TMR configuration written to {args.out}. Enabled {enabled_regs} out of {total_regs} registers.")

# =============================================================================
# Script entry point
# =============================================================================
if __name__ == "__main__":
    main()
