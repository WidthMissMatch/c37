library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use STD.TEXTIO.ALL;

use work.test_data_harmonics_pkg.all;

entity tb_pmu_harmonics_test is
end tb_pmu_harmonics_test;

architecture behavioral of tb_pmu_harmonics_test is

    constant CLK_PERIOD         : time := 10 ns;
    constant INTER_SAMPLE_CLKS  : integer := 6667;
    constant EXPECTED_PKT_WORDS : integer := 19;
    constant SYNC_FRAMESIZE     : std_logic_vector(31 downto 0) := x"AA01004C";

    signal clk  : std_logic := '0';
    signal rst  : std_logic := '1';

    signal enable             : std_logic := '0';
    signal s_axis_tdata       : std_logic_vector(127 downto 0) := (others => '0');
    signal s_axis_tvalid      : std_logic := '0';
    signal s_axis_tlast       : std_logic := '0';
    signal s_axis_tready      : std_logic;

    signal m_axis_tdata       : std_logic_vector(31 downto 0);
    signal m_axis_tvalid      : std_logic;
    signal m_axis_tready      : std_logic := '1';
    signal m_axis_tlast       : std_logic;

    signal sync_locked        : std_logic;
    signal input_packets_good : std_logic_vector(31 downto 0);
    signal input_packets_bad  : std_logic_vector(31 downto 0);
    signal output_packets     : std_logic_vector(31 downto 0);
    signal processing_active  : std_logic;
    signal system_ready       : std_logic;
    signal frequency_out      : std_logic_vector(31 downto 0);
    signal freq_valid         : std_logic;
    signal rocof_out          : std_logic_vector(31 downto 0);
    signal rocof_valid        : std_logic;
    signal channels_extracted : std_logic_vector(31 downto 0);
    signal dft_busy           : std_logic;
    signal cordic_busy        : std_logic;

    signal stimulus_done      : boolean := false;

    type pkt_word_array_t is array (0 to 18) of std_logic_vector(31 downto 0);

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

    function byte_to_hex(byte_val : std_logic_vector(7 downto 0)) return string is
        variable nibble_high : integer;
        variable nibble_low  : integer;
        constant hex_chars : string(1 to 16) := "0123456789ABCDEF";
    begin
        nibble_high := to_integer(unsigned(byte_val(7 downto 4)));
        nibble_low  := to_integer(unsigned(byte_val(3 downto 0)));
        return hex_chars(nibble_high + 1) & hex_chars(nibble_low + 1);
    end function;

    function word32_to_hex(word : std_logic_vector(31 downto 0)) return string is
    begin
        return byte_to_hex(word(31 downto 24)) &
               byte_to_hex(word(23 downto 16)) &
               byte_to_hex(word(15 downto 8))  &
               byte_to_hex(word(7 downto 0));
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

    reset_proc: process
    begin
        rst    <= '1';
        enable <= '0';
        wait for 200 ns;
        rst    <= '0';
        wait for 100 ns;
        enable <= '1';
        wait;
    end process;

    stimulus_proc: process
    begin
        wait until rst = '0';
        wait until rising_edge(clk);
        wait for 200 ns;

        report "========================================";
        report "[STIMULUS] Harmonic Test: " & integer'image(NUM_TEST_SAMPLES) &
               " packets, " & integer'image(NUM_TEST_SAMPLES / 300) & " cycles";
        report "========================================";

        for n in 0 to NUM_TEST_SAMPLES - 1 loop

            s_axis_tdata  <= TEST_PACKETS(n);
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
                       "/" & integer'image(NUM_TEST_SAMPLES / 300) &
                       " complete (" & integer'image(n + 1) & " packets sent)" &
                       " | Good=" & integer'image(to_integer(unsigned(input_packets_good))) &
                       " Bad=" & integer'image(to_integer(unsigned(input_packets_bad))) &
                       " Output=" & integer'image(to_integer(unsigned(output_packets)));
            end if;

        end loop;

        report "[STIMULUS] All " & integer'image(NUM_TEST_SAMPLES) &
               " packets transmitted. Waiting for pipeline flush...";
        stimulus_done <= true;
        wait;
    end process;

    output_writer: process
        file out_file       : text;
        variable l          : line;
        variable pkt_buf    : pkt_word_array_t;
        variable word_cnt   : integer := 0;
        variable total_pkts : integer := 0;
        variable w          : integer;
    begin
        file_open(out_file, "sim_output/output_packets_hex.txt", write_mode);
        wait until rst = '0';

        loop
            wait until rising_edge(clk);

            if m_axis_tvalid = '1' and m_axis_tready = '1' then

                if word_cnt < EXPECTED_PKT_WORDS then
                    pkt_buf(word_cnt) := m_axis_tdata;
                end if;

                if m_axis_tlast = '1' then
                    total_pkts := total_pkts + 1;

                    w := 0;
                    while w <= word_cnt and w < EXPECTED_PKT_WORDS loop
                        if w > 0 then
                            write(l, string'(" "));
                        end if;
                        write(l, word32_to_hex(pkt_buf(w)));
                        w := w + 1;
                    end loop;
                    writeline(out_file, l);

                    report "[OUTPUT] Packet #" & integer'image(total_pkts) &
                           " (" & integer'image(word_cnt + 1) & " words)" &
                           " Mag=" & integer'image(to_integer(unsigned(pkt_buf(4)))) &
                           " Freq=" & integer'image(to_integer(unsigned(pkt_buf(6))));

                    word_cnt := 0;
                else
                    word_cnt := word_cnt + 1;
                end if;

            end if;

            if stimulus_done then

                wait for 100 ms;
                file_close(out_file);
                report "[OUTPUT] File closed. Total packets written: " &
                       integer'image(total_pkts);
                exit;
            end if;

        end loop;

        wait;
    end process;

    timeout_proc: process
    begin
        wait for 350 ms;

        report "";
        report "################################################################";
        report "#              HARMONIC TEST SUMMARY                           #";
        report "################################################################";
        report "";
        report "  Input packets sent:  " & integer'image(NUM_TEST_SAMPLES);
        report "  Good packets:        " & integer'image(to_integer(unsigned(input_packets_good)));
        report "  Bad packets:         " & integer'image(to_integer(unsigned(input_packets_bad)));
        report "  Output C37.118 pkts: " & integer'image(to_integer(unsigned(output_packets)));
        report "  Sync locked:         " & std_logic'image(sync_locked);
        report "";
        report "  Output file: sim_output/output_packets_hex.txt";
        report "  Analyze with: python3 scripts/analyze_harmonic_output.py";
        report "";
        report "################################################################";

        assert false report "Simulation finished (timeout)." severity failure;
        wait;
    end process;

end behavioral;
