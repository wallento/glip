/* Copyright (c) 2015 by the author(s)
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 *
 * =============================================================================
 *
 * GLIP Toplevel Interface for the Cypress FX3 backend
 *
 * Author(s):
 *   Stefan Wallentowitz <stefan.wallentowitz@tum.de>
 */
module glip_cypressfx3_toplevel
  #(
    parameter WIDTH = 16,
    parameter XILINX_TARGET_DEVICE = "7SERIES"
    )
  (
   // Cypress FX3 ports
   input 	      fx3_pclk,
   inout [WIDTH-1:0]  fx3_dq,
   output 	      fx3_slcs_n,
   output 	      fx3_sloe_n,
   output 	      fx3_slrd_n,
   output 	      fx3_slwr_n,
   output 	      fx3_pktend_n,
   output [1:0]       fx3_a,
   input 	      fx3_flaga,
   input 	      fx3_flagb,
   input 	      fx3_flagc,
   input 	      fx3_flagd,
   input 	      fx3_com_rst,
   input 	      fx3_logic_rst,
//   output [2:0]       fx3_pmode, 

   // Clock/Reset
   input 	      clk,
   input 	      rst,
   output 	      com_rst,

   // GLIP FIFO Interface
   input 	      fifo_out_valid,
   output 	      fifo_out_ready,
   input [WIDTH-1:0]  fifo_out_data,
   output 	      fifo_in_valid,
   input 	      fifo_in_ready,
   output [WIDTH-1:0] fifo_in_data,

   // GLIP Control Interface
   output 	      ctrl_logic_rst,
   
   input [2:0] 	      debug_in,
   output [7:0]       debug_out
   );

   localparam FORCE_SEND_TIMEOUT = 10000;
   localparam FX3_EPOUT  = 2'b11;
   localparam FX3_EPIN = 2'b00;

   assign ctrl_logic_rst = fx3_logic_rst;

   wire int_rst;
   assign int_rst = fx3_com_rst | rst;
   assign com_rst = int_rst;

   // Interface to the FIFOs from USB side
   wire int_fifo_in_full;
   wire int_fifo_in_almost_full;
   wire int_fifo_in_empty;
   reg 	int_fifo_in_valid;
   reg 	int_fifo_out_ready;
   
   wire          fx3_out_empty;
   wire          fx3_in_almost_full;
   wire          fx3_in_full;

   wire [15:0]   fx3_dq_in;
   wire [15:0]   fx3_dq_out;
   assign fx3_dq_in = fx3_dq;
   assign fx3_dq = (~fx3_slwr_n ? fx3_dq_out : 16'hz);
   
   assign fx3_slcs_n = 1'b0;

   reg [WIDTH-1:0] fx3_dq_in_reg;
   reg 		   fx3_flaga_reg;
   reg 		   fx3_flagb_reg;
   reg 		   fx3_flagc_reg;
   reg 		   fx3_flagd_reg;

   always @(posedge fx3_pclk) begin
      fx3_dq_in_reg <= fx3_dq_in;
      fx3_flaga_reg <= fx3_flaga;
      fx3_flagb_reg <= fx3_flagb;
      fx3_flagc_reg <= fx3_flagc;
      fx3_flagd_reg <= fx3_flagd;
   end
   
   assign fx3_out_empty = !fx3_flagc_reg;
   assign fx3_out_almost_empty = !fx3_flagd_reg;
   assign fx3_in_full = !fx3_flaga_reg;
   assign fx3_in_almost_full = !fx3_flagb_reg;

//   assign fx3_pmode = 3'b010;
   
   reg           wr;
   reg 		 oe;
   reg           rd;
   reg [1:0]     fifoadr;
   reg           pktend;
   assign fx3_sloe_n = ~oe;
   assign fx3_slwr_n = ~wr;
   assign fx3_slrd_n = ~rd;
   assign fx3_a = fifoadr;
   assign fx3_pktend_n = ~pktend;

   reg [$clog2(FORCE_SEND_TIMEOUT+1)-1:0]  idle_counter;
   reg [$clog2(FORCE_SEND_TIMEOUT+1)-1:0]  nxt_idle_counter;

   reg [1:0]  cycle_counter;
   reg [1:0]  nxt_cycle_counter;

   localparam STATE_IDLE = 0;
   localparam STATE_WRITE = 1;
   localparam STATE_READ_DELAY = 2;
   localparam STATE_READ = 3;
   localparam STATE_READ_DRAIN = 4;

   reg [2:0] state;
   reg [2:0] nxt_state;

   reg   flush;
   reg 	 nxt_flush;

   always @(posedge fx3_pclk) begin
      if (int_rst) begin
         state <= STATE_IDLE;
         idle_counter <= 0;
	 cycle_counter <= 0;
	 flush <= 1;
      end else begin
         state <= nxt_state;
         idle_counter <= nxt_idle_counter;
	 cycle_counter <= nxt_cycle_counter;
	 flush <= nxt_flush;
      end
   end
   
   assign debug_out[0] = fx3_in_almost_full;
   assign debug_out[1] = int_fifo_out_empty;
   assign debug_out[2] = fx3_out_empty;
   assign debug_out[3] = int_fifo_in_almost_full;
   assign debug_out[4] = fifo_in_valid;
   assign debug_out[5] = state[0];
   assign debug_out[6] = state[1];
   assign debug_out[7] = state[2];
   
   always @(*) begin
      nxt_state = state;
      nxt_cycle_counter = cycle_counter + 1;
      if (idle_counter > 0) begin
	 nxt_idle_counter = idle_counter - 1;
      end else begin
	 nxt_idle_counter = 0;
      end

      if (!flush && (idle_counter == 1)) begin
	 nxt_flush = 1;
      end else begin
	 nxt_flush = flush;
      end
      
      wr = 0;
      rd = 0;
      oe = 0;
      
      pktend = 0;
      fifoadr = 2'bxx;

      int_fifo_in_valid = 0;
      int_fifo_out_ready = 0;

      case (state)
	STATE_IDLE: begin
	   if (!fx3_in_almost_full && !int_fifo_out_empty) begin
	      fifoadr = FX3_EPIN;
	      nxt_state = STATE_WRITE;
	   end else if (flush) begin
	      fifoadr = FX3_EPIN;
	      pktend = 1;
	      nxt_flush = 0;
	   end else if (!fx3_out_empty && !int_fifo_in_almost_full) begin

	      // We can read from FX3 if data is available and we can
	      // receive receive data. We have to use th almost full
	      // signal as we need to be capable of reading 3 words (1
	      // delay of latching, 2 delay of interface, see fig 12)
	      fifoadr = FX3_EPOUT;
	      nxt_state = STATE_READ_DELAY;
	      nxt_cycle_counter = 0;
	      rd = 1;
	      oe = 1;
	   end
	end	
	STATE_READ_DELAY: begin
	   // Wait two cycles before forwarding data to the FIFO
	   rd = 1;
	   oe = 1;
	   fifoadr = FX3_EPOUT;
	   if (cycle_counter == 2) begin
	      nxt_state = STATE_READ;
	   end
	end
	STATE_READ: begin
	   fifoadr = FX3_EPOUT;
	   if (fx3_out_empty) begin
	      // No more data from FX3
	      nxt_state = STATE_IDLE;
	   end else begin
	      int_fifo_in_valid = 1;
	      rd = 1;
	      oe = 1;
	      if (int_fifo_in_almost_full) begin
		 // We need to back-pressure and drain
		 nxt_state = STATE_READ_DRAIN;
		 nxt_cycle_counter = 0;
	      end
	   end
	end
	STATE_READ_DRAIN: begin
	   fifoadr = FX3_EPOUT;
	   if (fx3_out_empty) begin
	      // No more data from FX3
	      nxt_state = STATE_IDLE;
	   end else begin
	      fifoadr = FX3_EPOUT;
	      int_fifo_in_valid = 1;
	      if (cycle_counter == 1) begin
		 nxt_state = STATE_IDLE;
	      end
	   end
	end
	STATE_WRITE: begin
	   if (int_fifo_out_empty) begin
	      nxt_idle_counter = FORCE_SEND_TIMEOUT;
	      nxt_state = STATE_IDLE;
	   end else if (fx3_in_almost_full) begin
	      nxt_idle_counter = FORCE_SEND_TIMEOUT;
	      nxt_state = STATE_IDLE;
	      pktend = 1;
	   end else begin
	      wr = 1;
	      fifoadr = FX3_EPIN;
	      int_fifo_out_ready = 1;
	   end
	end // case: STATE_WRITE
	default: begin
	   nxt_state = state;
	end
      endcase
   end
   
   assign fifo_in_valid = !int_fifo_in_empty;
   
   // Clock domain crossing FX3 -> logic
   FIFO_DUALCLOCK_MACRO
     #(.ALMOST_FULL_OFFSET(9'h006), // Sets almost full threshold
       .ALMOST_EMPTY_OFFSET(9'h006),
       .DATA_WIDTH(WIDTH), // Valid values are 1-72 (37-72 only valid when FIFO_SIZE="36Kb")
       .DEVICE(XILINX_TARGET_DEVICE), // Target device: "VIRTEX5", "VIRTEX6", "7SERIES"
       .FIFO_SIZE("18Kb"), // Target BRAM: "18Kb" or "36Kb"
       .FIRST_WORD_FALL_THROUGH("TRUE") // Sets the FIfor FWFT to "TRUE" or "FALSE"
       )
   in_fifo
     (.ALMOSTEMPTY (),
      .ALMOSTFULL  (int_fifo_in_almost_full),
      .DO          (fifo_in_data),
      .EMPTY       (int_fifo_in_empty),
      .FULL        (int_fifo_in_full),
      .RDCOUNT     (),
      .RDERR       (),
      .WRCOUNT     (),
      .WRERR       (),
      .DI          (fx3_dq_in_reg),
      .RDCLK       (clk),
      .RDEN        (fifo_in_ready & !int_fifo_in_empty),
      .RST         (int_rst),
      .WRCLK       (fx3_pclk),
      .WREN        (int_fifo_in_valid)
      );


   assign fifo_out_ready = !int_fifo_out_full;
   // Clock domain crossing logic -> FX3 
   FIFO_DUALCLOCK_MACRO
     #(.ALMOST_EMPTY_OFFSET(9'h006), // Sets the almost empty threshold
       .ALMOST_FULL_OFFSET(9'h006),
       .DATA_WIDTH(WIDTH), // Valid values are 1-72 (37-72 only valid when FIFO_SIZE="36Kb")
       .DEVICE(XILINX_TARGET_DEVICE), // Target device: "VIRTEX5", "VIRTEX6", "7SERIES"
       .FIFO_SIZE("18Kb"), // Target BRAM: "18Kb" or "36Kb"
       .FIRST_WORD_FALL_THROUGH("TRUE") // Sets the FIfor FWFT to "TRUE" or "FALSE"
       )
   out_fifo
     (.ALMOSTEMPTY (int_fifo_out_almost_empty),
      .ALMOSTFULL  (),
      .DO          (fx3_dq_out),
      .EMPTY       (int_fifo_out_empty),
      .FULL        (int_fifo_out_full),
      .RDCOUNT     (),
      .RDERR       (),
      .WRCOUNT     (),
      .WRERR       (),
      .DI          (fifo_out_data),
      .RDCLK       (fx3_pclk),
      .RDEN        (int_fifo_out_ready & !int_fifo_out_empty),
      .RST         (int_rst),
      .WRCLK       (clk),
      .WREN        (fifo_out_valid)
      );



endmodule

// Local Variables:
// verilog-library-directories:("." "cdc")
// verilog-auto-inst-param-value: t
// End:
