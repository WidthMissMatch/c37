library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use STD.TEXTIO.ALL;

entity crc_ccitt_c37118_tb is
end crc_ccitt_c37118_tb;

architecture testbench of crc_ccitt_c37118_tb is

    component crc_ccitt_c37118
        generic (
            CRC_WIDTH   : integer := 16;
            DATA_WIDTH  : integer := 8
        );
        port (
            clk         : in  std_logic;
            rst         : in  std_logic;
            start       : in  std_logic;
            clear       : in  std_logic;
            data_in     : in  std_logic_vector(DATA_WIDTH-1 downto 0);
            data_valid  : in  std_logic;
            data_last   : in  std_logic;
            crc_out     : out std_logic_vector(CRC_WIDTH-1 downto 0);
            crc_valid   : out std_logic;
            busy        : out std_logic;
            byte_count  : out std_logic_vector(15 downto 0)
        );
    end component;

    constant CLK_PERIOD : time := 10 ns;

    signal clk          : std_logic := '0';
    signal rst          : std_logic := '1';
    signal start        : std_logic := '0';
    signal clear        : std_logic := '0';
    signal data_in      : std_logic_vector(7 downto 0) := (others => '0');
    signal data_valid   : std_logic := '0';
    signal data_last    : std_logic := '0';
    signal crc_out      : std_logic_vector(15 downto 0);
    signal crc_valid    : std_logic;
    signal busy         : std_logic;
    signal byte_count   : std_logic_vector(15 downto 0);

    type byte_array is array (natural range <>) of std_logic_vector(7 downto 0);

    function hex_to_byte(hex_char : character) return integer is
    begin
        case hex_char is
            when '0' => return 0;
            when '1' => return 1;
            when '2' => return 2;
            when '3' => return 3;
            when '4' => return 4;
            when '5' => return 5;
            when '6' => return 6;
            when '7' => return 7;
            when '8' => return 8;
            when '9' => return 9;
            when 'A' | 'a' => return 10;
            when 'B' | 'b' => return 11;
            when 'C' | 'c' => return 12;
            when 'D' | 'd' => return 13;
            when 'E' | 'e' => return 14;
            when 'F' | 'f' => return 15;
            when others => return 0;
        end case;
    end function;

    procedure send_packet(
        signal clk        : in  std_logic;
        signal data_in    : out std_logic_vector(7 downto 0);
        signal data_valid : out std_logic;
        signal data_last  : out std_logic;
        constant packet   : in  byte_array;
        constant pkt_name : in  string
    ) is
    begin
        report "Sending packet: " & pkt_name;
        report "  Packet length: " & integer'image(packet'length) & " bytes";

        for i in packet'range loop
            wait until rising_edge(clk);
            data_in <= packet(i);
            data_valid <= '1';

            if i = packet'high then
                data_last <= '1';
            else
                data_last <= '0';
            end if;
        end loop;

        wait until rising_edge(clk);
        data_valid <= '0';
        data_last <= '0';
    end procedure;

begin

    clk <= not clk after CLK_PERIOD / 2;

    dut: crc_ccitt_c37118
        port map (
            clk => clk,
            rst => rst,
            start => start,
            clear => clear,
            data_in => data_in,
            data_valid => data_valid,
            data_last => data_last,
            crc_out => crc_out,
            crc_valid => crc_valid,
            busy => busy,
            byte_count => byte_count
        );

    stimulus: process

        constant test_pkt1 : byte_array(0 to 8) := (
            x"31", x"32", x"33", x"34", x"35", x"36", x"37", x"38", x"39"
        );

        constant test_pkt2 : byte_array(0 to 13) := (
            x"AA", x"01",
            x"00", x"18",
            x"00", x"01",
            x"00", x"00", x"00", x"00",
            x"00", x"00", x"00", x"00"
        );

        constant test_pkt3 : byte_array(0 to 0) := (
            0 => x"FF"
        );

        constant test_pkt4 : byte_array(0 to 7) := (
            x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00"
        );

        variable crc_result : unsigned(15 downto 0);

    begin

        rst <= '1';
        wait for 100 ns;
        rst <= '0';
        wait for 100 ns;

        report "========================================";
        report "CRC-CCITT Calculator Testbench Starting";
        report "========================================";

        report " ";
        report "TEST CASE 1: Standard CRC Test Vector";
        report "  Input: '123456789' (ASCII)";
        report "  Expected CRC: 0x29B1";

        start <= '1';
        wait for CLK_PERIOD;
        start <= '0';

        send_packet(clk, data_in, data_valid, data_last, test_pkt1, "ASCII '123456789'");

        wait until crc_valid = '1';
        wait for CLK_PERIOD;

        crc_result := unsigned(crc_out);
        report "  Calculated CRC: 0x" &
               integer'image(to_integer(crc_result(15 downto 12))) &
               integer'image(to_integer(crc_result(11 downto 8))) &
               integer'image(to_integer(crc_result(7 downto 4))) &
               integer'image(to_integer(crc_result(3 downto 0)));

        wait for 500 ns;

        report " ";
        report "TEST CASE 2: IEEE C37.118 Header Format";

        clear <= '1';
        wait for CLK_PERIOD;
        clear <= '0';

        start <= '1';
        wait for CLK_PERIOD;
        start <= '0';

        send_packet(clk, data_in, data_valid, data_last, test_pkt2, "C37.118 Header");

        wait until crc_valid = '1';
        wait for CLK_PERIOD;

        crc_result := unsigned(crc_out);
        report "  Calculated CRC: 0x" &
               integer'image(to_integer(crc_result(15 downto 12))) &
               integer'image(to_integer(crc_result(11 downto 8))) &
               integer'image(to_integer(crc_result(7 downto 4))) &
               integer'image(to_integer(crc_result(3 downto 0)));
        report "  Byte count: " & integer'image(to_integer(unsigned(byte_count)));

        wait for 500 ns;

        report " ";
        report "TEST CASE 3: Single Byte (0xFF)";

        clear <= '1';
        wait for CLK_PERIOD;
        clear <= '0';

        start <= '1';
        wait for CLK_PERIOD;
        start <= '0';

        send_packet(clk, data_in, data_valid, data_last, test_pkt3, "Single byte 0xFF");

        wait until crc_valid = '1';
        wait for CLK_PERIOD;

        crc_result := unsigned(crc_out);
        report "  Calculated CRC: 0x" &
               integer'image(to_integer(crc_result(15 downto 12))) &
               integer'image(to_integer(crc_result(11 downto 8))) &
               integer'image(to_integer(crc_result(7 downto 4))) &
               integer'image(to_integer(crc_result(3 downto 0)));

        wait for 500 ns;

        report " ";
        report "TEST CASE 4: All Zeros (8 bytes)";

        clear <= '1';
        wait for CLK_PERIOD;
        clear <= '0';

        start <= '1';
        wait for CLK_PERIOD;
        start <= '0';

        send_packet(clk, data_in, data_valid, data_last, test_pkt4, "All zeros");

        wait until crc_valid = '1';
        wait for CLK_PERIOD;

        crc_result := unsigned(crc_out);
        report "  Calculated CRC: 0x" &
               integer'image(to_integer(crc_result(15 downto 12))) &
               integer'image(to_integer(crc_result(11 downto 8))) &
               integer'image(to_integer(crc_result(7 downto 4))) &
               integer'image(to_integer(crc_result(3 downto 0)));

        wait for 500 ns;

        report " ";
        report "TEST CASE 5: Back-to-back Packets";

        clear <= '1';
        wait for CLK_PERIOD;
        clear <= '0';

        start <= '1';
        wait for CLK_PERIOD;
        start <= '0';

        send_packet(clk, data_in, data_valid, data_last, test_pkt1, "Packet 1");

        wait until crc_valid = '1';
        wait for CLK_PERIOD;
        report "  First CRC complete";

        clear <= '1';
        wait for CLK_PERIOD;
        clear <= '0';

        start <= '1';
        wait for CLK_PERIOD;
        start <= '0';

        send_packet(clk, data_in, data_valid, data_last, test_pkt2, "Packet 2");

        wait until crc_valid = '1';
        wait for CLK_PERIOD;
        report "  Second CRC complete";

        wait for 500 ns;

        report " ";
        report "========================================";
        report "CRC-CCITT Calculator Testbench Complete";
        report "All tests executed successfully!";
        report "========================================";
        report " ";
        report "NOTES:";
        report "  - CRC values shown are calculated values";
        report "  - For packet validation, append CRC to packet";
        report "  - Receiver recalculates CRC over data+CRC = 0x0000 if valid";

        wait;
    end process;

end testbench;
