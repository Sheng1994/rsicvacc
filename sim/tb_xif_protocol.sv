`default_nettype none
module tb_xif_protocol;
  logic clk_i=0, rst_ni=0;
  logic [63:0] nn_instruction_count, nn_dotp4_count, nn_requant_count;
  logic [63:0] nn_array_mac_count;
  logic trace_valid, trace_kill;
  logic [3:0] trace_id; logic [2:0] trace_operation; logic [31:0] trace_result;
  cv32e40x_if_xif #(.X_NUM_RS(2),.X_ID_WIDTH(4),.X_MEM_WIDTH(32),.X_RFR_WIDTH(32),.X_RFW_WIDTH(32)) xif();
  xif_nn_coprocessor dut(
    .clk_i,.rst_ni,.nn_instruction_count_o(nn_instruction_count),
    .nn_dotp4_count_o(nn_dotp4_count),.nn_requant_count_o(nn_requant_count),
    .nn_array_mac_count_o(nn_array_mac_count),
    .trace_valid_o(trace_valid),.trace_id_o(trace_id),.trace_operation_o(trace_operation),
    .trace_kill_o(trace_kill),.trace_result_o(trace_result),
    .xif_compressed_if(xif),.xif_issue_if(xif),.xif_commit_if(xif),
    .xif_mem_if(xif),.xif_mem_result_if(xif),.xif_result_if(xif));
  always #5 clk_i=~clk_i;

  function automatic logic [31:0] insn(input logic [2:0] op,input logic [4:0] rd,input logic [6:0] funct7);
    insn={funct7,5'd2,5'd1,op,rd,7'b0001011};
  endfunction
  function automatic logic [31:0] dot4(input logic [31:0] a,input logic [31:0] b);
    integer signed total;
    integer signed av,bv;
    begin total=0;
      for(int i=0;i<4;i++) begin
        av=$signed(a[i*8 +: 8]); bv=$signed(b[i*8 +: 8]); total+=av*bv;
      end
      dot4=total;
    end
  endfunction

  task automatic reset_dut;
    begin
      rst_ni=0; xif.issue_valid=0; xif.commit_valid=0; xif.result_ready=0;
      xif.compressed_valid=0; xif.mem_ready=0; xif.mem_result_valid=0;
      xif.issue_req='0; xif.commit='0; xif.compressed_req='0; xif.mem_resp='0; xif.mem_result='0;
      repeat(3) @(posedge clk_i); rst_ni=1; @(posedge clk_i); #1;
      if(xif.result_valid) $fatal(1,"FAIL: spurious result after reset");
      if(nn_instruction_count||nn_dotp4_count||nn_requant_count||nn_array_mac_count) $fatal(1,"FAIL: counters nonzero after reset");
    end
  endtask
  task automatic issue(input logic[3:0] id,input logic[2:0] op,input logic[31:0] a,input logic[31:0] b,input logic[4:0] rd);
    begin
      xif.issue_req='0; xif.issue_req.id=id; xif.issue_req.instr=insn(op,rd,0);
      xif.issue_req.rs[0]=a; xif.issue_req.rs[1]=b; xif.issue_req.rs_valid=2'b11;
      xif.issue_valid=1; #1;
      if(!xif.issue_ready||!xif.issue_resp.accept) $fatal(1,"FAIL: legal issue rejected id=%0d op=%0d",id,op);
      @(posedge clk_i); #1; xif.issue_valid=0;
      if(xif.issue_ready) $fatal(1,"FAIL: issue_ready did not backpressure occupied entry");
    end
  endtask
  task automatic commit(input logic[3:0] id,input logic kill);
    begin
      xif.commit.id=id; xif.commit.commit_kill=kill; xif.commit_valid=1;
      @(posedge clk_i); #1; xif.commit_valid=0;
    end
  endtask
  task automatic consume(input logic[3:0] id,input logic[31:0] expected,input logic expected_we);
    logic[31:0] held; begin
      if(!xif.result_valid) $fatal(1,"FAIL: missing result id=%0d",id);
      held=xif.result.data;
      repeat(7) begin
        if(!xif.result_valid||xif.result.data!==held||xif.result.id!==id)
          $fatal(1,"FAIL: result changed under backpressure");
        @(posedge clk_i); #1;
      end
      if(xif.result.data!==expected||xif.result.we!==expected_we)
        $fatal(1,"FAIL: result id=%0d got=%08x we=%0b expected=%08x we=%0b",id,xif.result.data,xif.result.we,expected,expected_we);
      xif.result_ready=1; @(posedge clk_i); #1; xif.result_ready=0;
      if(xif.result_valid) $fatal(1,"FAIL: result_valid remained after handshake");
    end
  endtask

  initial begin
    logic[31:0] a,b,exp;
    reset_dut();

    // Unknown funct7 and opcode must be rejected without occupying the entry.
    xif.issue_req='0; xif.issue_req.instr=insn(0,3,7'h3); xif.issue_valid=1; #1;
    if(xif.issue_resp.accept) $fatal(1,"FAIL: nonzero funct7 accepted");
    @(posedge clk_i); #1; xif.issue_valid=0;
    if(!xif.issue_ready||xif.result_valid) $fatal(1,"FAIL: rejected instruction changed state");

    // Wrong commit ID is ignored, then a killed operation produces no result.
    issue(4'h2,0,32'h04fd02ff,32'h08070605,5'd3);
    xif.issue_req.id=4'h9; xif.issue_req.instr=insn(1,5'd4,0); xif.issue_req.rs[0]=32'd9; xif.issue_valid=1;
    repeat(4) begin
      #1; if(xif.issue_ready) $fatal(1,"FAIL: busy coprocessor accepted second request");
      @(posedge clk_i);
    end
    #1; xif.issue_valid=0;
    commit(4'h3,0);
    if(xif.result_valid||xif.issue_ready) $fatal(1,"FAIL: wrong commit ID affected request");
    commit(4'h2,1);
    if(!trace_valid||!trace_kill||trace_id!=4'h2) $fatal(1,"FAIL: killed commit trace missing");
    repeat(3) @(posedge clk_i); #1;
    if(xif.result_valid||!xif.issue_ready) $fatal(1,"FAIL: killed request produced result or remained busy");

    // Normal response must remain stable for arbitrary result backpressure.
    issue(4'h4,0,32'h04fd02ff,32'h08070605,5'd7); commit(4'h4,0); consume(4'h4,32'd18,1);
    if(nn_instruction_count!=1||nn_dotp4_count!=1||nn_requant_count!=0) $fatal(1,"FAIL: DOTP4 counters incorrect");

    // Reset in WAIT_COMMIT and SEND_RESULT must remove all pending state.
    issue(4'h5,1,32'hfffffff0,0,5'd8); rst_ni=0; @(posedge clk_i); #1;
    if(xif.result_valid) $fatal(1,"FAIL: result during reset from WAIT_COMMIT");
    rst_ni=1; @(posedge clk_i); #1;
    issue(4'h6,1,32'h7,0,5'd9); commit(4'h6,0);
    if(!xif.result_valid) $fatal(1,"FAIL: pre-reset result missing");
    rst_ni=0; @(posedge clk_i); #1;
    if(xif.result_valid) $fatal(1,"FAIL: result survived reset");
    rst_ni=1; @(posedge clk_i); #1;

    // A killed configuration write must not alter REQUANT state.
    issue(4'h7,5,32'd7,0,0); commit(4'h7,1);
    issue(4'h8,4,32'd2,0,5'd10); commit(4'h8,0); consume(4'h8,32'd2,1);
    if(nn_instruction_count!=1||nn_dotp4_count!=0||nn_requant_count!=1) $fatal(1,"FAIL: kill/reset/config counter semantics incorrect");

    // Consecutive transactions with varying operands and IDs.
    for(int n=0;n<64;n++) begin
      a=32'h9e3779b9*n+32'h12345678; b=32'h7f4a7c15*n+32'h89abcdef; exp=dot4(a,b);
      issue(n[3:0],0,a,b,(n%31)+1); commit(n[3:0],0);
      repeat(n%6) begin
        #1; if(!xif.result_valid||xif.result.data!==exp) $fatal(1,"FAIL: variable backpressure n=%0d",n);
        @(posedge clk_i); #1;
      end
      xif.result_ready=1; #1;
      if(!xif.result_valid||xif.result.data!==exp) $fatal(1,"FAIL: consecutive DOTP4 n=%0d valid=%0b got=%08x exp=%08x",n,xif.result_valid,xif.result.data,exp);
      @(posedge clk_i); #1; xif.result_ready=0;
    end
    if(nn_instruction_count!=65||nn_dotp4_count!=64||nn_requant_count!=1)
      $fatal(1,"FAIL: final counters instr=%0d dot=%0d requant=%0d",nn_instruction_count,nn_dotp4_count,nn_requant_count);
    $display("PASS: XIF illegal/backpressure/kill/reset/config/64-consecutive protocol tests");
    $finish;
  end
endmodule
`default_nettype wire
