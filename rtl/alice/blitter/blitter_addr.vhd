library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity blitter_addr is
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
        reg_write_en  : in    std_logic;                     -- CPU schreibt in ein Blitter-Register
        
        -- =============================================================
        -- 3. SCHNITTSTELLE ZUM KONTROLLWERK (INTERNE FSM-STEUERUNG)
        -- =============================================================
        chan_select   : in    std_logic_vector(1 downto 0);  -- "00"=A, "01"=B, "10"=C, "11"=D
        ptr_inc       : in    std_logic;                     -- Befehl zum Weiterschalten des Pointers (+/- 2 Byte)
        mod_add       : in    std_logic;                     -- Befehl zum Addieren des Zeilen-Modulos
        
        -- NEU: Linienmodus-Steuerung vom Rechenwerk und von den Registern
        line_mode_en  : in    std_logic;                     -- Schaltet die Adress-Logik auf Vektor-Schritte um
        line_sign_bit : in    std_logic;                     -- Das Vorzeichen des aktuellen Linienfehlers
        
        -- =============================================================
        -- 4. ADRESS-AUSGANG ZUR ÜBERGEORDNETEN CHIP-ZENTRALE
        -- =============================================================
        blt_dma_addr  : out   std_logic_vector(31 downto 0)  -- Berechnete 32-Bit Adresse ans Alice-Dach
    );
end blitter_addr;

architecture Behavioral of blitter_addr is

    -- Die originalen vier 32-Bit-Adresspointer des Amiga-Blitters
    signal bpl_ptr_a : unsigned(31 downto 0) := (others => '0'); 
    signal bpl_ptr_b : unsigned(31 downto 0) := (others => '0'); 
    signal bpl_ptr_c : unsigned(31 downto 0) := (others => '0'); 
    signal bpl_ptr_d : unsigned(31 downto 0) := (others => '0'); 

    -- Die originalen vier vorzeichenbehafteten 16-Bit-Moduloregister
    signal reg_bltamod : signed(15 downto 0) := (others => '0'); 
    signal reg_bltbmod : signed(15 downto 0) := (others => '0'); 
    signal reg_bltcmod : signed(15 downto 0) := (others => '0'); 
    signal reg_bltdmod : signed(15 downto 0) := (others => '0'); 

    -- Originale Amiga-Schalter für Richtung und Oktanten
    signal direction_desc : std_logic := '0';                     -- Bit 1 aus BLTCON1
    signal line_octant    : std_logic_vector(2 downto 0) := "000"; -- Bits 4 bis 2 aus BLTCON1
    
    -- Interner Adressbus für die kombinatorische Ausgabe
    signal active_addr : unsigned(31 downto 0);

begin

    -- =================================================================
    -- 1. CPU-REGISTER-SCHREIBPROZESS (Pointer, Modulos & Oktanten)
    -- =================================================================
    process(clk_amiga, reset)
    begin
        if reset = '1' then
            bpl_ptr_a      <= (others => '0'); bpl_ptr_b   <= (others => '0');
            bpl_ptr_c      <= (others => '0'); bpl_ptr_d   <= (others => '0');
            reg_bltamod    <= (others => '0'); reg_bltbmod <= (others => '0');
            reg_bltcmod    <= (others => '0'); reg_bltdmod <= (others => '0');
            direction_desc <= '0';
            line_octant    <= "000";
        elsif rising_edge(clk_amiga) then
            if reg_write_en = '1' then
                case reg_addr is
                    when x"04C" => bpl_ptr_a(31 downto 16) <= unsigned(reg_data_w(15 downto 0));
                    when x"050" => bpl_ptr_a(15 downto 0)  <= unsigned(reg_data_w(15 downto 0));
                    when x"04C" => bpl_ptr_b(31 downto 16) <= unsigned(reg_data_w(15 downto 0));
                    when x"04E" => bpl_ptr_b(15 downto 0)  <= unsigned(reg_data_w(15 downto 0));
                    when x"048" => bpl_ptr_c(31 downto 16) <= unsigned(reg_data_w(15 downto 0));
                    when x"04A" => bpl_ptr_c(15 downto 0)  <= unsigned(reg_data_w(15 downto 0));
                    when x"054" => bpl_ptr_d(31 downto 16) <= unsigned(reg_data_w(15 downto 0));
                    when x"056" => bpl_ptr_d(15 downto 0)  <= unsigned(reg_data_w(15 downto 0));
                    
                    when x"060" => reg_bltcmod <= signed(reg_data_w(15 downto 0));
                    when x"062" => reg_bltdmod <= signed(reg_data_w(15 downto 0));
                    when x"064" => reg_bltamod <= signed(reg_data_w(15 downto 0));
                    when x"066" => reg_bltbmod <= signed(reg_data_w(15 downto 0));
                    
                    when x"042" => 
                        direction_desc <= reg_data_w(1);
                        line_octant    <= reg_data_w(4 downto 2); -- Die originalen 3 Oktanten-Bits
                    when others => null;
                end case;
            
            -- =========================================================
            -- 2. OPERATIVER SCHALTSCHRITT (Blockmodus oder Linienmodus)
            -- =========================================================
            elsif ptr_inc = '1' then
                if line_mode_en = '1' then
                    -- DIE ORIGINALEN AMIGA-BRESENHAM-OKTANTEN-REGELN:
                    -- Je nach geladenem Oktant und dem Vorzeichen des Fehlers (line_sign_bit)
                    -- springen die Adress-Pointer im RAM horizontal, vertikal oder diagonal!
                    -- Hinweis: Der Linienzeichner steuert exklusiv den Zielkanal D.
                    case line_octant is
                        when "000" => -- Oktant 0
                            if line_sign_bit = '0' then bpl_ptr_d <= bpl_ptr_d + 2 + unsigned(resize(reg_bltcmod, 32));
                            else bpl_ptr_d <= bpl_ptr_d + 2; end if;
                        when "001" => -- Oktant 1
                            if line_sign_bit = '0' then bpl_ptr_d <= bpl_ptr_d + 2 + unsigned(resize(reg_bltcmod, 32));
                            else bpl_ptr_d <= bpl_ptr_d + unsigned(resize(reg_bltcmod, 32)); end if;
                        when "010" => -- Oktant 2
                            if line_sign_bit = '0' then bpl_ptr_d <= bpl_ptr_d - 2 + unsigned(resize(reg_bltcmod, 32));
                            else bpl_ptr_d <= bpl_ptr_d + unsigned(resize(reg_bltcmod, 32)); end if;
                        when "011" => -- Oktant 3
                            if line_sign_bit = '0' then bpl_ptr_d <= bpl_ptr_d - 2 + unsigned(resize(reg_bltcmod, 32));
                            else bpl_ptr_d <= bpl_ptr_d - 2; end if;
                        when others =>
                            -- Rückwärts-Oktanten (4-7) verhalten sich spiegelbildlich mit negativen Offsets
                            if line_sign_bit = '0' then bpl_ptr_d <= bpl_ptr_d + 2 - unsigned(resize(reg_bltcmod, 32));
                            else bpl_ptr_d <= bpl_ptr_d + 2; end if;
                    end case;
                else
                    -- Klassischer Amiga-Block-Kopierbetrieb (Wort-Schritte)
                    case chan_select is
                        when "00" => if direction_desc = '1' then bpl_ptr_a <= bpl_ptr_a - 2; else bpl_ptr_a <= bpl_ptr_a + 2; end if;
                        when "01" => if direction_desc = '1' then bpl_ptr_b <= bpl_ptr_b - 2; else bpl_ptr_b <= bpl_ptr_b + 2; end if;
                        when "10" => if direction_desc = '1' then bpl_ptr_c <= bpl_ptr_c - 2; else bpl_ptr_c <= bpl_ptr_c + 2; end if;
                        when "11" => if direction_desc = '1' then bpl_ptr_d <= bpl_ptr_d - 2; else bpl_ptr_d <= bpl_ptr_d + 2; end if;
                        when others => null;
                    end case;
                end if;
                
            elsif mod_add = '1' and line_mode_en = '0' then
                -- Modulo-Sprünge werden im Linienmodus komplett deaktiviert, 
                -- da Bresenham die Zeilensprünge permanent über BLTCMOD abwickelt!
                case chan_select is
                    when "00" => bpl_ptr_a <= unsigned(signed(bpl_ptr_a) + resize(reg_bltamod, 32));
                    when "01" => bpl_ptr_b <= unsigned(signed(bpl_ptr_b) + resize(reg_bltbmod, 32));
                    when "10" => bpl_ptr_c <= unsigned(signed(bpl_ptr_c) + resize(reg_bltcmod, 32));
                    when "11" => bpl_ptr_d <= unsigned(signed(bpl_ptr_d) + resize(reg_bltdmod, 32));
                    when others => null;
                end case;
            end if;
        end if;
    end process;

    -- =================================================================
    -- 3. COMBINATORISCHES ADRESS-ROUTING (Innen nach Außen)
    -- =================================================================
    with chan_select select
        active_addr <= bpl_ptr_a when "00",
                       bpl_ptr_b when "01",
                       bpl_ptr_c when "10",
                       bpl_ptr_d when "11",
                       (others => '0') when others;

    blt_dma_addr <= std_logic_vector(active_addr);

end Behavioral;
