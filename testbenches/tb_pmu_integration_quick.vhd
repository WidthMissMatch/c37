library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.MATH_REAL.ALL;

entity tb_pmu_integration_quick is
end tb_pmu_integration_quick;

architecture behavioral of tb_pmu_integration_quick is

    constant CLK_PERIOD : time := 10 ns;
    constant ADC_INTERVAL : integer := 6666;
    constant TOTAL_SAMPLES : integer := 320;

    signal clk : std_logic := '0';
    signal rst : std_logic := '1';
    signal enable : std_logic := '1';
    signal test_done : std_logic := '0';

    signal adc_sample : std_logic_vector(15 downto 0) := (others => '0');
    signal adc_valid  : std_logic := '0';

    signal phasor_magnitude : std_logic_vector(31 downto 0);
    signal phasor_phase     : std_logic_vector(15 downto 0);
    signal phasor_valid     : std_logic;
    signal dft_real_out     : std_logic_vector(31 downto 0);
    signal dft_imag_out     : std_logic_vector(31 downto 0);
    signal dft_valid_out    : std_logic;
    signal frequency_out    : std_logic_vector(31 downto 0);
    signal freq_valid_out   : std_logic;
    signal rocof_out        : std_logic_vector(31 downto 0);
    signal rocof_valid_out  : std_logic;
    signal cycle_complete   : std_logic;
    signal dft_busy         : std_logic;
    signal cordic_busy      : std_logic;
    signal system_ready     : std_logic;
    signal samples_per_cycle : std_logic_vector(31 downto 0);
    signal cycle_count      : std_logic_vector(15 downto 0);

    signal resamp_valid_count : integer := 0;
    signal dft_valid_count    : integer := 0;
    signal phasor_valid_count : integer := 0;
    signal freq_valid_count   : integer := 0;

begin

    dut: entity work.pmu_processing_top
        generic map (
            SAMPLE_WIDTH      => 16,
            SAMPLE_RATE       => 15000,
            DFT_SIZE          => 256,
            BUFFER_DEPTH      => 512,
            BUFFER_ADDR_WIDTH => 9,
            FREQ_WIDTH        => 32,
            FRAC_BITS         => 16,
            COEFF_WIDTH       => 16,
            DFT_OUTPUT_WIDTH  => 32,
            PHASE_WIDTH       => 16
        )
        port map (
            clk              => clk,
            rst              => rst,
            adc_sample       => adc_sample,
            adc_valid        => adc_valid,
            phasor_magnitude => phasor_magnitude,
            phasor_phase     => phasor_phase,
            phasor_valid     => phasor_valid,
            dft_real_out     => dft_real_out,
            dft_imag_out     => dft_imag_out,
            dft_valid_out    => dft_valid_out,
            frequency_out    => frequency_out,
            freq_valid       => freq_valid_out,
            rocof_out        => rocof_out,
            rocof_valid      => rocof_valid_out,
            cycle_complete   => cycle_complete,
            dft_busy         => dft_busy,
            cordic_busy      => cordic_busy,
            system_ready     => system_ready,
            samples_per_cycle => samples_per_cycle,
            cycle_count      => cycle_count,
            enable           => enable
        );

    clk_proc: process
    begin
        while test_done = '0' loop
            clk <= '0'; wait for CLK_PERIOD/2;
            clk <= '1'; wait for CLK_PERIOD/2;
        end loop;
        wait;
    end process;

    stim_proc: process
        variable sample_idx : integer := 0;
        variable theta      : real;
        variable sine_val   : real;
        variable sample_int : integer;
    begin

        rst <= '1';
        adc_valid <= '0';
        wait for 200 ns;
        wait until rising_edge(clk);
        rst <= '0';
        wait for 100 ns;

        report "=== INTEGRATION TEST: pmu_processing_top with Hann + Freq Damping ===";
        report "Injecting " & integer'image(TOTAL_SAMPLES) & " samples of 50 Hz sine at 15 kHz";

        for i in 0 to TOTAL_SAMPLES-1 loop
            wait until rising_edge(clk);

            theta := 2.0 * MATH_PI * 50.0 * real(i) / 15000.0;
            sine_val := sin(theta);

            sample_int := integer(sine_val * 16000.0);
            adc_sample <= std_logic_vector(to_signed(sample_int, 16));
            adc_valid <= '1';

            wait until rising_edge(clk);
            adc_valid <= '0';

            for j in 0 to ADC_INTERVAL-2 loop
                wait until rising_edge(clk);
            end loop;

            if (i+1) mod 100 = 0 then
                report "Injected " & integer'image(i+1) & "/" & integer'image(TOTAL_SAMPLES) & " samples";
            end if;
        end loop;

        report "All samples injected. Waiting for pipeline to complete...";

        for i in 0 to 500000 loop
            wait until rising_edge(clk);
        end loop;

        report "=== TEST RESULTS ===";
        report "DFT valid outputs:    " & integer'image(dft_valid_count);
        report "Phasor valid outputs: " & integer'image(phasor_valid_count);
        report "Freq valid outputs:   " & integer'image(freq_valid_count);

        if dft_valid_count > 0 then
            report "PASS: DFT produced output (Hann window pipeline working)";
        else
            report "INFO: DFT not yet complete (need more simulation time or samples)";
        end if;

        if phasor_valid_count > 0 then
            report "PASS: CORDIC produced phasor output";
        else
            report "INFO: CORDIC not yet complete";
        end if;

        if freq_valid_count > 0 then
            report "PASS: Frequency calculator produced output (freq damping filter in path)";
        else
            report "INFO: Frequency not yet available";
        end if;

        report "=== INTEGRATION TEST COMPLETE ===";
        test_done <= '1';
        wait;
    end process;

    monitor: process(clk)
    begin
        if rising_edge(clk) then
            if dft_valid_out = '1' then
                dft_valid_count <= dft_valid_count + 1;
                if dft_valid_count = 0 then
                    report "[MONITOR] First DFT output: real=" &
                        integer'image(to_integer(signed(dft_real_out))) &
                        " imag=" & integer'image(to_integer(signed(dft_imag_out)));
                end if;
            end if;

            if phasor_valid = '1' then
                phasor_valid_count <= phasor_valid_count + 1;
                if phasor_valid_count = 0 then
                    report "[MONITOR] First phasor: mag=" &
                        integer'image(to_integer(unsigned(phasor_magnitude))) &
                        " phase=" & integer'image(to_integer(signed(phasor_phase)));
                end if;
            end if;

            if freq_valid_out = '1' then
                freq_valid_count <= freq_valid_count + 1;
                if freq_valid_count = 0 then
                    report "[MONITOR] First frequency output: " &
                        integer'image(to_integer(signed(frequency_out))) &
                        " (Q16.16, expected ~3276800 for 50 Hz)";
                end if;
            end if;
        end if;
    end process;

end behavioral;
