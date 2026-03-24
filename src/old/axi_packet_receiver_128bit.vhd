library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity axi_packet_receiver_128bit is
    port (

        clk                 : in  std_logic;
        rst                 : in  std_logic;

        s_axis_tdata        : in  std_logic_vector(127 downto 0);
        s_axis_tvalid       : in  std_logic;
        s_axis_tlast        : in  std_logic;
        s_axis_tready       : out std_logic;

        downstream_ready    : in  std_logic;

        packet_out          : out std_logic_vector(127 downto 0);
        packet_ready        : out std_logic;

        receiving           : out std_logic
    );
end axi_packet_receiver_128bit;

architecture rtl of axi_packet_receiver_128bit is

    type state_type is (IDLE, DONE);
    signal state, next_state : state_type;

    signal packet_buffer : std_logic_vector(127 downto 0);

    signal transfer_complete : std_logic;
    signal tready_int : std_logic;

begin

    transfer_complete <= '1' when (s_axis_tvalid = '1' and tready_int = '1' and s_axis_tlast = '1')
                         else '0';

    s_axis_tready <= tready_int;
    receiving <= '1' when state = IDLE and s_axis_tvalid = '1' else '0';

    state_register: process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state <= IDLE;
            else
                state <= next_state;
            end if;
        end if;
    end process;

    next_state_logic: process(state, transfer_complete, downstream_ready)
    begin

        next_state <= state;

        case state is

            when IDLE =>

                if transfer_complete = '1' then
                    next_state <= DONE;
                end if;

            when DONE =>

                if downstream_ready = '1' then
                    next_state <= IDLE;
                end if;

            when others =>
                next_state <= IDLE;

        end case;
    end process;

    output_logic: process(state)
    begin
        case state is
            when IDLE =>
                tready_int <= '1';

            when DONE =>
                tready_int <= '0';

            when others =>
                tready_int <= '0';
        end case;
    end process;

    packet_capture: process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                packet_buffer <= (others => '0');

            else

                if transfer_complete = '1' then
                    packet_buffer <= s_axis_tdata;
                end if;
            end if;
        end if;
    end process;

    packet_output: process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                packet_out <= (others => '0');
                packet_ready <= '0';

            else

                packet_ready <= '0';

                if state = DONE then
                    packet_out <= packet_buffer;
                    packet_ready <= '1';
                end if;
            end if;
        end if;
    end process;

end rtl;
