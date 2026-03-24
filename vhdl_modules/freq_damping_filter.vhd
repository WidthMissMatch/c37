library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity freq_damping_filter is
    generic (
        FREQ_WIDTH : integer := 32;

        ALPHA      : integer := 19661
    );
    port (
        clk           : in  std_logic;
        rst           : in  std_logic;

        freq_in       : in  std_logic_vector(FREQ_WIDTH-1 downto 0);
        freq_valid    : in  std_logic;

        freq_out      : out std_logic_vector(FREQ_WIDTH-1 downto 0);
        freq_out_valid: out std_logic;

        freq_init     : in  std_logic_vector(FREQ_WIDTH-1 downto 0);

        diff_out      : out std_logic_vector(FREQ_WIDTH-1 downto 0);
        initialized   : out std_logic
    );
end freq_damping_filter;

architecture behavioral of freq_damping_filter is

    constant ALPHA_S : signed(16 downto 0) := to_signed(ALPHA, 17);

    signal f_prev       : signed(FREQ_WIDTH-1 downto 0);
    signal init_done    : std_logic := '0';

    signal diff_reg     : signed(FREQ_WIDTH-1 downto 0) := (others => '0');
    signal pipe1_valid  : std_logic := '0';

    signal product      : signed(FREQ_WIDTH + 16 downto 0) := (others => '0');
    signal correction   : signed(FREQ_WIDTH-1 downto 0) := (others => '0');
    signal pipe2_valid  : std_logic := '0';

    signal f_new        : signed(FREQ_WIDTH-1 downto 0) := (others => '0');
    signal pipe3_valid  : std_logic := '0';

begin

    pipeline: process(clk, rst)
        variable sum_ext : signed(FREQ_WIDTH downto 0);
    begin
        if rst = '1' then
            f_prev      <= signed(freq_init);
            init_done   <= '0';
            diff_reg    <= (others => '0');
            product     <= (others => '0');
            correction  <= (others => '0');
            f_new       <= signed(freq_init);
            pipe1_valid <= '0';
            pipe2_valid <= '0';
            pipe3_valid <= '0';
        elsif rising_edge(clk) then

            if freq_valid = '1' then
                if init_done = '0' then

                    f_prev    <= signed(freq_in);
                    diff_reg  <= (others => '0');
                    init_done <= '1';
                    pipe1_valid <= '0';
                else
                    diff_reg <= signed(freq_in) - f_prev;
                    pipe1_valid <= '1';
                end if;
            else
                pipe1_valid <= '0';
            end if;

            if pipe1_valid = '1' then
                product    <= diff_reg * ALPHA_S;

                correction <= resize(shift_right(diff_reg * ALPHA_S + to_signed(32768, FREQ_WIDTH + 17), 16), FREQ_WIDTH);
                pipe2_valid <= '1';
            else
                pipe2_valid <= '0';
            end if;

            if pipe2_valid = '1' then
                sum_ext := resize(f_prev, FREQ_WIDTH+1) + resize(correction, FREQ_WIDTH+1);

                if sum_ext > to_signed(2147483647, FREQ_WIDTH+1) then
                    f_new <= to_signed(2147483647, FREQ_WIDTH);
                elsif sum_ext < to_signed(-2147483648, FREQ_WIDTH+1) then
                    f_new <= to_signed(-2147483648, FREQ_WIDTH);
                else
                    f_new <= sum_ext(FREQ_WIDTH-1 downto 0);
                end if;

                f_prev <= sum_ext(FREQ_WIDTH-1 downto 0);
                pipe3_valid <= '1';
            else
                pipe3_valid <= '0';
            end if;

        end if;
    end process;

    freq_out       <= std_logic_vector(f_new);
    freq_out_valid <= pipe3_valid;
    diff_out       <= std_logic_vector(diff_reg);
    initialized    <= init_done;

end behavioral;
