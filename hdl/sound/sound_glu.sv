//
// IIgs GLU
//
// (c) 2023,2024 Ed Anuff <ed@a2fpga.com> 
//
// Permission to use, copy, modify, and/or distribute this software for any
// purpose with or without fee is hereby granted, provided that the above
// copyright notice and this permission notice appear in all copies.
//
// THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
// WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
// MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
// ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
// WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
// ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
// OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
//
// Description:
//
// The GLU interfaces the Ensoniq DOC5503 sound chip to the Apple II bus
//

module sound_glu #(
    parameter bit ENABLE = 1'b1,
    // Exclusive DOC owner: 0 = original GS GLU; 1 = MB-DOC bridge.
    // ENABLE remains asserted in MB mode for DOC waveform fetches.
    parameter bit MB_DOC_MODE = 1'b0,
    parameter bit MONO_MIX = 1'b0, // If true, mono mix is used instead of stereo
    parameter bit USE_BSRAM = 1'b0, // If true, use on-chip BSRAM instead of DDR3 for sound RAM

    // Enables the explicit A2FPGA 128K extension protocol. Even when this
    // parameter is true, reset enters native IIgs-compatible locked mode.
    parameter bit ENABLE_128K_EXTENSION = 1'b0
) (
    a2bus_if.slave a2bus_if,

    // Mockingboard bridge host commands. Synchronous to clk_logic.
    // Address/data must remain valid with the write strobe; the
    // DOC core captures them on the asserted chip-select edge.
    // Not yet driven by the bridge in P1 (tied low by top.sv).
    input  logic       mb_doc_wr_i,
    input  logic [7:0] mb_doc_addr_i,
    input  logic [7:0] mb_doc_data_i,

    // Exclusive MB-DOC waveform preload uses the existing GLU
    // SDRAM write port; DOC oscillator fetch stays on DOC_MEM_PORT.
    input  logic        mb_ram_wr_i,
    input  logic [20:0] mb_ram_addr_i,
    input  logic [31:0] mb_ram_data_i,
    input  logic [3:0]  mb_ram_byte_en_i,
    output logic        mb_ram_ready_o,

    output [7:0] data_o,
    output rd_en_o,

    output [15:0] audio_l_o,
    output [15:0] audio_r_o,

output [7:0] debug_osc_en_o,
output [1:0] debug_osc_mode_o[8],

// Existing oscillator 0-7 HALT output.
// Retained temporarily for compatibility.
output [7:0] debug_osc_halt_o,

// Complete live HALT state for all 32 oscillators.
//
//   bits 31:24 = oscillators  0-7
//   bits 23:16 = oscillators  8-15
//   bits 15:8  = oscillators 16-23
//   bits 7:0   = oscillators 24-31
output [31:0] debug_osc_halt_all_o,

output [7:0] debug_halt_event_o,
    output [7:0] debug_halt_wtp_o,
    output [7:0] debug_halt_rts_o,
output [7:0] debug_swap_ca_o,

output [7:0] debug_host_ctrl_osc_o,
output [7:0] debug_host_ctrl_data_o,
output [7:0] debug_internal_ctrl_event_o,
output [7:0] debug_internal_ctrl_data_o,

// Completed DOC mixer saturation diagnostic.
output [7:0] debug_mix_clip_o,

// One-second DOC clipping histories, newest 125 ms slice in bit 0.
output [7:0] debug_mix_clip_history_left_o,
output [7:0] debug_mix_clip_history_right_o,
output [7:0] debug_mix_clip_history_mono_o,

// DOC oscillator and mixer activity from the last completed 125 ms slice.
output [31:0] debug_nonzero_osc_activity_o,
output [31:0] debug_mixer_osc_activity_o,
output [15:0] debug_channel_activity_o,

// One-second histories of nonzero completed left/right DOC mixes.
output [7:0] debug_left_nonzero_history_o,
output [7:0] debug_right_nonzero_history_o,

// DOC waveform-read diagnostics. Each byte is a stable, saturating count
// from the last completed 125 ms interval.
output [7:0] debug_mem_overlap_count_o,
output [7:0] debug_mem_timeout_count_o,
output [7:0] debug_mem_late_count_o,

// Current Sound GLU control register at $C03C.
//
// The low hexadecimal digit is the native IIgs
// global-volume setting:
//
//   $0 = lowest
//   $F = highest
output [7:0] debug_sound_control_o,

// A2FPGA 128K protocol status:
//
//   $00 = extension is not compiled into this instance
//   $10 = protocol version 1, locked
//   $11 = protocol version 1, unlocked, bank 1 not yet populated
//   $13 = protocol version 1, unlocked, bank 1 populated
output [7:0] debug_128k_status_o,

    mem_port_if.client glu_mem_if,
    mem_port_if.client doc_mem_if
    
);

    reg [7:0] sound_control_r;      // Sound Control Register
    reg [7:0] sound_data_r;         // Sound Data Register 
    reg [7:0] sound_ptr_lo_r;       // Sound Pointer Lo Register
    reg [7:0] sound_ptr_hi_r;       // Sound Pointer Hi Register

    localparam [15:0] SOUND_CONTROL_ADDR = 16'hC03C;
    localparam [15:0] SOUND_DATA_ADDR = 16'hC03D;
    localparam [15:0] SOUND_PTR_LO_ADDR = 16'hC03E;
    localparam [15:0] SOUND_PTR_HI_ADDR = 16'hC03F;

    // address in GLU range, $C03C-$C03F, during phi0 and m2sel_n asserted
    // Disable only *GS CPU access* when Mockingboard owns DOC.
    // Do not gate DOC execution or SDRAM waveform fetches.
    wire glu_sel_w = ENABLE & !MB_DOC_MODE &
        a2bus_if.phi0 &
        (a2bus_if.addr[15:2] == SOUND_CONTROL_ADDR[15:2]) &
        !a2bus_if.m2sel_n;
    // sound control register is at $C03C
    wire sc_sel_w = glu_sel_w & (a2bus_if.addr[1:0] == 2'b00);
    // sound data register is at $C03D
    wire sd_sel_w = glu_sel_w & (a2bus_if.addr[1:0] == 2'b01);
    // address pointer lo register is at $C03E
    wire spl_sel_w = glu_sel_w & (a2bus_if.addr[1:0] == 2'b10);
    // address pointer hi register is at $C03F
    wire sph_sel_w = glu_sel_w & (a2bus_if.addr[1:0] == 2'b11);

 // all accesses are to the dedicated sound RAM
wire access_ram_w = sound_control_r[6];

// all accesses are to the DOC
wire access_doc_w = ~access_ram_w;

// auto increment address pointer
wire auto_inc_w = sound_control_r[5];

// Extension state. Both flags clear on system reset and explicit relock.
logic sound_128k_unlocked_r;
logic sound_128k_enable_r; // Bank 1 has received waveform data.
logic [2:0] sound_128k_key_state_r;

// Bit 4 selects the upload bank only after the explicit protocol unlock.
// While locked it is ignored exactly like the reserved native-IIgs bit.
wire sound_ram_bank_w =
    sound_128k_unlocked_r && sound_control_r[4];

// Volume control, 0 is lowest and 15 is highest.
wire [3:0] volume_w =
    sound_control_r[3:0];

// Display the complete $C03C register.
// The low hexadecimal digit is the volume.
assign debug_sound_control_o =
    sound_control_r;

    //assign rd_en_o = glu_sel_w & a2bus_if.rw_n;
    assign rd_en_o = 1'b0;

    logic [7:0] doc_data_o_w;

    assign data_o = a2bus_if.addr[1:0] == 2'b00 ? sound_control_r :
        (a2bus_if.addr[1:0] == 2'b01) & access_ram_w ? sound_data_r :
        (a2bus_if.addr[1:0] == 2'b01) & access_doc_w ? doc_data_o_w :
        a2bus_if.addr[1:0] == 2'b10 ? sound_ptr_lo_r :
        sound_ptr_hi_r;

    // write only for a2fpga, will need to implement reads at alternate address
    // and for future standalone IIgs core
    // DOC memory is at 0x4_0000/8 or 0x1_0000/32
reg [20:0] glu_mem_addr_r;
reg glu_mem_wr_r;
reg [3:0] glu_mem_byte_en_r;

// The extension uses otherwise-unused DOC register addresses $E2-$E6.
// Software writes the ASCII key "A2FP" to $E2-$E5 followed by a command
// byte at $E6. Command $01 unlocks and command $00 relocks. Any mismatched
// DOC/Sound-RAM data write abandons a partial key.
localparam [7:0] EXT_KEY_ADDR_0 = 8'hE2;
localparam [7:0] EXT_KEY_ADDR_1 = 8'hE3;
localparam [7:0] EXT_KEY_ADDR_2 = 8'hE4;
localparam [7:0] EXT_KEY_ADDR_3 = 8'hE5;
localparam [7:0] EXT_COMMAND_ADDR = 8'hE6;

localparam [7:0] EXT_KEY_DATA_0 = 8'h41; // A
localparam [7:0] EXT_KEY_DATA_1 = 8'h32; // 2
localparam [7:0] EXT_KEY_DATA_2 = 8'h46; // F
localparam [7:0] EXT_KEY_DATA_3 = 8'h50; // P

localparam [7:0] EXT_COMMAND_LOCK = 8'h00;
localparam [7:0] EXT_COMMAND_UNLOCK = 8'h01;

wire extension_addr_w =
    (sound_ptr_hi_r == 8'h00) &&
    (sound_ptr_lo_r >= EXT_KEY_ADDR_0) &&
    (sound_ptr_lo_r <= EXT_COMMAND_ADDR);

assign debug_128k_status_o =
    ENABLE_128K_EXTENSION ?
        {4'h1, 2'b00, sound_128k_enable_r,
         sound_128k_unlocked_r} :
        8'h00;

    assign mb_ram_ready_o =
        MB_DOC_MODE && !USE_BSRAM && glu_mem_if.ready;

    // GLU mem_if driven to DDR3 when USE_BSRAM=0, idle when USE_BSRAM=1
    generate
        if (USE_BSRAM) begin : gen_glu_idle
            assign glu_mem_if.rd = '0;
            assign glu_mem_if.wr = '0;
            assign glu_mem_if.addr = '0;
            assign glu_mem_if.data = '0;
            assign glu_mem_if.byte_en = '0;
            assign glu_mem_if.burst = 1'b0;
        end else begin : gen_glu_ddr3
            assign glu_mem_if.rd = '0;
            // GS and MB sample loader never own RAM together.
            // Preserve the exact original GS path in mode 0.
            assign glu_mem_if.addr = MB_DOC_MODE ?
                mb_ram_addr_i : glu_mem_addr_r;
            assign glu_mem_if.wr = MB_DOC_MODE ?
                mb_ram_wr_i : glu_mem_wr_r;
            assign glu_mem_if.byte_en = MB_DOC_MODE ?
                mb_ram_byte_en_i : glu_mem_byte_en_r;
            assign glu_mem_if.data = MB_DOC_MODE ?
                mb_ram_data_i :
                {a2bus_if.data, a2bus_if.data,
                 a2bus_if.data, a2bus_if.data};
            assign glu_mem_if.burst = 1'b0;
        end
    endgenerate

    reg doc_wr_r;
    reg [7:0] doc_addr_r;

    always_ff @(posedge a2bus_if.clk_logic) begin
        if (!a2bus_if.system_reset_n) begin
            glu_mem_wr_r <= 1'b0;
            glu_mem_addr_r <= 21'h0;
            glu_mem_byte_en_r <= 4'b1111;
            doc_wr_r <= 1'b0;
            doc_addr_r <= 8'h00;
            sound_128k_enable_r <= 1'b0;
            sound_128k_unlocked_r <= 1'b0;
            sound_128k_key_state_r <= 3'd0;
            sound_control_r <= 8'h0F;
            sound_data_r <= 8'h00;
            sound_ptr_lo_r <= 8'h00;
            sound_ptr_hi_r <= 8'h00;
        end else begin
            glu_mem_wr_r <= 1'b0;
            doc_wr_r <= 1'b0;

            if (ENABLE && glu_sel_w &&
                a2bus_if.data_in_strobe &&
                !a2bus_if.rw_n) begin
                case (a2bus_if.addr[1:0])
                    2'b00: begin
                        sound_control_r <= a2bus_if.data;
                        sound_128k_key_state_r <= 3'd0;
                    end

                    2'b01: begin
                        sound_data_r <= a2bus_if.data;

                        if (access_ram_w) begin
                            // Native-compatible while locked: bit 4 is
                            // ignored and every upload targets bank 0.
                            glu_mem_wr_r <= 1'b1;
                            sound_128k_key_state_r <= 3'd0;

                            if (sound_ram_bank_w)
                                sound_128k_enable_r <= 1'b1;

                            glu_mem_addr_r <= {
                                6'b000000,
                                sound_ram_bank_w,
                                sound_ptr_hi_r,
                                sound_ptr_lo_r[7:2]
                            };

                            glu_mem_byte_en_r <=
                                1'b1 << sound_ptr_lo_r[1:0];
                        end else if (access_doc_w) begin
                            if (ENABLE_128K_EXTENSION &&
                                extension_addr_w) begin
                                // Consume extension commands instead of
                                // forwarding the unused $E2-$E6 addresses
                                // into the DOC core.
                                case (sound_128k_key_state_r)
                                    3'd0: begin
                                        if ((sound_ptr_lo_r ==
                                             EXT_KEY_ADDR_0) &&
                                            (a2bus_if.data ==
                                             EXT_KEY_DATA_0)) begin
                                            sound_128k_key_state_r <= 3'd1;
                                        end else begin
                                            sound_128k_key_state_r <= 3'd0;
                                        end
                                    end

                                    3'd1: begin
                                        if ((sound_ptr_lo_r ==
                                             EXT_KEY_ADDR_1) &&
                                            (a2bus_if.data ==
                                             EXT_KEY_DATA_1)) begin
                                            sound_128k_key_state_r <= 3'd2;
                                        end else begin
                                            sound_128k_key_state_r <= 3'd0;
                                        end
                                    end

                                    3'd2: begin
                                        if ((sound_ptr_lo_r ==
                                             EXT_KEY_ADDR_2) &&
                                            (a2bus_if.data ==
                                             EXT_KEY_DATA_2)) begin
                                            sound_128k_key_state_r <= 3'd3;
                                        end else begin
                                            sound_128k_key_state_r <= 3'd0;
                                        end
                                    end

                                    3'd3: begin
                                        if ((sound_ptr_lo_r ==
                                             EXT_KEY_ADDR_3) &&
                                            (a2bus_if.data ==
                                             EXT_KEY_DATA_3)) begin
                                            sound_128k_key_state_r <= 3'd4;
                                        end else begin
                                            sound_128k_key_state_r <= 3'd0;
                                        end
                                    end

                                    3'd4: begin
                                        sound_128k_key_state_r <= 3'd0;

                                        if (sound_ptr_lo_r ==
                                            EXT_COMMAND_ADDR) begin
                                            if (a2bus_if.data ==
                                                EXT_COMMAND_UNLOCK) begin
                                                sound_128k_unlocked_r <=
                                                    1'b1;
                                                sound_128k_enable_r <=
                                                    1'b0;
                                            end else if (a2bus_if.data ==
                                                         EXT_COMMAND_LOCK) begin
                                                sound_128k_unlocked_r <=
                                                    1'b0;
                                                sound_128k_enable_r <=
                                                    1'b0;
                                            end
                                        end
                                    end

                                    default:
                                        sound_128k_key_state_r <= 3'd0;
                                endcase
                            end else begin
                                // Ordinary DOC register write. It also
                                // invalidates any incomplete extension key.
                                doc_wr_r <= 1'b1;
                                doc_addr_r <= sound_ptr_lo_r;
                                sound_128k_key_state_r <= 3'd0;
                            end
                        end

                        if (auto_inc_w) begin
                            {sound_ptr_hi_r, sound_ptr_lo_r} <=
                                {sound_ptr_hi_r, sound_ptr_lo_r} + 1'd1;
                        end
                    end

                    2'b10:
                        sound_ptr_lo_r <= a2bus_if.data;

                    2'b11:
                        sound_ptr_hi_r <= a2bus_if.data;
                endcase
            end else if (ENABLE && glu_sel_w &&
                         a2bus_if.data_in_strobe &&
                         a2bus_if.rw_n &&
                         (a2bus_if.addr[1:0] == 2'b01) &&
                         auto_inc_w) begin
                {sound_ptr_hi_r, sound_ptr_lo_r} <=
                    {sound_ptr_hi_r, sound_ptr_lo_r} + 1'd1;
            end
        end
    end

    // DOC Memory Interface
    // All DOC logic in the sound module is clocked by clk_logic

wire [15:0] wave_addr_w;
wire wave_bank_w;

// Legacy 64K software always reads bank 0. RTS bit 6 gains meaning only
// after the extension is unlocked and bank 1 has received waveform data.
wire wave_bank_active_w =
    sound_128k_unlocked_r &&
    sound_128k_enable_r &&
    wave_bank_w;

wire doc_mem_rd_w;

    reg [1:0] doc_mem_offset_r;

    always_ff @(posedge a2bus_if.clk_logic) begin
        if (doc_mem_rd_w) begin
            doc_mem_offset_r <= wave_addr_w[1:0];
        end
    end

    reg [7:0] wave_data_r;
    reg wave_data_ready_r;
    wire doc_mem_response_event_w;

    generate
        if (USE_BSRAM) begin : gen_doc_bsram
            // Drive DDR3 DOC port idle
            assign doc_mem_if.wr = '0;
            assign doc_mem_if.rd = '0;
            assign doc_mem_if.data = '0;
            assign doc_mem_if.byte_en = '0;
            assign doc_mem_if.addr = '0;
            assign doc_mem_if.burst = 1'b0;

            // BSRAM instance for 64KB sound RAM
            wire [31:0] bsram_rd_data;
            wire        bsram_rd_valid;

            ensoniq_bsram ensoniq_bsram (
                .clk(a2bus_if.clk_logic),

                // Write port (GLU) - use registered signals from always_ff block
                .wr_en(glu_mem_wr_r),
                .wr_addr(glu_mem_addr_r[13:0]),
                .wr_data({sound_data_r, sound_data_r, sound_data_r, sound_data_r}),
                .wr_byte_en(glu_mem_byte_en_r),

                // Read port (DOC)
                .rd_en(ENABLE && doc_mem_rd_w),
                .rd_addr(wave_addr_w[15:2]),
                .rd_data(bsram_rd_data),
                .rd_valid(bsram_rd_valid)
            );

            // BSRAM read completes in 1 cycle (rd_valid is 1 cycle after rd_en)
            assign doc_mem_response_event_w =
                bsram_rd_valid;

            always_ff @(posedge a2bus_if.clk_logic) begin
                wave_data_ready_r <= 1'b0;
                if (bsram_rd_valid) begin
                    wave_data_r <= bsram_rd_data[8*doc_mem_offset_r +: 8];
                    wave_data_ready_r <= 1'b1;
                end
            end

        end else begin : gen_doc_ddr3
            // Original DDR3 path
            assign doc_mem_if.wr = '0;
            assign doc_mem_if.data = '0;
            assign doc_mem_if.byte_en = 4'b1111;
assign doc_mem_if.addr = {
    6'b000000,
    wave_bank_active_w,
    wave_addr_w[15:2]
};
            assign doc_mem_if.rd = ENABLE && doc_mem_rd_w;
            assign doc_mem_if.burst = 1'b0;
            assign doc_mem_response_event_w =
                doc_mem_if.ready;

            always_ff @(posedge a2bus_if.clk_logic) begin
                wave_data_ready_r <= 1'b0;
                if (doc_mem_if.ready) begin
                    wave_data_r <= doc_mem_if.q[8*doc_mem_offset_r +: 8];
                    wave_data_ready_r <= 1'b1;
                end
            end
        end
    endgenerate

    // Track ownership independently of the functional read path. This block
    // observes the existing request/response signals but does not gate, delay,
    // or otherwise modify them.
    //
    // overlap: a new DOC request arrived while an earlier read was outstanding
    // late:    a response arrived with no unique valid request owner
    // timeout: counted in doc5503 at the exact $80-silence substitution point
    wire debug_fetch_timeout_pulse_w;
    wire [7:0] debug_fetch_timeout_count_w;

    logic doc_read_outstanding_r;
    logic doc_read_owner_valid_r;

    wire doc_read_request_event_w =
        ENABLE && doc_mem_rd_w;
    wire doc_read_response_event_w =
        doc_mem_response_event_w;

    wire doc_read_overlap_event_w =
        doc_read_request_event_w &&
        doc_read_outstanding_r &&
        !doc_read_response_event_w &&
        !debug_fetch_timeout_pulse_w;

    wire doc_read_late_event_w =
        doc_read_response_event_w &&
        (debug_fetch_timeout_pulse_w ||
         !doc_read_outstanding_r ||
         !doc_read_owner_valid_r);

    always_ff @(posedge a2bus_if.clk_logic) begin
        if (!a2bus_if.system_reset_n) begin
            doc_read_outstanding_r <= 1'b0;
            doc_read_owner_valid_r <= 1'b0;
        end else begin
            // A delivered response or an oscillator-slot timeout ends the
            // current diagnostic ownership interval.
            if (doc_read_response_event_w ||
                debug_fetch_timeout_pulse_w) begin
                doc_read_outstanding_r <= 1'b0;
                doc_read_owner_valid_r <= 1'b0;
            end

            // A simultaneous completion/timeout closes the old interval;
            // the new request then becomes the unique owner. Otherwise a
            // request over an outstanding read makes ownership ambiguous.
            if (doc_read_request_event_w) begin
                doc_read_outstanding_r <= 1'b1;

                if (doc_read_outstanding_r &&
                    !doc_read_response_event_w &&
                    !debug_fetch_timeout_pulse_w) begin
                    doc_read_owner_valid_r <= 1'b0;
                end else begin
                    doc_read_owner_valid_r <= 1'b1;
                end
            end
        end
    end

    localparam int MEM_DIAG_SLICE_CYCLES =
        54_000_000 / 8;
    localparam int MEM_DIAG_COUNTER_WIDTH =
        $clog2(MEM_DIAG_SLICE_CYCLES);

    logic [MEM_DIAG_COUNTER_WIDTH-1:0]
        mem_diag_slice_counter_r;
    logic [7:0] mem_overlap_slice_count_r;
    logic [7:0] mem_late_slice_count_r;
    logic [7:0] debug_mem_overlap_count_r;
    logic [7:0] debug_mem_late_count_r;

    assign debug_mem_overlap_count_o =
        debug_mem_overlap_count_r;
    assign debug_mem_timeout_count_o =
        debug_fetch_timeout_count_w;
    assign debug_mem_late_count_o =
        debug_mem_late_count_r;

    always_ff @(posedge a2bus_if.clk_logic) begin
        if (!a2bus_if.system_reset_n) begin
            mem_diag_slice_counter_r <= '0;
            mem_overlap_slice_count_r <= 8'h00;
            mem_late_slice_count_r <= 8'h00;
            debug_mem_overlap_count_r <= 8'h00;
            debug_mem_late_count_r <= 8'h00;
        end else if (mem_diag_slice_counter_r ==
                     MEM_DIAG_SLICE_CYCLES - 1) begin
            mem_diag_slice_counter_r <= '0;

            if (doc_read_overlap_event_w &&
                (mem_overlap_slice_count_r != 8'hFF)) begin
                debug_mem_overlap_count_r <=
                    mem_overlap_slice_count_r + 1'b1;
            end else begin
                debug_mem_overlap_count_r <=
                    mem_overlap_slice_count_r;
            end

            if (doc_read_late_event_w &&
                (mem_late_slice_count_r != 8'hFF)) begin
                debug_mem_late_count_r <=
                    mem_late_slice_count_r + 1'b1;
            end else begin
                debug_mem_late_count_r <=
                    mem_late_slice_count_r;
            end

            mem_overlap_slice_count_r <= 8'h00;
            mem_late_slice_count_r <= 8'h00;
        end else begin
            mem_diag_slice_counter_r <=
                mem_diag_slice_counter_r + 1'b1;

            if (doc_read_overlap_event_w &&
                (mem_overlap_slice_count_r != 8'hFF)) begin
                mem_overlap_slice_count_r <=
                    mem_overlap_slice_count_r + 1'b1;
            end

            if (doc_read_late_event_w &&
                (mem_late_slice_count_r != 8'hFF)) begin
                mem_late_slice_count_r <=
                    mem_late_slice_count_r + 1'b1;
            end
        end
    end

    wire signed [15:0] mono_mix_w;
    wire signed [15:0] left_mix_w;
    wire signed [15:0] right_mix_w;
    //wire signed [15:0] channel_w[15:0]; 

    // Debug: Capture and expose the oscillator enable register
    wire [7:0] debug_doc_osc_en_w;
    assign debug_osc_en_o = debug_doc_osc_en_w;

    wire [1:0] debug_osc_mode_w[8];
    assign debug_osc_mode_o = debug_osc_mode_w;

wire [7:0] debug_osc_halt_w;
assign debug_osc_halt_o =
    debug_osc_halt_w;

// Complete live HALT state from the DOC core.
wire [31:0] debug_osc_halt_all_w;

assign debug_osc_halt_all_o =
    debug_osc_halt_all_w;

wire [7:0] debug_halt_event_w;
    assign debug_halt_event_o = debug_halt_event_w;

    wire [7:0] debug_halt_wtp_w;
    assign debug_halt_wtp_o = debug_halt_wtp_w;

    wire [7:0] debug_halt_rts_w;
    assign debug_halt_rts_o = debug_halt_rts_w;

    wire [7:0] debug_swap_ca_w;
    assign debug_swap_ca_o = debug_swap_ca_w;

wire [7:0] debug_host_ctrl_osc_w;
wire [7:0] debug_host_ctrl_data_w;
wire [7:0] debug_internal_ctrl_event_w;
wire [7:0] debug_internal_ctrl_data_w;

assign debug_host_ctrl_osc_o =
    debug_host_ctrl_osc_w;

assign debug_host_ctrl_data_o =
    debug_host_ctrl_data_w;

assign debug_internal_ctrl_event_o =
    debug_internal_ctrl_event_w;

assign debug_internal_ctrl_data_o =
    debug_internal_ctrl_data_w;

    
    // Both personalities own this single DOC5503 exclusively.
    // Preserve the original GS data path exactly for MODE=0:
    // a2bus_if.data is intentionally used in the golden design.
    // The bridge must present a synchronous one-shot write with
    // its own stable address and data; it will be wired in P2.
    wire doc_host_wr_w =
        MB_DOC_MODE ? mb_doc_wr_i : doc_wr_r;
    wire [7:0] doc_host_addr_w =
        MB_DOC_MODE ? mb_doc_addr_i : doc_addr_r;
    wire [7:0] doc_host_data_w =
        MB_DOC_MODE ? mb_doc_data_i : a2bus_if.data;

    doc5503 #(
    ) doc5503 (
        .clk_i(a2bus_if.clk_logic),
        .reset_n_i(a2bus_if.system_reset_n),
        .clk_en_i(a2bus_if.clk_7M_posedge),
        .cs_n_i(~doc_host_wr_w),
        .we_n_i(1'b0),
        .addr_i(doc_host_addr_w),
        .data_i(doc_host_data_w),
        .data_o(doc_data_o_w),
        .wave_address_o(wave_addr_w),
        .wave_bank_o(wave_bank_w),
        .wave_rd_o(doc_mem_rd_w),
        .wave_data_ready_i(wave_data_ready_r),
        .wave_data_i(wave_data_r),
        .left_mix_o(left_mix_w),
        .right_mix_o(right_mix_w),
        .mono_mix_o(mono_mix_w),
        .channel_o(),
        .ready_o(),
.debug_osc_en_o(
    debug_doc_osc_en_w
),

.debug_osc_mode_o(
    debug_osc_mode_w
),

.debug_osc_halt_o(
    debug_osc_halt_w
),

.debug_osc_halt_all_o(
    debug_osc_halt_all_w
),

.debug_halt_event_o(
    debug_halt_event_w
),
.debug_halt_wtp_o(debug_halt_wtp_w),
.debug_halt_rts_o(debug_halt_rts_w),
.debug_swap_ca_o(debug_swap_ca_w),

.debug_host_ctrl_osc_o(
    debug_host_ctrl_osc_w
),

.debug_host_ctrl_data_o(
    debug_host_ctrl_data_w
),

.debug_internal_ctrl_event_o(
    debug_internal_ctrl_event_w
),

.debug_internal_ctrl_data_o(
    debug_internal_ctrl_data_w
),

.debug_mix_clip_o(
    debug_mix_clip_o
),

.debug_mix_clip_history_left_o(
    debug_mix_clip_history_left_o
),

.debug_mix_clip_history_right_o(
    debug_mix_clip_history_right_o
),

.debug_mix_clip_history_mono_o(
    debug_mix_clip_history_mono_o
),

.debug_nonzero_osc_activity_o(
    debug_nonzero_osc_activity_o
),

.debug_mixer_osc_activity_o(
    debug_mixer_osc_activity_o
),

.debug_channel_activity_o(
    debug_channel_activity_o
),

.debug_left_nonzero_history_o(
    debug_left_nonzero_history_o
),

.debug_right_nonzero_history_o(
    debug_right_nonzero_history_o
),

.debug_wave_fetch_timeout_pulse_o(
    debug_fetch_timeout_pulse_w
),

.debug_wave_fetch_timeout_count_o(
    debug_fetch_timeout_count_w
)

    );

    // Volume is inverted for right shift (0 is min volume, 15 is max volume)
    // IIgs volume control ranges from 0-15, invert for right shift (0=lots of shift, 15=no shift)
    logic [3:0] volume_shift_w = volume_w < 12 ? 4'd4 - {2'b0, volume_w[3:2]} : 4'd0;
    
    // Output registers for audio with zero-centering preserved
    reg signed [15:0] audio_l_reg;
    reg signed [15:0] audio_r_reg;
    
    // Assign outputs from registers
    assign audio_l_o = audio_l_reg;
    assign audio_r_o = audio_r_reg;
    
// Calibration build:
// Pass the DOC mixer output through at unity gain.
always_ff @(posedge a2bus_if.clk_logic) begin
    if (MONO_MIX) begin
        audio_l_reg <= mono_mix_w;
        audio_r_reg <= mono_mix_w;
    end else begin
        audio_l_reg <= left_mix_w;
        audio_r_reg <= right_mix_w;
    end
end

    //assign audio_l_o = channel_w[0] >>> (4'd15 - volume_w);
    //assign audio_r_o = channel_w[0] >>> (4'd15 - volume_w);
    //assign audio_l_o = channel_w[1] >>> (4'd15 - volume_w);
    //assign audio_r_o = channel_w[2] >>> (4'd15 - volume_w);

endmodule
