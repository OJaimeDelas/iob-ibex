`timescale 1ns / 1ps
`include "iob_reg_re_conf.vh"

module iob_reg_re_tmr #(
    parameter DATA_W  = `IOB_REG_RE_DATA_W,
    parameter RST_VAL = `IOB_REG_RE_RST_VAL,
    parameter TMR_EN  = 0   // 0 = no TMR, 1 = TMR enabled
) (
    input               clk_i,
    input               cke_i,
    input               arst_i,
    input               en_i,
    input               rst_i,
    input  [DATA_W-1:0] data_i,
    output [DATA_W-1:0] data_o,
    output logic          maj_err_o,       // major error
    output logic          min_err_o,       // minor error
    output logic [2:0]    err_loc_o    // In which replica is the error
);

    generate
        if (TMR_EN == 0) begin : no_tmr
            // Single register, no TMR
            iob_reg_re #(
                .DATA_W (DATA_W),
                .RST_VAL(RST_VAL)
            ) reg_inst (
                .clk_i (clk_i),
                .cke_i (cke_i),
                .arst_i(arst_i),
                .en_i  (en_i),
                .rst_i (rst_i),
                .data_i(data_i),
                .data_o(data_o)
            );

            // No errors when TMR disabled
            always_comb begin
                maj_err_o       = 1'b0;
                min_err_o       = 1'b0;
                err_loc_o   = 3'b000;
            end

        end else begin : tmr_enabled
            // Triplicated registers
            wire [DATA_W-1:0] r0, r1, r2;

            iob_reg_re #(
                .DATA_W (DATA_W),
                .RST_VAL(RST_VAL)
            ) reg0 (
                .clk_i (clk_i),
                .cke_i (cke_i),
                .arst_i(arst_i),
                .en_i  (en_i),
                .rst_i (rst_i),
                .data_i(data_i),
                .data_o(r0)
            );

            iob_reg_re #(
                .DATA_W (DATA_W),
                .RST_VAL(RST_VAL)
            ) reg1 (
                .clk_i (clk_i),
                .cke_i (cke_i),
                .arst_i(arst_i),
                .en_i  (en_i),
                .rst_i (rst_i),
                .data_i(data_i),
                .data_o(r1)
            );

            iob_reg_re #(
                .DATA_W (DATA_W),
                .RST_VAL(RST_VAL)
            ) reg2 (
                .clk_i (clk_i),
                .cke_i (cke_i),
                .arst_i(arst_i),
                .en_i  (en_i),
                .rst_i (rst_i),
                .data_i(data_i),
                .data_o(r2)
            );

            // Word-wise majority voting
            reg [DATA_W-1:0] voted_data;
            always_comb begin
                if (r0 == r1 || r0 == r2)
                    voted_data = r0;
                else if (r1 == r2)
                    voted_data = r1;
                else
                    voted_data = r0; // all disagree, fallback
            end

            assign data_o = voted_data;

            // Per-register error flags (word comparison)
            always_comb begin
                err_loc_o[0] = (r0 != voted_data);
                err_loc_o[1] = (r1 != voted_data);
                err_loc_o[2] = (r2 != voted_data);

                // Minor error = any replica disagrees
                min_err_o = |err_loc_o;

                // Major error = all three disagree
                maj_err_o = &err_loc_o;
            end
        end
    endgenerate

endmodule
