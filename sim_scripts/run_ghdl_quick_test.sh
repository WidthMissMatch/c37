#!/bin/bash
# Quick Test - 8 Cycles Only (2400 samples)
# Fast validation before full 100K simulation

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "======================================"
echo "QUICK TEST (8 cycles)"
echo "======================================"
echo ""

cd "$(dirname "$0")/.."

# Create quick test testbench
cat > pmu_quick_test_tb.vhd << 'EOF'
-- Quick Test Testbench (8 cycles only)
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use STD.TEXTIO.ALL;

entity pmu_quick_test_tb is
end pmu_quick_test_tb;

architecture behavioral of pmu_quick_test_tb is
    constant CLK_PERIOD : time := 10 ns;
    constant SAMPLE_COUNT : integer := 2400;  -- 8 cycles

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

    type sample_array_t is array (0 to 2399, 0 to 5) of signed(15 downto 0);
    signal sample_data : sample_array_t;
    signal csv_loaded : boolean := false;
    signal stimulus_done : boolean := false;

    signal result_count : integer := 0;

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
    -- DUT
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
            input_packets_good => open,
            input_packets_bad => open,
            output_packets => open,
            processing_active => open,
            system_ready => open,
            frequency_out => open,
            freq_valid => open,
            rocof_out => open,
            rocof_valid => open,
            channels_extracted => open,
            dft_busy => open,
            cordic_busy => open
        );

    -- Clock
    clk <= not clk after CLK_PERIOD/2;

    -- Reset & Enable
    process
    begin
        rst <= '1';
        wait for 200 ns;
        rst <= '0';
        wait for 100 ns;
        enable <= '1';
        wait;
    end process;

    -- CSV Loader
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
        report "Loading medhavi_small.csv...";
        file_open(open_status, csv_file, "medhavi_small.csv", read_mode);

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

        report "Starting stimulus...";

        for i in 0 to SAMPLE_COUNT-1 loop
            pkt(127 downto 120) := x"AA";  -- SYNC
            pkt(119 downto 104) := std_logic_vector(sample_data(i, 0));
            pkt(103 downto 88)  := std_logic_vector(sample_data(i, 1));
            pkt(87 downto 72)   := std_logic_vector(sample_data(i, 2));
            pkt(71 downto 56)   := std_logic_vector(sample_data(i, 3));
            pkt(55 downto 40)   := std_logic_vector(sample_data(i, 4));
            pkt(39 downto 24)   := std_logic_vector(sample_data(i, 5));
            pkt(23 downto 16)   := x"00";
            pkt(15 downto 8)    := x"55";  -- CHECKSUM
            pkt(7 downto 0)     := x"00";

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
        end loop;

        report "Stimulus complete";
        stimulus_done <= true;
        wait;
    end process;

    -- Output Monitor
    process
    begin
        wait until rising_edge(clk);
        if m_axis_tvalid = '1' and m_axis_tready = '1' then
            result_count <= result_count + 1;
            report "Output word " & integer'image(result_count) & ": 0x" &
                   integer'image(to_integer(unsigned(m_axis_tdata)));
        end if;
    end process;

    -- Final report
    process
    begin
        wait for 200 ms;  -- 200ms should be enough for 8 cycles
        report "============================================";
        report "QUICK TEST COMPLETE";
        report "Output words received: " & integer'image(result_count);
        if result_count > 100 then
            report "SUCCESS: System is producing output!";
        else
            report "FAILURE: No output detected!" severity error;
        end if;
        report "============================================";
        wait;
    end process;

end behavioral;
EOF

echo "Step 1: Compiling VHDL files..."
mkdir -p logs

ghdl -a --std=93 -C --work=work sine.vhd 2>> logs/quick_test.log
ghdl -a --std=93 -C --work=work cos.vhd 2>> logs/quick_test.log
ghdl -a --std=93 -C --work=work circular_buffer.vhd 2>> logs/quick_test.log
ghdl -a --std=93 -C --work=work sample_counter.vhd 2>> logs/quick_test.log
ghdl -a --std=93 -C --work=work cycle_tracker.vhd 2>> logs/quick_test.log
ghdl -a --std=93 -C --work=work position_calc.vhd 2>> logs/quick_test.log
ghdl -a --std=93 -C --work=work Sample_fetcher.vhd 2>> logs/quick_test.log
ghdl -a --std=93 -C --work=work interpolation_engine.vhd 2>> logs/quick_test.log
ghdl -a --std=93 -C --work=work resampler_top.vhd 2>> logs/quick_test.log
ghdl -a --std=93 -C --work=work dft_sample_buffer.vhd 2>> logs/quick_test.log
ghdl -a --std=93 -C --work=work dft.vhd 2>> logs/quick_test.log
ghdl -a --std=93 -C --work=work cordic_calculator_256.vhd 2>> logs/quick_test.log
ghdl -a --std=93 -C --work=work frequency_rocof_calculator_256.vhd 2>> logs/quick_test.log
ghdl -a --std=93 -C --work=work pmu_processing_top.vhd 2>> logs/quick_test.log
ghdl -a --std=93 -C --work=work packet_validator.vhd 2>> logs/quick_test.log
ghdl -a --std=93 -C --work=work c37118_packet_formatter_6ch.vhd 2>> logs/quick_test.log
ghdl -a --std=93 -C --work=work axi_packet_receiver_128bit.vhd 2>> logs/quick_test.log
ghdl -a --std=93 -C --work=work channel_extractor.vhd 2>> logs/quick_test.log
ghdl -a --std=93 -C --work=work input_interface_complete.vhd 2>> logs/quick_test.log
ghdl -a --std=93 -C --work=work pmu_6ch_processing_256.vhd 2>> logs/quick_test.log
ghdl -a --std=93 -C --work=work pmu_system_complete_256.vhd 2>> logs/quick_test.log
ghdl -a --std=93 -C --work=work pmu_quick_test_tb.vhd 2>> logs/quick_test.log

echo -e "${GREEN}✓${NC} Compilation complete"

echo ""
echo "Step 2: Elaborating..."
ghdl -e --std=93 -C --work=work pmu_quick_test_tb >> logs/quick_test.log 2>&1

echo -e "${GREEN}✓${NC} Elaboration complete"

echo ""
echo "Step 3: Running quick simulation (200ms simulated time)..."
echo "This should take 30-60 seconds..."

START_TIME=$(date +%s)
ghdl -r --std=93 -C --work=work pmu_quick_test_tb --stop-time=200ms \
    --assert-level=warning 2>&1 | tee logs/quick_test_run.log

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

echo ""
echo "======================================"
echo "QUICK TEST RESULTS"
echo "======================================"
echo "Simulation time: ${ELAPSED}s"
echo ""
echo "Last 20 lines of output:"
tail -20 logs/quick_test_run.log
echo ""

if grep -q "SUCCESS: System is producing output" logs/quick_test_run.log; then
    echo -e "${GREEN}✓✓✓ QUICK TEST PASSED ✓✓✓${NC}"
    echo ""
    echo "The system is working! Ready for full 100K test."
    exit 0
else
    echo -e "${RED}✗✗✗ QUICK TEST FAILED ✗✗✗${NC}"
    echo ""
    echo "System is not producing output. Check logs."
    exit 1
fi
