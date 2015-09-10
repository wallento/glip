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
    parameter WIDTH = 16
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
   localparam FX3_FIFO_IN  = 2'b11;
   localparam FX3_FIFO_OUT = 2'b00;

   assign ctrl_logic_rst = fx3_logic_rst;

   wire int_rst;
   assign int_rst = fx3_com_rst | rst;
   assign com_rst = int_rst;

   wire [WIDTH-1:0]   int_fifo_out_data;
   wire 	      int_fifo_out_valid;
   reg 		      int_fifo_out_ready;
   
   wire [WIDTH-1:0]   int_fifo_in_data;
   reg 		      int_fifo_in_valid;
   wire 	      int_fifo_in_ready;

   wire          fx3_epout_fifo_empty;
   wire          fx3_epin_fifo_almost_full;
   wire          fx3_epin_fifo_full;

   assign fx3_slcs_n = 1'b0;
   
   assign fx3_epout_fifo_empty = !fx3_flagc;
   assign fx3_epin_fifo_full = !fx3_flaga;
   assign fx3_epin_fifo_almost_full = !fx3_flagb;

   wire [15:0]   fx3_dq_in;
   wire [15:0]   fx3_dq_out;
   assign fx3_dq_in = fx3_dq;
   assign fx3_dq = (~fx3_slwr_n ? fx3_dq_out : 16'hz);

   assign fx3_dq_out = int_fifo_out_data;
   assign int_fifo_in_data = fx3_dq_in;

   reg           wr;
   reg           rd;
   reg [1:0]     fifoadr;
   reg           pktend;
   assign fx3_sloe_n = ~rd;
   assign fx3_slwr_n = ~wr;
   assign fx3_slrd_n = ~rd;
   assign fx3_a = fifoadr;
   assign fx3_pktend_n = ~pktend;

   reg [$clog2(FORCE_SEND_TIMEOUT+1)-1:0]  idle_counter;
   reg [$clog2(FORCE_SEND_TIMEOUT+1)-1:0]  nxt_idle_counter;

   reg [1:0]  cycle_counter;
   reg [1:0]  nxt_cycle_counter;

   localparam STATE_IDLE = 0;
   localparam STATE_READ_DELAY = 1;
   localparam STATE_READ = 2;
   localparam STATE_WRITE_DELAY = 3;
   localparam STATE_WRITE = 4;
   localparam STATE_FLUSH = 5;

   reg [2:0] state;
   reg [2:0] nxt_state;

   wire   can_write, can_read, flush;
   assign can_write = !fx3_epin_fifo_full && int_fifo_out_valid;
   assign can_read = !fx3_epout_fifo_empty && int_fifo_in_ready;
   assign flush = (idle_counter == 1);

   assign debug_out[0] = clk;
   assign debug_out[1] = int_fifo_in_valid;
   assign debug_out[2] = int_fifo_in_ready;
   assign debug_out[3] = fifo_in_valid;
   assign debug_out[4] = fifo_in_ready;
   assign debug_out[5] = int_fifo_out_valid;
   assign debug_out[6] = int_fifo_out_ready;
   assign debug_out[7] = pktend;

   always @(posedge fx3_pclk) begin
      if (int_rst) begin
         state <= STATE_IDLE;
         idle_counter <= 0;
	 cycle_counter <= 0;
      end else begin
         state <= nxt_state;
         idle_counter <= nxt_idle_counter;
	 cycle_counter <= nxt_cycle_counter;
      end
   end

   always @(*) begin
      nxt_state = state;
      nxt_cycle_counter = cycle_counter + 1;
      if (idle_counter > 0) begin
	 nxt_idle_counter = idle_counter - 1;
      end else begin
	 nxt_idle_counter = 0;
      end
      
      wr = 0;
      rd = 0;
      pktend = 0;
      fifoadr = 2'bxx;

      int_fifo_in_valid = 0;
      int_fifo_out_ready = 0;

      case (state)
	STATE_IDLE: begin
	   if (can_write) begin
	      fifoadr = FX3_FIFO_OUT;
	      nxt_state = STATE_WRITE;
	      nxt_cycle_counter = 0;
	      nxt_idle_counter = 0;
	   end else if (flush) begin
	      fifoadr = FX3_FIFO_OUT;
	      pktend = 1;
	   end else if (can_read) begin
//	      rd = 1;
	      fifoadr = FX3_FIFO_IN;
	      nxt_state = STATE_READ_DELAY;
	      nxt_cycle_counter = 0;
	   end
	end	
	STATE_READ_DELAY: begin
	   rd = 1;
	   fifoadr = FX3_FIFO_IN;
	   if (cycle_counter == 2) begin
	      nxt_state = STATE_READ;
	   end
	end
	STATE_READ: begin
	   if (can_read) begin
	      fifoadr = FX3_FIFO_IN;
	      int_fifo_in_valid = 1;
	      rd = 1;
	   end else begin
	      nxt_state = STATE_IDLE;
	   end
	end
	STATE_WRITE: begin
	   if (can_write) begin
	      wr = 1;
	      fifoadr = FX3_FIFO_OUT;
	      int_fifo_out_ready = 1;
	   end else begin
	      nxt_idle_counter = FORCE_SEND_TIMEOUT;
	      nxt_state = STATE_IDLE;
	   end
	end
      endcase
   end
   

   // Clock domain crossing logic -> FX3
   wire out_full;
   wire out_empty;
   assign fifo_out_ready = ~out_full;
   assign int_fifo_out_valid = ~out_empty;

   cdc_fifo
      #(.DW(WIDTH),.ADDRSIZE(4))
      out_fifo_cdc(// Logic side (write input)
                   .wr_full(out_full),
                   .wr_clk(clk),
                   .wr_en(fifo_out_valid),
                   .wr_data(fifo_out_data),
                   .wr_rst(~int_rst),

                   // FX3 side (read output)
                   .rd_empty(out_empty),
                   .rd_data(int_fifo_out_data),
                   .rd_clk(fx3_pclk),
                   .rd_rst(~int_rst),
                   .rd_en(int_fifo_out_ready));

   // Clock domain crossing FX3 -> logic
   wire in_full;
   wire in_empty;
   assign int_fifo_in_ready = ~in_full;
   assign fifo_in_valid = ~in_empty;

   cdc_fifo
      #(.DW(WIDTH),.ADDRSIZE(4))
      in_fifo_cdc(// FX3 side (write input)
                  .wr_full(in_full),
                  .wr_clk(fx3_pclk),
                  .wr_en(int_fifo_in_valid),
                  .wr_data(int_fifo_in_data),
                  .wr_rst(~int_rst),

                  // Logic side (read output)
                  .rd_empty(in_empty),
                  .rd_data(fifo_in_data),
                  .rd_clk(clk),
                  .rd_rst(~int_rst),
                  .rd_en(fifo_in_ready));

endmodule

// Local Variables:
// verilog-library-directories:("." "cdc")
// verilog-auto-inst-param-value: t
// End:
