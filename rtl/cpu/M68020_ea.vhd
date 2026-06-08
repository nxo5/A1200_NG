library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- Einbindung des globalen CPU-Wörterbuchs
use work.M68020_pkg.all;

entity M68020_ea is
    Port (
        clk           : in  std_logic;
        reset         : in  std_logic;
        
        -- Eingänge von der Pipeline und dem Hauptdecoder
        stage_b       : in  std_logic_vector(15 downto 0); -- Lauscht auf Erweiterungswörter
        ea_field      : in  std_logic_vector(5 downto 0);  -- Adressierungsmodus aus dem Opcode
        ea_start      : in  std_logic;                     -- Impuls von der FSM, die Berechnung zu starten
        
        -- Statussignale und Ausgänge
        ea_ready      : out std_logic;                     -- '1' wenn die Adresse stabil berechnet ist
        ea_address    : out std_logic_vector(31 downto 0)  -- Die finale berechnete Adresse
    );
end M68020_ea;

architecture Behavioral of M68020_ea is
    -- Interne Zustandsmaschine für komplexe, mehrzyklische Adressierungen
    type ea_state_t is (ST_IDLE, ST_CALC_DONE);
    signal current_state : ea_state_t := ST_IDLE;
begin

    process(clk, reset)
    begin
        if reset = '1' then
            current_state <= ST_IDLE;
            ea_ready      <= '0';
            ea_address    <= (others => '0');
        elsif rising_edge(clk) then
            case current_state is
                
                when ST_IDLE =>
                    ea_ready <= '0';
                    if ea_start = '1' then
                        -- Für einfache Modi (z.B. Datenregister direkt) brauchen wir 0 Zusatzzyklen
                        -- Für unseren Start mit NOP springen wir sofort auf Fertig
                        current_state <= ST_CALC_DONE;
                    end if;
                    
                when ST_CALC_DONE =>
                    ea_ready      <= '1';
                    ea_address    <= (others => '0'); -- Temporärer Dummy-Wert
                    current_state <= ST_IDLE;
                    
                when others =>
                    current_state <= ST_IDLE;
            end case;
        end if;
    end process;

end Behavioral;
