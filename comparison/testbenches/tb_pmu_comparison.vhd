library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use STD.TEXTIO.ALL;
use IEEE.STD_LOGIC_TEXTIO.ALL;

library old_lib;
library new_lib;

entity tb_pmu_comparison is
    generic (
        INPUT_FILE  : string := "input_samples.txt";
        OUTPUT_FILE : string := "comparison_output.csv"
    );
end entity tb_pmu_comparison;

architecture sim of tb_pmu_comparison is

    constant CLK_PERIOD   : time    := 10 ns;
    constant ADC_INTERVAL : integer := 6666;
    constant DRAIN_CLOCKS : integer := 1000000;

    signal clk        : std_logic := '0';
    signal rst        : std_logic := '1';
    signal enable     : std_logic := '1';
    signal adc_sample : std_logic_vector(15 downto 0) := (others => '0');
    signal adc_valid  : std_logic := '0';

    signal old_phasor_magnitude : std_logic_vector(31 downto 0);
    signal old_phasor_phase     : std_logic_vector(15 downto 0);
    signal old_phasor_valid     : std_logic;
    signal old_dft_real_out     : std_logic_vector(31 downto 0);
    signal old_dft_imag_out     : std_logic_vector(31 downto 0);
    signal old_dft_valid_out    : std_logic;
    signal old_frequency_out    : std_logic_vector(31 downto 0);
    signal old_freq_valid       : std_logic;
    signal old_rocof_out        : std_logic_vector(31 downto 0);
    signal old_rocof_valid      : std_logic;
    signal old_cycle_complete   : std_logic;
    signal old_dft_busy         : std_logic;
    signal old_cordic_busy      : std_logic;
    signal old_system_ready     : std_logic;
    signal old_samples_per_cycle: std_logic_vector(31 downto 0);
    signal old_cycle_count      : std_logic_vector(15 downto 0);

    signal new_phasor_magnitude : std_logic_vector(31 downto 0);
    signal new_phasor_phase     : std_logic_vector(15 downto 0);
    signal new_phasor_valid     : std_logic;
    signal new_dft_real_out     : std_logic_vector(31 downto 0);
    signal new_dft_imag_out     : std_logic_vector(31 downto 0);
    signal new_dft_valid_out    : std_logic;
    signal new_frequency_out    : std_logic_vector(31 downto 0);
    signal new_freq_valid       : std_logic;
    signal new_rocof_out        : std_logic_vector(31 downto 0);
    signal new_rocof_valid      : std_logic;
    signal new_cycle_complete   : std_logic;
    signal new_dft_busy         : std_logic;
    signal new_cordic_busy      : std_logic;
    signal new_system_ready     : std_logic;
    signal new_samples_per_cycle: std_logic_vector(31 downto 0);
    signal new_cycle_count      : std_logic_vector(15 downto 0);

    signal old_mag_reg    : signed(31 downto 0) := (others => '0');
    signal old_phase_reg  : signed(15 downto 0) := (others => '0');
    signal old_freq_reg   : signed(31 downto 0) := (others => '0');
    signal old_rocof_reg  : signed(31 downto 0) := (others => '0');
    signal old_dft_r_reg  : signed(31 downto 0) := (others => '0');
    signal old_dft_i_reg  : signed(31 downto 0) := (others => '0');

    signal new_mag_reg    : signed(31 downto 0) := (others => '0');
    signal new_phase_reg  : signed(15 downto 0) := (others => '0');
    signal new_freq_reg   : signed(31 downto 0) := (others => '0');
    signal new_rocof_reg  : signed(31 downto 0) := (others => '0');
    signal new_dft_r_reg  : signed(31 downto 0) := (others => '0');
    signal new_dft_i_reg  : signed(31 downto 0) := (others => '0');

    signal csv_row_count : integer := 0;
    signal sim_done      : boolean := false;

begin

    clk_proc : process
    begin
        if sim_done then
            wait;
        end if;
        clk <= '0';
        wait for CLK_PERIOD / 2;
        clk <= '1';
        wait for CLK_PERIOD / 2;
    end process;

    old_dut : entity old_lib.pmu_processing_top
        port map (
            clk                 => clk,
            rst                 => rst,
            adc_sample          => adc_sample,
            adc_valid           => adc_valid,
            phasor_magnitude    => old_phasor_magnitude,
            phasor_phase        => old_phasor_phase,
            phasor_valid        => old_phasor_valid,
            dft_real_out        => old_dft_real_out,
            dft_imag_out        => old_dft_imag_out,
            dft_valid_out       => old_dft_valid_out,
            frequency_out       => old_frequency_out,
            freq_valid          => old_freq_valid,
            rocof_out           => old_rocof_out,
            rocof_valid         => old_rocof_valid,
            cycle_complete      => old_cycle_complete,
            dft_busy            => old_dft_busy,
            cordic_busy         => old_cordic_busy,
            system_ready        => old_system_ready,
            samples_per_cycle   => old_samples_per_cycle,
            cycle_count         => old_cycle_count,
            enable              => enable
        );

    new_dut : entity new_lib.pmu_processing_top
        port map (
            clk                 => clk,
            rst                 => rst,
            adc_sample          => adc_sample,
            adc_valid           => adc_valid,
            phasor_magnitude    => new_phasor_magnitude,
            phasor_phase        => new_phasor_phase,
            phasor_valid        => new_phasor_valid,
            dft_real_out        => new_dft_real_out,
            dft_imag_out        => new_dft_imag_out,
            dft_valid_out       => new_dft_valid_out,
            frequency_out       => new_frequency_out,
            freq_valid          => new_freq_valid,
            rocof_out           => new_rocof_out,
            rocof_valid         => new_rocof_valid,
            cycle_complete      => new_cycle_complete,
            dft_busy            => new_dft_busy,
            cordic_busy         => new_cordic_busy,
            system_ready        => new_system_ready,
            samples_per_cycle   => new_samples_per_cycle,
            cycle_count         => new_cycle_count,
            enable              => enable
        );

    stim_proc : process
        file     stim_file : text;
        variable line_buf   : line;
        variable sample_val : integer;
        variable sample_cnt : integer := 0;
        variable file_ok    : boolean;
    begin

        rst <= '1';
        adc_valid <= '0';
        wait for 200 ns;
        wait until rising_edge(clk);
        rst <= '0';
        wait for 100 ns;
        wait until rising_edge(clk);

        file_open(stim_file, INPUT_FILE, read_mode);

        while not endfile(stim_file) loop
            readline(stim_file, line_buf);

            if line_buf'length = 0 then
                next;
            end if;

            read(line_buf, sample_val, file_ok);
            if not file_ok then
                next;
            end if;

            if sample_val > 32767 then
                sample_val := 32767;
            elsif sample_val < -32768 then
                sample_val := -32768;
            end if;

            wait until rising_edge(clk);
            adc_sample <= std_logic_vector(to_signed(sample_val, 16));
            adc_valid  <= '1';
            wait until rising_edge(clk);
            adc_valid  <= '0';

            for j in 0 to ADC_INTERVAL - 3 loop
                wait until rising_edge(clk);
            end loop;

            sample_cnt := sample_cnt + 1;
        end loop;

        file_close(stim_file);

        report "Stimulus complete: " & integer'image(sample_cnt) &
               " samples injected. Draining pipeline..."
            severity note;

        for j in 0 to DRAIN_CLOCKS - 1 loop
            wait until rising_edge(clk);
        end loop;

        sim_done <= true;
        report "Simulation finished." severity note;
        wait;
    end process;

    old_latch_proc : process(clk)
    begin
        if rising_edge(clk) then
            if old_phasor_valid = '1' then
                old_mag_reg   <= signed(old_phasor_magnitude);
                old_phase_reg <= signed(old_phasor_phase);
            end if;
            if old_freq_valid = '1' then
                old_freq_reg  <= signed(old_frequency_out);
            end if;
            if old_rocof_valid = '1' then
                old_rocof_reg <= signed(old_rocof_out);
            end if;
            if old_dft_valid_out = '1' then
                old_dft_r_reg <= signed(old_dft_real_out);
                old_dft_i_reg <= signed(old_dft_imag_out);
            end if;
        end if;
    end process;

    new_latch_proc : process(clk)
    begin
        if rising_edge(clk) then
            if new_phasor_valid = '1' then
                new_mag_reg   <= signed(new_phasor_magnitude);
                new_phase_reg <= signed(new_phasor_phase);
            end if;
            if new_freq_valid = '1' then
                new_freq_reg  <= signed(new_frequency_out);
            end if;
            if new_rocof_valid = '1' then
                new_rocof_reg <= signed(new_rocof_out);
            end if;
            if new_dft_valid_out = '1' then
                new_dft_r_reg <= signed(new_dft_real_out);
                new_dft_i_reg <= signed(new_dft_imag_out);
            end if;
        end if;
    end process;

    csv_writer_proc : process
        file     outfile  : text;
        variable oline    : line;
        variable row_num  : integer := 0;
    begin

        file_open(outfile, OUTPUT_FILE, write_mode);
        write(oline, string'("cycle,old_mag,new_mag,old_phase,new_phase,old_freq,new_freq,old_rocof,new_rocof,old_dft_real,new_dft_real,old_dft_imag,new_dft_imag"));
        writeline(outfile, oline);

        wait until rst = '0';

        while not sim_done loop
            wait until rising_edge(clk) or sim_done;
            if sim_done then
                exit;
            end if;

            if old_phasor_valid = '1' then
                row_num := row_num + 1;

                wait until rising_edge(clk);
                wait until rising_edge(clk);
                wait until rising_edge(clk);
                wait until rising_edge(clk);
                wait until rising_edge(clk);

                write(oline, row_num);
                write(oline, string'(","));
                write(oline, to_integer(old_mag_reg));
                write(oline, string'(","));
                write(oline, to_integer(new_mag_reg));
                write(oline, string'(","));
                write(oline, to_integer(old_phase_reg));
                write(oline, string'(","));
                write(oline, to_integer(new_phase_reg));
                write(oline, string'(","));
                write(oline, to_integer(old_freq_reg));
                write(oline, string'(","));
                write(oline, to_integer(new_freq_reg));
                write(oline, string'(","));
                write(oline, to_integer(old_rocof_reg));
                write(oline, string'(","));
                write(oline, to_integer(new_rocof_reg));
                write(oline, string'(","));
                write(oline, to_integer(old_dft_r_reg));
                write(oline, string'(","));
                write(oline, to_integer(new_dft_r_reg));
                write(oline, string'(","));
                write(oline, to_integer(old_dft_i_reg));
                write(oline, string'(","));
                write(oline, to_integer(new_dft_i_reg));
                writeline(outfile, oline);

                report "Cycle " & integer'image(row_num) &
                       ": OLD mag=" & integer'image(to_integer(old_mag_reg)) &
                       "  NEW mag=" & integer'image(to_integer(new_mag_reg)) &
                       "  OLD freq=" & integer'image(to_integer(old_freq_reg)) &
                       "  NEW freq=" & integer'image(to_integer(new_freq_reg))
                    severity note;
            end if;
        end loop;

        file_close(outfile);
        report "CSV written: " & integer'image(row_num) & " rows to " & OUTPUT_FILE
            severity note;
        wait;
    end process;

end architecture sim;
