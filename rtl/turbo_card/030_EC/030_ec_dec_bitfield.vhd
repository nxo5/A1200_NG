-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   030_ec_dec_bitfield.vhd
-- Funktion: Der übergeordnete BITFIELD-Decoder-Wrapper des 68EC030.
--           Instanziiert den Opcode-Klassifizierer strukturell.
--           Steuert die zyklustreue Befehls-Freigabe an das Rechenwerk.
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity cpu_030_ec_dec_bitfield is
    Port (
        -- Takt und System-Zustand
        CLK             : in    std_logic;
        RESET_N         : in    std_logic;

        -- Schnittstelle nach außen zum Top-Decoder
        bitfield_en     : in    std_logic;                      -- Freigabe dieses Decoders
        opcode          : in    std_logic_vector(15 downto 0);  -- Aktueller Opcode aus der Pipeline
        
        -- Schnittstelle zum effektiven Adress-Decoder (EA-Modul)
        ea_calc_start   : out   std_logic;                      -- Trigger an EA-Modul senden
        ea_mode         : out   std_logic_vector(2 downto 0);   -- Geforderter EA-Modus
        ea_reg          : out   std_logic_vector(2 downto 0);   -- Gefordertes EA-Register
        ea_ready        : in    std_logic;                      -- EA-Modul meldet: Adresse berechnet
        ea_is_register  : in    std_logic;                      -- EA zeigt direkt auf ein Register
        
        -- Schnittstelle zum Rechenwerk (ALU)
        bf_alu_op       : out   std_logic_vector(7 downto 0);   -- Operations-ID für das Rechenwerk
        bf_ready        : out   std_logic                       -- Befehl komplett fertig ausgeführt
    );
end cpu_030_ec_dec_bitfield;

architecture structural of cpu_030_ec_dec_bitfield is

    -- =====================================================================
    -- KOMPONENTENDEKLARATION DER AUSGELAGERTEN KLASSIFIZIERUNG
    -- =====================================================================
    component cpu_030_ec_dec_bitfield_op
        Port (
            opcode          : in    std_logic_vector(15 downto 0);
            bitfield_en     : in    std_logic;
            bf_ea_calc      : out   std_logic;
            bf_alu_op       : out   std_logic_vector(7 downto 0);
            bf_offset_is_reg: out   std_logic;
            bf_width_is_reg : out   std_logic
        );
    end component;

    -- Interne Logikleitungen zur Verbindung des Bausteins
    signal sub_ea_calc      : std_logic;
    signal sub_alu_op       : std_logic_vector(7 downto 0);

begin

    -- Direktes kombinatorisches Weiterreichen an das EA-Modul
    ea_calc_start <= sub_ea_calc;
    ea_mode       <= opcode(5 downto 3); -- Bitfeld-Basisadresse liegt in Bits 5..3
    ea_reg        <= opcode(2 downto 0);  -- Bitfeld-Basisregister liegt in Bits 2..0

    -- =====================================================================
    -- INSTANZIIERUNG: Der kombinatorische Bitfeld-Klassifizierer
    -- =====================================================================
    i_bitfield_op_decoder : cpu_030_ec_dec_bitfield_op
        port map (
            opcode          => opcode,
            bitfield_en     => bitfield_en,
            bf_ea_calc      => sub_ea_calc,
            bf_alu_op       => sub_alu_op,
            bf_offset_is_reg=> open,
            bf_width_is_reg => open
        );

    -- =====================================================================
    -- SYNCHRONER ABLAUF-PROZESS: Befehlsausführung synchron takten
    -- =====================================================================
    process(CLK, RESET_N)
    begin
        if RESET_N = '0' then
            bf_ready  <= '0';
            bf_alu_op <= (others => '0');
            
        elsif rising_edge(CLK) then
            bf_ready  <= '0';
            
            if bitfield_en = '1' then
                -- Warten, bis das EA-Modul die Basisadresse berechnet hat
                if ea_ready = '1' or ea_is_register = '1' then
                    -- Operations-ID taktgenau an die ALU übergeben
                    bf_alu_op <= sub_alu_op;
                    
                    -- Befehl im selben Takt als erfolgreich ausgeführt quittieren
                    bf_ready  <= '1';
                end if;
            end if;
        end if;
    end process;

end structural;
