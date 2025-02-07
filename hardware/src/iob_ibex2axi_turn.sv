module iob_ibex2axi_turn (
    input  logic clk_i,
    input  logic cke_i,
    input  logic arst_i,
    input  logic req_0,
    input  logic gnt_0,
    input  logic req_1,
    input  logic gnt_1,
    input  logic stalling_i,
    output logic data_allowed,
    output logic [1:0] curr_turn // 2-bit output to represent different turns
);


    localparam [1:0] TURN_NO = 2'b00, TURN_0 = 2'b01, TURN_1 = 2'b10, TURN_STALL = 2'b11;

    // Declare a register for last turn

    always_ff @(posedge clk_i or posedge arst_i) begin
        if (arst_i) begin
            curr_turn <= TURN_NO;    // Default to module 0's turn
        end else if (cke_i) begin
            case (curr_turn)

                TURN_0: begin // Module 0's turn

                    if (stalling_i) begin
                        curr_turn <= TURN_STALL; // Stall
                    end else begin

                        if (gnt_0) begin //This turn has finished
                            if (req_1) begin //Does Module 1 want it?
                                curr_turn <= TURN_1; // Switch to Module 1
                            end else begin
                                curr_turn <= TURN_NO; // Module 0's turn over
                            end
                        end else begin
                            curr_turn <= TURN_0; // Stay with module 0's turn, while no gnt signal
                        end
                    end
                end
                TURN_1: begin // Module 1's turn

                    if (stalling_i) begin
                        curr_turn <= TURN_STALL; // Stall
                    end else begin
                        if (gnt_1) begin //This turn has finished
                            if (req_0) begin //Does Module 0 want it?
                                curr_turn <= TURN_0; // Switch to Module 0
                            end else begin
                                curr_turn <= TURN_NO; // Module 1's turn over
                            end
                        end else begin
                            curr_turn <= TURN_1; // Stay with module 0's turn, while no gnt signal
                        end
                    end
                end

                TURN_STALL: begin // Stall

                    if (stalling_i & req_0) begin
                        data_allowed <= '1; 
                        curr_turn <= TURN_STALL; // Keep Stalling
                    end if (stalling_i & req_1) begin
                        data_allowed <= '0; 
                        curr_turn <= TURN_STALL; // Keep Stalling
                    end else if (stalling_i) begin
                        data_allowed <= '0; 
                        curr_turn <= TURN_STALL; // Keep Stalling
                    end else begin
                        curr_turn <= TURN_NO; // Continue Operation
                    end
                end

                default: begin // No one's turn (TURN_NO)

                    if (stalling_i) begin
                        curr_turn <= TURN_STALL; // Stall
                    end else begin

                        if (req_0) begin //Does Module 0 want it?
                            curr_turn <= TURN_0; // Switch to Module 0
                        end else if (req_1) begin //Does Module 0 want it?
                            curr_turn <= TURN_1; // Switch to Module 0
                        end else begin //Keep in TURN_NO
                            curr_turn <= TURN_NO;
                        end
                    end
                    
                end
            endcase
        end
    end

endmodule
