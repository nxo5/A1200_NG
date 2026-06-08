library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- Einbindung des globalen CPU-Wörterbuchs
use work.M68020_pkg.all;

entity M68020_decode is
    Port (
        -- Eingang von Pipeline-Stage C (Befehlsdekodierung)
        stage_c       : in  std_logic_vector(15 downto 0);
        
        -- Rein bitbasierte Steuersignale (Execution Control Lines)
        op_is_nop     : out std_logic;
        op_is_illegal : out std_logic;
        
        -- Extrahiertes Feld für die effektive Adresse (Bits 5 bis 0 des Opcodes)
        ea_field      : out std_logic_vector(5 downto 0)
    );
end M68020_decode;

architecture Behavioral of M68020_decode is
begin

    -- Kombinatorisches Logiknetzwerk (PLA)
    process(stage_c)
    begin
        -- Standard-Zuweisung (Alles inaktiv)
        op_is_nop     <= '0';
        op_is_illegal <= '0';
        ea_field      <= stage_c(5 downto 0); -- Die unteren 6 Bit bestimmen fast immer die EA

        -- Bitmuster-Abgleich direkt über die Package-Konstanten
        if stage_c = OP_NOP then
            op_is_nop <= '1';
        elsif stage_c = OP_ILLEGAL then
            op_is_illegal <= '1';
        else
            -- Wenn das Bitmuster absolut unbekannt ist, feuert die Hardware "Illegal"
            op_is_illegal <= '1';
        end if;
    end process;

end Behavioral;
