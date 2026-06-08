library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity M68020_test_board is
    Port (
        clk           : in  std_logic;
        reset         : in  std_logic;
        
        -- Verbindung zu den physischen Pins der CPU
        cpu_addr      : in  std_logic_vector(31 downto 0);
        cpu_data_out  : in  std_logic_vector(31 downto 0);
        cpu_data_in   : out std_logic_vector(31 downto 0);
        cpu_as_n      : in  std_logic;
        cpu_ds_n      : in  std_logic;
        cpu_rw        : in  std_logic;
        
        -- Handshake-Signale zurück zur CPU
        cpu_dsack0_n  : out std_logic;
        cpu_dsack1_n  : out std_logic
    );
end M68020_test_board;

architecture Behavioral of M68020_test_board is
    -- Wartezyklen-Zähler
    signal wait_cnt   : integer range 0 to 7 := 0;
    signal bus_active : std_logic := '0';
    
    -- Interne Signale für das Handshake
    signal sig_dsack0 : std_logic := '1';
    signal sig_dsack1 : std_logic := '1';

begin

    -- Zuweisung der Handshake-Leitungen (32-Bit Port: DSACK0=0, DSACK1=0)
    cpu_dsack0_n <= sig_dsack0;
    cpu_dsack1_n <= sig_dsack1;

    -- Erkennung eines aktiven Buszugriffs
    bus_active <= '1' when (cpu_as_n = '0' and cpu_ds_n = '0') else '0';

    process(clk, reset)
        variable addr : unsigned(31 downto 0);
    begin
        if reset = '1' then
            wait_cnt     <= 0;
            sig_dsack0   <= '1';
            sig_dsack1   <= '1';
            cpu_data_in  <= (others => 'Z');
        elsif rising_edge(clk) then
            
            if bus_active = '1' then
                addr := unsigned(cpu_addr);
                
                -- -----------------------------------------------------
                -- 1. BEREICH: CHIP-RAM / VEKTOREN ($00000000 - $001FFFFF) -> 1 Wait-State
                -- -----------------------------------------------------
                if addr < x"00200000" then
                    if wait_cnt < 1 then
                        wait_cnt <= wait_cnt + 1;
                    else
                        -- Daten anlegen
                        if addr = x"00000000" then
                            cpu_data_in <= x"001FFFFF"; -- Initialer SSP (Top of Chip-RAM)
                        elsif addr = x"00000004" then
                            cpu_data_in <= x"00F80000"; -- Initialer PC (Kickstart Start)
                        else
                            cpu_data_in <= (others => '0'); -- Restliches RAM ist leer
                        end if;
                        -- 32-Bit Datenquittung (Beide DSACK auf '0')
                        sig_dsack0 <= '0';
                        sig_dsack1 <= '0';
                    end if;
                    
                -- -----------------------------------------------------
                -- 2. BEREICH: KICKSTART-ROM ($00F80000 - $00FFFFFF) -> 3 Wait-States
                -- -----------------------------------------------------
                elsif addr >= x"00F80000" and addr <= x"00FFFFFF" then
                    if wait_cnt < 3 then
                        wait_cnt <= wait_cnt + 1;
                    else
                        -- Unser optimierter Test-Opcode-Ablauf (32-Bit Packungen)
                        if addr = x"00F80000" then
                            cpu_data_in <= x"4E714E71"; -- NOP ($4E71) und NOP ($4E71)
                        elsif addr = x"00F80004" then
                            cpu_data_in <= x"60FA4E71"; -- BRA.B zurück zu $F80000 ($60FA) + NOP
                        else
                            cpu_data_in <= x"4E714E71"; -- Sicherheitsfall: Überall NOPs
                        end if;
                        -- 32-Bit ROM-Quittung
                        sig_dsack0 <= '0';
                        sig_dsack1 <= '0';
                    end if;
                    
                else
                    -- Unbekannter Adressbereich (Sofortige Quittung zur Sicherheit)
                    sig_dsack0 <= '0';
                    sig_dsack1 <= '0';
                    cpu_data_in <= (others => '0');
                end if;
            else
                -- Wenn der Bus inaktiv ist, Zähler zurücksetzen und Bus freigeben
                wait_cnt     <= 0;
                sig_dsack0   <= '1';
                sig_dsack1   <= '1';
                cpu_data_in  <= (others => 'Z');
            end if;
            
        end if;
    end process;

end Behavioral;
