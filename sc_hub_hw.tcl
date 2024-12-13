################################################
# onewire_master "Slow Control Hub" 24.0.1119
# Yifeng Wang 
################################################

################################################
# request TCL package from ACDS 16.1
################################################
package require qsys 


################################################
# module sc_hub
################################################
set_module_property DESCRIPTION "Converts slow-control packet into system bus (Avalon Memory-Mapped) transactions"
set_module_property NAME sc_hub
set_module_property VERSION 24.0.1119
set_module_property INTERNAL false
set_module_property OPAQUE_ADDRESS_MAP true
set_module_property GROUP "Mu3e Control Plane/Modules"
set_module_property AUTHOR "Yifeng Wang"
set_module_property DISPLAY_NAME "Slow Control Hub"
set_module_property INSTANTIATE_IN_SYSTEM_MODULE true
set_module_property ICON_PATH ../figures/mu3e_logo.png
set_module_property EDITABLE false
set_module_property REPORT_TO_TALKBACK false
set_module_property ALLOW_GREYBOX_GENERATION false
set_module_property REPORT_HIERARCHY false
set_module_property ELABORATION_CALLBACK my_elaborate


################################################ 
# file sets
################################################
add_fileset QUARTUS_SYNTH QUARTUS_SYNTH "" ""
set_fileset_property QUARTUS_SYNTH TOP_LEVEL sc_hub_wrapper

add_fileset_file sc_hub_wrapper.vhd VHDL PATH sc_hub_wrapper.vhd 
add_fileset_file sc_hub.vhd VHDL PATH sc_hub.vhd
add_fileset_file alt_fifo_w32d256.vhd VHDL PATH ./alt_ip/alt_fifo_w32d256/alt_fifo_w32d256.vhd



################################################
# parameters
################################################


add_parameter AVMM_BURST_W NATURAL 
set_parameter_property AVMM_BURST_W DEFAULT_VALUE 9
set_parameter_property AVMM_BURST_W DISPLAY_NAME "Burst count signal wdith"
set_parameter_property AVMM_BURST_W TYPE NATURAL
set_parameter_property AVMM_BURST_W UNITS Bits
set_parameter_property AVMM_BURST_W ALLOWED_RANGES 0:10
set_parameter_property AVMM_BURST_W HDL_PARAMETER true
set dscpt \
"<html>
Set the Avalon Memory-Mapped <b>burstcount</b> signal width <br>
For example: for width set to 9 bits, the max burst is 2^ wdith-1 = 2^8 = 256 words.
</html>"
set_parameter_property AVMM_BURST_W DESCRIPTION $dscpt
set_parameter_property AVMM_BURST_W LONG_DESCRIPTION $dscpt


add_parameter AVMM_ADDR_W NATURAL 
set_parameter_property AVMM_ADDR_W DEFAULT_VALUE 16
set_parameter_property AVMM_ADDR_W DISPLAY_NAME "Address signal width"
set_parameter_property AVMM_ADDR_W TYPE NATURAL
set_parameter_property AVMM_ADDR_W UNITS Bits
set_parameter_property AVMM_ADDR_W ALLOWED_RANGES 0:32
set_parameter_property AVMM_ADDR_W HDL_PARAMETER true
set dscpt \
"<html>
Set the Avalon Memory-Mapped <b>address</b> signal width <br>
Note: word addressing <br>
</html>"
set_parameter_property AVMM_ADDR_W DESCRIPTION $dscpt
set_parameter_property AVMM_ADDR_W LONG_DESCRIPTION $dscpt


add_parameter AVST_ERROR_W NATURAL 
set_parameter_property AVST_ERROR_W DEFAULT_VALUE 1
set_parameter_property AVST_ERROR_W DISPLAY_NAME "Error signal width"
set_parameter_property AVST_ERROR_W TYPE NATURAL
set_parameter_property AVST_ERROR_W UNITS Bits
set_parameter_property AVST_ERROR_W ALLOWED_RANGES 1:1
set_parameter_property AVST_ERROR_W HDL_PARAMETER true
set dscpt \
"<html>
Select error width of error signal of the avalon streaming interface. <br>
Currently fixed, awaiting future update...

</html>"
set_parameter_property AVST_ERROR_W DESCRIPTION $dscpt
set_parameter_property AVST_ERROR_W LONG_DESCRIPTION $dscpt


add_parameter DEBUG NATURAL
set_parameter_property DEBUG DEFAULT_VALUE 1
set_parameter_property DEBUG DISPLAY_NAME "Debug level"
set_parameter_property DEBUG UNITS None
set_parameter_property DEBUG ALLOWED_RANGES {0 1 2}
set_parameter_property DEBUG HDL_PARAMETER true
set dscpt \
"<html>
Select the debug level of the IP (affects generation).<br>
<ul>
	<li><b>0</b> : off <br> </li>
	<li><b>1</b> : on, synthesizble <br> </li>
	<li><b>2</b> : on, non-synthesizble, simulation-only <br> </li>
</ul>
</html>"
set_parameter_property DEBUG LONG_DESCRIPTION $dscpt
set_parameter_property DEBUG DESCRIPTION $dscpt

################################################  
# display items
################################################ 




################################################ 
# connection point hub
################################################ 
add_interface hub avalon start
set_interface_property hub addressUnits WORDS
set_interface_property hub associatedClock clk
set_interface_property hub associatedReset rst
set_interface_property hub burstOnBurstBoundariesOnly false
set_interface_property hub burstcountUnits WORDS
set_interface_property hub linewrapBursts true
set_interface_property hub maximumPendingReadTransactions 1
set_interface_property hub maximumPendingWriteTransactions 1
set_interface_property hub alwaysBurstMaxBurst true


add_interface_port hub avm_hub_address address Output 16
add_interface_port hub avm_hub_read read Output 1
add_interface_port hub avm_hub_readdata readdata Input 32
add_interface_port hub avm_hub_writeresponsevalid writeresponsevalid Input 1
add_interface_port hub avm_hub_response response Input 2
add_interface_port hub avm_hub_write write Output 1
add_interface_port hub avm_hub_writedata writedata Output 32
add_interface_port hub avm_hub_waitrequest waitrequest Input 1
add_interface_port hub avm_hub_readdatavalid readdatavalid Input 1
add_interface_port hub avm_hub_burstcount burstcount Output 9


################################################ 
# connection point download
################################################ 
add_interface download avalon_streaming end
set_interface_property download associatedClock clk
set_interface_property download associatedReset rst
set_interface_property download dataBitsPerSymbol 36

add_interface_port download asi_download_data data Input 36
add_interface_port download asi_download_valid valid Input 1
add_interface_port download asi_download_ready ready Output 1


################################################ 
# connection point upload
################################################ 
add_interface upload avalon_streaming start
set_interface_property upload associatedClock clk
set_interface_property upload associatedReset rst
set_interface_property upload dataBitsPerSymbol 36
set_interface_property upload errorDescriptor "reply_pkt_broken"

add_interface_port upload aso_upload_data data Output 36
add_interface_port upload aso_upload_valid valid Output 1
add_interface_port upload aso_upload_ready ready Input 1
add_interface_port upload aso_upload_startopacket startofpacket Output 1
add_interface_port upload aso_upload_endofpacket endofpacket Output 1
add_interface_port upload aso_upload_error error Output 1

################################################ 
# connection point clk
################################################ 
add_interface clk clock end
set_interface_property clk clockRate 0

add_interface_port clk i_clk clk Input 1


################################################  
# connection point rst
################################################ 
add_interface rst reset end
set_interface_property rst associatedClock clk
set_interface_property rst synchronousEdges DEASSERT

add_interface_port rst i_rst reset Input 1


################################################
# callbacks
################################################
proc my_elaborate {} {
    # report:
	set ver [get_module_property version] 
	send_message INFO "<b>Slow Control Hub</b>: you are using version: $ver"
    
    # port width adaption:
    set_port_property avm_hub_address WIDTH_EXPR [get_parameter_value "AVMM_ADDR_W"]
    set_port_property avm_hub_burstcount WIDTH_EXPR [get_parameter_value "AVMM_BURST_W"]
    set_port_property aso_upload_error WIDTH_EXPR [get_parameter_value "AVST_ERROR_W"]
    
    return -code ok
}


