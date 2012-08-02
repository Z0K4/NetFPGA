///////////////////////////////////////////////////////////////////////////////
// vim:set shiftwidth=3 softtabstop=3 expandtab:
// $Id: in_arb_regs.v 5077 2009-02-22 20:17:46Z grg $
//
// Module: out_aggr_regs.v
// Project: NF2.1
// Description: Demultiplexes, stores and serves register requests
//
///////////////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps

  module out_aggr_regs
    #( parameter DATA_WIDTH = 64,
       parameter CTRL_WIDTH = DATA_WIDTH/8,
       parameter UDP_REG_SRC_WIDTH = 2
       )
   
   ( 
      input                                  reg_req_in,
      input                                  reg_ack_in,
      input                                  reg_rd_wr_L_in,
      input  [`UDP_REG_ADDR_WIDTH-1:0]       reg_addr_in,
      input  [`CPCI_NF2_DATA_WIDTH-1:0]      reg_data_in,
      input  [UDP_REG_SRC_WIDTH-1:0]         reg_src_in,

      output reg                             reg_req_out,
      output reg                             reg_ack_out,
      output reg                             reg_rd_wr_L_out,
      output reg [`UDP_REG_ADDR_WIDTH-1:0]   reg_addr_out,
      output reg [`CPCI_NF2_DATA_WIDTH-1:0]  reg_data_out,
      output reg [UDP_REG_SRC_WIDTH-1:0]     reg_src_out,

      input                                  state,
      input                                  out_wr,
      input [CTRL_WIDTH-1:0]                 out_ctrl,
      input [DATA_WIDTH-1:0]                 out_data,
      input                                  out_rdy,
      input                                  eop,

      output reg [1:0]                       outport_sel,

      input                                  clk,
      input                                  reset
     );

   function integer log2;
      input integer number;
      begin
         log2=0;
         while(2**log2<number) begin
            log2=log2+1;
         end
      end
   endfunction // log2

   // ------------- Internal parameters --------------
   localparam NUM_REGS_USED = 9; /* don't forget to update this when adding regs */
   localparam ADDR_WIDTH = log2(NUM_REGS_USED);

   // ------------- Wires/reg ------------------

   wire [ADDR_WIDTH-1:0]                              addr;
   wire [`OUT_AGGR_REG_ADDR_WIDTH - 1:0]                reg_addr;
   wire [`UDP_REG_ADDR_WIDTH-`OUT_AGGR_REG_ADDR_WIDTH - 1:0] tag_addr;

   wire                                               addr_good;
   wire                                               tag_hit;

   reg                                                in_pkt;
   reg                                                second_word;

   reg                                                state_latched;
   reg                                                out_rdy_latched;

   reg [CTRL_WIDTH-1:0]                               last_pkt_ctrl_0;
   reg [DATA_WIDTH-1:0]                               last_pkt_data_0;

   reg [CTRL_WIDTH-1:0]                               last_pkt_ctrl_1;
   reg [DATA_WIDTH-1:0]                               last_pkt_data_1;

   reg [`CPCI_NF2_DATA_WIDTH-1:0]                     eop_cnt;

   reg [`CPCI_NF2_DATA_WIDTH-1:0]                     reg_data;

   wire                                               first_word;


   // -------------- Logic --------------------
   assign addr = reg_addr_in[ADDR_WIDTH-1:0];
   assign reg_addr = reg_addr_in[`OUT_AGGR_REG_ADDR_WIDTH-1:0];
   assign tag_addr = reg_addr_in[`UDP_REG_ADDR_WIDTH - 1:`OUT_AGGR_REG_ADDR_WIDTH];

   assign addr_good = reg_addr[`OUT_AGGR_REG_ADDR_WIDTH-1:ADDR_WIDTH] == 'h0 &&
      addr < NUM_REGS_USED;
   assign tag_hit = tag_addr == `OUT_AGGR_BLOCK_ADDR;

   // Record the various inputs for later output
   always @(posedge clk)
   begin
      // EOP -- resets on read (or write)
      if (reset || (reg_req_in && tag_hit && addr == `OUT_AGGR_NUM_PKTS_SENT))
         eop_cnt <= 'h0;
      else if (eop)
         eop_cnt <= eop_cnt + 'h1;

      if (reset) begin
         state_latched <= 0;
	 out_rdy_latched <= 0;

         last_pkt_ctrl_0 <= 'h0;
         last_pkt_data_0 <= 'h0;

         last_pkt_ctrl_1 <= 'h0;
         last_pkt_data_1 <= 'h0;
      end
      else begin
         state_latched <= state;
	 out_rdy_latched <= out_rdy;

         if (first_word && out_wr) begin
            last_pkt_ctrl_0 <= out_ctrl;
            last_pkt_data_0 <= out_data;
         end
         
         if (second_word && out_wr) begin
            last_pkt_ctrl_1 <= out_ctrl;
            last_pkt_data_1 <= out_data;
         end
      end // else: !if(reset)
   end // always @ (posedge clk)


   // Location tracking
   assign first_word = !in_pkt && !(|out_ctrl);
   always @(posedge clk)
   begin
      if (reset) begin
         in_pkt <= 0;
         second_word <= 0;
      end
      else begin
         if (first_word && out_wr)
            in_pkt <= 1'b1;
         else if (in_pkt && |out_ctrl && out_wr)
            in_pkt <= 1'b0;

         if(first_word && out_wr) begin
            second_word <= 1;
         end
         else if(second_word==1 && out_wr) begin
            second_word <= 0;
         end
      end
   end


   // Select the register data for output
   always @*
   begin
      if (reset) begin
         reg_data = 'h0;
      end
      else begin
         case (addr)
            `OUT_AGGR_NUM_PKTS_SENT:        reg_data = eop_cnt;
            `OUT_AGGR_STATE:                reg_data = {{(`CPCI_NF2_DATA_WIDTH-2){1'b0}}, out_rdy_latched, state_latched};
            `OUT_AGGR_LAST_PKT_WORD_0_LO:   reg_data = last_pkt_data_0[31:0];
            `OUT_AGGR_LAST_PKT_WORD_0_HI:   reg_data = last_pkt_data_0[63:32];
            `OUT_AGGR_LAST_PKT_CTRL_0:      reg_data = last_pkt_ctrl_0;
            `OUT_AGGR_LAST_PKT_WORD_1_LO:   reg_data = last_pkt_data_1[31:0];
            `OUT_AGGR_LAST_PKT_WORD_1_HI:   reg_data = last_pkt_data_1[63:32];
            `OUT_AGGR_LAST_PKT_CTRL_1:      reg_data = last_pkt_ctrl_1;
            `OUT_AGGR_OUTPORT:              reg_data = {{(`CPCI_NF2_DATA_WIDTH-2){1'b0}}, outport_sel};
         endcase // case (reg_cnt)
      end
   end

   // Register I/O
   always @(posedge clk) begin
      // Never modify the address/src
      reg_rd_wr_L_out <= reg_rd_wr_L_in;
      reg_addr_out <= reg_addr_in;
      reg_src_out <= reg_src_in;

      if( reset ) begin
         reg_req_out <= 1'b0;
         reg_ack_out <= 1'b0;
         reg_data_out <= 'h0;

         outport_sel <= 0;

      end
      else begin
         if(reg_req_in && tag_hit) begin
            // data output
            if(addr_good) begin
               reg_data_out <= reg_data;
            end
            else begin
               reg_data_out <= 32'hdead_beef;
            end
            // data input
            if((addr_good) && (addr == `OUT_AGGR_OUTPORT) && (reg_rd_wr_L_in == 0)) begin
               outport_sel <= reg_data_in[1:0];
            end
            // requests complete after one cycle
            reg_ack_out <= 1'b1;
         end
         else begin
            reg_ack_out <= reg_ack_in;
            reg_data_out <= reg_data_in;
         end
         reg_req_out <= reg_req_in;
      end // else: !if( reset )
   end // always @ (posedge clk)

endmodule // out_aggr_regs
