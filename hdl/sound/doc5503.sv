// Ensoniq DOC5503 Sound Engine
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
// The DOC5503 is a 32 voice polyphonic sound engine used in the Apple IIgs and
// a number of Ensoniq synthesizers. It is a digital sound engine that uses
// wavetable synthesis to produce sound.
//
// The DOC5503 consists of 32 time-multiplexed digital oscillators that are
// mixed together to produce the final output. Each oscillator has a 24-bit
// accumulator that is used to address a 256 to 32768 byte wavetable in the
// system's RAM. The accumulator is incremented by a frequency value that is
// loaded from a 16-bit frequency register. The output of the wavetable is
// scaled by a 8-bit volume register and then mixed with the outputs of the
// other oscillators.
//
// In the IIgs, the DOC5503 is clocked using the Apple II 7.15909 MHz clock
// rather than its intended 8 MHz clock. The 7.15909 MHz clock is derived from
// the 14.31818 MHz clock that is used to drive the video system. The DOC5503
// divdes this clock by 8 for every oscillator cycle, so the effective
// oscillator maximum frequency is 894886.25 Hz. This module is assumed to be
// clocked at at least 50 MHz on clk_i with a single clk pulse on clk_en_i
// on 7.15909 MHz clock timing.  Although the main DOC5503 FSM operates on the
// clk_en_i pulse, register memory and the oscillator outputs are updated on
// the rising edge of clk_i. At 50 MHz, there are aproximately 5 clk_i pulses
// in between each clk_en_i pulse that can be used to update the control
// registers before the next FSM state change.
//
// The core logic of the DOC5503 is not particularly complex, but the large
// number of oscillators and the control registers for each oscillator make
// for a complex memory structure that is difficult to implement as a typical
// register file. This module is designed to provide the memory access logic
// for the DOC5503 and to infer the memory as block RAMs or distributed RAMs
// during synthesis.
//
// =============================================================================
// DOC5503 TIMING REFERENCE (from Ensoniq 5503 datasheet)
// =============================================================================
//
// CLOCK STRUCTURE
// ---------------
// The DOC5503 divides the input clock (CLK) by 8 to produce one oscillator
// cycle. Each complete scan consists of N oscillator slots (set by the
// Oscillator Enable register) plus 2 refresh slots.
//
//   At 8.000 MHz (nominal):  Tcyc1 = 125.0 ns, osc cycle = 1000.0 ns
//   At 7.159 MHz (IIgs):     Tcyc1 = 139.7 ns, osc cycle = 1117.6 ns
//
// INPUT CLOCK (Page 17)
//   Symbol  Parameter                     Min    Typ    Max    Units
//   Tcyc1   Input Clock Cycle Time        100     -     125    ns
//   Tpwh    Clock High                     50     -      -     ns
//   Tpwl    Clock Low                      50     -      -     ns
//
// OUTPUT CLOCKS (Page 17)
//   Symbol  Parameter                     Min    Typ    Max    Units
//   Tcyc2   RAS/CAS Cycle Time (2 MHz)   480     -     500    ns
//   Toh1    RAS/CAS Output High           270     -     290    ns
//   Tol1    RAS/CAS Output Low            190     -     210    ns
//   Trd     RAS High after E Low            -     -      40    ns
//   Tcd     CAS High after RAS High        40     -      70    ns
//   Tcyc3   E/Q Cycle Time (1 MHz)        980     -    1000    ns
//   Toh2    E/Q Output High               480     -     500    ns
//   Tol2    E/Q Output Low                480     -     500    ns
//   Tqd     E High from Q High            240     -     250    ns
//
// NOTE: The min values in the above table are not fully self-consistent:
//   Toh1_min + Tol1_min = 460 != 480 = Tcyc2_min
//   Toh2_min + Tol2_min = 960 != 980 = Tcyc3_min
//   2 * Tcyc2_min = 960 != 980 = Tcyc3_min
// The max values are consistent (290+210=500, 500+500=1000, 2*500=1000).
//
// CLK-EDGE-REFERENCED TIMING (Page 21, handwritten, at 8 MHz)
// All times referenced to rising edge of indicated 8 MHz CLK cycle.
//   Symbol   Parameter                   Min    Typ    Max    Units
//   tEH      Time to E high               40     50     60    ns
//   tEL      Time to E low                50     63     80    ns
//   tRASH    Time to RAS high             50     60     80    ns
//   tRASL    Time to RAS low              60     82     97    ns
//   tCASH    Time to CAS high             60     65     80    ns
//   tCASL    Time to CAS low              50     60     70    ns
//   tQL      Time to Q low                50     55     70    ns
//   tQH      Time to Q high               50     60     70    ns
//
// 5503 READ FROM MEMORY (Page 18)
//   Symbol  Parameter                     Min    Typ    Max    Units
//   Tas     Time to Valid Addr from E       -     -      50    ns
//   Tah     Addr Hold Time (A0-A7)          0     -      10    ns
//   Thh     A8-A15 Hold from RAS Fall       -     -      30    ns
//   Tof     A8/D0-A15/D7 Switching Time    30     -       -    ns
//   Tds     Data In Setup Time            100     -       -    ns
//   Tdh     Data In Hold Time              20     -       -    ns
//
// MICROPROCESSOR READ/WRITE TO 5503 (Page 18)
//   Symbol  Parameter                     Min    Typ    Max    Units
//   Tas     Address Setup Time            350     -       -    ns
//   Tah     Address Hold Time               0     -     100    ns
//   Trw     R/W Valid for Read            350     -       -    ns
//   Th      CS Hold from E Low              0     -       -    ns
//   Tds     Data In Setup Time            150     -       -    ns
//   Tdh     Data In/Out Hold Time          30     -       -    ns
//   Tww     R/W Valid for Write           350     -       -    ns
//
// CHANNEL STROBE / CHANNEL ASSIGN TIMING (Page 22, handwritten, at 8 MHz)
//   Symbol   Parameter                              Typ    Units
//   tEcyc    E clock cycle time                    1000    ns
//   tEh      E clock high time                      500    ns
//   tEL      E clock low time                       500    ns
//   tCSTBL   Channel strobe low time                500    ns
//   tCAV     CA0-CA3 valid time                    1000    ns
//   tCAS     CA0-CA3 setup to CSTRB low             250    ns
//   tCAh     CA0-CA3 hold from CSTRB high           250    ns
//
// MEASURED IIgs TIMING (Page 23, 7.159 MHz, as measured on hardware)
//   Signal        Measured Value     Notes
//   E high        ~480 ns
//   E cycle       ~540 ns (pin 5)   Annotation unclear; may be half-cycle
//   CAS low       ~290 ns           ~2 CLK at 7.159 MHz (279.4 ns)
//   RAS low       ~270 ns           ~2 CLK at 7.159 MHz
//   Read data     ~50 ns valid      70 ns for 16Kx4 DRAM
//   M ADDR (row)  ~160 ns valid
//   M ADDR (col)  ~270 ns valid
//
// =============================================================================
// PER-OSCILLATOR CYCLE SEQUENCE (derived from timing diagrams pp. 19-23)
// =============================================================================
//
// The following shows what happens within one oscillator cycle (8 CLK periods).
// E-high is the memory access phase; E-low is the output/host-access phase.
//
//   CLK Edge  Event
//   --------  -----
//   0         E rises (after tEH delay from CLK edge)
//   0+Tas     Address A0-A7 valid (waveform table address, low byte)
//             Address A8-A15 valid (waveform table address, high byte)
//   ~1        RAS falls — row address (A8-A15) latched by DRAM
//   ~1+Thh    A8-A15 released, lines switch to data mode (Tof >= 30 ns)
//   ~2        CAS falls — column address (A0-A7) latched, DRAM read begins
//   ~3        Data valid on D0-D7 (Tds >= 100 ns before latch point)
//             Waveform sample stored in WDS register
//   4         E falls (after tEL delay from CLK edge)
//             Volume DAC (VOL-) drives current from volume register
//             Waveform DAC (SIG+/SIG-) outputs sample * volume
//   ~4        RAS rises (within Trd <= 40 ns of E fall)
//   ~4+Tcd    CAS rises (40-70 ns after RAS rise)
//   4-5       CSTRB falls — channel strobe active, analog output sampled
//             CA0-CA3 valid — routes output to assigned channel
//   ~7        Accumulator updated: A = A + FC (frequency control)
//   7         Cycle ends, next oscillator begins
//
// KEY IMPLICATION: The DOC reads waveform data and outputs it in the SAME
// oscillator cycle. The address is generated from the current accumulator,
// data is fetched from DRAM during E-high, volume-scaled during E-high/low
// transition, and output via CSTRB during E-low. The accumulator is then
// updated for the next cycle.
//
// This means the sequence is: read mem[ACC] -> output -> ACC += FC
// NOT a pipelined: output old WDS -> fetch new WDS -> ACC += FC
//
// =============================================================================
// FPGA IMPLEMENTATION TIMING BUDGET
// =============================================================================
//
// This module runs the FSM on clk_i (>= 50 MHz) with clk_en_i pulsing at
// the DOC clock rate (7.159 MHz on IIgs). The 8-count clk_en_i divider
// (clk_count_r) provides 8 sub-cycles per oscillator slot.
//
// At 54 MHz clk_i / 7.159 MHz clk_en_i: ~7.5 clk_i edges per clk_en_i pulse
// Total clk_i edges per oscillator cycle: ~60
// FSM states per oscillator: up to 14 (fits comfortably)
//
// Critical path: wave_rd_o asserted in OSC_REQUEST_DATA, wave_data_ready_i
// must arrive before clk_count_r == 7 (timeout). This gives ~7/8 of the
// oscillator cycle (~978 ns at 7.159 MHz) for memory round-trip.
// Timeout produces 0x80 (mid-level silence) as a safe fallback.
//
// Real DOC DRAM access completes in ~300-400 ns (within E-high phase).
// DDR3/SDRAM through CDC bridges should be well under the 838 ns budget.
//
// =============================================================================

module doc5503 #(
    parameter int CLOCK_SPEED_HZ = 54_000_000,
    parameter int DOC_CLOCK_SPEED_HZ = 7_159_090, // 7.15909 MHz

 // Diagnostic invariant:
    // An oscillator whose DOC volume register is zero
    // must contribute exactly zero to every mixer.
    parameter bit FORCE_ZERO_VOLUME_MUTE = 1'b1

) (
    input clk_i,
    input reset_n_i,
    input clk_en_i,

    input cs_n_i,
    input we_n_i,

    input [7:0] addr_i,
    input [7:0] data_i,
    output reg [7:0] data_o,

    output reg [15:0] wave_address_o,
    output reg wave_bank_o,
    output reg wave_rd_o,
    input wave_data_ready_i,
    input [7:0] wave_data_i,

    output signed [15:0] mono_mix_o,
    output signed [15:0] left_mix_o,
    output signed [15:0] right_mix_o,

    output signed [15:0] channel_o[16],
    
    output logic ready_o,          // Indicate when out of reset and ready to process

    output [7:0] debug_osc_en_o,
    output [1:0] debug_osc_mode_o[8],

    // Original sampled HALT display for oscillators 0-7.
    // Retained temporarily while the 32-bit path is added.
    output [7:0] debug_osc_halt_o,

    // Complete live HALT state for all 32 oscillators.
    //
    // Each displayed byte is reversed so the lowest
    // oscillator number appears at the left:
    //
    //   bits 31:24 = oscillators  0-7
    //   bits 23:16 = oscillators  8-15
    //   bits 15:8  = oscillators 16-23
    //   bits 7:0   = oscillators 24-31
    //
    // Display meaning:
    //   1 = halted
    //   0 = running
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

// One-second clipping histories. Each bit represents one 125 ms slice;
// bit 0 is the newest slice and bit 7 is the oldest.
output [7:0] debug_mix_clip_history_left_o,
output [7:0] debug_mix_clip_history_right_o,
output [7:0] debug_mix_clip_history_mono_o,

// Oscillator-to-mixer activity from the last completed 125 ms interval.
// The two 32-bit masks use the same display ordering as the HALT mask:
// oscillator 0 is the leftmost displayed bit and oscillator 31 is rightmost.
output [31:0] debug_nonzero_osc_activity_o,
output [31:0] debug_mixer_osc_activity_o,

// DOC channel addresses observed at OSC_MIX during the last completed
// 125 ms interval. Bit N corresponds directly to DOC channel address N.
output [15:0] debug_channel_activity_o,

// One-second completed-mix activity histories. Each bit represents one
// 125 ms slice; bit 0 is newest and bit 7 is oldest.
output [7:0] debug_left_nonzero_history_o,
output [7:0] debug_right_nonzero_history_o,

// Live waveform-fetch diagnostics. The pulse marks the exact oscillator
// slot that falls through to $80 silence. The byte is the saturating number
// of such events in the last completed 125 ms interval.
output debug_wave_fetch_timeout_pulse_o,
output [7:0] debug_wave_fetch_timeout_count_o

);

    reg [7:0] host_addr_r;         // Address register for host access
    reg [7:0] host_data_r;        // Data register for host access
    reg host_we_n_r;              // Write enable register for host access
    reg prev_cs_n_r;          // Previous chip select state
    reg prev_we_n_r;          // Previous write enable state
    reg host_access_r;         // Host access register

    always_ff @(posedge clk_i) begin
        if (!reset_n_i) begin
            host_addr_r <= '0;
            host_data_r <= '0;
            host_we_n_r <= 1'b1;
        end else begin
            prev_cs_n_r <= cs_n_i;
            prev_we_n_r <= we_n_i;
            host_access_r <= 1'b0;
            if (!cs_n_i) begin
                host_addr_r <= addr_i;
                host_data_r <= data_i;
                host_we_n_r <= we_n_i;

                // Pulse host_access_r on negative edge of cs_n_i
                // if cs_n_i is low and negative edge of we_n_i
                if (prev_cs_n_r || (!we_n_i && prev_we_n_r)) begin
                    host_access_r <= 1'b1;
                end
            end
        end
    end

    // Registers

reg [7:0] osc_int_r;            // $E0 : Oscillator Interrupt Register
reg [7:0] osc_en_r;             // $E1 : Oscillator Enable Register

// Shadow of each oscillator's control-register HALT bit.
//
// 1 = halted
// 0 = running
//
// This lets a host control write distinguish a genuine
// HALTED-to-RUNNING transition from a repeated write that
// leaves an already-running oscillator running.
reg [31:0] osc_halt_shadow_r;

assign debug_osc_en_o = osc_en_r;

reg [1:0] debug_osc_mode_r[8];
assign debug_osc_mode_o = debug_osc_mode_r;

// Live HALT state for oscillators 0-7.
//
// Retain the existing eight-bit output temporarily
// while the new 32-bit path is connected through
// sound_glu.sv and top.sv.
//
// The overlay displays bit 7 first:
//
//   bit 7 = oscillator 0
//   bit 6 = oscillator 1
//   ...
//   bit 0 = oscillator 7
//
// Display meaning:
//
//   1 = halted
//   0 = running
assign debug_osc_halt_o = {
    osc_halt_shadow_r[0],
    osc_halt_shadow_r[1],
    osc_halt_shadow_r[2],
    osc_halt_shadow_r[3],
    osc_halt_shadow_r[4],
    osc_halt_shadow_r[5],
    osc_halt_shadow_r[6],
    osc_halt_shadow_r[7]
};

// Live HALT state for all 32 oscillators.
//
// Each group of eight is reversed so the lowest
// oscillator number appears on the left side of
// its displayed byte.
//
//   bits 31:24 = OSC 00 01 02 03 04 05 06 07
//   bits 23:16 = OSC 08 09 10 11 12 13 14 15
//   bits 15:8  = OSC 16 17 18 19 20 21 22 23
//   bits 7:0   = OSC 24 25 26 27 28 29 30 31
//
// Display meaning:
//
//   1 = halted
//   0 = running
assign debug_osc_halt_all_o = {
    osc_halt_shadow_r[0],
    osc_halt_shadow_r[1],
    osc_halt_shadow_r[2],
    osc_halt_shadow_r[3],
    osc_halt_shadow_r[4],
    osc_halt_shadow_r[5],
    osc_halt_shadow_r[6],
    osc_halt_shadow_r[7],

    osc_halt_shadow_r[8],
    osc_halt_shadow_r[9],
    osc_halt_shadow_r[10],
    osc_halt_shadow_r[11],
    osc_halt_shadow_r[12],
    osc_halt_shadow_r[13],
    osc_halt_shadow_r[14],
    osc_halt_shadow_r[15],

    osc_halt_shadow_r[16],
    osc_halt_shadow_r[17],
    osc_halt_shadow_r[18],
    osc_halt_shadow_r[19],
    osc_halt_shadow_r[20],
    osc_halt_shadow_r[21],
    osc_halt_shadow_r[22],
    osc_halt_shadow_r[23],

    osc_halt_shadow_r[24],
    osc_halt_shadow_r[25],
    osc_halt_shadow_r[26],
    osc_halt_shadow_r[27],
    osc_halt_shadow_r[28],
    osc_halt_shadow_r[29],
    osc_halt_shadow_r[30],
    osc_halt_shadow_r[31]
};


// Original halt-event diagnostic registers.
//
// These remain declared because the existing reset and
// event-capture code still updates them. They are not
// displayed during the full accumulator-trace build.
reg [7:0] debug_halt_event_r;
reg [7:0] debug_halt_wtp_r;
reg [7:0] debug_halt_rts_r;
reg [7:0] debug_swap_ca_r;


// Original host/internal control-write diagnostics.
//
// These also remain active internally, although their
// output positions are temporarily used by the full
// accumulator trace.
reg [7:0] debug_host_ctrl_osc_r;
reg [7:0] debug_host_ctrl_data_r;
reg [7:0] debug_internal_ctrl_event_r;
reg [7:0] debug_internal_ctrl_data_r;


// Temporarily route the live oscillator-3 accumulator
// diagnostic through the existing eight overlay ports.
//
// CTRL RTS WTP ACC-HI ACC-MID ACC-LO OVF-CNT WRAP-CNT
assign debug_halt_event_o =
    debug_live_ctrl_r;

assign debug_halt_wtp_o =
    debug_live_rts_r;

assign debug_halt_rts_o =
    debug_live_wtp_r;

assign debug_swap_ca_o =
    debug_live_acc_r[23:16];

assign debug_host_ctrl_osc_o =
    debug_live_acc_r[15:8];

assign debug_host_ctrl_data_o =
    debug_live_acc_r[7:0];

assign debug_internal_ctrl_event_o =
    debug_live_overflow_count_r;

assign debug_internal_ctrl_data_o =
    debug_live_wrap_count_r;

// Full accumulator lifecycle diagnostic.
//
// The existing eight-byte second overlay row is temporarily
// repurposed as:
//
//   byte 1: start oscillator
//   byte 2: start accumulator bits 23:16
//   byte 3: start accumulator bits 15:8
//   byte 4: start accumulator bits 7:0
//
//   byte 5: overflow oscillator
//   byte 6: overflow temp accumulator bits 23:16
//   byte 7: overflow temp accumulator bits 15:8
//   byte 8: overflow temp accumulator bits 7:0
reg [7:0] debug_acc_start_osc_r;
reg [23:0] debug_acc_start_r;

reg [7:0] debug_acc_end_osc_r;
reg [23:0] debug_acc_end_r;

// One pending-start bit for every oscillator.
//
// Set whenever an oscillator genuinely enters RUN state.
// Cleared when that oscillator reaches OSC_REQUEST_DATA and
// its actual starting accumulator is captured.
reg [31:0] debug_acc_start_pending_r;

// Host control-register lifecycle diagnostic.
//
// Overlay bytes:
//
//   1: last control-register write oscillator
//   2: last control-register write data
//   3: control-write count high byte
//   4: control-write count low byte
//
//   5: last control-register read oscillator
//   6: value returned to the host
//   7: control-read count
//   8: internal halt count
reg [7:0]  debug_ctrl_write_osc_r;
reg [7:0]  debug_ctrl_write_data_r;
reg [15:0] debug_ctrl_write_count_r;

reg [7:0] debug_ctrl_read_osc_r;
reg [7:0] debug_ctrl_read_data_r;
reg [7:0] debug_ctrl_read_count_r;

reg [7:0] debug_ctrl_halt_count_r;

// Live oscillator-3 accumulator diagnostic.
//
// Overlay bytes:
//
//   1: current control register
//   2: current resolution/table-size register
//   3: current waveform table pointer
//   4: next accumulator bits 23:16
//   5: next accumulator bits 15:8
//   6: next accumulator bits 7:0
//   7: accumulator-overflow count
//   8: masked accumulator wrap count
reg [7:0] debug_live_ctrl_r;
reg [7:0] debug_live_rts_r;
reg [7:0] debug_live_wtp_r;
reg [23:0] debug_live_acc_r;

reg [7:0] debug_live_overflow_count_r;
reg [7:0] debug_live_wrap_count_r;

reg [23:0] debug_live_prev_acc_r;
reg debug_live_prev_valid_r;


// Waveform-fetch diagnostic captured when an oscillator
// halts by zero byte or accumulator overflow.
//
// Overlay row:
//   OSC WTP RTS ADDR-HI ADDR-LO DATA FLAGS TIMEOUTS
reg [7:0] debug_fetch_osc_r;
reg [7:0] debug_fetch_wtp_r;
reg [7:0] debug_fetch_rts_r;
reg [15:0] debug_fetch_addr_r;
reg [7:0] debug_fetch_data_r;
reg [7:0] debug_fetch_flags_r;
reg [7:0] debug_fetch_timeouts_r;

// Per-oscillator timeout tracking for oscillators 0-7.
reg [7:0] fetch_timeout_count_r [0:7];
reg [7:0] fetch_timeout_seen_r;
integer fetch_reset_i;

// SYNC-AM diagnostic capture registers
reg       debug_am_write_toggle_r;
reg [4:0] debug_am_source_osc_r;
reg [4:0] debug_am_target_osc_r;
reg [7:0] debug_am_data_r;
reg [7:0] debug_am_target_vol_before_r;

// CPU volume-write diagnostic capture registers
reg       debug_vol_write_toggle_r;
reg [4:0] debug_vol_write_osc_r;
reg [7:0] debug_vol_write_data_r;




    // Oscillator registers as RAM
    // Necessary to use RAMs to implement the large number of registers but adds
    // complexity to the design.  Current implementation uses synchronous writes
    // and asynchronous reads which means that read data is available on the next
    // clock cycle.

    // Oscillator RAM control signals

    reg [4:0] ram_fl_osc_r;         // RAM oscillator for frequency low operation
    reg [4:0] ram_fh_osc_r;         // RAM oscillator for frequency high operation
    reg [4:0] ram_vol_osc_r;        // RAM oscillator for volume operation
    reg [4:0] ram_wds_osc_r;        // RAM oscillator for waveform data sample operation
    reg [4:0] ram_wtp_osc_r;        // RAM oscillator for waveform table pointer operation
    reg [4:0] ram_control_osc_r;    // RAM oscillator for control operation
    reg [4:0] ram_rts_osc_r;        // RAM oscillator for resolution table size operation
    reg [4:0] ram_acc_osc_r;        // RAM oscillator for accumulator operation

    reg ram_fl_we_r;                // RAM oscillator write enable for frequency low register
    reg ram_fh_we_r;                // RAM oscillator write enable for frequency high register
    reg ram_vol_we_r;               // RAM oscillator write enable for volume register
    reg ram_wds_we_r;               // RAM oscillator write enable for waveform data sample register
    reg ram_wtp_we_r;               // RAM oscillator write enable for waveform table pointer register
    reg ram_control_we_r;           // RAM oscillator write enable for control register
    reg ram_rts_we_r;               // RAM oscillator write enable for resolution table size register
    reg ram_acc_we_r;               // RAM oscillator write enable for accumulator register

    reg [7:0] ram_fl_din_r;         // RAM oscillator data in for frequency low register
    reg [7:0] ram_fh_din_r;         // RAM oscillator data in for frequency high register
    reg [7:0] ram_vol_din_r;        // RAM oscillator data in for volume register
    reg [7:0] ram_wds_din_r;        // RAM oscillator data in for waveform data sample register
    reg [7:0] ram_wtp_din_r;        // RAM oscillator data in for waveform table pointer register
    reg [7:0] ram_control_din_r;    // RAM oscillator data in for control register
    reg [7:0] ram_rts_din_r;        // RAM oscillator data in for resolution table size register
    reg [23:0] ram_acc_din_r;       // RAM oscillator data in for accumulator register

    wire [7:0] ram_fl_dout_w;       // RAM oscillator data out for frequency low register
    wire [7:0] ram_fh_dout_w;       // RAM oscillator data out for frequency high register
    wire [7:0] ram_vol_dout_w;      // RAM oscillator data out for volume register
    wire [7:0] ram_wds_dout_w;      // RAM oscillator data out for waveform data sample register
    wire [7:0] ram_wtp_dout_w;      // RAM oscillator data out for waveform table pointer register
    wire [7:0] ram_control_dout_w;  // RAM oscillator data out for control register
    wire [7:0] ram_rts_dout_w;      // RAM oscillator data out for resolution table size register
    wire [23:0] ram_acc_dout_w;     // RAM oscillator data out for accumulator register

    // Instantiate the RAMs for each oscillator register

    // $00-1F : Frequency Low Register
    osc_reg_ram fl_ram (
        .clk_i(clk_i),
        .osc_i(ram_fl_osc_r),
        .we_i(ram_fl_we_r),
        .data_i(ram_fl_din_r),
        .data_o(ram_fl_dout_w)
    );

    // $20-3F : Frequency High Register
    osc_reg_ram fh_ram (
        .clk_i(clk_i),
        .osc_i(ram_fh_osc_r),
        .we_i(ram_fh_we_r),
        .data_i(ram_fh_din_r),
        .data_o(ram_fh_dout_w)
    );

    // $40-5F : Volume Register
    osc_reg_ram vol_ram (
        .clk_i(clk_i),
        .osc_i(ram_vol_osc_r),
        .we_i(ram_vol_we_r),
        .data_i(ram_vol_din_r),
        .data_o(ram_vol_dout_w)
    );

    // $60-7F : Waveform Data Sample Register
    osc_reg_ram wds_ram (
        .clk_i(clk_i),
        .osc_i(ram_wds_osc_r),
        .we_i(ram_wds_we_r),
        .data_i(ram_wds_din_r),
        .data_o(ram_wds_dout_w)
    );

    // $80-9F : Waveform Table Pointer Register
    osc_reg_ram wtp_ram (
        .clk_i(clk_i),
        .osc_i(ram_wtp_osc_r),
        .we_i(ram_wtp_we_r),
        .data_i(ram_wtp_din_r),
        .data_o(ram_wtp_dout_w)
    );

    // $A0-BF : Control Register
    osc_reg_ram control_ram (
        .clk_i(clk_i),
        .osc_i(ram_control_osc_r),
        .we_i(ram_control_we_r),
        .data_i(ram_control_din_r),
        .data_o(ram_control_dout_w)
    );

    // $C0-DF : Resolution Table Size Register
    osc_reg_ram rts_ram (
        .clk_i(clk_i),
        .osc_i(ram_rts_osc_r),
        .we_i(ram_rts_we_r),
        .data_i(ram_rts_din_r),
        .data_o(ram_rts_dout_w)
    );

    // $E0-FF : Oscillator Accumulator Register
    osc_reg_ram #(.DATA_WIDTH(24)) acc_ram (
        .clk_i(clk_i),
        .osc_i(ram_acc_osc_r),
        .we_i(ram_acc_we_r),
        .data_i(ram_acc_din_r),
        .data_o(ram_acc_dout_w)
    );

    // Current oscillator state, copied from the register file at the start of each cycle
    reg [7:0] curr_fl_r;
    reg [7:0] curr_fh_r;
    reg [7:0] curr_vol_r;
    reg [7:0] curr_wds_r;
    reg [7:0] curr_wtp_r;
    reg [7:0] curr_control_r;
    reg [7:0] curr_rts_r;
    reg [7:0] partner_control_r;
    reg [7:0] next_control_r;
    reg [7:0] prev_control_r;

    wire zero_byte_w = (curr_wds_r == 8'h00);
    
    reg [4:0] curr_osc_r;
    wire curr_osc_odd_w = curr_osc_r[0];
    wire curr_osc_even_w = ~curr_osc_odd_w;
    wire [4:0] partner_osc_w = curr_osc_r ^ 5'b1;

    wire [2:0] curr_wts_w =
    curr_rts_r[5:3];

wire [2:0] curr_res_w =
    curr_rts_r[2:0];

wire [4:0] curr_shift_w =
    5'd9 + curr_res_w - curr_wts_w;

// Active accumulator width is:
//
//   17 bits when RES=0
//   18 bits when RES=1
//   ...
//   24 bits when RES=7
//
// Use a 25-bit intermediate so RES=7 can represent
// the $01000000 boundary without truncation.
wire [24:0] curr_acc_limit_w =
    25'd1 << (5'd17 + curr_res_w);

wire [24:0] curr_acc_mask_ext_w =
    curr_acc_limit_w - 25'd1;

wire [23:0] curr_acc_mask_w =
    curr_acc_mask_ext_w[23:0];

    wire halt_w = curr_control_r[0];
    wire [1:0] curr_mode_w = curr_control_r[2:1];
    wire [3:0] curr_ca_w = curr_control_r[7:4];

    wire partner_halt_w = partner_control_r[0];
    wire [1:0] partner_mode_w = partner_control_r[2:1];

    wire next_halt_w = next_control_r[0];
    wire [1:0] next_mode_w = next_control_r[2:1];

    wire prev_halt_w = prev_control_r[0];
    wire [1:0] prev_mode_w = prev_control_r[2:1];

//    reg [23:0] curr_acc_r;
//    reg signed [17:0] curr_output_r;



reg [23:0] curr_acc_r;
reg signed [17:0] curr_output_r;


// Diagnostic values from the most recently mixed
// oscillator. These can be viewed in simulation,
// SignalTap-equivalent capture, or temporarily routed
// to existing debug outputs.
// Diagnostic values from the most recently mixed
// oscillator.
reg [4:0] debug_mix_osc_r;
reg [7:0] debug_mix_vol_r;
reg [7:0] debug_mix_wds_r;
reg [3:0] debug_mix_ca_r;
reg signed [17:0] debug_mix_output_r;

//reg       debug_am_write_toggle_r;
//reg [4:0] debug_am_source_osc_r;
//reg [4:0] debug_am_target_osc_r;
//reg [7:0] debug_am_data_r;
//reg [7:0] debug_am_target_vol_before_r;







    // Incoming wave date requested by the FSM

    reg [7:0] loaded_wds_r;

    always_ff @(posedge clk_i) begin
        if (!reset_n_i) begin
            loaded_wds_r <= 8'h80;
        end else begin
            if (wave_data_ready_i) begin
                loaded_wds_r <= wave_data_i;
            end
        end
    end

    // Use 24-bit accumulators for mixing to provide more headroom and prevent clipping
    localparam int MIXER_SUM_RESOLUTION = 24;

 // Scale the completed 24-bit DOC mix before converting
// it to signed 16-bit PCM.
//
// 0 = unity, but dense mixes saturate heavily.
// 3 = divide by 8 before saturation.
// Divide the completed 24-bit DOC mix by 4 before
// saturation and conversion to signed 16-bit PCM.
localparam int TOP_BIT_OFFSET = 2;




    //localparam int WINDOW_SIZE = 15;     // Use this many bits for magnitude

// Saturating conversion from internal 24-bit mix to signed 16-bit output.
// This avoids wraparound/scratchiness when loud MOD/sample playback overdrives.
function automatic signed [15:0] sat16_from_mix;
    input signed [MIXER_SUM_RESOLUTION-1:0] v;
    reg signed [MIXER_SUM_RESOLUTION-1:0] s;
begin
    s = v >>> TOP_BIT_OFFSET;

    if (s > 24'sd32767)
        sat16_from_mix = 16'sh7FFF;
    else if (s < -24'sd32768)
        sat16_from_mix = 16'sh8000;
    else
        sat16_from_mix = s[15:0];
end
endfunction


// Returns true when the scaled 24-bit mix cannot fit into
// a signed 16-bit output without saturation.
function automatic mix_would_saturate;
    input signed [MIXER_SUM_RESOLUTION-1:0] v;
    reg signed [MIXER_SUM_RESOLUTION-1:0] s;
begin
    s = v >>> TOP_BIT_OFFSET;

    mix_would_saturate =
        (s > 24'sd32767) ||
        (s < -24'sd32768);
end
endfunction


// DOC completed-mix clipping diagnostics.
//
// Bits 3:0 are the latest completed mix.
// Bits 7:4 are sticky until reset.
reg [7:0] debug_mix_clip_r;

assign debug_mix_clip_o = debug_mix_clip_r;

reg [7:0] debug_mix_clip_history_left_r;
reg [7:0] debug_mix_clip_history_right_r;
reg [7:0] debug_mix_clip_history_mono_r;

assign debug_mix_clip_history_left_o =
    debug_mix_clip_history_left_r;
assign debug_mix_clip_history_right_o =
    debug_mix_clip_history_right_r;
assign debug_mix_clip_history_mono_o =
    debug_mix_clip_history_mono_r;

// Activity accumulators are written with natural oscillator numbering
// (bit N = oscillator N). The two public oscillator masks are reversed here
// to match the existing HALT overlay convention, where oscillator 0 is the
// leftmost displayed bit.
logic [31:0] nonzero_osc_slice_mask_r;
logic [31:0] mixer_osc_slice_mask_r;
logic [31:0] debug_nonzero_osc_activity_r;
logic [31:0] debug_mixer_osc_activity_r;

logic [15:0] channel_slice_mask_r;
logic [15:0] debug_channel_activity_r;

logic left_nonzero_pending_r;
logic right_nonzero_pending_r;
logic [7:0] debug_left_nonzero_history_r;
logic [7:0] debug_right_nonzero_history_r;

assign debug_nonzero_osc_activity_o = {
    debug_nonzero_osc_activity_r[0],
    debug_nonzero_osc_activity_r[1],
    debug_nonzero_osc_activity_r[2],
    debug_nonzero_osc_activity_r[3],
    debug_nonzero_osc_activity_r[4],
    debug_nonzero_osc_activity_r[5],
    debug_nonzero_osc_activity_r[6],
    debug_nonzero_osc_activity_r[7],
    debug_nonzero_osc_activity_r[8],
    debug_nonzero_osc_activity_r[9],
    debug_nonzero_osc_activity_r[10],
    debug_nonzero_osc_activity_r[11],
    debug_nonzero_osc_activity_r[12],
    debug_nonzero_osc_activity_r[13],
    debug_nonzero_osc_activity_r[14],
    debug_nonzero_osc_activity_r[15],
    debug_nonzero_osc_activity_r[16],
    debug_nonzero_osc_activity_r[17],
    debug_nonzero_osc_activity_r[18],
    debug_nonzero_osc_activity_r[19],
    debug_nonzero_osc_activity_r[20],
    debug_nonzero_osc_activity_r[21],
    debug_nonzero_osc_activity_r[22],
    debug_nonzero_osc_activity_r[23],
    debug_nonzero_osc_activity_r[24],
    debug_nonzero_osc_activity_r[25],
    debug_nonzero_osc_activity_r[26],
    debug_nonzero_osc_activity_r[27],
    debug_nonzero_osc_activity_r[28],
    debug_nonzero_osc_activity_r[29],
    debug_nonzero_osc_activity_r[30],
    debug_nonzero_osc_activity_r[31]
};

assign debug_mixer_osc_activity_o = {
    debug_mixer_osc_activity_r[0],
    debug_mixer_osc_activity_r[1],
    debug_mixer_osc_activity_r[2],
    debug_mixer_osc_activity_r[3],
    debug_mixer_osc_activity_r[4],
    debug_mixer_osc_activity_r[5],
    debug_mixer_osc_activity_r[6],
    debug_mixer_osc_activity_r[7],
    debug_mixer_osc_activity_r[8],
    debug_mixer_osc_activity_r[9],
    debug_mixer_osc_activity_r[10],
    debug_mixer_osc_activity_r[11],
    debug_mixer_osc_activity_r[12],
    debug_mixer_osc_activity_r[13],
    debug_mixer_osc_activity_r[14],
    debug_mixer_osc_activity_r[15],
    debug_mixer_osc_activity_r[16],
    debug_mixer_osc_activity_r[17],
    debug_mixer_osc_activity_r[18],
    debug_mixer_osc_activity_r[19],
    debug_mixer_osc_activity_r[20],
    debug_mixer_osc_activity_r[21],
    debug_mixer_osc_activity_r[22],
    debug_mixer_osc_activity_r[23],
    debug_mixer_osc_activity_r[24],
    debug_mixer_osc_activity_r[25],
    debug_mixer_osc_activity_r[26],
    debug_mixer_osc_activity_r[27],
    debug_mixer_osc_activity_r[28],
    debug_mixer_osc_activity_r[29],
    debug_mixer_osc_activity_r[30],
    debug_mixer_osc_activity_r[31]
};

assign debug_channel_activity_o = debug_channel_activity_r;
assign debug_left_nonzero_history_o =
    debug_left_nonzero_history_r;
assign debug_right_nonzero_history_o =
    debug_right_nonzero_history_r;


    reg signed [15:0] channel_r[16]; 
    assign channel_o = channel_r;
    reg signed [MIXER_SUM_RESOLUTION-1:0] next_channel_r[16]; 
    reg signed [MIXER_SUM_RESOLUTION-1:0] channel_sum_r;

    reg signed [15:0] mono_mix_r;
    assign mono_mix_o = mono_mix_r;
    reg signed [MIXER_SUM_RESOLUTION-1:0] next_mono_mix_r;

    reg signed [15:0] left_mix_r;
    assign left_mix_o = left_mix_r;
    reg signed [MIXER_SUM_RESOLUTION-1:0] next_left_mix_r;

    reg signed [15:0] right_mix_r;
    assign right_mix_o = right_mix_r;
    reg signed [MIXER_SUM_RESOLUTION-1:0] next_right_mix_r;

    localparam [1:0] MODE_FREE = 2'b00;
	localparam [1:0] MODE_ONE_SHOT = 2'b01;
    localparam [1:0] MODE_SYNC_AM = 2'b10;
    localparam [1:0] MODE_SWAP = 2'b11;

    // Use bits 5:1 to determine the number of oscillators enabled (divide by 2)
    wire [4:0] osc_max_w = osc_en_r[5:1];

    // Timing generator

    localparam int TICKS_PER_CYCLE = CLOCK_SPEED_HZ / (DOC_CLOCK_SPEED_HZ / 8);
    localparam int CYCLE_WIDTH = (TICKS_PER_CYCLE <= 1) ? 1 : $clog2(TICKS_PER_CYCLE + 1);
    logic [CYCLE_WIDTH-1:0] cycle_timer_r;

    localparam [1:0] CYCLE_RESET = 2'b00;
    localparam [1:0] CYCLE_OSC = 2'b01;
    localparam [1:0] CYCLE_REFRESH_0 = 2'b10;
    localparam [1:0] CYCLE_REFRESH_1 = 2'b11;

localparam int OSC_STATE_COUNT = 14;

typedef enum logic [$clog2(OSC_STATE_COUNT)-1:0] {
    OSC_IDLE,
    OSC_START,
    OSC_LOAD_REGISTERS,
    OSC_LOAD_PARTNER_CONTROL,
    OSC_LOAD_NEXT_CONTROL,
    OSC_REQUEST_DATA,
    OSC_HANDLE_DATA,
    OSC_OUT,
    OSC_MIX,
    OSC_ACC,
    OSC_HALT,
    OSC_HALT_ONE_SHOT_OR_ZERO_BYTE,
    OSC_START_PARTNER,
    OSC_RETRIGGER
} osc_state_e;

osc_state_e osc_state_r;

reg [1:0] cycle_state_r;
reg cycle_start_r;
reg [2:0] clk_count_r;
reg loaded_wds_pending_r;

// This is the same condition used by osc_handle_data() to substitute $80
// silence. Keep it combinational so sound_glu can invalidate the outstanding
// SDRAM-read owner on the exact timeout clock without changing the audio FSM.
wire wave_fetch_timeout_event_w =
    (cycle_state_r == CYCLE_OSC) &&
    !cycle_start_r &&
    (osc_state_r == OSC_HANDLE_DATA) &&
    !loaded_wds_pending_r &&
    (clk_count_r == 3'd7);

assign debug_wave_fetch_timeout_pulse_o =
    wave_fetch_timeout_event_w;

// Present a stable count for each completed 125 ms interval. The active
// counter saturates at $FF; the displayed byte changes only at the interval
// boundary so it remains readable on the HDMI overlay.
localparam int FETCH_DIAG_SLICE_CYCLES =
    CLOCK_SPEED_HZ / 8;
localparam int FETCH_DIAG_COUNTER_WIDTH =
    $clog2(FETCH_DIAG_SLICE_CYCLES);

logic [FETCH_DIAG_COUNTER_WIDTH-1:0]
    fetch_diag_slice_counter_r;
logic [7:0] fetch_timeout_slice_count_r;
logic [7:0] debug_wave_fetch_timeout_count_r;

assign debug_wave_fetch_timeout_count_o =
    debug_wave_fetch_timeout_count_r;

always_ff @(posedge clk_i) begin
    if (!reset_n_i) begin
        fetch_diag_slice_counter_r <= '0;
        fetch_timeout_slice_count_r <= 8'h00;
        debug_wave_fetch_timeout_count_r <= 8'h00;
    end else if (fetch_diag_slice_counter_r ==
                 FETCH_DIAG_SLICE_CYCLES - 1) begin
        fetch_diag_slice_counter_r <= '0;

        if (wave_fetch_timeout_event_w &&
            (fetch_timeout_slice_count_r != 8'hFF)) begin
            debug_wave_fetch_timeout_count_r <=
                fetch_timeout_slice_count_r + 1'b1;
        end else begin
            debug_wave_fetch_timeout_count_r <=
                fetch_timeout_slice_count_r;
        end

        fetch_timeout_slice_count_r <= 8'h00;
    end else begin
        fetch_diag_slice_counter_r <=
            fetch_diag_slice_counter_r + 1'b1;

        if (wave_fetch_timeout_event_w &&
            (fetch_timeout_slice_count_r != 8'hFF)) begin
            fetch_timeout_slice_count_r <=
                fetch_timeout_slice_count_r + 1'b1;
        end
    end
end

    wire ready_w = (cycle_state_r != CYCLE_RESET);
    assign ready_o = ready_w;

    always @(posedge clk_i) begin
        if (!reset_n_i) begin
            clk_count_r <= '0;
            cycle_timer_r <= '0;
            cycle_state_r <= CYCLE_RESET;
            curr_osc_r <= '0;
            cycle_start_r <= 1'b0;
        end else begin
            cycle_timer_r <= cycle_timer_r + 1'd1;
            cycle_start_r <= 1'b0;
            if (clk_en_i) begin
                clk_count_r <= clk_count_r + 1'd1;
                if (clk_count_r == 3'b111) begin
                    cycle_timer_r <= '0;
                    cycle_start_r <= 1'b1;

                    if (cycle_state_r == CYCLE_RESET) begin
                        curr_osc_r <= '0;
                        cycle_state_r <= CYCLE_OSC;
                    end else if (cycle_state_r == CYCLE_OSC) begin
                        if (curr_osc_r == osc_max_w) begin
                            cycle_state_r <= CYCLE_REFRESH_0;
                        end else begin
                            curr_osc_r <= curr_osc_r + 1'd1;
                        end
                    end else if (cycle_state_r == CYCLE_REFRESH_0) begin
                        cycle_state_r <= CYCLE_REFRESH_1;
                    end else if (cycle_state_r == CYCLE_REFRESH_1) begin
                        curr_osc_r <= '0;
                        cycle_state_r <= CYCLE_OSC;
                    end
                end
            end
        end
    end

    // Eight 125 ms slices form the live one-second display history.
    // Capture only the completed-mix decision at refresh slot 15, exactly
    // where debug_mix_clip_r is updated, so oscillator-processing cycles
    // cannot be mistaken for completed audio mixes.
    localparam int CLIP_HISTORY_SLICE_CYCLES = CLOCK_SPEED_HZ / 8;
    localparam int CLIP_HISTORY_COUNTER_WIDTH =
        $clog2(CLIP_HISTORY_SLICE_CYCLES);

    logic [CLIP_HISTORY_COUNTER_WIDTH-1:0]
        clip_history_counter_r;
    logic clip_history_left_pending_r;
    logic clip_history_right_pending_r;
    logic clip_history_mono_pending_r;

    wire completed_mix_w =
        (cycle_state_r == CYCLE_REFRESH_0) &&
        (cycle_timer_r < 'd16) &&
        (cycle_timer_r[3:0] == 4'hF);

    wire completed_left_clip_w = completed_mix_w &&
        mix_would_saturate(next_left_mix_r);
    wire completed_right_clip_w = completed_mix_w &&
        mix_would_saturate(next_right_mix_r);
    wire completed_mono_clip_w = completed_mix_w &&
        mix_would_saturate(next_mono_mix_r);

    // Observe the exact oscillator lifecycle boundaries without changing
    // any audio-path value or state transition.
    wire nonzero_osc_output_event_w =
        (cycle_state_r == CYCLE_OSC) &&
        !cycle_start_r &&
        (osc_state_r == OSC_OUT) &&
        !halt_w &&
        !((curr_mode_w == MODE_SYNC_AM) && curr_osc_odd_w) &&
        (curr_wds_r != 8'h80) &&
        (curr_vol_r != 8'h00);

    wire mixer_osc_event_w =
        (cycle_state_r == CYCLE_OSC) &&
        !cycle_start_r &&
        (osc_state_r == OSC_MIX);

    wire [31:0] diagnostic_osc_onehot_w =
        32'b1 << curr_osc_r;
    wire [15:0] diagnostic_channel_onehot_w =
        16'b1 << curr_ca_w;

    // Compare the exact values published by cycle_refresh0(), after the
    // unchanged DOC scale and saturation conversion.
    wire completed_left_nonzero_w = completed_mix_w &&
        (sat16_from_mix(next_left_mix_r) != 16'sd0);
    wire completed_right_nonzero_w = completed_mix_w &&
        (sat16_from_mix(next_right_mix_r) != 16'sd0);

    always_ff @(posedge clk_i) begin
        if (!reset_n_i) begin
            clip_history_counter_r <= '0;
            clip_history_left_pending_r <= 1'b0;
            clip_history_right_pending_r <= 1'b0;
            clip_history_mono_pending_r <= 1'b0;
            debug_mix_clip_history_left_r <= 8'h00;
            debug_mix_clip_history_right_r <= 8'h00;
            debug_mix_clip_history_mono_r <= 8'h00;
        end else if (clip_history_counter_r ==
                     CLIP_HISTORY_SLICE_CYCLES - 1) begin
            clip_history_counter_r <= '0;

            debug_mix_clip_history_left_r <= {
                debug_mix_clip_history_left_r[6:0],
                clip_history_left_pending_r ||
                    completed_left_clip_w
            };
            debug_mix_clip_history_right_r <= {
                debug_mix_clip_history_right_r[6:0],
                clip_history_right_pending_r ||
                    completed_right_clip_w
            };
            debug_mix_clip_history_mono_r <= {
                debug_mix_clip_history_mono_r[6:0],
                clip_history_mono_pending_r ||
                    completed_mono_clip_w
            };

            clip_history_left_pending_r <= 1'b0;
            clip_history_right_pending_r <= 1'b0;
            clip_history_mono_pending_r <= 1'b0;
        end else begin
            clip_history_counter_r <= clip_history_counter_r + 1'b1;

            if (completed_left_clip_w)
                clip_history_left_pending_r <= 1'b1;
            if (completed_right_clip_w)
                clip_history_right_pending_r <= 1'b1;
            if (completed_mono_clip_w)
                clip_history_mono_pending_r <= 1'b1;
        end
    end

    // Snapshot oscillator and channel activity once per 125 ms slice. The
    // displayed masks remain stable for the next slice, which makes them
    // readable in person and frame-accurate in a captured video.
    always_ff @(posedge clk_i) begin
        if (!reset_n_i) begin
            nonzero_osc_slice_mask_r <= 32'h00000000;
            mixer_osc_slice_mask_r <= 32'h00000000;
            debug_nonzero_osc_activity_r <= 32'h00000000;
            debug_mixer_osc_activity_r <= 32'h00000000;
            channel_slice_mask_r <= 16'h0000;
            debug_channel_activity_r <= 16'h0000;
            left_nonzero_pending_r <= 1'b0;
            right_nonzero_pending_r <= 1'b0;
            debug_left_nonzero_history_r <= 8'h00;
            debug_right_nonzero_history_r <= 8'h00;
        end else if (clip_history_counter_r ==
                     CLIP_HISTORY_SLICE_CYCLES - 1) begin
            debug_nonzero_osc_activity_r <=
                nonzero_osc_slice_mask_r |
                (nonzero_osc_output_event_w ?
                    diagnostic_osc_onehot_w : 32'h00000000);

            debug_mixer_osc_activity_r <=
                mixer_osc_slice_mask_r |
                (mixer_osc_event_w ?
                    diagnostic_osc_onehot_w : 32'h00000000);

            debug_channel_activity_r <=
                channel_slice_mask_r |
                (mixer_osc_event_w ?
                    diagnostic_channel_onehot_w : 16'h0000);

            debug_left_nonzero_history_r <= {
                debug_left_nonzero_history_r[6:0],
                left_nonzero_pending_r || completed_left_nonzero_w
            };
            debug_right_nonzero_history_r <= {
                debug_right_nonzero_history_r[6:0],
                right_nonzero_pending_r || completed_right_nonzero_w
            };

            nonzero_osc_slice_mask_r <= 32'h00000000;
            mixer_osc_slice_mask_r <= 32'h00000000;
            channel_slice_mask_r <= 16'h0000;
            left_nonzero_pending_r <= 1'b0;
            right_nonzero_pending_r <= 1'b0;
        end else begin
            if (nonzero_osc_output_event_w) begin
                nonzero_osc_slice_mask_r <=
                    nonzero_osc_slice_mask_r |
                    diagnostic_osc_onehot_w;
            end

            if (mixer_osc_event_w) begin
                mixer_osc_slice_mask_r <=
                    mixer_osc_slice_mask_r |
                    diagnostic_osc_onehot_w;
                channel_slice_mask_r <=
                    channel_slice_mask_r |
                    diagnostic_channel_onehot_w;
            end

            if (completed_left_nonzero_w)
                left_nonzero_pending_r <= 1'b1;
            if (completed_right_nonzero_w)
                right_nonzero_pending_r <= 1'b1;
        end
    end

    reg halt_zero_r = 1'b0;
    reg halt_overflow_r = 1'b0;

    reg host_request_pending_r = 1'b0;
    reg device_response_pending_r = 1'b0;

    always_ff @(posedge clk_i) begin
        if (!reset_n_i) begin
            osc_state_r <= OSC_IDLE;
            wave_address_o <= '0;
            wave_bank_o <= 1'b0;
            wave_rd_o <= '0;
            loaded_wds_pending_r <= '0;
halt_zero_r <= 1'b0;
halt_overflow_r <= 1'b0;

// cycle_reset() initializes every control register to $FF,
// so every oscillator begins with HALT=1.
osc_halt_shadow_r <= 32'hFFFFFFFF;

debug_halt_event_r <= 8'h00;
debug_halt_wtp_r <= 8'h00;
debug_halt_rts_r <= 8'h00;
debug_swap_ca_r <= 8'h00;

debug_host_ctrl_osc_r <= 8'h00;
debug_host_ctrl_data_r <= 8'h00;
debug_internal_ctrl_event_r <= 8'h00;
debug_internal_ctrl_data_r <= 8'h00;

debug_acc_start_osc_r <= 8'h00;
debug_acc_start_r <= 24'h000000;

debug_acc_end_osc_r <= 8'h00;
debug_acc_end_r <= 24'h000000;

debug_acc_start_pending_r <= 32'h00000000;

debug_fetch_osc_r <= 8'h00;
debug_fetch_wtp_r <= 8'h00;
debug_fetch_rts_r <= 8'h00;
debug_fetch_addr_r <= 16'h0000;
debug_fetch_data_r <= 8'h00;
debug_fetch_flags_r <= 8'h00;
debug_fetch_timeouts_r <= 8'h00;

debug_ctrl_write_osc_r <= 8'h00;
debug_ctrl_write_data_r <= 8'h00;
debug_ctrl_write_count_r <= 16'h0000;

debug_ctrl_read_osc_r <= 8'h00;
debug_ctrl_read_data_r <= 8'h00;
debug_ctrl_read_count_r <= 8'h00;

debug_ctrl_halt_count_r <= 8'h00;

debug_live_ctrl_r <= 8'h00;
debug_live_rts_r <= 8'h00;
debug_live_wtp_r <= 8'h00;
debug_live_acc_r <= 24'h000000;

debug_live_overflow_count_r <= 8'h00;
debug_live_wrap_count_r <= 8'h00;

debug_live_prev_acc_r <= 24'h000000;
debug_live_prev_valid_r <= 1'b0;


fetch_timeout_seen_r <= 8'h00;

for (fetch_reset_i = 0;
     fetch_reset_i < 8;
     fetch_reset_i = fetch_reset_i + 1) begin

    fetch_timeout_count_r[fetch_reset_i] <= 8'h00;
end

debug_am_write_toggle_r <= 1'b0;
debug_am_source_osc_r <= 5'd0;
debug_am_target_osc_r <= 5'd0;
debug_am_data_r <= 8'h00;
debug_am_target_vol_before_r <= 8'h00;

debug_vol_write_toggle_r <= 1'b0;
debug_vol_write_osc_r <= 5'd0;
debug_vol_write_data_r <= 8'h00;


debug_mix_osc_r <= 5'd0;
debug_mix_vol_r <= 8'h00;
debug_mix_wds_r <= 8'h80;
debug_mix_ca_r <= 4'h0;
debug_mix_output_r <= 18'sd0;

// Clear latest and sticky saturation indicators.
debug_mix_clip_r <= 8'h00;


            host_request_pending_r <= 1'b0;
            device_response_pending_r <= 1'b0;

            // Reset all oscillator RAM control signals

            ram_fl_osc_r <= '0;
            ram_fh_osc_r <= '0;
            ram_vol_osc_r <= '0;
            ram_wds_osc_r <= '0;
            ram_wtp_osc_r <= '0;
            ram_control_osc_r <= '0;
            ram_rts_osc_r <= '0;
            ram_acc_osc_r <= '0;

            ram_fl_din_r <= '0;
            ram_fh_din_r <= '0;
            ram_vol_din_r <= '0;
            ram_wds_din_r <= '0;
            ram_wtp_din_r <= '0;
            ram_control_din_r <= '0;
            ram_rts_din_r <= '0;
            ram_acc_din_r <= '0;

            ram_fl_we_r <= 1'b0;
            ram_fh_we_r <= 1'b0;
            ram_vol_we_r <= 1'b0;
            ram_wds_we_r <= 1'b0;
            ram_wtp_we_r <= 1'b0;
            ram_control_we_r <= 1'b0;
            ram_rts_we_r <= 1'b0;
            ram_acc_we_r <= 1'b0;

        end else begin

            wave_rd_o <= '0;

            if (host_access_r) begin
                host_request_pending_r <= 1'b1;
            end
            device_response_pending_r <= 1'b0;

            // Default all target oscillators to the current oscillator
            ram_fl_osc_r <= curr_osc_r;
            ram_fh_osc_r <= curr_osc_r;
            ram_vol_osc_r <= curr_osc_r;
            ram_wds_osc_r <= curr_osc_r;
            ram_wtp_osc_r <= curr_osc_r;
            ram_control_osc_r <= curr_osc_r;
            ram_rts_osc_r <= curr_osc_r;
            ram_acc_osc_r <= curr_osc_r;

            // Default all target write enables to 0
            ram_fl_we_r <= 1'b0;
            ram_fh_we_r <= 1'b0;
            ram_vol_we_r <= 1'b0;
            ram_wds_we_r <= 1'b0;
            ram_wtp_we_r <= 1'b0;
            ram_control_we_r <= 1'b0;
            ram_rts_we_r <= 1'b0;
            ram_acc_we_r <= 1'b0;

            if (wave_data_ready_i) begin
                loaded_wds_pending_r <= 1'b1;
            end

            case (cycle_state_r)
                CYCLE_RESET: cycle_reset();
                CYCLE_OSC: cycle_osc();
                CYCLE_REFRESH_0: cycle_refresh0();
                CYCLE_REFRESH_1: cycle_refresh1();
            endcase // case (cycle_state_r)

        end // else: !if(!reset_n_i)

    end // always_ff

 task automatic host_request();
    // Handles CPU register read/write access to DOC registers.
    // Processes oscillator interrupt and enable registers,
    // plus all oscillator-specific register banks.

    if (host_request_pending_r) begin
        host_request_pending_r <= 1'b0;

        if (!host_we_n_r) begin
            // Host write.
            data_o <= host_data_r;

            if (host_addr_r == 8'hE0) begin
                // Oscillator Interrupt Register.
                osc_int_r <= host_data_r;

            end else if (host_addr_r == 8'hE1) begin
                // Oscillator Enable Register.
                osc_en_r <= host_data_r;

            end else if ((host_addr_r >= 8'h00) &&
                         (host_addr_r <= 8'hDF)) begin

                case (host_addr_r[7:5])

                    3'b000: begin
                        // $00-$1F: Frequency Low.
                        ram_fl_osc_r <= host_addr_r[4:0];
                        ram_fl_din_r <= host_data_r;
                        ram_fl_we_r <= 1'b1;
                    end

                    3'b001: begin
                        // $20-$3F: Frequency High.
                        ram_fh_osc_r <= host_addr_r[4:0];
                        ram_fh_din_r <= host_data_r;
                        ram_fh_we_r <= 1'b1;
                    end

                    3'b010: begin
                        // $40-$5F: Volume.
                        ram_vol_osc_r <= host_addr_r[4:0];
                        ram_vol_din_r <= host_data_r;
                        ram_vol_we_r <= 1'b1;

                        // Capture every CPU volume write.
                        debug_vol_write_osc_r <=
                            host_addr_r[4:0];

                        debug_vol_write_data_r <=
                            host_data_r;

                        debug_vol_write_toggle_r <=
                            ~debug_vol_write_toggle_r;
                    end

                    3'b011: begin
                        // $60-$7F: Waveform Data Sample.
                        ram_wds_osc_r <= host_addr_r[4:0];
                        ram_wds_din_r <= host_data_r;
                        ram_wds_we_r <= 1'b1;
                    end

                    3'b100: begin
                        // $80-$9F: Waveform Table Pointer.
                        ram_wtp_osc_r <= host_addr_r[4:0];
                        ram_wtp_din_r <= host_data_r;
                        ram_wtp_we_r <= 1'b1;
                    end

                    3'b101: begin
                        // $A0-$BF: Oscillator Control.
                        automatic logic previous_halt_w;

                        previous_halt_w =
                            osc_halt_shadow_r[
                                host_addr_r[4:0]
                            ];

                        ram_control_osc_r <=
                            host_addr_r[4:0];

                        ram_control_din_r <=
                            host_data_r;

                        ram_control_we_r <= 1'b1;

                        // Original control-write trace.
                        debug_host_ctrl_osc_r <= {
                            3'b000,
                            host_addr_r[4:0]
                        };

                        debug_host_ctrl_data_r <=
                            host_data_r;

                        // Lifecycle trace.
                        debug_ctrl_write_osc_r <= {
                            3'b000,
                            host_addr_r[4:0]
                        };

                        debug_ctrl_write_data_r <=
                            host_data_r;

                        if (debug_ctrl_write_count_r !=
                            16'hFFFF) begin

                            debug_ctrl_write_count_r <=
                                debug_ctrl_write_count_r +
                                1'b1;
                        end

                        // Reset the accumulator only when
                        // HALT changes from 1 to 0.
                        if (previous_halt_w &&
                            !host_data_r[0]) begin

                            ram_acc_osc_r <=
                                host_addr_r[4:0];

                            ram_acc_din_r <= '0;
                            ram_acc_we_r <= 1'b1;

                            // Capture the actual starting
                            // accumulator later.
                            debug_acc_start_pending_r[
                                host_addr_r[4:0]
                            ] <= 1'b1;

// Begin a fresh live trace whenever oscillator 3
// genuinely transitions from HALTED to RUNNING.
if (host_addr_r[4:0] == 5'd3) begin
    debug_live_overflow_count_r <= 8'h00;
    debug_live_wrap_count_r <= 8'h00;

    debug_live_prev_acc_r <= 24'h000000;
    debug_live_prev_valid_r <= 1'b0;
end

                            // Begin a fresh waveform-fetch
                            // timeout measurement for
                            // oscillators 0-7.
                            if (host_addr_r[4:0] <
                                5'd8) begin

                                fetch_timeout_count_r[
                                    host_addr_r[2:0]
                                ] <= 8'h00;

                                fetch_timeout_seen_r[
                                    host_addr_r[2:0]
                                ] <= 1'b0;
                            end
                        end

                        // Record the new HALT state.
                        osc_halt_shadow_r[
                            host_addr_r[4:0]
                        ] <= host_data_r[0];
                    end

                    3'b110: begin
                        // $C0-$DF: Resolution/Table Size.
                        ram_rts_osc_r <= host_addr_r[4:0];
                        ram_rts_din_r <= host_data_r;
                        ram_rts_we_r <= 1'b1;
                    end

                    default: begin
                        // No oscillator register bank.
                    end

                endcase
            end

        end else begin
            // Host read.
            device_response_pending_r <= 1'b1;

            if ((host_addr_r >= 8'h00) &&
                (host_addr_r <= 8'hDF)) begin

                case (host_addr_r[7:5])

                    3'b000:
                        ram_fl_osc_r <=
                            host_addr_r[4:0];

                    3'b001:
                        ram_fh_osc_r <=
                            host_addr_r[4:0];

                    3'b010:
                        ram_vol_osc_r <=
                            host_addr_r[4:0];

                    3'b011:
                        ram_wds_osc_r <=
                            host_addr_r[4:0];

                    3'b100:
                        ram_wtp_osc_r <=
                            host_addr_r[4:0];

                    3'b101:
                        ram_control_osc_r <=
                            host_addr_r[4:0];

                    3'b110:
                        ram_rts_osc_r <=
                            host_addr_r[4:0];

                    default: begin
                        // No oscillator register bank.
                    end

                endcase
            end
        end
    end
endtask: host_request

    task automatic device_response();
        if (device_response_pending_r) begin
            device_response_pending_r <= 1'b0;
            // Handle device response to host request

            if (host_we_n_r) begin
                if (host_addr_r >= 8'h00 && host_addr_r <= 8'hDF) begin
                    // Read from oscillator registers
                    case (host_addr_r[7:5])
                        3'b000: begin                               // $00-1F
                            data_o <= ram_fl_dout_w;
                        end
                        3'b001: begin                               // $20-3F
                            data_o <= ram_fh_dout_w;
                        end
                        3'b010: begin                               // $40-5F
                            data_o <= ram_vol_dout_w;
                        end
                        3'b011: begin                               // $60-7F
                            data_o <= ram_wds_dout_w;
                        end
                        3'b100: begin                               // $80-9F
                            data_o <= ram_wtp_dout_w;
                        end
                        3'b101: begin
    // Return the value currently visible from the
    // shared control-register RAM port.
    data_o <= ram_control_dout_w;

    // Record exactly what oscillator was requested
    // and what value the FPGA returned.
    debug_ctrl_read_osc_r <= {
        3'b000,
        host_addr_r[4:0]
    };

    debug_ctrl_read_data_r <=
        ram_control_dout_w;

    if (debug_ctrl_read_count_r !=
        8'hFF) begin

        debug_ctrl_read_count_r <=
            debug_ctrl_read_count_r + 1'b1;
    end
end
                        3'b110: begin                               // $C0-DF
                            data_o <= ram_rts_dout_w;
                        end
                    endcase
                end else if (host_addr_r == 8'hE0) begin
                    // Oscillator Interrupt Register
                    data_o <= osc_int_r; 
                end else if (host_addr_r == 8'hE1) begin
                    // Oscillator Enable Register
                    data_o <= osc_en_r;
                end else begin
                    data_o <= '0; // Default value for unrecognized addresses
                end
            end
        end
    endtask: device_response

    task automatic host_access();
        host_request();
        device_response();
    endtask: host_access

    task automatic cycle_reset();
        // Initialize all oscillator registers during reset cycle
        // Sets frequency, volume, waveform, control registers to default values
        // Ensures all oscillators start in non-halted state with zeroed accumulators
        // This differs from the original DOC5503 which initializes the register bits to 1
        // Called during CYCLE_RESET state only

         // Set target oscillators based on cycle time
        ram_fl_osc_r <= cycle_timer_r[4:0];
        ram_fh_osc_r <= cycle_timer_r[4:0];
        ram_vol_osc_r <= cycle_timer_r[4:0];
        ram_wds_osc_r <= cycle_timer_r[4:0];
        ram_wtp_osc_r <= cycle_timer_r[4:0];
        ram_control_osc_r <= cycle_timer_r[4:0];
        ram_rts_osc_r <= cycle_timer_r[4:0];
        ram_acc_osc_r <= cycle_timer_r[4:0];

        ram_fl_we_r <= 1'b1;
        ram_fh_we_r <= 1'b1;
        ram_vol_we_r <= 1'b1;
        ram_wds_we_r <= 1'b1;
        ram_wtp_we_r <= 1'b1;
        ram_control_we_r <= 1'b1;
        ram_rts_we_r <= 1'b1;
        ram_acc_we_r <= 1'b1;

        ram_fl_din_r <= '0;
        ram_fh_din_r <= '0;
        ram_vol_din_r <= '0;
        ram_wds_din_r <= '0;
        ram_wtp_din_r <= '0;
        ram_control_din_r <= '1;
        ram_rts_din_r <= '0;
        ram_acc_din_r <= '0;

    endtask: cycle_reset

    task automatic cycle_refresh0();
        // First phase of output channel refresh cycle
        // Copies next_channel values to channel output registers
        // Updates mono_mix, left_mix, and right_mix final output values
        // Only updates final mix values when processing the last channel (15)

        if (cycle_timer_r < 'd16) begin
            if (cycle_start_r) begin
                device_response();
            end
    
//            channel_r[cycle_timer_r[3:0]] <= {
//                 Sign bit
//                next_channel_r[cycle_timer_r[3:0]][MIXER_SUM_RESOLUTION-1],
//                 Magnitude bits - using parameterized window 
//                next_channel_r[cycle_timer_r[3:0]][MIXER_SUM_RESOLUTION-1-TOP_BIT_OFFSET -: WINDOW_SIZE]
//            };



channel_r[cycle_timer_r[3:0]] <=
    sat16_from_mix(next_channel_r[cycle_timer_r[3:0]]);



            
            // Only copy the final values when processing the last channel (15)
            if (cycle_timer_r[3:0] == 4'hF) begin
//                mono_mix_r <= {
//                    next_mono_mix_r[MIXER_SUM_RESOLUTION-1],
//                    next_mono_mix_r[MIXER_SUM_RESOLUTION-1-TOP_BIT_OFFSET -: WINDOW_SIZE]
//                };
//                left_mix_r <= {
//                    next_left_mix_r[MIXER_SUM_RESOLUTION-1],
//                    next_left_mix_r[MIXER_SUM_RESOLUTION-1-TOP_BIT_OFFSET -: WINDOW_SIZE]
//                };
//                right_mix_r <= {
//                    next_right_mix_r[MIXER_SUM_RESOLUTION-1],
//                    next_right_mix_r[MIXER_SUM_RESOLUTION-1-TOP_BIT_OFFSET -: WINDOW_SIZE]
//                };
                // Debug: Print the final mix values

mono_mix_r <=
    sat16_from_mix(next_mono_mix_r);

left_mix_r <=
    sat16_from_mix(next_left_mix_r);

right_mix_r <=
    sat16_from_mix(next_right_mix_r);


// --------------------------------------------------
// Completed-mix saturation diagnostics.
//
// Low nibble: current completed mix
//   bit 0 = left
//   bit 1 = right
//   bit 2 = mono
//   bit 3 = any
//
// High nibble: sticky until reset
//   bit 4 = left
//   bit 5 = right
//   bit 6 = mono
//   bit 7 = any
// --------------------------------------------------

// Current completed-mix flags.
debug_mix_clip_r[0] <=
    mix_would_saturate(next_left_mix_r);

debug_mix_clip_r[1] <=
    mix_would_saturate(next_right_mix_r);

debug_mix_clip_r[2] <=
    mix_would_saturate(next_mono_mix_r);

debug_mix_clip_r[3] <=
    mix_would_saturate(next_left_mix_r) ||
    mix_would_saturate(next_right_mix_r) ||
    mix_would_saturate(next_mono_mix_r);


// Sticky left saturation.
if (mix_would_saturate(next_left_mix_r)) begin
    debug_mix_clip_r[4] <= 1'b1;
end

// Sticky right saturation.
if (mix_would_saturate(next_right_mix_r)) begin
    debug_mix_clip_r[5] <= 1'b1;
end

// Sticky mono saturation.
if (mix_would_saturate(next_mono_mix_r)) begin
    debug_mix_clip_r[6] <= 1'b1;
end

// Sticky any-channel saturation.
if (mix_would_saturate(next_left_mix_r) ||
    mix_would_saturate(next_right_mix_r) ||
    mix_would_saturate(next_mono_mix_r)) begin

    debug_mix_clip_r[7] <= 1'b1;
end


            end
        end else begin
            // use remaining time to process host access
            host_access();
        end

    endtask: cycle_refresh0

    task automatic cycle_refresh1();
        // Second phase of output channel refresh cycle 
        // Resets next_channel accumulators for the next oscillator processing cycle
        // Clears mono_mix, left_mix, and right_mix accumulators when processing last channel

        if (cycle_timer_r < 'd16) begin
            if (cycle_start_r) begin
                device_response();
            end

            next_channel_r[cycle_timer_r[3:0]] <= '0;
            
            // Only reset the mix values when processing the last channel (15)
            if (cycle_timer_r[3:0] == 4'hF) begin
                next_mono_mix_r <= '0;
                next_left_mix_r <= '0;
                next_right_mix_r <= '0;
        end
        end else begin
            // use remaining time to process host access
            host_access();
        end

    endtask: cycle_refresh1

task automatic cycle_osc();
    automatic osc_state_e osc_state_w;

    osc_state_w =
        cycle_start_r ? OSC_IDLE : osc_state_r;

    case (osc_state_w)
        OSC_IDLE:
            osc_idle();

        OSC_START:
            osc_start();

        OSC_LOAD_REGISTERS:
            osc_load_registers();

        OSC_LOAD_PARTNER_CONTROL:
            osc_load_partner_control();

        OSC_LOAD_NEXT_CONTROL:
            osc_load_next_control();

        OSC_REQUEST_DATA:
            osc_request_data();

        OSC_HANDLE_DATA:
            osc_handle_data();

        OSC_OUT:
            osc_out();

        OSC_MIX:
            osc_mix();

        OSC_ACC:
            osc_acc();

        OSC_HALT:
            osc_halt();

        OSC_HALT_ONE_SHOT_OR_ZERO_BYTE:
            osc_halt_one_shot_or_zero_byte();

        OSC_START_PARTNER:
            osc_start_partner();

        OSC_RETRIGGER:
            osc_retrigger();

        default:
            osc_idle();
    endcase
endtask: cycle_osc
    
    task automatic osc_idle();
        // Idle state for oscillator state machine
        // Waits for the start of a new cycle to begin processing
        // Handles host access to oscillator registers
        // Sets the oscillator state to OSC_START when a new cycle begins

        osc_state_r <= OSC_IDLE;
        host_access();

        if (cycle_start_r) begin
            osc_state_r <= OSC_START;
        end

    endtask : osc_idle

    task automatic osc_start();
        device_response();

        // Init other working values
        curr_output_r <= '0;
        halt_zero_r <= 1'b0;
        halt_overflow_r <= 1'b0;

// DOC control RAM is reset to all ones, so every
// oscillator initially has HALT=1.



        osc_state_r <= OSC_LOAD_REGISTERS;
    endtask: osc_start

    task automatic osc_load_registers();
        // Load all current oscillator registers from register file RAM
        // Transitions to OSC_REQUEST_DATA state to begin oscillator processing
        curr_fl_r <= ram_fl_dout_w;                  // Frequency low
        curr_fh_r <= ram_fh_dout_w;                  // Frequency high
        curr_vol_r <= ram_vol_dout_w;                // Volume
        curr_wds_r <= ram_wds_dout_w;                // Waveform data sample
        curr_wtp_r <= ram_wtp_dout_w;                // Waveform table pointer
        curr_control_r <= ram_control_dout_w;        // Control
        curr_rts_r <= ram_rts_dout_w;                // Resolution/table size
        curr_acc_r <= ram_acc_dout_w;                // Accumulator

        ram_control_osc_r <= partner_osc_w;

        osc_state_r <= OSC_LOAD_PARTNER_CONTROL;             // Request data from memory
    endtask: osc_load_registers

    task automatic osc_load_partner_control();
        partner_control_r <= ram_control_dout_w;
        ram_control_osc_r <= curr_osc_r + 1'b1;
        osc_state_r <= OSC_LOAD_NEXT_CONTROL;
    endtask: osc_load_partner_control

    task automatic osc_load_next_control();
        next_control_r <= ram_control_dout_w;
        ram_control_osc_r <= curr_osc_r - 1'b1;
        osc_state_r <= OSC_REQUEST_DATA;
    endtask: osc_load_next_control

    task automatic osc_request_data();
        // Generate wave table address and request data if oscillator not halted
        // If oscillator is halted, handles one-shot mode accumulator reset
        //
        // Per the DOC5503 datasheet timing diagrams (pp. 19, 23), the real chip
        // reads waveform data and uses it in the same oscillator cycle:
        //   - Address output within Tas (50 ns) of E rising
        //   - DRAM read completes during E-high phase (~300-400 ns)
        //   - Data used for volume multiplication and analog output during E-low
        //   - Accumulator updated at end of cycle
        // This implementation matches that behavior: fetch -> output -> ACC += FC

 automatic logic [15:0] curr_wave_addr_w =
    16'(curr_acc_r >> curr_shift_w);

// Capture the first actual accumulator observed after
// an oscillator was placed into RUN state.
//
// This happens after register loading, so curr_acc_r is
// the accumulator value the waveform-address calculation
// is genuinely about to use.
if (!halt_w &&
    debug_acc_start_pending_r[curr_osc_r]) begin

    debug_acc_start_osc_r <= {
        3'b000,
        curr_osc_r
    };

    debug_acc_start_r <= curr_acc_r;

    debug_acc_start_pending_r[
        curr_osc_r
    ] <= 1'b0;
end

if (!halt_w) begin
            // Address Output Multiplexer - create wave table address from accumulator
            // Create mask for wave table pointer based on wave table size
            automatic logic [7:0] ptr_hi_mask_w = 8'(8'hFF << curr_wts_w);
            // Create pointer to wave table with ignored bits masked out
            automatic logic [15:0] ptr_w = {ptr_hi_mask_w & curr_wtp_r, 8'b0};
            // 
            automatic logic [15:0] addr_w = curr_wave_addr_w | ptr_w;

            // Read next byte from SDRAM.
            //
            // RTS bit 6 selects the lower or upper
            // 64K waveform RAM bank.
            loaded_wds_pending_r <= 1'b0;
            wave_address_o <= addr_w;
            wave_bank_o <= curr_rts_r[6];
            wave_rd_o <= 1'b1;

            osc_state_r <= OSC_HANDLE_DATA;

        end else begin
            // When halted but in one-shot mode, clear accumulator
            if (curr_mode_w[0]) begin
                ram_acc_we_r <= 1'b1;
                ram_acc_din_r <= '0;
            end
            // When halted, skip OUT and return to IDLE state
            osc_state_r <= OSC_IDLE;
        end

if (curr_osc_r < 5'd8) begin
    debug_osc_mode_r[
        curr_osc_r[2:0]
    ] <= curr_mode_w;
end

        // load prev control register (needed later)
        prev_control_r <= ram_control_dout_w;
    endtask: osc_request_data

   task automatic osc_handle_data();
    // Process waveform data returned from sound RAM.

    if (loaded_wds_pending_r) begin
        loaded_wds_pending_r <= 1'b0;

        ram_wds_we_r <= 1'b1;
        ram_wds_din_r <= loaded_wds_r;
        curr_wds_r <= loaded_wds_r;

        if (loaded_wds_r == 8'h00) begin
            halt_zero_r <= 1'b1;
            osc_state_r <= OSC_HALT;
        end else begin
            osc_state_r <= OSC_OUT;
        end

    end else if (clk_count_r == 3'd7) begin
        // No waveform byte arrived before the oscillator
        // slot expired. Use offset-binary silence.
        curr_wds_r <= 8'h80;

        if (curr_osc_r < 5'd8) begin
            fetch_timeout_seen_r[
                curr_osc_r[2:0]
            ] <= 1'b1;

            if (fetch_timeout_count_r[
                    curr_osc_r[2:0]
                ] != 8'hFF) begin

                fetch_timeout_count_r[
                    curr_osc_r[2:0]
                ] <=
                    fetch_timeout_count_r[
                        curr_osc_r[2:0]
                    ] + 1'b1;
            end
        end

        osc_state_r <= OSC_OUT;
    end
endtask: osc_handle_data

task automatic osc_out();
    // Calculate the oscillator output from waveform data
    // and the oscillator's programmed DOC volume.
    //
    // Restore the original pre-AM-experiment behavior:
    //
    // An odd oscillator in SYNC/AM mode produces no direct
    // audio. Its waveform-data byte is written to the volume
    // register of the following even oscillator.
    //
    // This is the known working baseline. Native AM behavior
    // can be revisited separately after broader playback
    // regressions are resolved.

    if ((curr_mode_w == MODE_SYNC_AM) &&
        curr_osc_odd_w) begin

        // Odd oscillator in SYNC/AM mode produces no
        // direct mixer output.
        curr_output_r <= 18'sd0;

        if ((curr_osc_r != 5'd31) &&
            !next_halt_w) begin

            ram_vol_osc_r <= curr_osc_r + 1'b1;
            ram_vol_we_r <= 1'b1;
            ram_vol_din_r <= curr_wds_r;

            // Preserve the existing diagnostic capture.
            debug_am_source_osc_r <= curr_osc_r;
            debug_am_target_osc_r <=
                curr_osc_r + 1'b1;
            debug_am_data_r <= curr_wds_r;
            debug_am_target_vol_before_r <=
                ram_vol_dout_w;
            debug_am_write_toggle_r <=
                ~debug_am_write_toggle_r;
        end

        // Skip direct mixing for the AM-control oscillator.
        osc_state_r <= OSC_ACC;

    end else begin
        automatic logic signed [7:0] data_w;
        automatic logic signed [8:0] vol_s;
        automatic logic signed [17:0] output_w;

        // DOC samples are stored as offset binary:
        // $80 is zero amplitude.
        data_w = curr_wds_r ^ 8'h80;

        // DOC volume is unsigned.
        vol_s = $signed({
            1'b0,
            curr_vol_r
        });

        output_w = data_w * vol_s;

        if (FORCE_ZERO_VOLUME_MUTE &&
            (curr_vol_r == 8'h00)) begin

            curr_output_r <= 18'sd0;

        end else begin

            curr_output_r <= output_w;
        end

        channel_sum_r <=
            next_channel_r[curr_ca_w];

        osc_state_r <= OSC_MIX;
    end
endtask: osc_out

task automatic osc_mix();
    automatic logic signed [17:0]
        mix_output_w;

    // Capture the oscillator that reached the mixer.
    debug_mix_osc_r <= curr_osc_r;
    debug_mix_vol_r <= curr_vol_r;
    debug_mix_wds_r <= curr_wds_r;
    debug_mix_ca_r <= curr_ca_w;

    // Enforce exact digital silence for halted or
    // zero-volume oscillators.
    if (halt_w) begin

        mix_output_w = 18'sd0;

    end else if (FORCE_ZERO_VOLUME_MUTE &&
                 (curr_vol_r == 8'h00)) begin

        mix_output_w = 18'sd0;

    end else begin

        mix_output_w = curr_output_r;
    end

    debug_mix_output_r <= mix_output_w;

    next_channel_r[curr_ca_w] <=
        channel_sum_r + mix_output_w;

    next_mono_mix_r <=
        next_mono_mix_r + mix_output_w;

    if (curr_ca_w[0]) begin
        next_left_mix_r <=
            next_left_mix_r + mix_output_w;
    end else begin
        next_right_mix_r <=
            next_right_mix_r + mix_output_w;
    end

    osc_state_r <= OSC_ACC;
endtask: osc_mix

task automatic osc_acc();
    // Update the oscillator accumulator and detect
    // crossing of the active resolution boundary.

    automatic logic [24:0] temp_acc;
    automatic logic [23:0] masked_acc_w;
    automatic logic overflow;

    temp_acc =
        {1'b0, curr_acc_r} +
        {
            9'b000000000,
            curr_fh_r,
            curr_fl_r
        };

    masked_acc_w =
        temp_acc[23:0] &
        curr_acc_mask_w;

    // The active accumulator limit is:
    //
    //   $00020000 for RES=0
    //   ...
    //   $01000000 for RES=7
    //
    // Crossing that boundary is the waveform-table
    // overflow event.
    overflow =
        temp_acc >= curr_acc_limit_w;

    halt_overflow_r <= overflow;

    ram_acc_we_r <= 1'b1;
    ram_acc_din_r <= masked_acc_w;

    osc_state_r <= OSC_IDLE;

    // Preserve the oscillator-3 live diagnostic.
    if (curr_osc_r == 5'd3) begin
        debug_live_ctrl_r <=
            curr_control_r;

        debug_live_rts_r <=
            curr_rts_r;

        debug_live_wtp_r <=
            curr_wtp_r;

        debug_live_acc_r <=
            masked_acc_w;

        if (overflow &&
            (debug_live_overflow_count_r !=
             8'hFF)) begin

            debug_live_overflow_count_r <=
                debug_live_overflow_count_r + 1'b1;
        end

        if (debug_live_prev_valid_r &&
            (masked_acc_w <
             debug_live_prev_acc_r) &&
            (debug_live_wrap_count_r !=
             8'hFF)) begin

            debug_live_wrap_count_r <=
                debug_live_wrap_count_r + 1'b1;
        end

        debug_live_prev_acc_r <=
            masked_acc_w;

        debug_live_prev_valid_r <=
            1'b1;
    end

    if (overflow) begin
        if (curr_osc_r < 5'd8) begin
            debug_acc_end_osc_r <= {
                3'b000,
                curr_osc_r
            };

            debug_acc_end_r <=
                temp_acc[23:0];
        end

        osc_state_r <= OSC_HALT;
    end
endtask: osc_acc

    task automatic osc_halt();
        // Handles oscillator state on halt events (overflow or zero byte)
        // Special processing for SYNC_AM mode where even oscillator halt
        // resets the accumulator of the previous odd oscillator
        // Latched halt event:
        //
        // bits 7:3 = oscillator number, 0-31
        // bits 2:1 = oscillator mode
        // bit 0    = 1 for zero-byte halt
        //            0 for accumulator/table overflow

// Capture the exact memory-fetch state that led to
// this halt. Restrict the visible trace to SynthLAB's
// first eight audio oscillators.
if (curr_osc_r < 5'd8) begin
    debug_fetch_osc_r <= {
        3'b000,
        curr_osc_r
    };

    debug_fetch_wtp_r <= curr_wtp_r;
    debug_fetch_rts_r <= curr_rts_r;
    debug_fetch_addr_r <= wave_address_o;
    debug_fetch_data_r <= curr_wds_r;

    debug_fetch_flags_r <= {
        5'b00000,
        fetch_timeout_seen_r[curr_osc_r[2:0]],
        halt_overflow_r,
        halt_zero_r
    };

    debug_fetch_timeouts_r <=
        fetch_timeout_count_r[curr_osc_r[2:0]];
end




        if (halt_zero_r ||
            (curr_mode_w != MODE_FREE)) begin
            debug_halt_event_r <= {
                curr_osc_r,
                curr_mode_w,
                halt_zero_r
            };
            debug_halt_wtp_r <= curr_wtp_r;
            debug_halt_rts_r <= curr_rts_r;
            debug_swap_ca_r <= {
                curr_control_r[7:4],
                partner_control_r[7:4]
             };
        end


        if (curr_mode_w == MODE_SYNC_AM) begin
            if (curr_osc_even_w) begin
                // we're even, so if the odd oscillator 1 below us is playing,
                // restart it.
                if (!prev_halt_w) begin
                    ram_acc_osc_r <= curr_osc_r - 1'b1;                // set target oscillator to previous one
                    ram_acc_we_r <= 1'b1;                              // write to accumulator register
                    ram_acc_din_r <= '0;                               // set accumulator to zero
                end
            end
        end
        osc_state_r <= OSC_HALT_ONE_SHOT_OR_ZERO_BYTE;
    endtask: osc_halt

 task automatic osc_halt_one_shot_or_zero_byte();
    // The register RAM consumes the address, write-enable, and data
    // values on the following clk_i edge.
    //
    // Therefore this state explicitly stages the current oscillator's
    // halt write using the current oscillator as the target.
    //
    // The following OSC_START_PARTNER state separately stages the
    // partner oscillator's start write using the partner as the target.

// Diagnostic operation 100:
// entered one-shot/zero-byte halt handling.
//
// Restrict this capture to the first eight oscillators.
// Oscillator 31 is commonly used as the MIDI Synth timer
// and otherwise overwrites the instrument event before
// it can be observed on the video overlay.
if (curr_osc_r < 5'd8) begin
    debug_internal_ctrl_event_r <= {
        3'b100,
        curr_osc_r
    };

    debug_internal_ctrl_data_r <=
        curr_control_r;
end



    if (curr_mode_w[0] || halt_zero_r) begin

        // Count internally generated halts for the
        // first eight SynthLAB audio oscillators.
        if (curr_osc_r < 5'd8) begin
            if (debug_ctrl_halt_count_r !=
                8'hFF) begin

                debug_ctrl_halt_count_r <=
                    debug_ctrl_halt_count_r + 1'b1;
            end
        end

        // Explicitly target the oscillator that just completed.
        ram_control_osc_r <= curr_osc_r;
        ram_control_we_r <= 1'b1;

        // Preserve channel, interrupt, and mode fields.
        // Set only the HALT bit.
 ram_control_din_r <= {
    curr_control_r[7:1],
    1'b1
};



// Internal operation 001:
// halt the oscillator that just completed.
if (curr_osc_r < 5'd8) begin
    // Internal operation 001:
    // halt the oscillator that just completed.
    debug_internal_ctrl_event_r <= {
        3'b001,
        curr_osc_r
    };

    debug_internal_ctrl_data_r <= {
        curr_control_r[7:1],
        1'b1
    };
end

curr_control_r <= {
    curr_control_r[7:1],
    1'b1
};

// Keep the HALT shadow synchronized with the
// internally generated one-shot/zero-byte halt.
osc_halt_shadow_r[curr_osc_r] <= 1'b1;
    end

    osc_state_r <= OSC_IDLE;

    if (curr_mode_w == MODE_SWAP) begin
        // Do not change the control-RAM address here.
        // The current oscillator's halt write must retain
        // curr_osc_r as its staged target.
        osc_state_r <= OSC_START_PARTNER;
    end else begin
        if ((partner_mode_w == MODE_SWAP) &&
            curr_osc_even_w) begin

            osc_state_r <= OSC_RETRIGGER;
        end
    end
endtask: osc_halt_one_shot_or_zero_byte


task automatic osc_start_partner();
    // The previous state staged the current oscillator halt write.
    // That write commits as this state executes.
    //
    // Now stage a separate write explicitly targeting the partner.

    ram_control_osc_r <= partner_osc_w;
    ram_control_we_r <= 1'b1;

    // Preserve the partner's own channel assignment,
    // interrupt bit, and mode. Clear only its HALT bit.
 ram_control_din_r <= {
    partner_control_r[7:1],
    1'b0
};

// The partner is now internally placed into RUN state.
osc_halt_shadow_r[partner_osc_w] <= 1'b0;



// Internal operation 010:
// start the swap partner.
if (partner_osc_w < 5'd8) begin
    debug_internal_ctrl_event_r <= {
        3'b010,
        partner_osc_w
    };

    debug_internal_ctrl_data_r <= {
        partner_control_r[7:1],
        1'b0
    };
end

    // Restart the partner from the beginning of its waveform.
ram_acc_osc_r <= partner_osc_w;
ram_acc_we_r <= 1'b1;
ram_acc_din_r <= '0;

// The partner has been explicitly restarted.
// Capture its actual accumulator when it reaches
// OSC_REQUEST_DATA.
debug_acc_start_pending_r[
    partner_osc_w
] <= 1'b1;

    osc_state_r <= OSC_IDLE;
endtask: osc_start_partner




  task automatic osc_retrigger();
    // Retrigger the current even oscillator when its partner
    // is configured for swap mode.

    ram_control_osc_r <= curr_osc_r;
    ram_control_we_r <= 1'b1;

 ram_control_din_r <= {
    curr_control_r[7:1],
    1'b0
};

// The current oscillator is internally placed
// into RUN state.
osc_halt_shadow_r[curr_osc_r] <= 1'b0;


// Capture the retriggered oscillator's actual accumulator
// when it reaches OSC_REQUEST_DATA.
debug_acc_start_pending_r[
    curr_osc_r
] <= 1'b1;

// Internal operation 011:
// retrigger the current oscillator.
if (curr_osc_r < 5'd8) begin
    debug_internal_ctrl_event_r <= {
        3'b011,
        curr_osc_r
    };

    debug_internal_ctrl_data_r <= {
        curr_control_r[7:1],
        1'b0
    };
end

    osc_state_r <= OSC_IDLE;
endtask: osc_retrigger

endmodule

module osc_reg_ram #(
    parameter int DATA_WIDTH = 8
) (
    input clk_i,
    input [4:0] osc_i,
    input we_i,
    input [DATA_WIDTH-1:0] data_i,
    output [DATA_WIDTH-1:0] data_o
);
    // This should infer as a RAM16 single port SSRAM during synthesis on Gowin
    // that is implemented in LUTs via Configurable Function Units,
    // allowing for synchronous write and asynchronous read.
    // Other FPGA families may use different synthesis directives.
    // Use of a different RAM structure like blockram might require
    // a different approach if asynchronous read is not supported, such as
    // requiring waiting an additional clock cycle from address valid to
    // data available.
    reg [DATA_WIDTH-1:0] osc_reg_r[32] /*synthesis syn_ramstyle="distributed_ram"*/; 
    always_ff @(posedge clk_i) begin
        if (we_i) begin
            osc_reg_r[osc_i] <= data_i;
        end
    end

    assign data_o = osc_reg_r[osc_i];

endmodule
