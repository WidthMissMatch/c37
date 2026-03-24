library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tb_packet_flow_validation is
end entity tb_packet_flow_validation;

architecture behavioral of tb_packet_flow_validation is

    signal clk : std_logic := '0';
    signal rst : std_logic := '1';
    signal test_complete : std_logic := '0';

    constant CLK_PERIOD : time := 10 ns;

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
    begin
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

        for i in 1 to 100 loop
            wait until rising_edge(clk);
        end loop;

        report "";
        report "========================================";
        report "TEST COMPLETE - Simulation finished";
        report "========================================";

        test_complete <= '1';
        wait;
    end process;

end architecture behavioral;
