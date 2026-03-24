#!/bin/bash
# Ultra-quick 1-cycle test (300 samples) - Debug version with fixed CHECKSUM
set -e

echo "======================================"
echo "1-Cycle Debug Test (300 samples)"
echo "======================================"

PROJECT_DIR="/home/arunupscee/Desktop/xtortion/c37 compliance"
cd "$PROJECT_DIR"

# Clean
rm -rf xsim.dir .Xil testbench_results_100k.csv 2>/dev/null

# Create 1-cycle test data (just first 301 lines of medhavi.csv)
head -301 medhavi.csv > medhavi_1cycle.csv

echo "Step 1: Compiling VHDL files with xvhdl..."
xvhdl --work work sine.vhd
xvhdl --work work cos.vhd
xvhdl --work work circular_buffer.vhd
xvhdl --work work sample_counter.vhd
xvhdl --work work cycle_tracker.vhd
xvhdl --work work position_calc.vhd
xvhdl --work work Sample_fetcher.vhd
xvhdl --work work interpolation_engine.vhd
xvhdl --work work resampler_top.vhd
xvhdl --work work dft_sample_buffer.vhd
xvhdl --work work dft.vhd
xvhdl --work work cordic_calculator_256.vhd
xvhdl --work work frequency_rocof_calculator_256.vhd
xvhdl --work work pmu_processing_top.vhd
xvhdl --work work packet_validator.vhd
xvhdl --work work c37118_packet_formatter_6ch.vhd
xvhdl --work work axi_packet_receiver_128bit.vhd
xvhdl --work work channel_extractor.vhd
xvhdl --work work input_interface_complete.vhd
xvhdl --work work pmu_6ch_processing_256.vhd
xvhdl --work work pmu_system_complete_256.vhd

# Create minimal debug testbench on-the-fly
cat > pmu_1cycle_tb.vhd << 'TBEOF'
-- 1-Cycle Debug Testbench (300 samples only)
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use STD.TEXTIO.ALL;

entity pmu_1cycle_tb is
end pmu_1cycle_tb;

architecture behavioral of pmu_1cycle_tb is
    constant CLK_PERIOD : time := 10 ns;
    constant SAMPLE_COUNT : integer := 300;  -- Just 1 cycle

    signal clk : std_logic := '0';
    signal rst : std_logic := '1';
    signal enable : std_logic := '0';

    signal s_axis_tdata  : std_logic_vector(127 downto 0) := (others => '0');
    signal s_axis_tvalid : std_logic := '0';
    signal s_axis_tlast  : std_logic := '0';
    signal s_axis_tready : std_logic;

    signal m_axis_tdata  : std_logic_vector(31 downto 0);
    signal m_axis_tvalid : std_logic;
    signal m_axis_tready : std_logic := '1';
    signal m_axis_tlast  : std_logic;

    signal sync_locked : std_logic;
    signal input_packets_good : std_logic_vector(31 downto 0);
    signal input_packets_bad : std_logic_vector(31 downto 0);
    signal output_packets : std_logic_vector(31 downto 0);
    signal processing_active : std_logic;
    signal system_ready : std_logic;

    type sample_array_t is array (0 to 299, 0 to 5) of signed(15 downto 0);
    signal sample_data : sample_array_t;
    signal csv_loaded : boolean := false;
    signal stimulus_done : boolean := false;

    component pmu_system_complete_256 is
        port (
            clk : in std_logic; rst : in std_logic;
            s_axis_tdata : in std_logic_vector(127 downto 0);
            s_axis_tvalid : in std_logic; s_axis_tlast : in std_logic;
            s_axis_tready : out std_logic;
            m_axis_tdata : out std_logic_vector(31 downto 0);
            m_axis_tvalid : out std_logic; m_axis_tready : in std_logic;
            m_axis_tlast : out std_logic;
            enable : in std_logic; sync_locked : out std_logic;
            input_packets_good : out std_logic_vector(31 downto 0);
            input_packets_bad : out std_logic_vector(31 downto 0);
            output_packets : out std_logic_vector(31 downto 0);
            processing_active : out std_logic; system_ready : out std_logic;
            frequency_out : out std_logic_vector(31 downto 0);
            freq_valid : out std_logic;
            rocof_out : out std_logic_vector(31 downto 0);
            rocof_valid : out std_logic;
            channels_extracted : out std_logic_vector(31 downto 0);
            dft_busy : out std_logic; cordic_busy : out std_logic
        );
    end component;

begin
    dut: pmu_system_complete_256
        port map (
            clk => clk, rst => rst, enable => enable,
            s_axis_tdata => s_axis_tdata,
            s_axis_tvalid => s_axis_tvalid,
            s_axis_tlast => s_axis_tlast,
            s_axis_tready => s_axis_tready,
            m_axis_tdata => m_axis_tdata,
            m_axis_tvalid => m_axis_tvalid,
            m_axis_tready => m_axis_tready,
            m_axis_tlast => m_axis_tlast,
            sync_locked => sync_locked,
            input_packets_good => input_packets_good,
            input_packets_bad => input_packets_bad,
            output_packets => output_packets,
            processing_active => processing_active,
            system_ready => system_ready,
            enable => enable,
            frequency_out => open,
            freq_valid => open,
            rocof_out => open,
            rocof_valid => open,
            channels_extracted => open,
            dft_busy => open,
            cordic_busy => open
        );

    clk <= not clk after CLK_PERIOD/2;

    process
    begin
        rst <= '1';
        wait for 200 ns;
        rst <= '0';
        wait for 100 ns;
        enable <= '1';
        wait;
    end process;

    -- CSV Loader (simplified)
    process
        file csv_file : text;
        variable csv_line : line;
        variable open_status : file_open_status;
        variable char : character;
        variable val_str : string(1 to 10);
        variable val_idx : integer;
        variable int_val : integer;
        variable good_status : boolean;
        variable sample_idx : integer := 0;
    begin
        report "Loading medhavi_1cycle.csv...";
        file_open(open_status, csv_file, "medhavi_1cycle.csv", read_mode);

        readline(csv_file, csv_line);  -- Skip header

        while not endfile(csv_file) and sample_idx < SAMPLE_COUNT loop
            readline(csv_file, csv_line);

            for ch in 0 to 5 loop
                val_idx := 0;
                val_str := (others => ' ');

                while csv_line'length > 0 loop
                    read(csv_line, char, good_status);
                    exit when not good_status;
                    exit when char = ',';

                    if char /= ' ' then
                        val_idx := val_idx + 1;
                        val_str(val_idx) := char;
                    end if;
                end loop;

                int_val := 0;
                for i in 1 to val_idx loop
                    if val_str(i) >= '0' and val_str(i) <= '9' then
                        int_val := int_val * 10 + (character'pos(val_str(i)) - character'pos('0'));
                    end if;
                end loop;

                if val_str(1) = '-' then
                    int_val := -int_val;
                end if;

                sample_data(sample_idx, ch) <= to_signed(int_val, 16);
            end loop;

            sample_idx := sample_idx + 1;
        end loop;

        file_close(csv_file);
        report "Loaded " & integer'image(sample_idx) & " samples";
        csv_loaded <= true;
        wait;
    end process;

    -- Stimulus
    process
        variable pkt : std_logic_vector(127 downto 0);
    begin
        wait until csv_loaded;
        wait until rst = '0';
        wait until rising_edge(clk);
        wait for 100 ns;

        report ">>> STARTING STIMULUS <<<";

        for i in 0 to SAMPLE_COUNT-1 loop
            -- Build packet with CORRECT checksum position!
            pkt(127 downto 120) := x"AA";  -- SYNC
            pkt(119 downto 104) := std_logic_vector(sample_data(i, 0));
            pkt(103 downto 88)  := std_logic_vector(sample_data(i, 1));
            pkt(87 downto 72)   := std_logic_vector(sample_data(i, 2));
            pkt(71 downto 56)   := std_logic_vector(sample_data(i, 3));
            pkt(55 downto 40)   := std_logic_vector(sample_data(i, 4));
            pkt(39 downto 24)   := std_logic_vector(sample_data(i, 5));
            pkt(23 downto 16)   := x"55";  -- CHECKSUM at correct position!
            pkt(15 downto 0)    := x"0000";  -- Reserved

            s_axis_tdata <= pkt;
            s_axis_tvalid <= '1';
            s_axis_tlast <= '1';

            wait until rising_edge(clk) and s_axis_tready = '1';

            s_axis_tvalid <= '0';
            s_axis_tlast <= '0';

            -- Wait 66.67 us between samples (15 kHz)
            for j in 0 to 6666 loop
                wait until rising_edge(clk);
            end loop;

            if (i+1) mod 100 = 0 then
                report "Transmitted " & integer'image(i+1) & " packets";
            end if;
        end loop;

        report ">>> STIMULUS COMPLETE <<<";
        stimulus_done <= true;
        wait;
    end process;

    -- Debug Monitor
    process
    begin
        wait for 50 ms;
        loop
            report "========================================";
            report "STATUS @ " & time'image(now);
            report "  Sync Locked: " & std_logic'image(sync_locked);
            report "  Good Packets: " & integer'image(to_integer(unsigned(input_packets_good)));
            report "  Bad Packets: " & integer'image(to_integer(unsigned(input_packets_bad)));
            report "  Output Packets: " & integer'image(to_integer(unsigned(output_packets)));
            report "  Processing: " & std_logic'image(processing_active);
            report "========================================";
            wait for 50 ms;
            exit when stimulus_done;
        end loop;
        wait;
    end process;

    -- Timeout
    process
    begin
        wait for 500 ms;
        report "====================================== ";
        report "1-CYCLE TEST COMPLETE";
        report "Total Good Packets: " & integer'image(to_integer(unsigned(input_packets_good)));
        report "Total Bad Packets:  " & integer'image(to_integer(unsigned(input_packets_bad)));
        report "Total Outputs:      " & integer'image(to_integer(unsigned(output_packets)));
        report "======================================";
        if to_integer(unsigned(input_packets_good)) > 250 then
            report "SUCCESS: Packets validated correctly!";
        else
            report "FAILURE: Packet validation failed!" severity error;
        end if;
        wait;
    end process;

end behavioral;
TBEOF

xvhdl --work work pmu_1cycle_tb.vhd
echo "✓ Compilation complete"

echo ""
echo "Step 2: Elaborating with xelab..."
xelab -debug typical work.pmu_1cycle_tb -s pmu_1cycle_sim
echo "✓ Elaboration complete"

echo ""
echo "Step 3: Running 1-cycle simulation..."
START_TIME=$(date +%s)

xsim pmu_1cycle_sim -runall -onfinish quit 2>&1 | tee xsim_1cycle.log

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

echo ""
echo "======================================"
echo "1-CYCLE TEST RESULTS"
echo "======================================"
echo "Simulation time: ${ELAPSED}s"
echo ""

if grep -q "SUCCESS: Packets validated correctly" xsim_1cycle.log; then
    echo "✓✓✓ TEST PASSED - System is working!"
    exit 0
else
    echo "✗✗✗ TEST FAILED - Check logs"
    echo ""
    echo "Last 50 lines:"
    tail -50 xsim_1cycle.log
    exit 1
fi
