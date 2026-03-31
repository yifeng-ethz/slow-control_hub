alt_fifo_w40d512_inst : alt_fifo_w40d512 PORT MAP (
		clock	 => clock_sig,
		data	 => data_sig,
		rdreq	 => rdreq_sig,
		sclr	 => sclr_sig,
		wrreq	 => wrreq_sig,
		empty	 => empty_sig,
		full	 => full_sig,
		q	 => q_sig,
		usedw	 => usedw_sig
	);
