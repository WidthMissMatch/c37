library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity cordic_calculator_256 is
    generic (
        INPUT_WIDTH  : integer := 32;
        ANGLE_WIDTH  : integer := 16;
        ITERATIONS   : integer := 16
    );
    port (
        clk          : in  std_logic;
        rst          : in  std_logic;

        start        : in  std_logic;
        real_in      : in  std_logic_vector(INPUT_WIDTH-1 downto 0);
        imag_in      : in  std_logic_vector(INPUT_WIDTH-1 downto 0);

        phase_out    : out std_logic_vector(ANGLE_WIDTH-1 downto 0);
        magnitude_out: out std_logic_vector(INPUT_WIDTH-1 downto 0);
        valid_out    : out std_logic;
        busy         : out std_logic
    );
end cordic_calculator_256;

architecture behavioral of cordic_calculator_256 is

    type atan_table_type is array (0 to 15) of signed(ANGLE_WIDTH-1 downto 0);
    constant ATAN_TABLE : atan_table_type := (
        to_signed(6434, ANGLE_WIDTH),
        to_signed(3798, ANGLE_WIDTH),
        to_signed(2007, ANGLE_WIDTH),
        to_signed(1019, ANGLE_WIDTH),
        to_signed(511, ANGLE_WIDTH),
        to_signed(256, ANGLE_WIDTH),
        to_signed(128, ANGLE_WIDTH),
        to_signed(64, ANGLE_WIDTH),
        to_signed(32, ANGLE_WIDTH),
        to_signed(16, ANGLE_WIDTH),
        to_signed(8, ANGLE_WIDTH),
        to_signed(4, ANGLE_WIDTH),
        to_signed(2, ANGLE_WIDTH),
        to_signed(1, ANGLE_WIDTH),
        to_signed(1, ANGLE_WIDTH),
        to_signed(0, ANGLE_WIDTH)
    );

    type state_type is (IDLE, SETUP, ITERATE, DONE);
    signal state : state_type;

    signal x_work : signed(INPUT_WIDTH+4 downto 0);
    signal y_work : signed(INPUT_WIDTH+4 downto 0);
    signal z_work : signed(ANGLE_WIDTH-1 downto 0);

    signal iter_count : integer range 0 to ITERATIONS;

    signal real_reg : signed(INPUT_WIDTH-1 downto 0);
    signal imag_reg : signed(INPUT_WIDTH-1 downto 0);

    constant PI_HALF : signed(ANGLE_WIDTH-1 downto 0) := to_signed(12868, ANGLE_WIDTH);
    constant PI_FULL : signed(ANGLE_WIDTH-1 downto 0) := to_signed(25736, ANGLE_WIDTH);

    constant RMS_SCALE : signed(15 downto 0) := to_signed(18432, 16);

begin

    process(clk, rst)
        variable x_temp, y_temp : signed(INPUT_WIDTH+4 downto 0);
        variable z_temp : signed(ANGLE_WIDTH-1 downto 0);
        variable x_shift, y_shift : signed(INPUT_WIDTH+4 downto 0);
        variable final_phase : signed(ANGLE_WIDTH-1 downto 0);
        variable final_magnitude : signed(INPUT_WIDTH+4 downto 0);
        variable magnitude_with_gain_comp : signed(INPUT_WIDTH downto 0);
        variable magnitude_scaled : signed(INPUT_WIDTH+16 downto 0);
        variable gain_comp_product : signed(INPUT_WIDTH+20 downto 0);
    begin
        if rst = '1' then
            state <= IDLE;
            x_work <= (others => '0');
            y_work <= (others => '0');
            z_work <= (others => '0');
            iter_count <= 0;
            real_reg <= (others => '0');
            imag_reg <= (others => '0');
            phase_out <= (others => '0');
            magnitude_out <= (others => '0');
            valid_out <= '0';
            busy <= '0';

        elsif rising_edge(clk) then
            case state is

                when IDLE =>
                    valid_out <= '0';
                    if start = '1' then
                        real_reg <= signed(real_in);
                        imag_reg <= signed(imag_in);
                        busy <= '1';
                        state <= SETUP;
                    else
                        busy <= '0';
                    end if;

                when SETUP =>

                    if real_reg >= 0 then

                        x_work <= resize(real_reg, INPUT_WIDTH+5);
                        y_work <= resize(imag_reg, INPUT_WIDTH+5);
                        z_work <= (others => '0');
                    else

                        x_work <= resize(-real_reg, INPUT_WIDTH+5);
                        y_work <= resize(-imag_reg, INPUT_WIDTH+5);
                        z_work <= PI_FULL;
                    end if;

                    iter_count <= 0;
                    state <= ITERATE;

                when ITERATE =>
                    if iter_count < ITERATIONS then
                        x_temp := x_work;
                        y_temp := y_work;
                        z_temp := z_work;

                        if iter_count < INPUT_WIDTH+5 then
                            x_shift := shift_right(x_temp, iter_count);
                            y_shift := shift_right(y_temp, iter_count);
                        else
                            x_shift := (others => '0');
                            y_shift := (others => '0');
                        end if;

                        if y_temp >= 0 then
                            x_work <= x_temp + y_shift;
                            y_work <= y_temp - x_shift;
                            z_work <= z_temp + ATAN_TABLE(iter_count);
                        else
                            x_work <= x_temp - y_shift;
                            y_work <= y_temp + x_shift;
                            z_work <= z_temp - ATAN_TABLE(iter_count);
                        end if;

                        iter_count <= iter_count + 1;
                    else
                        state <= DONE;
                    end if;

                when DONE =>

                    final_phase := z_work;

                    if final_phase > PI_FULL then
                        final_phase := final_phase - (PI_FULL sll 1);
                    elsif final_phase <= -PI_FULL then
                        final_phase := final_phase + (PI_FULL sll 1);
                    end if;

                    phase_out <= std_logic_vector(final_phase);

                    if x_work >= 0 then
                        final_magnitude := x_work;
                    else
                        final_magnitude := -x_work;
                    end if;

                    gain_comp_product := final_magnitude * to_signed(19898, 16);
                    magnitude_with_gain_comp := resize(shift_right(gain_comp_product, 15), INPUT_WIDTH+1);

                    magnitude_scaled := magnitude_with_gain_comp * RMS_SCALE;

                    magnitude_out <= std_logic_vector(resize(
                        shift_right(magnitude_scaled, 15),
                        INPUT_WIDTH));

                    valid_out <= '1';
                    busy <= '0';
                    state <= IDLE;

                when others =>
                    state <= IDLE;
            end case;
        end if;
    end process;

end behavioral;
