library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use STD.TEXTIO.ALL;

package csv_reader_pkg is
    constant MAX_SAMPLES : integer := 10000;

    type sample_array is array (0 to MAX_SAMPLES-1) of signed(15 downto 0);

    type channel_data is record
        ch1 : sample_array;
        ch2 : sample_array;
        ch3 : sample_array;
        ch4 : sample_array;
        ch5 : sample_array;
        ch6 : sample_array;
        count : integer;
    end record;

    procedure read_csv_file(
        file_path : in string;
        variable samples : inout channel_data;
        max_lines : in integer
    );
end package csv_reader_pkg;

package body csv_reader_pkg is

    procedure skip_whitespace(variable L : inout line; variable idx : inout integer) is
    begin
        while idx <= L'length and (L(idx) = ' ' or L(idx) = HT) loop
            idx := idx + 1;
        end loop;
    end procedure;

    procedure parse_integer(
        variable L : inout line;
        variable idx : inout integer;
        variable value : out integer;
        variable success : out boolean
    ) is
        variable temp_str : string(1 to 20);
        variable str_len : integer := 0;
        variable is_negative : boolean := false;
        variable result : integer := 0;
        variable ch : character;
    begin
        success := false;
        value := 0;

        skip_whitespace(L, idx);

        if idx > L'length then
            return;
        end if;

        if L(idx) = '-' then
            is_negative := true;
            idx := idx + 1;
        elsif L(idx) = '+' then
            idx := idx + 1;
        end if;

        while idx <= L'length loop
            ch := L(idx);
            if ch >= '0' and ch <= '9' then
                result := result * 10 + (character'pos(ch) - character'pos('0'));
                idx := idx + 1;
            else
                exit;
            end if;
        end loop;

        if is_negative then
            result := -result;
        end if;

        value := result;
        success := true;
    end procedure;

    procedure read_csv_file(
        file_path : in string;
        variable samples : inout channel_data;
        max_lines : in integer
    ) is
        file csv_file : text;
        variable L : line;
        variable idx : integer;
        variable val : integer;
        variable success : boolean;
        variable line_count : integer := 0;
        variable ch : character;
    begin
        samples.count := 0;

        file_open(csv_file, file_path, READ_MODE);

        if not endfile(csv_file) then
            readline(csv_file, L);
            report "Skipped header line: " & L.all;
        end if;

        while not endfile(csv_file) and line_count < max_lines loop
            readline(csv_file, L);
            idx := 1;

            if L'length = 0 then
                next;
            end if;

            parse_integer(L, idx, val, success);
            if success then
                samples.ch1(line_count) := to_signed(val, 16);
            else
                report "Error parsing column 1 at line " & integer'image(line_count + 2);
                exit;
            end if;

            skip_whitespace(L, idx);
            if idx <= L'length and L(idx) = ',' then
                idx := idx + 1;
            end if;

            parse_integer(L, idx, val, success);
            if success then
                samples.ch2(line_count) := to_signed(val, 16);
            else
                report "Error parsing column 2 at line " & integer'image(line_count + 2);
                exit;
            end if;

            skip_whitespace(L, idx);
            if idx <= L'length and L(idx) = ',' then
                idx := idx + 1;
            end if;

            parse_integer(L, idx, val, success);
            if success then
                samples.ch3(line_count) := to_signed(val, 16);
            else
                report "Error parsing column 3 at line " & integer'image(line_count + 2);
                exit;
            end if;

            skip_whitespace(L, idx);
            if idx <= L'length and L(idx) = ',' then
                idx := idx + 1;
            end if;

            parse_integer(L, idx, val, success);
            if success then
                samples.ch4(line_count) := to_signed(val, 16);
            else
                report "Error parsing column 4 at line " & integer'image(line_count + 2);
                exit;
            end if;

            skip_whitespace(L, idx);
            if idx <= L'length and L(idx) = ',' then
                idx := idx + 1;
            end if;

            parse_integer(L, idx, val, success);
            if success then
                samples.ch5(line_count) := to_signed(val, 16);
            else
                report "Error parsing column 5 at line " & integer'image(line_count + 2);
                exit;
            end if;

            skip_whitespace(L, idx);
            if idx <= L'length and L(idx) = ',' then
                idx := idx + 1;
            end if;

            parse_integer(L, idx, val, success);
            if success then
                samples.ch6(line_count) := to_signed(val, 16);
            else
                report "Error parsing column 6 at line " & integer'image(line_count + 2);
                exit;
            end if;

            line_count := line_count + 1;

            if line_count mod 500 = 0 then
                report "CSV Reader: Loaded " & integer'image(line_count) & " samples";
            end if;
        end loop;

        file_close(csv_file);
        samples.count := line_count;

        report "CSV Reader: Successfully loaded " & integer'image(line_count) & " samples from " & file_path;
    end procedure;

end package body csv_reader_pkg;
