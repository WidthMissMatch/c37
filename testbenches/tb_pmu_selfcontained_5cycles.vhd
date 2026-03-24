library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use STD.TEXTIO.ALL;
use IEEE.STD_LOGIC_TEXTIO.ALL;

library work;
use work.test_data_constants_pkg.all;

entity tb_pmu_selfcontained_5cycles is
end tb_pmu_selfcontained_5cycles;

architecture Behavioral of tb_pmu_selfcontained_5cycles is

    component pmu_system_complete_256 is
        port (
            clk : in std_logic;
            rst : in std_logic;
            s_axis_tdata : in std_logic_vector(127 downto 0);
            s_axis_tvalid : in std_logic;
            s_axis_tlast : in std_logic;
            s_axis_tready : out std_logic;
            m_axis_tdata : out std_logic_vector(31 downto 0);
            m_axis_tvalid : out std_logic;
            m_axis_tready : in std_logic;
            m_axis_tlast : out std_logic;
            enable : in std_logic;
            sync_locked : out std_logic;
            input_packets_good : out std_logic_vector(31 downto 0);
            input_packets_bad : out std_logic_vector(31 downto 0);
            output_packets : out std_logic_vector(31 downto 0);
            processing_active : out std_logic;
            system_ready : out std_logic;
            frequency_out : out std_logic_vector(31 downto 0);
            freq_valid : out std_logic;
            rocof_out : out std_logic_vector(31 downto 0);
            rocof_valid : out std_logic;
            channels_extracted : out std_logic_vector(31 downto 0);
            dft_busy : out std_logic;
            cordic_busy : out std_logic
        );
    end component;

    constant CLK_PERIOD : time := 10 ns;
    constant ADC_CYCLES : integer := 6666;
    constant TOTAL_SAMPLES : integer := 1500;
    constant EXPECTED_PACKETS : integer := 5;
    constant WORDS_PER_PACKET : integer := 19;
    constant BYTES_PER_PACKET : integer := 76;

    signal clk : std_logic := '0';
    signal rst : std_logic := '1';

    signal s_axis_tdata : std_logic_vector(127 downto 0) := (others => '0');
    signal s_axis_tvalid : std_logic := '0';
    signal s_axis_tlast : std_logic := '0';
    signal s_axis_tready : std_logic;

    signal m_axis_tdata : std_logic_vector(31 downto 0);
    signal m_axis_tvalid : std_logic;
    signal m_axis_tlast : std_logic;
    signal m_axis_tready : std_logic := '1';

    signal enable : std_logic := '1';

    signal sync_locked : std_logic;
    signal input_packets_good : std_logic_vector(31 downto 0);
    signal input_packets_bad : std_logic_vector(31 downto 0);
    signal output_packets_count : std_logic_vector(31 downto 0);
    signal processing_active : std_logic;
    signal system_ready : std_logic;
    signal frequency_out : std_logic_vector(31 downto 0);
    signal freq_valid : std_logic;
    signal rocof_out : std_logic_vector(31 downto 0);
    signal rocof_valid : std_logic;
    signal channels_extracted : std_logic_vector(31 downto 0);
    signal dft_busy : std_logic;
    signal cordic_busy : std_logic;

    signal samples_injected : integer := 0;
    signal packets_captured : integer := 0;

    type word_array is array (0 to WORDS_PER_PACKET-1) of std_logic_vector(31 downto 0);
    type packet_array is array (0 to EXPECTED_PACKETS-1) of word_array;
    signal captured_packets : packet_array := (others => (others => (others => '0')));

    function byte_to_hex(byte_val : std_logic_vector(7 downto 0)) return string is
        variable hex_chars : string(1 to 16) := "0123456789ABCDEF";
        variable result : string(1 to 2);
        variable nibble_high : integer;
        variable nibble_low : integer;
    begin
        nibble_high := to_integer(unsigned(byte_val(7 downto 4)));
        nibble_low := to_integer(unsigned(byte_val(3 downto 0)));
        result(1) := hex_chars(nibble_high + 1);
        result(2) := hex_chars(nibble_low + 1);
        return result;
    end function;

    function word32_to_hex(word : std_logic_vector(31 downto 0)) return string is
    begin
        return byte_to_hex(word(31 downto 24)) & " " &
               byte_to_hex(word(23 downto 16)) & " " &
               byte_to_hex(word(15 downto 8)) & " " &
               byte_to_hex(word(7 downto 0));
    end function;

begin

    dut : pmu_system_complete_256
        port map (
            clk => clk,
            rst => rst,
            s_axis_tdata => s_axis_tdata,
            s_axis_tvalid => s_axis_tvalid,
            s_axis_tlast => s_axis_tlast,
            s_axis_tready => s_axis_tready,
            m_axis_tdata => m_axis_tdata,
            m_axis_tvalid => m_axis_tvalid,
            m_axis_tready => m_axis_tready,
            m_axis_tlast => m_axis_tlast,
            enable => enable,
            sync_locked => sync_locked,
            input_packets_good => input_packets_good,
            input_packets_bad => input_packets_bad,
            output_packets => output_packets_count,
            processing_active => processing_active,
            system_ready => system_ready,
            frequency_out => frequency_out,
            freq_valid => freq_valid,
            rocof_out => rocof_out,
            rocof_valid => rocof_valid,
            channels_extracted => channels_extracted,
            dft_busy => dft_busy,
            cordic_busy => cordic_busy
        );

    clk_process : process
    begin
        clk <= '0';
        wait for CLK_PERIOD / 2;
        clk <= '1';
        wait for CLK_PERIOD / 2;
    end process;

    reset_process : process
    begin
        rst <= '1';
        wait for 100 ns;
        rst <= '0';
        wait;
    end process;

    stimulus_process : process
        variable sample_idx : integer := 0;
        variable cycle_count : integer := 0;
    begin

        wait until rst = '0';
        wait for CLK_PERIOD * 10;

        report "======================================== ";
        report "PMU SELF-CONTAINED 5-CYCLE TEST          ";
        report "======================================== ";
        report "Total samples: " & integer'image(TOTAL_SAMPLES);
        report "Expected packets: " & integer'image(EXPECTED_PACKETS);
        report "Sample rate: 15 kHz";
        report "======================================== ";
        report "";
        report "Starting sample injection...";

        while sample_idx < TOTAL_SAMPLES loop
            wait until rising_edge(clk);

            if s_axis_tready = '1' then

                s_axis_tdata <= TEST_PACKETS(sample_idx);
                s_axis_tvalid <= '1';
                s_axis_tlast <= '1';

                wait until rising_edge(clk);
                s_axis_tvalid <= '0';
                s_axis_tlast <= '0';

                sample_idx := sample_idx + 1;
                samples_injected <= sample_idx;

                if sample_idx mod 300 = 0 then
                    cycle_count := sample_idx / 300;
                    report "Injected " & integer'image(sample_idx) &
                           " samples (Cycle " & integer'image(cycle_count) & " complete)";
                end if;

                for i in 0 to ADC_CYCLES - 2 loop
                    wait until rising_edge(clk);
                end loop;
            end if;
        end loop;

        report "";
        report "All " & integer'image(TOTAL_SAMPLES) & " samples injected";
        report "Waiting for final processing...";
        report "";

        wait;
    end process;

    capture_process : process(clk)
        variable packet_idx : integer := 0;
        variable word_idx : integer := 0;
    begin
        if rising_edge(clk) then
            if rst = '0' and m_axis_tvalid = '1' and m_axis_tready = '1' then

                captured_packets(packet_idx)(word_idx) <= m_axis_tdata;

                if m_axis_tlast = '1' then

                    packets_captured <= packets_captured + 1;
                    report "Captured packet #" & integer'image(packet_idx + 1);
                    packet_idx := packet_idx + 1;
                    word_idx := 0;
                else
                    word_idx := word_idx + 1;
                end if;
            end if;
        end if;
    end process;

    display_process : process
        variable byte_idx : integer;
        variable L : line;
    begin

        wait until packets_captured >= EXPECTED_PACKETS;
        wait for CLK_PERIOD * 1000;

        report "";
        report "======================================== ";
        report "OUTPUT PACKET HEX DUMP                   ";
        report "======================================== ";
        report "";

        for pkt in 0 to EXPECTED_PACKETS - 1 loop
            report "---------------------------------------- ";
            report "PACKET #" & integer'image(pkt + 1) & " (76 BYTES)";
            report "---------------------------------------- ";

            report "Byte  0- 3: " & word32_to_hex(captured_packets(pkt)(0)) &
                   "  (SYNC + FrameSize)";

            report "Byte  4- 7: " & word32_to_hex(captured_packets(pkt)(1)) &
                   "  (IDCODE + SOC[31:16])";

            report "Byte  8-11: " & word32_to_hex(captured_packets(pkt)(2)) &
                   "  (SOC[15:0] + Reserved)";

            report "Byte 12-15: " & word32_to_hex(captured_packets(pkt)(3)) &
                   "  (STAT + Reserved)";

            report "Byte 16-19: " & word32_to_hex(captured_packets(pkt)(4)) &
                   "  (CH1 Magnitude)";
            report "Byte 20-23: " & word32_to_hex(captured_packets(pkt)(5)) &
                   "  (Padding + CH1 Phase)";
            report "Byte 24-27: " & word32_to_hex(captured_packets(pkt)(6)) &
                   "  (CH1 Frequency)";

            report "Byte 28-31: " & word32_to_hex(captured_packets(pkt)(7)) &
                   "  (CH1 ROCOF)";

            report "Byte 32-35: " & word32_to_hex(captured_packets(pkt)(8)) &
                   "  (CH2 Magnitude)";
            report "Byte 36-39: " & word32_to_hex(captured_packets(pkt)(9)) &
                   "  (Padding + CH2 Phase)";

            report "Byte 40-43: " & word32_to_hex(captured_packets(pkt)(10)) &
                   "  (CH3 Magnitude)";
            report "Byte 44-47: " & word32_to_hex(captured_packets(pkt)(11)) &
                   "  (Padding + CH3 Phase)";

            report "Byte 48-51: " & word32_to_hex(captured_packets(pkt)(12)) &
                   "  (CH4 Magnitude)";
            report "Byte 52-55: " & word32_to_hex(captured_packets(pkt)(13)) &
                   "  (Padding + CH4 Phase)";

            report "Byte 56-59: " & word32_to_hex(captured_packets(pkt)(14)) &
                   "  (CH5 Magnitude)";
            report "Byte 60-63: " & word32_to_hex(captured_packets(pkt)(15)) &
                   "  (Padding + CH5 Phase)";

            report "Byte 64-67: " & word32_to_hex(captured_packets(pkt)(16)) &
                   "  (CH6 Magnitude)";
            report "Byte 68-71: " & word32_to_hex(captured_packets(pkt)(17)) &
                   "  (Padding + CH6 Phase)";

            report "Byte 72-75: " & word32_to_hex(captured_packets(pkt)(18)) &
                   "  (CRC + Reserved)";

            report "";
        end loop;

        report "======================================== ";
        report "TEST COMPLETE                            ";
        report "Packets captured: " & integer'image(packets_captured);
        report "Expected: " & integer'image(EXPECTED_PACKETS);
        if packets_captured = EXPECTED_PACKETS then
            report "RESULT: PASS                             ";
        else
            report "RESULT: FAIL                             ";
        end if;
        report "======================================== ";

        wait for CLK_PERIOD * 100;
        report "Simulation finished";
        std.env.finish;
    end process;

end Behavioral;
