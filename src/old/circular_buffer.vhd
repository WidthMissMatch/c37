library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity circular_buffer_controller is
    generic (
        BUFFER_DEPTH      : integer := 512;
        BUFFER_ADDR_WIDTH : integer := 9;
        SAMPLE_WIDTH      : integer := 16
    );
    port (

        clk             : in  std_logic;
        rst             : in  std_logic;

        sample_in       : in  std_logic_vector(SAMPLE_WIDTH-1 downto 0);
        sample_valid    : in  std_logic;

        read_addr       : in  std_logic_vector(BUFFER_ADDR_WIDTH-1 downto 0);
        read_enable     : in  std_logic;
        read_data       : out std_logic_vector(SAMPLE_WIDTH-1 downto 0);
        read_valid      : out std_logic;

        write_addr_out  : out std_logic_vector(BUFFER_ADDR_WIDTH-1 downto 0);
        sample_count    : out std_logic_vector(31 downto 0);

        buffer_oldest   : out std_logic_vector(31 downto 0)
    );
end circular_buffer_controller;

architecture behavioral of circular_buffer_controller is

    type memory_array is array (0 to BUFFER_DEPTH-1) of
        std_logic_vector(SAMPLE_WIDTH-1 downto 0);
    signal sample_memory : memory_array := (others => (others => '0'));

    signal write_ptr : unsigned(BUFFER_ADDR_WIDTH-1 downto 0) := (others => '0');

    signal abs_sample_count : unsigned(31 downto 0) := (others => '0');

    signal read_data_reg   : std_logic_vector(SAMPLE_WIDTH-1 downto 0);
    signal read_valid_reg  : std_logic;

    signal buffer_filled : std_logic := '0';

    signal oldest_sample_pos : unsigned(31 downto 0);

begin

    write_process: process(clk, rst)
        variable first_write_seen : boolean := false;
    begin
        if rst = '1' then
            write_ptr <= (others => '0');
            abs_sample_count <= (others => '0');
            buffer_filled <= '0';
            first_write_seen := false;
        elsif rising_edge(clk) then
            if sample_valid = '1' then

                if not first_write_seen then
                    report "[CIRC_BUF] First sample written to circular buffer" severity note;
                    first_write_seen := true;
                end if;

                sample_memory(to_integer(write_ptr)) <= sample_in;

                if abs_sample_count = 99 or abs_sample_count = 299 or abs_sample_count = 511 then
                    report "[CIRC_BUF] Sample count = " & integer'image(to_integer(abs_sample_count) + 1) &
                           ", write_ptr = " & integer'image(to_integer(write_ptr) + 1) severity note;
                end if;

                if write_ptr = BUFFER_DEPTH - 1 then
                    write_ptr <= (others => '0');
                    buffer_filled <= '1';
                    report "[CIRC_BUF] Buffer wrapped around at " & integer'image(BUFFER_DEPTH) & " samples" severity note;
                else
                    write_ptr <= write_ptr + 1;
                end if;

                abs_sample_count <= abs_sample_count + 1;
            end if;
        end if;
    end process;

    read_process: process(clk, rst)
    begin
        if rst = '1' then
            read_data_reg <= (others => '0');
            read_valid_reg <= '0';
        elsif rising_edge(clk) then

            read_valid_reg <= read_enable;

            if read_enable = '1' then
                read_data_reg <= sample_memory(to_integer(unsigned(read_addr)));
            end if;
        end if;
    end process;

    oldest_calc_process: process(clk, rst)
    begin
        if rst = '1' then
            oldest_sample_pos <= (others => '0');
        elsif rising_edge(clk) then
            if buffer_filled = '1' then

                oldest_sample_pos <= abs_sample_count - to_unsigned(BUFFER_DEPTH, 32);
            else

                oldest_sample_pos <= (others => '0');
            end if;
        end if;
    end process;

    read_data <= read_data_reg;
    read_valid <= read_valid_reg;
    write_addr_out <= std_logic_vector(write_ptr);
    sample_count <= std_logic_vector(abs_sample_count);
    buffer_oldest <= std_logic_vector(oldest_sample_pos);

end behavioral;
