// M6.5b: original algorithmic DOC one-shot FX bank in external sound RAM.
// This logic GENERATES samples during boot. No 20KiB FPGA ROM/BSRAM,
// no copyrighted samples, no extra BL616 firmware and no I/O to the CPU.
//
// Address layout is identical to tools/build_mb_doc_fx_bank.py.
// PCM is offset-binary 8-bit; only final bytes of each patch are $00,
// which is DOC's one-shot HALT marker. Other samples cannot be $00.
//
// This bank is a DIAGNOSTIC sound source, not the finished instrument bank.
// Replace it later with user-supplied WAV samples uploaded to sound SDRAM.
module mb_doc_fx_wavegen (
    input wire [12:0] word_addr_i, // in-bank DOC byte addr >>2, $800-$1BFF
    input wire variant_i,          // 0: bank0, 1: independent bank1 texture
    output wire [31:0] sample_word_o
);
    function automatic [7:0] hash8(input logic [15:0] addr);
        reg [7:0] h;
        begin
            h = addr[7:0] ^ addr[15:8] ^ 8'hA5;
            h = h ^ (h << 3);
            h = h ^ (h >> 5);
            hash8 = h ^ (h << 1);
        end
    endfunction

    function automatic [7:0] one_sample(
        input logic [15:0] a, input logic variant
    );
        logic [2:0] patch;
        logic [12:0] off;
        logic [12:0] lenmask;
        logic [1:0] quarter;
        logic valid_patch;
        integer raw;
        integer scaled;
        integer shift_n;
        logic [7:0] n;
        logic [15:0] texture_addr;
        begin
            patch=3'd0;off=13'd0;lenmask=13'd0;
            quarter=2'd0; valid_patch=1'b1;
            if (a>=16'h2000 && a<16'h4000) begin
                patch=3'd0;off=13'(a-16'h2000);lenmask=13'h1FFF;
                quarter=off[12:11];
            end else if (a>=16'h4000 && a<16'h4400) begin
                patch=3'd1;off=13'(a-16'h4000);lenmask=13'h3FF;
                quarter=off[9:8];
            end else if (a>=16'h4400 && a<16'h4800) begin
                patch=3'd2;off=13'(a-16'h4400);lenmask=13'h3FF;
                quarter=off[9:8];
            end else if (a>=16'h4800 && a<16'h4C00) begin
                patch=3'd3;off=13'(a-16'h4800);lenmask=13'h3FF;
                quarter=off[9:8];
            end else if (a>=16'h4C00 && a<16'h5000) begin
                patch=3'd4;off=13'(a-16'h4C00);lenmask=13'h3FF;
                quarter=off[9:8];
            end else if (a>=16'h5000 && a<16'h5800) begin
                patch=3'd5;off=13'(a-16'h5000);lenmask=13'h7FF;
                quarter=off[10:9];
            end else if (a>=16'h6000 && a<16'h7000) begin
                patch=3'd6;off=13'(a-16'h6000);lenmask=13'hFFF;
                quarter=off[11:10];
            end else valid_patch=1'b0;
            if (!valid_patch)
                one_sample=8'h80;
            else if (off==lenmask)
                one_sample=8'h00; // End marker exactly at patch last byte
            else begin
                // The address layout is identical in both 64KiB banks.
                // Bank1 has independent original diagnostic textures
                // while the DOC's one-shot termination stays identical.
                texture_addr = a ^ (variant ? 16'h35A9 : 16'h0000);
                n=hash8(texture_addr);
                raw=$signed({1'b0,n})-9'sd128;
                // Low-frequency percussion: coarse triangle instead of
                // white noise; other patches vary noise grain and decay.
                if (patch==3'd1 || patch==3'd3) begin
                    if (off[6])
                        raw=(96-integer'(off[6:0]))*3;
                    else
                        raw=(integer'(off[6:0])-32)*3;
                end else if (patch==3'd0) begin
                    raw=((integer'(hash8(texture_addr))+integer'(hash8(texture_addr-16'd1)))>>1)-128;
                end else if (patch==3'd5) begin
                    raw=integer'(hash8({texture_addr[15:7],texture_addr[6:0]^off[10:4]}))-128;
                end else if (patch==3'd4 || patch==3'd6) begin
                    raw=integer'(hash8(texture_addr)^hash8(texture_addr+16'd7))-128;
                end
                shift_n=integer'(quarter)+(patch==3'd0 ? 0 : 1);
                if (patch==3'd6) shift_n=integer'(quarter);
                scaled=128 + (raw >>> shift_n);
                if (scaled<1) one_sample=8'd1;
                else if (scaled>255) one_sample=8'd255;
                else one_sample=8'(scaled);
            end
        end
    endfunction

    wire [15:0] addr_w={1'b0,word_addr_i,2'b00};
    assign sample_word_o={
        one_sample(addr_w+16'd3, variant_i),
        one_sample(addr_w+16'd2, variant_i),
        one_sample(addr_w+16'd1, variant_i),
        one_sample(addr_w, variant_i)
    };
endmodule
