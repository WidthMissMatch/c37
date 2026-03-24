library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity taylor_frequency_estimator is
    generic (
        INPUT_WIDTH  : integer := 32;
        FREQ_WIDTH   : integer := 32;
        FRAC_BITS    : integer := 16
    );
    port (
        clk                : in  std_logic;
        rst                : in  std_logic;

        c0_real            : in  std_logic_vector(INPUT_WIDTH-1 downto 0);
        c0_imag            : in  std_logic_vector(INPUT_WIDTH-1 downto 0);
        c1_real            : in  std_logic_vector(INPUT_WIDTH-1 downto 0);
        c1_imag            : in  std_logic_vector(INPUT_WIDTH-1 downto 0);
        taylor_valid       : in  std_logic;

        std_frequency      : in  std_logic_vector(FREQ_WIDTH-1 downto 0);
        std_freq_valid     : in  std_logic;

        taylor_frequency   : out std_logic_vector(FREQ_WIDTH-1 downto 0);
        taylor_freq_valid  : out std_logic;
        transient_detected : out std_logic;
        taylor_rocof       : out std_logic_vector(FREQ_WIDTH-1 downto 0)
    );
end taylor_frequency_estimator;

architecture behavioral of taylor_frequency_estimator is

    type state_type is (IDLE, CROSS_PRODUCT_1, CROSS_PRODUCT_2,
                        MAG_SQUARED_1, MAG_SQUARED_2,
                        BIAS_CORRECT_1, BIAS_CORRECT_2,
                        CHECK_MAG, DIVIDE_INIT, DIVIDE_LOOP,
                        DIVIDE_FINISH, SCALE_1, SCALE_2, OUTPUT_FREQ);
    signal state : state_type;

    constant K_CONST : signed(31 downto 0) := to_signed(15961896, 32);

    constant BIAS_B : signed(15 downto 0) := to_signed(869, 16);

    constant FREQ_50HZ : signed(FREQ_WIDTH-1 downto 0) := to_signed(3276800, FREQ_WIDTH);

    constant MIN_MAG_SQ : signed(63 downto 0) := to_signed(1024, 64);

    constant ENTER_THRESH : unsigned(FREQ_WIDTH-1 downto 0) := to_unsigned(6554, FREQ_WIDTH);
    constant EXIT_THRESH  : unsigned(FREQ_WIDTH-1 downto 0) := to_unsigned(1311, FREQ_WIDTH);

    signal c0r, c0i, c1r, c1i : signed(INPUT_WIDTH-1 downto 0);

    signal cross_prod_a  : signed(63 downto 0);
    signal cross_prod_b  : signed(63 downto 0);
    signal cross_result  : signed(63 downto 0);

    signal mag_sq_a      : signed(63 downto 0);
    signal mag_sq_b      : signed(63 downto 0);
    signal mag_sq_result : signed(63 downto 0);

    signal bias_diff     : signed(63 downto 0);
    signal bias_prod     : signed(79 downto 0);

    signal div_numer     : unsigned(63 downto 0);
    signal div_denom     : unsigned(63 downto 0);
    signal div_accum     : unsigned(63 downto 0);
    signal div_result    : unsigned(63 downto 0);
    signal div_counter   : integer range 0 to 63;
    signal cross_neg     : std_logic;

    signal delta_f_wide  : signed(63 downto 0);
    signal delta_f       : signed(FREQ_WIDTH-1 downto 0);
    signal quotient_signed : signed(31 downto 0);

    signal taylor_freq_reg : signed(FREQ_WIDTH-1 downto 0);
    signal valid_reg       : std_logic;

    signal transient_reg   : std_logic;
    signal std_freq_reg    : signed(FREQ_WIDTH-1 downto 0);

    signal prev_taylor_freq : signed(FREQ_WIDTH-1 downto 0);
    signal rocof_reg        : signed(FREQ_WIDTH-1 downto 0);
    signal first_measurement : std_logic;

begin

    main_fsm: process(clk, rst)
        variable freq_diff     : signed(FREQ_WIDTH-1 downto 0);
        variable freq_diff_abs : unsigned(FREQ_WIDTH-1 downto 0);
        variable trial_sub     : unsigned(63 downto 0);
        variable new_accum     : unsigned(63 downto 0);
        variable rocof_wide    : signed(63 downto 0);
    begin
        if rst = '1' then
            state           <= IDLE;
            valid_reg       <= '0';
            transient_reg   <= '0';
            taylor_freq_reg <= FREQ_50HZ;
            std_freq_reg    <= FREQ_50HZ;
            prev_taylor_freq <= FREQ_50HZ;
            rocof_reg       <= (others => '0');
            first_measurement <= '1';
            cross_prod_a    <= (others => '0');
            cross_prod_b    <= (others => '0');
            cross_result    <= (others => '0');
            mag_sq_a        <= (others => '0');
            mag_sq_b        <= (others => '0');
            mag_sq_result   <= (others => '0');
            bias_diff       <= (others => '0');
            bias_prod       <= (others => '0');
            div_numer       <= (others => '0');
            div_denom       <= (others => '0');
            div_accum       <= (others => '0');
            div_result      <= (others => '0');
            div_counter     <= 0;
            cross_neg       <= '0';
            delta_f_wide    <= (others => '0');
            delta_f         <= (others => '0');
            quotient_signed <= (others => '0');
            c0r <= (others => '0');
            c0i <= (others => '0');
            c1r <= (others => '0');
            c1i <= (others => '0');

        elsif rising_edge(clk) then

            valid_reg <= '0';

            if std_freq_valid = '1' then
                std_freq_reg <= signed(std_frequency);
            end if;

            case state is

                when IDLE =>
                    if taylor_valid = '1' then
                        c0r <= signed(c0_real);
                        c0i <= signed(c0_imag);
                        c1r <= signed(c1_real);
                        c1i <= signed(c1_imag);
                        state <= CROSS_PRODUCT_1;
                    end if;

                when CROSS_PRODUCT_1 =>
                    cross_prod_a <= resize(c1i * c0r, 64);
                    cross_prod_b <= resize(c1r * c0i, 64);
                    state <= CROSS_PRODUCT_2;

                when CROSS_PRODUCT_2 =>
                    cross_result <= cross_prod_a - cross_prod_b;
                    state <= MAG_SQUARED_1;

                when MAG_SQUARED_1 =>
                    mag_sq_a <= resize(c0r * c0r, 64);
                    mag_sq_b <= resize(c0i * c0i, 64);
                    state <= MAG_SQUARED_2;

                when MAG_SQUARED_2 =>
                    mag_sq_result <= mag_sq_a + mag_sq_b;
                    bias_diff     <= mag_sq_a - mag_sq_b;
                    state <= BIAS_CORRECT_1;

                when BIAS_CORRECT_1 =>

                    bias_prod <= bias_diff * BIAS_B;
                    state <= BIAS_CORRECT_2;

                when BIAS_CORRECT_2 =>

                    cross_result <= cross_result + resize(shift_right(bias_prod, 15), 64);
                    state <= CHECK_MAG;

                when CHECK_MAG =>
                    if mag_sq_result < MIN_MAG_SQ then
                        taylor_freq_reg <= std_freq_reg;
                        valid_reg <= '1';
                        state <= IDLE;
                    else
                        state <= DIVIDE_INIT;
                    end if;

                when DIVIDE_INIT =>

                    if cross_result(63) = '1' then
                        cross_neg <= '1';
                        div_numer <= unsigned(shift_left(-cross_result, 16));
                    else
                        cross_neg <= '0';
                        div_numer <= unsigned(shift_left(cross_result, 16));
                    end if;
                    div_denom   <= unsigned(mag_sq_result);
                    div_accum   <= (others => '0');
                    div_result  <= (others => '0');
                    div_counter <= 63;
                    state       <= DIVIDE_LOOP;

                when DIVIDE_LOOP =>

                    new_accum := shift_left(div_accum, 1);
                    new_accum(0) := div_numer(div_counter);

                    if new_accum >= div_denom then
                        div_accum <= new_accum - div_denom;
                        div_result(div_counter) <= '1';
                    else
                        div_accum <= new_accum;
                        div_result(div_counter) <= '0';
                    end if;

                    if div_counter = 0 then
                        state <= DIVIDE_FINISH;
                    else
                        div_counter <= div_counter - 1;
                    end if;

                when DIVIDE_FINISH =>

                    if cross_neg = '1' then
                        quotient_signed <= -signed(div_result(31 downto 0));
                    else
                        quotient_signed <= signed(div_result(31 downto 0));
                    end if;
                    state <= SCALE_1;

                when SCALE_1 =>

                    delta_f_wide <= resize(quotient_signed * K_CONST, 64);
                    state <= SCALE_2;

                when SCALE_2 =>

                    delta_f <= resize(shift_right(delta_f_wide, FRAC_BITS), FREQ_WIDTH);
                    state <= OUTPUT_FREQ;

                when OUTPUT_FREQ =>
                    taylor_freq_reg <= FREQ_50HZ + delta_f;

                    if first_measurement = '1' then
                        rocof_reg <= (others => '0');
                        first_measurement <= '0';
                    else
                        freq_diff := (FREQ_50HZ + delta_f) - prev_taylor_freq;

                        rocof_wide := resize(freq_diff * to_signed(50, FREQ_WIDTH), 64);
                        rocof_reg <= resize(rocof_wide, FREQ_WIDTH);
                    end if;
                    prev_taylor_freq <= FREQ_50HZ + delta_f;

                    freq_diff := (FREQ_50HZ + delta_f) - std_freq_reg;
                    if freq_diff(FREQ_WIDTH-1) = '1' then
                        freq_diff_abs := unsigned(-freq_diff);
                    else
                        freq_diff_abs := unsigned(freq_diff);
                    end if;

                    if transient_reg = '0' then
                        if freq_diff_abs > ENTER_THRESH then
                            transient_reg <= '1';
                        end if;
                    else
                        if freq_diff_abs < EXIT_THRESH then
                            transient_reg <= '0';
                        end if;
                    end if;

                    valid_reg <= '1';
                    state <= IDLE;

            end case;
        end if;
    end process;

    taylor_frequency   <= std_logic_vector(taylor_freq_reg);
    taylor_freq_valid  <= valid_reg;
    transient_detected <= transient_reg;
    taylor_rocof       <= std_logic_vector(rocof_reg);

end behavioral;
