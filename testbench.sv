module testbench;
    logic clk, reset;
    logic [31:0] WriteData, DataAdr;
    logic        MemWrite;
    logic [9:0]  LEDR, SW;
    logic [31:0] HEX3HEX0;
    logic [15:0] HEX5HEX4;
    logic [1:0]  KEY;
  
  // DUT
    top dut(clk, WriteData, DataAdr, MemWrite, LEDR, HEX3HEX0, HEX5HEX4, SW, KEY);

    // clock
    initial clk = 0;
    always #5 clk = ~clk;

    // old reset behaviour
    initial begin
        reset = 1;
        #20 reset = 0;
        // any other old stimulus
    end

    // map old reset to new KEY[0] (active low)
    assign KEY[0] = ~reset;
    assign KEY[1] = 1'b1;
    initial SW = '0;

    // check results
  always @(negedge clk)
    begin
      if(MemWrite) begin
        if(DataAdr === 100 & WriteData === 25) begin
          $display("Simulation succeeded");
          $stop;
        end else if (DataAdr !== 96) begin
          $display("Simulation failed");
          $stop;
        end
      end
    end
endmodule