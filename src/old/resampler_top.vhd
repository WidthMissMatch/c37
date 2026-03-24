library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity resampler_top is
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
end resampler_top;

architecture structural of resampler_top is

    component circular_buffer_controller
        generic (
            BUFFER_DEPTH      : integer := 512;
            BUFFER_ADDR_WIDTH : integer := 9;
            SAMPLE_WIDTH      : integer := 16
        );
        port (
            clk             : in  std_logic;
            rst             : in  std_logic;
            sample_in       : in  std_logic_vector(SAMPLE_WIDTH-1 downto 0);
            sample_valid    : in  std_logic;
            read_addr       : in  std_logic_vector(BUFFER_ADDR_WIDTH-1 downto 0);
            read_enable     : in  std_logic;
            read_data       : out std_logic_vector(SAMPLE_WIDTH-1 downto 0);
            read_valid      : out std_logic;
            write_addr_out  : out std_logic_vector(BUFFER_ADDR_WIDTH-1 downto 0);
            sample_count    : out std_logic_vector(31 downto 0);
            buffer_oldest   : out std_logic_vector(31 downto 0)
        );
    end component;

    component samples_per_cycle_calc
        generic (
            SAMPLE_RATE       : integer := 15000;
            INPUT_WIDTH       : integer := 32;
            OUTPUT_WIDTH      : integer := 32;
            FRAC_BITS         : integer := 16
        );
        port (
            clk                   : in  std_logic;
            rst                   : in  std_logic;
            frequency_in          : in  std_logic_vector(INPUT_WIDTH-1 downto 0);
            freq_valid            : in  std_logic;
            samples_per_cycle     : out std_logic_vector(OUTPUT_WIDTH-1 downto 0);
            output_valid          : out std_logic;
            frequency_out_of_range: out std_logic;
            busy                  : out std_logic
        );
    end component;

    component cycle_tracker
        generic (
            FRAC_BITS     : integer := 16;
            COUNT_WIDTH   : integer := 32
        );
        port (
            clk                 : in  std_logic;
            rst                 : in  std_logic;
            adc_valid           : in  std_logic;
            samples_per_cycle   : in  std_logic_vector(COUNT_WIDTH-1 downto 0);
            spc_valid           : in  std_logic;
            enable              : in  std_logic;
            cycle_complete      : out std_logic;
            cycle_start_offset  : out std_logic_vector(COUNT_WIDTH-1 downto 0);
            cycle_end_sample    : out std_logic_vector(COUNT_WIDTH-1 downto 0);
            cycle_count         : out std_logic_vector(15 downto 0);
            current_accumulator : out std_logic_vector(COUNT_WIDTH-1 downto 0);
            ready               : out std_logic
        );
    end component;

    component position_calculator
        generic (
            OUTPUT_SAMPLES    : integer := 256;
            BUFFER_ADDR_WIDTH : integer := 9;
            FRAC_BITS         : integer := 16
        );
        port (
            clk                 : in  std_logic;
            rst                 : in  std_logic;
            cycle_complete      : in  std_logic;
            cycle_end_sample    : in  std_logic_vector(31 downto 0);
            samples_per_cycle   : in  std_logic_vector(31 downto 0);
            position_valid      : out std_logic;
            position_index      : out std_logic_vector(7 downto 0);
            position_last       : out std_logic;
            buffer_addr_left    : out std_logic_vector(BUFFER_ADDR_WIDTH-1 downto 0);
            buffer_addr_right   : out std_logic_vector(BUFFER_ADDR_WIDTH-1 downto 0);
            interp_fraction     : out std_logic_vector(FRAC_BITS-1 downto 0);
            busy                : out std_logic;
            ready               : out std_logic;
            downstream_ready    : in  std_logic
        );
    end component;

    component sample_fetcher
        generic (
            SAMPLE_WIDTH      : integer := 16;
            BUFFER_ADDR_WIDTH : integer := 9;
            FRAC_BITS         : integer := 16
        );
        port (
            clk                 : in  std_logic;
            rst                 : in  std_logic;
            position_valid      : in  std_logic;
            position_index      : in  std_logic_vector(7 downto 0);
            position_last       : in  std_logic;
            buffer_addr_left    : in  std_logic_vector(BUFFER_ADDR_WIDTH-1 downto 0);
            buffer_addr_right   : in  std_logic_vector(BUFFER_ADDR_WIDTH-1 downto 0);
            interp_fraction     : in  std_logic_vector(FRAC_BITS-1 downto 0);
            fetcher_ready       : out std_logic;
            buffer_read_addr    : out std_logic_vector(BUFFER_ADDR_WIDTH-1 downto 0);
            buffer_read_enable  : out std_logic;
            buffer_read_data    : in  std_logic_vector(SAMPLE_WIDTH-1 downto 0);
            buffer_read_valid   : in  std_logic;
            sample_left         : out std_logic_vector(SAMPLE_WIDTH-1 downto 0);
            sample_right        : out std_logic_vector(SAMPLE_WIDTH-1 downto 0);
            fraction_out        : out std_logic_vector(FRAC_BITS-1 downto 0);
            index_out           : out std_logic_vector(7 downto 0);
            samples_valid       : out std_logic;
            samples_last        : out std_logic;
            busy                : out std_logic
        );
    end component;

    component interpolation_engine
        generic (
            SAMPLE_WIDTH    : integer := 16;
            FRAC_WIDTH      : integer := 16;
            INDEX_WIDTH     : integer := 8
        );
        port (
            clk             : in  std_logic;
            rst             : in  std_logic;
            sample_left     : in  std_logic_vector(SAMPLE_WIDTH-1 downto 0);
            sample_right    : in  std_logic_vector(SAMPLE_WIDTH-1 downto 0);
            fraction        : in  std_logic_vector(FRAC_WIDTH-1 downto 0);
            index_in        : in  std_logic_vector(INDEX_WIDTH-1 downto 0);
            last_in         : in  std_logic;
            input_valid     : in  std_logic;
            interp_sample   : out std_logic_vector(SAMPLE_WIDTH-1 downto 0);
            index_out       : out std_logic_vector(INDEX_WIDTH-1 downto 0);
            last_out        : out std_logic;
            output_valid    : out std_logic
        );
    end component;

    signal buf_read_addr    : std_logic_vector(BUFFER_ADDR_WIDTH-1 downto 0);
    signal buf_read_enable  : std_logic;
    signal buf_read_data    : std_logic_vector(SAMPLE_WIDTH-1 downto 0);
    signal buf_read_valid   : std_logic;
    signal buf_write_addr   : std_logic_vector(BUFFER_ADDR_WIDTH-1 downto 0);
    signal buf_sample_count : std_logic_vector(31 downto 0);
    signal buf_oldest       : std_logic_vector(31 downto 0);

    signal spc_result       : std_logic_vector(FREQ_WIDTH-1 downto 0);
    signal spc_valid        : std_logic;
    signal spc_out_of_range : std_logic;
    signal spc_busy         : std_logic;

    signal ct_cycle_complete    : std_logic;
    signal ct_start_offset      : std_logic_vector(FREQ_WIDTH-1 downto 0);
    signal ct_end_sample        : std_logic_vector(31 downto 0);
    signal ct_cycle_count       : std_logic_vector(15 downto 0);
    signal ct_accumulator       : std_logic_vector(FREQ_WIDTH-1 downto 0);
    signal ct_ready             : std_logic;

    signal pc_position_valid    : std_logic;
    signal pc_position_index    : std_logic_vector(7 downto 0);
    signal pc_position_last     : std_logic;
    signal pc_addr_left         : std_logic_vector(BUFFER_ADDR_WIDTH-1 downto 0);
    signal pc_addr_right        : std_logic_vector(BUFFER_ADDR_WIDTH-1 downto 0);
    signal pc_interp_fraction   : std_logic_vector(FRAC_BITS-1 downto 0);
    signal pc_busy              : std_logic;
    signal pc_ready             : std_logic;

    signal sf_fetcher_ready     : std_logic;
    signal sf_sample_left       : std_logic_vector(SAMPLE_WIDTH-1 downto 0);
    signal sf_sample_right      : std_logic_vector(SAMPLE_WIDTH-1 downto 0);
    signal sf_fraction_out      : std_logic_vector(FRAC_BITS-1 downto 0);
    signal sf_index_out         : std_logic_vector(7 downto 0);
    signal sf_samples_valid     : std_logic;
    signal sf_samples_last      : std_logic;
    signal sf_busy              : std_logic;

    signal ie_interp_sample     : std_logic_vector(SAMPLE_WIDTH-1 downto 0);
    signal ie_index_out         : std_logic_vector(7 downto 0);
    signal ie_last_out          : std_logic;
    signal ie_output_valid      : std_logic;

    signal system_ready     : std_logic;

begin

    circular_buffer_inst: circular_buffer_controller
        generic map (
            BUFFER_DEPTH      => BUFFER_DEPTH,
            BUFFER_ADDR_WIDTH => BUFFER_ADDR_WIDTH,
            SAMPLE_WIDTH      => SAMPLE_WIDTH
        )
        port map (
            clk             => clk,
            rst             => rst,
            sample_in       => adc_sample,
            sample_valid    => adc_valid,
            read_addr       => buf_read_addr,
            read_enable     => buf_read_enable,
            read_data       => buf_read_data,
            read_valid      => buf_read_valid,
            write_addr_out  => buf_write_addr,
            sample_count    => buf_sample_count,
            buffer_oldest   => buf_oldest
        );

    samples_per_cycle_inst: samples_per_cycle_calc
        generic map (
            SAMPLE_RATE  => SAMPLE_RATE,
            INPUT_WIDTH  => FREQ_WIDTH,
            OUTPUT_WIDTH => FREQ_WIDTH,
            FRAC_BITS    => FRAC_BITS
        )
        port map (
            clk                    => clk,
            rst                    => rst,
            frequency_in           => frequency_estimate,
            freq_valid             => frequency_valid,
            samples_per_cycle      => spc_result,
            output_valid           => spc_valid,
            frequency_out_of_range => spc_out_of_range,
            busy                   => spc_busy
        );

    cycle_tracker_inst: cycle_tracker
        generic map (
            FRAC_BITS   => FRAC_BITS,
            COUNT_WIDTH => FREQ_WIDTH
        )
        port map (
            clk                 => clk,
            rst                 => rst,
            adc_valid           => adc_valid,
            samples_per_cycle   => spc_result,
            spc_valid           => spc_valid,
            enable              => enable,
            cycle_complete      => ct_cycle_complete,
            cycle_start_offset  => ct_start_offset,
            cycle_end_sample    => ct_end_sample,
            cycle_count         => ct_cycle_count,
            current_accumulator => ct_accumulator,
            ready               => ct_ready
        );

    position_calc_inst: position_calculator
        generic map (
            OUTPUT_SAMPLES    => OUTPUT_SAMPLES,
            BUFFER_ADDR_WIDTH => BUFFER_ADDR_WIDTH,
            FRAC_BITS         => FRAC_BITS
        )
        port map (
            clk                 => clk,
            rst                 => rst,
            cycle_complete      => ct_cycle_complete,
            cycle_end_sample    => ct_end_sample,
            samples_per_cycle   => spc_result,
            position_valid      => pc_position_valid,
            position_index      => pc_position_index,
            position_last       => pc_position_last,
            buffer_addr_left    => pc_addr_left,
            buffer_addr_right   => pc_addr_right,
            interp_fraction     => pc_interp_fraction,
            busy                => pc_busy,
            ready               => pc_ready,
            downstream_ready    => sf_fetcher_ready
        );

    sample_fetcher_inst: sample_fetcher
        generic map (
            SAMPLE_WIDTH      => SAMPLE_WIDTH,
            BUFFER_ADDR_WIDTH => BUFFER_ADDR_WIDTH,
            FRAC_BITS         => FRAC_BITS
        )
        port map (
            clk                 => clk,
            rst                 => rst,
            position_valid      => pc_position_valid,
            position_index      => pc_position_index,
            position_last       => pc_position_last,
            buffer_addr_left    => pc_addr_left,
            buffer_addr_right   => pc_addr_right,
            interp_fraction     => pc_interp_fraction,
            fetcher_ready       => sf_fetcher_ready,
            buffer_read_addr    => buf_read_addr,
            buffer_read_enable  => buf_read_enable,
            buffer_read_data    => buf_read_data,
            buffer_read_valid   => buf_read_valid,
            sample_left         => sf_sample_left,
            sample_right        => sf_sample_right,
            fraction_out        => sf_fraction_out,
            index_out           => sf_index_out,
            samples_valid       => sf_samples_valid,
            samples_last        => sf_samples_last,
            busy                => sf_busy
        );

    interpolation_engine_inst: interpolation_engine
        generic map (
            SAMPLE_WIDTH => SAMPLE_WIDTH,
            FRAC_WIDTH   => FRAC_BITS,
            INDEX_WIDTH  => 8
        )
        port map (
            clk           => clk,
            rst           => rst,
            sample_left   => sf_sample_left,
            sample_right  => sf_sample_right,
            fraction      => sf_fraction_out,
            index_in      => sf_index_out,
            last_in       => sf_samples_last,
            input_valid   => sf_samples_valid,
            interp_sample => ie_interp_sample,
            index_out     => ie_index_out,
            last_out      => ie_last_out,
            output_valid  => ie_output_valid
        );

    ready_process: process(clk, rst)
    begin
        if rst = '1' then
            system_ready <= '0';
        elsif rising_edge(clk) then
            if enable = '1' and spc_busy = '0' and ct_ready = '1' and pc_ready = '1' then
                system_ready <= '1';
            else
                system_ready <= '0';
            end if;
        end if;
    end process;

    debug_resamp_output: process(clk)
        variable first_resamp_seen : boolean := false;
        variable resamp_count : integer := 0;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                first_resamp_seen := false;
                resamp_count := 0;
            elsif ie_output_valid = '1' then
                if not first_resamp_seen then
                    report "[RESAMPLER] First resampled sample output!" severity note;
                    first_resamp_seen := true;
                end if;
                resamp_count := resamp_count + 1;
                if resamp_count = 50 or resamp_count = 128 or resamp_count = 256 then
                    report "[RESAMPLER] Resampled count = " & integer'image(resamp_count) severity note;
                end if;
                if ie_last_out = '1' then
                    report "[RESAMPLER] Last sample (256/256) - cycle complete!" severity note;
                    resamp_count := 0;
                end if;
            end if;
        end if;
    end process;

    resampled_sample <= ie_interp_sample;
    resampled_valid  <= ie_output_valid;
    resampled_index  <= ie_index_out;
    resampled_last   <= ie_last_out;

    cycle_complete      <= ct_cycle_complete;
    samples_per_cycle   <= spc_result;
    buffer_sample_count <= buf_sample_count;
    freq_out_of_range   <= spc_out_of_range;

    cycle_count        <= ct_cycle_count;
    cycle_start_offset <= ct_start_offset;
    cycle_end_sample   <= ct_end_sample;

    position_calc_busy <= pc_busy;

    sample_fetcher_busy <= sf_busy;

    ready <= system_ready;

end structural;
