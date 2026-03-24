library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.MATH_REAL.ALL;

library STD;
use STD.TEXTIO.ALL;

entity tb_freq_damping is
end tb_freq_damping;

architecture testbench of tb_freq_damping is

    constant CLK_PERIOD : time := 10 ns;
    constant FREQ_WIDTH : integer := 32;

    constant HZ_SCALE : real := 65536.0;

    constant ALPHA_01 : integer := 6554;
    constant ALPHA_03 : integer := 19661;
    constant ALPHA_05 : integer := 32768;

    constant N_SAMPLES : integer := 30;

    signal clk : std_logic := '0';
    signal rst : std_logic := '1';

    signal freq_in       : std_logic_vector(FREQ_WIDTH-1 downto 0) := (others => '0');
    signal freq_valid    : std_logic := '0';
    signal freq_init     : std_logic_vector(FREQ_WIDTH-1 downto 0);

    signal freq_out_01      : std_logic_vector(FREQ_WIDTH-1 downto 0);
    signal freq_out_valid_01: std_logic;
    signal diff_out_01      : std_logic_vector(FREQ_WIDTH-1 downto 0);
    signal init_01          : std_logic;

    signal freq_out_03      : std_logic_vector(FREQ_WIDTH-1 downto 0);
    signal freq_out_valid_03: std_logic;
    signal diff_out_03      : std_logic_vector(FREQ_WIDTH-1 downto 0);
    signal init_03          : std_logic;

    signal freq_out_05      : std_logic_vector(FREQ_WIDTH-1 downto 0);
    signal freq_out_valid_05: std_logic;
    signal diff_out_05      : std_logic_vector(FREQ_WIDTH-1 downto 0);
    signal init_05          : std_logic;

    signal test_done : boolean := false;

begin

    clk <= not clk after CLK_PERIOD/2 when not test_done else '0';

    freq_init <= std_logic_vector(to_signed(integer(50.0 * HZ_SCALE), FREQ_WIDTH));

    uut_01: entity work.freq_damping_filter
        generic map (FREQ_WIDTH => FREQ_WIDTH, ALPHA => ALPHA_01)
        port map (
            clk => clk, rst => rst,
            freq_in => freq_in, freq_valid => freq_valid,
            freq_out => freq_out_01, freq_out_valid => freq_out_valid_01,
            freq_init => freq_init,
            diff_out => diff_out_01, initialized => init_01
        );

    uut_03: entity work.freq_damping_filter
        generic map (FREQ_WIDTH => FREQ_WIDTH, ALPHA => ALPHA_03)
        port map (
            clk => clk, rst => rst,
            freq_in => freq_in, freq_valid => freq_valid,
            freq_out => freq_out_03, freq_out_valid => freq_out_valid_03,
            freq_init => freq_init,
            diff_out => diff_out_03, initialized => init_03
        );

    uut_05: entity work.freq_damping_filter
        generic map (FREQ_WIDTH => FREQ_WIDTH, ALPHA => ALPHA_05)
        port map (
            clk => clk, rst => rst,
            freq_in => freq_in, freq_valid => freq_valid,
            freq_out => freq_out_05, freq_out_valid => freq_out_valid_05,
            freq_init => freq_init,
            diff_out => diff_out_05, initialized => init_05
        );

    stim_proc: process
        file f_01 : text;
        file f_03 : text;
        file f_05 : text;
        variable L : line;

        type freq_array is array (0 to N_SAMPLES-1) of real;
        variable input_freqs : freq_array;
        variable freq_hz     : real;
        variable freq_q16    : integer;

        type int_array is array (0 to N_SAMPLES-1) of integer;
        variable in_captured  : int_array;
        variable out_01_cap   : int_array;
        variable out_03_cap   : int_array;
        variable out_05_cap   : int_array;
        variable cap_idx      : integer;

        procedure reset_filters is
        begin
            rst <= '1';
            wait for 5 * CLK_PERIOD;
            rst <= '0';
            wait for 2 * CLK_PERIOD;
        end procedure;

        procedure run_scenario(
            scenario_id : integer;
            scenario_name : string
        ) is
        begin
            report "=== Scenario " & integer'image(scenario_id) & ": " & scenario_name & " ===" severity note;

            reset_filters;
            cap_idx := 0;

            for i in 0 to N_SAMPLES-1 loop
                freq_hz := input_freqs(i);
                freq_q16 := integer(freq_hz * HZ_SCALE);
                in_captured(i) := freq_q16;

                freq_in    <= std_logic_vector(to_signed(freq_q16, FREQ_WIDTH));
                freq_valid <= '1';
                wait until rising_edge(clk);
                freq_valid <= '0';

                wait until rising_edge(clk);
                wait until rising_edge(clk);
                wait until rising_edge(clk);

                if i > 0 then
                    out_01_cap(cap_idx) := to_integer(signed(freq_out_01));
                    out_03_cap(cap_idx) := to_integer(signed(freq_out_03));
                    out_05_cap(cap_idx) := to_integer(signed(freq_out_05));
                    cap_idx := cap_idx + 1;
                end if;

                wait for 2 * CLK_PERIOD;
            end loop;

            for i in 0 to 4 loop
                wait until rising_edge(clk);
                if freq_out_valid_01 = '1' and cap_idx < N_SAMPLES then
                    out_01_cap(cap_idx) := to_integer(signed(freq_out_01));
                    out_03_cap(cap_idx) := to_integer(signed(freq_out_03));
                    out_05_cap(cap_idx) := to_integer(signed(freq_out_05));
                    cap_idx := cap_idx + 1;
                end if;
            end loop;

            report "  Captured " & integer'image(cap_idx) & " output samples" severity note;

            for i in 0 to cap_idx-1 loop

                write(L, scenario_id);
                write(L, string'(" "));
                write(L, in_captured(i+1));
                write(L, string'(" "));
                write(L, out_01_cap(i));
                writeline(f_01, L);

                write(L, scenario_id);
                write(L, string'(" "));
                write(L, in_captured(i+1));
                write(L, string'(" "));
                write(L, out_03_cap(i));
                writeline(f_03, L);

                write(L, scenario_id);
                write(L, string'(" "));
                write(L, in_captured(i+1));
                write(L, string'(" "));
                write(L, out_05_cap(i));
                writeline(f_05, L);
            end loop;
        end procedure;

        variable angle : real;

    begin

        file_open(f_01, "freq_damp_alpha01.txt", write_mode);
        file_open(f_03, "freq_damp_alpha03.txt", write_mode);
        file_open(f_05, "freq_damp_alpha05.txt", write_mode);

        rst <= '1';
        wait for 5 * CLK_PERIOD;
        rst <= '0';
        wait for 2 * CLK_PERIOD;

        report "==========================================" severity note;
        report " Frequency Damping Filter Standalone Test " severity note;
        report "==========================================" severity note;

        for i in 0 to N_SAMPLES-1 loop
            input_freqs(i) := 50.0;
        end loop;
        run_scenario(1, "Steady state 50 Hz");

        for i in 0 to N_SAMPLES-1 loop
            input_freqs(i) := 50.0;
        end loop;
        input_freqs(2) := 56.33;
        run_scenario(2, "Single spike 56.33 Hz at sample 2");

        for i in 0 to N_SAMPLES-1 loop
            if i < 20 then
                input_freqs(i) := 50.0 + (real(i) / 20.0) * 1.0;
            else
                input_freqs(i) := 51.0;
            end if;
        end loop;
        run_scenario(3, "Ramp 50->51 Hz over 20 samples");

        for i in 0 to N_SAMPLES-1 loop
            if i < 5 then
                input_freqs(i) := 50.0;
            else
                input_freqs(i) := 51.0;
            end if;
        end loop;
        run_scenario(4, "Step 50->51 Hz at sample 5");

        input_freqs(0)  := 50.0;
        input_freqs(1)  := 50.0;
        input_freqs(2)  := 56.33;
        input_freqs(3)  := 50.02;
        input_freqs(4)  := 50.01;
        input_freqs(5)  := 50.005;
        input_freqs(6)  := 50.003;
        input_freqs(7)  := 50.001;
        for i in 8 to N_SAMPLES-1 loop
            input_freqs(i) := 50.0 + 0.001 * sin(MATH_PI * real(i) / 10.0);
        end loop;
        run_scenario(5, "Real PMU startup pattern");

        for i in 0 to N_SAMPLES-1 loop
            input_freqs(i) := 50.0 + 0.5 * sin(MATH_PI * real(i) / 5.0);
        end loop;
        run_scenario(6, "Oscillating 50 +/- 0.5 Hz");

        file_close(f_01);
        file_close(f_03);
        file_close(f_05);

        report "==========================================" severity note;
        report " ALL SCENARIOS COMPLETE                   " severity note;
        report "==========================================" severity note;
        report "Output files:" severity note;
        report "  freq_damp_alpha01.txt (alpha=0.1)" severity note;
        report "  freq_damp_alpha03.txt (alpha=0.3)" severity note;
        report "  freq_damp_alpha05.txt (alpha=0.5)" severity note;
        report "Format: scenario_id input_q16_16 output_q16_16" severity note;
        report "Run: python3 verify_freq_damping.py" severity note;

        test_done <= true;
        wait;
    end process;

end testbench;
