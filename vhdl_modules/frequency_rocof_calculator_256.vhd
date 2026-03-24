library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity frequency_rocof_calculator_256 is
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
end frequency_rocof_calculator_256;

architecture behavioral of frequency_rocof_calculator_256 is

    type state_type is (IDLE, FIRST_SAMPLE, CALCULATING);
    signal current_state, next_state : state_type;

    constant PI_Q2_29       : signed(THETA_WIDTH-1 downto 0) := to_signed(1686629713,  THETA_WIDTH);
    constant NEG_PI_Q2_29   : signed(THETA_WIDTH-1 downto 0) := to_signed(-1686629713, THETA_WIDTH);

    constant TWO_PI_Q2_29   : signed(THETA_WIDTH downto 0)   :=
        resize(PI_Q2_29, THETA_WIDTH+1) + resize(PI_Q2_29, THETA_WIDTH+1);

    constant C_FREQ_SCALE   : signed(31 downto 0) := to_signed(4172521, 32);

    constant F_NOMINAL_Q16_16 : signed(OUTPUT_WIDTH-1 downto 0) := to_signed(3276800, OUTPUT_WIDTH);

    constant C_ROCOF_SCALE  : signed(31 downto 0) := to_signed(3276800, 32);

    signal theta_reg1       : signed(THETA_WIDTH-1 downto 0) := (others => '0');
    signal theta_reg2       : signed(THETA_WIDTH-1 downto 0) := (others => '0');

    signal freq_reg1        : signed(OUTPUT_WIDTH-1 downto 0) := (others => '0');
    signal freq_reg2        : signed(OUTPUT_WIDTH-1 downto 0) := (others => '0');

    signal delta_theta_raw  : signed(THETA_WIDTH downto 0);
    signal delta_theta      : signed(THETA_WIDTH downto 0);
    signal product_freq     : signed(64 downto 0);
    signal delta_f          : signed(OUTPUT_WIDTH-1 downto 0);
    signal frequency_calc   : signed(OUTPUT_WIDTH-1 downto 0);
    signal delta_f_rocof    : signed(OUTPUT_WIDTH-1 downto 0);
    signal product_rocof    : signed(63 downto 0);
    signal rocof_calc       : signed(OUTPUT_WIDTH-1 downto 0);

    signal valid_count      : unsigned(1 downto 0) := (others => '0');
    signal calc_valid       : std_logic;
    signal pipeline_valid   : std_logic_vector(5 downto 0) := (others => '0');
    signal phase_jump_flag  : std_logic := '0';

begin

    state_register: process(clk, rst)
    begin
        if rst = '1' then
            current_state <= IDLE;
        elsif rising_edge(clk) then
            current_state <= next_state;
        end if;
    end process;

    next_state_logic: process(current_state, theta_valid)
    begin
        next_state <= current_state;

        case current_state is
            when IDLE =>
                if theta_valid = '1' then
                    next_state <= FIRST_SAMPLE;
                end if;

            when FIRST_SAMPLE =>
                if theta_valid = '1' then
                    next_state <= CALCULATING;
                end if;

            when CALCULATING =>
                null;

            when others =>
                next_state <= IDLE;
        end case;
    end process;

    fsm_output: process(current_state)
    begin
        case current_state is
            when IDLE =>
                ready <= '1';
                calc_valid <= '0';

            when FIRST_SAMPLE =>
                ready <= '1';
                calc_valid <= '0';

            when CALCULATING =>
                ready <= '1';
                calc_valid <= '1';

            when others =>
                ready <= '0';
                calc_valid <= '0';
        end case;
    end process;

    valid_counter: process(clk, rst)
    begin
        if rst = '1' then
            valid_count <= (others => '0');
        elsif rising_edge(clk) then
            if current_state = IDLE then
                valid_count <= (others => '0');
            elsif theta_valid = '1' and valid_count < 3 then
                valid_count <= valid_count + 1;
            end if;
        end if;
    end process;

    sliding_window_theta: process(clk, rst)
    begin
        if rst = '1' then
            theta_reg1 <= (others => '0');
            theta_reg2 <= (others => '0');
            pipeline_valid(0) <= '0';
        elsif rising_edge(clk) then
            if theta_valid = '1' then
                theta_reg1 <= theta_reg2;
                theta_reg2 <= signed(theta_in);
                pipeline_valid(0) <= '1';
            else
                pipeline_valid(0) <= '0';
            end if;
        end if;
    end process;

    phase_difference: process(clk, rst)
    begin
        if rst = '1' then
            delta_theta_raw <= (others => '0');
            pipeline_valid(1) <= '0';
        elsif rising_edge(clk) then
            if pipeline_valid(0) = '1' then
                delta_theta_raw <= resize(theta_reg2, THETA_WIDTH+1) -
                                   resize(theta_reg1, THETA_WIDTH+1);
                pipeline_valid(1) <= '1';
            else
                pipeline_valid(1) <= '0';
            end if;
        end if;
    end process;

    phase_unwrap: process(clk, rst)
        variable large_jump : std_logic;
    begin
        if rst = '1' then
            delta_theta <= (others => '0');
            pipeline_valid(2) <= '0';
            phase_jump_flag <= '0';
        elsif rising_edge(clk) then
            if pipeline_valid(1) = '1' then
                large_jump := '0';

                if delta_theta_raw > resize(PI_Q2_29, THETA_WIDTH+1) then
                    delta_theta <= delta_theta_raw - TWO_PI_Q2_29;
                    large_jump := '1';
                elsif delta_theta_raw < resize(NEG_PI_Q2_29, THETA_WIDTH+1) then
                    delta_theta <= delta_theta_raw + TWO_PI_Q2_29;
                    large_jump := '1';
                else
                    delta_theta <= delta_theta_raw;
                end if;

                phase_jump_flag <= large_jump;
                pipeline_valid(2) <= '1';
            else
                pipeline_valid(2) <= '0';
                phase_jump_flag <= '0';
            end if;
        end if;
    end process;

    freq_multiply: process(clk, rst)
    begin
        if rst = '1' then
            product_freq <= (others => '0');
            delta_f <= (others => '0');
            pipeline_valid(3) <= '0';
        elsif rising_edge(clk) then
            if pipeline_valid(2) = '1' then

                product_freq <= delta_theta * C_FREQ_SCALE;

                delta_f <= resize(shift_right(product_freq, 32), OUTPUT_WIDTH);

                pipeline_valid(3) <= '1';
            else
                pipeline_valid(3) <= '0';
            end if;
        end if;
    end process;

    add_nominal_freq: process(clk, rst)
        variable temp_sum : signed(OUTPUT_WIDTH downto 0);
    begin
        if rst = '1' then
            frequency_calc <= (others => '0');
            pipeline_valid(4) <= '0';
        elsif rising_edge(clk) then
            if pipeline_valid(3) = '1' then
                temp_sum := resize(F_NOMINAL_Q16_16, OUTPUT_WIDTH+1) +
                            resize(delta_f, OUTPUT_WIDTH+1);

                if temp_sum > to_signed(2147483647, OUTPUT_WIDTH+1) then
                    frequency_calc <= to_signed(2147483647, OUTPUT_WIDTH);
                elsif temp_sum < to_signed(-2147483648, OUTPUT_WIDTH+1) then
                    frequency_calc <= to_signed(-2147483648, OUTPUT_WIDTH);
                else
                    frequency_calc <= temp_sum(OUTPUT_WIDTH-1 downto 0);
                end if;

                pipeline_valid(4) <= calc_valid;
            else
                pipeline_valid(4) <= '0';
            end if;
        end if;
    end process;

    sliding_window_freq: process(clk, rst)
    begin
        if rst = '1' then
            freq_reg1 <= (others => '0');
            freq_reg2 <= (others => '0');
        elsif rising_edge(clk) then
            if pipeline_valid(4) = '1' then
                freq_reg1 <= freq_reg2;
                freq_reg2 <= frequency_calc;
            end if;
        end if;
    end process;

    rocof_calculation: process(clk, rst)
    begin
        if rst = '1' then
            delta_f_rocof <= (others => '0');
            product_rocof <= (others => '0');
            rocof_calc <= (others => '0');
            pipeline_valid(5) <= '0';
        elsif rising_edge(clk) then
            if pipeline_valid(4) = '1' then

                delta_f_rocof <= freq_reg2 - freq_reg1;

                product_rocof <= delta_f_rocof * C_ROCOF_SCALE;

                rocof_calc <= resize(shift_right(product_rocof, 16), OUTPUT_WIDTH);

                pipeline_valid(5) <= '1';
            else
                pipeline_valid(5) <= '0';
            end if;
        end if;
    end process;

    output_assignment: process(clk, rst)
    begin
        if rst = '1' then
            frequency_out <= (others => '0');
            rocof_out <= (others => '0');
            freq_valid <= '0';
            rocof_valid <= '0';
            phase_jump <= '0';
        elsif rising_edge(clk) then

            frequency_out <= std_logic_vector(frequency_calc);
            rocof_out <= std_logic_vector(rocof_calc);

            if pipeline_valid(4) = '1' and valid_count >= 2 then
                freq_valid <= '1';
            else
                freq_valid <= '0';
            end if;

            if pipeline_valid(5) = '1' and valid_count >= 3 then
                rocof_valid <= '1';
            else
                rocof_valid <= '0';
            end if;

            phase_jump <= phase_jump_flag;
        end if;
    end process;

end behavioral;
