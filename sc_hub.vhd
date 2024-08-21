-- File name: sc_hub.vhd 
-- Author: Yifeng Wang (yifenwan@phys.ethz.ch)
-- =======================================
-- Revision: 1.0 (file created)
--		Date: Jan 9, 2024
-- Revision: 2.0 (add single read and write; burst read is implemented with DP-RAM; 
--				 burst write is implemented with SC-FIFO)
-- 	Date: Jan 29, 2024
-- Revision: 3.0 (all commands are buffered with SC-FIFO, basic functions verified)
-- 	Date: Jan 31, 2024
-- Revision: 3.1 (fix minor bug to release the qsys read if terminated; add timeout for write)
--		Date: Feb 13, 2024
-- =========
-- Description:	[Slow Control Hub] 
	-- Acting as the Hub with two Avalon-MM Master port to interfacing the ports locally in this FPGA.
	
-- Block diagram: 
	--+-------------------------------------------------+------------------+
	--|                                                 |                  |
	--|  +------------+                                 +--------+         |
	--|  |            |                                 |        |         |
	--|  |  sc frame  |    +---------+                  |Avalon  +----+    |
	--|  |  assembly  |    |         |                  |Write   |    v    |
	--|  |            +--->| Write   +----------------->|Handler | +-------+
	--|  +------------+    | FIFO    |                  |        | |       |
	--|                    +---------+                  +--------+ |       |
	--+------+                                          |          |       |
	--|      |                                          |          |AVMM   |
	--|AVMM  |            +-----------+                 |          |Master |
	--|Slave |            | Control-  |                 |          |Inter- |
	--|Inter-|<---------->| Status-   |                 |          |face   |
	--|face  |            | Register  |                 |          |       |
	--|      |            +-----------+                 |          |       |
	--+------+                                          +--------+ |       |
	--|                                                 |        | +-------+
	--|  +------------+                                 |Avalon  |     ^   |
	--|  |            |   +----------+                  |Read    +-----+   |
	--|  |  sc frame  |   |          |                  |Handler |         |
	--|  | deassembly |<--+ Read     |<-----------------+        |         |
	--|  |            |   | FIFO     |                  +--------+         |
	--|  +------------+   +----------+                  |                  |
	--|                                                 |                  |
	--+-------------------------------------------------+------------------+
	
-- Mu3e IP Library: 
			--@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@\
			--@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@\
			--@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@\
			--@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@\
			--@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@\
			--@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@&BG@@@@@@\
			--@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@#GJ7~~~!7Y&@@@@@\
			--@@@@@@@@@@@@@@@@@YB@@@@@@@@@@@@@@@@@@@&&&&@@@@@@@@@@@@#P?!~7JP#&@@@@@@@@@@@\
			--@@@@@@@@@@@@@@@5.~@@&@@@@@@@@@@&&&#&&&&&&&#BGG#@@@#57!?P#@@@@@@@@@@@@@@@@@@\
			--@@@@@@@@@@@@@G~Y!&#GY&@@&&@@@&&@@@@@@@@@@@@@@@B!!~YB&@@@@@@@@@@@@@@@@@@@@@@\
			--@@@@@@@@@@@#7J@@G#&@&G&&@55@@@@@@@@@&&&&&@@@GY5B&5P@@@@@@@@@@@@@@@@@@@@@@@@\
			--@@@@@@@@@&YJ&@@@@@@@@@@@&Y&@@@@@&&&&@@@@&5?7G@@@@@55@@@@@@@@@@@@@@@@@@@@@@@\
			--@@@@@@@@GY&@@@@@@@@@@@@@#&Y@@@@@@@@@@@@&G#@@5@@@@@@7&@@@@@@@@@@@@@@@@@@@@@@\
			--@@@@@@#P&@@@@@@@@@@@#&@@@BY@@@@@@@@@@&PB&&##JJBB#@@?B@@@@@@@@@@@@@@@@@@@@@@\
			--@@@@&B&@@@@@@@@@@@@@@GBGGGGG5@@@@@@@&B&@@@@@J#@&#PJ^#@@@@@@@@@@@@@@@@@@@@@@\
			--@@@&@@@@@@@@@@@@@@@@#@@@@GYGB&@@@##@@@@@@@@P5@@@@@Y~7P@@@@@@@@@@@@@@@@@@@@@\
			--@@@@@@@@@@@@@@@@@@@G~&@@@@@@@@@GG@@@@@@@@@55@@@@@G7&@J~@@@@@@@@@@@@@@@@@@@@\
			--@@@@@@@@@@@@@@@@@@@5!@@@@@@##GY&@@@@@@@&GY#@@@@@P7&@@@J^@@@@@@@@@@@@@@@@@@@\
			--@@@@@@@@@@@@@@@@@@@#~B@@@@@P:!#&@@&&BG5P&@@@@@&JY@@@@@@:P@@@@@@@@@@@@@@@@@@\
			--@@@@@@@@@@@@@@@@@@@@P!#@@@7?@@#BGGB#&@@@@@@@&5J#@@@@@@@?~@@@@@@@@@@@@@@@@@@\
			--@@@@@@@@@@@@@@@@@@@@@B75#^5@@@@@@@@@@@@@@&GJY#@@@@@@@@@:?@@@@@@@@@@@@@@@@@@\
			--@@@@@@@@@@@@@@@@@@@@@@@5 ^G#&@@@@@&&#BP5JYG&@@@@@@@@@@J.&@@@@@@@@@@@@@@@@@@\
			--@@@@@@@@@@@@@@@@@@@@@@@~!@#GP555555PPG#&@@@@@@@@@@@@@7:&@@@@@@@@@@@@@@@@@@@\
			--@@@@@@@@@@@@@@@@@@@@@@B &@@@@@@@@@@@@@@@@@@@@@@@@@&Y^J@@@@@@@@@@@@@@@@@@@@@\
			--@@@@@@@@@@@@@@@@@@@@@@5.@@@@@@@@@@@@@@@@@&^J#&#PJ!!5@@@@@@@@@@@@@@@@@@@@@@@\
			--@@@@@@@@@@@@@@@@@@@@@@B &@@@@@@@@@@@@@@@@@@GYJYP#@@@@@@@@@@@@@@@@@@@@@@@@@@\
			--@@@@@@@@@@@@@@@@@@@@@@@~:@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@\
			--@@@@@@@@@@@@@@@@@@@@@@@@!:G@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@\
			--@@@@@@@@@@@@@@@@@@@@@@@@@#?!7J5G@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@\
			--@@@@@@@@@@@@@@@@@@@@@@@@@@@@&#BG@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@\
			--@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@\
			--@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@\
			--@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@\
			--@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@\
			--@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@}
--	
-- ================ synthsizer configuration =================== 		
-- altera vhdl_input_version vhdl_2008
-- ============================================================= 

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use IEEE.math_real.log2;
use IEEE.math_real.ceil;
use ieee.std_logic_arith.conv_std_logic_vector;

entity sc_hub is 
	generic(
		DEBUG				: natural := 1
	);
	port(
		i_clk				: in  std_logic;
		i_rst				: in  std_logic;
		
		i_linkin_data     	: in  std_logic_vector(31 downto 0);
		i_linkin_datak    	: in  std_logic_vector(3 downto 0);
		o_linkin_ready		: out std_logic;
		
		o_linkout_data		: out std_logic_vector(31 downto 0);
		o_linkout_datak		: out std_logic_vector(3 downto 0);
		o_linkout_en		: out std_logic;
		o_linkout_sop		: out std_logic;
		o_linkout_eop		: out std_logic;
		
		avm_m0_address				: out std_logic_vector(15 downto 0);
		avm_m0_read					: out std_logic;
		avm_m0_readdata				: in  std_logic_vector(31 downto 0);
		avm_m0_writeresponsevalid	: in std_logic;
		avm_m0_response				: in  std_logic_vector(1 downto 0);
		avm_m0_write				: out std_logic;
		avm_m0_writedata			: out std_logic_vector(31 downto 0);
		avm_m0_waitrequest			: in  std_logic;
		avm_m0_readdatavalid		: in  std_logic;
		avm_m0_flush				: out std_logic := '0';
		avm_m0_burstcount			: out std_logic_vector(8 downto 0) -- max burst is 2^<burstcount-1>=2^8=256
	);
end entity sc_hub;

architecture rtl of sc_hub is 

	constant K285						: std_logic_vector(7 downto 0) := "10111100"; -- 8#BC#
	constant K284						: std_logic_vector(7 downto 0) := "10011100"; -- 8#9C#
	constant K237						: std_logic_vector(7 downto 0) := "11110111"; -- 8#F7#
	signal address_code				: std_logic_vector(15 downto 0);
	signal qsys_addr 				: std_logic_vector(15 downto 0);
	signal qsys_addr_vld			: std_logic;
	
	signal link_data_comb, link_data		: std_logic_vector(31 downto 0);
	signal link_datak_comb, link_datak		: std_logic_vector(3 downto 0);
	signal link_en_comb, link_en			: std_logic;
	signal link_sop, link_eop				: std_logic;
	
	signal wr_word_cnt				: std_logic_vector(7 downto 0);
	signal isPreamble				: std_logic;
	signal isSkipWord				: std_logic;
	signal record_preamble_done		: std_logic;
	signal record_head_done			: std_logic;
	signal record_length_done		: std_logic;
	signal send_trailer_done		: std_logic;
	signal read_trans_start			: std_logic;
	signal read_ack_done			: std_logic;
	signal send_preamble_done		: std_logic;
	signal send_addr_done			: std_logic;
	signal send_write_reply_done	: std_logic;
	signal reset_done				: std_logic;
	signal reset_start				: std_logic;
	
	signal read_avstart								: std_logic;

	signal rd_trans_terminated						: std_logic;
	signal rd_timeout_cnt							: std_logic_vector(15 downto 0);
	
	signal av_rd_cmd_send_done						: std_logic;
		--attribute syn_keep of av_rd_cmd_send_done: signal is true;
	
	signal write_buff_ready							: std_logic;
	signal write_buff_done							: std_logic;
	signal wr_trans_done, rd_trans_done				: std_logic;
	--signal single_write_avstart					: std_logic;
	signal burst_write_avstart						: std_logic;
	signal write_av_waitforcomp						: std_logic;
	signal wr_trans_cnt, rd_trans_cnt				: std_logic_vector(7 downto 0);
		
	signal rd_ack_start								: std_logic;
	signal read_ack_almostdone						: std_logic;

	signal rd_ack_word_cnt							: std_logic_vector(7 downto 0);

	signal wr_fifo_din, rd_fifo_din				: std_logic_vector(31 downto 0);
	signal wr_fifo_wrreq, rd_fifo_wrreq 		: std_logic;
	signal wr_fifo_rdreq, rd_fifo_rdreq			: std_logic;
	signal wr_fifo_dout, rd_fifo_dout			: std_logic_vector(31 downto 0);
	signal wr_fifo_empty, rd_fifo_empty			: std_logic;
	signal wr_fifo_full, rd_fifo_full			: std_logic;
	signal wr_fifo_usedw, rd_fifo_usedw			: std_logic_vector(7 downto 0);
	signal wr_fifo_sclr, rd_fifo_sclr			: std_logic;
	
	signal sc_hub_reset_done					: std_logic;

	signal skipWord_charac	: std_logic_vector(31 downto 0)	:= "00000000000000000000000010111100"; 
	
	type sc_pkt_info_t is record
		sc_type				: std_logic_vector(1 downto 0);
		fpga_id				: std_logic_vector(15 downto 0);
		mask_m				: std_logic;
		mask_s				: std_logic;
		mask_t				: std_logic;
		mask_r				: std_logic;
		start_address		: std_logic_vector(23 downto 0);
		rw_length			: std_logic_vector(15 downto 0);
	end record;
	
	signal sc_pkt_info 		: sc_pkt_info_t;
	
	type sc_hub_state_t is (IDLE, RECORD_HEADER, RUNNING_HEAD, RUNNING_READ, RUNNING_WRITE, RUNNING_TRAILER, REPLY, RESET);
	signal sc_hub_state		: sc_hub_state_t:= RESET;
	
	type ack_state_t is (IDLE, PREAMBLE, ADDR, WR_ACK, RD_ACK, TRAILER, RESET);
	signal ack_state		: ack_state_t;
	
	type read_ack_flow_t is (S1, S2, IDLE);
	signal read_ack_flow 	: read_ack_flow_t;
	
	type ath_state_t is (AV_RD, AV_WR, RESET, IDLE);
	signal ath_state			: ath_state_t;
	
	component alt_fifo_w32d256
	PORT
	(
		clock		: IN STD_LOGIC ;
		data		: IN STD_LOGIC_VECTOR (31 DOWNTO 0);
		rdreq		: IN STD_LOGIC ;
		sclr		: IN STD_LOGIC ;
		wrreq		: IN STD_LOGIC ;
		empty		: OUT STD_LOGIC ;
		full		: OUT STD_LOGIC ;
		q			: OUT STD_LOGIC_VECTOR (31 DOWNTO 0);
		usedw		: OUT STD_LOGIC_VECTOR (7 DOWNTO 0)
	);
	end component;

begin
	-- Time Interleaving of Multiple State Machines (hub main, avmm handler, ack)
	-- Description: 
	--              It is allowed for the write avmm handler to start while commands are being received,
	--              during which the data buffering will be kept by the local alt_fifo.
	--              For the read commands, since only start address is needed, the read avmm handler
	--              can start immediate the adddress and burst count is given.
	--              However, in both cases, the acknowledge state machine must start once the avmm 
	--              transaction is completed. This lock mechanism will not create back-pressure on
	--              the SC_Link side (no IDLE words in ack packet), but it will induce back-pressure
	--              on the qsys bus side, which will be absorbed elastically by qsys interconnect and
	--              the local alt_fifo.
	-- 
	-- TODO:
	--       [ ] 1) add wrapper level for buffering the commands, currently only one cmd accepted until
	--              ack packet is sent.
	--
	-- Notation: ~~: idle wait
	--				 ||: wait until other process finishes
	--           |->: callback to start other process
	-- =======================================================================================================
	-- WRITE FLOW:
	-- [cmd]: main state machine => write handler -> FIFO~~||
	--		        |(fifo not empty)                        ||
	--            |->         FIFO -> write handler -> AVMM||
	-- [ack]:                                              ||(wr_trans_done)
	--                                                     |||->ack state machine -> SC_Link
	-- =======================================================================================================
	-- READ FLOW:									
	-- [cmd]: main state machine => read handler||
	--                                          ||
	--                                          ||FIFO <- read handler <- AVMM||(rd_trans_done)
	-- [ack]:                                                                 ||->ack state machine -> SC_Link
	-- =======================================================================================================
	alt_fifo_wr : alt_fifo_w32d256 
	port map(
		clock	 => i_clk,
		data	 => wr_fifo_din,
		rdreq	 => wr_fifo_rdreq,
		sclr	 => wr_fifo_sclr,
		wrreq	 => wr_fifo_wrreq,
		empty	 => wr_fifo_empty,
		full	 => wr_fifo_full,
		q	 	 => wr_fifo_dout,
		usedw	 => wr_fifo_usedw
	);
	
	alt_fifo_rd	: alt_fifo_w32d256
	port map(
		clock	 => i_clk,
		data	 => rd_fifo_din,
		rdreq	 => rd_fifo_rdreq,
		sclr	 => rd_fifo_sclr,
		wrreq	 => rd_fifo_wrreq,
		empty	 => rd_fifo_empty,
		full	 => rd_fifo_full,
		q	 	 => rd_fifo_dout,
		usedw	 => rd_fifo_usedw
	);
	
	proc_link_reg_out : process(i_clk,i_rst)
	begin
		if (i_rst = '1') then
			o_linkout_data		<= (others=>'0');
			o_linkout_datak	<= (others=>'0');
			o_linkout_en		<= '0';
			o_linkout_sop		<= '0';
			o_linkout_eop		<= '0';
		elsif (rising_edge(i_clk)) then
			o_linkout_data		<= link_data;
			o_linkout_datak	<= link_datak;
			o_linkout_en		<= link_en;
			o_linkout_sop		<= link_sop;
			o_linkout_eop		<= link_eop;
		end if;
	end process proc_link_reg_out;

-- === main fsm ===
	proc_fsm : process(i_clk,i_rst)
	begin
		if (i_rst = '1') then
			sc_hub_state	<= RESET;
		elsif (rising_edge(i_clk)) then
			case(sc_hub_state) is 
				when IDLE =>	-- ignore command until ack is done
					if (isPreamble = '1') then
						sc_hub_state	<= RECORD_HEADER;
					end if;
				when RECORD_HEADER =>
					if (sc_pkt_info.sc_type(0)='0' and (isSkipWord='0')) then 
						sc_hub_state	<= RUNNING_READ;
					elsif (not isSkipWord) then
						sc_hub_state	<= RUNNING_WRITE;
					else
					end if;
				when RUNNING_READ => 
					if (not isSkipWord) then
						sc_hub_state	<= RUNNING_TRAILER;
					end if;
				when RUNNING_WRITE =>
					if (record_length_done = '1' and to_integer(unsigned(wr_word_cnt)) = to_integer(unsigned(sc_pkt_info.rw_length)) and (isSkipWord='0')) then
						sc_hub_state	<= RUNNING_TRAILER;
					else
						sc_hub_state	<= RUNNING_WRITE;
					end if;
				-- this state should delay to cover the trailer for correct timing
				when RUNNING_TRAILER =>
					sc_hub_state	<= REPLY;
				when REPLY =>
					if (send_trailer_done = '1') then
						sc_hub_state	<= RESET;
					end if;
					if (rd_trans_terminated = '1') then
						sc_hub_state	<= RESET;
					end if;
				when RESET =>
					if (sc_hub_reset_done = '1') then
						sc_hub_state 	<= IDLE;
					end if;
				when others =>
					sc_hub_state	<= RESET; 
			end case;
		end if;
	end process proc_fsm;
	
-- === part 1: RECEIVING the commands
	
	proc_fsm_regs : process(i_clk,i_rst)
	begin
		if (i_rst = '1') then
			
		elsif (rising_edge(i_clk))  then 
			case sc_hub_state is
				when RESET =>
					if (rd_trans_terminated = '1') then
						avm_m0_flush	<= '1'; -- flush the unfinished read pipeline transaction, if addressed unspecified region, removed in spec 1.2
					else
						avm_m0_flush	<= '0';
					end if;
					ath_state						<= RESET;	
					o_linkin_ready					<= '0';
					read_trans_start				<= '0';
					write_buff_ready				<= '0';
					write_buff_done					<= '0';
					ack_state						<= RESET;
					sc_pkt_info.sc_type				<= (others=>'0');
					sc_pkt_info.fpga_id				<= (others=>'0');
					record_preamble_done			<= '0';
					sc_pkt_info.start_address		<= (others=>'0');
					sc_pkt_info.mask_m				<= '0';
					sc_pkt_info.mask_s				<= '0';
					sc_pkt_info.mask_t				<= '0';
					sc_pkt_info.mask_r				<= '0';
					record_head_done				<= '0';
					sc_pkt_info.rw_length			<= (others=>'0');
					record_length_done				<= '0';
					wr_fifo_din						<= (others=>'0');
					wr_word_cnt						<= (others=>'0');
					wr_fifo_wrreq					<= '0';
				when IDLE =>
					avm_m0_flush					<= '0';
					ath_state						<= IDLE;
					ack_state						<= IDLE;
					o_linkin_ready					<= '1';
					if (isPreamble = '1' and record_preamble_done = '0' and (isSkipWord='0')) then
						sc_pkt_info.sc_type		<= i_linkin_data(25 downto 24);
						sc_pkt_info.fpga_id		<= i_linkin_data(23 downto 8);
						record_preamble_done		<= '1';
						o_linkin_ready				<= '0';
					end if;
				when RECORD_HEADER =>
					if (record_head_done = '0' and (isSkipWord='0')) then 
						sc_pkt_info.start_address		<= i_linkin_data(23 downto 0);
						sc_pkt_info.mask_m				<= i_linkin_data(27);
						sc_pkt_info.mask_s				<= i_linkin_data(26);
						sc_pkt_info.mask_t				<= i_linkin_data(25);
						sc_pkt_info.mask_r				<= i_linkin_data(24);
						record_head_done				<= '1';
					end if;
				when RUNNING_READ =>
					if (isSkipWord='0') then
						read_trans_start		<= '1';
						ath_state				<= AV_RD;
						if (record_length_done = '0') then
							sc_pkt_info.rw_length	<= i_linkin_data(15 downto 0);
							record_length_done		<= '1';
						end if;
					end if;
				when RUNNING_WRITE => 
					-- burst write / 
					-- non-burst write (treated as burst write length=1)
					if (isSkipWord='0') then
						write_buff_ready		<= '1';
						ath_state				<= AV_WR;
						if (record_length_done = '0') then
							sc_pkt_info.rw_length	<= i_linkin_data(15 downto 0);
							record_length_done		<= '1';
						end if;
						if (to_integer(unsigned(wr_word_cnt)) < to_integer(unsigned(sc_pkt_info.rw_length)) and record_length_done='1') then 
						-- this is case for the second cycle of receiving write command 
							wr_fifo_wrreq		<= '1';
							wr_fifo_din			<= i_linkin_data;
							wr_word_cnt			<= conv_std_logic_vector(to_integer(unsigned(wr_word_cnt)) + 1, wr_word_cnt'length); 
						elsif (record_length_done = '0') then
						-- first cycle of one length write
						else -- last cycle of running write, we reset everything
							wr_fifo_wrreq		<= '0';
							wr_word_cnt			<= conv_std_logic_vector(0, wr_word_cnt'length);
							write_buff_done	<= '1';
						end if;
					else
						wr_fifo_wrreq			<= '0';
					end if;
				when RUNNING_TRAILER => 
					-- TODO: confirm the packet structure is correct
				when REPLY =>
					case ack_state is 
						when IDLE => 
							if ((wr_trans_done='1' or rd_trans_done='1') and send_trailer_done='0') then
							-- prevent loop: haven't send trailer yet, so we start reply
								ack_state	<= PREAMBLE;
								ath_state	<= IDLE; -- it must NOT reset, until ack has done reading the fifo
							end if;
						when PREAMBLE =>
							ack_state	<= ADDR;
						when ADDR	=>
							if (sc_pkt_info.sc_type(0) = '1') then 
								ack_state	<= WR_ACK;
							else
								ack_state	<= RD_ACK;
							end if;
						when RD_ACK =>
							if (read_ack_almostdone = '1') then
								ack_state	<= TRAILER;
							end if;
						when WR_ACK =>					
							ack_state	<= TRAILER;
						when TRAILER =>
							ack_state	<= RESET;
						when RESET =>
							ack_state	<= IDLE;
						when others =>
							ack_state	<= RESET;
					end case;
				when others =>
					-- do nothing 
					-- illegal state, the main fsm will move it back to RESET, thus reset everything
			end case;
		end if;
	end process proc_fsm_regs;

	-- Avalon transaction handler (co-process as the main fsm)
	
	proc_wr_fifo2avmm_logic : process(all)
	begin -- the rdreq must be in sync with waitrequest, so no latency from the get from fifo to data available on bus
		if (burst_write_avstart = '1') then -- when avalon transaction starts
			if (wr_trans_done = '0') then
				avm_m0_writedata		<= wr_fifo_dout;
				if (wr_fifo_empty /= '1') then
					avm_m0_write		<= '1';
						if (avm_m0_waitrequest	= '0') then
							wr_fifo_rdreq	<= '1';
						else
							wr_fifo_rdreq	<= '0';
						end if;
				else
					avm_m0_write		<= '0';
					wr_fifo_rdreq		<= '0';
				end if;
			else -- transaction is completed as words are all transmitted
				avm_m0_writedata		<= (others=>'0');
				wr_fifo_rdreq			<= '0';
				avm_m0_write			<= '0';
			end if;
		else -- when the avalon transaction is permanently done
			avm_m0_writedata		<= (others=>'0');
			wr_fifo_rdreq			<= '0';
			avm_m0_write			<= '0';
		end if;
	end process proc_wr_fifo2avmm_logic;
	
	proc_read_write_trans : process(i_clk,i_rst)
	begin
		if (i_rst = '1') then
			sc_hub_reset_done		<= '0';
		elsif rising_edge(i_clk) then 
			case ath_state is 
				when AV_RD => 
					wr_fifo_sclr		<= '0';
					rd_fifo_sclr		<= '0';
					avm_m0_address		<= conv_std_logic_vector(to_integer(unsigned(sc_pkt_info.start_address)), avm_m0_address'length);
					avm_m0_burstcount	<= sc_pkt_info.rw_length(8 downto 0);
					read_avstart		<= '1';
					if (read_avstart = '1' and avm_m0_waitrequest = '1' and av_rd_cmd_send_done = '0') then
						avm_m0_read			<= '1'; -- high for one cycle after read start
					elsif (read_avstart = '1' and avm_m0_waitrequest = '0') then
						avm_m0_read				<= '0';
						av_rd_cmd_send_done		<= '1'; -- ack of the qsys that read command is sent
					else 
						avm_m0_read			<= '0';
					end if;
					if (to_integer(unsigned(rd_trans_cnt))	< to_integer(unsigned(sc_pkt_info.rw_length))) then
						if (rd_fifo_full /= '1' and avm_m0_readdatavalid = '1') then -- read fifo captured
							rd_trans_cnt		<= conv_std_logic_vector(to_integer(unsigned(rd_trans_cnt))+1, rd_trans_cnt'length);
							rd_fifo_wrreq		<= '1';
							rd_fifo_din			<= avm_m0_readdata;
							rd_timeout_cnt		<= (others=>'0'); -- remember to feed to dog for each read word received
						else -- halt for qsys to send the read word
							rd_timeout_cnt		<= conv_std_logic_vector(to_integer(unsigned(rd_timeout_cnt))+1, rd_timeout_cnt'length);
							rd_trans_cnt		<= rd_trans_cnt;
							rd_fifo_wrreq		<= '0';
							rd_fifo_din			<= (others=>'0');
						end if;
						rd_trans_done		<= '0';
					else
						rd_fifo_wrreq		<= '0';
						rd_fifo_din			<= (others=>'0');
						rd_trans_done		<= '1';
					end if;
					if (to_integer(unsigned(rd_timeout_cnt)) >= 200) then -- if the qsys does not response for a read
						rd_trans_terminated	<= '1';
					end if;
				when AV_WR =>
					wr_fifo_sclr		<= '0';
					rd_fifo_sclr		<= '0';
					avm_m0_address			<= conv_std_logic_vector(to_integer(unsigned(sc_pkt_info.start_address)), avm_m0_address'length);	
					avm_m0_burstcount		<= sc_pkt_info.rw_length(8 downto 0);	
					burst_write_avstart	<= '1';
					if (to_integer(unsigned(wr_trans_cnt)) < to_integer(unsigned(sc_pkt_info.rw_length))) then
						if (wr_fifo_rdreq = '1') then -- counter for tracking the consumed words
							wr_trans_cnt			<= conv_std_logic_vector(to_integer(unsigned(wr_trans_cnt))+1, wr_trans_cnt'length);
						end if; 
						-- write timeout should be monitored outside of master with a seperate timeout bridge
					else			
						wr_trans_done						<= '1';					
					end if;
				when RESET => 
					avm_m0_read				<= '0';
					read_avstart			<= '0';
					av_rd_cmd_send_done		<= '0';
					burst_write_avstart		<= '0';
					write_av_waitforcomp	<= '0';
					wr_trans_done			<= '0';
					rd_trans_done			<= '0';
					wr_trans_cnt			<= (others => '0');
					avm_m0_address			<= (others => '0');
					avm_m0_burstcount		<= (others => '0');
					rd_trans_cnt			<= (others => '0');
					wr_fifo_sclr			<= '1';
					rd_fifo_sclr			<= '1';
					rd_fifo_wrreq			<= '0';
					rd_timeout_cnt			<= (others => '0');
					if (wr_fifo_empty = '1') then
						sc_hub_reset_done <= '1';
					else
						sc_hub_reset_done <= '0';
					end if;
				when IDLE =>
					rd_trans_terminated		<= '0'; -- clear the flag here
					sc_hub_reset_done		<= '0';
					wr_fifo_sclr			<= '0';
					rd_fifo_sclr			<= '0';
				when others =>
					-- illegal state 
					-- calls the main fsm to move on the av read/write, thus reset everything
					rd_trans_terminated	<= '1';
			end case;	
		end if;
	end process proc_read_write_trans;
	
-- === part 2: REPLYING the commands

	proc_rd_fifo2acklink_logic : process(all)
	begin
		if (read_ack_flow = S2) then -- be mindful: this state is comb out!
			if (to_integer(unsigned(rd_ack_word_cnt)) <= to_integer(unsigned(sc_pkt_info.rw_length))-1) then
				if (rd_fifo_empty /= '1') then
					link_data_comb		<= rd_fifo_dout;
					link_datak_comb		<= "0000";
					link_en_comb		<= '1';				
				else -- fifo underflow, error!
					link_data_comb(31 downto 8)		<= (others => '0'); -- send comma word
					link_data_comb(7 downto 0)		<= K237; -- send control error word
					link_datak_comb					<= "0001";
					link_en_comb					<= '1';			
				end if;
			else -- send to link is finished as word count depleted (this should not be seen by the link)
				link_data_comb(31 downto 8)		<= (others => '0'); -- send comma word
				link_data_comb(7 downto 0)		<= K285;
				link_datak_comb					<= "0001";
				link_en_comb					<= '0';		
			end if;
		else -- when ack_state is not sending read words (this should not be seen by the link)
			link_data_comb(31 downto 8)	<= (others => '0'); -- send comma word
			link_data_comb(7 downto 0)		<= K285;
			link_datak_comb					<= "0001";
			link_en_comb					<= '0';	
		end if;	
		if (to_integer(unsigned(rd_ack_word_cnt)) = to_integer(unsigned(sc_pkt_info.rw_length))-1) then
			-- almost finish read fifo
			-- comb out of S2 which should push the timing one cycle earlier
			if (rd_fifo_empty /= '1') then
				read_ack_almostdone	<= '1';
			else 
				read_ack_almostdone	<= '0';
			end if;
		else
			read_ack_almostdone	<= '0';
		end if;
	end process proc_rd_fifo2acklink_logic;
	
	proc_ack_fsm_regs : process(i_clk,i_rst)
	begin
		if (i_rst = '1') then
		
		elsif rising_edge(i_clk) then 
			case ack_state is
				when PREAMBLE =>
					link_eop					<= '0';
					if (send_preamble_done = '0') then
						link_data				<= "000111" & sc_pkt_info.sc_type & sc_pkt_info.fpga_id & K285;
						link_datak				<= "0001";
						link_en					<= '1';
						link_sop				<= '1';
						send_preamble_done	<= '1';
					else
						link_en					<= '0'; -- toggle the link_en
						link_sop				<= '0';
					end if;
				when ADDR =>
					link_sop					<= '0';
					if (send_addr_done = '0') then
						link_data(23 downto 0) 		<= sc_pkt_info.start_address;
						link_data(31 downto 24)		<= (others=>'0');
						link_datak					<= "0000";
						link_en						<= '1';
						send_addr_done				<= '1';
					else
						link_en		<= '0'; -- toggle the link_en 
					end if;
					if (rd_trans_done = '1') then
						read_ack_flow	<= S1;
					end if;
				when RD_ACK => 
					case read_ack_flow is
						when S1 =>
							link_data(15 downto 0)		<= sc_pkt_info.rw_length;
							link_data(16)				<= '1';
							link_data(31 downto 17)		<= (others=>'0');
							link_datak					<= "0000";
							link_en						<= '1';
							read_ack_flow				<= S2;
						when S2 =>
							rd_ack_start				<= '1';
							if (rd_fifo_empty /= '1') then
								rd_ack_word_cnt				<= conv_std_logic_vector(to_integer(unsigned(rd_ack_word_cnt)) + 1, rd_ack_word_cnt'length);
							end if;
							link_data					<= link_data_comb;
							link_datak					<= link_datak_comb;
							link_en 					<= link_en_comb;
							if (to_integer(unsigned(rd_ack_word_cnt)) = to_integer(unsigned(sc_pkt_info.rw_length))-1) then
								-- almost finish read fifo
								read_ack_flow	<= S2;
								read_ack_done	<= '0';
								if (rd_fifo_empty /= '1') then
									rd_fifo_rdreq		<= '1';
								else 
									rd_fifo_rdreq		<= '0';
								end if;
							elsif (to_integer(unsigned(rd_ack_word_cnt)) > to_integer(unsigned(sc_pkt_info.rw_length))-1) then
								-- finish read fifo
								read_ack_flow	<= IDLE;
								read_ack_done	<= '1';
								rd_fifo_rdreq	<= '0';
							else 
								-- reading fifo
								read_ack_flow	<= S2;
								read_ack_done	<= '0';
								if (rd_fifo_empty /= '1') then
									rd_fifo_rdreq		<= '1';
								else 
									rd_fifo_rdreq		<= '0';
								end if;
							end if;
						when IDLE =>
							link_en				<= '0';
							rd_fifo_rdreq		<= '0';
						when others => 
							-- illegal state
							-- do nothing, but fake read_ack_done to move on
							link_en				<= '0';
							rd_fifo_rdreq		<= '0';
							read_ack_done		<= '0';
					end case;
				when WR_ACK =>
					if (send_write_reply_done = '0') then 
						link_data(15 downto 0)		<= sc_pkt_info.rw_length;
						link_data(16)					<= '1';
						link_data(31 downto 17)		<= (others=>'0');
						link_datak	<= "0000";
						link_en		<= '1';
						send_write_reply_done	<= '1';
					elsif (send_write_reply_done = '1') then
						link_en		<= '0'; -- toggle the link_en 
					end if;
				when TRAILER =>
					if (send_trailer_done = '0') then
						link_eop								<= '1';
						link_data(7 downto 0)			<= K284;
						link_data(31 downto 8)			<= (others=>'0');
						link_datak							<= "0001";
						link_en								<= '1';
						send_trailer_done					<= '1';
					elsif (send_trailer_done = '1') then
						link_eop								<= '0';
						link_en								<= '0'; -- toggle the link_en 
					end if;
				when RESET =>
					link_sop						<= '0';
					link_eop						<= '0';
					rd_ack_start				<= '0';
					rd_ack_word_cnt			<= (others=>'0');
					send_preamble_done		<= '0';
					link_data					<= (others=>'0');
					link_datak					<= (others=>'0');
					link_en						<= '0';
					send_addr_done				<= '0';
					read_ack_done				<= '0';
					send_write_reply_done	<= '0';
					send_trailer_done			<= '0';
					read_ack_flow				<= IDLE;
					rd_fifo_rdreq				<= '0';
				when IDLE =>
					link_sop						<= '0';
					link_eop						<= '0';
					link_en						<= '0';
					read_ack_done				<= '0';
					send_write_reply_done	<= '0';
					read_ack_flow				<= IDLE;
				when others =>
					-- illegal state
					-- fake send_trailer_done and the main fsm will move on
					link_en				<= '0';
					send_trailer_done	<= '1';
			end case;
		end if;
	end process proc_ack_fsm_regs;
		
-- === some utilities

	proc_preamble_det : process(all)
	begin
		if (i_linkin_data(31 downto 26)="000111" and i_linkin_data(7 downto 0)=K285 and i_linkin_datak="0001") then
			isPreamble <= '1';
		else 
			isPreamble	<= '0';
		end if;                                                                                                    
	end process proc_preamble_det;
	
	proc_skip_word_det : process(all)
	begin 
		if (i_linkin_data = skipWord_charac and i_linkin_datak="0001") then
			isSkipWord <= '1';
		else
			isSkipWord	<= '0';
		end if;
	end process proc_skip_word_det;
	
end architecture rtl;

