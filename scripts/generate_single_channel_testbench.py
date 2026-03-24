#!/usr/bin/env python3
"""
Generate VHDL testbench with real ADC data from medhavi.csv for channel 1,
and constant values for channels 2-6.
"""

import csv

# Configuration
CSV_PATH = "/home/arunupscee/Desktop/xtortion/c37 compliance/data_files/medhavi.csv"
OUTPUT_PATH = "/home/arunupscee/Desktop/xtortion/c37 compliance/testbenches/tb_pmu_realdata_ch1.vhd"
NUM_SAMPLES = 600  # 2 power cycles

# Constant values for channels 2-6 (fixed ADC values)
CONST_CH2 = 1000   # Constant value for channel 2
CONST_CH3 = 2000   # Constant value for channel 3
CONST_CH4 = 500    # Constant value for channel 4
CONST_CH5 = 1500   # Constant value for channel 5
CONST_CH6 = 800    # Constant value for channel 6

def signed16_to_unsigned(value):
    """Convert signed 16-bit to unsigned (two's complement)"""
    if value < 0:
        return (1 << 16) + value
    return value & 0xFFFF

def create_128bit_packet(ch0, ch1, ch2, ch3, ch4, ch5):
    """
    Create 128-bit packet:
    [127:120] = 0xAA (SYNC)
    [119:104] = Ch0 (16-bit)
    [103:88]  = Ch1 (16-bit)
    [87:72]   = Ch2 (16-bit)
    [71:56]   = Ch3 (16-bit)
    [55:40]   = Ch4 (16-bit)
    [39:24]   = Ch5 (16-bit)
    [23:16]   = 0x55 (CHECKSUM)
    [15:0]    = 0x0000 (Reserved)
    """
    packet = 0
    packet |= (0xAA << 120)  # SYNC
    packet |= (signed16_to_unsigned(ch0) << 104)
    packet |= (signed16_to_unsigned(ch1) << 88)
    packet |= (signed16_to_unsigned(ch2) << 72)
    packet |= (signed16_to_unsigned(ch3) << 56)
    packet |= (signed16_to_unsigned(ch4) << 40)
    packet |= (signed16_to_unsigned(ch5) << 24)
    packet |= (0x55 << 16)  # CHECKSUM
    packet |= 0x0000        # Reserved
    return packet

def read_csv_channel1(csv_path, num_samples):
    """Read channel 1 (first column) from CSV"""
    ch1_data = []
    with open(csv_path, 'r') as f:
        reader = csv.reader(f)
        next(reader)  # Skip header

        for i, row in enumerate(reader):
            if i >= num_samples:
                break
            if len(row) < 1:
                raise ValueError(f"Row {i+2} is empty")

            ch1_data.append(int(row[0]))

    print(f"Read {len(ch1_data)} samples from channel 1")
    return ch1_data

def generate_vhdl_testbench(ch1_data, output_path):
    """Generate VHDL testbench with hardcoded packets"""

    # Create packets: Channel 1 = real data, Channels 2-6 = constants
    packets = []
    for ch1_val in ch1_data:
        packet = create_128bit_packet(
            ch1_val,   # Channel 1: Real ADC data
            CONST_CH2, # Channel 2: Constant
            CONST_CH3, # Channel 3: Constant
            CONST_CH4, # Channel 4: Constant
            CONST_CH5, # Channel 5: Constant
            CONST_CH6  # Channel 6: Constant
        )
        packets.append(packet)

    with open(output_path, 'w') as f:
        f.write("""--------------------------------------------------------------------------------
-- PMU Testbench with Real ADC Data (Channel 1) + Constants (Channels 2-6)
-- Generated from medhavi.csv
-- Fast simulation with immediate console hex output
--------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tb_pmu_realdata_ch1 is
end entity tb_pmu_realdata_ch1;

architecture behavioral of tb_pmu_realdata_ch1 is

    -- Clock and reset
    signal clk : std_logic := '0';
    signal rst : std_logic := '1';

    -- AXI Stream Input (128-bit)
    signal s_axis_tdata  : std_logic_vector(127 downto 0) := (others => '0');
    signal s_axis_tvalid : std_logic := '0';
    signal s_axis_tready : std_logic;
    signal s_axis_tlast  : std_logic := '0';

    -- AXI Stream Output (32-bit)
    signal m_axis_tdata  : std_logic_vector(31 downto 0);
    signal m_axis_tvalid : std_logic;
    signal m_axis_tready : std_logic := '1';
    signal m_axis_tlast  : std_logic;

    -- System control and status
    signal enable : std_logic := '1';
    signal sync_locked : std_logic;
    signal input_packets_good : std_logic_vector(31 downto 0);
    signal input_packets_bad  : std_logic_vector(31 downto 0);
    signal output_packets     : std_logic_vector(31 downto 0);
    signal processing_active  : std_logic;
    signal system_ready       : std_logic;
    signal frequency_out      : std_logic_vector(31 downto 0);
    signal rocof_out          : std_logic_vector(31 downto 0);

    -- Test control
    signal test_complete : std_logic := '0';
    signal sample_count  : integer := 0;

    -- Packet capture (single packet)
    type word_array is array (0 to 18) of std_logic_vector(31 downto 0);
    signal captured_packet : word_array := (others => (others => '0'));
    signal word_idx : integer := 0;
    signal packet_captured : boolean := false;

    -- Constants
    constant CLK_PERIOD : time := 10 ns;  -- 100 MHz
""")

        f.write(f"    constant TOTAL_SAMPLES : integer := {len(packets)};\n")
        f.write(f"    constant INTER_SAMPLE_DELAY : integer := 6666;  -- 15 kHz rate\n\n")

        # Write packet array
        f.write("    -- Hardcoded test packets (Channel 1 = Real ADC, Channels 2-6 = Constants)\n")
        f.write(f"    -- CH1: Real data from medhavi.csv\n")
        f.write(f"    -- CH2: {CONST_CH2} (constant)\n")
        f.write(f"    -- CH3: {CONST_CH3} (constant)\n")
        f.write(f"    -- CH4: {CONST_CH4} (constant)\n")
        f.write(f"    -- CH5: {CONST_CH5} (constant)\n")
        f.write(f"    -- CH6: {CONST_CH6} (constant)\n")
        f.write("    type packet_array_type is array (0 to TOTAL_SAMPLES-1) of std_logic_vector(127 downto 0);\n")
        f.write("    constant TEST_PACKETS : packet_array_type := (\n")

        for i, pkt in enumerate(packets):
            hex_str = f"{pkt:032X}"
            if i < len(packets) - 1:
                f.write(f'        x"{hex_str}",\n')
            else:
                f.write(f'        x"{hex_str}"\n')

        f.write("    );\n\n")

        # Write component and functions
        f.write("""    -- DUT component
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

    -- Function to convert byte to hex string
    function byte_to_hex(byte_val : std_logic_vector(7 downto 0)) return string is
        variable nibble_high : integer;
        variable nibble_low  : integer;
        constant hex_chars : string(1 to 16) := "0123456789ABCDEF";
    begin
        nibble_high := to_integer(unsigned(byte_val(7 downto 4)));
        nibble_low  := to_integer(unsigned(byte_val(3 downto 0)));
        return hex_chars(nibble_high + 1) & hex_chars(nibble_low + 1);
    end function;

    -- Function to convert 32-bit word to hex string
    function word32_to_hex(word : std_logic_vector(31 downto 0)) return string is
    begin
        return byte_to_hex(word(31 downto 24)) & " " &
               byte_to_hex(word(23 downto 16)) & " " &
               byte_to_hex(word(15 downto 8))  & " " &
               byte_to_hex(word(7 downto 0));
    end function;

begin

    -- DUT instantiation
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

    -- Clock generation
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

    -- Stimulus process
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
        report "PMU TESTBENCH - REAL DATA CH1";
        report "========================================";
        report "Channel 1: Real ADC data from medhavi.csv";
""")

        f.write(f'        report "Channels 2-6: Constants ({CONST_CH2}, {CONST_CH3}, {CONST_CH4}, {CONST_CH5}, {CONST_CH6})";\n')
        f.write("""        report "Injecting " & integer'image(TOTAL_SAMPLES) & " samples";
        report "========================================";

        -- Inject samples
        while sample_idx < TOTAL_SAMPLES loop
            wait until rising_edge(clk);

            if s_axis_tready = '1' then
                s_axis_tdata <= TEST_PACKETS(sample_idx);
                s_axis_tvalid <= '1';
                s_axis_tlast <= '1';
                sample_count <= sample_idx + 1;

                wait until rising_edge(clk);
                s_axis_tvalid <= '0';
                s_axis_tlast <= '0';

                sample_idx := sample_idx + 1;

                if sample_idx mod 100 = 0 then
                    report ">>> Injected " & integer'image(sample_idx) & " samples";
                end if;

                for i in 0 to INTER_SAMPLE_DELAY-1 loop
                    wait until rising_edge(clk);
                end loop;
            end if;
        end loop;

        report ">>> All samples injected! Waiting for packet...";

        -- Wait for packet capture
        wait until packet_captured;
        wait for 100 ns;

        report "========================================";
        report "SIMULATION COMPLETE";
        report "========================================";

        wait for 100 us;
        test_complete <= '1';
        wait;
    end process;

    -- Capture and immediate display process
    capture_and_display: process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                word_idx <= 0;
                packet_captured <= false;
            elsif m_axis_tvalid = '1' and m_axis_tready = '1' and not packet_captured then
                -- Capture word
                captured_packet(word_idx) <= m_axis_tdata;

                if m_axis_tlast = '1' then
                    -- Packet complete - display immediately
                    report "";
                    report "========================================";
                    report "*** OUTPUT PACKET CAPTURED ***";
                    report "========================================";
                    report "";
                    report "76-BYTE PACKET (19 WORDS) IN HEX:";
                    report "----------------------------------------";
                    report "Byte  0- 3: " & word32_to_hex(captured_packet(0))  & "  (SYNC + FrameSize)";
                    report "Byte  4- 7: " & word32_to_hex(captured_packet(1))  & "  (IDCODE + SOC[31:16])";
                    report "Byte  8-11: " & word32_to_hex(captured_packet(2))  & "  (SOC[15:0] + Reserved)";
                    report "Byte 12-15: " & word32_to_hex(captured_packet(3))  & "  (STAT + Reserved)";
                    report "Byte 16-19: " & word32_to_hex(captured_packet(4))  & "  (CH1 Magnitude)";
                    report "Byte 20-23: " & word32_to_hex(captured_packet(5))  & "  (Padding + CH1 Phase)";
                    report "Byte 24-27: " & word32_to_hex(captured_packet(6))  & "  (CH2 Magnitude)";
                    report "Byte 28-31: " & word32_to_hex(captured_packet(7))  & "  (Padding + CH2 Phase)";
                    report "Byte 32-35: " & word32_to_hex(captured_packet(8))  & "  (CH3 Magnitude)";
                    report "Byte 36-39: " & word32_to_hex(captured_packet(9))  & "  (Padding + CH3 Phase)";
                    report "Byte 40-43: " & word32_to_hex(captured_packet(10)) & "  (CH4 Magnitude)";
                    report "Byte 44-47: " & word32_to_hex(captured_packet(11)) & "  (Padding + CH4 Phase)";
                    report "Byte 48-51: " & word32_to_hex(captured_packet(12)) & "  (CH5 Magnitude)";
                    report "Byte 52-55: " & word32_to_hex(captured_packet(13)) & "  (Padding + CH5 Phase)";
                    report "Byte 56-59: " & word32_to_hex(captured_packet(14)) & "  (CH6 Magnitude)";
                    report "Byte 60-63: " & word32_to_hex(captured_packet(15)) & "  (Padding + CH6 Phase)";
                    report "Byte 64-67: " & word32_to_hex(captured_packet(16)) & "  (Frequency)";
                    report "Byte 68-71: " & word32_to_hex(captured_packet(17)) & "  (ROCOF)";
                    report "Byte 72-75: " & word32_to_hex(captured_packet(18)) & "  (CRC + Reserved)";
                    report "========================================";
                    report "";

                    packet_captured <= true;
                    word_idx <= 0;
                else
                    word_idx <= word_idx + 1;
                end if;
            end if;
        end if;
    end process;

end architecture behavioral;
""")

    print(f"Generated testbench: {output_path}")
    print(f"Total samples: {len(packets)}")

def main():
    print("=" * 70)
    print("PMU Real Data Testbench Generator")
    print("=" * 70)

    # Read channel 1 from CSV
    ch1_data = read_csv_channel1(CSV_PATH, NUM_SAMPLES)

    # Generate testbench
    generate_vhdl_testbench(ch1_data, OUTPUT_PATH)

    print("=" * 70)
    print("SUCCESS!")
    print("=" * 70)

if __name__ == "__main__":
    main()
