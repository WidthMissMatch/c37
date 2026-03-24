library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.MATH_REAL.ALL;
use STD.TEXTIO.ALL;

entity tb_system_5cycle_hardcoded is
end tb_system_5cycle_hardcoded;

architecture behavioral of tb_system_5cycle_hardcoded is

    constant CLK_PERIOD     : time := 10 ns;
    constant SAMPLE_RATE    : integer := 15000;
    constant GRID_FREQ      : real := 50.0;
    constant SAMPLES_PER_CYC: integer := 300;
    constant NUM_CYCLES     : integer := 5;
    constant TOTAL_SAMPLES  : integer := SAMPLES_PER_CYC * NUM_CYCLES;
    constant INTER_SAMPLE_CLKS : integer := 6667;

    constant V_AMPLITUDE    : real := 10000.0;
    constant I_AMPLITUDE    : real := 5000.0;

    constant EXPECTED_PKT_WORDS : integer := 19;
    constant SYNC_FRAMESIZE     : std_logic_vector(31 downto 0) := x"AA01004C";
    constant EXPECTED_STAT      : std_logic_vector(15 downto 0) := x"C010";

    constant FREQ_50HZ_Q16  : std_logic_vector(31 downto 0) := x"00320000";
    constant FREQ_51HZ_Q16  : std_logic_vector(31 downto 0) := x"00330000";
    constant FREQ_49HZ_Q16  : std_logic_vector(31 downto 0) := x"00310000";

    signal clk  : std_logic := '0';
    signal rst  : std_logic := '1';

    signal enable           : std_logic := '0';
    signal s_axis_tdata     : std_logic_vector(127 downto 0) := (others => '0');
    signal s_axis_tvalid    : std_logic := '0';
    signal s_axis_tlast     : std_logic := '0';
    signal s_axis_tready    : std_logic;

    signal m_axis_tdata     : std_logic_vector(31 downto 0);
    signal m_axis_tvalid    : std_logic;
    signal m_axis_tready    : std_logic := '1';
    signal m_axis_tlast     : std_logic;

    signal sync_locked      : std_logic;
    signal input_packets_good : std_logic_vector(31 downto 0);
    signal input_packets_bad  : std_logic_vector(31 downto 0);
    signal output_packets   : std_logic_vector(31 downto 0);
    signal processing_active: std_logic;
    signal system_ready     : std_logic;
    signal frequency_out    : std_logic_vector(31 downto 0);
    signal freq_valid       : std_logic;
    signal rocof_out        : std_logic_vector(31 downto 0);
    signal rocof_valid      : std_logic;
    signal channels_extracted : std_logic_vector(31 downto 0);
    signal dft_busy         : std_logic;
    signal cordic_busy      : std_logic;

    signal stimulus_done    : boolean := false;

    signal pkt_word_count   : integer := 0;
    signal pkt_total_count  : integer := 0;
    signal pkt_words        : std_logic_vector(19*32-1 downto 0) := (others => '0');
    signal pkt_complete     : boolean := false;

    signal test1_pass       : boolean := false;
    signal test2_pass       : boolean := false;
    signal test3_pass       : boolean := false;

    signal hann_sample_in    : std_logic_vector(15 downto 0) := (others => '0');
    signal hann_sample_index : std_logic_vector(7 downto 0) := (others => '0');
    signal hann_sample_valid : std_logic := '0';
    signal hann_sample_out   : std_logic_vector(15 downto 0);
    signal hann_out_valid    : std_logic;
    signal hann_index_out    : std_logic_vector(7 downto 0);
    signal hann_coeff_out    : std_logic_vector(15 downto 0);
    signal hann_done         : boolean := false;
    signal hann_errors       : integer := 0;

    signal fd_freq_in        : std_logic_vector(31 downto 0) := FREQ_50HZ_Q16;
    signal fd_freq_valid     : std_logic := '0';
    signal fd_freq_out       : std_logic_vector(31 downto 0);
    signal fd_freq_out_valid : std_logic;
    signal fd_diff_out       : std_logic_vector(31 downto 0);
    signal fd_initialized    : std_logic;
    signal fd_done           : boolean := false;
    signal fd_errors         : integer := 0;

    component pmu_system_complete_256 is
        port (
            clk               : in  std_logic;
            rst               : in  std_logic;
            s_axis_tdata      : in  std_logic_vector(127 downto 0);
            s_axis_tvalid     : in  std_logic;
            s_axis_tlast      : in  std_logic;
            s_axis_tready     : out std_logic;
            m_axis_tdata      : out std_logic_vector(31 downto 0);
            m_axis_tvalid     : out std_logic;
            m_axis_tready     : in  std_logic;
            m_axis_tlast      : out std_logic;
            enable            : in  std_logic;
            sync_locked       : out std_logic;
            input_packets_good: out std_logic_vector(31 downto 0);
            input_packets_bad : out std_logic_vector(31 downto 0);
            output_packets    : out std_logic_vector(31 downto 0);
            processing_active : out std_logic;
            system_ready      : out std_logic;
            frequency_out     : out std_logic_vector(31 downto 0);
            freq_valid        : out std_logic;
            rocof_out         : out std_logic_vector(31 downto 0);
            rocof_valid       : out std_logic;
            channels_extracted: out std_logic_vector(31 downto 0);
            dft_busy          : out std_logic;
            cordic_busy       : out std_logic
        );
    end component;

    component hann_window is
        generic (
            WINDOW_SIZE  : integer := 256;
            SAMPLE_WIDTH : integer := 16;
            COEFF_WIDTH  : integer := 16
        );
        port (
            clk             : in  std_logic;
            rst             : in  std_logic;
            sample_in       : in  std_logic_vector(15 downto 0);
            sample_index    : in  std_logic_vector(7 downto 0);
            sample_valid    : in  std_logic;
            sample_out      : out std_logic_vector(15 downto 0);
            sample_out_valid: out std_logic;
            index_out       : out std_logic_vector(7 downto 0);
            coeff_out       : out std_logic_vector(15 downto 0)
        );
    end component;

    component freq_damping_filter is
        generic (
            FREQ_WIDTH : integer := 32;
            ALPHA      : integer := 19661
        );
        port (
            clk           : in  std_logic;
            rst           : in  std_logic;
            freq_in       : in  std_logic_vector(31 downto 0);
            freq_valid    : in  std_logic;
            freq_out      : out std_logic_vector(31 downto 0);
            freq_out_valid: out std_logic;
            freq_init     : in  std_logic_vector(31 downto 0);
            diff_out      : out std_logic_vector(31 downto 0);
            initialized   : out std_logic
        );
    end component;

    function real_to_slv16(val : real) return std_logic_vector is
        variable int_val : integer;
    begin
        if val >= 32767.0 then
            int_val := 32767;
        elsif val <= -32768.0 then
            int_val := -32768;
        else
            int_val := integer(val);
        end if;
        return std_logic_vector(to_signed(int_val, 16));
    end function;

begin

    clk <= not clk after CLK_PERIOD / 2;

    dut: pmu_system_complete_256
        port map (
            clk                => clk,
            rst                => rst,
            s_axis_tdata       => s_axis_tdata,
            s_axis_tvalid      => s_axis_tvalid,
            s_axis_tlast       => s_axis_tlast,
            s_axis_tready      => s_axis_tready,
            m_axis_tdata       => m_axis_tdata,
            m_axis_tvalid      => m_axis_tvalid,
            m_axis_tready      => m_axis_tready,
            m_axis_tlast       => m_axis_tlast,
            enable             => enable,
            sync_locked        => sync_locked,
            input_packets_good => input_packets_good,
            input_packets_bad  => input_packets_bad,
            output_packets     => output_packets,
            processing_active  => processing_active,
            system_ready       => system_ready,
            frequency_out      => frequency_out,
            freq_valid         => freq_valid,
            rocof_out          => rocof_out,
            rocof_valid        => rocof_valid,
            channels_extracted => channels_extracted,
            dft_busy           => dft_busy,
            cordic_busy        => cordic_busy
        );

    hann_inst: hann_window
        generic map (
            WINDOW_SIZE  => 256,
            SAMPLE_WIDTH => 16,
            COEFF_WIDTH  => 16
        )
        port map (
            clk              => clk,
            rst              => rst,
            sample_in        => hann_sample_in,
            sample_index     => hann_sample_index,
            sample_valid     => hann_sample_valid,
            sample_out       => hann_sample_out,
            sample_out_valid => hann_out_valid,
            index_out        => hann_index_out,
            coeff_out        => hann_coeff_out
        );

    fd_inst: freq_damping_filter
        generic map (
            FREQ_WIDTH => 32,
            ALPHA      => 19661
        )
        port map (
            clk            => clk,
            rst            => rst,
            freq_in        => fd_freq_in,
            freq_valid     => fd_freq_valid,
            freq_out       => fd_freq_out,
            freq_out_valid => fd_freq_out_valid,
            freq_init      => FREQ_50HZ_Q16,
            diff_out       => fd_diff_out,
            initialized    => fd_initialized
        );

    reset_proc: process
    begin
        rst <= '1';
        enable <= '0';
        wait for 200 ns;
        rst <= '0';
        wait for 100 ns;
        enable <= '1';
        wait;
    end process;

    stimulus_proc: process
        variable theta      : real;
        variable v1, v2, v3 : real;
        variable i1, i2, i3 : real;
        variable ch0_slv, ch1_slv, ch2_slv : std_logic_vector(15 downto 0);
        variable ch3_slv, ch4_slv, ch5_slv : std_logic_vector(15 downto 0);
        variable pkt        : std_logic_vector(127 downto 0);
    begin

        wait until rst = '0';
        wait until rising_edge(clk);
        wait for 200 ns;

        report "========================================";
        report "TEST 1: Full System - 5 Cycle Input Stimulus";
        report "  Total samples: " & integer'image(TOTAL_SAMPLES);
        report "  Inter-sample gap: " & integer'image(INTER_SAMPLE_CLKS) & " clocks";
        report "========================================";

        for n in 0 to TOTAL_SAMPLES - 1 loop

            theta := MATH_2_PI * real(n) / real(SAMPLES_PER_CYC);

            v1 := V_AMPLITUDE * sin(theta);
            v2 := V_AMPLITUDE * sin(theta - MATH_2_PI / 3.0);
            v3 := V_AMPLITUDE * sin(theta + MATH_2_PI / 3.0);

            i1 := I_AMPLITUDE * sin(theta);
            i2 := I_AMPLITUDE * sin(theta - MATH_2_PI / 3.0);
            i3 := I_AMPLITUDE * sin(theta + MATH_2_PI / 3.0);

            ch0_slv := real_to_slv16(v1);
            ch1_slv := real_to_slv16(v2);
            ch2_slv := real_to_slv16(v3);
            ch3_slv := real_to_slv16(i1);
            ch4_slv := real_to_slv16(i2);
            ch5_slv := real_to_slv16(i3);

            pkt(127 downto 120) := x"AA";
            pkt(119 downto 104) := ch0_slv;
            pkt(103 downto 88)  := ch1_slv;
            pkt(87 downto 72)   := ch2_slv;
            pkt(71 downto 56)   := ch3_slv;
            pkt(55 downto 40)   := ch4_slv;
            pkt(39 downto 24)   := ch5_slv;
            pkt(23 downto 16)   := x"55";
            pkt(15 downto 0)    := x"0000";

            s_axis_tdata  <= pkt;
            s_axis_tvalid <= '1';
            s_axis_tlast  <= '1';

            wait until rising_edge(clk) and s_axis_tready = '1';

            s_axis_tvalid <= '0';
            s_axis_tlast  <= '0';

            for j in 0 to INTER_SAMPLE_CLKS - 2 loop
                wait until rising_edge(clk);
            end loop;

            if (n + 1) mod 300 = 0 then
                report "[STIMULUS] Cycle " & integer'image((n + 1) / 300) &
                       "/5 complete (" & integer'image(n + 1) & " packets sent)" &
                       " | Good=" & integer'image(to_integer(unsigned(input_packets_good))) &
                       " Bad=" & integer'image(to_integer(unsigned(input_packets_bad))) &
                       " Output=" & integer'image(to_integer(unsigned(output_packets)));
            end if;

        end loop;

        report "[STIMULUS] All 1500 packets transmitted. Waiting for pipeline flush...";
        stimulus_done <= true;
        wait;
    end process;

    output_monitor: process
        variable word_count : integer := 0;
        variable total_pkts : integer := 0;
        variable word0_ok   : boolean;
        variable stat_ok    : boolean;
        variable mag_ch1    : std_logic_vector(31 downto 0);
        variable freq_ch1   : std_logic_vector(31 downto 0);
        variable crc_word   : std_logic_vector(31 downto 0);
        variable all_pkts_ok: boolean := true;
    begin
        wait until rst = '0';

        loop
            wait until rising_edge(clk);

            if m_axis_tvalid = '1' and m_axis_tready = '1' then

                if word_count < 19 then
                    pkt_words((19 - word_count) * 32 - 1 downto (18 - word_count) * 32)
                        <= m_axis_tdata;
                end if;

                case word_count is
                    when 0 =>
                        word0_ok := (m_axis_tdata = SYNC_FRAMESIZE);
                        if not word0_ok then
                            report "[OUTPUT] ERROR: Word 0 = " &
                                   integer'image(to_integer(unsigned(m_axis_tdata))) &
                                   ", expected 0xAA01004C" severity warning;
                        end if;

                    when 3 =>
                        stat_ok := (m_axis_tdata(31 downto 16) = EXPECTED_STAT);
                        if not stat_ok then
                            report "[OUTPUT] ERROR: STAT = " &
                                   integer'image(to_integer(unsigned(m_axis_tdata(31 downto 16)))) &
                                   ", expected 0xC010" severity warning;
                        end if;

                    when 4 =>
                        mag_ch1 := m_axis_tdata;

                    when 6 =>
                        freq_ch1 := m_axis_tdata;

                    when others =>
                        null;
                end case;

                word_count := word_count + 1;

                if m_axis_tlast = '1' then
                    total_pkts := total_pkts + 1;
                    pkt_total_count <= total_pkts;

                    crc_word := m_axis_tdata;

                    report "========================================";
                    report "[OUTPUT] Packet #" & integer'image(total_pkts) & " received:";
                    report "  Words: " & integer'image(word_count) &
                           " (expected " & integer'image(EXPECTED_PKT_WORDS) & ")";
                    report "  Word0 (SYNC+SIZE): " &
                           integer'image(to_integer(unsigned(pkt_words(19*32-1 downto 18*32))));
                    report "  Magnitude Ch1: " & integer'image(to_integer(unsigned(mag_ch1)));
                    report "  Frequency Ch1 (Q16.16): " & integer'image(to_integer(signed(freq_ch1)));
                    report "  CRC word: " & integer'image(to_integer(unsigned(crc_word)));

                    if word_count /= EXPECTED_PKT_WORDS then
                        report "  FAIL: Wrong word count!" severity warning;
                        all_pkts_ok := false;
                    end if;
                    if not word0_ok then
                        report "  FAIL: Bad SYNC/FRAMESIZE!" severity warning;
                        all_pkts_ok := false;
                    end if;
                    if not stat_ok then
                        report "  FAIL: Bad STAT field!" severity warning;
                        all_pkts_ok := false;
                    end if;
                    if mag_ch1 = x"00000000" then
                        report "  WARN: Ch1 magnitude is zero" severity warning;
                    end if;

                    report "========================================";

                    word_count := 0;
                end if;
            end if;

            if stimulus_done and total_pkts > 0 then

                wait for 50 ms;
                test1_pass <= all_pkts_ok and (total_pkts > 0);
                report "[TEST 1] System test: " & integer'image(total_pkts) &
                       " output packets received";
                if all_pkts_ok and total_pkts > 0 then
                    report "[TEST 1] PASSED: All output packets have correct structure";
                else
                    report "[TEST 1] FAILED" severity warning;
                end if;
                exit;
            end if;
        end loop;

        wait;
    end process;

    hann_test_proc: process
        variable theta_h     : real;
        variable sample_real : real;
        variable sample_int  : integer;
        variable out_count   : integer := 0;
        variable err_count   : integer := 0;
        variable out_val     : integer;
        variable idx_val     : integer;
    begin
        wait until rst = '0';
        wait for 500 ns;

        report "========================================";
        report "TEST 2: Hann Window Standalone Test";
        report "  Feeding 256 sine samples with indices";
        report "========================================";

        for n in 0 to 255 loop
            theta_h := MATH_2_PI * real(n) / 256.0;
            sample_real := 10000.0 * sin(theta_h);

            if sample_real >= 32767.0 then
                sample_int := 32767;
            elsif sample_real <= -32768.0 then
                sample_int := -32768;
            else
                sample_int := integer(sample_real);
            end if;

            hann_sample_in    <= std_logic_vector(to_signed(sample_int, 16));
            hann_sample_index <= std_logic_vector(to_unsigned(n, 8));
            hann_sample_valid <= '1';
            wait until rising_edge(clk);
            hann_sample_valid <= '0';

            wait until rising_edge(clk);
            wait until rising_edge(clk);

            if hann_out_valid = '1' then
                out_count := out_count + 1;
                out_val := to_integer(signed(hann_sample_out));
                idx_val := to_integer(unsigned(hann_index_out));

                if idx_val = 0 and out_val /= 0 then
                    report "[HANN] ERROR: index 0 output should be 0, got " &
                           integer'image(out_val) severity warning;
                    err_count := err_count + 1;
                end if;

                if idx_val = 64 then
                    if out_val < 4500 or out_val > 5500 then
                        report "[HANN] ERROR: index 64 expected ~5000, got " &
                               integer'image(out_val) severity warning;
                        err_count := err_count + 1;
                    else
                        report "[HANN] OK: index 64 output = " & integer'image(out_val) &
                               " (expected ~5000)";
                    end if;
                end if;

                if n mod 32 = 0 then
                    report "[HANN] idx=" & integer'image(idx_val) &
                           " in=" & integer'image(sample_int) &
                           " coeff=" & integer'image(to_integer(signed(hann_coeff_out))) &
                           " out=" & integer'image(out_val);
                end if;
            end if;
        end loop;

        wait until rising_edge(clk);
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        wait until rising_edge(clk);

        hann_errors <= err_count;
        hann_done <= true;

        report "========================================";
        report "[TEST 2] Hann Window: " & integer'image(out_count) & " outputs, " &
               integer'image(err_count) & " errors";
        if err_count = 0 and out_count > 200 then
            report "[TEST 2] PASSED";
            test2_pass <= true;
        else
            report "[TEST 2] FAILED" severity warning;
            test2_pass <= false;
        end if;
        report "========================================";

        wait;
    end process;

    fd_test_proc: process
        variable out_count   : integer := 0;
        variable err_count   : integer := 0;
        variable freq_val    : integer;
        variable settled_ok  : boolean := false;
        variable prev_freq   : integer := 0;
        variable target_q16  : integer;
    begin
        wait until rst = '0';
        wait for 500 ns;

        report "========================================";
        report "TEST 3: Frequency Damping Filter Test";
        report "  Step: 50 Hz -> 51 Hz -> 49 Hz -> 50 Hz";
        report "  ALPHA = 0.3 (19661 in Q0.16)";
        report "========================================";

        report "[FD] Phase 1: Initialize at 50 Hz";
        for n in 0 to 4 loop
            fd_freq_in <= FREQ_50HZ_Q16;
            fd_freq_valid <= '1';
            wait until rising_edge(clk);
            fd_freq_valid <= '0';

            for w in 0 to 5 loop
                wait until rising_edge(clk);
                if fd_freq_out_valid = '1' then
                    freq_val := to_integer(signed(fd_freq_out));
                    report "[FD] Init sample " & integer'image(n) &
                           ": out = " & integer'image(freq_val) &
                           " (Q16.16, ~" & integer'image(freq_val / 65536) & " Hz)";
                    out_count := out_count + 1;
                    exit;
                end if;
            end loop;
        end loop;

        report "[FD] Phase 2: Step to 51 Hz";
        target_q16 := to_integer(signed(FREQ_51HZ_Q16));
        for n in 0 to 9 loop
            fd_freq_in <= FREQ_51HZ_Q16;
            fd_freq_valid <= '1';
            wait until rising_edge(clk);
            fd_freq_valid <= '0';

            for w in 0 to 5 loop
                wait until rising_edge(clk);
                if fd_freq_out_valid = '1' then
                    freq_val := to_integer(signed(fd_freq_out));
                    report "[FD] Step51 sample " & integer'image(n) &
                           ": out = " & integer'image(freq_val) &
                           " (delta from 51Hz = " & integer'image(target_q16 - freq_val) & ")";
                    out_count := out_count + 1;

                    if n >= 8 then
                        if abs(freq_val - target_q16) < 3277 then
                            settled_ok := true;
                        end if;
                    end if;

                    if n > 0 and prev_freq /= 0 then
                        if abs(freq_val - target_q16) > abs(prev_freq - target_q16) then
                            report "[FD] WARNING: Non-monotonic convergence at sample " &
                                   integer'image(n) severity warning;
                        end if;
                    end if;
                    prev_freq := freq_val;
                    exit;
                end if;
            end loop;
        end loop;

        if not settled_ok then
            report "[FD] ERROR: Filter did not settle to 51 Hz after 10 samples" severity warning;
            err_count := err_count + 1;
        else
            report "[FD] OK: Filter settled to ~51 Hz";
        end if;

        report "[FD] Phase 3: Step to 49 Hz";
        target_q16 := to_integer(signed(FREQ_49HZ_Q16));
        settled_ok := false;
        for n in 0 to 11 loop
            fd_freq_in <= FREQ_49HZ_Q16;
            fd_freq_valid <= '1';
            wait until rising_edge(clk);
            fd_freq_valid <= '0';

            for w in 0 to 5 loop
                wait until rising_edge(clk);
                if fd_freq_out_valid = '1' then
                    freq_val := to_integer(signed(fd_freq_out));
                    report "[FD] Step49 sample " & integer'image(n) &
                           ": out = " & integer'image(freq_val) &
                           " (delta from 49Hz = " & integer'image(target_q16 - freq_val) & ")";
                    out_count := out_count + 1;

                    if n >= 8 then
                        if abs(freq_val - target_q16) < 3277 then
                            settled_ok := true;
                        end if;
                    end if;
                    exit;
                end if;
            end loop;
        end loop;

        if not settled_ok then
            report "[FD] ERROR: Filter did not settle to 49 Hz" severity warning;
            err_count := err_count + 1;
        else
            report "[FD] OK: Filter settled to ~49 Hz";
        end if;

        fd_errors <= err_count;
        fd_done <= true;

        report "========================================";
        report "[TEST 3] Freq Damping: " & integer'image(out_count) & " outputs, " &
               integer'image(err_count) & " errors";
        if err_count = 0 and out_count > 15 then
            report "[TEST 3] PASSED";
            test3_pass <= true;
        else
            report "[TEST 3] FAILED" severity warning;
            test3_pass <= false;
        end if;
        report "========================================";

        wait;
    end process;

    status_monitor: process
    begin
        wait until enable = '1';
        wait for 10 ms;

        loop
            report "--- STATUS @ " & time'image(now) & " ---" &
                   " SyncLock=" & std_logic'image(sync_locked) &
                   " Good=" & integer'image(to_integer(unsigned(input_packets_good))) &
                   " Bad=" & integer'image(to_integer(unsigned(input_packets_bad))) &
                   " OutPkts=" & integer'image(to_integer(unsigned(output_packets))) &
                   " DFT=" & std_logic'image(dft_busy) &
                   " CORDIC=" & std_logic'image(cordic_busy);
            wait for 20 ms;

            if stimulus_done then
                wait for 50 ms;
                exit;
            end if;
        end loop;

        wait;
    end process;

    final_report: process
    begin

        wait for 200 ms;

        report "";
        report "################################################################";
        report "#                    FINAL TEST SUMMARY                        #";
        report "################################################################";
        report "";
        report "  TEST 1 - System End-to-End (5 cycles -> 76-byte packets):";
        report "    Input packets sent: 1500";
        report "    Good packets: " & integer'image(to_integer(unsigned(input_packets_good)));
        report "    Bad packets:  " & integer'image(to_integer(unsigned(input_packets_bad)));
        report "    Output C37.118 packets: " & integer'image(pkt_total_count);
        if test1_pass then
            report "    Result: PASSED";
        else
            if pkt_total_count > 0 then
                report "    Result: PARTIAL (packets received but some checks failed)";
            else
                report "    Result: FAILED (no output packets)";
            end if;
        end if;
        report "";
        report "  TEST 2 - Hann Window (standalone):";
        report "    Errors: " & integer'image(hann_errors);
        if test2_pass then
            report "    Result: PASSED";
        elsif hann_done then
            report "    Result: FAILED";
        else
            report "    Result: DID NOT COMPLETE";
        end if;
        report "";
        report "  TEST 3 - Frequency Damping Filter (standalone):";
        report "    Errors: " & integer'image(fd_errors);
        if test3_pass then
            report "    Result: PASSED";
        elsif fd_done then
            report "    Result: FAILED";
        else
            report "    Result: DID NOT COMPLETE";
        end if;
        report "";
        report "################################################################";

        if test1_pass and test2_pass and test3_pass then
            report ">>> ALL TESTS PASSED <<<";
        else
            report ">>> SOME TESTS FAILED <<<" severity warning;
        end if;

        report "################################################################";
        report "";

        assert false report "Simulation finished." severity failure;
        wait;
    end process;

end behavioral;
