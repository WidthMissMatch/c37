library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity samples_per_cycle_calc is
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
end samples_per_cycle_calc;

architecture behavioral of samples_per_cycle_calc is

    type state_type is (IDLE, NORMALIZE, LOOKUP, ITER1_MULT, ITER1_SUB, ITER1_SCALE,
                        ITER2_MULT, ITER2_SUB, ITER2_SCALE,
                        ITER3_MULT, ITER3_SUB, ITER3_SCALE,
                        FINAL_MULT, OUTPUT_RESULT);
    signal current_state, next_state : state_type;

    type lut_array is array (0 to 63) of unsigned(31 downto 0);

    constant RECIP_LUT : lut_array := (

        to_unsigned(23860929, 32),
        to_unsigned(23778042, 32),
        to_unsigned(23695774, 32),
        to_unsigned(23614118, 32),
        to_unsigned(23533069, 32),
        to_unsigned(23452619, 32),
        to_unsigned(23372762, 32),
        to_unsigned(23293493, 32),
        to_unsigned(23214805, 32),
        to_unsigned(23136692, 32),
        to_unsigned(23059149, 32),
        to_unsigned(22982169, 32),
        to_unsigned(22905747, 32),
        to_unsigned(22829878, 32),
        to_unsigned(22754555, 32),
        to_unsigned(22679774, 32),

        to_unsigned(22605528, 32),
        to_unsigned(22531814, 32),
        to_unsigned(22458625, 32),
        to_unsigned(22385957, 32),
        to_unsigned(22313805, 32),
        to_unsigned(22242163, 32),
        to_unsigned(22171027, 32),
        to_unsigned(22100392, 32),
        to_unsigned(22030253, 32),
        to_unsigned(21960605, 32),
        to_unsigned(21891444, 32),
        to_unsigned(21822766, 32),
        to_unsigned(21754565, 32),
        to_unsigned(21686838, 32),
        to_unsigned(21619579, 32),
        to_unsigned(21552785, 32),

        to_unsigned(21474836, 32),
        to_unsigned(21409159, 32),
        to_unsigned(21343930, 32),
        to_unsigned(21279144, 32),
        to_unsigned(21214798, 32),
        to_unsigned(21150887, 32),
        to_unsigned(21087408, 32),
        to_unsigned(21024356, 32),
        to_unsigned(20961728, 32),
        to_unsigned(20899520, 32),
        to_unsigned(20837727, 32),
        to_unsigned(20776347, 32),
        to_unsigned(20715375, 32),
        to_unsigned(20654808, 32),
        to_unsigned(20594642, 32),
        to_unsigned(20534873, 32),

        to_unsigned(20475499, 32),
        to_unsigned(20416515, 32),
        to_unsigned(20357918, 32),
        to_unsigned(20299704, 32),
        to_unsigned(20241870, 32),
        to_unsigned(20184413, 32),
        to_unsigned(20127328, 32),
        to_unsigned(20070613, 32),
        to_unsigned(20014264, 32),
        to_unsigned(19958279, 32),
        to_unsigned(19902653, 32),
        to_unsigned(19847384, 32),
        to_unsigned(19792468, 32),
        to_unsigned(19737902, 32),
        to_unsigned(19683683, 32),
        to_unsigned(19550632, 32)
    );

    constant FREQ_MIN_Q16 : unsigned(31 downto 0) := to_unsigned(2949120, 32);
    constant FREQ_MAX_Q16 : unsigned(31 downto 0) := to_unsigned(3604480, 32);

constant TWO_Q2_30 : unsigned(31 downto 0) := x"80000000";

    signal freq_reg           : unsigned(31 downto 0);
    signal freq_integer       : unsigned(15 downto 0);
    signal lut_index          : unsigned(5 downto 0);
    signal recip_estimate     : unsigned(31 downto 0);
    signal out_of_range_reg   : std_logic;

    signal nr_product         : unsigned(47 downto 0);
    signal nr_diff            : signed(32 downto 0);

    signal final_product      : unsigned(63 downto 0);
    signal result_reg         : unsigned(31 downto 0);

    signal valid_pipe         : std_logic;

begin

    state_sync: process(clk, rst)
    begin
        if rst = '1' then
            current_state <= IDLE;
        elsif rising_edge(clk) then
            current_state <= next_state;
        end if;
    end process;

    state_comb: process(current_state, freq_valid)
    begin
        next_state <= current_state;

        case current_state is
            when IDLE =>
                if freq_valid = '1' then
                    next_state <= NORMALIZE;
                end if;

            when NORMALIZE =>
                next_state <= LOOKUP;

            when LOOKUP =>
                next_state <= ITER1_MULT;

            when ITER1_MULT =>
                next_state <= ITER1_SUB;
            when ITER1_SUB =>
                next_state <= ITER1_SCALE;
            when ITER1_SCALE =>
                next_state <= ITER2_MULT;

            when ITER2_MULT =>
                next_state <= ITER2_SUB;
            when ITER2_SUB =>
                next_state <= ITER2_SCALE;
            when ITER2_SCALE =>
                next_state <= ITER3_MULT;

            when ITER3_MULT =>
                next_state <= ITER3_SUB;
            when ITER3_SUB =>
                next_state <= ITER3_SCALE;
            when ITER3_SCALE =>
                next_state <= FINAL_MULT;

            when FINAL_MULT =>
                next_state <= OUTPUT_RESULT;

            when OUTPUT_RESULT =>
                next_state <= IDLE;

            when others =>
                next_state <= IDLE;
        end case;
    end process;

    datapath: process(clk, rst)
        variable freq_offset     : unsigned(15 downto 0);
        variable index_mult      : unsigned(23 downto 0);
        variable mult_result_48  : unsigned(47 downto 0);
        variable sub_result      : signed(32 downto 0);
        variable scale_result    : unsigned(63 downto 0);
        variable final_mult_var  : unsigned(63 downto 0);
    begin
        if rst = '1' then
            freq_reg <= (others => '0');
            freq_integer <= (others => '0');
            lut_index <= (others => '0');
            recip_estimate <= (others => '0');
            out_of_range_reg <= '0';
            nr_product <= (others => '0');
            nr_diff <= (others => '0');
            final_product <= (others => '0');
            result_reg <= (others => '0');
            valid_pipe <= '0';

        elsif rising_edge(clk) then

            valid_pipe <= '0';

            case current_state is
                when IDLE =>
                    if freq_valid = '1' then
                        freq_reg <= unsigned(frequency_in);

                        freq_integer <= unsigned(frequency_in(31 downto 16));
                        out_of_range_reg <= '0';
                    end if;

                when NORMALIZE =>

                    if freq_reg < FREQ_MIN_Q16 then

                        lut_index <= (others => '0');
                        out_of_range_reg <= '1';
                        freq_integer <= to_unsigned(45, 16);
                    elsif freq_reg > FREQ_MAX_Q16 then

                        lut_index <= (others => '1');
                        out_of_range_reg <= '1';
                        freq_integer <= to_unsigned(55, 16);
                    else

                        freq_offset := freq_integer - to_unsigned(45, 16);

                        index_mult := freq_offset(7 downto 0) * to_unsigned(51, 16);

                        lut_index <= index_mult(8 downto 3);
                    end if;

                when LOOKUP =>

                    recip_estimate <= RECIP_LUT(to_integer(lut_index));

                when ITER1_MULT =>

                    mult_result_48 := freq_integer * recip_estimate;
                    nr_product <= mult_result_48;

                when ITER1_SUB =>

                    sub_result := signed('0' & TWO_Q2_30) - signed('0' & nr_product(31 downto 0));
                    nr_diff <= sub_result;

                when ITER1_SCALE =>

                    if nr_diff(32) = '0' then
                        scale_result := recip_estimate * unsigned(nr_diff(31 downto 0));
                        recip_estimate <= scale_result(61 downto 30);
                    end if;

                when ITER2_MULT =>
                    mult_result_48 := freq_integer * recip_estimate;
                    nr_product <= mult_result_48;

                when ITER2_SUB =>
                    sub_result := signed('0' & TWO_Q2_30) - signed('0' & nr_product(31 downto 0));
                    nr_diff <= sub_result;

                when ITER2_SCALE =>
                    if nr_diff(32) = '0' then
                        scale_result := recip_estimate * unsigned(nr_diff(31 downto 0));
                        recip_estimate <= scale_result(61 downto 30);
                    end if;

                when ITER3_MULT =>
                    mult_result_48 := freq_integer * recip_estimate;
                    nr_product <= mult_result_48;

                when ITER3_SUB =>
                    sub_result := signed('0' & TWO_Q2_30) - signed('0' & nr_product(31 downto 0));
                    nr_diff <= sub_result;

                when ITER3_SCALE =>
                    if nr_diff(32) = '0' then
                        scale_result := recip_estimate * unsigned(nr_diff(31 downto 0));
                        recip_estimate <= scale_result(61 downto 30);
                    end if;

                when FINAL_MULT =>

                    final_mult_var := to_unsigned(SAMPLE_RATE, 32) * recip_estimate;
                    final_product <= final_mult_var;

                    result_reg <= final_mult_var(45 downto 14);

                when OUTPUT_RESULT =>
                    valid_pipe <= '1';

                when others =>
                    null;

            end case;
        end if;
    end process;

    samples_per_cycle <= std_logic_vector(result_reg);
    output_valid <= valid_pipe;
    frequency_out_of_range <= out_of_range_reg;

    busy_proc: process(current_state)
    begin
        if current_state = IDLE then
            busy <= '0';
        else
            busy <= '1';
        end if;
    end process;

end behavioral;
