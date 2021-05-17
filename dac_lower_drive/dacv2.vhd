library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.std_logic_misc.all;
use ieee.numeric_std.all;

use work.FRONTPANEL.all;

Library UNISIM;
use UNISIM.vcomponents.all;

entity dac is
	port (
        -- opal kelly --
		hi_in     : in    std_logic_vector(7 downto 0);
		hi_out    : out   std_logic_vector(1 downto 0);
		hi_inout  : inout std_logic_vector(15 downto 0);
		hi_muxsel : out   std_logic;
		-- ok peripherals --
      led : out std_logic_vector(7 downto 0) := (others => '1');
		-- 100 MHz from PLL --
		clk_100 : in std_logic;
		clk_ext : in std_logic;	
      trigger : in std_logic;
		-- dac --
      dac_bus : inout std_logic_vector(15 downto 0);
      dac_cs  : out std_logic_vector(7 downto 0) := (others => '1');
      ldac    : out std_logic := '0'
    );

    function log2(x: natural) return natural is
        variable temp : integer := x;
        variable n : integer := 0;
    begin
        while temp > 1 loop
            temp := temp/2;
            n := n+1;
        end loop;
        return n;
    end function log2;
end dac;



architecture arch of dac is
    -- opal kelly --
    signal ti_clk   : std_logic; -- 48MHz clk. USB data is sync'd to this.
	 signal ok1      : std_logic_vector(30 downto 0);
	 signal ok2      : std_logic_vector(16 downto 0);
	 signal ok2s     : std_logic_vector(17*2-1 downto 0);
    -- ok usb --
	 signal ep00wire  : std_logic_vector(15 downto 0);
    signal ep01wire  : std_logic_vector(15 downto 0);
    signal ep02wire  : std_logic_vector(15 downto 0);
    signal ep03wire  : std_logic_vector(15 downto 0);
    signal ep04wire  : std_logic_vector(15 downto 0);
    signal ep05wire  : std_logic_vector(15 downto 0);
    signal ep06wire  : std_logic_vector(15 downto 0);
    signal ep07wire  : std_logic_vector(15 downto 0);
    signal ep08wire  : std_logic_vector(15 downto 0);
    signal ep09wire  : std_logic_vector(15 downto 0);
	signal ep20wire  : std_logic_vector(15 downto 0);
    signal ep80pipe  : std_logic_vector(15 downto 0); 
    signal ep80write : std_logic; -- hi during communication

    type state_type is (idle, load, run, ready);
    signal state : state_type := idle;

    signal clk     : std_logic;

    signal dac_count   : integer range 0 to 7 := 0;
    signal latch_count : integer range 0 to 4 := 0;
    signal sequence_count : integer range 0 to 10000 := 0;
    signal read_logic  : std_logic_vector(47 downto 0) := std_logic_vector(to_unsigned(0, 48));
       
    type int_array is array(0 to 7) of integer;
	 type int16_array is array(0 to 7) of integer range 0 to 2**16-1;
    signal ticks_til_update : int_array := (others => 5);
    signal step_size        : int_array := (others => 0);
    signal next_voltage     : int16_array := (others => 2**15);
    signal duration         : int_array := (others => 20);
    type nat_array is array(0 to 7) of natural;
    signal shift_bits       : nat_array := (others => 0);
	 signal voltage_changed  : std_logic_vector(7 downto 0) := (others => '1');
    
    type voltage_array is array(7 downto 0) of std_logic_vector(15 downto 0);
    signal manual_voltages : voltage_array;

    -- ram --
	 signal ram_clk_select : std_logic := '0';
    signal ram_clk     : std_logic;
    signal ram_we      : std_logic;
    signal ram_addr    : integer range 0 to 10000 := 0; -- update ram_data_depth too!!
    signal ram_data_i  : std_logic_vector(15 downto 0);
    signal ram_data_o  : std_logic_vector(47 downto 0);

    component ram
    generic(
        data_depth : integer;
        data_width : integer
    );
    port(
        clock         : in std_logic;
        we            : in std_logic;
        address       : in integer range 0 to data_depth - 1;
        data_i        : inout std_logic_vector(data_width - 1 downto 0);
        data_o        : out std_logic_vector(3*data_width - 1 downto 0)
    );
    end component;

begin 

hi_muxsel <= '0';

--clk <= ti_clk;
--ram_clk <= ti_clk;

manual_voltages(0) <= ep01wire;
manual_voltages(1) <= ep02wire;
manual_voltages(2) <= ep03wire;
manual_voltages(3) <= ep04wire;
manual_voltages(4) <= ep05wire;
manual_voltages(5) <= ep06wire;
manual_voltages(6) <= ep07wire;
manual_voltages(7) <= ep08wire;

state <= idle when ep00wire(1 downto 0) = "00" else
         load when ep00wire(1 downto 0) = "01" else
         run when (ep00wire(1 downto 0) = "10" and trigger = '1') else
         ready;
			
	 process(ti_clk) is
	 variable count: integer range 0 to 3 := 0;
    begin
		if falling_edge(ti_clk) then
			if count < 2 then
				count := count + 1;
				clk <= '0';
			elsif count = 2 then
				count := count + 1;
				clk <= '1';
			else
				count := 0;
				clk <= '1';
			end if;
		end if;
	 end process;
	 
	 process(ti_clk) is
    begin
		if falling_edge(ti_clk) then
			if state = idle or state = run then
				ram_clk_select <= '1';
--				ram_clk_select <= '0';
			else
				ram_clk_select <= '0';
			end if;
		end if;
	 end process;
			
	 process(state) is
    begin
		case state is
        when idle =>
            led(0) <= '1';
				led(1) <= '1';
        when load =>
            led(0) <= '0';
				led(1) <= '1';
        when ready =>
            led(0) <= '1';
				led(1) <= '0';
		  when run =>
				led(0) <= '0';
				led(1) <= '0';
		end case;
	 end process;

    -- we have eight dacs. need a process to write a new voltage to each dac and then update them all at the same time.
    process(state, clk, latch_count, dac_count, voltage_changed) is
    begin
        if falling_edge(clk) then
            case (state) is
                when run =>
                    if latch_count = 0 then 
								if voltage_changed(dac_count) = '1' then
									dac_cs(dac_count) <= '0';
								else
									dac_cs(dac_count) <= '1';
								end if;
                        latch_count <= latch_count + 1;
--                        ldac(dac_count) <= '1';
                    elsif latch_count = 1 then
                        dac_cs(dac_count) <= '1';
 --                       ldac(dac_count) <= '0';
                        if dac_count < 7 then
                            dac_count <= dac_count + 1;
                            latch_count <= 0;
                        else 
                            latch_count <= latch_count + 1;
                            dac_count <= 0;
                        end if;
						  elsif latch_count = 2 then
                        latch_count <= latch_count + 1;
						  elsif latch_count = 3 then
								if or_reduce(voltage_changed) = '1' then
									ldac <= '1';
								end if;
                        latch_count <= latch_count + 1;
                    else
                        ldac <= '0';
                        latch_count <= 0;
                    end if;

                when others =>
                    dac_cs <= (others => '1');
                    ldac <= '0';
                    latch_count <= 0;
            end case;
        end if;
    end process;


    -- control dacbus
    process (state, clk, dac_count, next_voltage, step_size, ticks_til_update, shift_bits, ep09wire, dac_bus, voltage_changed) is
    begin
        if falling_edge(clk) then
            if (state = run) and (ep09wire(dac_count) = '0') then
					if voltage_changed(dac_count) = '1' then
						dac_bus <= std_logic_vector(to_unsigned(
									  next_voltage(dac_count) - to_integer(shift_right(to_signed(step_size(dac_count), 48)*to_signed(ticks_til_update(dac_count), 48), shift_bits(dac_count)))
                             , 16));
					else
						dac_bus <= dac_bus;
					end if;
            else 
                dac_bus <= manual_voltages(dac_count);
            end if;
        end if;
    end process;
   

    -- control dac_bus
    process(state, clk) is
	 variable delta_voltage: integer range 0 to 2**16-1 := 0;
    begin
        if falling_edge(clk) then
            case (state) is 
                when run =>
                    case latch_count is
                        when 0 =>
                            if ticks_til_update(dac_count) <= 0 then
                                if to_integer(unsigned(ram_data_o(47 downto 16))) = 0 then -- done with the current sequence
                                    null;
                                else -- not done with sequence, advance 
                                    sequence_count <= sequence_count + 1;
                                    ticks_til_update(dac_count) <= to_integer(unsigned(ram_data_o(47 downto 16)));
                                    duration(dac_count) <= to_integer(unsigned(ram_data_o(47 downto 16)));
                                    step_size(dac_count) <= to_integer(signed(ram_data_o(15 downto 0)));
                                    shift_bits(dac_count) <= log2(to_integer(unsigned(ram_data_o(47 downto 16))))-1;
                                end if;
                            end if;
                        when 1 => 
                            if ticks_til_update(dac_count) = duration(dac_count) then -- if we just read new values
											delta_voltage := to_integer(shift_right(to_signed(step_size(dac_count), 48)*to_signed(duration(dac_count), 48), shift_bits(dac_count)));
										   next_voltage(dac_count) <= next_voltage(dac_count) + delta_voltage;
										   if delta_voltage = 0 then
											   voltage_changed(dac_count) <= '0';
										    else
											   voltage_changed(dac_count) <= '1';
										    end if;
                            end if;
                        when 4 =>
                            ticks_til_update(0) <= ticks_til_update(0) - 1;
                            ticks_til_update(1) <= ticks_til_update(1) - 1;
                            ticks_til_update(2) <= ticks_til_update(2) - 1;
                            ticks_til_update(3) <= ticks_til_update(3) - 1;
                            ticks_til_update(4) <= ticks_til_update(4) - 1;
                            ticks_til_update(5) <= ticks_til_update(5) - 1;
                            ticks_til_update(6) <= ticks_til_update(6) - 1;
                            ticks_til_update(7) <= ticks_til_update(7) - 1;
                        when others => -- other latch_count 
                            null;
                    end case;
                when others => -- other states
                    shift_bits <= (others => 0);
                    next_voltage <= (others => 2**15);
                    step_size <= (others => 0);
                    ticks_til_update <= (others => 5);
                    sequence_count <= 0;
            end case;
        end if;
    end process;


    --control ram_data_i, ram_we
    process (ram_clk, state, ep80write, ep80pipe) is
    begin
        if falling_edge(ram_clk) then
            case (state) is
                when load => --load data from ep80pipe (USB) into ram
                    if ep80write = '1' then 
                        ram_we <= '1'; -- ep80wire goes hi for 1 ti_clk cycle if ep80pipe has been updated.
                    else 
                        ram_we <= '0';
                    end if;
                    ram_data_i <= ep80pipe(15 downto 0);
                when others => null;
            end case;
        end if;
    end process;

    --control ram_addr
    process(ram_clk, state, ep80write)
    begin 
        if rising_edge(ram_clk) then
            case state is
                when load =>
                    if ep80write = '1' then
                        ram_addr <= ram_addr + 1;
                    end if;
                when run =>
                    ram_addr <= 3*sequence_count;
                when others => 
                    ram_addr <= 0;
            end case;
        end if;
    end process;

ram_block : ram
generic map(
    data_depth => 10000, --update ram_addr too!
    data_width => 16)
port map(
    clock => ram_clk,
    data_i => ram_data_i,
    address => ram_addr,
    we => ram_we,
    data_o => ram_data_o
);

BUFGMUX_inst : BUFGMUX
generic map (
	CLK_SEL_TYPE => "SYNC"  -- Glitchles ("SYNC") or fast ("ASYNC") clock switch-over
)
port map (
	O => ram_clk,   -- 1-bit output: Clock buffer output
	I0 => ti_clk, -- 1-bit input: Clock buffer input (S=0)
	I1 => clk, -- 1-bit input: Clock buffer input (S=1)
	S => ram_clk_select    -- 1-bit input: Clock buffer select
);

-- Instantiate the okHost and connect endpoints
okHI : okHost port map (hi_in=>hi_in, hi_out=>hi_out, hi_inout=>hi_inout, ti_clk=>ti_clk, ok1=>ok1, ok2=>ok2);
okWO : okWireOR  generic map (N=>2) port map (ok2=>ok2, ok2s=>ok2s);
ep00 : okWireIn  port map (ok1=>ok1,                                ep_addr=>x"00", ep_dataout=>ep00wire);
ep01 : okWireIn  port map (ok1=>ok1,                                ep_addr=>x"01", ep_dataout=>ep01wire);
ep02 : okWireIn  port map (ok1=>ok1,                                ep_addr=>x"02", ep_dataout=>ep02wire);
ep03 : okWireIn  port map (ok1=>ok1,                                ep_addr=>x"03", ep_dataout=>ep03wire);
ep04 : okWireIn  port map (ok1=>ok1,                                ep_addr=>x"04", ep_dataout=>ep04wire);
ep05 : okWireIn  port map (ok1=>ok1,                                ep_addr=>x"05", ep_dataout=>ep05wire);
ep06 : okWireIn  port map (ok1=>ok1,                                ep_addr=>x"06", ep_dataout=>ep06wire);
ep07 : okWireIn  port map (ok1=>ok1,                                ep_addr=>x"07", ep_dataout=>ep07wire);
ep08 : okWireIn  port map (ok1=>ok1,                                ep_addr=>x"08", ep_dataout=>ep08wire);
ep09 : okWireIn  port map (ok1=>ok1,                                ep_addr=>x"09", ep_dataout=>ep09wire);
ep20 : okWireOut port map (ok1=>ok1, ok2=>ok2s(1*17-1 downto 0*17), ep_addr=>x"20", ep_datain=>ep20wire);
ep80 : okPipeIn  port map (ok1=>ok1, ok2=>ok2s(2*17-1 downto 1*17), ep_addr=>x"80", ep_dataout=>ep80pipe, 
                           ep_write=>ep80write);

end arch;
