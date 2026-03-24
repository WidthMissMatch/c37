library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity dft_sample_buffer is
    generic (
        BUFFER_SIZE   : integer := 256;
        SAMPLE_WIDTH  : integer := 16
    );
    port (
        clk             : in  std_logic;
        rst             : in  std_logic;

        write_sample    : in  std_logic_vector(SAMPLE_WIDTH-1 downto 0);
        write_index     : in  std_logic_vector(7 downto 0);
        write_valid     : in  std_logic;
        write_last      : in  std_logic;

        read_addr       : in  std_logic_vector(7 downto 0);
        read_data       : out std_logic_vector(SAMPLE_WIDTH-1 downto 0);

        buffer_full     : out std_logic;
        sample_count    : out std_logic_vector(8 downto 0)
    );
end dft_sample_buffer;

architecture behavioral of dft_sample_buffer is

    type ram_type is array (0 to BUFFER_SIZE-1) of std_logic_vector(SAMPLE_WIDTH-1 downto 0);
    signal sample_ram : ram_type := (others => (others => '0'));

    signal write_addr_int : integer range 0 to BUFFER_SIZE-1;
    signal read_addr_int  : integer range 0 to BUFFER_SIZE-1;
    signal count_reg      : unsigned(8 downto 0) := (others => '0');
    signal full_pulse     : std_logic := '0';

    signal read_data_reg  : std_logic_vector(SAMPLE_WIDTH-1 downto 0) := (others => '0');

begin

    write_addr_int <= to_integer(unsigned(write_index));
    read_addr_int <= to_integer(unsigned(read_addr));

    write_process: process(clk, rst)
        variable first_sample_seen : boolean := false;
        variable first_full_seen : boolean := false;
    begin
        if rst = '1' then
            count_reg <= (others => '0');
            full_pulse <= '0';
            first_sample_seen := false;
            first_full_seen := false;
        elsif rising_edge(clk) then
            full_pulse <= '0';

            if write_valid = '1' then

                if not first_sample_seen then
                    report "[DFT_BUF] First sample received in DFT buffer!" severity note;
                    first_sample_seen := true;
                end if;

                sample_ram(write_addr_int) <= write_sample;

                if write_last = '1' then
                    count_reg <= to_unsigned(256, 9);
                    full_pulse <= '1';

                    if not first_full_seen then
                        report "[DFT_BUF] Buffer FULL - all 256 samples received!" severity note;
                        first_full_seen := true;
                    end if;
                else
                    if count_reg < 256 then
                        count_reg <= count_reg + 1;

                        if to_integer(count_reg) = 50 or to_integer(count_reg) = 100 or
                           to_integer(count_reg) = 150 or to_integer(count_reg) = 200 then
                            report "[DFT_BUF] Sample count = " & integer'image(to_integer(count_reg) + 1) severity note;
                        end if;
                    end if;
                end if;
            end if;
        end if;
    end process;

    read_process: process(clk)
    begin
        if rising_edge(clk) then
            read_data_reg <= sample_ram(read_addr_int);
        end if;
    end process;

    read_data    <= read_data_reg;
    buffer_full  <= full_pulse;
    sample_count <= std_logic_vector(count_reg);

end behavioral;
