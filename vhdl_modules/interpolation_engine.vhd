library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity interpolation_engine is
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
end interpolation_engine;

architecture behavioral of interpolation_engine is

    signal stage1_valid         : std_logic;
    signal stage1_index         : std_logic_vector(INDEX_WIDTH-1 downto 0);
    signal stage1_last          : std_logic;
    signal stage1_left          : signed(SAMPLE_WIDTH-1 downto 0);
    signal stage1_diff          : signed(SAMPLE_WIDTH downto 0);
    signal stage1_fraction      : unsigned(FRAC_WIDTH-1 downto 0);

    signal stage2_valid         : std_logic;
    signal stage2_index         : std_logic_vector(INDEX_WIDTH-1 downto 0);
    signal stage2_last          : std_logic;
    signal stage2_left          : signed(SAMPLE_WIDTH-1 downto 0);
    signal stage2_product       : signed(SAMPLE_WIDTH + FRAC_WIDTH + 1 downto 0);

    signal diff_extended        : signed(SAMPLE_WIDTH downto 0);
    signal product_full         : signed(SAMPLE_WIDTH + FRAC_WIDTH downto 0);
    signal scaled_product       : signed(SAMPLE_WIDTH downto 0);
    signal raw_result           : signed(SAMPLE_WIDTH downto 0);
    signal saturated_result     : signed(SAMPLE_WIDTH-1 downto 0);

    constant MAX_POSITIVE       : signed(SAMPLE_WIDTH-1 downto 0) := to_signed(32767, SAMPLE_WIDTH);
    constant MAX_NEGATIVE       : signed(SAMPLE_WIDTH-1 downto 0) := to_signed(-32768, SAMPLE_WIDTH);

begin

    stage1_process: process(clk, rst)
        variable left_ext  : signed(SAMPLE_WIDTH downto 0);
        variable right_ext : signed(SAMPLE_WIDTH downto 0);
    begin
        if rst = '1' then
            stage1_valid    <= '0';
            stage1_index    <= (others => '0');
            stage1_last     <= '0';
            stage1_left     <= (others => '0');
            stage1_diff     <= (others => '0');
            stage1_fraction <= (others => '0');
        elsif rising_edge(clk) then
            if input_valid = '1' then

                stage1_valid    <= '1';
                stage1_index    <= index_in;
                stage1_last     <= last_in;

                stage1_left     <= signed(sample_left);

                left_ext  := resize(signed(sample_left), SAMPLE_WIDTH + 1);
                right_ext := resize(signed(sample_right), SAMPLE_WIDTH + 1);
                stage1_diff <= right_ext - left_ext;

                stage1_fraction <= unsigned(fraction);
            else
                stage1_valid <= '0';
            end if;
        end if;
    end process;

    stage2_process: process(clk, rst)
        variable product_temp : signed(SAMPLE_WIDTH + FRAC_WIDTH + 1 downto 0);
        variable scaled_temp  : signed(SAMPLE_WIDTH downto 0);
        variable result_temp  : signed(SAMPLE_WIDTH downto 0);
    begin
        if rst = '1' then
            stage2_valid    <= '0';
            stage2_index    <= (others => '0');
            stage2_last     <= '0';
            stage2_left     <= (others => '0');
            stage2_product  <= (others => '0');
        elsif rising_edge(clk) then
            if stage1_valid = '1' then

                stage2_valid <= '1';
                stage2_index <= stage1_index;
                stage2_last  <= stage1_last;
                stage2_left  <= stage1_left;

                product_temp := stage1_diff * signed('0' & std_logic_vector(stage1_fraction));
                stage2_product <= product_temp;
            else
                stage2_valid <= '0';
            end if;
        end if;
    end process;

    output_process: process(clk, rst)
        variable shifted_product : signed(SAMPLE_WIDTH + FRAC_WIDTH + 1 downto 0);
        variable scaled_temp     : signed(SAMPLE_WIDTH downto 0);
        variable left_extended   : signed(SAMPLE_WIDTH downto 0);
        variable result_temp     : signed(SAMPLE_WIDTH downto 0);
    begin
        if rst = '1' then
            interp_sample <= (others => '0');
            index_out     <= (others => '0');
            last_out      <= '0';
            output_valid  <= '0';
        elsif rising_edge(clk) then
            if stage2_valid = '1' then

                shifted_product := shift_right(stage2_product, FRAC_WIDTH);

                scaled_temp := shifted_product(SAMPLE_WIDTH downto 0);

                left_extended := resize(stage2_left, SAMPLE_WIDTH + 1);
                result_temp := left_extended + scaled_temp;

                if result_temp > to_signed(32767, SAMPLE_WIDTH + 1) then
                    interp_sample <= std_logic_vector(MAX_POSITIVE);
                elsif result_temp < to_signed(-32768, SAMPLE_WIDTH + 1) then
                    interp_sample <= std_logic_vector(MAX_NEGATIVE);
                else
                    interp_sample <= std_logic_vector(result_temp(SAMPLE_WIDTH-1 downto 0));
                end if;

                index_out    <= stage2_index;
                last_out     <= stage2_last;
                output_valid <= '1';
            else
                output_valid <= '0';
            end if;
        end if;
    end process;

end behavioral;
