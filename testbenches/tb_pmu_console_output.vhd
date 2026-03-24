library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tb_pmu_console_output is
end entity tb_pmu_console_output;

architecture behavioral of tb_pmu_console_output is

    signal clk : std_logic := '0';
    signal rst : std_logic := '1';

    signal s_axis_tdata  : std_logic_vector(127 downto 0) := (others => '0');
    signal s_axis_tvalid : std_logic := '0';
    signal s_axis_tready : std_logic;
    signal s_axis_tlast  : std_logic := '0';

    signal m_axis_tdata  : std_logic_vector(31 downto 0);
    signal m_axis_tvalid : std_logic;
    signal m_axis_tready : std_logic := '1';
    signal m_axis_tlast  : std_logic;

    signal enable : std_logic := '1';
    signal sync_locked : std_logic;
    signal input_packets_good : std_logic_vector(31 downto 0);
    signal input_packets_bad  : std_logic_vector(31 downto 0);
    signal output_packets     : std_logic_vector(31 downto 0);
    signal processing_active  : std_logic;
    signal system_ready       : std_logic;
    signal frequency_out      : std_logic_vector(31 downto 0);
    signal rocof_out          : std_logic_vector(31 downto 0);

    signal test_complete : std_logic := '0';
    signal sample_count  : integer := 0;
    signal packet_count  : integer := 0;

    type word_array is array (0 to 18) of std_logic_vector(31 downto 0);
    type packet_array_type is array (0 to 4) of word_array;
    signal captured_packets : packet_array_type := (others => (others => (others => '0')));
    signal word_idx : integer := 0;
    signal packet_idx : integer := 0;
    signal packets_captured : integer := 0;

    constant CLK_PERIOD : time := 10 ns;

    constant INTER_SAMPLE_DELAY : integer := 6666;
    constant TOTAL_SAMPLES : integer := 900;

    component pmu_system_complete_256 is
        port (
            clk              : in  std_logic;
            rst              : in  std_logic;
            s_axis_tdata     : in  std_logic_vector(127 downto 0);
            s_axis_tvalid    : in  std_logic;
            s_axis_tready    : out std_logic;
            s_axis_tlast     : in  std_logic;
            m_axis_tdata     : out std_logic_vector(31 downto 0);
            m_axis_tvalid    : out std_logic;
            m_axis_tready    : in  std_logic;
            m_axis_tlast     : out std_logic;
            enable           : in  std_logic;
            sync_locked      : out std_logic;
            input_packets_good : out std_logic_vector(31 downto 0);
            input_packets_bad  : out std_logic_vector(31 downto 0);
            output_packets     : out std_logic_vector(31 downto 0);
            processing_active  : out std_logic;
            system_ready       : out std_logic;
            frequency_out      : out std_logic_vector(31 downto 0);
            rocof_out          : out std_logic_vector(31 downto 0)
        );
    end component;

    type test_packet_array is array (0 to 7) of std_logic_vector(127 downto 0);
    constant TEST_PACKETS : test_packet_array := (
        x"AA2BF610C5C3402F67F585DB0F550000",
        x"AA2B041209C2EE2F13F68BDA5D550000",
        x"AA29AB19FFBFAE2E67F597D7F0550000",
        x"AA27D3FD37BB662D69F7C0D59A550000",
        x"AA25CB27D8B60E2C2AF91DD373550000",
        x"AA239D04F6B0A72AA2F8C8D111550000",
        x"AA216049C8AA262913F7F6CEDA550000",
        x"AA1F26F3DAA3A52726F5B8CCE4550000"
    );

    function byte_to_hex(byte_val : std_logic_vector(7 downto 0)) return string is
        variable nibble_high : integer;
        variable nibble_low  : integer;
        variable result : string(1 to 2);
        constant hex_chars : string(1 to 16) := "0123456789ABCDEF";
    begin
        nibble_high := to_integer(unsigned(byte_val(7 downto 4)));
        nibble_low  := to_integer(unsigned(byte_val(3 downto 0)));
        result(1) := hex_chars(nibble_high + 1);
        result(2) := hex_chars(nibble_low + 1);
        return result;
    end function;

    function word32_to_hex(word : std_logic_vector(31 downto 0)) return string is
    begin
        return byte_to_hex(word(31 downto 24)) & " " &
               byte_to_hex(word(23 downto 16)) & " " &
               byte_to_hex(word(15 downto 8))  & " " &
               byte_to_hex(word(7 downto 0));
    end function;

begin

    dut: pmu_system_complete_256
        port map (
            clk              => clk,
            rst              => rst,
            s_axis_tdata     => s_axis_tdata,
            s_axis_tvalid    => s_axis_tvalid,
            s_axis_tready    => s_axis_tready,
            s_axis_tlast     => s_axis_tlast,
            m_axis_tdata     => m_axis_tdata,
            m_axis_tvalid    => m_axis_tvalid,
            m_axis_tready    => m_axis_tready,
            m_axis_tlast     => m_axis_tlast,
            enable           => enable,
            sync_locked      => sync_locked,
            input_packets_good => input_packets_good,
            input_packets_bad  => input_packets_bad,
            output_packets     => output_packets,
            processing_active  => processing_active,
            system_ready       => system_ready,
            frequency_out      => frequency_out,
            rocof_out          => rocof_out
        );

    clk_process: process
    begin
        while test_complete = '0' loop
            clk <= '0';
            wait for CLK_PERIOD/2;
            clk <= '1';
            wait for CLK_PERIOD/2;
        end loop;
        wait;
    end process;

    stimulus_process: process
        variable sample_idx : integer := 0;
    begin

        rst <= '1';
        s_axis_tvalid <= '0';
        s_axis_tlast <= '0';
        wait for 100 ns;
        wait until rising_edge(clk);
        rst <= '0';
        wait for 100 ns;

        report "========================================";
        report "PMU CONSOLE OUTPUT TEST";
        report "========================================";
        report "Injecting " & integer'image(TOTAL_SAMPLES) & " samples (3 power cycles)";
        report "Sample rate: 15 kHz";
        report "Waiting for packet output...";
        report "========================================";
        report "";

        sample_idx := 0;
        while sample_idx < TOTAL_SAMPLES loop
            wait until rising_edge(clk);

            if s_axis_tready = '1' then

                s_axis_tdata <= TEST_PACKETS(sample_idx mod 8);
                s_axis_tvalid <= '1';
                s_axis_tlast <= '1';
                sample_count <= sample_idx + 1;

                wait until rising_edge(clk);
                s_axis_tvalid <= '0';
                s_axis_tlast <= '0';

                sample_idx := sample_idx + 1;

                if sample_idx mod 100 = 0 then
                    report ">>> Injected " & integer'image(sample_idx) & "/" & integer'image(TOTAL_SAMPLES) & " samples";
                end if;

                for i in 0 to INTER_SAMPLE_DELAY-1 loop
                    wait until rising_edge(clk);
                end loop;
            end if;
        end loop;

        report "";
        report ">>> All " & integer'image(TOTAL_SAMPLES) & " samples injected!";
        report ">>> Waiting for packet processing to complete...";
        report "";

        wait for 5 ms;

        report "========================================";
        report "INJECTION COMPLETE";
        report "Total samples injected: " & integer'image(sample_count);
        report "Total packets captured: " & integer'image(packets_captured);
        report "========================================";

        wait for 1 ms;

        test_complete <= '1';
        wait;
    end process;

    capture_process: process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                packet_idx <= 0;
                word_idx <= 0;
                packets_captured <= 0;
            elsif m_axis_tvalid = '1' and m_axis_tready = '1' then

                if packet_idx < 5 then
                    captured_packets(packet_idx)(word_idx) <= m_axis_tdata;
                end if;

                if m_axis_tlast = '1' then

                    report ">>> PACKET #" & integer'image(packet_idx + 1) & " CAPTURED (" & integer'image(word_idx + 1) & " words)";
                    packets_captured <= packets_captured + 1;
                    packet_idx <= packet_idx + 1;
                    word_idx <= 0;
                else
                    word_idx <= word_idx + 1;
                end if;
            end if;
        end if;
    end process;

    display_process: process
        variable word_val : std_logic_vector(31 downto 0);
    begin

        wait until sample_count >= TOTAL_SAMPLES;
        wait for 6 ms;

        report "";
        report "========================================";
        report "OUTPUT PACKET HEX DUMP";
        report "========================================";
        report "";

        for pkt in 0 to 4 loop
            if pkt < packets_captured then
                report "----------------------------------------";
                report "PACKET #" & integer'image(pkt + 1) & " (76 BYTES = 19 WORDS)";
                report "----------------------------------------";

                for w in 0 to 18 loop
                    word_val := captured_packets(pkt)(w);

                    if w = 0 then
                        report "Word  " & integer'image(w) & ": " & word32_to_hex(word_val) & "  (SYNC + FrameSize)";
                    elsif w = 1 then
                        report "Word  " & integer'image(w) & ": " & word32_to_hex(word_val) & "  (IDCODE + SOC[31:16])";
                    elsif w = 2 then
                        report "Word  " & integer'image(w) & ": " & word32_to_hex(word_val) & "  (SOC[15:0] + Reserved)";
                    elsif w = 3 then
                        report "Word  " & integer'image(w) & ": " & word32_to_hex(word_val) & "  (STAT + Reserved)";
                    elsif w = 4 then
                        report "Word  " & integer'image(w) & ": " & word32_to_hex(word_val) & "  (CH1 Magnitude)";
                    elsif w = 5 then
                        report "Word  " & integer'image(w) & ": " & word32_to_hex(word_val) & "  (Padding + CH1 Phase)";
                    elsif w = 6 then
                        report "Word  " & integer'image(w) & ": " & word32_to_hex(word_val) & "  (CH2 Magnitude)";
                    elsif w = 7 then
                        report "Word  " & integer'image(w) & ": " & word32_to_hex(word_val) & "  (Padding + CH2 Phase)";
                    elsif w = 8 then
                        report "Word  " & integer'image(w) & ": " & word32_to_hex(word_val) & "  (CH3 Magnitude)";
                    elsif w = 9 then
                        report "Word  " & integer'image(w) & ": " & word32_to_hex(word_val) & "  (Padding + CH3 Phase)";
                    elsif w = 10 then
                        report "Word " & integer'image(w) & ": " & word32_to_hex(word_val) & "  (CH4 Magnitude)";
                    elsif w = 11 then
                        report "Word " & integer'image(w) & ": " & word32_to_hex(word_val) & "  (Padding + CH4 Phase)";
                    elsif w = 12 then
                        report "Word " & integer'image(w) & ": " & word32_to_hex(word_val) & "  (CH5 Magnitude)";
                    elsif w = 13 then
                        report "Word " & integer'image(w) & ": " & word32_to_hex(word_val) & "  (Padding + CH5 Phase)";
                    elsif w = 14 then
                        report "Word " & integer'image(w) & ": " & word32_to_hex(word_val) & "  (CH6 Magnitude)";
                    elsif w = 15 then
                        report "Word " & integer'image(w) & ": " & word32_to_hex(word_val) & "  (Padding + CH6 Phase)";
                    elsif w = 16 then
                        report "Word " & integer'image(w) & ": " & word32_to_hex(word_val) & "  (Frequency)";
                    elsif w = 17 then
                        report "Word " & integer'image(w) & ": " & word32_to_hex(word_val) & "  (ROCOF)";
                    elsif w = 18 then
                        report "Word " & integer'image(w) & ": " & word32_to_hex(word_val) & "  (CRC + Reserved)";
                    end if;
                end loop;

                report "";
            end if;
        end loop;

        if packets_captured = 0 then
            report ">>> NO PACKETS CAPTURED <<<";
            report ">>> System may need more samples or time to produce output <<<";
            report "";
        end if;

        report "========================================";
        report "HEX DUMP COMPLETE";
        report "Packets displayed: " & integer'image(packets_captured);
        report "========================================";

        wait;
    end process;

end architecture behavioral;
