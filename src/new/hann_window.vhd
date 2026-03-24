library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity hann_window is
    generic (
        WINDOW_SIZE  : integer := 256;
        SAMPLE_WIDTH : integer := 16;
        COEFF_WIDTH  : integer := 16
    );
    port (
        clk             : in  std_logic;
        rst             : in  std_logic;

        sample_in       : in  std_logic_vector(SAMPLE_WIDTH-1 downto 0);
        sample_index    : in  std_logic_vector(7 downto 0);
        sample_valid    : in  std_logic;

        sample_out      : out std_logic_vector(SAMPLE_WIDTH-1 downto 0);
        sample_out_valid: out std_logic;

        index_out       : out std_logic_vector(7 downto 0);

        coeff_out       : out std_logic_vector(COEFF_WIDTH-1 downto 0)
    );
end hann_window;

architecture behavioral of hann_window is

    type rom_type is array (0 to WINDOW_SIZE-1) of signed(COEFF_WIDTH-1 downto 0);

    constant HANN_ROM : rom_type := (

        to_signed(    0, 16), to_signed(    5, 16), to_signed(   20, 16), to_signed(   44, 16),
        to_signed(   79, 16), to_signed(  123, 16), to_signed(  177, 16), to_signed(  241, 16),
        to_signed(  315, 16), to_signed(  398, 16), to_signed(  491, 16), to_signed(  593, 16),
        to_signed(  705, 16), to_signed(  827, 16), to_signed(  958, 16), to_signed( 1098, 16),

        to_signed( 1247, 16), to_signed( 1406, 16), to_signed( 1573, 16), to_signed( 1749, 16),
        to_signed( 1935, 16), to_signed( 2128, 16), to_signed( 2331, 16), to_signed( 2542, 16),
        to_signed( 2761, 16), to_signed( 2989, 16), to_signed( 3224, 16), to_signed( 3468, 16),
        to_signed( 3719, 16), to_signed( 3978, 16), to_signed( 4244, 16), to_signed( 4518, 16),

        to_signed( 4799, 16), to_signed( 5087, 16), to_signed( 5381, 16), to_signed( 5682, 16),
        to_signed( 5990, 16), to_signed( 6304, 16), to_signed( 6624, 16), to_signed( 6950, 16),
        to_signed( 7282, 16), to_signed( 7619, 16), to_signed( 7961, 16), to_signed( 8308, 16),
        to_signed( 8661, 16), to_signed( 9018, 16), to_signed( 9379, 16), to_signed( 9745, 16),

        to_signed(10114, 16), to_signed(10487, 16), to_signed(10864, 16), to_signed(11245, 16),
        to_signed(11628, 16), to_signed(12014, 16), to_signed(12403, 16), to_signed(12794, 16),
        to_signed(13188, 16), to_signed(13583, 16), to_signed(13980, 16), to_signed(14378, 16),
        to_signed(14778, 16), to_signed(15179, 16), to_signed(15580, 16), to_signed(15982, 16),

        to_signed(16384, 16), to_signed(16786, 16), to_signed(17188, 16), to_signed(17589, 16),
        to_signed(17990, 16), to_signed(18390, 16), to_signed(18788, 16), to_signed(19185, 16),
        to_signed(19580, 16), to_signed(19974, 16), to_signed(20365, 16), to_signed(20754, 16),
        to_signed(21140, 16), to_signed(21523, 16), to_signed(21904, 16), to_signed(22281, 16),

        to_signed(22654, 16), to_signed(23023, 16), to_signed(23389, 16), to_signed(23750, 16),
        to_signed(24107, 16), to_signed(24460, 16), to_signed(24807, 16), to_signed(25149, 16),
        to_signed(25486, 16), to_signed(25818, 16), to_signed(26144, 16), to_signed(26464, 16),
        to_signed(26778, 16), to_signed(27086, 16), to_signed(27387, 16), to_signed(27681, 16),

        to_signed(27969, 16), to_signed(28250, 16), to_signed(28524, 16), to_signed(28790, 16),
        to_signed(29049, 16), to_signed(29300, 16), to_signed(29544, 16), to_signed(29779, 16),
        to_signed(30007, 16), to_signed(30226, 16), to_signed(30437, 16), to_signed(30640, 16),
        to_signed(30833, 16), to_signed(31019, 16), to_signed(31195, 16), to_signed(31362, 16),

        to_signed(31521, 16), to_signed(31670, 16), to_signed(31810, 16), to_signed(31941, 16),
        to_signed(32063, 16), to_signed(32175, 16), to_signed(32277, 16), to_signed(32370, 16),
        to_signed(32453, 16), to_signed(32527, 16), to_signed(32591, 16), to_signed(32645, 16),
        to_signed(32689, 16), to_signed(32724, 16), to_signed(32748, 16), to_signed(32763, 16),

        to_signed(32767, 16), to_signed(32763, 16), to_signed(32748, 16), to_signed(32724, 16),
        to_signed(32689, 16), to_signed(32645, 16), to_signed(32591, 16), to_signed(32527, 16),
        to_signed(32453, 16), to_signed(32370, 16), to_signed(32277, 16), to_signed(32175, 16),
        to_signed(32063, 16), to_signed(31941, 16), to_signed(31810, 16), to_signed(31670, 16),

        to_signed(31521, 16), to_signed(31362, 16), to_signed(31195, 16), to_signed(31019, 16),
        to_signed(30833, 16), to_signed(30640, 16), to_signed(30437, 16), to_signed(30226, 16),
        to_signed(30007, 16), to_signed(29779, 16), to_signed(29544, 16), to_signed(29300, 16),
        to_signed(29049, 16), to_signed(28790, 16), to_signed(28524, 16), to_signed(28250, 16),

        to_signed(27969, 16), to_signed(27681, 16), to_signed(27387, 16), to_signed(27086, 16),
        to_signed(26778, 16), to_signed(26464, 16), to_signed(26144, 16), to_signed(25818, 16),
        to_signed(25486, 16), to_signed(25149, 16), to_signed(24807, 16), to_signed(24460, 16),
        to_signed(24107, 16), to_signed(23750, 16), to_signed(23389, 16), to_signed(23023, 16),

        to_signed(22654, 16), to_signed(22281, 16), to_signed(21904, 16), to_signed(21523, 16),
        to_signed(21140, 16), to_signed(20754, 16), to_signed(20365, 16), to_signed(19974, 16),
        to_signed(19580, 16), to_signed(19185, 16), to_signed(18788, 16), to_signed(18390, 16),
        to_signed(17990, 16), to_signed(17589, 16), to_signed(17188, 16), to_signed(16786, 16),

        to_signed(16384, 16), to_signed(15982, 16), to_signed(15580, 16), to_signed(15179, 16),
        to_signed(14778, 16), to_signed(14378, 16), to_signed(13980, 16), to_signed(13583, 16),
        to_signed(13188, 16), to_signed(12794, 16), to_signed(12403, 16), to_signed(12014, 16),
        to_signed(11628, 16), to_signed(11245, 16), to_signed(10864, 16), to_signed(10487, 16),

        to_signed(10114, 16), to_signed( 9745, 16), to_signed( 9379, 16), to_signed( 9018, 16),
        to_signed( 8661, 16), to_signed( 8308, 16), to_signed( 7961, 16), to_signed( 7619, 16),
        to_signed( 7282, 16), to_signed( 6950, 16), to_signed( 6624, 16), to_signed( 6304, 16),
        to_signed( 5990, 16), to_signed( 5682, 16), to_signed( 5381, 16), to_signed( 5087, 16),

        to_signed( 4799, 16), to_signed( 4518, 16), to_signed( 4244, 16), to_signed( 3978, 16),
        to_signed( 3719, 16), to_signed( 3468, 16), to_signed( 3224, 16), to_signed( 2989, 16),
        to_signed( 2761, 16), to_signed( 2542, 16), to_signed( 2331, 16), to_signed( 2128, 16),
        to_signed( 1935, 16), to_signed( 1749, 16), to_signed( 1573, 16), to_signed( 1406, 16),

        to_signed( 1247, 16), to_signed( 1098, 16), to_signed(  958, 16), to_signed(  827, 16),
        to_signed(  705, 16), to_signed(  593, 16), to_signed(  491, 16), to_signed(  398, 16),
        to_signed(  315, 16), to_signed(  241, 16), to_signed(  177, 16), to_signed(  123, 16),
        to_signed(   79, 16), to_signed(   44, 16), to_signed(   20, 16), to_signed(    5, 16)
    );

    signal coeff_reg     : signed(COEFF_WIDTH-1 downto 0) := (others => '0');
    signal sample_reg    : signed(SAMPLE_WIDTH-1 downto 0) := (others => '0');
    signal product       : signed(SAMPLE_WIDTH + COEFF_WIDTH - 1 downto 0) := (others => '0');
    signal valid_pipe    : std_logic_vector(1 downto 0) := "00";
    signal index_pipe_0  : std_logic_vector(7 downto 0) := (others => '0');
    signal index_pipe_1  : std_logic_vector(7 downto 0) := (others => '0');

begin

    pipeline: process(clk, rst)
        variable addr : integer range 0 to WINDOW_SIZE-1;
    begin
        if rst = '1' then
            coeff_reg    <= (others => '0');
            sample_reg   <= (others => '0');
            product      <= (others => '0');
            valid_pipe   <= "00";
            index_pipe_0 <= (others => '0');
            index_pipe_1 <= (others => '0');
        elsif rising_edge(clk) then

            if sample_valid = '1' then
                addr := to_integer(unsigned(sample_index));
                coeff_reg  <= HANN_ROM(addr);
                sample_reg <= signed(sample_in);
            end if;
            valid_pipe(0) <= sample_valid;
            index_pipe_0  <= sample_index;

            product       <= sample_reg * coeff_reg;
            valid_pipe(1) <= valid_pipe(0);
            index_pipe_1  <= index_pipe_0;
        end if;
    end process;

    sample_out       <= std_logic_vector(resize(shift_right(product, 15), SAMPLE_WIDTH));
    sample_out_valid <= valid_pipe(1);
    index_out        <= index_pipe_1;

    coeff_out <= std_logic_vector(coeff_reg);

end behavioral;
