// =============================================================================
// FATORI-V: Fault Injection Communications Controller
// File: fi_coms.v
// 
// Hardware UART-based fault injection command router with configurable
// debug/acknowledgment modes for high-speed register-level fault campaigns.
// Routes both SEM and FI-REG messages to a single UART
// =============================================================================
`timescale 1ns/1ps

module fi_coms #(
    parameter CLOCK_FREQ_HZ = 100_000_000,
    parameter BAUD_RATE = 1_250_000,
    parameter DEBUG = 1,
    parameter ACK = 1     // Minimal acknowledgment when DEBUG=0
) (
    input wire clk,
    input wire rst,
    input wire uart_rx,
    output wire uart_tx,
    output reg sem_uart_rx,
    input wire sem_uart_tx,
    output reg [7:0] fi_port,
    
    // Injection pulse tracking (for fault_mgr Layer 3 metrics)
    output reg reg_injection_pulse,     // Pulses when 'R' message detected
    output reg logic_injection_pulse    // Pulses when 'N' message detected
);

    localparam CYCLES_PER_BIT = CLOCK_FREQ_HZ / BAUD_RATE;
    localparam HALF_BIT_CYCLES = CYCLES_PER_BIT / 2;

    // =========================================================================
    // UART RX Decoder 
    // =========================================================================
    
    reg uart_rx_meta, uart_rx_sync;
    always @(posedge clk) begin
        if (rst) begin
            uart_rx_meta <= 1'b1;
            uart_rx_sync <= 1'b1;
        end else begin
            uart_rx_meta <= uart_rx;
            uart_rx_sync <= uart_rx_meta;
        end
    end
    
    reg [15:0] rx_clk_count;
    reg [2:0] rx_bit_index;
    reg [7:0] rx_byte;
    reg rx_valid;
    reg [1:0] rx_state;
    
    localparam RX_IDLE = 2'd0, RX_START = 2'd1, RX_DATA = 2'd2, RX_STOP = 2'd3;
    
    always @(posedge clk) begin
        if (rst) begin
            rx_state <= RX_IDLE;
            rx_clk_count <= 16'd0;
            rx_bit_index <= 3'd0;
            rx_byte <= 8'd0;
            rx_valid <= 1'b0;
        end else begin
            rx_valid <= 1'b0;
            case (rx_state)
                RX_IDLE: begin
                    rx_clk_count <= 16'd0;
                    if (!uart_rx_sync) rx_state <= RX_START;
                end
                RX_START: begin
                    if (rx_clk_count == HALF_BIT_CYCLES - 1) begin
                        rx_state <= (!uart_rx_sync) ? RX_DATA : RX_IDLE;
                        rx_clk_count <= 16'd0;
                    end else begin
                        rx_clk_count <= rx_clk_count + 16'd1;
                    end
                end
                RX_DATA: begin
                    if (rx_clk_count == CYCLES_PER_BIT - 1) begin
                        rx_clk_count <= 16'd0;
                        rx_byte[rx_bit_index] <= uart_rx_sync;
                        rx_state <= (rx_bit_index == 3'd7) ? RX_STOP : RX_DATA;
                        rx_bit_index <= (rx_bit_index == 3'd7) ? 3'd0 : rx_bit_index + 3'd1;
                    end else begin
                        rx_clk_count <= rx_clk_count + 16'd1;
                    end
                end
                RX_STOP: begin
                    if (rx_clk_count == CYCLES_PER_BIT - 1) begin
                        if (uart_rx_sync) rx_valid <= 1'b1;
                        rx_state <= RX_IDLE;
                        rx_clk_count <= 16'd0;
                    end else begin
                        rx_clk_count <= rx_clk_count + 16'd1;
                    end
                end
            endcase
        end
    end

    // =========================================================================
    // Command Parser
    // =========================================================================
    
    reg [1:0] cmd_state;
    localparam CMD_IDLE = 2'd0;
    localparam CMD_R_WAIT_ID = 2'd1;
    localparam CMD_N_WAIT_ID = 2'd2;
    
    reg [7:0] cmd_reg_id;
    reg cmd_enqueue;
    reg cmd_forward;
    reg cmd_logic_inject;  // New: marks logic injection command
    
    always @(posedge clk) begin
        if (rst) begin
            cmd_state <= CMD_IDLE;
            cmd_reg_id <= 8'd0;
            cmd_enqueue <= 1'b0;
            cmd_forward <= 1'b0;
            cmd_logic_inject <= 1'b0;
        end else begin
            cmd_enqueue <= 1'b0;
            cmd_forward <= 1'b0;
            cmd_logic_inject <= 1'b0;
            
            if (rx_valid) begin
                case (cmd_state)
                    CMD_IDLE: begin
                        if (rx_byte == 8'h52) begin              // 'R' = 0x52
                            cmd_state <= CMD_R_WAIT_ID;
                        end else if (rx_byte == 8'h4E) begin     // 'N' = 0x4E
                            cmd_state <= CMD_N_WAIT_ID;
                        end else begin
                            cmd_forward <= 1'b1;
                        end
                    end
                    
                    CMD_R_WAIT_ID: begin
                        cmd_reg_id <= rx_byte;
                        cmd_enqueue <= 1'b1;
                        cmd_state <= CMD_IDLE;
                    end
                    
                    CMD_N_WAIT_ID: begin
                        // Logic injection: forward to SEM, mark for pulse tracking
                        cmd_forward <= 1'b1;
                        cmd_logic_inject <= 1'b1;
                        cmd_state <= CMD_IDLE;
                    end
                endcase
            end
        end
    end

    // =========================================================================
    // Injection Pulse Generation (for fault_mgr Layer 3 metrics)
    // =========================================================================
    // Generate single-cycle pulses when injection commands are detected.
    // These pulses allow fault_mgr to measure time from injection to detection.
    
    always @(posedge clk) begin
        if (rst) begin
            reg_injection_pulse <= 1'b0;
            logic_injection_pulse <= 1'b0;
        end else begin
            // Pulse when register injection command enqueued
            reg_injection_pulse <= cmd_enqueue;
            
            // Pulse when logic injection command detected
            logic_injection_pulse <= cmd_logic_inject;
        end
    end

    // =========================================================================
    // Register Injection FIFO
    // =========================================================================
    
    reg [7:0] reg_fifo [0:31];
    reg [4:0] fifo_wr_ptr, fifo_rd_ptr;
    reg [5:0] fifo_count;
    
    (* mark_debug = "true" *) wire fifo_empty = (fifo_count == 6'd0);
    wire fifo_full = (fifo_count == 6'd32);
    
    reg fifo_dequeue;
    
    always @(posedge clk) begin
        if (rst) begin
            fifo_wr_ptr <= 5'd0;
            fifo_rd_ptr <= 5'd0;
            fifo_count <= 6'd0;
        end else begin
            if (cmd_enqueue && !fifo_full) begin
                reg_fifo[fifo_wr_ptr] <= cmd_reg_id;
                fifo_wr_ptr <= fifo_wr_ptr + 5'd1;
                fifo_count <= fifo_count + 6'd1;
            end
            
            if (fifo_dequeue && !fifo_empty) begin
                fifo_rd_ptr <= fifo_rd_ptr + 5'd1;
                fifo_count <= fifo_count - 6'd1;
            end
            
            if (cmd_enqueue && fifo_dequeue && !fifo_full && !fifo_empty) begin
                fifo_count <= fifo_count;
            end
        end
    end
    
    wire [7:0] fifo_rd_data = reg_fifo[fifo_rd_ptr];

    // =========================================================================
    // Debug Transmitter Status
    // =========================================================================
    
    (* mark_debug = "true" *) wire debug_tx_busy;  // High when transmitter is sending
    (* mark_debug = "true" *) wire debug_ack_done; // Pulses when final "INJ - REG XX" completes

    // =========================================================================
    // Injection Handler 
    // =========================================================================
    // State progression (1 cycle each):
    //   INJ_IDLE     -> check fifo, dequeue
    //   INJ_PULSE    -> set fi_port = ID
    //   INJ_CLEAR    -> clear fi_port = 0     <-- CRITICAL: only 1 cycle HIGH
    //   INJ_ACK      -> wait for debug completion
    //   INJ_WAIT     -> ensure clean separation
    // 
    // Debug messages trigger on state ENTRY but don't block state transitions.
    // Only INJ_IDLE checks debug_tx_busy (to avoid message collision).
    // Only INJ_ACK waits for debug_ack_done (final message complete).
    // =========================================================================
    
    (* mark_debug = "true" *) reg [2:0] inj_state;
    localparam INJ_IDLE = 3'd0;
    localparam INJ_PULSE = 3'd1;
    localparam INJ_CLEAR = 3'd2;
    localparam INJ_ACK = 3'd3;
    localparam INJ_WAIT = 3'd4;
    
    reg [7:0] current_reg_id;
    
    always @(posedge clk) begin
        if (rst) begin
            fi_port <= 8'd0;
            inj_state <= INJ_IDLE;
            current_reg_id <= 8'd0;
            fifo_dequeue <= 1'b0;
        end else begin
            fifo_dequeue <= 1'b0;
            
            case (inj_state)
                INJ_IDLE: begin
                    fi_port <= 8'd0;
                    // Only start new injection if debug transmitter is idle
                    // (avoids corrupting in-flight debug messages)
                    if (!fifo_empty && !debug_tx_busy) begin
                        current_reg_id <= fifo_rd_data;
                        fifo_dequeue <= 1'b1;
                        inj_state <= INJ_PULSE;  // Advance immediately
                    end
                end
                
                INJ_PULSE: begin
                    // Set fi_port HIGH for exactly 1 cycle
                    fi_port <= current_reg_id;
                    inj_state <= INJ_CLEAR;  // Advance immediately (no wait!)
                end
                
                INJ_CLEAR: begin
                    // Clear fi_port after 1 cycle
                    fi_port <= 8'd0;
                    inj_state <= INJ_ACK;  // Advance immediately (no wait!)
                end
                
                INJ_ACK: begin
                    // Wait for debug "INJ - REG XX" message to complete
                    if (debug_ack_done) begin
                        inj_state <= INJ_WAIT;
                    end
                    // Note: fi_port remains 0 during this entire wait
                end
                
                INJ_WAIT: begin
                    // Extra cycle to ensure clean separation before next injection
                    // (allows debug_tx_busy to clear after debug_ack_done pulse)
                    if (!debug_tx_busy) begin
                        inj_state <= INJ_IDLE;
                    end
                end
                
                default: begin
                    inj_state <= INJ_IDLE;
                    fi_port <= 8'd0;
                end
            endcase
        end
    end

    // =========================================================================
    // SEM UART RX Regeneration
    // =========================================================================
    
    reg [2:0] sem_tx_state;
    reg [15:0] sem_tx_clk_count;
    reg [2:0] sem_tx_bit_index;
    reg [7:0] sem_tx_byte;
    
    localparam SEM_IDLE = 3'd0, SEM_START = 3'd1, SEM_DATA = 3'd2, SEM_STOP = 3'd3;
    
    always @(posedge clk) begin
        if (rst) begin
            sem_tx_state <= SEM_IDLE;
            sem_uart_rx <= 1'b1;
        end else begin
            case (sem_tx_state)
                SEM_IDLE: begin
                    sem_uart_rx <= 1'b1;
                    if (cmd_forward) begin
                        sem_tx_byte <= rx_byte;
                        sem_tx_state <= SEM_START;
                        sem_tx_clk_count <= 16'd0;
                    end
                end
                SEM_START: begin
                    sem_uart_rx <= 1'b0;
                    if (sem_tx_clk_count == CYCLES_PER_BIT - 1) begin
                        sem_tx_state <= SEM_DATA;
                        sem_tx_clk_count <= 16'd0;
                        sem_tx_bit_index <= 3'd0;
                    end else begin
                        sem_tx_clk_count <= sem_tx_clk_count + 16'd1;
                    end
                end
                SEM_DATA: begin
                    sem_uart_rx <= sem_tx_byte[sem_tx_bit_index];
                    if (sem_tx_clk_count == CYCLES_PER_BIT - 1) begin
                        sem_tx_clk_count <= 16'd0;
                        if (sem_tx_bit_index == 3'd7) begin
                            sem_tx_state <= SEM_STOP;
                        end else begin
                            sem_tx_bit_index <= sem_tx_bit_index + 3'd1;
                        end
                    end else begin
                        sem_tx_clk_count <= sem_tx_clk_count + 16'd1;
                    end
                end
                SEM_STOP: begin
                    sem_uart_rx <= 1'b1;
                    if (sem_tx_clk_count == CYCLES_PER_BIT - 1) begin
                        sem_tx_state <= SEM_IDLE;
                    end else begin
                        sem_tx_clk_count <= sem_tx_clk_count + 16'd1;
                    end
                end
            endcase
        end
    end

    // =========================================================================
    // Debug/ACK Message Transmitter
    // =========================================================================
    // Three modes:
    //   DEBUG=1          → Full debug messages (43 bytes/injection)
    //   DEBUG=0, ACK=1   → Minimal ACK (1 byte/injection)
    //   DEBUG=0, ACK=0   → No messages (maximum speed)
    // =========================================================================
    
    generate
        if (DEBUG) begin : gen_full_debug
            // =====================================================================
            // MODE 3: Full Debug Messages (43 bytes)
            // =====================================================================
            
            reg [7:0] msg_buffer [0:15];
            reg [3:0] msg_len;
            reg [3:0] msg_index;
            reg msg_active;
            reg debug_ack_done_reg;
            reg [2:0] last_msg_state;
            
            assign debug_tx_busy = msg_active;
            assign debug_ack_done = debug_ack_done_reg;
            
            reg [2:0] tx_state;
            reg [15:0] tx_clk_count;
            reg [2:0] tx_bit_index;
            reg [7:0] tx_byte;
            reg tx_line;
            
            localparam TX_IDLE = 3'd0, TX_START = 3'd1, TX_DATA = 3'd2, 
                       TX_STOP = 3'd3, TX_NEXT = 3'd4;
            
            function [7:0] nibble_to_hex;
                input [3:0] n;
                begin
                    nibble_to_hex = (n < 10) ? (8'h30 + n) : (8'h41 + n - 10);
                end
            endfunction
            
            always @(posedge clk) begin
                if (rst) begin
                    tx_state <= TX_IDLE;
                    msg_active <= 1'b0;
                    debug_ack_done_reg <= 1'b0;
                    tx_line <= 1'b1;
                    msg_index <= 4'd0;
                    msg_len <= 4'd0;
                    last_msg_state <= INJ_IDLE;
                end else begin
                    debug_ack_done_reg <= 1'b0;
                    
                    case (tx_state)
                        TX_IDLE: begin
                            tx_line <= 1'b1;
                            tx_clk_count <= 16'd0;
                            
                            if (!msg_active && (inj_state != last_msg_state)) begin
                                last_msg_state <= inj_state;
                                
                                case (inj_state)
                                    INJ_PULSE: begin
                                        // "DEQUEUE XX\r\n"
                                        msg_buffer[0] <= 8'h44;  // 'D'
                                        msg_buffer[1] <= 8'h45;  // 'E'
                                        msg_buffer[2] <= 8'h51;  // 'Q'
                                        msg_buffer[3] <= 8'h55;  // 'U'
                                        msg_buffer[4] <= 8'h45;  // 'E'
                                        msg_buffer[5] <= 8'h55;  // 'U'
                                        msg_buffer[6] <= 8'h45;  // 'E'
                                        msg_buffer[7] <= 8'h20;  // ' '
                                        msg_buffer[8] <= nibble_to_hex(current_reg_id[7:4]);
                                        msg_buffer[9] <= nibble_to_hex(current_reg_id[3:0]);
                                        msg_buffer[10] <= 8'h0D;
                                        msg_buffer[11] <= 8'h0A;
                                        msg_len <= 4'd12;
                                        msg_active <= 1'b1;
                                        msg_index <= 4'd0;
                                        tx_byte <= 8'h44;
                                        tx_state <= TX_START;
                                    end
                                    
                                    INJ_CLEAR: begin
                                        // "PULSE XX\r\n"
                                        msg_buffer[0] <= 8'h50;  // 'P'
                                        msg_buffer[1] <= 8'h55;  // 'U'
                                        msg_buffer[2] <= 8'h4C;  // 'L'
                                        msg_buffer[3] <= 8'h53;  // 'S'
                                        msg_buffer[4] <= 8'h45;  // 'E'
                                        msg_buffer[5] <= 8'h20;  // ' '
                                        msg_buffer[6] <= nibble_to_hex(current_reg_id[7:4]);
                                        msg_buffer[7] <= nibble_to_hex(current_reg_id[3:0]);
                                        msg_buffer[8] <= 8'h0D;
                                        msg_buffer[9] <= 8'h0A;
                                        msg_len <= 4'd10;
                                        msg_active <= 1'b1;
                                        msg_index <= 4'd0;
                                        tx_byte <= 8'h50;
                                        tx_state <= TX_START;
                                    end
                                    
                                    INJ_ACK: begin
                                        // "CLEAR\r\n"
                                        msg_buffer[0] <= 8'h43;  // 'C'
                                        msg_buffer[1] <= 8'h4C;  // 'L'
                                        msg_buffer[2] <= 8'h45;  // 'E'
                                        msg_buffer[3] <= 8'h41;  // 'A'
                                        msg_buffer[4] <= 8'h52;  // 'R'
                                        msg_buffer[5] <= 8'h0D;
                                        msg_buffer[6] <= 8'h0A;
                                        msg_len <= 4'd7;
                                        msg_active <= 1'b1;
                                        msg_index <= 4'd0;
                                        tx_byte <= 8'h43;
                                        tx_state <= TX_START;
                                    end
                                endcase
                            end
                            
                            else if (!msg_active && (inj_state == INJ_ACK) && 
                                     (last_msg_state == INJ_ACK)) begin
                                // "INJ - REG XX\r\n"
                                msg_buffer[0] <= 8'h49;  // 'I'
                                msg_buffer[1] <= 8'h4E;  // 'N'
                                msg_buffer[2] <= 8'h4A;  // 'J'
                                msg_buffer[3] <= 8'h20;  // ' '
                                msg_buffer[4] <= 8'h2D;  // '-'
                                msg_buffer[5] <= 8'h20;  // ' '
                                msg_buffer[6] <= 8'h52;  // 'R'
                                msg_buffer[7] <= 8'h45;  // 'E'
                                msg_buffer[8] <= 8'h47;  // 'G'
                                msg_buffer[9] <= 8'h20;  // ' '
                                msg_buffer[10] <= nibble_to_hex(current_reg_id[7:4]);
                                msg_buffer[11] <= nibble_to_hex(current_reg_id[3:0]);
                                msg_buffer[12] <= 8'h0D;
                                msg_buffer[13] <= 8'h0A;
                                msg_len <= 4'd14;
                                msg_active <= 1'b1;
                                msg_index <= 4'd0;
                                tx_byte <= 8'h49;
                                tx_state <= TX_START;
                                last_msg_state <= INJ_WAIT;
                            end
                        end
                        
                        TX_START: begin
                            tx_line <= 1'b0;
                            if (tx_clk_count == CYCLES_PER_BIT - 1) begin
                                tx_clk_count <= 16'd0;
                                tx_state <= TX_DATA;
                                tx_bit_index <= 3'd0;
                            end else begin
                                tx_clk_count <= tx_clk_count + 16'd1;
                            end
                        end
                        
                        TX_DATA: begin
                            tx_line <= tx_byte[tx_bit_index];
                            if (tx_clk_count == CYCLES_PER_BIT - 1) begin
                                tx_clk_count <= 16'd0;
                                if (tx_bit_index == 3'd7) begin
                                    tx_state <= TX_STOP;
                                end else begin
                                    tx_bit_index <= tx_bit_index + 3'd1;
                                end
                            end else begin
                                tx_clk_count <= tx_clk_count + 16'd1;
                            end
                        end
                        
                        TX_STOP: begin
                            tx_line <= 1'b1;
                            if (tx_clk_count == CYCLES_PER_BIT - 1) begin
                                tx_clk_count <= 16'd0;
                                tx_state <= TX_NEXT;
                            end else begin
                                tx_clk_count <= tx_clk_count + 16'd1;
                            end
                        end
                        
                        TX_NEXT: begin
                            if (msg_index < msg_len - 1) begin
                                msg_index <= msg_index + 4'd1;
                                tx_byte <= msg_buffer[msg_index + 4'd1];
                                tx_state <= TX_START;
                            end else begin
                                tx_line <= 1'b1;
                                msg_active <= 1'b0;
                                msg_index <= 4'd0;
                                
                                if (inj_state == INJ_ACK || inj_state == INJ_WAIT) begin
                                    debug_ack_done_reg <= 1'b1;
                                end
                                
                                tx_state <= TX_IDLE;
                            end
                        end
                        
                        default: begin
                            tx_state <= TX_IDLE;
                            msg_active <= 1'b0;
                        end
                    endcase
                end
            end
            
            assign uart_tx = msg_active ? tx_line : sem_uart_tx;
            
        end else if (ACK) begin : gen_minimal_ack
            // =====================================================================
            // MODE 2: Minimal ACK (1 byte: '.')
            // =====================================================================
            
            reg ack_active;
            reg debug_ack_done_reg;
            reg [2:0] last_ack_state;
            
            assign debug_tx_busy = ack_active;
            assign debug_ack_done = debug_ack_done_reg;
            
            reg [2:0] tx_state;
            reg [15:0] tx_clk_count;
            reg [2:0] tx_bit_index;
            reg tx_line;
            reg [7:0] tx_byte;
            
            localparam TX_IDLE = 3'd0, TX_START = 3'd1, TX_DATA = 3'd2, TX_STOP = 3'd3;
            
            always @(posedge clk) begin
                if (rst) begin
                    tx_state <= TX_IDLE;
                    ack_active <= 1'b0;
                    debug_ack_done_reg <= 1'b0;
                    tx_line <= 1'b1;
                    last_ack_state <= INJ_IDLE;
                end else begin
                    debug_ack_done_reg <= 1'b0;
                    
                    case (tx_state)
                        TX_IDLE: begin
                            tx_line <= 1'b1;
                            tx_clk_count <= 16'd0;
                            
                            // Send single '.' character when entering INJ_ACK
                            if (!ack_active && (inj_state == INJ_ACK) && 
                                (last_ack_state != INJ_ACK)) begin
                                last_ack_state <= INJ_ACK;
                                ack_active <= 1'b1;
                                tx_byte <= 8'h2E;  // Load '.' character
                                tx_state <= TX_START;
                            end else if (inj_state != INJ_ACK) begin
                                last_ack_state <= inj_state;
                            end
                        end
                        
                        TX_START: begin
                            tx_line <= 1'b0;  // Start bit
                            if (tx_clk_count == CYCLES_PER_BIT - 1) begin
                                tx_clk_count <= 16'd0;
                                tx_state <= TX_DATA;
                                tx_bit_index <= 3'd0;
                            end else begin
                                tx_clk_count <= tx_clk_count + 16'd1;
                            end
                        end
                        
                        TX_DATA: begin
                            tx_line <= tx_byte[tx_bit_index];  // '.' = 0x2E
                            if (tx_clk_count == CYCLES_PER_BIT - 1) begin
                                tx_clk_count <= 16'd0;
                                if (tx_bit_index == 3'd7) begin
                                    tx_state <= TX_STOP;
                                end else begin
                                    tx_bit_index <= tx_bit_index + 3'd1;
                                end
                            end else begin
                                tx_clk_count <= tx_clk_count + 16'd1;
                            end
                        end
                        
                        TX_STOP: begin
                            tx_line <= 1'b1;  // Stop bit
                            if (tx_clk_count == CYCLES_PER_BIT - 1) begin
                                tx_line <= 1'b1;
                                ack_active <= 1'b0;
                                debug_ack_done_reg <= 1'b1;  // Pulse done
                                tx_state <= TX_IDLE;
                            end else begin
                                tx_clk_count <= tx_clk_count + 16'd1;
                            end
                        end
                        
                        default: begin
                            tx_state <= TX_IDLE;
                            ack_active <= 1'b0;
                        end
                    endcase
                end
            end
            
            assign uart_tx = ack_active ? tx_line : sem_uart_tx;
            
        end else begin : gen_no_messages
            // =====================================================================
            // MODE 1: No Messages (MAXIMUM SPEED)
            // =====================================================================
            
            assign debug_tx_busy = 1'b0;      // Never busy
            assign debug_ack_done = 1'b1;     // Always ready
            assign uart_tx = sem_uart_tx;     // Direct passthrough
        end
    endgenerate
    
endmodule