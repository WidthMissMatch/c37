library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity pmu_system_complete_256 is
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

        frequency_out     : out std_logic_vector(FREQ_WIDTH-1 downto 0);
        freq_valid        : out std_logic;
        rocof_out         : out std_logic_vector(FREQ_WIDTH-1 downto 0);
        rocof_valid       : out std_logic;

        channels_extracted: out std_logic_vector(31 downto 0);
        dft_busy          : out std_logic;
        cordic_busy       : out std_logic
    );
end pmu_system_complete_256;

architecture structural of pmu_system_complete_256 is

    component input_interface_complete is
        port (
            clk                 : in  std_logic;
            rst                 : in  std_logic;
            s_axis_tdata        : in  std_logic_vector(127 downto 0);
            s_axis_tvalid       : in  std_logic;
            s_axis_tlast        : in  std_logic;
            s_axis_tready       : out std_logic;
            ch0_data            : out std_logic_vector(15 downto 0);
            ch0_valid           : out std_logic;
            ch1_data            : out std_logic_vector(15 downto 0);
            ch1_valid           : out std_logic;
            ch2_data            : out std_logic_vector(15 downto 0);
            ch2_valid           : out std_logic;
            ch3_data            : out std_logic_vector(15 downto 0);
            ch3_valid           : out std_logic;
            ch4_data            : out std_logic_vector(15 downto 0);
            ch4_valid           : out std_logic;
            ch5_data            : out std_logic_vector(15 downto 0);
            ch5_valid           : out std_logic;
            sync_locked         : out std_logic;
            good_packet_count   : out std_logic_vector(31 downto 0);
            bad_packet_count    : out std_logic_vector(31 downto 0);
            channels_extracted  : out std_logic_vector(31 downto 0);
            axi_receiving       : out std_logic;
            raw_packet_count    : out std_logic_vector(15 downto 0)
        );
    end component;

    component pmu_6ch_processing_256 is
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
            adc_sample_ch1    : in  std_logic_vector(SAMPLE_WIDTH-1 downto 0);
            adc_valid_ch1     : in  std_logic;
            adc_sample_ch2    : in  std_logic_vector(SAMPLE_WIDTH-1 downto 0);
            adc_valid_ch2     : in  std_logic;
            adc_sample_ch3    : in  std_logic_vector(SAMPLE_WIDTH-1 downto 0);
            adc_valid_ch3     : in  std_logic;
            adc_sample_ch4    : in  std_logic_vector(SAMPLE_WIDTH-1 downto 0);
            adc_valid_ch4     : in  std_logic;
            adc_sample_ch5    : in  std_logic_vector(SAMPLE_WIDTH-1 downto 0);
            adc_valid_ch5     : in  std_logic;
            adc_sample_ch6    : in  std_logic_vector(SAMPLE_WIDTH-1 downto 0);
            adc_valid_ch6     : in  std_logic;
            enable            : in  std_logic;
            m_axis_tdata      : out std_logic_vector(31 downto 0);
            m_axis_tvalid     : out std_logic;
            m_axis_tready     : in  std_logic;
            m_axis_tlast      : out std_logic;
            system_ready      : out std_logic;
            master_freq_valid : out std_logic;
            frequency_out     : out std_logic_vector(FREQ_WIDTH-1 downto 0);
            freq_valid        : out std_logic;
            rocof_out         : out std_logic_vector(FREQ_WIDTH-1 downto 0);
            rocof_valid       : out std_logic;
            packet_count      : out std_logic_vector(31 downto 0);
            packet_sent       : out std_logic;
            dft_busy_master   : out std_logic;
            cordic_busy_master: out std_logic;
            ref_real_ch1      : in  std_logic_vector(DFT_OUTPUT_WIDTH-1 downto 0);
            ref_imag_ch1      : in  std_logic_vector(DFT_OUTPUT_WIDTH-1 downto 0);
            ref_valid_ch1     : in  std_logic
        );
    end component;

    signal ch0_data_int     : std_logic_vector(15 downto 0);
    signal ch0_valid_int    : std_logic;
    signal ch1_data_int     : std_logic_vector(15 downto 0);
    signal ch1_valid_int    : std_logic;
    signal ch2_data_int     : std_logic_vector(15 downto 0);
    signal ch2_valid_int    : std_logic;
    signal ch3_data_int     : std_logic_vector(15 downto 0);
    signal ch3_valid_int    : std_logic;
    signal ch4_data_int     : std_logic_vector(15 downto 0);
    signal ch4_valid_int    : std_logic;
    signal ch5_data_int     : std_logic_vector(15 downto 0);
    signal ch5_valid_int    : std_logic;

    signal sync_locked_int  : std_logic;
    signal good_pkt_count   : std_logic_vector(31 downto 0);
    signal bad_pkt_count    : std_logic_vector(31 downto 0);
    signal ch_extracted     : std_logic_vector(31 downto 0);
    signal axi_receiving    : std_logic;
    signal raw_pkt_count    : std_logic_vector(15 downto 0);

    signal system_ready_int : std_logic;
    signal master_freq_valid_int : std_logic;
    signal output_pkt_count : std_logic_vector(31 downto 0);
    signal packet_sent_int  : std_logic;
    signal dft_busy_int     : std_logic;
    signal cordic_busy_int  : std_logic;

    signal proc_active      : std_logic;

    signal ref_real_ch1 : std_logic_vector(DFT_OUTPUT_WIDTH-1 downto 0) := (others => '0');
    signal ref_imag_ch1 : std_logic_vector(DFT_OUTPUT_WIDTH-1 downto 0) := (others => '0');
    signal ref_valid_ch1 : std_logic := '0';

begin

    input_interface_inst: input_interface_complete
        port map (
            clk                 => clk,
            rst                 => rst,

            s_axis_tdata        => s_axis_tdata,
            s_axis_tvalid       => s_axis_tvalid,
            s_axis_tlast        => s_axis_tlast,
            s_axis_tready       => s_axis_tready,

            ch0_data            => ch0_data_int,
            ch0_valid           => ch0_valid_int,
            ch1_data            => ch1_data_int,
            ch1_valid           => ch1_valid_int,
            ch2_data            => ch2_data_int,
            ch2_valid           => ch2_valid_int,
            ch3_data            => ch3_data_int,
            ch3_valid           => ch3_valid_int,
            ch4_data            => ch4_data_int,
            ch4_valid           => ch4_valid_int,
            ch5_data            => ch5_data_int,
            ch5_valid           => ch5_valid_int,

            sync_locked         => sync_locked_int,
            good_packet_count   => good_pkt_count,
            bad_packet_count    => bad_pkt_count,
            channels_extracted  => ch_extracted,
            axi_receiving       => axi_receiving,
            raw_packet_count    => raw_pkt_count
        );

    pmu_processing_inst: pmu_6ch_processing_256
        generic map (
            SAMPLE_WIDTH      => SAMPLE_WIDTH,
            SAMPLE_RATE       => SAMPLE_RATE,
            DFT_SIZE          => DFT_SIZE,
            BUFFER_DEPTH      => BUFFER_DEPTH,
            BUFFER_ADDR_WIDTH => BUFFER_ADDR_WIDTH,
            FREQ_WIDTH        => FREQ_WIDTH,
            FRAC_BITS         => FRAC_BITS,
            COEFF_WIDTH       => COEFF_WIDTH,
            DFT_OUTPUT_WIDTH  => DFT_OUTPUT_WIDTH,
            PHASE_WIDTH       => PHASE_WIDTH,
            IDCODE_VAL        => IDCODE_VAL,
            CLK_FREQ_HZ       => CLK_FREQ_HZ
        )
        port map (
            clk               => clk,
            rst               => rst,

            adc_sample_ch1    => ch0_data_int,
            adc_valid_ch1     => ch0_valid_int,
            adc_sample_ch2    => ch1_data_int,
            adc_valid_ch2     => ch1_valid_int,
            adc_sample_ch3    => ch2_data_int,
            adc_valid_ch3     => ch2_valid_int,
            adc_sample_ch4    => ch3_data_int,
            adc_valid_ch4     => ch3_valid_int,
            adc_sample_ch5    => ch4_data_int,
            adc_valid_ch5     => ch4_valid_int,
            adc_sample_ch6    => ch5_data_int,
            adc_valid_ch6     => ch5_valid_int,

            enable            => enable,

            m_axis_tdata      => m_axis_tdata,
            m_axis_tvalid     => m_axis_tvalid,
            m_axis_tready     => m_axis_tready,
            m_axis_tlast      => m_axis_tlast,

            system_ready      => system_ready_int,
            master_freq_valid => master_freq_valid_int,
            frequency_out     => frequency_out,
            freq_valid        => freq_valid,
            rocof_out         => rocof_out,
            rocof_valid       => rocof_valid,
            packet_count      => output_pkt_count,
            packet_sent       => packet_sent_int,
            dft_busy_master   => dft_busy_int,
            cordic_busy_master=> cordic_busy_int,

            ref_real_ch1      => ref_real_ch1,
            ref_imag_ch1      => ref_imag_ch1,
            ref_valid_ch1     => ref_valid_ch1
        );

    processing_active_flag: process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                proc_active <= '0';
            else

                proc_active <= axi_receiving or dft_busy_int or
                              cordic_busy_int or packet_sent_int;
            end if;
        end if;
    end process;

    sync_locked        <= sync_locked_int;
    input_packets_good <= good_pkt_count;
    input_packets_bad  <= bad_pkt_count;
    output_packets     <= output_pkt_count;
    processing_active  <= proc_active;
    system_ready       <= system_ready_int;

    channels_extracted <= ch_extracted;
    dft_busy           <= dft_busy_int;
    cordic_busy        <= cordic_busy_int;

end structural;
