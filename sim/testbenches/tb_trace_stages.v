// tb_trace_stages.v
// Trace computation through each stage to find where outputs diverge

`timescale 1ns/1ps

module tb_trace_stages;

  // --- Clock and stimulus generation ---
  reg clk, rst;
  
  // Memory signals for all 4 banks
  wire [33:0] mem_read_data_0, mem_read_data_1, mem_read_data_2, mem_read_data_3;
  reg  [33:0] mem_write_data_0, mem_write_data_1, mem_write_data_2, mem_write_data_3;
  reg  [5:0]  mem_write_addr_0, mem_write_addr_1, mem_write_addr_2, mem_write_addr_3;
  reg  [5:0]  mem_read_addr_0,  mem_read_addr_1,  mem_read_addr_2,  mem_read_addr_3;
  reg          mem_write_en_0,   mem_write_en_1,   mem_write_en_2,   mem_write_en_3;

  // Status signals
  wire [3:0] state, stage_cnt, sub_stage_cnt, seq_cnt;
  wire [1:0] poly_sel;
  wire done;

  // --- Read input stimuli ---
  reg [16:0] input_a [0:255];
  reg [16:0] input_b [0:255];
  reg [16:0] expected_c [0:255];
  
  integer i;

  // Expected output trace
  reg [16:0] post_ntt1 [0:255];  // After NTT1
  reg [16:0] post_ntt2 [0:255];  // After NTT2
  reg [16:0] post_pwm [0:255];   // After PWM
  reg [16:0] post_intt [0:255];  // After INTT (final)
  
  integer capture_state = 0;

  // --- Instantiate DUT ---
  ntt_top uut (
    .clk(clk), .rst(rst),
    .mem_read_data_0(mem_read_data_0),
    .mem_read_data_1(mem_read_data_1),
    .mem_read_data_2(mem_read_data_2),
    .mem_read_data_3(mem_read_data_3),
    .mem_write_data_0(mem_write_data_0),
    .mem_write_data_1(mem_write_data_1),
    .mem_write_data_2(mem_write_data_2),
    .mem_write_data_3(mem_write_data_3),
    .mem_write_addr_0(mem_write_addr_0),
    .mem_write_addr_1(mem_write_addr_1),
    .mem_write_addr_2(mem_write_addr_2),
    .mem_write_addr_3(mem_write_addr_3),
    .mem_read_addr_0(mem_read_addr_0),
    .mem_read_addr_1(mem_read_addr_1),
    .mem_read_addr_2(mem_read_addr_2),
    .mem_read_addr_3(mem_read_addr_3),
    .mem_write_en_0(mem_write_en_0),
    .mem_write_en_1(mem_write_en_1),
    .mem_write_en_2(mem_write_en_2),
    .mem_write_en_3(mem_write_en_3),
    .done(done)
  );

  // --- Memory banks ---
  mem_bank bank0 (.clk(clk), .read_addr(mem_read_addr_0), .read_data(mem_read_data_0),
                  .write_addr(mem_write_addr_0), .write_data(mem_write_data_0), .write_en(mem_write_en_0));
  mem_bank bank1 (.clk(clk), .read_addr(mem_read_addr_1), .read_data(mem_read_data_1),
                  .write_addr(mem_write_addr_1), .write_data(mem_write_data_1), .write_en(mem_write_en_1));
  mem_bank bank2 (.clk(clk), .read_addr(mem_read_addr_2), .read_data(mem_read_data_2),
                  .write_addr(mem_write_addr_2), .write_data(mem_write_data_2), .write_en(mem_write_en_2));
  mem_bank bank3 (.clk(clk), .read_addr(mem_read_addr_3), .read_data(mem_read_data_3),
                  .write_addr(mem_write_addr_3), .write_data(mem_write_data_3), .write_en(mem_write_en_3));

  // --- Probe internal signals ---
  assign state = uut.ctrl.state;
  assign stage_cnt = uut.ctrl.stage_cnt;
  assign sub_stage_cnt = uut.ctrl.sub_stage_cnt;
  assign seq_cnt = uut.ctrl.seq_cnt;
  assign poly_sel = uut.ctrl.poly_sel;

  // --- Monitor computation stages ---
  task capture_memory_state(integer snapshot_state);
    integer j;
    begin
      // Read all 64 addresses from all 4 banks
      for(j=0; j<64; j=j+1) begin
        // This is simplified - in real sim you'd need proper read cycle timing
        case(snapshot_state)
          3: begin  // After NTT1
            // post_ntt1[4*j] = ...
            // post_ntt1[4*j+1] = ...
            // etc.
          end
          4: begin  // After NTT2
            // Similar capture
          end
          5: begin  // After PWM
            // Similar capture
          end
          6: begin  // After INTT (done)
            // Similar capture
          end
        endcase
      end
    end
  endtask

  // --- Generate Clock ---
  always #5 clk = ~clk;

  // --- Main test ---
  initial begin
    clk = 0;
    rst = 1;
    
    // Load test vectors
    $readmemh("input_a.hex", input_a);
    $readmemh("input_b.hex", input_b);
    $readmemh("expected_out.hex", expected_c);

    #20 rst = 0;

    // Load poly A and B
    for(i=0; i<256; i=i+1) begin
      wait(state == 0);  // LOAD state
      mem_write_data_0 = input_a[i];
      mem_write_en_0 = 1;
      mem_write_addr_0 = i[5:0];
      #10;
    end
    mem_write_en_0 = 0;

    // Wait for computation to complete
    wait(done == 1);
    
    // Capture output
    #100;
    $display("STAGE TRACE COMPLETE");
    $finish;
  end

  // Monitor state transitions
  always @(posedge clk) begin
    if(state != capture_state) begin
      case(state)
        0: $display("LOAD state");
        1: $display("NTT1 state, stage_cnt=%d", stage_cnt);
        2: $display("NTT2 state, stage_cnt=%d", stage_cnt);
        3: $display("PWM state");
        4: $display("INTT state, stage_cnt=%d", stage_cnt);
        5: $display("OUTPUT state");
        6: $display("IDLE/DONE state");
      endcase
      capture_state = state;
    end
  end

endmodule
