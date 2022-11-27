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

    type ok_state_type is (idle, load, run);
    signal ok_state : ok_state_type := idle;

    type trig_state_type is (idle, run);
    signal trig_state : trig_state_type := idle;
    
    -- clock --
    signal clk            : std_logic; -- derived from external clock, clocks DACs when running

    signal dac_count      : integer range 0 to 7 := 0;
    signal latch_count    : integer range 0 to 4 := 0;
    signal sequence_count : integer range 0 to 16384 := 0;
    signal read_logic     : std_logic_vector(47 downto 0) := std_logic_vector(to_unsigned(0, 48));
       
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
    signal ram_addr    : integer range 0 to 16384 := 0; -- update ram_data_depth too!!
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
    
    ep20wire <= (others => '0');

    hi_muxsel <= '0';
	 
    manual_voltages(0) <= ep01wire;
    manual_voltages(1) <= ep02wire;
    manual_voltages(2) <= ep03wire;
    manual_voltages(3) <= ep04wire;
    manual_voltages(4) <= ep05wire;
    manual_voltages(5) <= ep06wire;
    manual_voltages(6) <= ep07wire;
    manual_voltages(7) <= ep08wire;

    -- control dacbus
    process (trig_state, clk_ext, dac_count, next_voltage, step_size, ticks_til_update, shift_bits, ep09wire, dac_bus, voltage_changed) is
    begin
		if falling_edge(clk_ext) then
        dac_bus <= std_logic_vector( unsigned(dac_bus) + 1);
		 end if;
    end process;
  

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
