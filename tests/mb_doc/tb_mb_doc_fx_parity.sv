`timescale 1ns/1ps
// M6.6b end-to-end register-to-mute test. The upstream AY PCM still
// comes from the unmodified YM2149 cores; this bench verifies that the
// DOC bridge never doubles a native FX channel with its piano voice.
module tb_mb_doc_fx_parity;
  logic clk=0,reset_n=0,sdram_ready=0;
  always #5 clk=~clk;
  logic l_wr=0,r_wr=0,l_reset_n=1,r_reset_n=1;
  logic [3:0] l_reg=0,r_reg=0;
  logic [7:0] l_data=0,r_data=0;
  wire doc_wr,ram_wr,ready,old_fx_l,old_fx_r,bank1_ready;
  wire [2:0] native_l,native_r,voice;
  wire [7:0] doc_addr,doc_data;
  wire [20:0] ram_addr;
  wire [31:0] ram_data;
  wire [3:0] ram_be;
  logic ram_ready=0;
  mb_doc_bridge #(
    .HOST_SPACING_CYCLES(16),
    .SCAN_PAUSE_CYCLES(64),
    .DECLICK_ENABLE(1'b1),
    .COHERENT_PUBLISH_ENABLE(1'b0),
    .FX_AY_BYPASS_ENABLE(1'b0),
    .SAMPLED_FX_ENABLE(1'b0),
    .AY_FX_CHANNEL_COMPAT_ENABLE(1'b1),
    .AY_FX_FORCE_NATIVE_ALL(1'b0),
    .FX_GLIDE_HOLD_CYCLES(160)
  ) dut (
    .clk_i(clk),.reset_n_i(reset_n),.sdram_ready_i(sdram_ready),
    .ay_l_wr_i(l_wr),.ay_l_reg_i(l_reg),.ay_l_data_i(l_data),
    .ay_r_wr_i(r_wr),.ay_r_reg_i(r_reg),.ay_r_data_i(r_data),
    .ay_l_env_level_i(5'd31),.ay_r_env_level_i(5'd31),
    .ay_l_reset_n_i(l_reset_n),.ay_r_reset_n_i(r_reset_n),
    .doc_wr_o(doc_wr),.doc_addr_o(doc_addr),.doc_data_o(doc_data),
    .ram_wr_o(ram_wr),.ram_addr_o(ram_addr),.ram_data_o(ram_data),
    .ram_byte_en_o(ram_be),.ram_ready_i(ram_ready),
    .ready_o(ready),.mb_bank1_ready_o(bank1_ready),
    .active_voice_o(voice),.fx_ay_l_o(old_fx_l),.fx_ay_r_o(old_fx_r),
    .fx_native_l_mask_o(native_l),.fx_native_r_mask_o(native_r)
  );
  integer writes=0,delay=0;
  logic ram_busy=0,prev_wr=0;
  always @(posedge clk) begin
    ram_ready<=0;
    if(!reset_n) begin
      ram_busy<=0;prev_wr<=0;writes<=0;delay<=0;
    end else begin
      prev_wr<=ram_wr;
      if(ram_wr&&!prev_wr) begin
        if(ram_busy || ram_addr !== writes || ram_be!==4'hF)
          $fatal(1,"Unexpected piano sample address");
        writes<=writes+1;
        ram_busy<=1;delay<=2;
      end
      if(ram_busy) begin
        if(delay==0) begin ram_ready<=1;ram_busy<=0;end
        else delay<=delay-1;
      end
    end
  end
  integer fx6=0,fx7=0;
  integer doc0_lastvol=0,doc4_lastvol=0;
  always @(posedge clk) if(reset_n && doc_wr) begin
    if(doc_addr==8'h40) doc0_lastvol=int'(doc_data);
    if(doc_addr==8'h44) doc4_lastvol=int'(doc_data);
    if(doc_addr==8'hA6 || doc_addr==8'hA7)
      $fatal(1,"Native FX path emitted forbidden sampled DOC6/7 one-shot");
    if(old_fx_l || old_fx_r)
      $fatal(1,"Whole-chip native AY bypass unexpectedly re-enabled");
  end
  task automatic ay_write(input bit side,input logic [3:0] r,input logic [7:0] d);
    @(negedge clk);
    if(side) begin r_reg=r;r_data=d;r_wr=1;end
    else begin l_reg=r;l_data=d;l_wr=1;end
    @(negedge clk);l_wr=0;r_wr=0;
  endtask
  task automatic wait_doc0_vol(input bit nonzero);
    integer i;
    begin
      i=0;
      while((nonzero ? (doc0_lastvol==0):(doc0_lastvol!=0)) && i<100000) begin
        @(negedge clk);i++;
      end
      if(i>=100000)
        $fatal(1,"DOC0 piano volume did not change as expected, wanted_nonzero=%0d volume=%0d",nonzero,doc0_lastvol);
    end
  endtask
  initial begin
    repeat(4) @(negedge clk);
    reset_n=1;sdram_ready=1;
    wait(ready);
    if(writes!==1408 || bank1_ready!==0)
      $fatal(1,"Compatibility-mode original piano preload changed");
    // Left piano A and right piano B both sound normally.
    ay_write(0,4'd0,8'h90);
    ay_write(0,4'd1,8'h00);
    ay_write(0,4'd7,8'h3E);
    ay_write(0,4'd8,8'h0F);
    ay_write(1,4'd2,8'h90);
    ay_write(1,4'd3,8'h00);
    ay_write(1,4'd7,8'h3D);
    ay_write(1,4'd9,8'h0F);
    wait_doc0_vol(1);
    if(native_l !== 0 || native_r !== 0)
      $fatal(1,"Tone-only piano routed to YM");

    // Same AY channel becomes mixed tone+noise: only left A reroutes.
    ay_write(0,4'd7,8'h36);
    #1;
    if(native_l!==3'b001 || native_r!==3'b000)
      $fatal(1,"Noise-enabled A not independently native");
    wait_doc0_vol(0);
    // Right B remained a live piano voice, despite left-side FX.
    if(native_r!==3'b000 || !dut.selected_reset_n_w)
      $fatal(1,"Right piano affected by left noise");

    // Disable left noise; piano A must return and attack again.
    ay_write(0,4'd7,8'h3E);
    #1;
    if(native_l!==3'b000)
      $fatal(1,"Native routing did not disengage after noise stopped");
    wait_doc0_vol(1);

    // Three simultaneous left envelope channels use native YM, while
    // right piano remains enabled; per-chip routing remains independent.
    ay_write(0,4'd7,8'h38);
    ay_write(0,4'd8,8'h10);
    ay_write(0,4'd9,8'h10);
    ay_write(0,4'd10,8'h10);
    #1;
    if(native_l!==3'b111 || native_r!==3'b000)
      $fatal(1,"Triple envelope FX did not preserve channel masks");

    // A fresh left noise pattern must not leave stale right FX state.
    ay_write(0,4'd7,8'h3E);
    ay_write(0,4'd8,8'h0F);
    ay_write(0,4'd9,8'h00);
    ay_write(0,4'd10,8'h00);
    ay_write(1,4'd7,8'h2D);
    #1;
    if(native_l!==3'b000 || native_r!==3'b010)
      $fatal(1,"Per-chip noise mask leaked to other side");

    // Reset left AY while right FX active. Do not stop right sound.
    l_reset_n=0;
    repeat(4) @(negedge clk);
    if(native_l!==3'b000 || native_r!==3'b010)
      $fatal(1,"Left reset affected right native noise");
    l_reset_n=1;
    $display("PASS: piano A->AY noise->piano transition with quiet DOC release");
    $display("PASS: triple-envelope FX, isolated stereo and no sampled one-shot hijack");
    $finish;
  end
  initial begin
    #30000000;
    $fatal(1,"M6.6b channel router timed out, piano RAM=%0d DOC0 volume=%0d",writes,doc0_lastvol);
  end
endmodule
