library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.MATH_REAL.ALL;

entity tb_pmu_processing_top_single is
end tb_pmu_processing_top_single;

architecture behavioral of tb_pmu_processing_top_single is

    constant CLK_PERIOD         : time    := 10 ns;
    constant SAMPLE_RATE        : integer := 15000;
    constant GRID_FREQ          : real    := 50.0;
    constant SAMPLES_PER_CYC    : integer := 300;
    constant INTER_SAMPLE_CLKS  : integer := 6667;
    constant NUM_CYCLES         : integer := 5;
    constant TOTAL_SAMPLES      : integer := SAMPLES_PER_CYC * NUM_CYCLES;
    constant V_AMPLITUDE        : real    := 10000.0;

    constant FREQ_48HZ_Q16  : signed(31 downto 0) := x"00300000";
    constant FREQ_52HZ_Q16  : signed(31 downto 0) := x"00340000";

    signal clk  : std_logic := '0';
    signal rst  : std_logic := '1';

    signal enable           : std_logic := '0';
    signal adc_sample       : std_logic_vector(15 downto 0) := (others => '0');
    signal adc_valid        : std_logic := '0';

    signal phasor_magnitude : std_logic_vector(31 downto 0);
    signal phasor_phase     : std_logic_vector(15 downto 0);
    signal phasor_valid     : std_logic;

    signal dft_real_out     : std_logic_vector(31 downto 0);
    signal dft_imag_out     : std_logic_vector(31 downto 0);
    signal dft_valid_out    : std_logic;

    signal frequency_out    : std_logic_vector(31 downto 0);
    signal freq_valid       : std_logic;

    signal rocof_out        : std_logic_vector(31 downto 0);
    signal rocof_valid      : std_logic;

    signal cycle_complete   : std_logic;
    signal dft_busy         : std_logic;
    signal cordic_busy      : std_logic;
    signal system_ready     : std_logic;

    signal samples_per_cycle: std_logic_vector(31 downto 0);
    signal cycle_count      : std_logic_vector(15 downto 0);

    signal stimulus_done    : boolean := false;

    signal system_ready_seen   : boolean := false;
    signal cycle_complete_cnt  : integer := 0;
    signal dft_valid_cnt       : integer := 0;
    signal phasor_valid_cnt    : integer := 0;
    signal freq_valid_cnt      : integer := 0;
    signal first_cycle_time    : time    := 0 ns;
    signal first_dft_time      : time    := 0 ns;
    signal first_phasor_time   : time    := 0 ns;
    signal first_freq_time     : time    := 0 ns;

    type mag_array_t is array(0 to 9) of integer;
    signal phasor_magnitudes   : mag_array_t := (others => 0);
    signal phasor_mag_idx      : integer := 0;
    signal testB_pass          : boolean := true;

    type freq_array_t is array(0 to 9) of integer;
    signal freq_values         : freq_array_t := (others => 0);
    signal freq_val_idx        : integer := 0;
    signal testC_pass          : boolean := true;

    signal testD_pass          : boolean := true;

    signal prev_freq_val       : integer := 0;
    signal freq_jump_count     : integer := 0;
    signal testE_pass          : boolean := true;

    function real_to_slv16(val : real) return std_logic_vector is
        variable int_val : integer;
    begin
        if val >= 32767.0 then
            int_val := 32767;
        elsif val <= -32768.0 then
            int_val := -32768;
        else
            int_val := integer(val);
        end if;
        return std_logic_vector(to_signed(int_val, 16));
    end function;

    component pmu_processing_top is
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
            PHASE_WIDTH       : integer := 16
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
            enable              : in  std_logic
        );
    end component;

begin

    clk <= not clk after CLK_PERIOD / 2;

    dut: pmu_processing_top
        generic map (
            SAMPLE_WIDTH      => 16,
            SAMPLE_RATE       => SAMPLE_RATE,
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
            freq_valid       => freq_valid,
            rocof_out        => rocof_out,
            rocof_valid      => rocof_valid,
            cycle_complete   => cycle_complete,
            dft_busy         => dft_busy,
            cordic_busy      => cordic_busy,
            system_ready     => system_ready,
            samples_per_cycle=> samples_per_cycle,
            cycle_count      => cycle_count,
            enable           => enable
        );

    reset_proc: process
    begin
        rst    <= '1';
        enable <= '0';
        wait for 200 ns;
        rst    <= '0';
        wait for 100 ns;
        enable <= '1';
        report "[INIT] Reset released, enable asserted at " &
               time'image(now) severity note;
        wait;
    end process;

    stimulus_proc: process
        variable theta   : real;
        variable sample  : real;
    begin

        wait until enable = '1';
        wait until rising_edge(clk);

        report "[STIM] Starting stimulus: " & integer'image(TOTAL_SAMPLES) &
               " samples (" & integer'image(NUM_CYCLES) & " cycles)" severity note;

        for n in 0 to TOTAL_SAMPLES - 1 loop

            theta  := 2.0 * MATH_PI * real(n) / real(SAMPLES_PER_CYC);
            sample := V_AMPLITUDE * sin(theta);

            adc_sample <= real_to_slv16(sample);
            adc_valid  <= '1';
            wait until rising_edge(clk);
            adc_valid  <= '0';

            for i in 1 to INTER_SAMPLE_CLKS - 1 loop
                wait until rising_edge(clk);
            end loop;

            if (n + 1) mod SAMPLES_PER_CYC = 0 then
                report "[STIM] Cycle " & integer'image((n + 1) / SAMPLES_PER_CYC) &
                       " complete (" & integer'image(n + 1) & " samples sent) at " &
                       time'image(now) severity note;
            end if;
        end loop;

        report "[STIM] All " & integer'image(TOTAL_SAMPLES) &
               " samples sent at " & time'image(now) severity note;
        stimulus_done <= true;

        wait for 10 ms;
        wait;
    end process;

    test_a_monitor: process(clk)
    begin
        if rising_edge(clk) then

            if system_ready = '1' and not system_ready_seen then
                system_ready_seen <= true;
                report "[TEST A] system_ready asserted at " &
                       time'image(now) severity note;
            end if;

            if cycle_complete = '1' then
                cycle_complete_cnt <= cycle_complete_cnt + 1;
                if cycle_complete_cnt = 0 then
                    first_cycle_time <= now;
                    report "[TEST A] First cycle_complete at " &
                           time'image(now) severity note;
                end if;
            end if;

            if dft_valid_out = '1' then
                dft_valid_cnt <= dft_valid_cnt + 1;
                if dft_valid_cnt = 0 then
                    first_dft_time <= now;
                    report "[TEST A] First dft_valid_out at " &
                           time'image(now) severity note;
                end if;
            end if;

            if phasor_valid = '1' then
                phasor_valid_cnt <= phasor_valid_cnt + 1;
                if phasor_valid_cnt = 0 then
                    first_phasor_time <= now;
                    report "[TEST A] First phasor_valid at " &
                           time'image(now) severity note;
                end if;
            end if;

            if freq_valid = '1' then
                freq_valid_cnt <= freq_valid_cnt + 1;
                if freq_valid_cnt = 0 then
                    first_freq_time <= now;
                    report "[TEST A] First freq_valid at " &
                           time'image(now) severity note;
                end if;
            end if;
        end if;
    end process;

    test_b_phasor: process(clk)
        variable mag_int : integer;
    begin
        if rising_edge(clk) then
            if phasor_valid = '1' then
                mag_int := to_integer(signed(phasor_magnitude));

                if phasor_mag_idx < 10 then
                    phasor_magnitudes(phasor_mag_idx) <= mag_int;
                    phasor_mag_idx <= phasor_mag_idx + 1;
                end if;

                if mag_int = 0 then
                    report "[TEST B] WARNING: phasor_magnitude is ZERO at phasor #" &
                           integer'image(phasor_mag_idx) severity warning;
                    testB_pass <= false;
                end if;

                if abs(mag_int) < 1000 and phasor_mag_idx > 1 then
                    report "[TEST B] WARNING: phasor_magnitude too small: " &
                           integer'image(mag_int) & " at phasor #" &
                           integer'image(phasor_mag_idx) severity warning;
                    testB_pass <= false;
                end if;

                report "[TEST B] Phasor #" & integer'image(phasor_mag_idx) &
                       ": magnitude=" & integer'image(mag_int) &
                       ", phase=0x" &
                       integer'image(to_integer(signed(phasor_phase)))
                       severity note;
            end if;
        end if;
    end process;

    test_c_freq: process(clk)
        variable freq_int  : integer;
        variable freq_hz_x10 : integer;
    begin
        if rising_edge(clk) then
            if freq_valid = '1' then
                freq_int := to_integer(signed(frequency_out));

                if freq_val_idx < 10 then
                    freq_values(freq_val_idx) <= freq_int;
                    freq_val_idx <= freq_val_idx + 1;
                end if;

                freq_hz_x10 := (freq_int * 10) / 65536;

                report "[TEST C] Frequency #" & integer'image(freq_val_idx) &
                       ": Q16.16=0x" &
                       integer'image(freq_int) &
                       " (~" & integer'image(freq_hz_x10 / 10) &
                       "." & integer'image(freq_hz_x10 mod 10) & " Hz)"
                       severity note;

                if freq_val_idx >= 2 then
                    if signed(frequency_out) < FREQ_48HZ_Q16 or
                       signed(frequency_out) > FREQ_52HZ_Q16 then
                        report "[TEST C] WARNING: Frequency outside 48-52 Hz range at #" &
                               integer'image(freq_val_idx) &
                               ": raw=" & integer'image(freq_int)
                               severity warning;
                        testC_pass <= false;
                    end if;
                end if;
            end if;
        end if;
    end process;

    test_e_damping: process(clk)
        variable freq_int  : integer;
        variable diff      : integer;
    begin
        if rising_edge(clk) then
            if freq_valid = '1' then
                freq_int := to_integer(signed(frequency_out));

                if freq_val_idx > 2 and prev_freq_val /= 0 then
                    diff := abs(freq_int - prev_freq_val);
                    if diff > 131072 then
                        freq_jump_count <= freq_jump_count + 1;
                        report "[TEST E] WARNING: Large frequency jump: " &
                               integer'image(diff) & " Q16.16 units (~" &
                               integer'image(diff / 65536) & " Hz) at measurement #" &
                               integer'image(freq_val_idx)
                               severity warning;
                    end if;
                end if;

                prev_freq_val <= freq_int;
            end if;
        end if;
    end process;

    status_monitor: process
    begin
        wait for 20 ms;
        while not stimulus_done loop
            report "[STATUS] t=" & time'image(now) &
                   " cycles=" & integer'image(cycle_complete_cnt) &
                   " dft=" & integer'image(dft_valid_cnt) &
                   " phasor=" & integer'image(phasor_valid_cnt) &
                   " freq=" & integer'image(freq_valid_cnt) &
                   " ready=" & std_logic'image(system_ready)
                   severity note;
            wait for 20 ms;
        end loop;
        wait;
    end process;

    final_report: process
        variable testA_pass : boolean := true;
        variable mag_min    : integer := 2147483647;
        variable mag_max    : integer := 0;
        variable all_pass   : boolean := true;
    begin

        wait for 150 ms;

        report "============================================" severity note;
        report "  SINGLE-CHANNEL PMU PROCESSING TOP TEST   " severity note;
        report "  FINAL TEST RESULTS                       " severity note;
        report "============================================" severity note;
        report "" severity note;

        report "[TEST A] Pipeline Activity Checks:" severity note;
        report "  system_ready seen:  " & boolean'image(system_ready_seen) severity note;
        report "  cycle_complete cnt: " & integer'image(cycle_complete_cnt) &
               " (expected >= 3)" severity note;
        report "  dft_valid cnt:      " & integer'image(dft_valid_cnt) &
               " (expected >= 2)" severity note;
        report "  phasor_valid cnt:   " & integer'image(phasor_valid_cnt) &
               " (expected >= 2)" severity note;
        report "  freq_valid cnt:     " & integer'image(freq_valid_cnt) &
               " (expected >= 2)" severity note;

        if first_cycle_time > 0 ns then
            report "  First cycle_complete: " & time'image(first_cycle_time) severity note;
        end if;
        if first_dft_time > 0 ns then
            report "  First dft_valid:      " & time'image(first_dft_time) severity note;
        end if;
        if first_phasor_time > 0 ns then
            report "  First phasor_valid:   " & time'image(first_phasor_time) severity note;
        end if;
        if first_freq_time > 0 ns then
            report "  First freq_valid:     " & time'image(first_freq_time) severity note;
        end if;

        if not system_ready_seen then
            report "  FAIL: system_ready never asserted" severity warning;
            testA_pass := false;
        end if;
        if cycle_complete_cnt < 3 then
            report "  FAIL: Too few cycle_complete pulses" severity warning;
            testA_pass := false;
        end if;
        if dft_valid_cnt < 2 then
            report "  FAIL: Too few dft_valid pulses" severity warning;
            testA_pass := false;
        end if;
        if phasor_valid_cnt < 2 then
            report "  FAIL: Too few phasor_valid pulses" severity warning;
            testA_pass := false;
        end if;
        if freq_valid_cnt < 2 then
            report "  FAIL: Too few freq_valid pulses" severity warning;
            testA_pass := false;
        end if;

        if testA_pass then
            report "[TEST A] PASSED - All pipeline stages active" severity note;
        else
            report "[TEST A] FAILED - Pipeline activity incomplete" severity note;
            all_pass := false;
        end if;
        report "" severity note;

        report "[TEST B] Phasor Output Verification:" severity note;
        report "  Phasor measurements received: " & integer'image(phasor_mag_idx) severity note;

        for i in 0 to phasor_mag_idx - 1 loop
            report "  Mag[" & integer'image(i) & "] = " &
                   integer'image(phasor_magnitudes(i)) severity note;
        end loop;

        if not testB_pass then
            report "[TEST B] FAILED - Magnitude out of range or zero" severity note;
            all_pass := false;
        elsif phasor_mag_idx < 2 then
            report "[TEST B] FAILED - Insufficient phasor outputs" severity note;
            all_pass := false;
        else
            report "[TEST B] PASSED - Phasor magnitudes in acceptable range" severity note;
        end if;
        report "" severity note;

        report "[TEST C] Frequency Output Verification:" severity note;
        report "  Frequency measurements received: " & integer'image(freq_val_idx) severity note;

        for i in 0 to freq_val_idx - 1 loop
            report "  Freq[" & integer'image(i) & "] = " &
                   integer'image(freq_values(i)) &
                   " (~" & integer'image((freq_values(i) * 10) / 65536 / 10) &
                   "." & integer'image(((freq_values(i) * 10) / 65536) mod 10) &
                   " Hz)" severity note;
        end loop;

        if not testC_pass then
            report "[TEST C] FAILED - Frequency outside ±2 Hz of 50 Hz" severity note;
            all_pass := false;
        elsif freq_val_idx < 2 then
            report "[TEST C] FAILED - Insufficient frequency outputs" severity note;
            all_pass := false;
        else
            report "[TEST C] PASSED - Frequency within expected range" severity note;
        end if;
        report "" severity note;

        report "[TEST D] Hann Window Confirmation (indirect):" severity note;

        if phasor_mag_idx >= 2 then

            mag_min := abs(phasor_magnitudes(0));
            mag_max := abs(phasor_magnitudes(0));
            for i in 1 to phasor_mag_idx - 1 loop
                if abs(phasor_magnitudes(i)) < mag_min then
                    mag_min := abs(phasor_magnitudes(i));
                end if;
                if abs(phasor_magnitudes(i)) > mag_max then
                    mag_max := abs(phasor_magnitudes(i));
                end if;
            end loop;

            report "  Magnitude range: " & integer'image(mag_min) &
                   " to " & integer'image(mag_max) severity note;

            if mag_min = 0 then
                report "[TEST D] FAILED - Zero magnitude detected (hann may be zeroing all)" severity note;
                testD_pass <= false;
                all_pass := false;
            else

                if mag_max > mag_min * 10 then
                    report "[TEST D] FAILED - Magnitude spread too large (>10x)" severity note;
                    testD_pass <= false;
                    all_pass := false;
                else
                    report "[TEST D] PASSED - Magnitude consistent across cycles (hann integrated)" severity note;
                end if;
            end if;
        else
            report "[TEST D] FAILED - Insufficient phasor data for hann check" severity note;
            all_pass := false;
        end if;
        report "" severity note;

        report "[TEST E] Freq Damping Confirmation:" severity note;
        report "  Large frequency jumps detected: " &
               integer'image(freq_jump_count) severity note;

        if freq_jump_count > 1 then
            report "[TEST E] FAILED - Too many frequency jumps (damping not smoothing)" severity note;
            all_pass := false;
        elsif freq_val_idx < 2 then
            report "[TEST E] FAILED - Insufficient frequency data for damping check" severity note;
            all_pass := false;
        else
            report "[TEST E] PASSED - Frequency converges smoothly" severity note;
        end if;
        report "" severity note;

        report "============================================" severity note;
        if all_pass then
            report "ALL TESTS PASSED" severity note;
        else
            report "SOME TESTS FAILED" severity note;
        end if;
        report "============================================" severity note;
        report "" severity note;

        report "  Total cycle_complete: " & integer'image(cycle_complete_cnt) severity note;
        report "  Total phasor_valid:   " & integer'image(phasor_valid_cnt) severity note;
        report "  Total freq_valid:     " & integer'image(freq_valid_cnt) severity note;
        report "  Stimulus complete:    " & boolean'image(stimulus_done) severity note;
        report "" severity note;

        assert false
            report "Simulation finished at " & time'image(now)
            severity failure;
        wait;
    end process;

end behavioral;
