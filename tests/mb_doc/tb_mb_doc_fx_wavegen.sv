`timescale 1ns/1ps
module tb_mb_doc_fx_wavegen;
    logic [12:0] word_addr;
    wire [31:0] word_data;
    mb_doc_fx_wavegen dut (.word_addr_i(word_addr),.variant_i(1'b0),.sample_word_o(word_data));
    integer start[0:6],length[0:6];
    logic [7:0] sample_byte;
    integer addr,patch,j,word_count,halters;
    initial begin
        start[0]='h2000;length[0]=8192;
        start[1]='h4000;length[1]=1024;
        start[2]='h4400;length[2]=1024;
        start[3]='h4800;length[3]=1024;
        start[4]='h4C00;length[4]=1024;
        start[5]='h5000;length[5]=2048;
        start[6]='h6000;length[6]=4096;
        halters=0;word_count=0;
        for(addr='h2000;addr<'h7000;addr+=4) begin
            word_addr=13'(addr>>2);
            #1;
            for(j=0;j<4;j++) begin
                sample_byte = (word_data >> (j*8)) & 8'hFF;
                for(patch=0;patch<7;patch++) begin
                    if(addr+j>=start[patch] &&
                       addr+j<start[patch]+length[patch]) begin
                        if(addr+j==start[patch]+length[patch]-1) begin
                            if(sample_byte!==8'h00)
                                $fatal(1,"Missing DOC HALT patch=%0d at $%04h",patch,addr+j);
                            halters++;
                        end else if(sample_byte===8'h00)
                            $fatal(1,"Premature DOC HALT at $%04h",addr+j);
                    end
                end
                if(addr+j>=16'h5800 && addr+j<16'h6000 &&
                   sample_byte!==8'h80)
                    $fatal(1,"FX bank gap has non-silent PCM at $%04h",addr+j);
            end
            word_count++;
        end
        if(word_count!==5120 || halters!==7)
            $fatal(1,"Expected 5120 words and 7 terminal markers");
        $display("PASS: 20KiB algorithmic FX bank, 5120 words, no early stop bytes");
        $display("PASS: 7 exact DOC HALT markers; reserved bank gap is silence");
        $finish;
    end
endmodule
