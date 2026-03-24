library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity pmu_processing_top_no_freq is
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
end pmu_processing_top_no_freq;

architecture structural of pmu_processing_top_no_freq is

    component resampler_top
        generic (
            BUFFER_DEPTH      : integer := 512;
            BUFFER_ADDR_WIDTH : integer := 9;
            SAMPLE_WIDTH      : integer := 16;
            SAMPLE_RATE       : integer := 15000;
            FREQ_WIDTH        : integer := 32;
            FRAC_BITS         : integer := 16;
            OUTPUT_SAMPLES    : integer := 256
        );
        port (
            clk                 : in  std_logic;
            rst                 : in  std_logic;
            adc_sample          : in  std_logic_vector(SAMPLE_WIDTH-1 downto 0);
            adc_valid           : in  std_logic;
            frequency_estimate  : in  std_logic_vector(FREQ_WIDTH-1 downto 0);
            frequency_valid     : in  std_logic;
            resampled_sample    : out std_logic_vector(SAMPLE_WIDTH-1 downto 0);
            resampled_valid     : out std_logic;
            resampled_index     : out std_logic_vector(7 downto 0);
            resampled_last      : out std_logic;
            cycle_complete      : out std_logic;
            samples_per_cycle   : out std_logic_vector(FREQ_WIDTH-1 downto 0);
            buffer_sample_count : out std_logic_vector(31 downto 0);
            freq_out_of_range   : out std_logic;
            cycle_count         : out std_logic_vector(15 downto 0);
            cycle_start_offset  : out std_logic_vector(FREQ_WIDTH-1 downto 0);
            cycle_end_sample    : out std_logic_vector(31 downto 0);
            position_calc_busy  : out std_logic;
            sample_fetcher_busy : out std_logic;
            enable              : in  std_logic;
            ready               : out std_logic
        );
    end component;

    component dft_sample_buffer
        generic (
            BUFFER_SIZE   : integer := 256;
            SAMPLE_WIDTH  : integer := 16
        );
        port (
            clk             : in  std_logic;
            rst             : in  std_logic;
            write_sample    : in  std_logic_vector(SAMPLE_WIDTH-1 downto 0);
            write_index     : in  std_logic_vector(7 downto 0);
            write_valid     : in  std_logic;
            write_last      : in  std_logic;
            read_addr       : in  std_logic_vector(7 downto 0);
            read_data       : out std_logic_vector(SAMPLE_WIDTH-1 downto 0);
            buffer_full     : out std_logic;
            sample_count    : out std_logic_vector(8 downto 0)
        );
    end component;

    component dft_complex_calculator
        generic (
            WINDOW_SIZE       : integer := 256;
            SAMPLE_WIDTH      : integer := 16;
            COEFF_WIDTH       : integer := 16;
            ACCUMULATOR_WIDTH : integer := 48;
            OUTPUT_WIDTH      : integer := 32
        );
        port (
            clk            : in  std_logic;
            rst            : in  std_logic;
            start          : in  std_logic;
            done           : out std_logic;
            sample_data    : in  std_logic_vector(SAMPLE_WIDTH-1 downto 0);
            sample_addr    : out std_logic_vector(7 downto 0);
            cos_coeff      : in  std_logic_vector(COEFF_WIDTH-1 downto 0);
            cos_addr       : out std_logic_vector(7 downto 0);
            cos_valid      : in  std_logic;
            sin_coeff      : in  std_logic_vector(COEFF_WIDTH-1 downto 0);
            sin_addr       : out std_logic_vector(7 downto 0);
            sin_valid      : in  std_logic;
            real_result    : out std_logic_vector(OUTPUT_WIDTH-1 downto 0);
            imag_result    : out std_logic_vector(OUTPUT_WIDTH-1 downto 0);
            result_valid   : out std_logic
        );
    end component;

    component cosine_single_k_rom
        generic (
            WINDOW_SIZE : integer := 256;
            COEFF_WIDTH : integer := 16;
            K_VALUE     : integer := 1
        );
        port (
            clk         : in  std_logic;
            rst         : in  std_logic;
            enable      : in  std_logic;
            n_addr      : in  std_logic_vector(7 downto 0);
            cos_coeff   : out std_logic_vector(COEFF_WIDTH-1 downto 0);
            data_valid  : out std_logic
        );
    end component;

    component sine_single_k_rom
        generic (
            WINDOW_SIZE : integer := 256;
            COEFF_WIDTH : integer := 16;
            K_VALUE     : integer := 1
        );
        port (
            clk         : in  std_logic;
            rst         : in  std_logic;
            enable      : in  std_logic;
            n_addr      : in  std_logic_vector(7 downto 0);
            sin_coeff   : out std_logic_vector(COEFF_WIDTH-1 downto 0);
            data_valid  : out std_logic
        );
    end component;

    component cordic_calculator_256
        generic (
            INPUT_WIDTH  : integer := 32;
            ANGLE_WIDTH  : integer := 32;
            ITERATIONS   : integer := 30
        );
        port (
            clk          : in  std_logic;
            rst          : in  std_logic;
            start        : in  std_logic;
            real_in      : in  std_logic_vector(INPUT_WIDTH-1 downto 0);
            imag_in      : in  std_logic_vector(INPUT_WIDTH-1 downto 0);
            phase_out    : out std_logic_vector(ANGLE_WIDTH-1 downto 0);
            magnitude_out: out std_logic_vector(INPUT_WIDTH-1 downto 0);
            valid_out    : out std_logic;
            busy         : out std_logic
        );
    end component;

    component hann_window
        generic (
            WINDOW_SIZE  : integer := 256;
            SAMPLE_WIDTH : integer := 16;
            COEFF_WIDTH  : integer := 16
        );
        port (
            clk             : in  std_logic;
            rst             : in  std_logic;
            sample_in       : in  std_logic_vector(SAMPLE_WIDTH-1 downto 0);
            sample_index    : in  std_logic_vector(7 downto 0);
            sample_valid    : in  std_logic;
            sample_out      : out std_logic_vector(SAMPLE_WIDTH-1 downto 0);
            sample_out_valid: out std_logic;
            index_out       : out std_logic_vector(7 downto 0);
            coeff_out       : out std_logic_vector(COEFF_WIDTH-1 downto 0)
        );
    end component;

    signal resamp_sample        : std_logic_vector(SAMPLE_WIDTH-1 downto 0);
    signal resamp_valid         : std_logic;
    signal resamp_index         : std_logic_vector(7 downto 0);
    signal resamp_last          : std_logic;
    signal resamp_cycle_complete: std_logic;
    signal resamp_spc           : std_logic_vector(FREQ_WIDTH-1 downto 0);
    signal resamp_cycle_count   : std_logic_vector(15 downto 0);
    signal resamp_ready         : std_logic;

    signal dft_buf_read_addr    : std_logic_vector(7 downto 0);
    signal dft_buf_read_data    : std_logic_vector(SAMPLE_WIDTH-1 downto 0);
    signal dft_buf_full         : std_logic;

    signal dft_start            : std_logic;
    signal dft_done             : std_logic;
    signal dft_sample_addr      : std_logic_vector(7 downto 0);
    signal dft_cos_addr         : std_logic_vector(7 downto 0);
    signal dft_sin_addr         : std_logic_vector(7 downto 0);
    signal dft_real_result      : std_logic_vector(DFT_OUTPUT_WIDTH-1 downto 0);
    signal dft_imag_result      : std_logic_vector(DFT_OUTPUT_WIDTH-1 downto 0);
    signal dft_result_valid     : std_logic;
    signal dft_busy_int         : std_logic;

    signal cos_coeff            : std_logic_vector(COEFF_WIDTH-1 downto 0);
    signal cos_valid            : std_logic;
    signal sin_coeff            : std_logic_vector(COEFF_WIDTH-1 downto 0);
    signal sin_valid            : std_logic;

    signal cordic_start         : std_logic;
    signal cordic_phase         : std_logic_vector(PHASE_WIDTH-1 downto 0);
    signal cordic_magnitude     : std_logic_vector(DFT_OUTPUT_WIDTH-1 downto 0);
    signal cordic_valid         : std_logic;
    signal cordic_busy_int      : std_logic;

    signal dft_trigger          : std_logic;
    signal dft_trigger_d        : std_logic;
    signal system_ready_int     : std_logic;

    constant INIT_FREQ_50HZ : std_logic_vector(FREQ_WIDTH-1 downto 0) := x"00320000";

    signal hann_out_sample      : std_logic_vector(SAMPLE_WIDTH-1 downto 0);
    signal hann_out_valid       : std_logic;
    signal hann_out_index       : std_logic_vector(7 downto 0);
    signal resamp_last_d1       : std_logic;
    signal resamp_last_d2       : std_logic;

    signal freq_to_resampler    : std_logic_vector(FREQ_WIDTH-1 downto 0);
    signal freq_valid_to_resamp : std_logic;
    signal freq_received        : std_logic;

begin

    resampler_inst: resampler_top
        generic map (
            BUFFER_DEPTH      => BUFFER_DEPTH,
            BUFFER_ADDR_WIDTH => BUFFER_ADDR_WIDTH,
            SAMPLE_WIDTH      => SAMPLE_WIDTH,
            SAMPLE_RATE       => SAMPLE_RATE,
            FREQ_WIDTH        => FREQ_WIDTH,
            FRAC_BITS         => FRAC_BITS,
            OUTPUT_SAMPLES    => DFT_SIZE
        )
        port map (
            clk                 => clk,
            rst                 => rst,
            adc_sample          => adc_sample,
            adc_valid           => adc_valid,
            frequency_estimate  => freq_to_resampler,
            frequency_valid     => freq_valid_to_resamp,
            resampled_sample    => resamp_sample,
            resampled_valid     => resamp_valid,
            resampled_index     => resamp_index,
            resampled_last      => resamp_last,
            cycle_complete      => resamp_cycle_complete,
            samples_per_cycle   => resamp_spc,
            buffer_sample_count => open,
            freq_out_of_range   => open,
            cycle_count         => resamp_cycle_count,
            cycle_start_offset  => open,
            cycle_end_sample    => open,
            position_calc_busy  => open,
            sample_fetcher_busy => open,
            enable              => enable,
            ready               => resamp_ready
        );

    hann_inst: hann_window
        generic map (
            WINDOW_SIZE  => DFT_SIZE,
            SAMPLE_WIDTH => SAMPLE_WIDTH,
            COEFF_WIDTH  => COEFF_WIDTH
        )
        port map (
            clk              => clk,
            rst              => rst,
            sample_in        => resamp_sample,
            sample_index     => resamp_index,
            sample_valid     => resamp_valid,
            sample_out       => hann_out_sample,
            sample_out_valid => hann_out_valid,
            index_out        => hann_out_index,
            coeff_out        => open
        );

    resamp_last_delay: process(clk, rst)
    begin
        if rst = '1' then
            resamp_last_d1 <= '0';
            resamp_last_d2 <= '0';
        elsif rising_edge(clk) then
            resamp_last_d1 <= resamp_last;
            resamp_last_d2 <= resamp_last_d1;
        end if;
    end process;

    dft_buffer_inst: dft_sample_buffer
        generic map (
            BUFFER_SIZE  => DFT_SIZE,
            SAMPLE_WIDTH => SAMPLE_WIDTH
        )
        port map (
            clk          => clk,
            rst          => rst,
            write_sample => hann_out_sample,
            write_index  => hann_out_index,
            write_valid  => hann_out_valid,
            write_last   => resamp_last_d2,
            read_addr    => dft_buf_read_addr,
            read_data    => dft_buf_read_data,
            buffer_full  => dft_buf_full,
            sample_count => open
        );

    dft_inst: dft_complex_calculator
        generic map (
            WINDOW_SIZE       => DFT_SIZE,
            SAMPLE_WIDTH      => SAMPLE_WIDTH,
            COEFF_WIDTH       => COEFF_WIDTH,
            ACCUMULATOR_WIDTH => 48,
            OUTPUT_WIDTH      => DFT_OUTPUT_WIDTH
        )
        port map (
            clk          => clk,
            rst          => rst,
            start        => dft_start,
            done         => dft_done,
            sample_data  => dft_buf_read_data,
            sample_addr  => dft_sample_addr,
            cos_coeff    => cos_coeff,
            cos_addr     => dft_cos_addr,
            cos_valid    => cos_valid,
            sin_coeff    => sin_coeff,
            sin_addr     => dft_sin_addr,
            sin_valid    => sin_valid,
            real_result  => dft_real_result,
            imag_result  => dft_imag_result,
            result_valid => dft_result_valid
        );

    dft_buf_read_addr <= dft_sample_addr;

    cos_rom_inst: cosine_single_k_rom
        generic map (
            WINDOW_SIZE => DFT_SIZE,
            COEFF_WIDTH => COEFF_WIDTH,
            K_VALUE     => 1
        )
        port map (
            clk        => clk,
            rst        => rst,
            enable     => '1',
            n_addr     => dft_cos_addr,
            cos_coeff  => cos_coeff,
            data_valid => cos_valid
        );

    sin_rom_inst: sine_single_k_rom
        generic map (
            WINDOW_SIZE => DFT_SIZE,
            COEFF_WIDTH => COEFF_WIDTH,
            K_VALUE     => 1
        )
        port map (
            clk        => clk,
            rst        => rst,
            enable     => '1',
            n_addr     => dft_sin_addr,
            sin_coeff  => sin_coeff,
            data_valid => sin_valid
        );

    cordic_inst: cordic_calculator_256
        generic map (
            INPUT_WIDTH => DFT_OUTPUT_WIDTH,
            ANGLE_WIDTH => PHASE_WIDTH,
            ITERATIONS  => 30
        )
        port map (
            clk           => clk,
            rst           => rst,
            start         => cordic_start,
            real_in       => dft_real_result,
            imag_in       => dft_imag_result,
            phase_out     => cordic_phase,
            magnitude_out => cordic_magnitude,
            valid_out     => cordic_valid,
            busy          => cordic_busy_int
        );

    dft_trigger_process: process(clk, rst)
    begin
        if rst = '1' then
            dft_trigger <= '0';
            dft_trigger_d <= '0';
            dft_start <= '0';
        elsif rising_edge(clk) then
            dft_trigger <= dft_buf_full;
            dft_trigger_d <= dft_trigger;

            if dft_trigger = '1' and dft_trigger_d = '0' then
                dft_start <= '1';
            else
                dft_start <= '0';
            end if;
        end if;
    end process;

    dft_busy_flag: process(clk, rst)
    begin
        if rst = '1' then
            dft_busy_int <= '0';
        elsif rising_edge(clk) then
            if dft_start = '1' then
                dft_busy_int <= '1';
            elsif dft_done = '1' then
                dft_busy_int <= '0';
            end if;
        end if;
    end process;

    cordic_trigger_process: process(clk, rst)
    begin
        if rst = '1' then
            cordic_start <= '0';
        elsif rising_edge(clk) then

            cordic_start <= dft_result_valid;
        end if;
    end process;

    freq_select_process: process(clk, rst)
    begin
        if rst = '1' then
            freq_to_resampler <= INIT_FREQ_50HZ;
            freq_valid_to_resamp <= '0';
            freq_received <= '0';
        elsif rising_edge(clk) then

            if frequency_valid_in = '1' then
                freq_received <= '1';
            end if;

            if freq_received = '0' then
                freq_to_resampler <= INIT_FREQ_50HZ;

                freq_valid_to_resamp <= '1';
            else

                freq_valid_to_resamp <= '0';
                if frequency_valid_in = '1' then
                    freq_to_resampler <= frequency_in;
                    freq_valid_to_resamp <= '1';
                end if;
            end if;
        end if;
    end process;

    system_ready_process: process(clk, rst)
    begin
        if rst = '1' then
            system_ready_int <= '0';
        elsif rising_edge(clk) then
            if enable = '1' and resamp_ready = '1' then
                system_ready_int <= '1';
            else
                system_ready_int <= '0';
            end if;
        end if;
    end process;

    phasor_magnitude <= cordic_magnitude;
    phasor_phase     <= cordic_phase;
    phasor_valid     <= cordic_valid;

    cycle_complete   <= resamp_cycle_complete;
    dft_busy         <= dft_busy_int;
    cordic_busy      <= cordic_busy_int;
    system_ready     <= system_ready_int;

    samples_per_cycle <= resamp_spc;
    cycle_count       <= resamp_cycle_count;

end structural;
