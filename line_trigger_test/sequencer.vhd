library IEEE;
use IEEE.std_logic_1164.all;
--use IEEE.std_logic_arith.all;
--use IEEE.std_logic_misc.all;
--use IEEE.std_logic_unsigned.all;
use IEEE.numeric_std.all;
use work.FRONTPANEL.all;

entity line_trigger_test is
	port (
        -- opal kelly --
		hi_in     : in    std_logic_vector(7 downto 0);
		hi_out    : out   std_logic_vector(1 downto 0);
		hi_inout  : inout std_logic_vector(15 downto 0);
		hi_muxsel : out   std_logic;
		-- ok peripherals --
        led    : out   std_logic_vector(7 downto 0);
		-- 100 MHz from PLL --
		clk_100 : in std_logic;	
        -- sequence out --
      line_trigger_in : in std_logic := '0';
		test_out : out std_logic := '1'
	);
end line_trigger_test;

architecture arch of line_trigger_test is
    -- opal kelly --
    signal ti_clk   : std_logic; -- 48MHz clk. USB data is sync'd to this.
	signal ok1      : std_logic_vector(30 downto 0);
	signal ok2      : std_logic_vector(16 downto 0);
	signal ok2s     : std_logic_vector(17*2-1 downto 0);
    -- ok usb --
	signal ep00wire : std_logic_vector(15 downto 0);
    signal ep01wire : std_logic_vector(15 downto 0);
    signal ep02wire : std_logic_vector(15 downto 0);
    signal ep03wire : std_logic_vector(15 downto 0);
    signal ep04wire : std_logic_vector(15 downto 0);
    signal ep05wire : std_logic_vector(15 downto 0);
    signal ep06wire : std_logic_vector(15 downto 0);
    signal ep07wire : std_logic_vector(15 downto 0);
    signal ep08wire : std_logic_vector(15 downto 0);
	signal ep20wire : std_logic_vector(15 downto 0);
    signal ep80pipe  : std_logic_vector(15 downto 0); 
    signal ep80write : std_logic; -- hi during communication
   	 
	 signal clk_1 : std_logic := '0';
	 
	 type state_t is (counting, debounce);
	 signal state : state_t := counting;
	 
	 signal counter : unsigned(15 downto 0) := (others => '0');
	 
	 attribute ASYNC_REG : string;
	 attribute RLOC : string;
	 
	 signal trigger : std_logic := '0';
	 signal trigger_reg : std_logic := '0';
	 signal trigger_reg_reg : std_logic := '0';
	 
	 -- Tells ISE to synthesize FFs
	 attribute ASYNC_REG of trigger_reg : signal is "TRUE";
	 attribute ASYNC_REG of trigger_reg_reg : signal is "TRUE";

begin

	hi_muxsel <= '0'; -- ok says so...
	led <= (others => '0');
	test_out <= '1';
	 
	 process (clk_100) is
		variable c : integer range 0 to 100 := 0;
	 begin
		if rising_edge(clk_100) then
			if (c < 50) then
				clk_1 <= '1';
				c := c + 1;
			elsif (c < 99) then
				clk_1 <= '0';
				c := c + 1;
			else
				c := 0;
			end if;
		end if;
	 end process;
	 
	process (clk_1) is
	begin
		if rising_edge(clk_1) then
			trigger_reg_reg <= line_trigger_in;
			trigger_reg <= trigger_reg_reg;
			trigger <= trigger_reg;
		end if;
	end process;
	 
	process(clk_1, state, trigger, trigger_reg) is
	begin
		if rising_edge(clk_1) then
			counter <= counter + 1;
			case state is
				when counting =>
					if trigger = '1' and trigger_reg = '0' then
						ep20wire <= std_logic_vector(counter);
						counter <= (others => '0');
						state <= debounce;
					end if;
				when debounce =>
					if counter > 2000 then
						state <= counting;
					end if;
			end case;
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
ep20 : okWireOut port map (ok1=>ok1, ok2=>ok2s(1*17-1 downto 0*17), ep_addr=>x"20", ep_datain=>ep20wire);
ep80 : okPipeIn  port map (ok1=>ok1, ok2=>ok2s(2*17-1 downto 1*17), ep_addr=>x"80", ep_dataout=>ep80pipe, 
                           ep_write=>ep80write);

end arch;
