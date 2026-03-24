library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity taylor_dft_calculator is
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
end taylor_dft_calculator;

architecture behavioral of taylor_dft_calculator is

    type state_type is (IDLE, INIT, FETCH_ADDR, WAIT_ROM, MULTIPLY_W,
                        MULTIPLY_TRIG, SCALE, ACCUMULATE, DONE_STATE);
    signal state : state_type;

    signal sample_cnt : unsigned(8 downto 0) := (others => '0');
    signal addr_reg   : unsigned(7 downto 0) := (others => '0');

    signal sample_reg : signed(SAMPLE_WIDTH-1 downto 0);
    signal cos_reg    : signed(COEFF_WIDTH-1 downto 0);
    signal sin_reg    : signed(COEFF_WIDTH-1 downto 0);
    signal w1_reg     : signed(COEFF_WIDTH-1 downto 0);
    signal w2_reg     : signed(COEFF_WIDTH-1 downto 0);

    signal w1_sample  : signed(SAMPLE_WIDTH-1 downto 0);
    signal w2_sample  : signed(SAMPLE_WIDTH-1 downto 0);

    signal prod_c0_real : signed(SAMPLE_WIDTH + COEFF_WIDTH - 1 downto 0);
    signal prod_c0_imag : signed(SAMPLE_WIDTH + COEFF_WIDTH - 1 downto 0);
    signal prod_c1_real : signed(SAMPLE_WIDTH + COEFF_WIDTH - 1 downto 0);
    signal prod_c1_imag : signed(SAMPLE_WIDTH + COEFF_WIDTH - 1 downto 0);
    signal prod_c2_real : signed(SAMPLE_WIDTH + COEFF_WIDTH - 1 downto 0);
    signal prod_c2_imag : signed(SAMPLE_WIDTH + COEFF_WIDTH - 1 downto 0);

    signal scaled_c0_real : signed(OUTPUT_WIDTH-1 downto 0);
    signal scaled_c0_imag : signed(OUTPUT_WIDTH-1 downto 0);
    signal scaled_c1_real : signed(OUTPUT_WIDTH-1 downto 0);
    signal scaled_c1_imag : signed(OUTPUT_WIDTH-1 downto 0);
    signal scaled_c2_real : signed(OUTPUT_WIDTH-1 downto 0);
    signal scaled_c2_imag : signed(OUTPUT_WIDTH-1 downto 0);

    signal acc_c0_real : signed(ACCUMULATOR_WIDTH-1 downto 0);
    signal acc_c0_imag : signed(ACCUMULATOR_WIDTH-1 downto 0);
    signal acc_c1_real : signed(ACCUMULATOR_WIDTH-1 downto 0);
    signal acc_c1_imag : signed(ACCUMULATOR_WIDTH-1 downto 0);
    signal acc_c2_real : signed(ACCUMULATOR_WIDTH-1 downto 0);
    signal acc_c2_imag : signed(ACCUMULATOR_WIDTH-1 downto 0);

    signal active_int  : std_logic;

begin

    taylor_active <= active_int;

    fsm: process(clk, rst)
        variable w1_prod : signed(SAMPLE_WIDTH + COEFF_WIDTH - 1 downto 0);
        variable w2_prod : signed(SAMPLE_WIDTH + COEFF_WIDTH - 1 downto 0);
    begin
        if rst = '1' then
            state       <= IDLE;
            sample_cnt  <= (others => '0');
            addr_reg    <= (others => '0');
            active_int  <= '0';
            done        <= '0';
            result_valid <= '0';
            acc_c0_real <= (others => '0');
            acc_c0_imag <= (others => '0');
            acc_c1_real <= (others => '0');
            acc_c1_imag <= (others => '0');
            acc_c2_real <= (others => '0');
            acc_c2_imag <= (others => '0');
            sample_reg  <= (others => '0');
            cos_reg     <= (others => '0');
            sin_reg     <= (others => '0');
            w1_reg      <= (others => '0');
            w2_reg      <= (others => '0');
            w1_sample   <= (others => '0');
            w2_sample   <= (others => '0');
            prod_c0_real <= (others => '0');
            prod_c0_imag <= (others => '0');
            prod_c1_real <= (others => '0');
            prod_c1_imag <= (others => '0');
            prod_c2_real <= (others => '0');
            prod_c2_imag <= (others => '0');
            scaled_c0_real <= (others => '0');
            scaled_c0_imag <= (others => '0');
            scaled_c1_real <= (others => '0');
            scaled_c1_imag <= (others => '0');
            scaled_c2_real <= (others => '0');
            scaled_c2_imag <= (others => '0');

        elsif rising_edge(clk) then

            done         <= '0';
            result_valid <= '0';

            case state is

                when IDLE =>
                    active_int <= '0';
                    if start = '1' then
                        state <= INIT;
                    end if;

                when INIT =>

                    acc_c0_real <= (others => '0');
                    acc_c0_imag <= (others => '0');
                    acc_c1_real <= (others => '0');
                    acc_c1_imag <= (others => '0');
                    acc_c2_real <= (others => '0');
                    acc_c2_imag <= (others => '0');
                    sample_cnt  <= (others => '0');
                    addr_reg    <= (others => '0');
                    active_int  <= '1';
                    state       <= FETCH_ADDR;

                when FETCH_ADDR =>

                    addr_reg <= sample_cnt(7 downto 0);
                    state    <= WAIT_ROM;

                when WAIT_ROM =>

                    sample_reg <= signed(sample_data);
                    cos_reg    <= signed(cos_coeff);
                    sin_reg    <= signed(sin_coeff);
                    w1_reg     <= signed(w1_coeff);
                    w2_reg     <= signed(w2_coeff);
                    state      <= MULTIPLY_W;

                when MULTIPLY_W =>

                    w1_prod := sample_reg * w1_reg;
                    w2_prod := sample_reg * w2_reg;
                    w1_sample <= resize(shift_right(w1_prod, 15), SAMPLE_WIDTH);
                    w2_sample <= resize(shift_right(w2_prod, 15), SAMPLE_WIDTH);
                    state <= MULTIPLY_TRIG;

                when MULTIPLY_TRIG =>

                    prod_c0_real <= sample_reg * cos_reg;
                    prod_c0_imag <= sample_reg * (-sin_reg);

                    prod_c1_real <= w1_sample * cos_reg;
                    prod_c1_imag <= w1_sample * (-sin_reg);

                    prod_c2_real <= w2_sample * cos_reg;
                    prod_c2_imag <= w2_sample * (-sin_reg);
                    state <= SCALE;

                when SCALE =>

                    scaled_c0_real <= resize(shift_right(prod_c0_real, 15), OUTPUT_WIDTH);
                    scaled_c0_imag <= resize(shift_right(prod_c0_imag, 15), OUTPUT_WIDTH);
                    scaled_c1_real <= resize(shift_right(prod_c1_real, 15), OUTPUT_WIDTH);
                    scaled_c1_imag <= resize(shift_right(prod_c1_imag, 15), OUTPUT_WIDTH);
                    scaled_c2_real <= resize(shift_right(prod_c2_real, 15), OUTPUT_WIDTH);
                    scaled_c2_imag <= resize(shift_right(prod_c2_imag, 15), OUTPUT_WIDTH);
                    state <= ACCUMULATE;

                when ACCUMULATE =>

                    acc_c0_real <= acc_c0_real + resize(scaled_c0_real, ACCUMULATOR_WIDTH);
                    acc_c0_imag <= acc_c0_imag + resize(scaled_c0_imag, ACCUMULATOR_WIDTH);
                    acc_c1_real <= acc_c1_real + resize(scaled_c1_real, ACCUMULATOR_WIDTH);
                    acc_c1_imag <= acc_c1_imag + resize(scaled_c1_imag, ACCUMULATOR_WIDTH);
                    acc_c2_real <= acc_c2_real + resize(scaled_c2_real, ACCUMULATOR_WIDTH);
                    acc_c2_imag <= acc_c2_imag + resize(scaled_c2_imag, ACCUMULATOR_WIDTH);

                    sample_cnt <= sample_cnt + 1;

                    if sample_cnt = to_unsigned(WINDOW_SIZE - 1, 9) then
                        state <= DONE_STATE;
                    else
                        state <= FETCH_ADDR;
                    end if;

                when DONE_STATE =>

                    active_int   <= '0';
                    done         <= '1';
                    result_valid <= '1';
                    state        <= IDLE;

            end case;
        end if;
    end process;

    sample_addr <= std_logic_vector(addr_reg);
    cos_addr    <= std_logic_vector(addr_reg);
    sin_addr    <= std_logic_vector(addr_reg);
    taylor_addr <= std_logic_vector(addr_reg);

    c0_real <= std_logic_vector(resize(acc_c0_real, OUTPUT_WIDTH));
    c0_imag <= std_logic_vector(resize(acc_c0_imag, OUTPUT_WIDTH));
    c1_real <= std_logic_vector(resize(acc_c1_real, OUTPUT_WIDTH));
    c1_imag <= std_logic_vector(resize(acc_c1_imag, OUTPUT_WIDTH));
    c2_real <= std_logic_vector(resize(acc_c2_real, OUTPUT_WIDTH));
    c2_imag <= std_logic_vector(resize(acc_c2_imag, OUTPUT_WIDTH));

end behavioral;
