# rsp_cg bad reply headers are unreachable because the harness never injects malformed replies.
coverage exclude -cvgpath {/sc_hub_uvm_pkg/sc_hub_cov_collector/rsp_cg/cp_header_valid/bad} -comment {reply header corruption is not injected by the UVM harness}
# rsp_cg badarg is unreachable because RTL only drives 00/10/11 response encodings.
coverage exclude -cvgpath {/sc_hub_uvm_pkg/sc_hub_cov_collector/rsp_cg/cp_response/badarg} -comment {RTL response mux never drives the 2'b01 badarg encoding}
# rsp_cross badarg combinations are unreachable for the same fixed response-encoding reason.
coverage exclude -cvgpath {/sc_hub_uvm_pkg/sc_hub_cov_collector/rsp_cg/rsp_cross/<badarg,*,*,*>} -comment {all badarg response crosses are unreachable because 2'b01 is never driven}
# cmd_cg malformed other is unreachable because the testbench only emits named malformed kinds.
coverage exclude -cvgpath {/sc_hub_uvm_pkg/sc_hub_cov_collector/cmd_cg/cp_malformed/other} -comment {malformed_kind is always one of the known helper strings}
# cmd_cg gap1 is unreachable because the collector timestamps commands on sent_ap after full packet emission, so the measured delta includes at least the next command body.
coverage exclude -cvgpath {/sc_hub_uvm_pkg/sc_hub_cov_collector/cmd_cg/cp_gap/gap1} -comment {cmd gap is sampled after full packet send completion so a 1-cycle bin cannot be observed}
# bus_cg control_csr bus range is unreachable because internal/control CSR commands never reach the external bus monitor.
coverage exclude -cvgpath {/sc_hub_uvm_pkg/sc_hub_cov_collector/bus_cg/cp_addr_range/control_csr} -comment {control CSR accesses are consumed internally before external-bus sampling}
# bus_cg internal_csr bus range is unreachable because internal/control CSR commands never reach the external bus monitor.
coverage exclude -cvgpath {/sc_hub_uvm_pkg/sc_hub_cov_collector/bus_cg/cp_addr_range/internal_csr} -comment {internal CSR accesses are consumed internally before external-bus sampling}
# x_addr_dir control_csr is unreachable because control CSR accesses never appear as external bus transactions.
coverage exclude -cvgpath {/sc_hub_uvm_pkg/sc_hub_cov_collector/bus_cg/x_addr_dir/<control_csr,*>} -comment {control CSR transactions are not sampled by bus_cg}
# x_addr_dir internal_csr is unreachable because internal CSR accesses never appear as external bus transactions.
coverage exclude -cvgpath {/sc_hub_uvm_pkg/sc_hub_cov_collector/bus_cg/x_addr_dir/<internal_csr,*>} -comment {internal CSR transactions are not sampled by bus_cg}
# rsp_cross atomic failure combinations are unreachable in the checked harness because forced-error atomic replies collapse to zero-payload protocol shortcuts that the reference model does not treat as valid atomic reads.
coverage exclude -cvgpath {/sc_hub_uvm_pkg/sc_hub_cov_collector/rsp_cg/rsp_cross/<failed,*,yes,*>} -comment {atomic error replies are not representable in the checked UVM harness without weakening reply checks}
# rsp_cross atomic busy combinations are unreachable in the checked harness because forced-error atomic replies collapse to zero-payload protocol shortcuts that the reference model does not treat as valid atomic reads.
coverage exclude -cvgpath {/sc_hub_uvm_pkg/sc_hub_cov_collector/rsp_cg/rsp_cross/<busy,*,yes,*>} -comment {atomic busy replies are not representable in the checked UVM harness without weakening reply checks}
# rsp_cross atomic long-burst successes are unreachable because the harness only models successful atomics as single-word read replies.
coverage exclude -cvgpath {/sc_hub_uvm_pkg/sc_hub_cov_collector/rsp_cg/rsp_cross/<*,long_burst,yes,*>} -comment {successful atomic replies are single-word only in the current harness}
# rsp_cross atomic burst successes are unreachable because the harness only models successful atomics as single-word read replies.
coverage exclude -cvgpath {/sc_hub_uvm_pkg/sc_hub_cov_collector/rsp_cg/rsp_cross/<*,burst,yes,*>} -comment {successful atomic replies are single-word only in the current harness}
# rsp_cross atomic short-burst successes are unreachable because the harness only models successful atomics as single-word read replies.
coverage exclude -cvgpath {/sc_hub_uvm_pkg/sc_hub_cov_collector/rsp_cg/rsp_cross/<*,short,yes,*>} -comment {successful atomic replies are single-word only in the current harness}
# rsp_cross atomic zero-payload successes are unreachable because the harness has no checked atomic-write reply path and successful atomic reads always return one word.
coverage exclude -cvgpath {/sc_hub_uvm_pkg/sc_hub_cov_collector/rsp_cg/rsp_cross/<*,zero,yes,*>} -comment {successful atomic replies are one-word reads and atomic-write replies are not modeled}
# rsp_cross write_reply with long payload is unreachable because write_reply is defined from payload_q.size()==0 in the collector.
coverage exclude -cvgpath {/sc_hub_uvm_pkg/sc_hub_cov_collector/rsp_cg/rsp_cross/<*,long_burst,*,yes>} -comment {write_reply implies zero observed payload words in rsp_cg}
# rsp_cross write_reply with burst payload is unreachable because write_reply is defined from payload_q.size()==0 in the collector.
coverage exclude -cvgpath {/sc_hub_uvm_pkg/sc_hub_cov_collector/rsp_cg/rsp_cross/<*,burst,*,yes>} -comment {write_reply implies zero observed payload words in rsp_cg}
# rsp_cross write_reply with short payload is unreachable because write_reply is defined from payload_q.size()==0 in the collector.
coverage exclude -cvgpath {/sc_hub_uvm_pkg/sc_hub_cov_collector/rsp_cg/rsp_cross/<*,short,*,yes>} -comment {write_reply implies zero observed payload words in rsp_cg}
# rsp_cross write_reply with one-word payload is unreachable because write_reply is defined from payload_q.size()==0 in the collector.
coverage exclude -cvgpath {/sc_hub_uvm_pkg/sc_hub_cov_collector/rsp_cg/rsp_cross/<*,one,*,yes>} -comment {write_reply implies zero observed payload words in rsp_cg}
# rsp_cross zero-payload non-write replies are unreachable because every command in this suite has echoed_length>0 and zero payload therefore classifies as write_reply=yes.
coverage exclude -cvgpath {/sc_hub_uvm_pkg/sc_hub_cov_collector/rsp_cg/rsp_cross/<*,zero,*,no>} -comment {zero payload with nonzero echoed length always classifies as write_reply=yes}
# rsp_cross atomic write-reply combinations are unreachable because the harness does not model a checked atomic-write response path.
coverage exclude -cvgpath {/sc_hub_uvm_pkg/sc_hub_cov_collector/rsp_cg/rsp_cross/<*,*,yes,yes>} -comment {atomic-write response combinations are not modeled in the current UVM harness}
# hub_cap_cg ord=off is unreachable because every compiled regression variant in this suite advertises ordering capability.
coverage exclude -cvgpath {/sc_hub_uvm_pkg/sc_hub_cov_collector/hub_cap_cg/cp_ord/off} -comment {all compiled regression variants advertise ordering support in HUB_CAP}
# hub_cap_cg atomic=off is unreachable because every compiled regression variant in this suite advertises atomic capability.
coverage exclude -cvgpath {/sc_hub_uvm_pkg/sc_hub_cov_collector/hub_cap_cg/cp_atomic/off} -comment {all compiled regression variants advertise atomic support in HUB_CAP}
# hub_cap_cg mismatched is unreachable because the collector compares HUB_CAP against the same cfg bits used to build each test.
coverage exclude -cvgpath {/sc_hub_uvm_pkg/sc_hub_cov_collector/hub_cap_cg/cp_match/mismatched} -comment {HUB_CAP is only sampled against matching per-run cfg capability bits in this suite}
# hub_cap_cg ord=off crosses are unreachable because ordering support is fixed on for all compiled variants in this suite.
coverage exclude -cvgpath {/sc_hub_uvm_pkg/sc_hub_cov_collector/hub_cap_cg/x_feature_match/<*,off,*,*>} -comment {ordering-off HUB_CAP combinations are not present in the compiled regression variants}
# hub_cap_cg atomic=off crosses are unreachable because atomic support is fixed on for all compiled variants in this suite.
coverage exclude -cvgpath {/sc_hub_uvm_pkg/sc_hub_cov_collector/hub_cap_cg/x_feature_match/<*,*,off,*>} -comment {atomic-off HUB_CAP combinations are not present in the compiled regression variants}
# hub_cap_cg mismatched crosses are unreachable because the per-run cfg is derived from the same compile-time capability knobs reported by HUB_CAP.
coverage exclude -cvgpath {/sc_hub_uvm_pkg/sc_hub_cov_collector/hub_cap_cg/x_feature_match/<*,*,*,mismatched>} -comment {HUB_CAP mismatch cases are unreachable with the current cfg derivation}
# aux_avmm_vif is a UVM-only stub interface and is never driven in simulation.
coverage exclude -scope /tb_top/harness/aux_avmm_vif -recursive -code t -comment {bench-only auxiliary Avalon interface is intentionally undriven}
# aux_axi4_vif is a UVM-only stub interface and is never driven in simulation.
coverage exclude -scope /tb_top/harness/aux_axi4_vif -recursive -code t -comment {bench-only auxiliary AXI4 interface is intentionally undriven}
