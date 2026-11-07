`timescale 1ns/1ps
module tb_ssi263_native;
    reg clk=0; always #5 clk=~clk;
    reg reset_n=0, powered=0, start=0;
    reg [5:0] phoneme=0;
    reg [3:0] amplitude=15;
    reg [7:0] inflection=128, rate=8'h80;
    wire signed [15:0] pcm;
    wire [28:0] params;
    ssi263_native_rom rom(.phoneme_i(phoneme),.params_o(params));
    ssi263_native_voice #(.CLK_HZ(160000),.SAMPLE_HZ(16000)) dut(
       .clk_i(clk),.reset_n_i(reset_n),.powered_i(powered),
       .phoneme_start_i(start),.phoneme_i(phoneme),
       .amplitude_i(amplitude),.inflection_i(inflection),
       .rate_i(rate),.pcm_o(pcm));
    integer i;
    reg [28:0] old_params;
    reg nonzero;
    initial begin
       #20; reset_n=1;
       for(i=0;i<64;i=i+1) begin
           phoneme=i; #2;
           if (^params === 1'bx) $fatal(1,"ROM X at %0d",i);
           if(i==0 && (params[23:20]!=0 || params[19:16]!=0))
               $fatal(1,"PA should have zero FA and VA");
           if(i==55 && params[11:8]!=3) $fatal(1,"M nasal=3");
           if(i==56 && params[11:8]!=3) $fatal(1,"N nasal=3");
           if(i==57 && params[11:8]!=3) $fatal(1,"NG nasal=3");
       end
       powered=1;phoneme=0;repeat(20) @(posedge clk);
       if (pcm !== 0) $fatal(1,"Pause should be silent");
       phoneme=6'h01;start=1;@(negedge clk);start=0;
       nonzero=0;
       for(i=0;i<100;i=i+1)begin @(negedge clk);if(pcm!=0)nonzero=1;end
       if(!nonzero)$fatal(1,"Voiced diagnostic sample remained silent");
       powered=0;repeat(4) @(negedge clk);
       if(pcm!==0)$fatal(1,"Powered down sample not zero");
       $display("PASS native ROM / diagnostic PCM");
       $finish;
    end
endmodule
