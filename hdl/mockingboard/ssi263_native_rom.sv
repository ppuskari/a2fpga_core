// SSI-263 64 x 29-bit silicon ROM, decoded by Rob Elmer (Casso, MIT).
// Bits [28:24] = closure, class1, class2, not_fricative, not_voiced
// [23:20] FA, [19:16] VA, [15:12] F3, [11:8] NAS, [7:4] F2, [3:0] F1.
// Provenance: Casso specs/024-mockingboard-speech/rom-extraction/rom-decoded-params.csv
// Parameter-to-analog-filter transfer functions are still research models.
module ssi263_native_rom (
    input wire [5:0] phoneme_i,
    output reg [28:0] params_o
);
    always @* begin
        case (phoneme_i)
            6'h00: params_o = 29'h1400c097; // PA
            6'h01: params_o = 29'h1e0ce0e2; // E
            6'h02: params_o = 29'h1e0ad0e5; // E1
            6'h03: params_o = 29'h1e0be0d1; // Y
            6'h04: params_o = 29'h1e06b0c2; // YI
            6'h05: params_o = 29'h1e0ce0e3; // AY
            6'h06: params_o = 29'h1e09f0f1; // IE
            6'h07: params_o = 29'h1e08c0a5; // I
            6'h08: params_o = 29'h1e08b0b6; // A
            6'h09: params_o = 29'h1e08a096; // AI
            6'h0a: params_o = 29'h1e08b089; // EH
            6'h0b: params_o = 29'h1e08b09a; // EH1
            6'h0c: params_o = 29'h1e06b09d; // AE
            6'h0d: params_o = 29'h1e06b07f; // AE1
            6'h0e: params_o = 29'h1e06b03f; // AH
            6'h0f: params_o = 29'h1e07b04f; // AH1
            6'h10: params_o = 29'h1e06a02d; // AW
            6'h11: params_o = 29'h1e08b017; // O
            6'h12: params_o = 29'h1e09b015; // OU
            6'h13: params_o = 29'h1e08a028; // OO
            6'h14: params_o = 29'h1e0aa063; // IU
            6'h15: params_o = 29'h1e09a044; // IU1
            6'h16: params_o = 29'h1e0a8013; // U
            6'h17: params_o = 29'h1e0a7001; // U1
            6'h18: params_o = 29'h1e0ab048; // UH
            6'h19: params_o = 29'h1e08b03a; // UH1
            6'h1a: params_o = 29'h1e06b03c; // UH2
            6'h1b: params_o = 29'h1e07b05c; // UH3
            6'h1c: params_o = 29'h1e083046; // ER
            6'h1d: params_o = 29'h1e081013; // R
            6'h1e: params_o = 29'h1e084032; // R1
            6'h1f: params_o = 29'h1e069067; // R2
            6'h20: params_o = 29'h1e07e033; // L
            6'h21: params_o = 29'h1e08f051; // L1
            6'h22: params_o = 29'h1e09e015; // LF
            6'h23: params_o = 29'h1e089003; // W
            6'h24: params_o = 29'h0e08c031; // B
            6'h25: params_o = 29'h0e08e091; // D
            6'h26: params_o = 29'h1e0a80a3; // KV
            6'h27: params_o = 29'h0df08024; // P
            6'h28: params_o = 29'h09f0e094; // T
            6'h29: params_o = 29'h0d4080a3; // K
            6'h2a: params_o = 29'h1606c097; // HV
            6'h2b: params_o = 29'h060fc097; // HVC
            6'h2c: params_o = 29'h1580c097; // HF
            6'h2d: params_o = 29'h0580c097; // HFC
            6'h2e: params_o = 29'h1604c397; // HN
            6'h2f: params_o = 29'h18a1d023; // Z
            6'h30: params_o = 29'h19f0c070; // S
            6'h31: params_o = 29'h1ca1e0b2; // J
            6'h32: params_o = 29'h1d60e0b2; // SCH
            6'h33: params_o = 29'h1c439032; // V
            6'h34: params_o = 29'h1d409032; // F
            6'h35: params_o = 29'h1821e073; // THV
            6'h36: params_o = 29'h1920a085; // TH
            6'h37: params_o = 29'h1e0a9330; // M
            6'h38: params_o = 29'h1e08d380; // N
            6'h39: params_o = 29'h1e04e3c2; // NG
            6'h3a: params_o = 29'h1e08a097; // :A
            6'h3b: params_o = 29'h1e069082; // :OH
            6'h3c: params_o = 29'h1e0a9071; // :U
            6'h3d: params_o = 29'h1e0aa090; // :UH
            6'h3e: params_o = 29'h1e07a076; // E2
            6'h3f: params_o = 29'h1e08e011; // LB
            default: params_o = 29'd0;
        endcase
    end
endmodule
