# SPDX-FileCopyrightText: 2024 IObundle
#
# SPDX-License-Identifier: MIT

# (c) 2022-Present IObundle, Lda, all rights reserved

SETUP_DIR ?= build/ibex_out
COPY_DIR ?= hardware/copy
WITH_SOC ?= 1  # Flag to indicate if this Makefile is run from the top-level iob-soc-ibex Makefile

# Add files that are not suposed to be copied from ibex repo to the Build Directory (because there is an updated version in iob_ibex, or are not needed)

NO_GENERATE_FILES ?= ibex_wb_stage.sv ibex_lockstep.sv ibex_top.sv ibex_controller.sv ibex_core.sv ibex_cs_registers.sv ibex_csr.sv ibex_decoder.sv ibex_dummy_instr.sv ibex_fetch_fifo.sv ibex_id_stage.sv ibex_if_stage.sv prim_assert.sv iob_reg_re_tmr.sv ibex_load_store_unit.sv ibex_prefetch_buffer.sv prim_mubi4_dec.sv prim_mubi4_sender.sv prim_mubi4_sync.sv prim_mubi8_dec.sv prim_mubi8_sender.sv prim_mubi8_sync.sv prim_mubi12_dec.sv prim_mubi12_sender.sv prim_mubi12_sync.sv prim_mubi16_dec.sv prim_mubi16_sender.sv prim_mubi16_sync.sv prim_mubi20_dec.sv prim_mubi20_sender.sv prim_mubi20_sync.sv prim_mubi24_dec.sv prim_mubi24_sender.sv prim_mubi24_sync.sv prim_mubi28_dec.sv prim_mubi28_sender.sv prim_mubi28_sync.sv prim_mubi32_dec.sv prim_mubi32_sender.sv prim_mubi32_sync.sv

# Files in this folder will also not be copied
HDW_SRC_DIR ?= hardware/src

# TMR config generation parameters
# for fatori-v usage
TMR_SCRIPT   		?= select_tmr.py
TMR_FOLDER	 		?= fault_tolerance/tmr
TMR_FINAL_FOLDER   	?= hardware/src
TMR_WRAP_FILE     	?= wrapped_registers.json
TMR_PERCENT 		?= 0
TMR_SEED     		?=
TMR_OUT      		?= $(TMR_FINAL_FOLDER)/fatori_tmr_config.svh
TMR_FORCED_FILE   	?= forced_enabled_files.json         	# JSON with forced-enable registers/files
TMR_FILE_INCLUDE  	?= 1        							# set to 1 to include forced regs in percentage
TMR_DIS_FLAGS     	?= dis_flags.json         				# JSON with disable flags
VERBOSE           	?= 0        							# set to 1 for debug output


# Colors for terminal personalisation
GREEN  := \033[0;32m
YELLOW := \033[1;33m
RED    := \033[0;31m
RESET  := \033[0m


# Use fusesoc to generate all ibex prim and RTL files
# cd submodules/ibex && fusesoc --cores-root . run --target=lint --setup --build-root $(SETUP_DIR) lowrisc:ibex:ibex_top
generate-ibex:
	nix --extra-experimental-features nix-command --no-warn-dirty --extra-experimental-features flakes develop --command bash -c "cd submodules/ibex && fusesoc --cores-root . run --target=lint --setup --build-root $(SETUP_DIR) lowrisc:ibex:ibex_top"

# Copy extracted files to the Build Directory
# The copied files must not be UNWANTED, or be in iob-ibex/hardware/src
copy-ibex:
	@mkdir -p "$(COPY_DIR)"  # Ensure the COPY_DIR exists
	@find submodules/ibex/$(SETUP_DIR) -type f \( -name "*.v" -o -name "*.sv" -o -name "*.vh" -o -name "*.svh" \) | while read file; do \
		basefile=$$(basename $$file); \
		if [ "$(WITH_SOC)" = "1" ] && [ -f "$(HDW_SRC_DIR)/$$basefile" ]; then \
			:; \
		elif echo "$(NO_GENERATE_FILES)" | grep -q -w "$$basefile"; then \
			:; \
		else \
			cp "$$file" "$(COPY_DIR)/" 1>/dev/null; \
		fi; \
	done

# Generate TMR .svh macro's file
tmr-config:
	@echo "$(YELLOW)[INFO] Generating $(TMR_OUT)...$(RESET)"
	python3 $(TMR_FOLDER)$(if $(TMR_FOLDER),/,$(null))$(TMR_SCRIPT) \
		--json $(TMR_FOLDER)/$(TMR_WRAP_FILE) \
		--percentage $(TMR_PERCENT) \
		$(if $(TMR_SEED),--seed $(TMR_SEED)) \
		--out $(TMR_OUT) \
		--file_enable $(TMR_FOLDER)/$(TMR_FORCED_FILE) \
		$(if $(filter 1,$(TMR_FILE_INCLUDE)),--file_enable_include) \
		--dis_flags $(TMR_FOLDER)/$(TMR_DIS_FLAGS) \
		$(if $(filter 1,$(VERBOSE)),--verbose); \
	
	@echo "$(GREEN)[SUCCESS] fatori_tmr_config.svh generated!$(RESET)"




clean-ibex:
	@echo "Cleaning in submodules/ibex/$(SETUP_DIR)/*..."
	@rm -rf submodules/ibex/$(SETUP_DIR)/*



.PHONY: generate-ibex copy-ibex tmr-config clean-ibex

