// Standalone simulation for the MB-DOC bridge.
// No Gowin primitives required. This checks control command order,
// SDRAM waveform initialization, stereo oscillator controls, divider
// frequency results and six independent voices, not actual DOC audio.
`timescale 1ns/1ps
module tb_mb_doc_bridge;
    logic clk = 1'b0;
    always #5 clk = ~clk;
    logic reset_n = 1'b0;
    logic sdram_ready = 1'b0;

    logic l_wr = 0, r_wr = 0;
    logic [3:0] l_reg = 0, r_reg = 0;
    logic [7:0] l_data = 0, r_data = 0;

    wire doc_wr;
    wire [7:0] doc_addr, doc_data;
    wire ram_wr;
    wire [20:0] ram_addr;
    wire [31:0] ram_data;
    wire [3:0] ram_byte_en;
    logic ram_ready = 0;
    wire active,unused;
    wire [2:0] active_voice;

    mb_doc_bridge #(
        .HOST_SPACING_CYCLES(80),
        .SCAN_PAUSE_CYCLES(128)
    ) dut (
        .clk_i(clk), .reset_n_i(reset_n),
        .sdram_ready_i(sdram_ready),
        .ay_l_wr_i(l_wr), .ay_l_reg_i(l_reg),
        .ay_l_data_i(l_data),
        .ay_r_wr_i(r_wr), .ay_r_reg_i(r_reg),
        .ay_r_data_i(r_data),
        .doc_wr_o(doc_wr), .doc_addr_o(doc_addr),
        .doc_data_o(doc_data),
        .ram_wr_o(ram_wr), .ram_addr_o(ram_addr),
        .ram_data_o(ram_data), .ram_byte_en_o(ram_byte_en),
        .ram_ready_i(ram_ready), .ready_o(active),
        .active_voice_o(active_voice)
    );

    integer write_count = 0, doc_count = 0;
    integer ram_busy = 0, ram_delay = 0;
    logic prev_ram_wr = 0;
    logic [7:0] doc_addresses [0:127];
    logic [7:0] doc_values [0:127];

    function automatic [7:0] wave(input [7:0] phase);
        reg [7:0] ramp;
        begin
            ramp = {phase[5:0],1'b0};
            case (phase[7:6])
                2'b00: wave = 8'h81 + ramp;
                2'b01: wave = 8'hFF - ramp;
                2'b10: wave = 8'h7F - ramp;
                default: wave = 8'h01 + ramp;
            endcase
        end
    endfunction

    // Pretend the SDRAM controller acknowledges exactly once.
    always @(posedge clk) begin
        ram_ready <= 1'b0;
        if (!reset_n) begin
            ram_busy <= 0;
            ram_delay <= 0;
            prev_ram_wr <= 0;
        end else begin
            prev_ram_wr <= ram_wr;
            if (ram_wr && !prev_ram_wr) begin
                if (ram_busy || write_count >= 64)
                    $fatal(1, "RAM double request");
                if (ram_addr !== write_count || ram_byte_en !== 4'hF)
                    $fatal(1, "Bad RAM addr/lane %d %h", write_count, ram_addr);
                for (integer lane=0; lane<4; lane=lane+1)
                    if (ram_data[lane*8 +:8] !== wave(8'(write_count*4+lane))
                        || ram_data[lane*8 +:8] == 8'h00)
                        $fatal(1, "Bad triangle byte word=%d lane=%d data=%h",
                               write_count, lane, ram_data[lane*8 +:8]);
                write_count <= write_count + 1;
                ram_busy <= 1;
                ram_delay <= 4;
            end
            if (ram_busy) begin
                if (ram_delay == 0) begin
                    ram_ready <= 1'b1;
                    ram_busy <= 0;
                end else ram_delay <= ram_delay - 1;
            end
            if (doc_wr) begin
                if (write_count != 64)
                    $fatal(1, "DOC command before preload complete");
                if (doc_count < 128) begin
                    doc_addresses[doc_count] <= doc_addr;
                    doc_values[doc_count] <= doc_data;
                end
                doc_count <= doc_count + 1;
            end
        end
    end

    task automatic ay_write(
        input logic chip,
        input logic [3:0] reg_id,
        input logic [7:0] data_byte
    );
        @(negedge clk);
        if (chip) begin
            r_reg = reg_id; r_data = data_byte; r_wr = 1;
        end else begin
            l_reg = reg_id; l_data = data_byte; l_wr = 1;
        end
        @(negedge clk);
        l_wr = 0; r_wr = 0;
    endtask

    task automatic voice_setup(
        input integer voice,
        input integer period
    );
        reg chip;
        reg [3:0] base;
        begin
            chip = voice >= 3;
            base = 4'((voice % 3)*2);
            ay_write(chip, base, 8'(period));
            ay_write(chip, base+1, 8'(period>>8));
            ay_write(chip, 4'(8+voice%3), 8'h0F);
        end
    endtask

    function automatic integer period_for(input integer i);
        case(i)
            0:period_for=100;
            1:period_for=150;
            2:period_for=200;
            3:period_for=250;
            4:period_for=300;
            default:period_for=400;
        endcase
    endfunction

    initial begin
        repeat(4) @(negedge clk);
        reset_n = 1'b1;
        for (integer i=0; i<6; i=i+1)
            voice_setup(i, period_for(i));

        sdram_ready = 1;
        wait (active && doc_count >= 43);
        @(negedge clk);

        if (write_count != 64 || doc_count < 43)
            $fatal(1, "Startup incomplete %d / %d",write_count,doc_count);
        if (doc_addresses[0] !== 8'hE1 || doc_values[0] !== 8'h0E)
            $fatal(1, "Osc enable incorrect");
        for (integer v=0;v<6;v=v+1) begin
            integer off, expect_fc;
            off = 1 + v*7;
            expect_fc = 93623 / period_for(v);
            if (doc_addresses[off] !== 8'(8'hA0+v) ||
                doc_values[off] !== (v < 3 ? 8'h11 : 8'h01))
                $fatal(1, "Voice %0d initial HALT bad",v);
            if (doc_addresses[off+1] !== 8'(8'h80+v) ||
                doc_values[off+1] !== 8'h00)
                $fatal(1, "Voice %0d WTP bad",v);
            if (doc_addresses[off+2] !== 8'(8'hC0+v) ||
                doc_values[off+2] !== 8'h00)
                $fatal(1, "Voice %0d RTS bad",v);
            if (doc_addresses[off+3] !== 8'(v) ||
                doc_values[off+3] !== 8'(expect_fc))
                $fatal(1,"Voice %0d freq low got %h expected %h",
                       v,doc_values[off+3],8'(expect_fc));
            if (doc_addresses[off+4] !== 8'(8'h20+v) ||
                doc_values[off+4] !== 8'(expect_fc>>8))
                $fatal(1,"Voice %0d freq high bad",v);
            if (doc_addresses[off+5] !== 8'(8'h40+v) ||
                doc_values[off+5] !== 8'd208)
                $fatal(1,"Voice %0d volume bad",v);
            if (doc_addresses[off+6] !== 8'(8'hA0+v) ||
                doc_values[off+6] !== (v < 3 ? 8'h10 : 8'h00))
                $fatal(1,"Voice %0d RUN/stereo bad",v);
        end
        $display("PASS: 64 waveform writes, 6 voice FC/volume/stereo, 43 DOC commands");
        $finish;
    end

    initial begin
        #2000000;
        $fatal(1,"Timeout boot/first six voices: RAM=%0d DOC=%0d",
               write_count,doc_count);
    end
endmodule
