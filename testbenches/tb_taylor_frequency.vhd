library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.MATH_REAL.ALL;

entity tb_taylor_frequency is
end tb_taylor_frequency;

architecture behavioral of tb_taylor_frequency is

    constant CLK_PERIOD : time := 10 ns;
    constant DFT_N      : integer := 256;
    constant SAMPLE_W   : integer := 16;
    constant COEFF_W    : integer := 16;
    constant ACC_W      : integer := 48;
    constant OUT_W      : integer := 32;
    constant FREQ_W     : integer := 32;

    constant FREQ_50HZ_Q16  : integer := 3276800;
    constant FREQ_49P5_Q16  : integer := 3244032;
    constant FREQ_50P5_Q16  : integer := 3309568;

    constant TOL_0P05HZ : integer := 3277;
    constant TOL_0P1HZ  : integer := 6554;
    constant TOL_0P2HZ  : integer := 13107;
    constant TOL_0P5HZ  : integer := 32768;
    constant TOL_1P0HZ  : integer := 65536;
    constant TOL_2P0HZ  : integer := 131072;
    constant TOL_3P0HZ  : integer := 196608;

    signal clk : std_logic := '0';
    signal rst : std_logic := '1';

    type sample_buf_type is array (0 to DFT_N-1) of signed(SAMPLE_W-1 downto 0);
    signal sample_buffer : sample_buf_type := (others => (others => '0'));

    type coeff_rom_type is array (0 to DFT_N-1) of signed(COEFF_W-1 downto 0);

    function init_cos_rom return coeff_rom_type is
        variable rom : coeff_rom_type;
        variable angle : real;
        variable val : integer;
    begin
        for n in 0 to DFT_N-1 loop
            angle := 2.0 * MATH_PI * real(n) / real(DFT_N);
            val := integer(cos(angle) * 32767.0);
            if val > 32767 then val := 32767; end if;
            if val < -32768 then val := -32768; end if;
            rom(n) := to_signed(val, COEFF_W);
        end loop;
        return rom;
    end function;

    function init_sin_rom return coeff_rom_type is
        variable rom : coeff_rom_type;
        variable angle : real;
        variable val : integer;
    begin
        for n in 0 to DFT_N-1 loop
            angle := 2.0 * MATH_PI * real(n) / real(DFT_N);
            val := integer(sin(angle) * 32767.0);
            if val > 32767 then val := 32767; end if;
            if val < -32768 then val := -32768; end if;
            rom(n) := to_signed(val, COEFF_W);
        end loop;
        return rom;
    end function;

    constant COS_ROM : coeff_rom_type := init_cos_rom;
    constant SIN_ROM : coeff_rom_type := init_sin_rom;

    function init_hann_rom return coeff_rom_type is
        variable rom : coeff_rom_type;
        variable val : integer;
    begin
        for n in 0 to DFT_N-1 loop
            val := integer(0.5 * (1.0 - cos(2.0 * MATH_PI * real(n) / real(DFT_N))) * 32767.0);
            if val > 32767 then val := 32767; end if;
            rom(n) := to_signed(val, COEFF_W);
        end loop;
        return rom;
    end function;

    constant HANN_ROM : coeff_rom_type := init_hann_rom;

    signal taylor_sample_addr : std_logic_vector(7 downto 0);
    signal taylor_cos_addr    : std_logic_vector(7 downto 0);
    signal taylor_sin_addr    : std_logic_vector(7 downto 0);
    signal taylor_w_addr      : std_logic_vector(7 downto 0);

    signal sample_data_out    : std_logic_vector(SAMPLE_W-1 downto 0);
    signal cos_data_out       : std_logic_vector(COEFF_W-1 downto 0);
    signal sin_data_out       : std_logic_vector(COEFF_W-1 downto 0);
    signal w1_data_out        : std_logic_vector(COEFF_W-1 downto 0);
    signal w2_data_out        : std_logic_vector(COEFF_W-1 downto 0);

    signal taylor_start       : std_logic := '0';
    signal taylor_done        : std_logic;
    signal taylor_active      : std_logic;

    signal c0_real, c0_imag   : std_logic_vector(OUT_W-1 downto 0);
    signal c1_real, c1_imag   : std_logic_vector(OUT_W-1 downto 0);
    signal c2_real, c2_imag   : std_logic_vector(OUT_W-1 downto 0);
    signal taylor_result_valid : std_logic;

    signal taylor_frequency   : std_logic_vector(FREQ_W-1 downto 0);
    signal taylor_freq_valid  : std_logic;
    signal transient_detected : std_logic;
    signal taylor_rocof       : std_logic_vector(FREQ_W-1 downto 0);

    signal std_frequency      : std_logic_vector(FREQ_W-1 downto 0) := x"00320000";
    signal std_freq_valid     : std_logic := '0';

    signal test_num           : integer := 0;

begin

    clk <= not clk after CLK_PERIOD / 2;

    rom_read: process(clk)
        variable s_addr : integer range 0 to DFT_N-1;
        variable c_addr : integer range 0 to DFT_N-1;
        variable n_addr : integer range 0 to DFT_N-1;
    begin
        if rising_edge(clk) then
            s_addr := to_integer(unsigned(taylor_sample_addr));
            sample_data_out <= std_logic_vector(sample_buffer(s_addr));

            c_addr := to_integer(unsigned(taylor_cos_addr));
            cos_data_out <= std_logic_vector(COS_ROM(c_addr));

            n_addr := to_integer(unsigned(taylor_sin_addr));
            sin_data_out <= std_logic_vector(SIN_ROM(n_addr));
        end if;
    end process;

    taylor_rom_inst: entity work.taylor_window_rom
        generic map (
            WINDOW_SIZE => DFT_N,
            COEFF_WIDTH => COEFF_W
        )
        port map (
            clk      => clk,
            rst      => rst,
            addr     => taylor_w_addr,
            w1_coeff => w1_data_out,
            w2_coeff => w2_data_out
        );

    taylor_dft_inst: entity work.taylor_dft_calculator
        generic map (
            WINDOW_SIZE       => DFT_N,
            SAMPLE_WIDTH      => SAMPLE_W,
            COEFF_WIDTH       => COEFF_W,
            ACCUMULATOR_WIDTH => ACC_W,
            OUTPUT_WIDTH      => OUT_W
        )
        port map (
            clk           => clk,
            rst           => rst,
            start         => taylor_start,
            done          => taylor_done,
            taylor_active => taylor_active,
            sample_data   => sample_data_out,
            sample_addr   => taylor_sample_addr,
            cos_coeff     => cos_data_out,
            cos_addr      => taylor_cos_addr,
            sin_coeff     => sin_data_out,
            sin_addr      => taylor_sin_addr,
            taylor_addr   => taylor_w_addr,
            w1_coeff      => w1_data_out,
            w2_coeff      => w2_data_out,
            c0_real       => c0_real,
            c0_imag       => c0_imag,
            c1_real       => c1_real,
            c1_imag       => c1_imag,
            c2_real       => c2_real,
            c2_imag       => c2_imag,
            result_valid  => taylor_result_valid
        );

    taylor_freq_inst: entity work.taylor_frequency_estimator
        generic map (
            INPUT_WIDTH => OUT_W,
            FREQ_WIDTH  => FREQ_W,
            FRAC_BITS   => 16
        )
        port map (
            clk                => clk,
            rst                => rst,
            c0_real            => c0_real,
            c0_imag            => c0_imag,
            c1_real            => c1_real,
            c1_imag            => c1_imag,
            taylor_valid       => taylor_result_valid,
            std_frequency      => std_frequency,
            std_freq_valid     => std_freq_valid,
            taylor_frequency   => taylor_frequency,
            taylor_freq_valid  => taylor_freq_valid,
            transient_detected => transient_detected,
            taylor_rocof       => taylor_rocof
        );

    stim: process
        variable pass_count : integer := 0;
        variable fail_count : integer := 0;
        variable angle : real;
        variable sample_val : integer;
        variable hann_val : real;
        variable windowed : real;
        variable t : real;
        variable actual_freq : integer;
        variable actual_rocof : integer;
        variable freq_error : integer;
        variable timed_out : boolean;

        type real_array is array (natural range <>) of real;
        type int_array is array (natural range <>) of integer;

        constant SWEEP_FREQS : real_array(0 to 6) :=
            (45.0, 47.0, 49.0, 50.0, 51.0, 53.0, 55.0);
        constant SWEEP_EXPECTED : int_array(0 to 6) :=
            (2949120, 3080192, 3211264, 3276800, 3342336, 3473408, 3604480);

        constant SWEEP_TOL : int_array(0 to 6) :=
            (TOL_3P0HZ, TOL_2P0HZ, TOL_1P0HZ, TOL_0P2HZ, TOL_1P0HZ, TOL_2P0HZ, TOL_3P0HZ);

        constant PHASE_VALUES : real_array(0 to 3) :=
            (0.0, MATH_PI/4.0, MATH_PI/2.0, 3.0*MATH_PI/4.0);

        constant AMP_VALUES : real_array(0 to 3) :=
            (4096.0, 8192.0, 16384.0, 24576.0);

        procedure fill_buffer_ext(freq : real; phase : real; amplitude : real) is
            constant SAMPLE_INTERVAL : real := 1.0 / (real(DFT_N) * 50.0);
            variable t_val : real;
            variable a_val : real;
            variable h_val : real;
            variable w_val : real;
            variable s_val : integer;
        begin
            for n in 0 to DFT_N-1 loop
                t_val := real(n) * SAMPLE_INTERVAL;
                a_val := 2.0 * MATH_PI * freq * t_val + phase;
                h_val := 0.5 * (1.0 - cos(2.0 * MATH_PI * real(n) / real(DFT_N)));
                w_val := amplitude * sin(a_val) * h_val;
                s_val := integer(w_val);
                if s_val > 32767 then s_val := 32767; end if;
                if s_val < -32768 then s_val := -32768; end if;
                sample_buffer(n) <= to_signed(s_val, SAMPLE_W);
            end loop;
        end procedure;

        procedure fill_buffer(freq : real) is
        begin
            fill_buffer_ext(freq, 0.0, 16384.0);
        end procedure;

        procedure fill_buffer_zero is
        begin
            for n in 0 to DFT_N-1 loop
                sample_buffer(n) <= (others => '0');
            end loop;
        end procedure;

        procedure fill_buffer_chirp(f_start : real; f_end : real) is
            variable inst_freq : real;
            variable phase_acc : real;
            variable t_frac : real;
            constant SAMPLE_INTERVAL : real := 1.0 / (real(DFT_N) * 50.0);
            variable h_val : real;
            variable w_val : real;
            variable s_val : integer;
        begin
            phase_acc := 0.0;
            for n in 0 to DFT_N-1 loop
                t_frac := real(n) / real(DFT_N);
                inst_freq := f_start + (f_end - f_start) * t_frac;
                phase_acc := phase_acc + 2.0 * MATH_PI * inst_freq * SAMPLE_INTERVAL;
                h_val := 0.5 * (1.0 - cos(2.0 * MATH_PI * real(n) / real(DFT_N)));
                w_val := 16384.0 * sin(phase_acc) * h_val;
                s_val := integer(w_val);
                if s_val > 32767 then s_val := 32767; end if;
                if s_val < -32768 then s_val := -32768; end if;
                sample_buffer(n) <= to_signed(s_val, SAMPLE_W);
            end loop;
        end procedure;

        procedure fill_buffer_harmonic is
            variable a_val : real;
            variable h_val : real;
            variable w_val : real;
            variable s_val : integer;
        begin
            for n in 0 to DFT_N-1 loop
                a_val := 2.0 * MATH_PI * real(n) / real(DFT_N);
                h_val := 0.5 * (1.0 - cos(2.0 * MATH_PI * real(n) / real(DFT_N)));
                w_val := 16384.0 * (sin(a_val) + 0.05 * sin(3.0 * a_val)) * h_val;
                s_val := integer(w_val);
                if s_val > 32767 then s_val := 32767; end if;
                if s_val < -32768 then s_val := -32768; end if;
                sample_buffer(n) <= to_signed(s_val, SAMPLE_W);
            end loop;
        end procedure;

        procedure check_freq(
            test_name : string;
            expected  : integer;
            tolerance : integer;
            actual    : integer
        ) is
            variable err : integer;
        begin
            if actual >= expected then
                err := actual - expected;
            else
                err := expected - actual;
            end if;
            if err <= tolerance then
                report test_name & ": PASS freq=" &
                    integer'image(actual) & " exp=" &
                    integer'image(expected) & " err=" &
                    integer'image(err) severity note;
                pass_count := pass_count + 1;
            else
                report test_name & ": FAIL freq=" &
                    integer'image(actual) & " exp=" &
                    integer'image(expected) & " err=" &
                    integer'image(err) & " tol=" &
                    integer'image(tolerance) severity error;
                fail_count := fail_count + 1;
            end if;
        end procedure;

        procedure check_trans(
            test_name : string;
            expected  : std_logic;
            actual    : std_logic
        ) is
        begin
            if actual = expected then
                report test_name & ": PASS transient=" &
                    std_logic'image(actual) severity note;
                pass_count := pass_count + 1;
            else
                report test_name & ": FAIL transient=" &
                    std_logic'image(actual) & " exp=" &
                    std_logic'image(expected) severity error;
                fail_count := fail_count + 1;
            end if;
        end procedure;

        procedure check_rocof_sign(
            test_name     : string;
            sign_expected : integer;
            actual        : integer
        ) is
            variable ok : boolean;
        begin
            case sign_expected is
                when 1  => ok := actual > 0;
                when -1 => ok := actual < 0;
                when others => ok := (actual > -TOL_0P5HZ) and (actual < TOL_0P5HZ);
            end case;
            if ok then
                report test_name & ": PASS rocof=" &
                    integer'image(actual) severity note;
                pass_count := pass_count + 1;
            else
                report test_name & ": FAIL rocof=" &
                    integer'image(actual) & " expected_sign=" &
                    integer'image(sign_expected) severity error;
                fail_count := fail_count + 1;
            end if;
        end procedure;

        procedure do_reset is
        begin
            rst <= '1';
            taylor_start <= '0';

        end procedure;

    begin

        rst <= '1';
        taylor_start <= '0';
        wait for CLK_PERIOD * 10;
        rst <= '0';
        wait for CLK_PERIOD * 5;

        std_freq_valid <= '1';
        wait for CLK_PERIOD;
        std_freq_valid <= '0';
        wait for CLK_PERIOD * 2;

        test_num <= 1;
        report "======= TEST 1: Steady 50 Hz =======" severity note;
        fill_buffer(50.0);
        wait for CLK_PERIOD * 2;

        taylor_start <= '1';
        wait for CLK_PERIOD;
        taylor_start <= '0';

        wait until taylor_freq_valid = '1' for 50 us;
        timed_out := taylor_freq_valid /= '1';
        if timed_out then
            report "T1: FAIL - TIMEOUT" severity error;
            fail_count := fail_count + 3;
        else
            actual_freq := to_integer(unsigned(taylor_frequency));
            actual_rocof := to_integer(signed(taylor_rocof));
            check_freq("T1-freq", FREQ_50HZ_Q16, TOL_0P2HZ, actual_freq);
            check_rocof_sign("T1-rocof", 0, actual_rocof);
            check_trans("T1-transient", '0', transient_detected);
        end if;
        wait for CLK_PERIOD * 10;

        test_num <= 2;
        report "======= TEST 2: Frequency sweep 45-55 Hz =======" severity note;

        for i in 0 to 6 loop
            fill_buffer_ext(SWEEP_FREQS(i), 0.0, 16384.0);
            wait for CLK_PERIOD * 2;

            taylor_start <= '1';
            wait for CLK_PERIOD;
            taylor_start <= '0';

            wait until taylor_freq_valid = '1' for 50 us;
            timed_out := taylor_freq_valid /= '1';
            if timed_out then
                report "T2-" & integer'image(i) & ": FAIL - TIMEOUT" severity error;
                fail_count := fail_count + 1;
            else
                actual_freq := to_integer(unsigned(taylor_frequency));
                check_freq("T2-" & integer'image(integer(SWEEP_FREQS(i))) & "Hz",
                           SWEEP_EXPECTED(i), SWEEP_TOL(i), actual_freq);
            end if;
            wait for CLK_PERIOD * 10;
        end loop;

        rst <= '1';
        taylor_start <= '0';
        wait for CLK_PERIOD * 10;
        rst <= '0';
        wait for CLK_PERIOD * 5;
        std_freq_valid <= '1';
        wait for CLK_PERIOD;
        std_freq_valid <= '0';
        wait for CLK_PERIOD * 2;

        test_num <= 3;
        report "======= TEST 3: Phase sensitivity at 50 Hz =======" severity note;

        for i in 0 to 3 loop
            fill_buffer_ext(50.0, PHASE_VALUES(i), 16384.0);
            wait for CLK_PERIOD * 2;

            taylor_start <= '1';
            wait for CLK_PERIOD;
            taylor_start <= '0';

            wait until taylor_freq_valid = '1' for 50 us;
            timed_out := taylor_freq_valid /= '1';
            if timed_out then
                report "T3-phase" & integer'image(i) & ": FAIL - TIMEOUT" severity error;
                fail_count := fail_count + 1;
            else
                actual_freq := to_integer(unsigned(taylor_frequency));
                check_freq("T3-phase" & integer'image(i),
                           FREQ_50HZ_Q16, TOL_0P2HZ, actual_freq);
            end if;
            wait for CLK_PERIOD * 10;
        end loop;

        test_num <= 4;
        report "======= TEST 4: Phase sensitivity at 49.5 Hz =======" severity note;

        for i in 0 to 3 loop
            fill_buffer_ext(49.5, PHASE_VALUES(i), 16384.0);
            wait for CLK_PERIOD * 2;

            taylor_start <= '1';
            wait for CLK_PERIOD;
            taylor_start <= '0';

            wait until taylor_freq_valid = '1' for 50 us;
            timed_out := taylor_freq_valid /= '1';
            if timed_out then
                report "T4-phase" & integer'image(i) & ": FAIL - TIMEOUT" severity error;
                fail_count := fail_count + 1;
            else
                actual_freq := to_integer(unsigned(taylor_frequency));
                check_freq("T4-phase" & integer'image(i),
                           FREQ_49P5_Q16, TOL_0P5HZ, actual_freq);
            end if;
            wait for CLK_PERIOD * 10;
        end loop;

        rst <= '1';
        taylor_start <= '0';
        wait for CLK_PERIOD * 10;
        rst <= '0';
        wait for CLK_PERIOD * 5;
        std_freq_valid <= '1';
        wait for CLK_PERIOD;
        std_freq_valid <= '0';
        wait for CLK_PERIOD * 2;

        test_num <= 5;
        report "======= TEST 5: Amplitude independence =======" severity note;

        for i in 0 to 3 loop
            fill_buffer_ext(50.0, 0.0, AMP_VALUES(i));
            wait for CLK_PERIOD * 2;

            taylor_start <= '1';
            wait for CLK_PERIOD;
            taylor_start <= '0';

            wait until taylor_freq_valid = '1' for 50 us;
            timed_out := taylor_freq_valid /= '1';
            if timed_out then
                report "T5-amp" & integer'image(i) & ": FAIL - TIMEOUT" severity error;
                fail_count := fail_count + 1;
            else
                actual_freq := to_integer(unsigned(taylor_frequency));
                check_freq("T5-amp" & integer'image(i),
                           FREQ_50HZ_Q16, TOL_0P2HZ, actual_freq);
            end if;
            wait for CLK_PERIOD * 10;
        end loop;

        rst <= '1';
        taylor_start <= '0';
        wait for CLK_PERIOD * 10;
        rst <= '0';
        wait for CLK_PERIOD * 5;
        std_freq_valid <= '1';
        wait for CLK_PERIOD;
        std_freq_valid <= '0';
        wait for CLK_PERIOD * 2;

        test_num <= 6;
        report "======= TEST 6: Low-signal safety (zero input) =======" severity note;
        fill_buffer_zero;
        wait for CLK_PERIOD * 2;

        taylor_start <= '1';
        wait for CLK_PERIOD;
        taylor_start <= '0';

        wait until taylor_freq_valid = '1' for 50 us;
        timed_out := taylor_freq_valid /= '1';
        if timed_out then
            report "T6: FAIL - TIMEOUT (valid never asserted)" severity error;
            fail_count := fail_count + 2;
        else

            actual_freq := to_integer(unsigned(taylor_frequency));
            check_freq("T6-freq", FREQ_50HZ_Q16, TOL_0P05HZ, actual_freq);
            check_trans("T6-transient", '0', transient_detected);
        end if;
        wait for CLK_PERIOD * 10;

        rst <= '1';
        taylor_start <= '0';
        wait for CLK_PERIOD * 10;
        rst <= '0';
        wait for CLK_PERIOD * 5;
        std_freq_valid <= '1';
        wait for CLK_PERIOD;
        std_freq_valid <= '0';
        wait for CLK_PERIOD * 2;

        test_num <= 7;
        report "======= TEST 7: ROCOF - frequency rising =======" severity note;

        fill_buffer(50.0);
        wait for CLK_PERIOD * 2;
        taylor_start <= '1';
        wait for CLK_PERIOD;
        taylor_start <= '0';
        wait until taylor_freq_valid = '1' for 50 us;
        wait for CLK_PERIOD * 10;

        fill_buffer(50.5);
        wait for CLK_PERIOD * 2;
        taylor_start <= '1';
        wait for CLK_PERIOD;
        taylor_start <= '0';

        wait until taylor_freq_valid = '1' for 50 us;
        timed_out := taylor_freq_valid /= '1';
        if timed_out then
            report "T7: FAIL - TIMEOUT" severity error;
            fail_count := fail_count + 1;
        else
            actual_rocof := to_integer(signed(taylor_rocof));
            check_rocof_sign("T7-rocof-positive", 1, actual_rocof);
        end if;
        wait for CLK_PERIOD * 10;

        test_num <= 8;
        report "======= TEST 8: ROCOF - frequency falling =======" severity note;

        fill_buffer(50.0);
        wait for CLK_PERIOD * 2;
        taylor_start <= '1';
        wait for CLK_PERIOD;
        taylor_start <= '0';
        wait until taylor_freq_valid = '1' for 50 us;
        wait for CLK_PERIOD * 10;

        fill_buffer(49.5);
        wait for CLK_PERIOD * 2;
        taylor_start <= '1';
        wait for CLK_PERIOD;
        taylor_start <= '0';

        wait until taylor_freq_valid = '1' for 50 us;
        timed_out := taylor_freq_valid /= '1';
        if timed_out then
            report "T8: FAIL - TIMEOUT" severity error;
            fail_count := fail_count + 1;
        else
            actual_rocof := to_integer(signed(taylor_rocof));
            check_rocof_sign("T8-rocof-negative", -1, actual_rocof);
        end if;
        wait for CLK_PERIOD * 10;

        rst <= '1';
        taylor_start <= '0';
        wait for CLK_PERIOD * 10;
        rst <= '0';
        wait for CLK_PERIOD * 5;
        std_freq_valid <= '1';
        wait for CLK_PERIOD;
        std_freq_valid <= '0';
        wait for CLK_PERIOD * 2;

        test_num <= 9;
        report "======= TEST 9: Transient hysteresis enter/exit =======" severity note;

        fill_buffer(50.0);
        wait for CLK_PERIOD * 2;
        taylor_start <= '1';
        wait for CLK_PERIOD;
        taylor_start <= '0';

        wait until taylor_freq_valid = '1' for 50 us;
        timed_out := taylor_freq_valid /= '1';
        if timed_out then
            report "T9-step1: FAIL - TIMEOUT" severity error;
            fail_count := fail_count + 1;
        else
            check_trans("T9-step1-no-transient", '0', transient_detected);
        end if;
        wait for CLK_PERIOD * 10;

        fill_buffer(48.0);
        wait for CLK_PERIOD * 2;
        taylor_start <= '1';
        wait for CLK_PERIOD;
        taylor_start <= '0';

        wait until taylor_freq_valid = '1' for 50 us;
        timed_out := taylor_freq_valid /= '1';
        if timed_out then
            report "T9-step2: FAIL - TIMEOUT" severity error;
            fail_count := fail_count + 1;
        else
            check_trans("T9-step2-enter-transient", '1', transient_detected);
        end if;
        wait for CLK_PERIOD * 10;

        fill_buffer_ext(50.0, 3.0*MATH_PI/4.0, 16384.0);
        wait for CLK_PERIOD * 2;
        taylor_start <= '1';
        wait for CLK_PERIOD;
        taylor_start <= '0';

        wait until taylor_freq_valid = '1' for 50 us;
        timed_out := taylor_freq_valid /= '1';
        if timed_out then
            report "T9-step3: FAIL - TIMEOUT" severity error;
            fail_count := fail_count + 1;
        else
            check_trans("T9-step3-exit-transient", '0', transient_detected);
        end if;
        wait for CLK_PERIOD * 10;

        rst <= '1';
        taylor_start <= '0';
        wait for CLK_PERIOD * 10;
        rst <= '0';
        wait for CLK_PERIOD * 5;
        std_freq_valid <= '1';
        wait for CLK_PERIOD;
        std_freq_valid <= '0';
        wait for CLK_PERIOD * 2;

        test_num <= 10;
        report "======= TEST 10: Multi-cycle steady state =======" severity note;

        for i in 0 to 4 loop
            fill_buffer(50.0);
            wait for CLK_PERIOD * 2;

            taylor_start <= '1';
            wait for CLK_PERIOD;
            taylor_start <= '0';

            wait until taylor_freq_valid = '1' for 50 us;
            timed_out := taylor_freq_valid /= '1';
            if timed_out then
                report "T10-cycle" & integer'image(i) & ": FAIL - TIMEOUT" severity error;
                fail_count := fail_count + 1;
            else
                actual_freq := to_integer(unsigned(taylor_frequency));
                check_freq("T10-cycle" & integer'image(i),
                           FREQ_50HZ_Q16, TOL_0P2HZ, actual_freq);
            end if;
            wait for CLK_PERIOD * 10;
        end loop;

        rst <= '1';
        taylor_start <= '0';
        wait for CLK_PERIOD * 10;
        rst <= '0';
        wait for CLK_PERIOD * 5;
        std_freq_valid <= '1';
        wait for CLK_PERIOD;
        std_freq_valid <= '0';
        wait for CLK_PERIOD * 2;

        test_num <= 11;
        report "======= TEST 11: Chirp 49.5->50.5 Hz =======" severity note;
        fill_buffer_chirp(49.5, 50.5);
        wait for CLK_PERIOD * 2;

        taylor_start <= '1';
        wait for CLK_PERIOD;
        taylor_start <= '0';

        wait until taylor_freq_valid = '1' for 50 us;
        timed_out := taylor_freq_valid /= '1';
        if timed_out then
            report "T11: FAIL - TIMEOUT" severity error;
            fail_count := fail_count + 1;
        else
            actual_freq := to_integer(unsigned(taylor_frequency));
            check_freq("T11-chirp", FREQ_50HZ_Q16, TOL_1P0HZ, actual_freq);
        end if;
        wait for CLK_PERIOD * 10;

        test_num <= 12;
        report "======= TEST 12: 50 Hz + 5% 3rd harmonic =======" severity note;
        fill_buffer_harmonic;
        wait for CLK_PERIOD * 2;

        taylor_start <= '1';
        wait for CLK_PERIOD;
        taylor_start <= '0';

        wait until taylor_freq_valid = '1' for 50 us;
        timed_out := taylor_freq_valid /= '1';
        if timed_out then
            report "T12: FAIL - TIMEOUT" severity error;
            fail_count := fail_count + 1;
        else
            actual_freq := to_integer(unsigned(taylor_frequency));
            check_freq("T12-harmonic", FREQ_50HZ_Q16, TOL_0P5HZ, actual_freq);
        end if;
        wait for CLK_PERIOD * 10;

        report "============================================" severity note;
        report "RESULTS: PASSED " & integer'image(pass_count) &
               " / " & integer'image(pass_count + fail_count) &
               " tests, " & integer'image(fail_count) & " failures" severity note;
        report "============================================" severity note;

        assert fail_count = 0
            report "TEST SUITE FAILED with " & integer'image(fail_count) & " failures"
            severity failure;

        report "ALL TESTS PASSED" severity note;

        wait for CLK_PERIOD * 20;
        assert false report "Simulation complete" severity failure;
        wait;
    end process;

end behavioral;
