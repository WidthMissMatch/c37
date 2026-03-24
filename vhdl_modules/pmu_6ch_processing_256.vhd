library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity pmu_6ch_processing_256 is
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
        ref_valid_ch1     : in  std_logic;

        tve_percent_ch1   : out std_logic_vector(15 downto 0);
        tve_valid_ch1     : out std_logic;
        tve_pass_ch1      : out std_logic;
        tve_exceeds_ch1   : out std_logic;

        taylor_frequency_out : out std_logic_vector(FREQ_WIDTH-1 downto 0);
        taylor_freq_valid    : out std_logic;
        taylor_rocof_out     : out std_logic_vector(FREQ_WIDTH-1 downto 0);
        transient_detected   : out std_logic
    );
end pmu_6ch_processing_256;

architecture structural of pmu_6ch_processing_256 is

    component pmu_processing_top
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
            PHASE_WIDTH       : integer := 32
        );
        port (
            clk                  : in  std_logic;
            rst                  : in  std_logic;
            adc_sample           : in  std_logic_vector(SAMPLE_WIDTH-1 downto 0);
            adc_valid            : in  std_logic;
            phasor_magnitude     : out std_logic_vector(DFT_OUTPUT_WIDTH-1 downto 0);
            phasor_phase         : out std_logic_vector(PHASE_WIDTH-1 downto 0);
            phasor_valid         : out std_logic;
            dft_real_out         : out std_logic_vector(DFT_OUTPUT_WIDTH-1 downto 0);
            dft_imag_out         : out std_logic_vector(DFT_OUTPUT_WIDTH-1 downto 0);
            dft_valid_out        : out std_logic;
            frequency_out        : out std_logic_vector(FREQ_WIDTH-1 downto 0);
            freq_valid           : out std_logic;
            rocof_out            : out std_logic_vector(FREQ_WIDTH-1 downto 0);
            rocof_valid          : out std_logic;
            cycle_complete       : out std_logic;
            dft_busy             : out std_logic;
            cordic_busy          : out std_logic;
            system_ready         : out std_logic;
            samples_per_cycle    : out std_logic_vector(FREQ_WIDTH-1 downto 0);
            cycle_count          : out std_logic_vector(15 downto 0);
            taylor_frequency_out : out std_logic_vector(FREQ_WIDTH-1 downto 0);
            taylor_freq_valid    : out std_logic;
            taylor_rocof_out     : out std_logic_vector(FREQ_WIDTH-1 downto 0);
            transient_detected   : out std_logic;
            enable               : in  std_logic
        );
    end component;

    component pmu_processing_top_no_freq
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
            PHASE_WIDTH       : integer := 32
        );
        port (
            clk                 : in  std_logic;
            rst                 : in  std_logic;
            adc_sample          : in  std_logic_vector(SAMPLE_WIDTH-1 downto 0);
            adc_valid           : in  std_logic;
            frequency_in        : in  std_logic_vector(FREQ_WIDTH-1 downto 0);
            frequency_valid_in  : in  std_logic;
            phasor_magnitude    : out std_logic_vector(DFT_OUTPUT_WIDTH-1 downto 0);
            phasor_phase        : out std_logic_vector(PHASE_WIDTH-1 downto 0);
            phasor_valid        : out std_logic;
            cycle_complete      : out std_logic;
            dft_busy            : out std_logic;
            cordic_busy         : out std_logic;
            system_ready        : out std_logic;
            samples_per_cycle   : out std_logic_vector(FREQ_WIDTH-1 downto 0);
            cycle_count         : out std_logic_vector(15 downto 0);
            enable              : in  std_logic
        );
    end component;

    component tve_calculator
        generic (
            DATA_WIDTH      : integer := 32;
            OUTPUT_WIDTH    : integer := 16;
            CORDIC_ITER     : integer := 16
        );
        port (
            clk             : in  std_logic;
            rst             : in  std_logic;
            ref_real        : in  std_logic_vector(DATA_WIDTH-1 downto 0);
            ref_imag        : in  std_logic_vector(DATA_WIDTH-1 downto 0);
            ref_valid       : in  std_logic;
            meas_real       : in  std_logic_vector(DATA_WIDTH-1 downto 0);
            meas_imag       : in  std_logic_vector(DATA_WIDTH-1 downto 0);
            meas_valid      : in  std_logic;
            tve_percent     : out std_logic_vector(OUTPUT_WIDTH-1 downto 0);
            tve_valid       : out std_logic;
            tve_pass        : out std_logic;
            tve_exceeds     : out std_logic;
            busy            : out std_logic
        );
    end component;

    component c37118_packet_formatter_6ch
        generic (
            MAG_WIDTH       : integer := 32;
            PHASE_WIDTH     : integer := 32;
            FREQ_WIDTH      : integer := 32;
            IDCODE_VAL      : std_logic_vector(15 downto 0) := x"0001";
            CLK_FREQ_HZ     : integer := 100_000_000
        );
        port (
            clk             : in  std_logic;
            rst             : in  std_logic;
            magnitude_ch1   : in  std_logic_vector(MAG_WIDTH-1 downto 0);
            phase_angle_ch1 : in  std_logic_vector(PHASE_WIDTH-1 downto 0);
            frequency_ch1   : in  std_logic_vector(FREQ_WIDTH-1 downto 0);
            rocof_ch1       : in  std_logic_vector(FREQ_WIDTH-1 downto 0);
            mag_valid_ch1   : in  std_logic;
            magnitude_ch2   : in  std_logic_vector(MAG_WIDTH-1 downto 0);
            phase_angle_ch2 : in  std_logic_vector(PHASE_WIDTH-1 downto 0);
            mag_valid_ch2   : in  std_logic;
            magnitude_ch3   : in  std_logic_vector(MAG_WIDTH-1 downto 0);
            phase_angle_ch3 : in  std_logic_vector(PHASE_WIDTH-1 downto 0);
            mag_valid_ch3   : in  std_logic;
            magnitude_ch4   : in  std_logic_vector(MAG_WIDTH-1 downto 0);
            phase_angle_ch4 : in  std_logic_vector(PHASE_WIDTH-1 downto 0);
            mag_valid_ch4   : in  std_logic;
            magnitude_ch5   : in  std_logic_vector(MAG_WIDTH-1 downto 0);
            phase_angle_ch5 : in  std_logic_vector(PHASE_WIDTH-1 downto 0);
            mag_valid_ch5   : in  std_logic;
            magnitude_ch6   : in  std_logic_vector(MAG_WIDTH-1 downto 0);
            phase_angle_ch6 : in  std_logic_vector(PHASE_WIDTH-1 downto 0);
            mag_valid_ch6   : in  std_logic;
            tve_percent_ch1 : in  std_logic_vector(15 downto 0);
            tve_valid_ch1   : in  std_logic;
            tve_pass_ch1    : in  std_logic;
            tve_exceeds_ch1 : in  std_logic;
            enable          : in  std_logic;
            m_axis_tdata    : out std_logic_vector(31 downto 0);
            m_axis_tvalid   : out std_logic;
            m_axis_tready   : in  std_logic;
            m_axis_tlast    : out std_logic;
            packet_count    : out std_logic_vector(31 downto 0);
            packet_sent     : out std_logic
        );
    end component;

    signal ch1_magnitude    : std_logic_vector(DFT_OUTPUT_WIDTH-1 downto 0);
    signal ch1_phase        : std_logic_vector(PHASE_WIDTH-1 downto 0);
    signal ch1_phasor_valid : std_logic;
    signal ch1_dft_real     : std_logic_vector(DFT_OUTPUT_WIDTH-1 downto 0);
    signal ch1_dft_imag     : std_logic_vector(DFT_OUTPUT_WIDTH-1 downto 0);
    signal ch1_dft_valid    : std_logic;
    signal ch1_frequency    : std_logic_vector(FREQ_WIDTH-1 downto 0);
    signal ch1_freq_valid   : std_logic;
    signal ch1_rocof        : std_logic_vector(FREQ_WIDTH-1 downto 0);
    signal ch1_rocof_valid  : std_logic;
    signal ch1_ready        : std_logic;
    signal ch1_dft_busy     : std_logic;
    signal ch1_cordic_busy  : std_logic;

    signal tve_percent_int  : std_logic_vector(15 downto 0);
    signal tve_valid_int    : std_logic;
    signal tve_pass_int     : std_logic;
    signal tve_exceeds_int  : std_logic;

    signal ch2_magnitude    : std_logic_vector(DFT_OUTPUT_WIDTH-1 downto 0);
    signal ch2_phase        : std_logic_vector(PHASE_WIDTH-1 downto 0);
    signal ch2_phasor_valid : std_logic;
    signal ch2_ready        : std_logic;

    signal ch3_magnitude    : std_logic_vector(DFT_OUTPUT_WIDTH-1 downto 0);
    signal ch3_phase        : std_logic_vector(PHASE_WIDTH-1 downto 0);
    signal ch3_phasor_valid : std_logic;
    signal ch3_ready        : std_logic;

    signal ch4_magnitude    : std_logic_vector(DFT_OUTPUT_WIDTH-1 downto 0);
    signal ch4_phase        : std_logic_vector(PHASE_WIDTH-1 downto 0);
    signal ch4_phasor_valid : std_logic;
    signal ch4_ready        : std_logic;

    signal ch5_magnitude    : std_logic_vector(DFT_OUTPUT_WIDTH-1 downto 0);
    signal ch5_phase        : std_logic_vector(PHASE_WIDTH-1 downto 0);
    signal ch5_phasor_valid : std_logic;
    signal ch5_ready        : std_logic;

    signal ch6_magnitude    : std_logic_vector(DFT_OUTPUT_WIDTH-1 downto 0);
    signal ch6_phase        : std_logic_vector(PHASE_WIDTH-1 downto 0);
    signal ch6_phasor_valid : std_logic;
    signal ch6_ready        : std_logic;

    signal ch1_taylor_freq        : std_logic_vector(FREQ_WIDTH-1 downto 0);
    signal ch1_taylor_freq_valid  : std_logic;
    signal ch1_taylor_rocof       : std_logic_vector(FREQ_WIDTH-1 downto 0);
    signal ch1_transient          : std_logic;

    signal shared_frequency       : std_logic_vector(FREQ_WIDTH-1 downto 0);
    signal shared_frequency_valid : std_logic;

    signal all_channels_ready : std_logic;

begin

    ch1_master_inst: pmu_processing_top
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
            PHASE_WIDTH       => PHASE_WIDTH
        )
        port map (
            clk                  => clk,
            rst                  => rst,
            adc_sample           => adc_sample_ch1,
            adc_valid            => adc_valid_ch1,
            phasor_magnitude     => ch1_magnitude,
            phasor_phase         => ch1_phase,
            phasor_valid         => ch1_phasor_valid,
            dft_real_out         => ch1_dft_real,
            dft_imag_out         => ch1_dft_imag,
            dft_valid_out        => ch1_dft_valid,
            frequency_out        => ch1_frequency,
            freq_valid           => ch1_freq_valid,
            rocof_out            => ch1_rocof,
            rocof_valid          => ch1_rocof_valid,
            cycle_complete       => open,
            dft_busy             => ch1_dft_busy,
            cordic_busy          => ch1_cordic_busy,
            system_ready         => ch1_ready,
            samples_per_cycle    => open,
            cycle_count          => open,
            taylor_frequency_out => ch1_taylor_freq,
            taylor_freq_valid    => ch1_taylor_freq_valid,
            taylor_rocof_out     => ch1_taylor_rocof,
            transient_detected   => ch1_transient,
            enable               => enable
        );

    shared_frequency       <= ch1_frequency;
    shared_frequency_valid <= ch1_freq_valid;

    ch2_slave_inst: pmu_processing_top_no_freq
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
            PHASE_WIDTH       => PHASE_WIDTH
        )
        port map (
            clk                => clk,
            rst                => rst,
            adc_sample         => adc_sample_ch2,
            adc_valid          => adc_valid_ch2,
            frequency_in       => shared_frequency,
            frequency_valid_in => shared_frequency_valid,
            phasor_magnitude   => ch2_magnitude,
            phasor_phase       => ch2_phase,
            phasor_valid       => ch2_phasor_valid,
            cycle_complete     => open,
            dft_busy           => open,
            cordic_busy        => open,
            system_ready       => ch2_ready,
            samples_per_cycle  => open,
            cycle_count        => open,
            enable             => enable
        );

    ch3_slave_inst: pmu_processing_top_no_freq
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
            PHASE_WIDTH       => PHASE_WIDTH
        )
        port map (
            clk                => clk,
            rst                => rst,
            adc_sample         => adc_sample_ch3,
            adc_valid          => adc_valid_ch3,
            frequency_in       => shared_frequency,
            frequency_valid_in => shared_frequency_valid,
            phasor_magnitude   => ch3_magnitude,
            phasor_phase       => ch3_phase,
            phasor_valid       => ch3_phasor_valid,
            cycle_complete     => open,
            dft_busy           => open,
            cordic_busy        => open,
            system_ready       => ch3_ready,
            samples_per_cycle  => open,
            cycle_count        => open,
            enable             => enable
        );

    ch4_slave_inst: pmu_processing_top_no_freq
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
            PHASE_WIDTH       => PHASE_WIDTH
        )
        port map (
            clk                => clk,
            rst                => rst,
            adc_sample         => adc_sample_ch4,
            adc_valid          => adc_valid_ch4,
            frequency_in       => shared_frequency,
            frequency_valid_in => shared_frequency_valid,
            phasor_magnitude   => ch4_magnitude,
            phasor_phase       => ch4_phase,
            phasor_valid       => ch4_phasor_valid,
            cycle_complete     => open,
            dft_busy           => open,
            cordic_busy        => open,
            system_ready       => ch4_ready,
            samples_per_cycle  => open,
            cycle_count        => open,
            enable             => enable
        );

    ch5_slave_inst: pmu_processing_top_no_freq
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
            PHASE_WIDTH       => PHASE_WIDTH
        )
        port map (
            clk                => clk,
            rst                => rst,
            adc_sample         => adc_sample_ch5,
            adc_valid          => adc_valid_ch5,
            frequency_in       => shared_frequency,
            frequency_valid_in => shared_frequency_valid,
            phasor_magnitude   => ch5_magnitude,
            phasor_phase       => ch5_phase,
            phasor_valid       => ch5_phasor_valid,
            cycle_complete     => open,
            dft_busy           => open,
            cordic_busy        => open,
            system_ready       => ch5_ready,
            samples_per_cycle  => open,
            cycle_count        => open,
            enable             => enable
        );

    ch6_slave_inst: pmu_processing_top_no_freq
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
            PHASE_WIDTH       => PHASE_WIDTH
        )
        port map (
            clk                => clk,
            rst                => rst,
            adc_sample         => adc_sample_ch6,
            adc_valid          => adc_valid_ch6,
            frequency_in       => shared_frequency,
            frequency_valid_in => shared_frequency_valid,
            phasor_magnitude   => ch6_magnitude,
            phasor_phase       => ch6_phase,
            phasor_valid       => ch6_phasor_valid,
            cycle_complete     => open,
            dft_busy           => open,
            cordic_busy        => open,
            system_ready       => ch6_ready,
            samples_per_cycle  => open,
            cycle_count        => open,
            enable             => enable
        );

    packet_creator_inst: c37118_packet_formatter_6ch
        generic map (
            MAG_WIDTH   => DFT_OUTPUT_WIDTH,
            PHASE_WIDTH => PHASE_WIDTH,
            FREQ_WIDTH  => FREQ_WIDTH,
            IDCODE_VAL  => IDCODE_VAL,
            CLK_FREQ_HZ => CLK_FREQ_HZ
        )
        port map (
            clk             => clk,
            rst             => rst,

            magnitude_ch1   => ch1_magnitude,
            phase_angle_ch1 => ch1_phase,
            frequency_ch1   => ch1_frequency,
            rocof_ch1       => ch1_rocof,
            mag_valid_ch1   => ch1_phasor_valid,

            magnitude_ch2   => ch2_magnitude,
            phase_angle_ch2 => ch2_phase,
            mag_valid_ch2   => ch2_phasor_valid,

            magnitude_ch3   => ch3_magnitude,
            phase_angle_ch3 => ch3_phase,
            mag_valid_ch3   => ch3_phasor_valid,

            magnitude_ch4   => ch4_magnitude,
            phase_angle_ch4 => ch4_phase,
            mag_valid_ch4   => ch4_phasor_valid,

            magnitude_ch5   => ch5_magnitude,
            phase_angle_ch5 => ch5_phase,
            mag_valid_ch5   => ch5_phasor_valid,

            magnitude_ch6   => ch6_magnitude,
            phase_angle_ch6 => ch6_phase,
            mag_valid_ch6   => ch6_phasor_valid,

            tve_percent_ch1 => tve_percent_int,
            tve_valid_ch1   => tve_valid_int,
            tve_pass_ch1    => tve_pass_int,
            tve_exceeds_ch1 => tve_exceeds_int,

            enable          => enable,

            m_axis_tdata    => m_axis_tdata,
            m_axis_tvalid   => m_axis_tvalid,
            m_axis_tready   => m_axis_tready,
            m_axis_tlast    => m_axis_tlast,

            packet_count    => packet_count,
            packet_sent     => packet_sent
        );

    tve_ch1_inst: tve_calculator
        generic map (
            DATA_WIDTH   => DFT_OUTPUT_WIDTH,
            OUTPUT_WIDTH => 16,
            CORDIC_ITER  => 16
        )
        port map (
            clk          => clk,
            rst          => rst,
            ref_real     => ref_real_ch1,
            ref_imag     => ref_imag_ch1,
            ref_valid    => ref_valid_ch1,
            meas_real    => ch1_dft_real,
            meas_imag    => ch1_dft_imag,
            meas_valid   => ch1_dft_valid,
            tve_percent  => tve_percent_int,
            tve_valid    => tve_valid_int,
            tve_pass     => tve_pass_int,
            tve_exceeds  => tve_exceeds_int,
            busy         => open
        );

    all_channels_ready <= ch1_ready and ch2_ready and ch3_ready and
                          ch4_ready and ch5_ready and ch6_ready;

    system_ready       <= all_channels_ready;
    master_freq_valid  <= ch1_freq_valid;
    frequency_out      <= ch1_frequency;
    freq_valid         <= ch1_freq_valid;
    rocof_out          <= ch1_rocof;
    rocof_valid        <= ch1_rocof_valid;
    dft_busy_master    <= ch1_dft_busy;
    cordic_busy_master <= ch1_cordic_busy;

    tve_percent_ch1    <= tve_percent_int;
    tve_valid_ch1      <= tve_valid_int;
    tve_pass_ch1       <= tve_pass_int;
    tve_exceeds_ch1    <= tve_exceeds_int;

    taylor_frequency_out <= ch1_taylor_freq;
    taylor_freq_valid    <= ch1_taylor_freq_valid;
    taylor_rocof_out     <= ch1_taylor_rocof;
    transient_detected   <= ch1_transient;

end structural;
