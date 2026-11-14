`timescale 1ns/1ps
module tb_audio_strobe_watch;
    reg clk=0, reset_n=0, tick=0, clear=0;
    wire stalled, beat;
    always #5 clk=~clk;
    mb_audio_strobe_watch #(
        .TIMEOUT_CYCLES(16),
        .HEARTBEAT_SAMPLES(4)
    ) dut (
        .clk_pixel_i(clk),.reset_n_i(reset_n),.sample_tick_i(tick),
        .clear_i(clear),.stalled_o(stalled),.heartbeat_o(beat)
    );
    task automatic pulse;
        begin
            @(negedge clk); tick=1;
            @(negedge clk); tick=0;
            repeat(3) @(negedge clk);
        end
    endtask
    initial begin
        repeat(2) @(negedge clk);
        reset_n=1;
        repeat(4) pulse();
        #1;
        if (stalled!==0 || beat!==1)
            $fatal(1,"Heartbeat missing on 4 sample ticks");
        repeat(20) @(negedge clk);
        #1;
        if (stalled!==1) $fatal(1,"2ms equivalent watchdog did not latch");
        pulse();
        if (stalled!==1) $fatal(1,"Fault should remain sticky");
        clear=1;
        @(negedge clk);
        #1;
        if (stalled!==0) $fatal(1,"S2 clear did not reset sticky flag");
        clear=0;
        $display("PASS: sample heartbeat, missing-clock watchdog, sticky clear");
        $finish;
    end
    initial begin
        #20000; $fatal(1,"watchdog simulation timeout");
    end
endmodule
