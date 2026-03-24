library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity channel_extractor is
    port (

        clk                 : in  std_logic;
        rst                 : in  std_logic;

        packet_in           : in  std_logic_vector(127 downto 0);
        packet_valid        : in  std_logic;

        ch0_data            : out std_logic_vector(15 downto 0);
        ch0_valid           : out std_logic;

        ch1_data            : out std_logic_vector(15 downto 0);
        ch1_valid           : out std_logic;

        ch2_data            : out std_logic_vector(15 downto 0);
        ch2_valid           : out std_logic;

        ch3_data            : out std_logic_vector(15 downto 0);
        ch3_valid           : out std_logic;

        ch4_data            : out std_logic_vector(15 downto 0);
        ch4_valid           : out std_logic;

        ch5_data            : out std_logic_vector(15 downto 0);
        ch5_valid           : out std_logic;

        channels_extracted  : out std_logic_vector(31 downto 0)
    );
end channel_extractor;

architecture rtl of channel_extractor is

    signal packet_reg : std_logic_vector(127 downto 0);

    signal extract_count : unsigned(31 downto 0);

begin

    extract_process: process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then

                ch0_data <= (others => '0');
                ch1_data <= (others => '0');
                ch2_data <= (others => '0');
                ch3_data <= (others => '0');
                ch4_data <= (others => '0');
                ch5_data <= (others => '0');

                ch0_valid <= '0';
                ch1_valid <= '0';
                ch2_valid <= '0';
                ch3_valid <= '0';
                ch4_valid <= '0';
                ch5_valid <= '0';

                packet_reg <= (others => '0');
                extract_count <= (others => '0');

            else

                ch0_valid <= '0';
                ch1_valid <= '0';
                ch2_valid <= '0';
                ch3_valid <= '0';
                ch4_valid <= '0';
                ch5_valid <= '0';

                if packet_valid = '1' then

                    if extract_count = 0 then
                        report "[CH_EXTRACT] First 128-bit packet received and extracting 6 channels" severity note;
                    elsif extract_count = 49 or extract_count = 99 or extract_count = 299 then
                        report "[CH_EXTRACT] Extracted " & integer'image(to_integer(extract_count) + 1) & " packets into channels" severity note;
                    end if;

                    packet_reg <= packet_in;

                    ch0_data <= packet_in(119 downto 112) & packet_in(111 downto 104);

                    ch1_data <= packet_in(103 downto 96) & packet_in(95 downto 88);

                    ch2_data <= packet_in(87 downto 80) & packet_in(79 downto 72);

                    ch3_data <= packet_in(71 downto 64) & packet_in(63 downto 56);

                    ch4_data <= packet_in(55 downto 48) & packet_in(47 downto 40);

                    ch5_data <= packet_in(39 downto 32) & packet_in(31 downto 24);

                    ch0_valid <= '1';
                    ch1_valid <= '1';
                    ch2_valid <= '1';
                    ch3_valid <= '1';
                    ch4_valid <= '1';
                    ch5_valid <= '1';

                    extract_count <= extract_count + 1;

                end if;

            end if;
        end if;
    end process;

    channels_extracted <= std_logic_vector(extract_count);

end rtl;
