library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- Einbindung des globalen CPU-Wörterbuchs
use work.M68020_pkg.all;

entity M68020_bus_ctrl is
    Port (
        clk           : in  std_logic;
        reset         : in  std_logic;
        
        -- Interne Schnittstelle zur CPU-Hauptsteuerung
        int_req       : in  std_logic;                     
        int_rw        : in  std_logic;                     
        int_addr      : in  std_logic_vector(31 downto 0); 
        int_data_w    : in  std_logic_vector(31 downto 0); 
        int_data_r    : out std_logic_vector(31 downto 0); 
        int_busy      : out std_logic;                     
        
        -- Physische Pins nach außen zum Amiga-Platinenbus (A1200_top.vhd)
        ext_addr      : out std_logic_vector(31 downto 0);
        ext_data_in   : in  std_logic_vector(31 downto 0);
        ext_data_out  : out std_logic_vector(31 downto 0);
        ext_as_n      : out std_logic;
        ext_ds_n      : out std_logic;
        ext_rw        : out std_logic; -- Bleibt sauber als out bestehen
        
        -- Die originalen Handshake-Pins des 68020
        dsack0_n      : in  std_logic;
        dsack1_n      : in  std_logic
    );
end M68020_bus_ctrl;

architecture Behavioral of M68020_bus_ctrl is
    -- Die originalen Bus-Zustände (Bus Cycles State Machine) des 68020
    type bus_state_t is (ST_IDLE, ST_S0, ST_S2, ST_S4, ST_SW, ST_S6);
    signal current_state : bus_state_t := ST_IDLE;
    
    signal reg_data_r    : std_logic_vector(31 downto 0) := (others => '0');
    
    -- Das interne Schatten-Signal löst das VHDL-Leseverbot für OUT-Ports
    signal int_ext_rw    : std_logic := '1';

begin

    -- Permanente Zuweisung des internen Steuersignals an den echten physischen Ausgangs-Pin
    ext_rw <= int_ext_rw;

    -- =================================================================
    -- ZYKLUSGENAUES 68020 BUS-PROTOKOLL
    -- =================================================================
    process(clk, reset)
    begin
        if reset = '1' then
            current_state <= ST_IDLE;
            int_busy      <= '0';
            int_data_r    <= (others => '0');
            reg_data_r    <= (others => '0');
            ext_addr      <= (others => 'Z'); 
            ext_data_out  <= (others => 'Z');
            ext_as_n      <= '1';
            ext_ds_n      <= '1';
            int_ext_rw    <= '1'; -- Nutzt das interne Signal
        elsif rising_edge(clk) then
            
            case current_state is
                
                -- Zustand IDLE: Warten auf eine Bus-Anforderung der CPU
                when ST_IDLE =>
                    int_busy <= '0';
                    ext_as_n <= '1';
                    ext_ds_n <= '1';
                    if int_req = '1' then
                        int_busy      <= '1';
                        ext_addr      <= int_addr;
                        int_ext_rw    <= int_rw;   -- Schreibt in das interne Signal
                        current_state <= ST_S0; 
                    else
                        ext_addr      <= (others => 'Z');
                        ext_data_out  <= (others => 'Z');
                    end if;
                    
                -- Zustand S0/S1: Adresse stabilisieren, Daten bei Schreibvorgang anlegen
                when ST_S0 =>
                    ext_as_n <= '0'; 
                    if int_ext_rw = '0' then       -- Liest jetzt fehlerfrei das interne Signal ab
                        ext_data_out <= int_data_w; 
                    end if;
                    current_state <= ST_S2;
                    
                -- Zustand S2/S3: Data Strobe aktivieren
                when ST_S2 =>
                    ext_ds_n      <= '0'; 
                    current_state <= ST_S4;
                    
                -- Zustand S4/S5: Die entscheidende Flanke für das DSACK-Handshake
                when ST_S4 =>
                    if dsack0_n = '1' and dsack1_n = '1' then
                        current_state <= ST_SW; 
                    else
                        if int_ext_rw = '1' then   -- Liest das interne Signal ab
                            reg_data_r <= ext_data_in;
                        end if;
                        current_state <= ST_S6; 
                    end if;
                    
                -- Zustand SW: Warteschleife (Generiert exakte Wait-States für den Chipsatz)
                when ST_SW =>
                    if dsack0_n = '0' or dsack1_n = '0' then
                        if int_ext_rw = '1' then   -- Liest das interne Signal ab
                            reg_data_r <= ext_data_in;
                        end if;
                        current_state <= ST_S6; 
                    else
                        current_state <= ST_SW; 
                    end if;
                    
                -- Zustand S6/S7: Bus-Signale wieder abbauen und Daten übergeben
                when ST_S6 =>
                    ext_as_n      <= '1'; 
                    ext_ds_n      <= '1';
                    int_data_r    <= reg_data_r; 
                    int_busy      <= '0';
                    current_state <= ST_IDLE;
                    
                when others =>
                    current_state <= ST_IDLE;
            end case;
        end if;
    end process;

end Behavioral;
