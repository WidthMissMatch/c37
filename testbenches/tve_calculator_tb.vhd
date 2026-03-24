library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.MATH_REAL.ALL;

entity tve_calculator_tb is
end tve_calculator_tb;

architecture testbench of tve_calculator_tb is

    component tve_calculator
        generic (
            DATA_WIDTH      : integer := 32;
            OUTPUT_WIDTH    : integer := 16;
            CORDIC_ITER     : integer := 16
        );
        port (
            clk             : in  std_logic;
            rst             : in  std_logic;
            ref_real        : in  std_logic_vector(DATA_WIDTH-1 downto 0);
            ref_imag        : in  std_logic_vector(DATA_WIDTH-1 downto 0);
            ref_valid       : in  std_logic;
            meas_real       : in  std_logic_vector(DATA_WIDTH-1 downto 0);
            meas_imag       : in  std_logic_vector(DATA_WIDTH-1 downto 0);
            meas_valid      : in  std_logic;
            tve_percent     : out std_logic_vector(OUTPUT_WIDTH-1 downto 0);
            tve_valid       : out std_logic;
            tve_pass        : out std_logic;
            tve_exceeds     : out std_logic;
            busy            : out std_logic
        );
    end component;

    constant CLK_PERIOD : time := 10 ns;

    signal clk          : std_logic := '0';
    signal rst          : std_logic := '1';
    signal ref_real     : std_logic_vector(31 downto 0) := (others => '0');
    signal ref_imag     : std_logic_vector(31 downto 0) := (others => '0');
    signal ref_valid    : std_logic := '0';
    signal meas_real    : std_logic_vector(31 downto 0) := (others => '0');
    signal meas_imag    : std_logic_vector(31 downto 0) := (others => '0');
    signal meas_valid   : std_logic := '0';
    signal tve_percent  : std_logic_vector(15 downto 0);
    signal tve_valid    : std_logic;
    signal tve_pass     : std_logic;
    signal tve_exceeds  : std_logic;
    signal busy         : std_logic;

    function real_to_q16_15(r : real) return std_logic_vector is
        variable temp : integer;
    begin
        temp := integer(r * 32768.0);
        return std_logic_vector(to_signed(temp, 32));
    end function;

    function q8_7_to_percent(slv : std_logic_vector) return real is
    begin
        return real(to_integer(unsigned(slv))) / 128.0;
    end function;

begin

    clk <= not clk after CLK_PERIOD / 2;

    dut: tve_calculator
        port map (
            clk => clk,
            rst => rst,
            ref_real => ref_real,
            ref_imag => ref_imag,
            ref_valid => ref_valid,
            meas_real => meas_real,
            meas_imag => meas_imag,
            meas_valid => meas_valid,
            tve_percent => tve_percent,
            tve_valid => tve_valid,
            tve_pass => tve_pass,
            tve_exceeds => tve_exceeds,
            busy => busy
        );

    stimulus: process
        variable tve_value : real;
    begin

        rst <= '1';
        wait for 100 ns;
        rst <= '0';
        wait for 100 ns;

        report "========================================";
        report "TVE Calculator Testbench Starting";
        report "========================================";

        report " ";
        report "TEST CASE 1: Zero Error (Identical Phasors)";
        report "Expected: TVE = 0%";

        ref_real <= real_to_q16_15(0.0);
        ref_imag <= real_to_q16_15(35.0);
        ref_valid <= '1';

        meas_real <= real_to_q16_15(0.0);
        meas_imag <= real_to_q16_15(35.0);
        meas_valid <= '1';

        wait for CLK_PERIOD;
        ref_valid <= '0';
        meas_valid <= '0';

        wait until tve_valid = '1';
        wait for CLK_PERIOD;

        tve_value := q8_7_to_percent(tve_percent);
        report "  Measured TVE: " & real'image(tve_value) & "%";
        report "  TVE Pass: " & std_logic'image(tve_pass);

        assert tve_value < 0.1
            report "FAIL: TVE should be near 0% for identical phasors"
            severity error;

        wait for 500 ns;

        report " ";
        report "TEST CASE 2: Small Error (0.5% magnitude)";
        report "Expected: TVE < 1%";

        ref_real <= real_to_q16_15(0.0);
        ref_imag <= real_to_q16_15(35.0);
        ref_valid <= '1';

        meas_real <= real_to_q16_15(0.0);
        meas_imag <= real_to_q16_15(35.175);
        meas_valid <= '1';

        wait for CLK_PERIOD;
        ref_valid <= '0';
        meas_valid <= '0';

        wait until tve_valid = '1';
        wait for CLK_PERIOD;

        tve_value := q8_7_to_percent(tve_percent);
        report "  Measured TVE: " & real'image(tve_value) & "%";
        report "  TVE Pass: " & std_logic'image(tve_pass);

        assert tve_value < 1.0
            report "FAIL: TVE should be < 1% for 0.5% error"
            severity error;

        assert tve_pass = '1'
            report "FAIL: tve_pass should be '1' for TVE < 1%"
            severity error;

        wait for 500 ns;

        report " ";
        report "TEST CASE 3: 1% Magnitude Error (Threshold)";
        report "Expected: TVE ≈ 1%";

        ref_real <= real_to_q16_15(0.0);
        ref_imag <= real_to_q16_15(35.0);
        ref_valid <= '1';

        meas_real <= real_to_q16_15(0.0);
        meas_imag <= real_to_q16_15(35.35);
        meas_valid <= '1';

        wait for CLK_PERIOD;
        ref_valid <= '0';
        meas_valid <= '0';

        wait until tve_valid = '1';
        wait for CLK_PERIOD;

        tve_value := q8_7_to_percent(tve_percent);
        report "  Measured TVE: " & real'image(tve_value) & "%";
        report "  TVE Pass: " & std_logic'image(tve_pass);

        wait for 500 ns;

        report " ";
        report "TEST CASE 4: Large Error (5% magnitude)";
        report "Expected: TVE > 3%, tve_exceeds = '1'";

        ref_real <= real_to_q16_15(0.0);
        ref_imag <= real_to_q16_15(35.0);
        ref_valid <= '1';

        meas_real <= real_to_q16_15(0.0);
        meas_imag <= real_to_q16_15(36.75);
        meas_valid <= '1';

        wait for CLK_PERIOD;
        ref_valid <= '0';
        meas_valid <= '0';

        wait until tve_valid = '1';
        wait for CLK_PERIOD;

        tve_value := q8_7_to_percent(tve_percent);
        report "  Measured TVE: " & real'image(tve_value) & "%";
        report "  TVE Exceeds 3%: " & std_logic'image(tve_exceeds);

        assert tve_value > 3.0
            report "FAIL: TVE should exceed 3% for 5% error"
            severity error;

        assert tve_exceeds = '1'
            report "FAIL: tve_exceeds should be '1' for TVE > 3%"
            severity error;

        wait for 500 ns;

        report " ";
        report "TEST CASE 5: Phase Error (2° shift)";
        report "Expected: TVE < 0.5%";

        ref_real <= real_to_q16_15(0.0);
        ref_imag <= real_to_q16_15(35.0);
        ref_valid <= '1';

        meas_real <= real_to_q16_15(-1.221);
        meas_imag <= real_to_q16_15(34.979);
        meas_valid <= '1';

        wait for CLK_PERIOD;
        ref_valid <= '0';
        meas_valid <= '0';

        wait until tve_valid = '1';
        wait for CLK_PERIOD;

        tve_value := q8_7_to_percent(tve_percent);
        report "  Measured TVE: " & real'image(tve_value) & "%";

        wait for 500 ns;

        report " ";
        report "========================================";
        report "TVE Calculator Testbench Complete";
        report "All tests passed successfully!";
        report "========================================";

        wait;
    end process;

end testbench;
