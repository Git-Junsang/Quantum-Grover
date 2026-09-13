//==============================================================================
// grover_dram_prep_seq.v -- hardware_dram branch, buffer-A preparation
// sequencer. This is the module that actually replaces grover_checkpoint.v's
// planner+executor pair.
//
// Given a target Grover iteration count prep_target_j, this sequencer makes
// buffer A (see grover_dram_queue.v) physically hold exactly G^j|psi0>, using
// the cheapest of three primitives:
//
//   (1) already there       -- buf_a_j == prep_target_j: no-op.
//   (2) DRAM restore        -- prep_target_j <= frontier_j: the exact state
//                               was already stored on a previous, deeper
//                               round; one direct burst read reproduces it.
//   (3) grow past frontier  -- prep_target_j > frontier_j: run the shared
//                               Grover engine forward one iteration at a
//                               time from the frontier, and after EACH
//                               completed iteration stream that row set out
//                               to DRAM (grover_dram_amp_store STORE side)
//                               before starting the next one. This is the
//                               literal implementation of "이터레이션이 끝날
//                               때마다 매 진폭값을 DRAM 에 저장" from
//                               CLAUDE.md section 3.
//
// frontier_j is the highest iteration index materialized in DRAM so far this
// search session (0 means only the implicit INIT state j=0 is known -- j=0
// is never written to DRAM, see grover_dram_param.vh). It only ever
// increases, and only case (3) advances it.
//
// v1 scope: only buffer A is driven (a_role_*). grover_dram_queue.v's buffer
// B exists for a future cross-round prefetch phase, deliberately NOT
// attempted here. The reason: BBHT's m_bound schedule (grover_iter_rom via
// round_idx) only advances round_idx AFTER a shot is confirmed to have
// failed, so a candidate for round r+1 cannot be legally drawn before round
// r's measurement result is known -- prefetching across that boundary is
// exactly the speculate-then-maybe-roll-back problem hardware_bram's
// AUTO_SPEC_ENABLE speculative epoch machinery exists to solve, and that
// machinery is nontrivial (grover_policy.v, ~2200 lines). Getting the
// within-round DRAM store/restore mechanism itself correct and simple is
// this draft's whole scope; cross-round speculation is future work.
//==============================================================================
`timescale 1ns/1ps
`include "grover_dram_param.vh"

module grover_dram_prep_seq (
    input  wire                              clk,
    input  wire                              rstn,

    // Pulse on any dataset/Oracle semantic change or a fresh accepted search
    // start. Forces the next PREP to rebuild from scratch: the DRAM table
    // written under the old semantics is no longer meaningful.
    input  wire                              dram_invalidate,

    input  wire                              prep_start,
    input  wire [`GP_J_W-1:0]                prep_target_j,
    output wire                              prep_busy,
    output reg                               prep_done,

    // Shared Grover growth engine (grover_ctrl_fsm), operating in place on
    // whichever buffer a_role_grow currently selects.
    output reg                               iter_start,
    output reg                               iter_do_init,
    output reg  [15:0]                       iter_count,
    input  wire                              iter_done,

    // Shared DRAM store/restore engine (grover_dram_amp_store).
    output reg                               store_start,
    output reg  [`GP_J_W-1:0]                store_j,
    input  wire                              store_done,

    output reg                               restore_start,
    output reg  [`GP_J_W-1:0]                restore_j,
    input  wire                              restore_done,

    // Buffer-A role selects into grover_dram_queue.
    output reg                               a_role_grow,
    output reg                               a_role_store,
    output reg                               a_role_restore,

    // Debug/Golden-trace visibility.
    output reg  [`GP_J_W-1:0]                frontier_j,
    output reg                               buf_a_valid,
    output reg  [`GP_J_W-1:0]                buf_a_j
);
    localparam [3:0]
        P_IDLE            = 4'd0,
        P_DECIDE          = 4'd1,
        P_RESTORE_TARGET  = 4'd2,
        P_RESTORE_FRONT   = 4'd3,
        P_INIT_ONLY       = 4'd4,
        P_INIT_THEN_GROW  = 4'd5,
        P_GROW_ISSUE      = 4'd6,
        P_GROW_WAIT       = 4'd7,
        P_STORE           = 4'd8,
        P_DONE            = 4'd9;

    reg [3:0]           st;
    reg [`GP_J_W-1:0]   target_j_r;

    assign prep_busy = (st != P_IDLE);

    always @(posedge clk) begin
        if (!rstn) begin
            st             <= P_IDLE;
            target_j_r     <= {`GP_J_W{1'b0}};
            prep_done      <= 1'b0;
            iter_start     <= 1'b0;
            iter_do_init   <= 1'b0;
            iter_count     <= 16'd0;
            store_start    <= 1'b0;
            store_j        <= {`GP_J_W{1'b0}};
            restore_start  <= 1'b0;
            restore_j      <= {`GP_J_W{1'b0}};
            a_role_grow    <= 1'b0;
            a_role_store   <= 1'b0;
            a_role_restore <= 1'b0;
            frontier_j     <= {`GP_J_W{1'b0}};
            buf_a_valid    <= 1'b0;
            buf_a_j        <= {`GP_J_W{1'b0}};
        end else begin
            prep_done     <= 1'b0;
            iter_start    <= 1'b0;
            store_start   <= 1'b0;
            restore_start <= 1'b0;

            if (dram_invalidate) begin
                frontier_j  <= {`GP_J_W{1'b0}};
                buf_a_valid <= 1'b0;
            end

            case (st)
                P_IDLE: begin
                    a_role_grow    <= 1'b0;
                    a_role_store   <= 1'b0;
                    a_role_restore <= 1'b0;
                    if (prep_start) begin
                        target_j_r <= prep_target_j;
                        st         <= P_DECIDE;
                    end
                end

                // Pure decision state: no bus activity, so it is safe to
                // land here the same cycle dram_invalidate clears buf_a_valid
                // above -- the branch below reads the just-updated value.
                //
                // target_j_r==0 is checked BEFORE the frontier/restore
                // branches and is always resolved via free local INIT, never
                // via DRAM restore: slot 0 is never written (see
                // grover_dram_param.vh), so restore_j=0 would read
                // uninitialized/garbage DRAM content. This also means a
                // redraw of j=0 after the frontier has already advanced past
                // it (a legal, unremarkable BBHT outcome -- j is redrawn
                // uniformly every round) must NOT fall into P_GROW_ISSUE
                // afterward, because that state's forward-growth step
                // assumes buf_a_j==frontier_j; landing there with buf_a_j
                // forced to 0 while frontier_j is already >0 would silently
                // grow from the wrong state and store it under the wrong
                // DRAM slot. P_INIT_ONLY therefore goes straight to P_DONE.
                P_DECIDE: begin
                    if (buf_a_valid && (buf_a_j == target_j_r)) begin
                        st <= P_DONE;
                    end else if (target_j_r == {`GP_J_W{1'b0}}) begin
                        a_role_grow  <= 1'b1;
                        iter_start   <= 1'b1;
                        iter_do_init <= 1'b1;
                        iter_count   <= 16'd0;
                        st           <= P_INIT_ONLY;
                    end else if (target_j_r <= frontier_j) begin
                        a_role_restore <= 1'b1;
                        restore_start  <= 1'b1;
                        restore_j      <= target_j_r;
                        st             <= P_RESTORE_TARGET;
                    end else if (buf_a_valid && (buf_a_j == frontier_j)) begin
                        st <= P_GROW_ISSUE;
                    end else if (frontier_j == {`GP_J_W{1'b0}}) begin
                        a_role_grow  <= 1'b1;
                        iter_start   <= 1'b1;
                        iter_do_init <= 1'b1;
                        iter_count   <= 16'd0;
                        st           <= P_INIT_THEN_GROW;
                    end else begin
                        a_role_restore <= 1'b1;
                        restore_start  <= 1'b1;
                        restore_j      <= frontier_j;
                        st             <= P_RESTORE_FRONT;
                    end
                end

                P_RESTORE_TARGET: begin
                    if (restore_done) begin
                        buf_a_j     <= target_j_r;
                        buf_a_valid <= 1'b1;
                        st          <= P_DONE;
                    end
                end

                P_RESTORE_FRONT: begin
                    if (restore_done) begin
                        buf_a_j     <= frontier_j;
                        buf_a_valid <= 1'b1;
                        st          <= P_GROW_ISSUE;
                    end
                end

                // target_j_r==0: INIT satisfies the request directly.
                P_INIT_ONLY: begin
                    if (iter_done) begin
                        buf_a_j     <= {`GP_J_W{1'b0}};
                        buf_a_valid <= 1'b1;
                        st          <= P_DONE;
                    end
                end

                // frontier_j==0 but target_j_r>0: INIT only reaches the
                // frontier state; forward growth continues below.
                P_INIT_THEN_GROW: begin
                    if (iter_done) begin
                        buf_a_j     <= {`GP_J_W{1'b0}};
                        buf_a_valid <= 1'b1;
                        st          <= P_GROW_ISSUE;
                    end
                end

                // frontier_j has not changed since the last time this state
                // was entered, so buf_a_j == frontier_j is still the
                // invariant here (either just established above, or true
                // from the previous P_STORE iteration below).
                P_GROW_ISSUE: begin
                    if (frontier_j == target_j_r) begin
                        st <= P_DONE;
                    end else begin
                        // 이 상태로 들어오는 두 경로가 각각 store/restore
                        // 역할을 켜 둔 채 도착합니다 (P_STORE 에서 오면
                        // a_role_store, P_RESTORE_FRONT 에서 오면
                        // a_role_restore). 여기서 내려 주지 않으면 grow 와
                        // 겹친 채로 성장 반복이 돌아갑니다. grover_dram_
                        // queue.v 의 읽기 인에이블은 역할별 OR 이라, 지금은
                        // 상대 엔진이 유휴여서 결과가 우연히 맞지만 그 모듈이
                        // 문서로 못박은 "버퍼당 역할은 한 번에 하나" 불변식은
                        // 깨진 상태가 됩니다. 나중에 버퍼 B 프리페치를 붙여
                        // store 와 grow 를 겹치게 하는 순간 조용히 잘못된 행을
                        // 읽게 되므로 여기서 끊어 둡니다.
                        a_role_store   <= 1'b0;
                        a_role_restore <= 1'b0;
                        a_role_grow    <= 1'b1;
                        iter_start     <= 1'b1;
                        iter_do_init   <= 1'b0;
                        iter_count     <= 16'd1;
                        st             <= P_GROW_WAIT;
                    end
                end

                P_GROW_WAIT: begin
                    if (iter_done) begin
                        a_role_grow  <= 1'b0;
                        a_role_store <= 1'b1;
                        store_start  <= 1'b1;
                        store_j      <= frontier_j + 1'b1;
                        st           <= P_STORE;
                    end
                end

                P_STORE: begin
                    if (store_done) begin
                        frontier_j <= frontier_j + 1'b1;
                        buf_a_j    <= frontier_j + 1'b1;
                        st         <= P_GROW_ISSUE;
                    end
                end

                P_DONE: begin
                    a_role_grow    <= 1'b0;
                    a_role_store   <= 1'b0;
                    a_role_restore <= 1'b0;
                    prep_done      <= 1'b1;
                    st             <= P_IDLE;
                end

                default: st <= P_IDLE;
            endcase
        end
    end
endmodule
