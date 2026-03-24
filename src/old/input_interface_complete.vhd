library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity input_interface_complete is
    port (

        clk                 : in  std_logic;
        rst                 : in  std_logic;

        s_axis_tdata        : in  std_logic_vector(127 downto 0);
        s_axis_tvalid       : in  std_logic;
        s_axis_tlast        : in  std_logic;
        s_axis_tready       : out std_logic;

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

        sync_locked         : out std_logic;
        good_packet_count   : out std_logic_vector(31 downto 0);
        bad_packet_count    : out std_logic_vector(31 downto 0);
        channels_extracted  : out std_logic_vector(31 downto 0);

        axi_receiving       : out std_logic;
        raw_packet_count    : out std_logic_vector(15 downto 0)
    );
end input_interface_complete;

architecture structural of input_interface_complete is

    component axi_packet_receiver_128bit is
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
    end component;

    component packet_validator is
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
    end component;

    component channel_extractor is
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
    end component;

    signal axi_packet_out   : std_logic_vector(127 downto 0);
    signal axi_packet_ready : std_logic;
    signal axi_receiving_sig: std_logic;

    signal validated_packet : std_logic_vector(127 downto 0);
    signal validated_valid  : std_logic;

    signal raw_pkt_count    : unsigned(15 downto 0);

begin

    axi_receiver_inst: axi_packet_receiver_128bit
        port map (
            clk                 => clk,
            rst                 => rst,

            s_axis_tdata        => s_axis_tdata,
            s_axis_tvalid       => s_axis_tvalid,
            s_axis_tlast        => s_axis_tlast,
            s_axis_tready       => s_axis_tready,

            downstream_ready    => '1',

            packet_out          => axi_packet_out,
            packet_ready        => axi_packet_ready,
            receiving           => axi_receiving_sig
        );

    packet_validator_inst: packet_validator
        port map (
            clk                 => clk,
            rst                 => rst,

            packet_in           => axi_packet_out,
            packet_valid_in     => axi_packet_ready,

            packet_out          => validated_packet,
            packet_valid_out    => validated_valid,

            sync_locked         => sync_locked,
            good_count          => good_packet_count,
            bad_count           => bad_packet_count
        );

    channel_extractor_inst: channel_extractor
        port map (
            clk                 => clk,
            rst                 => rst,

            packet_in           => validated_packet,
            packet_valid        => validated_valid,

            ch0_data            => ch0_data,
            ch0_valid           => ch0_valid,

            ch1_data            => ch1_data,
            ch1_valid           => ch1_valid,

            ch2_data            => ch2_data,
            ch2_valid           => ch2_valid,

            ch3_data            => ch3_data,
            ch3_valid           => ch3_valid,

            ch4_data            => ch4_data,
            ch4_valid           => ch4_valid,

            ch5_data            => ch5_data,
            ch5_valid           => ch5_valid,

            channels_extracted  => channels_extracted
        );

    raw_packet_counter: process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                raw_pkt_count <= (others => '0');
            else
                if axi_packet_ready = '1' then
                    raw_pkt_count <= raw_pkt_count + 1;
                end if;
            end if;
        end if;
    end process;

    axi_receiving    <= axi_receiving_sig;
    raw_packet_count <= std_logic_vector(raw_pkt_count);

end structural;
