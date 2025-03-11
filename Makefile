# SPDX-FileCopyrightText: 2024 IObundle
#
# SPDX-License-Identifier: MIT

# (c) 2022-Present IObundle, Lda, all rights reserved

SETUP_DIR ?= build/ibex_out
IBEX_CONFIG ?= opentitan
COPY_DIR ?= hardware/copy
WITH_SOC ?= 1  # Flag to indicate if this Makefile is run from the top-level iob-soc-ibex Makefile

# Add files that are not suposed to be copied to the Build Directory
UNWANTED_FILES ?= ibex_top.sv

# Files in this folder will also not be copied
HDW_SRC_DIR ?= hardware/src

# Use fusesoc to generate all ibex prim and RTL files
# cd submodules/ibex && fusesoc --cores-root . run --target=lint --setup --build-root $(SETUP_DIR) lowrisc:ibex:ibex_top


# Copy extracted files to the Build Directory
# The copied files must not be UNWANTED, or be in iob-ibex/hardware/src
copy-ibex:
	@find submodules/ibex/$(SETUP_DIR) -type f \( -name "*.v" -o -name "*.sv" -o -name "*.vh" \) | while read file; do \
		basefile=$$(basename $$file); \
		if [ "$(WITH_SOC)" = "1" ] && [ -f "$(HDW_SRC_DIR)/$$basefile" ]; then \
			:; \
		elif echo "$(UNWANTED_FILES)" | grep -q -w "$$basefile"; then \
			:; \
		else \
			cp "$$file" "$(COPY_DIR)/" 1>/dev/null \
		fi; \
	done

clean-ibex:
	@rm -rf submodules/ibex/$(SETUP_DIR)/*

.PHONY: copy-ibex clean-ibex

