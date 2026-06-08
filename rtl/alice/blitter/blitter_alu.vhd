library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity blitter_alu is
    Port (
        -- =============================================================
        -- 1. CLOCK- UND RESET-EINGÄNGE
        -- =============================================================
        clk_amiga     : in    std_logic; -- Der synchrone 14,18 MHz Systemtakt von Alice
        reset         : in    std_logic; -- Globaler System-Reset
        
        -- =============================================================
        -- 2. SCHNITTSTELLE ZUM REGISTER-PFAD (VON BLITTER.VHD)
        -- =============================================================
        reg_addr      : in    std_logic_vector(11 downto 0); -- Custom-Reg-Adresse ($DFFXXX)
        reg_data_w    : in    std_logic_vector(31 downto 0); -- 32-Bit Schreibdaten der CPU
        reg_write_en  : in    std_logic;                     -- CPU schreibt in ein Register
        
        -- =============================================================
        -- 3. INTERNE DIGITALE ZUBRINGER VOM SHIFTER (VON BLITTER_SHIFT.VHD)
        -- =============================================================
        shifted_data_a: in    std_logic_vector(15 downto 0); -- Kanal A (Vorbereitet)
        shifted_data_b: in    std_logic_vector(15 downto 0); -- Kanal B (Vorbereitet)
        buffered_data_c: in    std_logic_vector(15 downto 0); -- Kanal C (Vorbereitet)
        
        -- =============================================================
        -- 4. KOMBATORISCHE FREIGABEN VOM KONTROLLWERK (VON BLITTER_FSM.VHD)
        -- =============================================================
        line_mode_en  : in    std_logic;                     -- Schaltet intern auf Linien-Vektorberechnung um
        alu_calc_tick : in    std_logic;                     -- FSM gibt Berechnung für diesen Schritt frei
        
        -- NEU: Schnittstelle zum Adressgenerator (blitter_addr.vhd)
        line_sign_bit : out   std_logic;                     -- Liefert das Vorzeichen des aktuellen Linienfehlers
        
        -- =============================================================
        -- 5. AUSGANGSKUPFERBAHNEN DIREKT ZUM SPEICHER-INTERFACE
        -- =============================================================
        alu_data_out  : out   std_logic_vector(15 downto 0); -- Das fertige Wort für Kanal D
        blitter_zero  : out   std_logic                      -- '1' wenn die gesamte Operation Null war
    );
end blitter_alu;

architecture Behavioral of blitter_alu is

    -- Originale 16-Bit Hardware-Kontrollregister des Amiga 1200
    signal reg_bltcon0 : std_logic_vector(15 downto 0) := (others => '0'); 
    signal reg_bltcon1 : std_logic_vector(15 downto 0) := (others => '0'); 
    
    -- Originale vorzeichenbehaftete 16-Bit Hardware-Modulo-Register für Bresenham
    signal reg_bltamod : signed(15 downto 0) := (others => '0'); -- $DFF064 (Wird als Sign_A genutzt)
    signal reg_bltbmod : signed(15 downto 0) := (others => '0'); -- $DFF066 (Wird als Sign_B genutzt)
    
    -- NEU: Signiertes 16-Bit Bresenham-Hardware-Fehlerregister (BLTAPTL)
    signal reg_bltaptl : signed(15 downto 0) := (others => '0'); -- $DFF052 (Bresenham Error Accumulator)
    
    -- Interne Akkumulatoren für das Amiga-Zero-Flag
    signal internal_zero : std_logic := '1';
    
    -- Interner kombinatorischer Datenbus für das Minterm-Rechenergebnis
    signal combined_minterms : std_logic_vector(15 downto 0);

begin

    -- Das Vorzeichen-Bit des aktuellen Linienfehlers (Bit 15) in Echtzeit ausgeben
    line_sign_bit <= reg_bltaptl(15);

    -- =================================================================
    -- 1. CPU-REGISTER-SCHREIB- UND RECHENPROZESS (Die Bresenham-Schleife)
    -- =================================================================
    process(clk_amiga, reset)
    begin
        if reset = '1' then
            reg_bltcon0   <= (others => '0');
            reg_bltcon1   <= (others => '0');
            reg_bltamod   <= (others => '0');
            reg_bltbmod   <= (others => '0');
            reg_bltaptl   <= (others => '0');
            internal_zero <= '1';
        elsif rising_edge(clk_amiga) then
            -- A: CPU-Schreibzugriffe auf die Register abfangen
            if reg_write_en = '1' then
                case reg_addr is
                    when x"040" => reg_bltcon0 <= reg_data_w(15 downto 0); -- BLTCON0
                    when x"042" => reg_bltcon1 <= reg_data_w(15 downto 0); -- BLTCON1
                    when x"052" => reg_bltaptl <= signed(reg_data_w(15 downto 0)); -- BLTAPTL (Fehler-Startwert)
                    when x"064" => reg_bltamod <= signed(reg_data_w(15 downto 0)); -- BLTAMOD
                    when x"066" => reg_bltbmod <= signed(reg_data_w(15 downto 0)); -- BLTBMOD
                    when x"058" => internal_zero <= '1'; -- Start über BLTSIZE setzt das Zero-Flag zurück
                    when others => null;
                end case;
            
            -- B: OPERATIVER RECHENTAKT (Bresenham-Schritt im Linienmodus)
            elsif alu_calc_tick = '1' then
                -- Das Zero-Flag mitführen, falls das Rechenergebnis ungleich Null ist
                if line_mode_en = '1' then
                    if shifted_data_a /= x"0000" then
                        internal_zero <= '0';
                    end if;
                    
                    -- DIE HARDWARE-BRESENHAM-SCHLEIFE:
                    -- Ist der aktuelle Fehler negativ (Bit 15 = '1'), addiere BLTAMOD.
                    -- Ist der Fehler positiv oder Null (Bit 15 = '0'), addiere BLTBMOD.
                    if reg_bltaptl(15) = '1' then
                        reg_bltaptl <= reg_bltaptl + reg_bltamod;
                    else
                        reg_bltaptl <= reg_bltaptl + reg_bltbmod;
                    end if;
                else
                    if combined_minterms /= x"0000" then
                        internal_zero <= '0';
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- =================================================================
    -- 2. KOMBINATORISCHE MINTERM-MATRIX (Die 256 Logik-Kombinationen)
    -- =================================================================
    gen_minterms: for i in 0 to 15 generate
        signal bit_index : std_logic_vector(2 downto 0);
    begin
        bit_index <= shifted_data_a(i) & shifted_data_b(i) & buffered_data_c(i);
        
        process(bit_index, reg_bltcon0)
        begin
            case bit_index is
                when "000" => combined_minterms(i) <= reg_bltcon0(0);
                when "001" => combined_minterms(i) <= reg_bltcon0(1);
                when "010" => combined_minterms(i) <= reg_bltcon0(2);
                when "011" => combined_minterms(i) <= reg_bltcon0(3);
                when "100" => combined_minterms(i) <= reg_bltcon0(4);
                when "101" => combined_minterms(i) <= reg_bltcon0(5);
                when "110" => combined_minterms(i) <= reg_bltcon0(6);
                when "111" => combined_minterms(i) <= reg_bltcon0(7);
                when others => combined_minterms(i) <= '0';
            end case;
        end process;
    end generate;

    -- =================================================================
    -- 3. ENTSCHEIDUNG UND STATUS-AUSGÄNGE
    -- =================================================================
    alu_data_out <= shifted_data_a when line_mode_en = '1' else combined_minterms;
    blitter_zero <= internal_zero;

end Behavioral;
