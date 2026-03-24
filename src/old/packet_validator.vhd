library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity packet_validator is
    port (
        clk                 : in  std_logic;
        rst                 : in  std_logic;

        packet_in           : in  std_logic_vector(127 downto 0);
        packet_valid_in     : in  std_logic;

        packet_out          : out std_logic_vector(127 downto 0);
        packet_valid_out    : out std_logic;

        sync_locked         : out std_logic;
        good_count          : out std_logic_vector(31 downto 0);
        bad_count           : out std_logic_vector(31 downto 0)
    );
end packet_validator;

architecture rtl of packet_validator is

    signal packet_reg : std_logic_vector(127 downto 0);

    signal sync_ok    : std_logic;
    signal check_ok   : std_logic;
    signal packet_ok  : std_logic;

    signal good_cnt       : unsigned(31 downto 0);
    signal bad_cnt        : unsigned(31 downto 0);
    signal consec_good    : unsigned(3 downto 0);
    signal consec_bad     : unsigned(3 downto 0);
    signal sync_lock      : std_logic;

    constant SYNC_BYTE  : std_logic_vector(7 downto 0) := x"AA";
    constant CHECK_BYTE : std_logic_vector(7 downto 0) := x"55";

begin

    sync_ok   <= '1' when packet_reg(127 downto 120) = SYNC_BYTE  else '0';
    check_ok  <= '1' when packet_reg(23 downto 16) = CHECK_BYTE   else '0';
    packet_ok <= '1' when (sync_ok = '1' and check_ok = '1')      else '0';

    main_process: process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                packet_reg <= (others => '0');
                packet_out <= (others => '0');
                packet_valid_out <= '0';

                good_cnt <= (others => '0');
                bad_cnt <= (others => '0');
                consec_good <= (others => '0');
                consec_bad <= (others => '0');
                sync_lock <= '0';

            else

                packet_valid_out <= '0';

                if packet_valid_in = '1' then

                    packet_reg <= packet_in;

                elsif packet_reg /= (127 downto 0 => '0') then

                    if packet_ok = '1' then

                        packet_out <= packet_reg;
                        packet_valid_out <= '1';

                        good_cnt <= good_cnt + 1;
                        consec_bad <= (others => '0');
                        if consec_good < 15 then
                            consec_good <= consec_good + 1;
                        end if;

                        if consec_good >= 2 then
                            sync_lock <= '1';
                        end if;

                    else

                        packet_out <= (others => '0');
                        packet_valid_out <= '0';

                        bad_cnt <= bad_cnt + 1;
                        consec_good <= (others => '0');
                        if consec_bad < 15 then
                            consec_bad <= consec_bad + 1;
                        end if;

                        if consec_bad >= 1 then
                            sync_lock <= '0';
                        end if;
                    end if;

                    packet_reg <= (others => '0');
                end if;

            end if;
        end if;
    end process;

    sync_locked <= sync_lock;
    good_count <= std_logic_vector(good_cnt);
    bad_count <= std_logic_vector(bad_cnt);

end rtl;
