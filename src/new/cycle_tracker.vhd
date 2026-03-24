library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity cycle_tracker is
    generic (
        FRAC_BITS     : integer := 16;
        COUNT_WIDTH   : integer := 32
    );
    port (

        clk                 : in  std_logic;
        rst                 : in  std_logic;

        adc_valid           : in  std_logic;

        samples_per_cycle   : in  std_logic_vector(COUNT_WIDTH-1 downto 0);
        spc_valid           : in  std_logic;

        enable              : in  std_logic;

        cycle_complete      : out std_logic;
        cycle_start_offset  : out std_logic_vector(COUNT_WIDTH-1 downto 0);
        cycle_end_sample    : out std_logic_vector(COUNT_WIDTH-1 downto 0);

        cycle_count         : out std_logic_vector(15 downto 0);
        current_accumulator : out std_logic_vector(COUNT_WIDTH-1 downto 0);
        ready               : out std_logic
    );
end cycle_tracker;

architecture behavioral of cycle_tracker is

    constant ONE_Q16_16 : unsigned(COUNT_WIDTH-1 downto 0) := to_unsigned(65536, COUNT_WIDTH);

    constant SPC_MIN : unsigned(COUNT_WIDTH-1 downto 0) := to_unsigned(13107200, COUNT_WIDTH);

    constant SPC_MAX : unsigned(COUNT_WIDTH-1 downto 0) := to_unsigned(26214400, COUNT_WIDTH);

    type state_type is (WAIT_SPC, TRACKING);
    signal current_state : state_type;
    signal next_state    : state_type;

    signal sample_accumulator : unsigned(COUNT_WIDTH-1 downto 0);

    signal spc_latched : unsigned(COUNT_WIDTH-1 downto 0);

    signal spc_pending : unsigned(COUNT_WIDTH-1 downto 0);
    signal spc_pending_valid : std_logic;

    signal start_offset_reg : unsigned(COUNT_WIDTH-1 downto 0);

    signal abs_sample_count : unsigned(COUNT_WIDTH-1 downto 0);

    signal cycle_count_reg : unsigned(15 downto 0);

    signal cycle_complete_reg : std_logic;

    signal ready_reg : std_logic;

    signal next_accumulator      : unsigned(COUNT_WIDTH-1 downto 0);
    signal cycle_boundary_hit    : std_logic;
    signal remainder_value       : unsigned(COUNT_WIDTH-1 downto 0);

begin

    next_accumulator <= sample_accumulator + ONE_Q16_16;

    cycle_boundary_hit <= '1' when (next_accumulator >= spc_latched) and
                                   (current_state = TRACKING) and
                                   (adc_valid = '1')
                          else '0';

    remainder_value <= next_accumulator - spc_latched;

    state_sync: process(clk, rst)
    begin
        if rst = '1' then
            current_state <= WAIT_SPC;
        elsif rising_edge(clk) then

            if current_state /= next_state then
                if next_state = TRACKING then
                    report "[CYCLE_TRACK] State transition: WAIT_SPC -> TRACKING" severity note;
                elsif next_state = WAIT_SPC then
                    report "[CYCLE_TRACK] State transition: TRACKING -> WAIT_SPC" severity note;
                end if;
            end if;
            current_state <= next_state;
        end if;
    end process;

    state_comb: process(current_state, spc_valid, spc_pending_valid, enable)
    begin

        next_state <= current_state;

        case current_state is
            when WAIT_SPC =>

                if enable = '1' and (spc_valid = '1' or spc_pending_valid = '1') then
                    next_state <= TRACKING;
                end if;

            when TRACKING =>

                if enable = '0' then
                    next_state <= WAIT_SPC;
                end if;

            when others =>
                next_state <= WAIT_SPC;
        end case;
    end process;

    spc_buffer_process: process(clk, rst)
    begin
        if rst = '1' then
            spc_pending <= (others => '0');
            spc_pending_valid <= '0';
        elsif rising_edge(clk) then

            if spc_valid = '1' then

                if unsigned(samples_per_cycle) >= SPC_MIN and
                   unsigned(samples_per_cycle) <= SPC_MAX then
                    spc_pending <= unsigned(samples_per_cycle);
                    spc_pending_valid <= '1';
                end if;
            end if;

            if cycle_boundary_hit = '1' then
                spc_pending_valid <= '0';
            end if;
        end if;
    end process;

    datapath_process: process(clk, rst)
    begin
        if rst = '1' then
            sample_accumulator <= (others => '0');
            spc_latched <= to_unsigned(19660800, COUNT_WIDTH);
            start_offset_reg <= (others => '0');
            abs_sample_count <= (others => '0');
            cycle_count_reg <= (others => '0');
            cycle_complete_reg <= '0';
            ready_reg <= '0';

        elsif rising_edge(clk) then

            cycle_complete_reg <= '0';

            case current_state is
                when WAIT_SPC =>

                    sample_accumulator <= (others => '0');
                    start_offset_reg <= (others => '0');
                    ready_reg <= '0';

                    if spc_pending_valid = '1' then
                        spc_latched <= spc_pending;
                    elsif spc_valid = '1' then
                        if unsigned(samples_per_cycle) >= SPC_MIN and
                           unsigned(samples_per_cycle) <= SPC_MAX then
                            spc_latched <= unsigned(samples_per_cycle);
                        end if;
                    end if;

                when TRACKING =>
                    ready_reg <= '1';

                    if adc_valid = '1' then

                        abs_sample_count <= abs_sample_count + 1;

                        if abs_sample_count < 5 then
                            report "[CYCLE_TRACK] In TRACKING state, sample #" & integer'image(to_integer(abs_sample_count) + 1) &
                                   ", accumulator = " & integer'image(to_integer(sample_accumulator)) &
                                   ", spc_latched = " & integer'image(to_integer(spc_latched)) severity note;
                        end if;

                        if cycle_boundary_hit = '1' then

                            cycle_complete_reg <= '1';
                            report "[CYCLE_TRACK] CYCLE COMPLETE! at sample #" & integer'image(to_integer(abs_sample_count) + 1) severity note;

                            cycle_count_reg <= cycle_count_reg + 1;

                            start_offset_reg <= remainder_value;

                            sample_accumulator <= remainder_value;

                            if spc_pending_valid = '1' then
                                spc_latched <= spc_pending;
                            end if;
                        else

                            sample_accumulator <= next_accumulator;
                        end if;
                    end if;

                when others =>
                    null;

            end case;
        end if;
    end process;

    cycle_complete <= cycle_complete_reg;
    cycle_start_offset <= std_logic_vector(start_offset_reg);
    cycle_end_sample <= std_logic_vector(abs_sample_count);
    cycle_count <= std_logic_vector(cycle_count_reg);
    current_accumulator <= std_logic_vector(sample_accumulator);
    ready <= ready_reg;

end behavioral;
