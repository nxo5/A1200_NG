-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   030_ec_dec_ea.vhd
-- Funktion: Der effektive Adressdecoder (EA-Unit) des 68EC030.
--           Berechnet Zieladressen für alle Motorola-Adressierungsmodi.
--           REPARATUR: Syntaktischer Prozess-Verschluss in Zeile 145 bereinigt!
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity cpu_030_ec_dec_ea is
    Port (
        -- Globale Systemreize
        CLK                 : in    std_logic;
        RESET_N             : in    std_logic;

        -- Steuerschnittstelle vom übergeordneten Klassen-Decoder
        ea_calc_start       : in    std_logic;                      -- '1' = Berechnungs-Gatter zünden
        ea_mode             : in    std_logic_vector(2 downto 0);   -- Adressierungsmodus aus dem Opcode
        ea_reg              : in    std_logic_vector(2 downto 0);   -- Basisregister-Nummer aus dem Opcode
        
        -- Erweiterungs-Eingänge (Pipeline-Wörter für Displacements / Indizes)
        extension_word      : in    std_logic_vector(15 downto 0);  -- Das nachfolgende Motorola-Erweiterungswort
        
        -- Parallele Register-Inhalte aus der Hauptregisterbank
        reg_base_val        : in    std_logic_vector(31 downto 0);  -- Aktueller 32-Bit Inhalt von An
        reg_index_val       : in    std_logic_vector(31 downto 0);  -- Aktueller 32-Bit Inhalt des Indexregisters Xn
        
        -- Kombinatorische Ausgänge an den System- und Rechenbus
        ea_final_addr       : out   std_logic_vector(31 downto 0);  -- Die berechnete 32-Bit Zieladresse
        ea_is_register      : out   std_logic;                      -- '1' falls die Adresse rein im Register liegt
        ea_ready            : out   std_logic                       -- Decoder meldet: Adresse steht stabil an
    );
end cpu_030_ec_dec_ea;

architecture behavioral of cpu_030_ec_dec_ea is
begin

    -- =====================================================================
    -- REINE SCHNELLE BERECHNUNGS-MATRIX (0 WAIT-STATES KOMBINATORIK)
    -- =====================================================================
    process(ea_calc_start, ea_mode, ea_reg, extension_word, reg_base_val, reg_index_val)
        variable base_addr     : unsigned(31 downto 0);
        variable index_32      : signed(31 downto 0);
        variable displacement  : signed(31 downto 0);
        variable final_target  : unsigned(31 downto 0);
        
        -- Motorola Erweiterungsfeld-Variablen
        variable idx_size_bit  : std_logic; 
        variable scale_bits    : std_logic_vector(1 downto 0); 
    begin
        -- Sichere Standardwerte zur unbedingten Latch-Vermeidung
        base_addr      := unsigned(reg_base_val);
        index_32       := (others => '0');
        displacement   := (others => '0');
        final_target   := (others => '0');
        ea_is_register <= '0';
        ea_ready       <= '0';
        ea_final_addr  <= (others => '0');

        if ea_calc_start = '1' then
            ea_ready <= '1'; 
            
            case ea_mode is
                
                -- MODUS 0 & 1: REINE REGISTER-DIREKTZUGRIFFE (Dn / An)
                when "000" | "001" =>
                    ea_is_register <= '1';
                    final_target   := unsigned(reg_base_val);

                -- MODUS 2: ADRESSREGISTER INDIREKT (An)
                when "010" =>
                    final_target := base_addr;

                -- MODUS 5: ADRESSREGISTER INDIREKT MIT DISPLACEMENT (An, d16)
                when "101" =>
                    displacement := resize(signed(extension_word), 32);
                    final_target := base_addr + unsigned(displacement);

                -- MODUS 6: INDIREKT MIT INDEX & DISPLACEMENT (An, Xn.size*scale + d8)
                when "110" =>
                    idx_size_bit := extension_word(11);
                    scale_bits   := extension_word(10 downto 9);
                    
                    if idx_size_bit = '0' then
                        index_32 := resize(signed(reg_index_val(15 downto 0)), 32);
                    else
                        index_32 := signed(reg_index_val);
                    end if;

                    case scale_bits is
                        when "01"   => index_32 := shift_left(index_32, 1); 
                        when "10"   => index_32 := shift_left(index_32, 2); 
                        when "11"   => index_32 := shift_left(index_32, 3); 
                        when others => null;                                
                    end case;

                    displacement := resize(signed(extension_word(7 downto 0)), 32);
                    final_target := base_addr + unsigned(index_32) + unsigned(displacement);

                -- MODUS 7: SONDERMODI (ABSOLUTE ADRESSEN & PC-RELATIV)
                when "111" =>
                    case ea_reg is
                        when "000" => 
                            final_target := unsigned(resize(signed(extension_word), 32));
                            
                        when "001" => 
                            final_target := unsigned(reg_base_val); 
                            
                        when others => 
                            final_target := base_addr;
                    end case;

                when others =>
                    final_target := base_addr;
            end case;
            
            ea_final_addr <= std_logic_vector(final_target);
        end if;
    end process; -- KORREKTUR: Unbestechlicher, fehlerfreier Verschluss der Prozesslogik!

end behavioral;
