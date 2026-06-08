library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

package M68020_pkg is

    -- Standardisierte Datentypen für die 68020-Architektur
    subtype byte_t is std_logic_vector(7 downto 0);   -- 8 Bit (Byte)
    subtype word_t is std_logic_vector(15 downto 0);  -- 16 Bit (Word)
    subtype long_t is std_logic_vector(31 downto 0);  -- 32 Bit (Longword)

    -- Die originalen Zustände der internen Ablaufsteuerung (FSM)
    type cpu_state_type is (
        ST_INIT,           -- Initialer Hardware-Zustand beim Einschalten
        ST_RESET_SSP,      -- Reset-Sequenz: Supervisor Stack Pointer holen (Adresse $0)
        ST_RESET_PC,       -- Reset-Sequenz: Start-Programmzähler holen (Adresse $4)
        ST_PREFETCH_1,     -- Pipeline füllen: Erstes Befehlswort laden
        ST_PREFETCH_2,     -- Pipeline füllen: Zweites Befehlswort laden
        ST_FETCH,          -- Regulärer Befehlsabruf / Cache-Prüfung
        ST_DECODE,         -- Befehlsdekodierung und Adressberechnung (EA)
        ST_EXECUTE         -- Ausführung des Befehls in der ALU / Register-Update
    );

    -- Die ersten elementaren Opcodes des 68020 (Inkrementeller Start)
    constant OP_NOP    : word_t := x"4E71"; -- No Operation
    constant OP_ILLEGAL: word_t := x"4AFC"; -- Illegal Instruction

end M68020_pkg;

package body M68020_pkg is
    -- Hier können später komplexe Funktionen zur Dekodierung eingefügt werden
end M68020_pkg;
