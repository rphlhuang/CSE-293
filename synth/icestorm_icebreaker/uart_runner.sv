module uart_runner;

  reg  CLK;
  reg  BTN_N = 0;
  wire LEDG_N;
  reg RX, TX;
  reg clk_i = CLK;

  wire led = !LEDG_N;

  initial begin
    CLK = 0;
    forever begin
      #41.666ns;  // 12MHz
      CLK = !CLK;
    end
  end

  logic pll_out;
  initial begin
    pll_out = 0;
    forever begin
      #24.661ns;  // 20.2752 Mhz --> 49.321 ns / 2 = 24.6605ns
      pll_out = !pll_out;
    end
  end
  assign icebreaker.pll.PLLOUTGLOBAL = pll_out;

  icebreaker icebreaker (
    .CLK(CLK),
    .BTN_N(BTN_N),
    .LEDG_N(LEDG_N),
    .RX(RX),
    .TX(TX)
  );

  wire [15:0] prescale_w;
  logic [7:0] tx_stim_i;
  logic [0:0] tx_valid_i, tx_ready_o;
  /* verilator lint_off WIDTHTRUNC */
  localparam BAUD_RATE = 115200;
  localparam CLK_FREQ_HZ = 20275200; // 20.2752 --> 20275200
  assign prescale_w = (CLK_FREQ_HZ) / (BAUD_RATE * 8);
  /* verilator lint_on WIDTHTRUNC */

  uart_tx #(.DATA_WIDTH(8)) model_tx_inst (
    .clk(pll_out),
    .rst(BTN_N),
    // AXI Stream Interface (parallel to serial, what we want to send to PC)
    .s_axis_tdata(tx_stim_i), // input, [DATA_WIDTH-1:0]
    .s_axis_tvalid(tx_valid_i), // input
    .s_axis_tready(tx_ready_o), // output

    // UART Interface (what the FPGA is sending, serially)
    .txd(RX), // input

    // Status
    .busy(), // output
    .prescale(prescale_w) // input, [15:0]
  );

  // output decoder: rx instance
  wire [7:0] rx_data_o;
  wire rx_valid_o;
  uart_rx #(.DATA_WIDTH(8)) rx_inst (
    .clk(pll_out),
    .rst(BTN_N),

    // AXI Stream Interface (serial to parallel, what we work with on FPGA)
    .m_axis_tdata(rx_data_o), // output, [DATA_WIDTH-1:0]
    .m_axis_tvalid(rx_valid_o), // output
    .m_axis_tready(1'b1), // input

    // UART Interface (what the FPGA is recieving, serially)
    .rxd(TX), // input

    // Status
    .busy(), // output
    .overrun_error(), // output
    .frame_error(), // output

    .prescale(prescale_w) // input, [15:0]
  );

  task automatic reset;
    @(negedge pll_out);
    tx_valid_i = 1'b0;
    tx_stim_i = '0;
    BTN_N = 1;
    @(negedge pll_out);
    BTN_N = 0;
  endtask

  task automatic wait_cycles(input int cycles);
    repeat(cycles) begin
      @(negedge pll_out);
    end
  endtask

  task automatic send_byte(input logic [7:0] data);
    wait (tx_ready_o == 1'b1);
    @(negedge pll_out);
    tx_valid_i = 1'b1;
    tx_stim_i = data;
    wait_cycles(2);
    tx_valid_i = 1'b0;
  endtask

  task automatic send_packet(
    input logic [7:0] opcode,
    input logic [31:0] data [],
    input logic [15:0] length
  );
    // header
    send_byte(opcode);
    send_byte(8'h00);
    send_byte(length[7:0]);
    send_byte(length[15:8]);

    // data
    for (int i = 0; i < data.size(); i++) begin
      send_byte(data[i][31:24]);
      send_byte(data[i][23:16]);
      send_byte(data[i][15:8]);
      send_byte(data[i][7:0]);
    end
  endtask

  task automatic wait_for_response(output logic [31:0] response);
    logic [7:0] b0, b1, b2, b3;

    $display("Waiting for rx_o...");
    // big-endian: read MSB first
    @(posedge rx_valid_o);
    b3 = rx_data_o;
    @(posedge rx_valid_o);
    b2 = rx_data_o;
    @(posedge rx_valid_o);
    b1 = rx_data_o;
    @(posedge rx_valid_o);
    b0 = rx_data_o;

    response = {b3, b2, b1, b0};
  endtask

endmodule
