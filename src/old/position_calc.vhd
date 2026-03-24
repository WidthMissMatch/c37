library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity position_calculator is
    generic (
        OUTPUT_SAMPLES    : integer := 256;
        BUFFER_ADDR_WIDTH : integer := 9;
        FRAC_BITS         : integer := 16
    );
    port (

        clk                 : in  std_logic;
        rst                 : in  std_logic;

        cycle_complete      : in  std_logic;

        cycle_end_sample    : in  std_logic_vector(31 downto 0);
        samples_per_cycle   : in  std_logic_vector(31 downto 0);

        position_valid      : out std_logic;
        position_index      : out std_logic_vector(7 downto 0);
        position_last       : out std_logic;

        buffer_addr_left    : out std_logic_vector(BUFFER_ADDR_WIDTH-1 downto 0);
        buffer_addr_right   : out std_logic_vector(BUFFER_ADDR_WIDTH-1 downto 0);

        interp_fraction     : out std_logic_vector(FRAC_BITS-1 downto 0);

        busy                : out std_logic;
        ready               : out std_logic;

        downstream_ready    : in  std_logic
    );
end position_calculator;

architecture behavioral of position_calculator is

    constant INDEX_MAX : integer := OUTPUT_SAMPLES - 1;

    constant BUFFER_DEPTH : integer := 512;

    type state_type is (IDLE, CALC_PARAMS, ENERATE, OUTPUT_POSITION);
    signal current_state : state_type;
    signal next_state    : state_type;

    signal step_size : unsigned(31 downto 0);

    signal cycle_start_q16 : unsigned(47 downto 0);

    signal current_position : unsigned(47 downto 0);

    signal output_index : unsigned(7 downto 0);

    signal spc_latched : unsigned(31 downto 0);
    signal end_sample_latched : unsigned(31 downto 0);

    signal addr_left_reg    : unsigned(BUFFER_ADDR_WIDTH-1 downto 0);
    signal addr_right_reg   : unsigned(BUFFER_ADDR_WIDTH-1 downto 0);
    signal fraction_reg     : unsigned(FRAC_BITS-1 downto 0);
    signal index_reg        : unsigned(7 downto 0);
    signal valid_reg        : std_logic;
    signal last_reg         : std_logic;

    signal busy_reg  : std_logic;
    signal ready_reg : std_logic;

    signal position_integer  : unsigned(31 downto 0);
    signal position_fraction : unsigned(FRAC_BITS-1 downto 0);
    signal addr_left_calc    : unsigned(BUFFER_ADDR_WIDTH-1 downto 0);
    signal addr_right_calc   : unsigned(BUFFER_ADDR_WIDTH-1 downto 0);

begin

    state_sync: process(clk, rst)
    begin
        if rst = '1' then
            current_state <= IDLE;
        elsif rising_edge(clk) then
            current_state <= next_state;
        end if;
    end process;

    state_comb: process(current_state, cycle_complete, output_index, downstream_ready)
    begin
        next_state <= current_state;

        case current_state is
            when IDLE =>
                if cycle_complete = '1' then
                    next_state <= CALC_PARAMS;
                end if;

            when CALC_PARAMS =>

                next_state <= ENERATE;

            when ENERATE =>

                next_state <= OUTPUT_POSITION;

            when OUTPUT_POSITION =>

                if downstream_ready = '1' then
                    if output_index = INDEX_MAX then
                        next_state <= IDLE;
                    else
                        next_state <= ENERATE;
                    end if;
                end if;

            when others =>
                next_state <= IDLE;
        end case;
    end process;

    position_integer <= current_position(47 downto 16);

    position_fraction <= current_position(FRAC_BITS-1 downto 0);

    addr_left_calc <= position_integer(BUFFER_ADDR_WIDTH-1 downto 0);

    addr_right_calc <= addr_left_calc + 1;

    datapath: process(clk, rst)
        variable cycle_end_extended : unsigned(47 downto 0);
        variable spc_extended       : unsigned(47 downto 0);
    begin
        if rst = '1' then
            step_size <= (others => '0');
            cycle_start_q16 <= (others => '0');
            current_position <= (others => '0');
            output_index <= (others => '0');
            spc_latched <= (others => '0');
            end_sample_latched <= (others => '0');
            addr_left_reg <= (others => '0');
            addr_right_reg <= (others => '0');
            fraction_reg <= (others => '0');
            index_reg <= (others => '0');
            valid_reg <= '0';
            last_reg <= '0';
            busy_reg <= '0';
            ready_reg <= '1';

        elsif rising_edge(clk) then

            valid_reg <= '0';
            last_reg <= '0';

            case current_state is
                when IDLE =>
                    busy_reg <= '0';
                    ready_reg <= '1';
                    output_index <= (others => '0');

                    if cycle_complete = '1' then
                        spc_latched <= unsigned(samples_per_cycle);
                        end_sample_latched <= unsigned(cycle_end_sample);
                        busy_reg <= '1';
                        ready_reg <= '0';
                    end if;

                when CALC_PARAMS =>

                    step_size <= "00000000" & spc_latched(31 downto 8);

                    cycle_end_extended := (others => '0');
                    cycle_end_extended(47 downto 16) := end_sample_latched;

                    spc_extended := (others => '0');
                    spc_extended(31 downto 0) := spc_latched;

                    cycle_start_q16 <= cycle_end_extended - spc_extended;

                    output_index <= (others => '0');

                when ENERATE =>

                    if output_index = 0 then

                        current_position <= cycle_start_q16;
                    else

                        current_position <= current_position + step_size;
                    end if;

                when OUTPUT_POSITION =>

                    if downstream_ready = '1' then

                        addr_left_reg <= addr_left_calc;
                        addr_right_reg <= addr_right_calc;
                        fraction_reg <= position_fraction;
                        index_reg <= output_index;

                        valid_reg <= '1';

                        if output_index = INDEX_MAX then
                            last_reg <= '1';
                        end if;

                        output_index <= output_index + 1;
                    end if;

                when others =>
                    null;

            end case;
        end if;
    end process;

    position_valid <= valid_reg;
    position_index <= std_logic_vector(index_reg);
    position_last <= last_reg;
    buffer_addr_left <= std_logic_vector(addr_left_reg);
    buffer_addr_right <= std_logic_vector(addr_right_reg);
    interp_fraction <= std_logic_vector(fraction_reg);
    busy <= busy_reg;
    ready <= ready_reg;

end behavioral;
