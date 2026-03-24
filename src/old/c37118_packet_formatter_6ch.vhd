library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity c37118_packet_formatter_6ch is
    generic (
        MAG_WIDTH       : integer := 32;
        PHASE_WIDTH     : integer := 16;
        FREQ_WIDTH      : integer := 32;
        IDCODE_VAL      : std_logic_vector(15 downto 0) := x"0001";
        CLK_FREQ_HZ     : integer := 100_000_000
    );
    port (
        clk             : in  std_logic;
        rst             : in  std_logic;

        magnitude_ch1   : in  std_logic_vector(MAG_WIDTH-1 downto 0);
        phase_angle_ch1 : in  std_logic_vector(PHASE_WIDTH-1 downto 0);
        frequency_ch1   : in  std_logic_vector(FREQ_WIDTH-1 downto 0);
        rocof_ch1       : in  std_logic_vector(FREQ_WIDTH-1 downto 0);
        mag_valid_ch1   : in  std_logic;

        magnitude_ch2   : in  std_logic_vector(MAG_WIDTH-1 downto 0);
        phase_angle_ch2 : in  std_logic_vector(PHASE_WIDTH-1 downto 0);
        mag_valid_ch2   : in  std_logic;

        magnitude_ch3   : in  std_logic_vector(MAG_WIDTH-1 downto 0);
        phase_angle_ch3 : in  std_logic_vector(PHASE_WIDTH-1 downto 0);
        mag_valid_ch3   : in  std_logic;

        magnitude_ch4   : in  std_logic_vector(MAG_WIDTH-1 downto 0);
        phase_angle_ch4 : in  std_logic_vector(PHASE_WIDTH-1 downto 0);
        mag_valid_ch4   : in  std_logic;

        magnitude_ch5   : in  std_logic_vector(MAG_WIDTH-1 downto 0);
        phase_angle_ch5 : in  std_logic_vector(PHASE_WIDTH-1 downto 0);
        mag_valid_ch5   : in  std_logic;

        magnitude_ch6   : in  std_logic_vector(MAG_WIDTH-1 downto 0);
        phase_angle_ch6 : in  std_logic_vector(PHASE_WIDTH-1 downto 0);
        mag_valid_ch6   : in  std_logic;

        tve_percent_ch1 : in  std_logic_vector(15 downto 0);
        tve_valid_ch1   : in  std_logic;
        tve_pass_ch1    : in  std_logic;
        tve_exceeds_ch1 : in  std_logic;

        enable          : in  std_logic;

        m_axis_tdata    : out std_logic_vector(31 downto 0);
        m_axis_tvalid   : out std_logic;
        m_axis_tready   : in  std_logic;
        m_axis_tlast    : out std_logic;

        packet_count    : out std_logic_vector(31 downto 0);
        packet_sent     : out std_logic
    );
end c37118_packet_formatter_6ch;

architecture behavioral of c37118_packet_formatter_6ch is

    component crc_ccitt_c37118 is
        port (
            clk             : in  std_logic;
            rst             : in  std_logic;
            start           : in  std_logic;
            clear           : in  std_logic;
            data_in         : in  std_logic_vector(7 downto 0);
            data_valid      : in  std_logic;
            data_last       : in  std_logic;
            crc_out         : out std_logic_vector(15 downto 0);
            crc_valid       : out std_logic;
            busy            : out std_logic;
            byte_count      : out std_logic_vector(15 downto 0)
        );
    end component;

    type state_type is (IDLE, CAPTURE, SEND_WORD, FEED_CRC, FEED_RESERVED, WAIT_CRC, SEND_CRC_WORD, DONE);
    signal state : state_type;

    signal mag_cap_ch1      : std_logic_vector(31 downto 0);
    signal phase_cap_ch1    : std_logic_vector(15 downto 0);
    signal freq_cap_ch1     : std_logic_vector(31 downto 0);
    signal rocof_cap_ch1    : std_logic_vector(31 downto 0);
    signal mag_cap_ch2      : std_logic_vector(31 downto 0);
    signal phase_cap_ch2    : std_logic_vector(15 downto 0);
    signal mag_cap_ch3      : std_logic_vector(31 downto 0);
    signal phase_cap_ch3    : std_logic_vector(15 downto 0);
    signal mag_cap_ch4      : std_logic_vector(31 downto 0);
    signal phase_cap_ch4    : std_logic_vector(15 downto 0);
    signal mag_cap_ch5      : std_logic_vector(31 downto 0);
    signal phase_cap_ch5    : std_logic_vector(15 downto 0);
    signal mag_cap_ch6      : std_logic_vector(31 downto 0);
    signal phase_cap_ch6    : std_logic_vector(15 downto 0);

    signal stat_field       : std_logic_vector(15 downto 0);

    signal word_idx         : integer range 0 to 19;
    signal byte_idx         : integer range 0 to 3;
    signal word_buffer      : std_logic_vector(31 downto 0);
    signal timestamp        : unsigned(31 downto 0) := (others => '0');
    signal pkt_cnt          : unsigned(31 downto 0) := (others => '0');
    signal mag_valid_ch1_prev : std_logic := '0';

    signal crc_start        : std_logic := '0';
    signal crc_clear        : std_logic := '0';
    signal crc_data_in      : std_logic_vector(7 downto 0) := (others => '0');
    signal crc_data_valid   : std_logic := '0';
    signal crc_data_last    : std_logic := '0';
    signal crc_out          : std_logic_vector(15 downto 0);
    signal crc_valid        : std_logic;
    signal crc_busy         : std_logic;
    signal crc_byte_count   : std_logic_vector(15 downto 0);

begin

    stat_calc: process(clk, rst)
    begin
        if rst = '1' then
            stat_field <= x"C010";
        elsif rising_edge(clk) then

            stat_field <= x"C010";
        end if;
    end process;

    crc_inst: crc_ccitt_c37118
        port map (
            clk         => clk,
            rst         => rst,
            start       => crc_start,
            clear       => crc_clear,
            data_in     => crc_data_in,
            data_valid  => crc_data_valid,
            data_last   => crc_data_last,
            crc_out     => crc_out,
            crc_valid   => crc_valid,
            busy        => crc_busy,
            byte_count  => crc_byte_count
        );

    process(clk, rst)
    begin
        if rst = '1' then
            state <= IDLE;
            mag_cap_ch1 <= (others => '0');
            phase_cap_ch1 <= (others => '0');
            freq_cap_ch1 <= (others => '0');
            rocof_cap_ch1 <= (others => '0');
            mag_cap_ch2 <= (others => '0');
            phase_cap_ch2 <= (others => '0');
            mag_cap_ch3 <= (others => '0');
            phase_cap_ch3 <= (others => '0');
            mag_cap_ch4 <= (others => '0');
            phase_cap_ch4 <= (others => '0');
            mag_cap_ch5 <= (others => '0');
            phase_cap_ch5 <= (others => '0');
            mag_cap_ch6 <= (others => '0');
            phase_cap_ch6 <= (others => '0');
            word_idx <= 0;
            byte_idx <= 0;
            word_buffer <= (others => '0');
            timestamp <= (others => '0');
            pkt_cnt <= (others => '0');

            m_axis_tdata <= (others => '0');
            m_axis_tvalid <= '0';
            m_axis_tlast <= '0';
            packet_sent <= '0';
            mag_valid_ch1_prev <= '0';
            crc_start <= '0';
            crc_clear <= '0';
            crc_data_in <= (others => '0');
            crc_data_valid <= '0';
            crc_data_last <= '0';

        elsif rising_edge(clk) then

            packet_sent <= '0';
            crc_start <= '0';
            crc_clear <= '0';
            crc_data_valid <= '0';
            crc_data_last <= '0';
            m_axis_tvalid <= '0';

            mag_valid_ch1_prev <= mag_valid_ch1;

            case state is

                when IDLE =>
                    m_axis_tlast <= '0';
                    if enable = '1' then
                        state <= CAPTURE;
                    end if;

                when CAPTURE =>
                    if mag_valid_ch1 = '1' and mag_valid_ch1_prev = '0' then
                        mag_cap_ch1 <= magnitude_ch1;
                        phase_cap_ch1 <= phase_angle_ch1;
                        freq_cap_ch1 <= frequency_ch1;
                        rocof_cap_ch1 <= rocof_ch1;
                        mag_cap_ch2 <= magnitude_ch2;
                        phase_cap_ch2 <= phase_angle_ch2;
                        mag_cap_ch3 <= magnitude_ch3;
                        phase_cap_ch3 <= phase_angle_ch3;
                        mag_cap_ch4 <= magnitude_ch4;
                        phase_cap_ch4 <= phase_angle_ch4;
                        mag_cap_ch5 <= magnitude_ch5;
                        phase_cap_ch5 <= phase_angle_ch5;
                        mag_cap_ch6 <= magnitude_ch6;
                        phase_cap_ch6 <= phase_angle_ch6;
                        timestamp <= timestamp + 1;
                        word_idx <= 0;
                        byte_idx <= 0;
                        report "CAPTURE: Starting new packet, pulsing crc_clear and crc_start";
                        crc_clear <= '1';
                        crc_start <= '1';
                        state <= SEND_WORD;
                    end if;

                when SEND_WORD =>

                    if m_axis_tready = '1' then
                        m_axis_tvalid <= '1';
                        case word_idx is
                            when 0 =>
                                word_buffer <= x"AA01" & x"004C";
                                m_axis_tdata <= x"AA01" & x"004C";
                                report "SEND_WORD 0: AA 01 00 4C";
                            when 1 =>
                                word_buffer <= IDCODE_VAL & std_logic_vector(timestamp(31 downto 16));
                                m_axis_tdata <= IDCODE_VAL & std_logic_vector(timestamp(31 downto 16));
                            when 2 =>
                                word_buffer <= std_logic_vector(timestamp(15 downto 0)) & x"0000";
                                m_axis_tdata <= std_logic_vector(timestamp(15 downto 0)) & x"0000";
                            when 3 =>
                                word_buffer <= stat_field & x"0000";
                                m_axis_tdata <= stat_field & x"0000";
                            when 4 =>
                                word_buffer <= mag_cap_ch1;
                                m_axis_tdata <= mag_cap_ch1;
                            when 5 =>
                                word_buffer <= x"0000" & phase_cap_ch1;
                                m_axis_tdata <= x"0000" & phase_cap_ch1;
                            when 6 =>
                                word_buffer <= freq_cap_ch1;
                                m_axis_tdata <= freq_cap_ch1;
                            when 7 =>
                                word_buffer <= rocof_cap_ch1;
                                m_axis_tdata <= rocof_cap_ch1;
                            when 8 =>
                                word_buffer <= mag_cap_ch2;
                                m_axis_tdata <= mag_cap_ch2;
                            when 9 =>
                                word_buffer <= x"0000" & phase_cap_ch2;
                                m_axis_tdata <= x"0000" & phase_cap_ch2;
                            when 10 =>
                                word_buffer <= mag_cap_ch3;
                                m_axis_tdata <= mag_cap_ch3;
                            when 11 =>
                                word_buffer <= x"0000" & phase_cap_ch3;
                                m_axis_tdata <= x"0000" & phase_cap_ch3;
                            when 12 =>
                                word_buffer <= mag_cap_ch4;
                                m_axis_tdata <= mag_cap_ch4;
                            when 13 =>
                                word_buffer <= x"0000" & phase_cap_ch4;
                                m_axis_tdata <= x"0000" & phase_cap_ch4;
                            when 14 =>
                                word_buffer <= mag_cap_ch5;
                                m_axis_tdata <= mag_cap_ch5;
                            when 15 =>
                                word_buffer <= x"0000" & phase_cap_ch5;
                                m_axis_tdata <= x"0000" & phase_cap_ch5;
                            when 16 =>
                                word_buffer <= mag_cap_ch6;
                                m_axis_tdata <= mag_cap_ch6;
                            when 17 =>
                                word_buffer <= x"0000" & phase_cap_ch6;
                                m_axis_tdata <= x"0000" & phase_cap_ch6;
                            when others =>
                                word_buffer <= (others => '0');
                                m_axis_tdata <= (others => '0');
                        end case;
                        byte_idx <= 0;
                        state <= FEED_CRC;
                    end if;

                when FEED_CRC =>

                    case byte_idx is
                        when 0 => crc_data_in <= word_buffer(31 downto 24);
                        when 1 => crc_data_in <= word_buffer(23 downto 16);
                        when 2 => crc_data_in <= word_buffer(15 downto 8);
                        when 3 => crc_data_in <= word_buffer(7 downto 0);
                        when others => null;
                    end case;
                    crc_data_valid <= '1';

                    if word_idx = 0 then
                        report "FEED_CRC word 0, byte " & integer'image(byte_idx) &
                               " = " & integer'image(to_integer(unsigned(crc_data_in)));
                    end if;

                    if byte_idx = 3 then
                        word_idx <= word_idx + 1;
                        if word_idx = 17 then

                            byte_idx <= 0;
                            state <= FEED_RESERVED;
                        else
                            state <= SEND_WORD;
                        end if;
                    else
                        byte_idx <= byte_idx + 1;
                    end if;

                when FEED_RESERVED =>

                    case byte_idx is
                        when 0 =>
                            crc_data_in <= x"00";
                            report "FEED_RESERVED: byte 73 = 0x00";
                        when 1 =>
                            crc_data_in <= x"00";
                            crc_data_last <= '1';
                            report "FEED_RESERVED: byte 74 = 0x00 (LAST)";
                        when others => null;
                    end case;
                    crc_data_valid <= '1';

                    if byte_idx = 1 then
                        state <= WAIT_CRC;
                    else
                        byte_idx <= byte_idx + 1;
                    end if;

                when WAIT_CRC =>
                    if crc_valid = '1' then
                        report "CRC_VALID detected! crc_out = " & integer'image(to_integer(unsigned(crc_out))) &
                               ", byte_count = " & integer'image(to_integer(unsigned(crc_byte_count)));
                        state <= SEND_CRC_WORD;
                    end if;

                when SEND_CRC_WORD =>
                    if m_axis_tready = '1' then
                        report "SEND_CRC_WORD: Sending CRC = " & integer'image(to_integer(unsigned(crc_out)));
                        m_axis_tdata <= x"0000" & crc_out;
                        m_axis_tvalid <= '1';
                        m_axis_tlast <= '1';
                        state <= DONE;
                    end if;

                when DONE =>
                    m_axis_tvalid <= '0';
                    m_axis_tlast <= '0';
                    pkt_cnt <= pkt_cnt + 1;
                    packet_sent <= '1';
                    state <= CAPTURE;

            end case;
        end if;
    end process;

    packet_count <= std_logic_vector(pkt_cnt);

end behavioral;
