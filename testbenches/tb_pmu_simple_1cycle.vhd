library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tb_pmu_simple_1cycle is
end entity tb_pmu_simple_1cycle;

architecture behavioral of tb_pmu_simple_1cycle is

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
    signal word_count    : integer := 0;

    constant CLK_PERIOD : time := 10 ns;

    constant INTER_SAMPLE_DELAY : integer := 6666;
    constant TOTAL_SAMPLES : integer := 520;

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

    type packet_array is array (0 to 7) of std_logic_vector(127 downto 0);
    constant TEST_PACKETS : packet_array := (
        x"AA2BF610C5C3402F67F585DB0F550000",
        x"AA2B041209C2EE2F13F68BDA5D550000",
        x"AA29AB19FFBFAE2E67F597D7F0550000",
        x"AA27D3FD37BB662D69F7C0D59A550000",
        x"AA25CB27D8B60E2C2AF91DD373550000",
        x"AA239D04F6B0A72AA2F8C8D111550000",
        x"AA216049C8AA262913F7F6CEDA550000",
        x"AA1F26F3DAA3A52726F5B8CCE4550000"
    );

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
        report "PMU SIMPLE 1-CYCLE TEST";
        report "========================================";
        report "Injecting " & integer'image(TOTAL_SAMPLES) & " samples (1 power cycle)";
        report "Sample rate: 15 kHz";
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

                if sample_idx mod 50 = 0 then
                    report "Injected " & integer'image(sample_idx) & "/" & integer'image(TOTAL_SAMPLES) & " samples";
                end if;

                for i in 0 to INTER_SAMPLE_DELAY-1 loop
                    wait until rising_edge(clk);
                end loop;
            end if;
        end loop;

        report "";
        report "All " & integer'image(TOTAL_SAMPLES) & " samples injected!";
        report "Waiting for packet output...";
        report "Continuing clock for 60ms to allow DUT processing...";
        report "";

        for i in 1 to 6000000 loop
            wait until rising_edge(clk);

            if i mod 500000 = 0 and packet_count > 0 then
                report ">>> First packet detected at " & integer'image(i/100000) & " ms after sample injection!";
                exit;
            end if;
        end loop;

        test_complete <= '1';
        report "========================================";
        if packet_count > 0 then
            report "TEST COMPLETE - SUCCESS";
        else
            report "TEST COMPLETE - WARNING";
        end if;
        report "========================================";
        report "Total samples injected: " & integer'image(sample_count);
        report "Total packets captured: " & integer'image(packet_count);
        if packet_count = 0 then
            report "WARNING: No packets captured!";
            report "Check: m_axis_tvalid, enable signals, DUT processing";
        end if;
        report "========================================";

        wait;
    end process;

    capture_process: process(clk)
        variable byte0, byte1, byte2, byte3 : integer;
        variable word_val : integer;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                packet_count <= 0;
                word_count <= 0;
            elsif m_axis_tvalid = '1' and m_axis_tready = '1' then

                byte3 := to_integer(unsigned(m_axis_tdata(31 downto 24)));
                byte2 := to_integer(unsigned(m_axis_tdata(23 downto 16)));
                byte1 := to_integer(unsigned(m_axis_tdata(15 downto 8)));
                byte0 := to_integer(unsigned(m_axis_tdata(7 downto 0)));

                report "[OUTPUT] Word #" & integer'image(word_count + 1) &
                       " bytes[3-0]: " & integer'image(byte3) & " " & integer'image(byte2) &
                       " " & integer'image(byte1) & " " & integer'image(byte0);

                word_count <= word_count + 1;

                if m_axis_tlast = '1' then
                    packet_count <= packet_count + 1;
                    report "*** PACKET #" & integer'image(packet_count + 1) & " CAPTURED (" & integer'image(word_count + 1) & " words = " & integer'image((word_count + 1) * 4) & " bytes) ***";
                    word_count <= 0;
                end if;
            end if;
        end if;
    end process;

    monitor_process: process(clk)
        variable first_sample_injected : boolean := false;
        variable first_output_seen : boolean := false;
    begin
        if rising_edge(clk) then

            if s_axis_tvalid = '1' and s_axis_tready = '1' and not first_sample_injected then
                report ">>> First sample injected at time " & time'image(now);
                first_sample_injected := true;
            end if;

            if m_axis_tvalid = '1' and not first_output_seen then
                report ">>> First output word at time " & time'image(now);
                first_output_seen := true;
            end if;
        end if;
    end process;

end architecture behavioral;
