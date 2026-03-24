library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity pmu_processing_top is
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

        phasor_magnitude    : out std_logic_vector(DFT_OUTPUT_WIDTH-1 downto 0);
        phasor_phase        : out std_logic_vector(PHASE_WIDTH-1 downto 0);
        phasor_valid        : out std_logic;

        dft_real_out        : out std_logic_vector(DFT_OUTPUT_WIDTH-1 downto 0);
        dft_imag_out        : out std_logic_vector(DFT_OUTPUT_WIDTH-1 downto 0);
        dft_valid_out       : out std_logic;

        frequency_out       : out std_logic_vector(FREQ_WIDTH-1 downto 0);
        freq_valid          : out std_logic;

        rocof_out           : out std_logic_vector(FREQ_WIDTH-1 downto 0);
        rocof_valid         : out std_logic;

        cycle_complete      : out std_logic;
        dft_busy            : out std_logic;
        cordic_busy         : out std_logic;
        system_ready        : out std_logic;

        samples_per_cycle   : out std_logic_vector(FREQ_WIDTH-1 downto 0);
        cycle_count         : out std_logic_vector(15 downto 0);

        taylor_frequency_out : out std_logic_vector(FREQ_WIDTH-1 downto 0);
        taylor_freq_valid    : out std_logic;
        taylor_rocof_out     : out std_logic_vector(FREQ_WIDTH-1 downto 0);
        transient_detected   : out std_logic;

        enable              : in  std_logic
    );
end pmu_processing_top;

architecture structural of pmu_processing_top is

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

    component frequency_rocof_calculator_256
        generic (
            THETA_WIDTH     : integer := 32;
            OUTPUT_WIDTH    : integer := 32
        );
        port (
            clk             : in  std_logic;
            rst             : in  std_logic;
            theta_in        : in  std_logic_vector(THETA_WIDTH-1 downto 0);
            theta_valid     : in  std_logic;
            frequency_out   : out std_logic_vector(OUTPUT_WIDTH-1 downto 0);
            freq_valid      : out std_logic;
            rocof_out       : out std_logic_vector(OUTPUT_WIDTH-1 downto 0);
            rocof_valid     : out std_logic;
            ready           : out std_logic;
            phase_jump      : out std_logic
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

    component freq_damping_filter
        generic (
            FREQ_WIDTH : integer := 32;
            ALPHA      : integer := 19661
        );
        port (
            clk           : in  std_logic;
            rst           : in  std_logic;
            freq_in       : in  std_logic_vector(FREQ_WIDTH-1 downto 0);
            freq_valid    : in  std_logic;
            freq_out      : out std_logic_vector(FREQ_WIDTH-1 downto 0);
            freq_out_valid: out std_logic;
            freq_init     : in  std_logic_vector(FREQ_WIDTH-1 downto 0);
            diff_out      : out std_logic_vector(FREQ_WIDTH-1 downto 0);
            initialized   : out std_logic
        );
    end component;

    component taylor_window_rom
        generic (
            WINDOW_SIZE  : integer := 256;
            COEFF_WIDTH  : integer := 16
        );
        port (
            clk         : in  std_logic;
            rst         : in  std_logic;
            addr        : in  std_logic_vector(7 downto 0);
            w1_coeff    : out std_logic_vector(COEFF_WIDTH-1 downto 0);
            w2_coeff    : out std_logic_vector(COEFF_WIDTH-1 downto 0)
        );
    end component;

    component taylor_dft_calculator
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
            taylor_active  : out std_logic;
            sample_data    : in  std_logic_vector(SAMPLE_WIDTH-1 downto 0);
            sample_addr    : out std_logic_vector(7 downto 0);
            cos_coeff      : in  std_logic_vector(COEFF_WIDTH-1 downto 0);
            cos_addr       : out std_logic_vector(7 downto 0);
            sin_coeff      : in  std_logic_vector(COEFF_WIDTH-1 downto 0);
            sin_addr       : out std_logic_vector(7 downto 0);
            taylor_addr    : out std_logic_vector(7 downto 0);
            w1_coeff       : in  std_logic_vector(COEFF_WIDTH-1 downto 0);
            w2_coeff       : in  std_logic_vector(COEFF_WIDTH-1 downto 0);
            c0_real        : out std_logic_vector(OUTPUT_WIDTH-1 downto 0);
            c0_imag        : out std_logic_vector(OUTPUT_WIDTH-1 downto 0);
            c1_real        : out std_logic_vector(OUTPUT_WIDTH-1 downto 0);
            c1_imag        : out std_logic_vector(OUTPUT_WIDTH-1 downto 0);
            c2_real        : out std_logic_vector(OUTPUT_WIDTH-1 downto 0);
            c2_imag        : out std_logic_vector(OUTPUT_WIDTH-1 downto 0);
            result_valid   : out std_logic
        );
    end component;

    component taylor_frequency_estimator
        generic (
            INPUT_WIDTH  : integer := 32;
            FREQ_WIDTH   : integer := 32;
            FRAC_BITS    : integer := 16
        );
        port (
            clk                : in  std_logic;
            rst                : in  std_logic;
            c0_real            : in  std_logic_vector(INPUT_WIDTH-1 downto 0);
            c0_imag            : in  std_logic_vector(INPUT_WIDTH-1 downto 0);
            c1_real            : in  std_logic_vector(INPUT_WIDTH-1 downto 0);
            c1_imag            : in  std_logic_vector(INPUT_WIDTH-1 downto 0);
            taylor_valid       : in  std_logic;
            std_frequency      : in  std_logic_vector(FREQ_WIDTH-1 downto 0);
            std_freq_valid     : in  std_logic;
            taylor_frequency   : out std_logic_vector(FREQ_WIDTH-1 downto 0);
            taylor_freq_valid  : out std_logic;
            transient_detected : out std_logic;
            taylor_rocof       : out std_logic_vector(FREQ_WIDTH-1 downto 0)
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

    signal freq_calc_out        : std_logic_vector(FREQ_WIDTH-1 downto 0);
    signal freq_calc_valid      : std_logic;
    signal rocof_calc_out       : std_logic_vector(FREQ_WIDTH-1 downto 0);
    signal rocof_calc_valid     : std_logic;
    signal freq_calc_ready      : std_logic;

    signal dft_trigger          : std_logic;
    signal dft_trigger_d        : std_logic;
    signal system_ready_int     : std_logic;

    constant INIT_FREQ_50HZ : std_logic_vector(FREQ_WIDTH-1 downto 0) := x"00320000";

    signal hann_out_sample      : std_logic_vector(SAMPLE_WIDTH-1 downto 0);
    signal hann_out_valid       : std_logic;
    signal hann_out_index       : std_logic_vector(7 downto 0);
    signal resamp_last_d1       : std_logic;
    signal resamp_last_d2       : std_logic;

    signal damped_freq_out      : std_logic_vector(FREQ_WIDTH-1 downto 0);
    signal damped_freq_valid    : std_logic;

    signal freq_feedback        : std_logic_vector(FREQ_WIDTH-1 downto 0);
    signal freq_feedback_valid  : std_logic;
    signal freq_measurement_count : unsigned(1 downto 0);

    signal taylor_active_int    : std_logic;
    signal taylor_dft_start     : std_logic;
    signal dft_done_prev        : std_logic;
    signal taylor_sample_addr   : std_logic_vector(7 downto 0);
    signal taylor_cos_addr      : std_logic_vector(7 downto 0);
    signal taylor_sin_addr      : std_logic_vector(7 downto 0);
    signal taylor_win_addr      : std_logic_vector(7 downto 0);
    signal muxed_sample_addr    : std_logic_vector(7 downto 0);
    signal muxed_cos_addr       : std_logic_vector(7 downto 0);
    signal muxed_sin_addr       : std_logic_vector(7 downto 0);

    signal tw_w1_coeff          : std_logic_vector(COEFF_WIDTH-1 downto 0);
    signal tw_w2_coeff          : std_logic_vector(COEFF_WIDTH-1 downto 0);

    signal taylor_c0_real       : std_logic_vector(DFT_OUTPUT_WIDTH-1 downto 0);
    signal taylor_c0_imag       : std_logic_vector(DFT_OUTPUT_WIDTH-1 downto 0);
    signal taylor_c1_real       : std_logic_vector(DFT_OUTPUT_WIDTH-1 downto 0);
    signal taylor_c1_imag       : std_logic_vector(DFT_OUTPUT_WIDTH-1 downto 0);
    signal taylor_c2_real       : std_logic_vector(DFT_OUTPUT_WIDTH-1 downto 0);
    signal taylor_c2_imag       : std_logic_vector(DFT_OUTPUT_WIDTH-1 downto 0);
    signal taylor_dft_valid     : std_logic;

    signal taylor_freq_int      : std_logic_vector(FREQ_WIDTH-1 downto 0);
    signal taylor_freq_valid_int: std_logic;
    signal taylor_rocof_int     : std_logic_vector(FREQ_WIDTH-1 downto 0);
    signal transient_det_int    : std_logic;

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
            frequency_estimate  => freq_feedback,
            frequency_valid     => freq_feedback_valid,
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

    muxed_sample_addr <= taylor_sample_addr when taylor_active_int = '1' else dft_sample_addr;
    muxed_cos_addr    <= taylor_cos_addr    when taylor_active_int = '1' else dft_cos_addr;
    muxed_sin_addr    <= taylor_sin_addr    when taylor_active_int = '1' else dft_sin_addr;

    dft_buf_read_addr <= muxed_sample_addr;

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
            n_addr     => muxed_cos_addr,
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
            n_addr     => muxed_sin_addr,
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

    freq_calc_inst: frequency_rocof_calculator_256
        generic map (
            THETA_WIDTH  => PHASE_WIDTH,
            OUTPUT_WIDTH => FREQ_WIDTH
        )
        port map (
            clk           => clk,
            rst           => rst,
            theta_in      => cordic_phase,
            theta_valid   => cordic_valid,
            frequency_out => freq_calc_out,
            freq_valid    => freq_calc_valid,
            rocof_out     => rocof_calc_out,
            rocof_valid   => rocof_calc_valid,
            ready         => freq_calc_ready,
            phase_jump    => open
        );

    freq_damp_inst: freq_damping_filter
        generic map (
            FREQ_WIDTH => FREQ_WIDTH,
            ALPHA      => 19661
        )
        port map (
            clk            => clk,
            rst            => rst,
            freq_in        => freq_calc_out,
            freq_valid     => freq_calc_valid,
            freq_out       => damped_freq_out,
            freq_out_valid => damped_freq_valid,
            freq_init      => INIT_FREQ_50HZ,
            diff_out       => open,
            initialized    => open
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

    freq_feedback_process: process(clk, rst)
    begin
        if rst = '1' then
            freq_feedback <= INIT_FREQ_50HZ;
            freq_feedback_valid <= '0';
            freq_measurement_count <= (others => '0');
        elsif rising_edge(clk) then

            if freq_calc_valid = '1' and freq_measurement_count < 2 then
                freq_measurement_count <= freq_measurement_count + 1;
            end if;

            if freq_measurement_count < 2 then

                freq_feedback <= INIT_FREQ_50HZ;
                freq_feedback_valid <= '1';
            else

                freq_feedback_valid <= '0';
                if damped_freq_valid = '1' then
                    freq_feedback <= damped_freq_out;
                    freq_feedback_valid <= '1';
                end if;
            end if;
        end if;
    end process;

    system_ready_process: process(clk, rst)
    begin
        if rst = '1' then
            system_ready_int <= '0';
        elsif rising_edge(clk) then
            if enable = '1' and resamp_ready = '1' and freq_calc_ready = '1' then
                system_ready_int <= '1';
            else
                system_ready_int <= '0';
            end if;
        end if;
    end process;

    taylor_trigger_process: process(clk, rst)
    begin
        if rst = '1' then
            dft_done_prev    <= '0';
            taylor_dft_start <= '0';
        elsif rising_edge(clk) then
            dft_done_prev    <= dft_done;

            if dft_done = '1' and dft_done_prev = '0' then
                taylor_dft_start <= '1';
            else
                taylor_dft_start <= '0';
            end if;
        end if;
    end process;

    taylor_rom_inst: taylor_window_rom
        generic map (
            WINDOW_SIZE => DFT_SIZE,
            COEFF_WIDTH => COEFF_WIDTH
        )
        port map (
            clk      => clk,
            rst      => rst,
            addr     => taylor_win_addr,
            w1_coeff => tw_w1_coeff,
            w2_coeff => tw_w2_coeff
        );

    taylor_dft_inst: taylor_dft_calculator
        generic map (
            WINDOW_SIZE       => DFT_SIZE,
            SAMPLE_WIDTH      => SAMPLE_WIDTH,
            COEFF_WIDTH       => COEFF_WIDTH,
            ACCUMULATOR_WIDTH => 48,
            OUTPUT_WIDTH      => DFT_OUTPUT_WIDTH
        )
        port map (
            clk           => clk,
            rst           => rst,
            start         => taylor_dft_start,
            done          => open,
            taylor_active => taylor_active_int,
            sample_data   => dft_buf_read_data,
            sample_addr   => taylor_sample_addr,
            cos_coeff     => cos_coeff,
            cos_addr      => taylor_cos_addr,
            sin_coeff     => sin_coeff,
            sin_addr      => taylor_sin_addr,
            taylor_addr   => taylor_win_addr,
            w1_coeff      => tw_w1_coeff,
            w2_coeff      => tw_w2_coeff,
            c0_real       => taylor_c0_real,
            c0_imag       => taylor_c0_imag,
            c1_real       => taylor_c1_real,
            c1_imag       => taylor_c1_imag,
            c2_real       => taylor_c2_real,
            c2_imag       => taylor_c2_imag,
            result_valid  => taylor_dft_valid
        );

    taylor_freq_inst: taylor_frequency_estimator
        generic map (
            INPUT_WIDTH => DFT_OUTPUT_WIDTH,
            FREQ_WIDTH  => FREQ_WIDTH,
            FRAC_BITS   => FRAC_BITS
        )
        port map (
            clk                => clk,
            rst                => rst,
            c0_real            => taylor_c0_real,
            c0_imag            => taylor_c0_imag,
            c1_real            => taylor_c1_real,
            c1_imag            => taylor_c1_imag,
            taylor_valid       => taylor_dft_valid,
            std_frequency      => freq_calc_out,
            std_freq_valid     => freq_calc_valid,
            taylor_frequency   => taylor_freq_int,
            taylor_freq_valid  => taylor_freq_valid_int,
            transient_detected => transient_det_int,
            taylor_rocof       => taylor_rocof_int
        );

    debug_monitor: process(clk)
        variable freq_valid_seen : boolean := false;
        variable resamp_valid_seen : boolean := false;
        variable cycle_complete_seen : boolean := false;
        variable dft_buf_full_seen : boolean := false;
        variable dft_valid_seen : boolean := false;
        variable phasor_valid_seen : boolean := false;
        variable sample_counter : integer := 0;
    begin
        if rising_edge(clk) then

            if adc_valid = '1' then
                sample_counter := sample_counter + 1;
                if sample_counter = 50 or sample_counter = 100 or
                   sample_counter = 200 or sample_counter = 300 then
                    report ">>> [DEBUG] Received " & integer'image(sample_counter) & " input samples" severity note;
                end if;
            end if;

            if freq_feedback_valid = '1' and not freq_valid_seen then
                report ">>> [DEBUG] freq_feedback_valid = 1 (initialization frequency active - FIX IS WORKING)" severity note;
                freq_valid_seen := true;
            end if;

            if resamp_valid = '1' and not resamp_valid_seen then
                report ">>> [DEBUG] Resampler output valid (resampling started)" severity note;
                resamp_valid_seen := true;
            end if;

            if resamp_cycle_complete = '1' and not cycle_complete_seen then
                report ">>> [DEBUG] First cycle_complete detected (resampler found cycle boundary)" severity note;
                cycle_complete_seen := true;
            end if;

            if dft_buf_full = '1' and not dft_buf_full_seen then
                report ">>> [DEBUG] DFT buffer full (256 samples ready for DFT)" severity note;
                dft_buf_full_seen := true;
            end if;

            if dft_result_valid = '1' and not dft_valid_seen then
                report ">>> [DEBUG] DFT result valid (DFT calculation complete)" severity note;
                dft_valid_seen := true;
            end if;

            if cordic_valid = '1' and not phasor_valid_seen then
                report ">>> [DEBUG] First phasor valid (CORDIC complete, magnitude/phase ready)" severity note;
                phasor_valid_seen := true;
            end if;
        end if;
    end process;

    phasor_magnitude <= cordic_magnitude;
    phasor_phase     <= cordic_phase;
    phasor_valid     <= cordic_valid;

    dft_real_out     <= dft_real_result;
    dft_imag_out     <= dft_imag_result;
    dft_valid_out    <= dft_result_valid;

    frequency_out    <= freq_calc_out;
    freq_valid       <= freq_calc_valid;

    rocof_out        <= rocof_calc_out;
    rocof_valid      <= rocof_calc_valid;

    cycle_complete   <= resamp_cycle_complete;
    dft_busy         <= dft_busy_int;
    cordic_busy      <= cordic_busy_int;
    system_ready     <= system_ready_int;

    samples_per_cycle <= resamp_spc;
    cycle_count       <= resamp_cycle_count;

    taylor_frequency_out <= taylor_freq_int;
    taylor_freq_valid    <= taylor_freq_valid_int;
    taylor_rocof_out     <= taylor_rocof_int;
    transient_detected   <= transient_det_int;

end structural;
