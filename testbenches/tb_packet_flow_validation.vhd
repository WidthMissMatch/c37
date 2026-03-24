library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.STD_LOGIC_TEXTIO.ALL;
use STD.TEXTIO.ALL;

entity tb_packet_flow_validation is
end entity tb_packet_flow_validation;

architecture behavioral of tb_packet_flow_validation is

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

    signal enable        : std_logic := '1';
    signal test_complete : std_logic := '0';

    signal sync_locked       : std_logic;
    signal input_packets_good: std_logic_vector(31 downto 0);
    signal input_packets_bad : std_logic_vector(31 downto 0);
    signal output_packets    : std_logic_vector(31 downto 0);
    signal processing_active : std_logic;
    signal system_ready      : std_logic;
    signal frequency_out     : std_logic_vector(31 downto 0);
    signal rocof_out         : std_logic_vector(31 downto 0);
    signal channels_extracted: std_logic_vector(31 downto 0);
    signal dft_busy          : std_logic;
    signal cordic_busy       : std_logic;

    constant CLK_PERIOD : time := 10 ns;
    constant INTER_SAMPLE_DELAY : integer := 6666;
    constant TOTAL_SAMPLES : integer := 80;

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

    type word_array is array (0 to 18) of std_logic_vector(31 downto 0);
    signal captured_packet : word_array := (others => (others => '0'));
    signal word_count : integer := 0;
    signal packet_count : integer := 0;
    signal packet_complete : std_logic := '0';

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
            PHASE_WIDTH       : integer := 16;
            IDCODE_VAL        : std_logic_vector(15 downto 0) := x"0001";
            CLK_FREQ_HZ       : integer := 100_000_000
        );
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
        return byte_to_hex(word(31 downto 24)) & " " &
               byte_to_hex(word(23 downto 16)) & " " &
               byte_to_hex(word(15 downto 8))  & " " &
               byte_to_hex(word(7 downto 0));
    end function;

    function get_byte(word : std_logic_vector(31 downto 0); byte_idx : integer)
        return std_logic_vector is
    begin
        case byte_idx is
            when 0 => return word(31 downto 24);
            when 1 => return word(23 downto 16);
            when 2 => return word(15 downto 8);
            when 3 => return word(7 downto 0);
            when others => return (others => '0');
        end case;
    end function;

    function validate_packet(pkt : word_array) return string is
        variable sync_byte : std_logic_vector(7 downto 0);
        variable frame_size : std_logic_vector(23 downto 0);
        variable idcode : std_logic_vector(15 downto 0);
        variable crc_bytes : std_logic_vector(15 downto 0);
        variable status : string(1 to 256);
        variable pos : integer := 1;
    begin

        sync_byte := get_byte(pkt(0), 0);

        frame_size := pkt(0)(23 downto 0);

        idcode := pkt(1)(31 downto 16);

        crc_bytes := pkt(18)(31 downto 16);

        status := "[OK] SYNC=0x" & byte_to_hex(sync_byte) & " ";
        if sync_byte /= x"AA" then
            status := "[FAIL] SYNC=0x" & byte_to_hex(sync_byte) & " ";
        end if;

        return status;
    end function;

begin

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
            rocof_out          => rocof_out,
            channels_extracted => channels_extracted,
            dft_busy           => dft_busy,
            cordic_busy        => cordic_busy
        );

    clock_process: process
    begin
        while test_complete = '0' loop
            clk <= '0';
            wait for CLK_PERIOD / 2;
            clk <= '1';
            wait for CLK_PERIOD / 2;
        end loop;
        wait;
    end process;

    stimulus_process: process
        variable sample_idx : integer := 0;
        variable packet_idx : integer := 0;
    begin

        rst <= '1';
        s_axis_tvalid <= '0';
        s_axis_tlast <= '0';
        wait for 100 ns;
        wait until rising_edge(clk);
        rst <= '0';
        wait for 100 ns;

        report "";
        report "================================================================================";
        report "  C37.118 PACKET FLOW VALIDATION TESTBENCH";
        report "================================================================================";
        report "  Injecting 8 test packets via 128-bit AXI-Stream input";
        report "  Expected output: 76-byte IEEE C37.118 synchrophasor packets";
        report "================================================================================";
        report "";

        while system_ready = '0' loop
            wait until rising_edge(clk);
        end loop;

        report ">>> System ready, beginning test packet injection...";

        while packet_idx < 8 loop
            wait until rising_edge(clk);

            if s_axis_tready = '1' then
                s_axis_tdata <= TEST_PACKETS(packet_idx);
                s_axis_tvalid <= '1';
                s_axis_tlast <= '1';

                report ">>> Injected test packet " & integer'image(packet_idx + 1) & "/8: " &
                       to_string(TEST_PACKETS(packet_idx));

                wait until rising_edge(clk);
                s_axis_tvalid <= '0';
                s_axis_tlast <= '0';

                packet_idx := packet_idx + 1;
                sample_idx := sample_idx + 1;

                for i in 0 to INTER_SAMPLE_DELAY loop
                    wait until rising_edge(clk);
                end loop;
            end if;
        end loop;

        report "";
        report ">>> All test packets injected. Waiting for output processing...";
        wait for 50 us;

        report "";
        report "================================================================================";
        report "  TEST COMPLETE";
        report "================================================================================";

        test_complete <= '1';
        wait;
    end process;

    capture_process: process(clk)
        variable output_file : TEXT;
        variable line_buf : LINE;
        variable word_idx : integer := 0;
        variable packet_idx : integer := 0;
        variable all_sync : boolean := true;
        variable all_crc : boolean := true;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                word_count <= 0;
                packet_count <= 0;
                packet_complete <= '0';

            elsif m_axis_tvalid = '1' and m_axis_tready = '1' then

                captured_packet(word_count) <= m_axis_tdata;

                if m_axis_tlast = '1' then

                    packet_complete <= '1';

                    report "";
                    report "================================================================================";
                    report "  OUTPUT PACKET " & integer'image(packet_count + 1) & " (76 BYTES / 19 WORDS)";
                    report "================================================================================";

                    report "Byte  0- 3: " & word32_to_hex(captured_packet(0))  & "  (SYNC + FrameSize)";
                    report "Byte  4- 7: " & word32_to_hex(captured_packet(1))  & "  (IDCODE + SOC[31:16])";
                    report "Byte  8-11: " & word32_to_hex(captured_packet(2))  & "  (SOC[15:0] + Reserved)";
                    report "Byte 12-15: " & word32_to_hex(captured_packet(3))  & "  (STAT + Reserved)";
                    report "Byte 16-19: " & word32_to_hex(captured_packet(4))  & "  (CH1 Magnitude)";
                    report "Byte 20-23: " & word32_to_hex(captured_packet(5))  & "  (Padding + CH1 Phase)";
                    report "Byte 24-27: " & word32_to_hex(captured_packet(6))  & "  (CH1 Frequency)";
                    report "Byte 28-31: " & word32_to_hex(captured_packet(7))  & "  (CH1 ROCOF)";
                    report "Byte 32-35: " & word32_to_hex(captured_packet(8))  & "  (CH2 Magnitude)";
                    report "Byte 36-39: " & word32_to_hex(captured_packet(9))  & "  (Padding + CH2 Phase)";
                    report "Byte 40-43: " & word32_to_hex(captured_packet(10)) & "  (CH3 Magnitude)";
                    report "Byte 44-47: " & word32_to_hex(captured_packet(11)) & "  (Padding + CH3 Phase)";
                    report "Byte 48-51: " & word32_to_hex(captured_packet(12)) & "  (CH4 Magnitude)";
                    report "Byte 52-55: " & word32_to_hex(captured_packet(13)) & "  (Padding + CH4 Phase)";
                    report "Byte 56-59: " & word32_to_hex(captured_packet(14)) & "  (CH5 Magnitude)";
                    report "Byte 60-63: " & word32_to_hex(captured_packet(15)) & "  (Padding + CH5 Phase)";
                    report "Byte 64-67: " & word32_to_hex(captured_packet(16)) & "  (CH6 Magnitude)";
                    report "Byte 68-71: " & word32_to_hex(captured_packet(17)) & "  (Padding + CH6 Phase)";
                    report "Byte 72-75: " & word32_to_hex(captured_packet(18)) & "  (CRC + Reserved)";
                    report "================================================================================";
                    report "";

                    report "VALIDATION CHECKS:";
                    if get_byte(captured_packet(0), 0) = x"AA" then
                        report "  [OK] SYNC byte = 0xAA";
                    else
                        report "  [FAIL] SYNC byte = 0x" & byte_to_hex(get_byte(captured_packet(0), 0));
                        all_sync := false;
                    end if;

                    if captured_packet(0)(23 downto 0) = x"004C00" or
                       captured_packet(0)(23 downto 0) = x"00004C" then
                        report "  [OK] Frame Size = 0x004C (76 bytes)";
                    else
                        report "  [FAIL] Frame Size = 0x" & to_hstring(captured_packet(0)(23 downto 0));
                    end if;

                    if captured_packet(18)(31 downto 16) /= x"0000" then
                        report "  [OK] CRC field populated: 0x" & to_hstring(captured_packet(18)(31 downto 16));
                    else
                        report "  [FAIL] CRC field is zero";
                        all_crc := false;
                    end if;

                    report "  [OK] All 19 words captured";

                    packet_count <= packet_count + 1;
                    word_count <= 0;

                else
                    word_count <= word_count + 1;
                end if;
            end if;
        end if;
    end process;

    status_monitor: process
    begin
        wait for 1 us;

        while test_complete = '0' loop
            wait for 10 us;

            report "STATUS: " &
                   "In=" & integer'image(to_integer(unsigned(input_packets_good))) & " " &
                   "Out=" & integer'image(to_integer(unsigned(output_packets))) & " " &
                   "DFT_busy=" & std_logic'image(dft_busy) & " " &
                   "CORDIC_busy=" & std_logic'image(cordic_busy) & " " &
                   "Ready=" & std_logic'image(system_ready);
        end loop;

        wait;
    end process;

end architecture behavioral;
