library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- Einbindung des globalen CPU-Wörterbuchs
use work.M68020_pkg.all;

entity M68020_execute is
    Port (
        clk           : in  std_logic;
        reset         : in  std_logic;
        
        -- Eingänge von der Pipeline und dem Decoder
        stage_d       : in  std_logic_vector(15 downto 0); -- Ausführungsstufe der Pipeline
        op_is_nop     : in  std_logic;
        op_is_illegal : in  std_logic;
        
        -- Schnittstelle zur effektiven Adresse (EA)
        ea_address    : in  std_logic_vector(31 downto 0);
        ea_ready      : in  std_logic;
        
        -- Statussignale nach außen zur Hauptsteuerung
        exec_done     : out std_logic                      -- '1' wenn der Befehl fertig ausgeführt ist
    );
end M68020_execute;

architecture Behavioral of M68020_execute is

    -- Originales Register-File des 68020 (8x Daten, 8x Adresse à 32-Bit)
    type register_file_t is array (0 to 7) of long_t;
    signal reg_D : register_file_t := (others => (others => '0'));
    signal reg_A : register_file_t := (others => (others => '0'));

    -- Das originale Statusregister des 68020 (Condition Code Register - CCR Bits 4 bis 0)
    signal flag_X : std_logic := '0'; -- Extend
    signal flag_N : std_logic := '0'; -- Negative
    signal flag_Z : std_logic := '0'; -- Zero
    signal flag_V : std_logic := '0'; -- Overflow
    signal flag_C : std_logic := '0'; -- Carry

begin

    -- =================================================================
    -- ZYKLUSGENAUE ALU- UND REGISTERLOGIK
    -- =================================================================
    process(clk, reset)
    begin
        if reset = '1' then
            exec_done <= '0';
            -- Alle Universalregister auf 0 zurücksetzen
            reg_D <= (others => (others => '0'));
            reg_A <= (others => (others => '0'));
            -- Flags zurücksetzen
            flag_X <= '0'; flag_N <= '0'; flag_Z <= '0'; flag_V <= '0'; flag_C <= '0';
        elsif rising_edge(clk) then
            exec_done <= '0';

            -- NOP benötigt beim echten 68020 im internen Cache-Hit-Fall exakt 2 Taktzyklen
            if op_is_nop = '1' then
                exec_done <= '1'; -- Meldet der Hauptsteuerung den Abschluss des Zyklus
                
            -- Wenn ein illegaler Befehl aufschlägt, friert die Ausführung vorerst ein
            elsif op_is_illegal = '1' then
                exec_done <= '0'; -- Verhindert das Vorrücken im Code (Löst später Exception aus)
            end if;
        end if;
    end process;

end Behavioral;
