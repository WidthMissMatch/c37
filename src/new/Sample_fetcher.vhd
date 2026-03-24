library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity sample_fetcher is
    generic (
        SAMPLE_WIDTH      : integer := 16;
        BUFFER_ADDR_WIDTH : integer := 9;
        FRAC_BITS         : integer := 16
    );
    port (
        clk                 : in  std_logic;
        rst                 : in  std_logic;

        position_valid      : in  std_logic;
        position_index      : in  std_logic_vector(7 downto 0);
        position_last       : in  std_logic;
        buffer_addr_left    : in  std_logic_vector(BUFFER_ADDR_WIDTH-1 downto 0);
        buffer_addr_right   : in  std_logic_vector(BUFFER_ADDR_WIDTH-1 downto 0);
        interp_fraction     : in  std_logic_vector(FRAC_BITS-1 downto 0);

        fetcher_ready       : out std_logic;

        buffer_read_addr    : out std_logic_vector(BUFFER_ADDR_WIDTH-1 downto 0);
        buffer_read_enable  : out std_logic;
        buffer_read_data    : in  std_logic_vector(SAMPLE_WIDTH-1 downto 0);
        buffer_read_valid   : in  std_logic;

        sample_left         : out std_logic_vector(SAMPLE_WIDTH-1 downto 0);
        sample_right        : out std_logic_vector(SAMPLE_WIDTH-1 downto 0);
        fraction_out        : out std_logic_vector(FRAC_BITS-1 downto 0);
        index_out           : out std_logic_vector(7 downto 0);
        samples_valid       : out std_logic;
        samples_last        : out std_logic;

        busy                : out std_logic
    );
end sample_fetcher;

architecture behavioral of sample_fetcher is

    type state_type is (IDLE, LATCH_POSITION, READ_LEFT, WAIT_LEFT,
                        READ_RIGHT, WAIT_RIGHT, OUTPUT_SAMPLES);
    signal current_state : state_type;
    signal next_state    : state_type;

    signal addr_left_reg    : std_logic_vector(BUFFER_ADDR_WIDTH-1 downto 0);
    signal addr_right_reg   : std_logic_vector(BUFFER_ADDR_WIDTH-1 downto 0);
    signal fraction_reg     : std_logic_vector(FRAC_BITS-1 downto 0);
    signal index_reg        : std_logic_vector(7 downto 0);
    signal last_reg         : std_logic;

    signal sample_left_reg  : std_logic_vector(SAMPLE_WIDTH-1 downto 0);
    signal sample_right_reg : std_logic_vector(SAMPLE_WIDTH-1 downto 0);

    signal samples_valid_reg : std_logic;
    signal samples_last_reg  : std_logic;

    signal read_enable_reg   : std_logic;
    signal read_addr_reg     : std_logic_vector(BUFFER_ADDR_WIDTH-1 downto 0);
    signal busy_reg          : std_logic;

begin

    state_sync: process(clk, rst)
    begin
        if rst = '1' then
            current_state <= IDLE;
        elsif rising_edge(clk) then
            current_state <= next_state;
        end if;
    end process;

    state_comb: process(current_state, position_valid, buffer_read_valid)
    begin
        next_state <= current_state;

        case current_state is
            when IDLE =>
                if position_valid = '1' then
                    next_state <= LATCH_POSITION;
                end if;

            when LATCH_POSITION =>
                next_state <= READ_LEFT;

            when READ_LEFT =>
                next_state <= WAIT_LEFT;

            when WAIT_LEFT =>
                if buffer_read_valid = '1' then
                    next_state <= READ_RIGHT;
                end if;

            when READ_RIGHT =>
                next_state <= WAIT_RIGHT;

            when WAIT_RIGHT =>
                if buffer_read_valid = '1' then
                    next_state <= OUTPUT_SAMPLES;
                end if;

            when OUTPUT_SAMPLES =>
                next_state <= IDLE;

            when others =>
                next_state <= IDLE;
        end case;
    end process;

    fetcher_ready_comb: process(current_state)
    begin
        if current_state = IDLE then
            fetcher_ready <= '1';
        else
            fetcher_ready <= '0';
        end if;
    end process;

    datapath: process(clk, rst)
    begin
        if rst = '1' then
            addr_left_reg <= (others => '0');
            addr_right_reg <= (others => '0');
            fraction_reg <= (others => '0');
            index_reg <= (others => '0');
            last_reg <= '0';
            sample_left_reg <= (others => '0');
            sample_right_reg <= (others => '0');
            samples_valid_reg <= '0';
            samples_last_reg <= '0';
            read_enable_reg <= '0';
            read_addr_reg <= (others => '0');
            busy_reg <= '0';

        elsif rising_edge(clk) then

            samples_valid_reg <= '0';
            samples_last_reg <= '0';
            read_enable_reg <= '0';

            case current_state is
                when IDLE =>
                    busy_reg <= '0';

                    if position_valid = '1' then
                        addr_left_reg <= buffer_addr_left;
                        addr_right_reg <= buffer_addr_right;
                        fraction_reg <= interp_fraction;
                        index_reg <= position_index;
                        last_reg <= position_last;
                    end if;

                when LATCH_POSITION =>

                    busy_reg <= '1';

                when READ_LEFT =>

                    read_addr_reg <= addr_left_reg;
                    read_enable_reg <= '1';

                when WAIT_LEFT =>

                    null;

                when READ_RIGHT =>

                    sample_left_reg <= buffer_read_data;

                    read_addr_reg <= addr_right_reg;
                    read_enable_reg <= '1';

                when WAIT_RIGHT =>

                    null;

                when OUTPUT_SAMPLES =>

                    sample_right_reg <= buffer_read_data;

                    samples_valid_reg <= '1';
                    samples_last_reg <= last_reg;
                    busy_reg <= '0';

                when others =>
                    null;

            end case;
        end if;
    end process;

    buffer_read_addr <= read_addr_reg;
    buffer_read_enable <= read_enable_reg;

    sample_left <= sample_left_reg;
    sample_right <= sample_right_reg;
    fraction_out <= fraction_reg;
    index_out <= index_reg;
    samples_valid <= samples_valid_reg;
    samples_last <= samples_last_reg;

    busy <= busy_reg;

end behavioral;
