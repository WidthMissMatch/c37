library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity crc_ccitt_c37118 is
    generic (
        CRC_WIDTH       : integer := 16;
        DATA_WIDTH      : integer := 8
    );
    port (

        clk             : in  std_logic;
        rst             : in  std_logic;

        start           : in  std_logic;
        clear           : in  std_logic;

        data_in         : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        data_valid      : in  std_logic;
        data_last       : in  std_logic;

        crc_out         : out std_logic_vector(CRC_WIDTH-1 downto 0);
        crc_valid       : out std_logic;

        busy            : out std_logic;
        byte_count      : out std_logic_vector(15 downto 0)
    );
end crc_ccitt_c37118;

architecture behavioral of crc_ccitt_c37118 is

    constant CRC_POLY       : std_logic_vector(CRC_WIDTH-1 downto 0) := x"1021";

    constant CRC_INIT       : std_logic_vector(CRC_WIDTH-1 downto 0) := x"FFFF";

    type state_type is (IDLE, PROCESSING, CRC_READY);
    signal current_state    : state_type;
    signal next_state       : state_type;

    signal crc_reg          : std_logic_vector(CRC_WIDTH-1 downto 0);
    signal crc_next         : std_logic_vector(CRC_WIDTH-1 downto 0);

    signal byte_count_reg   : unsigned(15 downto 0);

    signal crc_valid_reg    : std_logic;
    signal busy_reg         : std_logic;

    signal shift_enable     : std_logic;

begin

    state_sync: process(clk, rst)
    begin
        if rst = '1' then
            current_state <= IDLE;
        elsif rising_edge(clk) then
            if current_state /= next_state then
                report "CRC: State transition " & state_type'image(current_state) &
                       " -> " & state_type'image(next_state);
            end if;
            current_state <= next_state;
        end if;
    end process;

    state_comb: process(current_state, start, data_valid, data_last)
    begin
        next_state <= current_state;

        case current_state is
            when IDLE =>
                if start = '1' or data_valid = '1' then
                    next_state <= PROCESSING;
                end if;

            when PROCESSING =>
                if data_valid = '1' and data_last = '1' then
                    next_state <= CRC_READY;
                end if;

            when CRC_READY =>
                next_state <= IDLE;

            when others =>
                next_state <= IDLE;
        end case;
    end process;

    crc_calc: process(clk, rst)
        variable bit_idx        : integer range 0 to 7;
        variable crc_temp       : std_logic_vector(CRC_WIDTH-1 downto 0);
        variable data_byte      : std_logic_vector(DATA_WIDTH-1 downto 0);
        variable xor_flag       : std_logic;
    begin
        if rst = '1' then
            crc_reg <= CRC_INIT;
            byte_count_reg <= (others => '0');
            crc_valid_reg <= '0';
            busy_reg <= '0';

        elsif rising_edge(clk) then

            crc_valid_reg <= '0';

            case current_state is
                when IDLE =>
                    busy_reg <= '0';

                    if start = '1' or clear = '1' then
                        report "CRC: IDLE state - Resetting! start=" & std_logic'image(start) &
                               ", clear=" & std_logic'image(clear);
                        crc_reg <= CRC_INIT;
                        byte_count_reg <= (others => '0');
                    end if;

                when PROCESSING =>
                    busy_reg <= '1';

                    if data_valid = '1' then
                        report "CRC: Processing byte #" & integer'image(to_integer(byte_count_reg)) &
                               " = " & integer'image(to_integer(unsigned(data_in))) &
                               ", crc_reg before = " & integer'image(to_integer(unsigned(crc_reg)));

                        data_byte := data_in;
                        crc_temp := crc_reg;

                        crc_temp(15 downto 8) := crc_temp(15 downto 8) xor data_byte;

                        for bit_idx in 7 downto 0 loop
                            xor_flag := crc_temp(15);

                            crc_temp := crc_temp(14 downto 0) & '0';

                            if xor_flag = '1' then
                                crc_temp := crc_temp xor CRC_POLY;
                            end if;
                        end loop;

                        crc_reg <= crc_temp;
                        byte_count_reg <= byte_count_reg + 1;
                        if to_integer(byte_count_reg) >= 30 and to_integer(byte_count_reg) <= 40 then
                            report "CRC: After processing, crc_temp (new value) = " &
                                   integer'image(to_integer(unsigned(crc_temp)));
                        end if;
                    end if;

                when CRC_READY =>
                    crc_valid_reg <= '1';
                    busy_reg <= '0';

                when others =>
                    null;

            end case;
        end if;
    end process;

    crc_out <= crc_reg;
    crc_valid <= crc_valid_reg;
    busy <= busy_reg;
    byte_count <= std_logic_vector(byte_count_reg);

end behavioral;
