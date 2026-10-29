// Replay the same independently checked policy packets through two RTL
// revisions. Intended for the capacity 1..5 / lookahead 1..8 campaign: its
// packed inputs and outputs fit the scalar Verilator ports used here.
#include "Vgrover_ckpt_policy_parameterized.h"
#include "verilated.h"
#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <fstream>
#include <iomanip>

int main(int argc,char** argv) {
    Verilated::commandArgs(argc,argv);
    if(argc!=2) return 2;
    std::ifstream input(argv[1]);
    if(!input) return 2;
    Vgrover_ckpt_policy_parameterized top;
    auto tick=[&](){top.clk=0;top.eval();top.clk=1;top.eval();};
    top.rstn=0;top.start=0;top.slot_valid=0;top.slot_j_flat=0;top.j_window_flat=0;
    for(int i=0;i<4;++i)tick();
    top.rstn=1;
    for(int i=0;top.busy && i<2000000;++i)tick();
    if(top.busy)return 3;
    uint64_t valid,held,window,chosen;
    unsigned source,count,cost,segments;
    uint64_t total=0,actions=0,hits=0,misses=0;
    unsigned row=0,maximum=0;
    std::puts("row,cycles,actions,hits,misses");
    while(input>>std::hex>>valid>>held>>window>>std::dec>>source>>count
               >>std::hex>>chosen>>std::dec>>cost>>segments) {
        top.slot_valid=valid;top.slot_j_flat=held;top.j_window_flat=window;
        top.start=1;tick();top.start=0;
        // Input changes must not affect the accepted transaction.
        top.slot_valid=0;top.slot_j_flat=0;top.j_window_flat=0;
        unsigned elapsed=0;
        while(!top.done && elapsed<10000000){tick();++elapsed;}
        if(!top.done || top.policy_error || top.source_j!=source ||
           top.next_count!=count || top.next_j_flat!=chosen ||
           top.root_cost!=cost || top.root_segment_count!=segments ||
           top.policy_cycles_last!=elapsed) {
            std::fprintf(stderr,"Mismatch row=%u elapsed=%u source=%u/%u count=%u/%u tuple=%llx/%llx cost=%u/%u segments=%u/%u counter=%u\n",
                row,elapsed,unsigned(top.source_j),source,unsigned(top.next_count),count,
                (unsigned long long)top.next_j_flat,(unsigned long long)chosen,
                unsigned(top.root_cost),cost,unsigned(top.root_segment_count),segments,
                unsigned(top.policy_cycles_last));
            return 1;
        }
        std::printf("%u,%u,%u,%u,%u\n",row,elapsed,top.policy_actions_last,
                    top.policy_memo_hit_last,top.policy_memo_miss_last);
        total+=elapsed;actions+=top.policy_actions_last;hits+=top.policy_memo_hit_last;
        misses+=top.policy_memo_miss_last;maximum=std::max(maximum,elapsed);++row;
        tick();
    }
    if(!input.eof())return 4;
    std::fprintf(stderr,"PASS rows=%u cycles=%llu actions=%llu hits=%llu misses=%llu max=%u\n",
        row,(unsigned long long)total,(unsigned long long)actions,
        (unsigned long long)hits,(unsigned long long)misses,maximum);
    return row?0:5;
}
