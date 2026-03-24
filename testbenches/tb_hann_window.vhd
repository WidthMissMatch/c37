library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.MATH_REAL.ALL;

library STD;
use STD.TEXTIO.ALL;

entity tb_hann_window is
end tb_hann_window;

architecture testbench of tb_hann_window is

    constant CLK_PERIOD   : time := 10 ns;
    constant N_SAMPLES    : integer := 256;
    constant AMPLITUDE    : real := 16000.0;

    signal clk             : std_logic := '0';
    signal rst             : std_logic := '1';
    signal sample_in       : std_logic_vector(15 downto 0) := (others => '0');
    signal sample_index    : std_logic_vector(7 downto 0)  := (others => '0');
    signal sample_valid    : std_logic := '0';
    signal sample_out      : std_logic_vector(15 downto 0);
    signal sample_out_valid: std_logic;
    signal index_out       : std_logic_vector(7 downto 0);
    signal coeff_out       : std_logic_vector(15 downto 0);

    signal test_done : boolean := false;

begin

    clk <= not clk after CLK_PERIOD/2 when not test_done else '0';

    uut: entity work.hann_window
        generic map (
            WINDOW_SIZE  => 256,
            SAMPLE_WIDTH => 16,
            COEFF_WIDTH  => 16
        )
        port map (
            clk              => clk,
            rst              => rst,
            sample_in        => sample_in,
            sample_index     => sample_index,
            sample_valid     => sample_valid,
            sample_out       => sample_out,
            sample_out_valid => sample_out_valid,
            index_out        => index_out,
            coeff_out        => coeff_out
        );

    stim_proc: process

        file f_rect   : text;
        file f_hann   : text;
        file f_coeff  : text;
        variable L    : line;

        variable angle     : real;
        variable sample_r  : real;
        variable sample_i  : integer;

        type sample_array is array (0 to N_SAMPLES-1) of integer;
        variable rect_samples : sample_array;
        variable hann_samples : sample_array;
        variable capture_idx  : integer;

        procedure run_test(
            freq1     : real;
            freq2     : real;
            amp2_frac : real;
            fname_rect: string;
            fname_hann: string;
            test_name : string
        ) is
        begin
            report "=== " & test_name & " ===" severity note;
            report "  freq1=" & real'image(freq1) & " Hz, freq2=" & real'image(freq2) & " Hz" severity note;

            capture_idx := 0;
            for n in 0 to N_SAMPLES-1 loop

                angle := 2.0 * MATH_PI * (freq1/50.0) * real(n) / real(N_SAMPLES);
                sample_r := AMPLITUDE * sin(angle);

                if freq2 > 0.0 then
                    angle := 2.0 * MATH_PI * (freq2/50.0) * real(n) / real(N_SAMPLES);
                    sample_r := sample_r + (AMPLITUDE * amp2_frac) * sin(angle);
                end if;

                if sample_r > 32767.0 then
                    sample_i := 32767;
                elsif sample_r < -32768.0 then
                    sample_i := -32768;
                else
                    sample_i := integer(sample_r);
                end if;

                rect_samples(n) := sample_i;

                sample_in    <= std_logic_vector(to_signed(sample_i, 16));
                sample_index <= std_logic_vector(to_unsigned(n, 8));
                sample_valid <= '1';
                wait until rising_edge(clk);
                sample_valid <= '0';

                wait until rising_edge(clk);
                wait until rising_edge(clk);

                if sample_out_valid = '1' then
                    hann_samples(capture_idx) := to_integer(signed(sample_out));
                    capture_idx := capture_idx + 1;
                end if;

                wait until rising_edge(clk);
            end loop;

            for i in 0 to 3 loop
                sample_in    <= (others => '0');
                sample_index <= (others => '0');
                sample_valid <= '1';
                wait until rising_edge(clk);
                sample_valid <= '0';
                wait until rising_edge(clk);
                wait until rising_edge(clk);
                if sample_out_valid = '1' and capture_idx < N_SAMPLES then
                    hann_samples(capture_idx) := to_integer(signed(sample_out));
                    capture_idx := capture_idx + 1;
                end if;
                wait until rising_edge(clk);
            end loop;

            report "  Captured " & integer'image(capture_idx) & " windowed samples" severity note;

            file_open(f_rect, fname_rect, write_mode);
            for n in 0 to N_SAMPLES-1 loop
                write(L, rect_samples(n));
                writeline(f_rect, L);
            end loop;
            file_close(f_rect);

            file_open(f_hann, fname_hann, write_mode);
            for n in 0 to capture_idx-1 loop
                write(L, hann_samples(n));
                writeline(f_hann, L);
            end loop;
            file_close(f_hann);

            report "  Files written: " & fname_rect & ", " & fname_hann severity note;

            for i in 0 to 4 loop
                wait until rising_edge(clk);
            end loop;
        end procedure;

    begin

        rst <= '1';
        wait for 5 * CLK_PERIOD;
        rst <= '0';
        wait for 2 * CLK_PERIOD;

        report "======================================" severity note;
        report " Hann Window Standalone Concept Test  " severity note;
        report "======================================" severity note;

        file_open(f_coeff, "hann_coefficients.txt", write_mode);
        for n in 0 to N_SAMPLES-1 loop

            sample_in    <= std_logic_vector(to_signed(32767, 16));
            sample_index <= std_logic_vector(to_unsigned(n, 8));
            sample_valid <= '1';
            wait until rising_edge(clk);
            sample_valid <= '0';
            wait until rising_edge(clk);

            write(L, to_integer(signed(coeff_out)));
            writeline(f_coeff, L);
            wait until rising_edge(clk);
        end loop;
        file_close(f_coeff);
        report "Hann coefficients dumped to hann_coefficients.txt" severity note;

        for i in 0 to 4 loop
            wait until rising_edge(clk);
        end loop;

        run_test(
            freq1      => 50.0,
            freq2      => 0.0,
            amp2_frac  => 0.0,
            fname_rect => "hann_test1_rect.txt",
            fname_hann => "hann_test1_hann.txt",
            test_name  => "TEST 1: On-bin (50.0 Hz)"
        );

        run_test(
            freq1      => 50.5,
            freq2      => 0.0,
            amp2_frac  => 0.0,
            fname_rect => "hann_test2_rect.txt",
            fname_hann => "hann_test2_hann.txt",
            test_name  => "TEST 2: Off-bin (50.5 Hz)"
        );

        run_test(
            freq1      => 50.0,
            freq2      => 150.0,
            amp2_frac  => 0.1,
            fname_rect => "hann_test3_rect.txt",
            fname_hann => "hann_test3_hann.txt",
            test_name  => "TEST 3: Harmonic (50 Hz + 10% 150 Hz)"
        );

        run_test(
            freq1      => 52.0,
            freq2      => 0.0,
            amp2_frac  => 0.0,
            fname_rect => "hann_test4_rect.txt",
            fname_hann => "hann_test4_hann.txt",
            test_name  => "TEST 4: Far off-bin (52.0 Hz)"
        );

        report "======================================" severity note;
        report " ALL TESTS COMPLETE                   " severity note;
        report "======================================" severity note;
        report "Output files:" severity note;
        report "  hann_coefficients.txt      - ROM coefficients" severity note;
        report "  hann_test1_*.txt           - On-bin (50 Hz)" severity note;
        report "  hann_test2_*.txt           - Off-bin (50.5 Hz)" severity note;
        report "  hann_test3_*.txt           - Harmonic (50+150 Hz)" severity note;
        report "  hann_test4_*.txt           - Far off-bin (52 Hz)" severity note;
        report "Run: python3 verify_hann_window.py" severity note;

        test_done <= true;
        wait;
    end process;

end testbench;
