library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tve_calculator is
    generic (
        DATA_WIDTH      : integer := 32;
        OUTPUT_WIDTH    : integer := 16;
        CORDIC_ITER     : integer := 16
    );
    port (

        clk             : in  std_logic;
        rst             : in  std_logic;

        ref_real        : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        ref_imag        : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        ref_valid       : in  std_logic;

        meas_real       : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        meas_imag       : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        meas_valid      : in  std_logic;

        tve_percent     : out std_logic_vector(OUTPUT_WIDTH-1 downto 0);
        tve_valid       : out std_logic;

        tve_pass        : out std_logic;
        tve_exceeds     : out std_logic;
        busy            : out std_logic
    );
end tve_calculator;

architecture behavioral of tve_calculator is

    type state_type is (IDLE, CALC_DIFF, CORDIC_ERROR, CORDIC_REF,
                        DIVIDE, OUTPUT_RESULT);
    signal current_state : state_type;
    signal next_state    : state_type;

    signal diff_real    : signed(DATA_WIDTH downto 0);
    signal diff_imag    : signed(DATA_WIDTH downto 0);

    signal ref_real_reg : signed(DATA_WIDTH-1 downto 0);
    signal ref_imag_reg : signed(DATA_WIDTH-1 downto 0);

    signal cordic_x_in     : signed(DATA_WIDTH downto 0);
    signal cordic_y_in     : signed(DATA_WIDTH downto 0);
    signal cordic_x_out    : signed(DATA_WIDTH downto 0);
    signal cordic_y_out    : signed(DATA_WIDTH downto 0);
    signal cordic_iter_cnt : integer range 0 to CORDIC_ITER;
    signal cordic_running  : std_logic;

    signal error_magnitude : unsigned(DATA_WIDTH-1 downto 0);
    signal ref_magnitude   : unsigned(DATA_WIDTH-1 downto 0);

    signal tve_result      : unsigned(OUTPUT_WIDTH-1 downto 0);
    signal tve_valid_reg   : std_logic;

    signal busy_reg        : std_logic;

    constant CORDIC_GAIN   : unsigned(15 downto 0) := to_unsigned(19898, 16);

    constant TVE_THRESHOLD_1PCT : unsigned(OUTPUT_WIDTH-1 downto 0) := to_unsigned(128, OUTPUT_WIDTH);
    constant TVE_THRESHOLD_3PCT : unsigned(OUTPUT_WIDTH-1 downto 0) := to_unsigned(384, OUTPUT_WIDTH);

begin

    state_sync: process(clk, rst)
    begin
        if rst = '1' then
            current_state <= IDLE;
        elsif rising_edge(clk) then
            current_state <= next_state;
        end if;
    end process;

    state_comb: process(current_state, ref_valid, meas_valid, cordic_iter_cnt)
    begin
        next_state <= current_state;

        case current_state is
            when IDLE =>
                if ref_valid = '1' and meas_valid = '1' then
                    next_state <= CALC_DIFF;
                end if;

            when CALC_DIFF =>
                next_state <= CORDIC_ERROR;

            when CORDIC_ERROR =>
                if cordic_iter_cnt = CORDIC_ITER then
                    next_state <= CORDIC_REF;
                end if;

            when CORDIC_REF =>
                if cordic_iter_cnt = CORDIC_ITER then
                    next_state <= DIVIDE;
                end if;

            when DIVIDE =>
                next_state <= OUTPUT_RESULT;

            when OUTPUT_RESULT =>
                next_state <= IDLE;

            when others =>
                next_state <= IDLE;
        end case;
    end process;

    datapath: process(clk, rst)
        variable real_ext : signed(DATA_WIDTH downto 0);
        variable imag_ext : signed(DATA_WIDTH downto 0);
        variable x_temp   : signed(DATA_WIDTH downto 0);
        variable y_temp   : signed(DATA_WIDTH downto 0);
        variable shift_amt: integer;
        variable div_result : unsigned(48 downto 0);
    begin
        if rst = '1' then
            diff_real <= (others => '0');
            diff_imag <= (others => '0');
            ref_real_reg <= (others => '0');
            ref_imag_reg <= (others => '0');
            cordic_x_in <= (others => '0');
            cordic_y_in <= (others => '0');
            cordic_x_out <= (others => '0');
            cordic_y_out <= (others => '0');
            cordic_iter_cnt <= 0;
            cordic_running <= '0';
            error_magnitude <= (others => '0');
            ref_magnitude <= (others => '0');
            tve_result <= (others => '0');
            tve_valid_reg <= '0';
            busy_reg <= '0';

        elsif rising_edge(clk) then

            tve_valid_reg <= '0';

            case current_state is
                when IDLE =>
                    busy_reg <= '0';
                    cordic_iter_cnt <= 0;

                    if ref_valid = '1' and meas_valid = '1' then
                        ref_real_reg <= signed(ref_real);
                        ref_imag_reg <= signed(ref_imag);
                        busy_reg <= '1';
                    end if;

                when CALC_DIFF =>

                    real_ext := resize(signed(ref_real), DATA_WIDTH + 1);
                    imag_ext := resize(signed(ref_imag), DATA_WIDTH + 1);

                    diff_real <= real_ext - resize(signed(meas_real), DATA_WIDTH + 1);
                    diff_imag <= imag_ext - resize(signed(meas_imag), DATA_WIDTH + 1);

                    cordic_iter_cnt <= 0;

                when CORDIC_ERROR =>

                    if cordic_iter_cnt = 0 then

                        if diff_real(DATA_WIDTH) = '0' then
                            cordic_x_in <= diff_real;
                        else
                            cordic_x_in <= -diff_real;
                        end if;

                        if diff_imag(DATA_WIDTH) = '0' then
                            cordic_y_in <= diff_imag;
                        else
                            cordic_y_in <= -diff_imag;
                        end if;

                        cordic_x_out <= cordic_x_in;
                        cordic_y_out <= cordic_y_in;
                        cordic_iter_cnt <= cordic_iter_cnt + 1;

                    elsif cordic_iter_cnt < CORDIC_ITER then

                        if cordic_y_out(DATA_WIDTH) = '0' then
                            x_temp := cordic_x_out + shift_right(cordic_y_out, cordic_iter_cnt);
                            y_temp := cordic_y_out - shift_right(cordic_x_out, cordic_iter_cnt);
                        else
                            x_temp := cordic_x_out - shift_right(cordic_y_out, cordic_iter_cnt);
                            y_temp := cordic_y_out + shift_right(cordic_x_out, cordic_iter_cnt);
                        end if;

                        cordic_x_out <= x_temp;
                        cordic_y_out <= y_temp;
                        cordic_iter_cnt <= cordic_iter_cnt + 1;

                    else

                        div_result := unsigned(abs(cordic_x_out)) * CORDIC_GAIN;
                        error_magnitude <= div_result(47 downto 16);
                        cordic_iter_cnt <= 0;
                    end if;

                when CORDIC_REF =>

                    if cordic_iter_cnt = 0 then

                        if ref_real_reg(DATA_WIDTH-1) = '0' then
                            cordic_x_in <= resize(ref_real_reg, DATA_WIDTH + 1);
                        else
                            cordic_x_in <= resize(-ref_real_reg, DATA_WIDTH + 1);
                        end if;

                        if ref_imag_reg(DATA_WIDTH-1) = '0' then
                            cordic_y_in <= resize(ref_imag_reg, DATA_WIDTH + 1);
                        else
                            cordic_y_in <= resize(-ref_imag_reg, DATA_WIDTH + 1);
                        end if;

                        cordic_x_out <= cordic_x_in;
                        cordic_y_out <= cordic_y_in;
                        cordic_iter_cnt <= cordic_iter_cnt + 1;

                    elsif cordic_iter_cnt < CORDIC_ITER then

                        if cordic_y_out(DATA_WIDTH) = '0' then
                            x_temp := cordic_x_out + shift_right(cordic_y_out, cordic_iter_cnt);
                            y_temp := cordic_y_out - shift_right(cordic_x_out, cordic_iter_cnt);
                        else
                            x_temp := cordic_x_out - shift_right(cordic_y_out, cordic_iter_cnt);
                            y_temp := cordic_y_out + shift_right(cordic_x_out, cordic_iter_cnt);
                        end if;

                        cordic_x_out <= x_temp;
                        cordic_y_out <= y_temp;
                        cordic_iter_cnt <= cordic_iter_cnt + 1;

                    else

                        div_result := unsigned(abs(cordic_x_out)) * CORDIC_GAIN;
                        ref_magnitude <= div_result(47 downto 16);
                        cordic_iter_cnt <= 0;
                    end if;

                when DIVIDE =>

                    if ref_magnitude > 0 then

                        div_result := resize(error_magnitude * to_unsigned(12800, 16), 49);

                        if ref_magnitude /= 0 then
                            tve_result <= resize(div_result / ref_magnitude, OUTPUT_WIDTH);
                        else
                            tve_result <= (others => '1');
                        end if;
                    else
                        tve_result <= (others => '1');
                    end if;

                when OUTPUT_RESULT =>
                    tve_valid_reg <= '1';
                    busy_reg <= '0';

                when others =>
                    null;

            end case;
        end if;
    end process;

    tve_percent <= std_logic_vector(tve_result);
    tve_valid <= tve_valid_reg;
    busy <= busy_reg;

    tve_pass <= '1' when (tve_result < TVE_THRESHOLD_1PCT) else '0';
    tve_exceeds <= '1' when (tve_result > TVE_THRESHOLD_3PCT) else '0';

end behavioral;
