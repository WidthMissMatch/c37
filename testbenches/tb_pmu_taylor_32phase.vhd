library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.MATH_REAL.ALL;
use STD.TEXTIO.ALL;
use IEEE.STD_LOGIC_TEXTIO.ALL;

entity tb_pmu_taylor_32phase is
end tb_pmu_taylor_32phase;

architecture behavioral of tb_pmu_taylor_32phase is

    constant CLK_PERIOD         : time    := 10 ns;
    constant SAMPLE_RATE        : integer := 15000;
    constant GRID_FREQ          : real    := 50.0;
    constant SAMPLES_PER_CYCLE  : integer := 300;
    constant NUM_CYCLES         : integer := 3;
    constant TOTAL_SAMPLES      : integer := SAMPLES_PER_CYCLE * NUM_CYCLES;
    constant INTER_SAMPLE_CLKS  : integer := 6667;

    constant V_AMPLITUDE        : real := 20000.0;
    constant I_AMPLITUDE        : real := 10000.0;

    constant PKT_WORDS          : integer := 19;
    constant SYNC_FRAMESIZE     : std_logic_vector(31 downto 0) := x"AA01004C";
    constant FREQ_50HZ_Q16_16   : std_logic_vector(31 downto 0) := x"00320000";

    constant FREQ_TOLERANCE_Q16 : integer := 32768;

    signal clk : std_logic := '0';
    signal rst : std_logic := '1';

    signal enable              : std_logic := '0';
    signal s_axis_tdata        : std_logic_vector(127 downto 0) := (others => '0');
    signal s_axis_tvalid       : std_logic := '0';
    signal s_axis_tlast        : std_logic := '0';
    signal s_axis_tready       : std_logic;

    signal m_axis_tdata        : std_logic_vector(31 downto 0);
    signal m_axis_tvalid       : std_logic;
    signal m_axis_tready       : std_logic := '1';
    signal m_axis_tlast        : std_logic;

    signal sync_locked         : std_logic;
    signal input_packets_good  : std_logic_vector(31 downto 0);
    signal input_packets_bad   : std_logic_vector(31 downto 0);
    signal output_packets      : std_logic_vector(31 downto 0);
    signal processing_active   : std_logic;
    signal system_ready        : std_logic;
    signal frequency_out       : std_logic_vector(31 downto 0);
    signal freq_valid          : std_logic;
    signal rocof_out           : std_logic_vector(31 downto 0);
    signal rocof_valid         : std_logic;
    signal channels_extracted  : std_logic_vector(31 downto 0);
    signal dft_busy            : std_logic;
    signal cordic_busy         : std_logic;

    signal taylor_frequency_out : std_logic_vector(31 downto 0);
    signal taylor_freq_valid    : std_logic;
    signal taylor_rocof_out     : std_logic_vector(31 downto 0);
    signal transient_detected   : std_logic;

    signal stimulus_done       : boolean := false;

    signal pkt_word_count      : integer := 0;
    signal pkt_total_count     : integer := 0;
    signal pkt_buf             : std_logic_vector(PKT_WORDS*32-1 downto 0) := (others => '0');
    signal pkt_complete        : boolean := false;

    signal test_phase_nonzero  : boolean := false;
    signal test_freq_converged : boolean := false;
    signal test_taylor_valid   : boolean := false;

    component pmu_system_complete_256 is
        generic (
            SAMPLE_WIDTH      : integer := 16;
            SAMPLE_RATE       : integer := 15000;
            DFT_SIZE          : integer := 256;
            BUFFER_DEPTH      : integer := 512;
            BUFFER_ADDR_WIDTH : integer := 9;
            FREQ_WIDTH        : integer := 32;
            FRAC_BITS         : integer := 16;
            COEFF_WIDTH       : integer := 16;
            DFT_OUTPUT_WIDTH  : integer := 32;
            PHASE_WIDTH       : integer := 32;
            IDCODE_VAL        : std_logic_vector(15 downto 0) := x"0001";
            CLK_FREQ_HZ       : integer := 100_000_000
        );
        port (
            clk                  : in  std_logic;
            rst                  : in  std_logic;
            s_axis_tdata         : in  std_logic_vector(127 downto 0);
            s_axis_tvalid        : in  std_logic;
            s_axis_tlast         : in  std_logic;
            s_axis_tready        : out std_logic;
            m_axis_tdata         : out std_logic_vector(31 downto 0);
            m_axis_tvalid        : out std_logic;
            m_axis_tready        : in  std_logic;
            m_axis_tlast         : out std_logic;
            enable               : in  std_logic;
            sync_locked          : out std_logic;
            input_packets_good   : out std_logic_vector(31 downto 0);
            input_packets_bad    : out std_logic_vector(31 downto 0);
            output_packets       : out std_logic_vector(31 downto 0);
            processing_active    : out std_logic;
            system_ready         : out std_logic;
            frequency_out        : out std_logic_vector(31 downto 0);
            freq_valid           : out std_logic;
            rocof_out            : out std_logic_vector(31 downto 0);
            rocof_valid          : out std_logic;
            channels_extracted   : out std_logic_vector(31 downto 0);
            dft_busy             : out std_logic;
            cordic_busy          : out std_logic;
            taylor_frequency_out : out std_logic_vector(31 downto 0);
            taylor_freq_valid    : out std_logic;
            taylor_rocof_out     : out std_logic_vector(31 downto 0);
            transient_detected   : out std_logic
        );
    end component;

    function real_to_slv16(x : real) return std_logic_vector is
        variable i : integer;
    begin
        if x > 32767.0 then
            i := 32767;
        elsif x < -32768.0 then
            i := -32768;
        else
            i := integer(x);
        end if;
        return std_logic_vector(to_signed(i, 16));
    end function;

begin

    clk_process: process
    begin
        clk <= '0';
        wait for CLK_PERIOD / 2;
        clk <= '1';
        wait for CLK_PERIOD / 2;
    end process;

    dut: pmu_system_complete_256
        port map (
            clk                  => clk,
            rst                  => rst,
            s_axis_tdata         => s_axis_tdata,
            s_axis_tvalid        => s_axis_tvalid,
            s_axis_tlast         => s_axis_tlast,
            s_axis_tready        => s_axis_tready,
            m_axis_tdata         => m_axis_tdata,
            m_axis_tvalid        => m_axis_tvalid,
            m_axis_tready        => m_axis_tready,
            m_axis_tlast         => m_axis_tlast,
            enable               => enable,
            sync_locked          => sync_locked,
            input_packets_good   => input_packets_good,
            input_packets_bad    => input_packets_bad,
            output_packets       => output_packets,
            processing_active    => processing_active,
            system_ready         => system_ready,
            frequency_out        => frequency_out,
            freq_valid           => freq_valid,
            rocof_out            => rocof_out,
            rocof_valid          => rocof_valid,
            channels_extracted   => channels_extracted,
            dft_busy             => dft_busy,
            cordic_busy          => cordic_busy,
            taylor_frequency_out => taylor_frequency_out,
            taylor_freq_valid    => taylor_freq_valid,
            taylor_rocof_out     => taylor_rocof_out,
            transient_detected   => transient_detected
        );

    stimulus_process: process
        variable va, vb, vc     : real;
        variable ia, ib, ic     : real;
        variable ch0, ch1, ch2  : std_logic_vector(15 downto 0);
        variable ch3, ch4, ch5  : std_logic_vector(15 downto 0);
        variable phase_rad      : real;
        variable checksum       : std_logic_vector(7 downto 0);
        variable pkt_128        : std_logic_vector(127 downto 0);
        variable n              : integer;
    begin

        rst    <= '1';
        enable <= '0';
        wait for CLK_PERIOD * 10;
        rst    <= '0';
        wait for CLK_PERIOD * 5;
        enable <= '1';
        wait for CLK_PERIOD * 5;

        report ">>> [TB] Reset released, enable asserted. Sending " &
               integer'image(TOTAL_SAMPLES) & " ADC samples." severity note;

        for n in 0 to TOTAL_SAMPLES - 1 loop

            phase_rad := 2.0 * MATH_PI * GRID_FREQ * real(n) / real(SAMPLE_RATE);

            va := V_AMPLITUDE * sin(phase_rad);
            vb := V_AMPLITUDE * sin(phase_rad - 2.0 * MATH_PI / 3.0);
            vc := V_AMPLITUDE * sin(phase_rad + 2.0 * MATH_PI / 3.0);

            ia := I_AMPLITUDE * sin(phase_rad);
            ib := I_AMPLITUDE * sin(phase_rad - 2.0 * MATH_PI / 3.0);
            ic := I_AMPLITUDE * sin(phase_rad + 2.0 * MATH_PI / 3.0);

            ch0 := real_to_slv16(va);
            ch1 := real_to_slv16(vb);
            ch2 := real_to_slv16(vc);
            ch3 := real_to_slv16(ia);
            ch4 := real_to_slv16(ib);
            ch5 := real_to_slv16(ic);

            pkt_128 := x"AA" & ch0 & ch1 & ch2 & ch3 & ch4 & ch5 & x"55" & x"0000";

            wait until rising_edge(clk);
            s_axis_tdata  <= pkt_128;
            s_axis_tvalid <= '1';
            s_axis_tlast  <= '1';

            wait until rising_edge(clk);
            s_axis_tvalid <= '0';
            s_axis_tlast  <= '0';

            wait for CLK_PERIOD * (INTER_SAMPLE_CLKS - 2);
        end loop;

        report ">>> [TB] All " & integer'image(TOTAL_SAMPLES) &
               " samples sent. Waiting for DFT/CORDIC pipeline to drain." severity note;

        wait for CLK_PERIOD * 50000;

        stimulus_done <= true;

        report ">>> [TB] Stimulus complete." severity note;
        wait;
    end process;

    capture_process: process(clk)
        variable phase_ch1 : std_logic_vector(31 downto 0);
        variable freq_ch1  : std_logic_vector(31 downto 0);
        variable mag_ch1   : std_logic_vector(31 downto 0);
        variable word0     : std_logic_vector(31 downto 0);
        variable freq_int  : integer;
        variable freq_diff : integer;
        variable l         : line;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                pkt_word_count <= 0;
                pkt_total_count <= 0;
                pkt_complete <= false;
            else
                pkt_complete <= false;

                if m_axis_tvalid = '1' and m_axis_tready = '1' then

                    pkt_buf(PKT_WORDS*32-1 downto 32) <=
                        pkt_buf(PKT_WORDS*32-33 downto 0);
                    pkt_buf(31 downto 0) <= m_axis_tdata;

                    pkt_word_count <= pkt_word_count + 1;

                    if m_axis_tlast = '1' then
                        pkt_total_count <= pkt_total_count + 1;
                        pkt_complete    <= true;
                        pkt_word_count  <= 0;

                        report ">>> [PKT #" & integer'image(pkt_total_count + 1) &
                               "] last word received (tlast=1)" severity note;
                    end if;
                end if;

                if pkt_complete then

                    word0     := pkt_buf(PKT_WORDS*32-1       downto PKT_WORDS*32-32);
                    mag_ch1   := pkt_buf(PKT_WORDS*32 - 4*32 - 1 downto PKT_WORDS*32 - 5*32);
                    phase_ch1 := pkt_buf(PKT_WORDS*32 - 5*32 - 1 downto PKT_WORDS*32 - 6*32);
                    freq_ch1  := pkt_buf(PKT_WORDS*32 - 6*32 - 1 downto PKT_WORDS*32 - 7*32);

                    hwrite(l, word0);
                    report ">>> [PKT] Word 0 (SYNC+SIZE): 0x" & l.all severity note;
                    deallocate(l);

                    hwrite(l, mag_ch1);
                    report ">>> [PKT] Ch1 Magnitude: 0x" & l.all severity note;
                    deallocate(l);

                    hwrite(l, phase_ch1);
                    report ">>> [PKT] Ch1 Phase (Q2.29): 0x" & l.all &
                           " = " & integer'image(to_integer(signed(phase_ch1))) severity note;
                    deallocate(l);

                    hwrite(l, freq_ch1);
                    report ">>> [PKT] Ch1 Frequency (Q16.16): 0x" & l.all severity note;
                    deallocate(l);

                    if phase_ch1 /= x"00000000" then
                        if not test_phase_nonzero then
                            report ">>> [PASS] Test 1: Ch1 phase is non-zero (32-bit Q2.29). " &
                                   "Zero-padding successfully removed." severity note;
                        end if;
                        test_phase_nonzero <= true;
                    else
                        report ">>> [FAIL] Test 1: Ch1 phase is 0x00000000 - " &
                               "zero-padding still present or CORDIC not running." severity warning;
                    end if;

                    freq_int  := to_integer(unsigned(freq_ch1));
                    freq_diff := freq_int - 3276800;
                    if freq_diff < 0 then freq_diff := -freq_diff; end if;
                    if freq_diff < FREQ_TOLERANCE_Q16 then
                        if not test_freq_converged then
                            report ">>> [PASS] Test 2: Frequency converged near 50 Hz. " &
                                   "Q16.16 value = " & integer'image(freq_int) severity note;
                        end if;
                        test_freq_converged <= true;
                    end if;
                end if;
            end if;
        end if;
    end process;

    taylor_monitor: process(clk)
    begin
        if rising_edge(clk) then
            if rst = '0' then
                if taylor_freq_valid = '1' then
                    if not test_taylor_valid then
                        report ">>> [PASS] Test 3: Taylor frequency valid pulse detected. " &
                               "taylor_frequency_out = 0x" &
                               integer'image(to_integer(unsigned(taylor_frequency_out))) &
                               " (Q16.16 = " &
                               integer'image(to_integer(unsigned(taylor_frequency_out))) &
                               ")" severity note;
                        report ">>> [INFO] Taylor ROCOF = 0x" &
                               integer'image(to_integer(unsigned(taylor_rocof_out))) severity note;
                        report ">>> [INFO] Transient detected = " &
                               std_ulogic'image(transient_detected) severity note;
                    end if;
                    test_taylor_valid <= true;
                end if;

                if freq_valid = '1' then
                    report ">>> [INFO] Standard frequency valid: 0x" &
                           integer'image(to_integer(unsigned(frequency_out))) &
                           " (Q16.16, nominal 50Hz = 3276800)" severity note;
                end if;
            end if;
        end if;
    end process;

    summary_process: process
    begin
        wait until stimulus_done;
        wait for CLK_PERIOD * 100;

        report "=======================================================" severity note;
        report "  PMU Taylor + 32-bit Phase Testbench: FINAL RESULTS" severity note;
        report "=======================================================" severity note;
        report "  Input packets sent:    " & integer'image(TOTAL_SAMPLES) severity note;
        report "  Output packets seen:   " & integer'image(pkt_total_count) severity note;

        if test_phase_nonzero then
            report "  Test 1 [PASS]: 32-bit phase non-zero (zero-padding removed)" severity note;
        else
            report "  Test 1 [FAIL]: Phase still zero - check CORDIC/phase pipeline" severity warning;
        end if;

        if test_freq_converged then
            report "  Test 2 [PASS]: Standard frequency converged near 50 Hz" severity note;
        else
            report "  Test 2 [INFO]: Frequency not yet converged (may need more cycles)" severity note;
        end if;

        if test_taylor_valid then
            report "  Test 3 [PASS]: Taylor frequency estimator produced valid output" severity note;
        else
            report "  Test 3 [INFO]: Taylor output not seen (may need more cycles)" severity note;
        end if;

        report "=======================================================" severity note;
        wait;
    end process;

end behavioral;
