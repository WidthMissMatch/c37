library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.STD_LOGIC_TEXTIO.ALL;
use STD.TEXTIO.ALL;

entity tb_packet_flow_validation is
end entity tb_packet_flow_validation;

architecture behavioral of tb_packet_flow_validation is

    signal clk : std_logic := '0';
    signal rst : std_logic := '1';
    signal test_complete : std_logic := '0';

    type test_packet_array is array (0 to 7) of std_logic_vector(127 downto 0);
    constant TEST_PACKETS : test_packet_array := (
        x"AA2BF610C5C3402F67F585DB0F550000",
        x"AA2B041209C2EE2F13F68BDA5D550000",
        x"AA29AB19FFBFAE2E67F597D7F0550000",
        x"AA27D3FD37BB662D69F7C0D59A550000",
        x"AA25CB27D8B60E2C2AF91DD373550000",
        x"AA239D04F6B0A72AA2F8C8D111550000",
        x"AA216049C8AA262913F7F6CEDA550000",
        x"AA1F26F3DAA3A52726F5B8CCE4550000"
    );

    constant CLK_PERIOD : time := 10 ns;

    function to_hex_string(val : std_logic_vector) return string is
        variable hex_str : string(1 to (val'length + 3) / 4);
        variable temp : std_logic_vector(3 downto 0);
        variable idx : integer;
    begin
        for i in val'range loop
            idx := (val'high - i) / 4 + 1;
            temp := val(i+3 downto i) when i + 3 <= val'high else
                    (val'high downto i => '0') or val(val'high downto i);
            case temp is
                when x"0" => hex_str(idx) := '0';
                when x"1" => hex_str(idx) := '1';
                when x"2" => hex_str(idx) := '2';
                when x"3" => hex_str(idx) := '3';
                when x"4" => hex_str(idx) := '4';
                when x"5" => hex_str(idx) := '5';
                when x"6" => hex_str(idx) := '6';
                when x"7" => hex_str(idx) := '7';
                when x"8" => hex_str(idx) := '8';
                when x"9" => hex_str(idx) := '9';
                when x"A" => hex_str(idx) := 'A';
                when x"B" => hex_str(idx) := 'B';
                when x"C" => hex_str(idx) := 'C';
                when x"D" => hex_str(idx) := 'D';
                when x"E" => hex_str(idx) := 'E';
                when others => hex_str(idx) := 'F';
            end case;
        end loop;
        return "0x" & hex_str;
    end function;

begin

    clock_process: process
    begin
        while test_complete = '0' loop
            clk <= '0';
            wait for CLK_PERIOD / 2;
            clk <= '1';
            wait for CLK_PERIOD / 2;
        end loop;
        wait;
    end process;

    stimulus_process: process
        variable l : line;
        file out_file : text;
    begin
        report "";
        report "========================================";
        report "C37.118 PMU PACKET VALIDATION TESTBENCH";
        report "========================================";
        report "";

        rst <= '1';
        wait for 100 ns;
        wait until rising_edge(clk);
        rst <= '0';
        wait for 100 ns;

        report "Initialization complete";
        report "System ready for testing";
        report "";

        report "Test Packets:";
        for i in 0 to 7 loop
            report "  Packet " & integer'image(i) & ": " & to_hex_string(TEST_PACKETS(i));
        end loop;
        report "";

        for i in 1 to 100 loop
            wait until rising_edge(clk);
        end loop;

        report "";
        report "========================================";
        report "TEST COMPLETE";
        report "========================================";
        report "";
        report "Next: Check Vivado waveforms for detailed analysis";
        report "";

        test_complete <= '1';
        wait;
    end process;

end architecture behavioral;
