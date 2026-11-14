`timescale 1ns/1ps
module tb_audio_simple_tick;
    reg clk=0, reset=1;
    wire tick;
    always #5 clk=~clk;
    // Same ratio/phase stepping mechanism scaled for fast simulation.
    mb_audio_simple_tick #(.CLK_RATE(2700),.AUDIO_RATE(441)) dut (
        .clk_i(clk),.reset_i(reset),.audio_tick_o(tick)
    );
    integer i, count=0, last=-1, delta;
    initial begin
        repeat(3) @(negedge clk);
        reset=0;
        for(i=1;i<=27000;i=i+1) begin
            @(posedge clk);
            #1;
            if(tick) begin
                count=count+1;
                if(last>=0) begin
                    delta=i-last;
                    if(delta!=6 && delta!=7)
                        $fatal(1,"Invalid strobe interval: %0d cycles",delta);
                end
                last=i;
            end
        end
        if(count!=4410) $fatal(1,"Expected 4410 sample pulses, got %0d",count);
        $display("PASS: exact average audio tick rate, 6/7-cycle bounded jitter");
        $display("PASS: no missing or duplicated sample ticks");
        $finish;
    end
    initial begin #500000; $fatal(1,"sample tick timeout"); end
endmodule
