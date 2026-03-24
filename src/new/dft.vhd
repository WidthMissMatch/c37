library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity dft_complex_calculator is
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
end dft_complex_calculator;

architecture behavioral of dft_complex_calculator is

    type state_type is (IDLE, INIT, FETCH_ADDR, WAIT_ROM, MULTIPLY, SCALE, ACCUMULATE, DONE_STATE);
    signal current_state, next_state : state_type;

    signal sample_counter : unsigned(7 downto 0) := (others => '0');
    signal address_reg    : unsigned(7 downto 0) := (others => '0');

    signal rom_wait_counter : unsigned(1 downto 0) := (others => '0');

    signal sample_data_reg    : std_logic_vector(SAMPLE_WIDTH-1 downto 0);
    signal cos_coeff_reg      : std_logic_vector(COEFF_WIDTH-1 downto 0);
    signal sin_coeff_reg      : std_logic_vector(COEFF_WIDTH-1 downto 0);
    signal data_valid_reg     : std_logic;

    signal multiplier_real_a   : signed(SAMPLE_WIDTH-1 downto 0);
    signal multiplier_real_b   : signed(COEFF_WIDTH-1 downto 0);
    signal product_real        : signed(SAMPLE_WIDTH + COEFF_WIDTH - 1 downto 0);
    signal product_real_scaled : signed(OUTPUT_WIDTH-1 downto 0);

    signal multiplier_imag_a   : signed(SAMPLE_WIDTH-1 downto 0);
    signal multiplier_imag_b   : signed(COEFF_WIDTH-1 downto 0);
    signal product_imag        : signed(SAMPLE_WIDTH + COEFF_WIDTH - 1 downto 0);
    signal product_imag_scaled : signed(OUTPUT_WIDTH-1 downto 0);

    signal accumulator_real    : signed(ACCUMULATOR_WIDTH-1 downto 0) := (others => '0');
    signal accumulator_imag    : signed(ACCUMULATOR_WIDTH-1 downto 0) := (others => '0');

    signal multiply_enable : std_logic;
    signal accumulate_enable : std_logic;
    signal clear_accumulator : std_logic;
    signal calculation_done : std_logic;
    signal increment_counter : std_logic;

begin

    state_machine_sync: process(clk, rst)
    begin
        if rst = '1' then
            current_state <= IDLE;
        elsif rising_edge(clk) then
            current_state <= next_state;
        end if;
    end process;

    state_machine_comb: process(current_state, start, sample_counter, data_valid_reg, rom_wait_counter)
    begin

        next_state <= current_state;
        multiply_enable <= '0';
        accumulate_enable <= '0';
        clear_accumulator <= '0';
        calculation_done <= '0';
        increment_counter <= '0';

        case current_state is
            when IDLE =>
                if start = '1' then
                    next_state <= INIT;
                end if;

            when INIT =>
                clear_accumulator <= '1';
                next_state <= FETCH_ADDR;

            when FETCH_ADDR =>

                next_state <= WAIT_ROM;

            when WAIT_ROM =>

                if data_valid_reg = '1' or rom_wait_counter >= 2 then
                    next_state <= MULTIPLY;
                end if;

            when MULTIPLY =>
                multiply_enable <= '1';
                next_state <= SCALE;

            when SCALE =>

                next_state <= ACCUMULATE;

            when ACCUMULATE =>
                accumulate_enable <= '1';
                increment_counter <= '1';

                if sample_counter = WINDOW_SIZE - 1 then
                    next_state <= DONE_STATE;
                else
                    next_state <= FETCH_ADDR;
                end if;

            when DONE_STATE =>
                calculation_done <= '1';
                if start = '0' then
                    next_state <= IDLE;
                end if;

            when others =>
                next_state <= IDLE;
        end case;
    end process;

    rom_wait_process: process(clk, rst)
    begin
        if rst = '1' then
            rom_wait_counter <= (others => '0');
        elsif rising_edge(clk) then
            if current_state = WAIT_ROM then
                if data_valid_reg = '1' then
                    rom_wait_counter <= (others => '0');
                else
                    rom_wait_counter <= rom_wait_counter + 1;
                end if;
            else
                rom_wait_counter <= (others => '0');
            end if;
        end if;
    end process;

    counter_process: process(clk, rst)
    begin
        if rst = '1' then
            sample_counter <= (others => '0');
            address_reg <= (others => '0');
        elsif rising_edge(clk) then
            case current_state is
                when INIT =>
                    sample_counter <= (others => '0');
                    address_reg <= (others => '0');

                when ACCUMULATE =>
                    if increment_counter = '1' then
                        if sample_counter = WINDOW_SIZE - 1 then
                            sample_counter <= (others => '0');
                            address_reg <= (others => '0');
                        else
                            sample_counter <= sample_counter + 1;
                            address_reg <= address_reg + 1;
                        end if;
                    end if;

                when others =>
                    null;
            end case;
        end if;
    end process;

    pipeline_process: process(clk, rst)
    begin
        if rst = '1' then
            sample_data_reg <= (others => '0');
            cos_coeff_reg <= (others => '0');
            sin_coeff_reg <= (others => '0');
            data_valid_reg <= '0';
        elsif rising_edge(clk) then

            if current_state = WAIT_ROM then
                sample_data_reg <= sample_data;

                if cos_valid = '1' and sin_valid = '1' then
                    cos_coeff_reg <= cos_coeff;
                    sin_coeff_reg <= sin_coeff;
                    data_valid_reg <= '1';
                end if;
            else
                data_valid_reg <= '0';
            end if;
        end if;
    end process;

    real_multiplier_process: process(clk, rst)
    begin
        if rst = '1' then
            multiplier_real_a <= (others => '0');
            multiplier_real_b <= (others => '0');
            product_real <= (others => '0');
            product_real_scaled <= (others => '0');
        elsif rising_edge(clk) then

            if multiply_enable = '1' then

                multiplier_real_a <= signed(sample_data_reg);
                multiplier_real_b <= signed(cos_coeff_reg);

                product_real <= signed(sample_data_reg) * signed(cos_coeff_reg);
            end if;

            product_real_scaled <= resize(shift_right(product_real, 15), OUTPUT_WIDTH);
        end if;
    end process;

    imag_multiplier_process: process(clk, rst)
    begin
        if rst = '1' then
            multiplier_imag_a <= (others => '0');
            multiplier_imag_b <= (others => '0');
            product_imag <= (others => '0');
            product_imag_scaled <= (others => '0');
        elsif rising_edge(clk) then

            if multiply_enable = '1' then

                multiplier_imag_a <= signed(sample_data_reg);
                multiplier_imag_b <= signed(sin_coeff_reg);

                product_imag <= -(signed(sample_data_reg) * signed(sin_coeff_reg));
            end if;

            product_imag_scaled <= resize(shift_right(product_imag, 15), OUTPUT_WIDTH);
        end if;
    end process;

    real_accumulator_process: process(clk, rst)
    begin
        if rst = '1' then
            accumulator_real <= (others => '0');
        elsif rising_edge(clk) then
            if clear_accumulator = '1' then
                accumulator_real <= (others => '0');
            elsif accumulate_enable = '1' then

                accumulator_real <= accumulator_real + resize(product_real_scaled, ACCUMULATOR_WIDTH);
            end if;
        end if;
    end process;

    imag_accumulator_process: process(clk, rst)
    begin
        if rst = '1' then
            accumulator_imag <= (others => '0');
        elsif rising_edge(clk) then
            if clear_accumulator = '1' then
                accumulator_imag <= (others => '0');
            elsif accumulate_enable = '1' then

                accumulator_imag <= accumulator_imag + resize(product_imag_scaled, ACCUMULATOR_WIDTH);
            end if;
        end if;
    end process;

    output_process: process(clk, rst)
    begin
        if rst = '1' then
            real_result <= (others => '0');
            imag_result <= (others => '0');
            result_valid <= '0';
        elsif rising_edge(clk) then
            if calculation_done = '1' then

                real_result <= std_logic_vector(accumulator_real(OUTPUT_WIDTH-1 downto 0));
                imag_result <= std_logic_vector(accumulator_imag(OUTPUT_WIDTH-1 downto 0));
                result_valid <= '1';
            elsif current_state = IDLE then
                result_valid <= '0';
            end if;
        end if;
    end process;

    sample_addr <= std_logic_vector(address_reg);
    cos_addr <= std_logic_vector(address_reg);
    sin_addr <= std_logic_vector(address_reg);

    done <= calculation_done;

end behavioral;
