library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity lisa_shifter is
    Port (
        -- =============================================================
        -- 1. CLOCK- UND RESET-EINGÄNGE
        -- =============================================================
        clk_amiga     : in    std_logic; -- Der synchrone 14,18 MHz Systemtakt
        reset         : in    std_logic; -- Globaler System-Reset
        ce_pix        : in    std_logic; -- Pixelclock-Enable für den Serializer-Vorschub
        
        -- =============================================================
        -- 2. SCHNITTSTELLE ZUM REGISTER-PFAD (VON LISA.VHD)
        -- =============================================================
        reg_addr      : in    std_logic_vector(11 downto 0); -- Custom-Reg-Adresse ($DFFXXX)
        reg_data_w    : in    std_logic_vector(31 downto 0); -- 32-Bit Schreibdaten der CPU
        reg_write_en  : in    std_logic;                     -- CPU schreibt in ein Kontrollregister
        
        -- =============================================================
        -- 3. INTERNE GRAPHIK-ZUBRINGER VOM SPEICHER (VON LISA.VHD)
        -- =============================================================
        bpl_data_in   : in    std_logic_vector(31 downto 0); -- Gelesenes Grafikwort vom RAM-Bus
        bpl_chan_load : in    std_logic_vector(2 downto 0);  -- Steuert, welche der 8 Bitplanes geladen wird
        bpl_write_en  : in    std_logic;                     -- Impuls zum Laden der Bitplane-Daten
        
        -- SYNC-SIGNALE VOM BEAM-COUNTER (DURCHGEREICHT)
        hblank        : in    std_logic;                     -- Blockiert das Shifting außerhalb des sichtbaren Bereichs
        vblank        : in    std_logic;
        
        -- =============================================================
        -- 4. GEKAPSELTER AUSGANG DIREKT ZUR MISCHEBENE (LISA_VIDEO_MUX.VHD)
        -- =============================================================
        bpl_pixel_idx : out   std_logic_vector(7 downto 0)   -- Der kombinierte Bitplane-Index
    );
end lisa_shifter;

architecture Behavioral of lisa_shifter is

    -- Originale acht 32-Bit Bitplane-Datenregister des AGA-Chipsatzes
    type bpl_regs_t is array (0 to 7) of std_logic_vector(31 downto 0);
    signal reg_bpldat : bpl_regs_t := (others => (others => '0'));

    -- Das Kontrollregister BPLCON0 ($DFF100)
    signal reg_bplcon0 : std_logic_vector(15 downto 0) := (others => '0');
    
    -- Extrahierte Anzahl an aktiven Bitplanes (Bits 14 bis 12 in BPLCON0)
    signal active_bpl_count : integer range 0 to 8 := 0;

begin

    -- =================================================================
    -- 1. REGISTERAUSWERTUNG (Konfiguration der Bitplane-Tiefe)
    -- =================================================================
    process(clk_amiga, reset)
        variable bpl_bits : std_logic_vector(2 downto 0);
    begin
        if reset = '1' then
            reg_bplcon0 <= (others => '0');
            active_bpl_count <= 0;
        elsif rising_edge(clk_amiga) then
            if reg_write_en = '1' and reg_addr = x"100" then
                reg_bplcon0 <= reg_data_w(15 downto 0);
                
                bpl_bits := reg_data_w(14 downto 12);
                case bpl_bits is
                    when "000" => active_bpl_count <= 0;
                    when "001" => active_bpl_count <= 1;
                    when "010" => active_bpl_count <= 2;
                    when "011" => active_bpl_count <= 3;
                    when "100" => active_bpl_count <= 4;
                    when "101" => active_bpl_count <= 5;
                    when "110" => active_bpl_count <= 6;
                    when "111" => active_bpl_count <= 8; -- AGA 8-Bitplane-TrueColor-Modus!
                    when others => null;
                end case;
            end if;
        end if;
    end process;

    -- =================================================================
    -- 2. OPERATIVER LADE- UND SERIALISIERUNGSPROZESS
    -- =================================================================
    process(clk_amiga, reset)
        variable chan_idx : integer range 0 to 7;
    begin
        if reset = '1' then
            reg_bpldat <= (others => (others => '0'));
        elsif rising_edge(clk_amiga) then
            if bpl_write_en = '1' then
                chan_idx := to_integer(unsigned(bpl_chan_load));
                reg_bpldat(chan_idx) <= bpl_data_in;
                
            elsif ce_pix = '1' then
                if hblank = '0' and vblank = '0' then
                    for i in 0 to 7 loop
                        reg_bpldat(i) <= reg_bpldat(i)(30 downto 0) & '0';
                    end loop;
                end if;
            end if;
        end if;
    end process;

    -- =================================================================
    -- 3. KORRIGIERT: KOMBINATORISCHER PIXEL-INDEX GEN-KNOTEN
    -- =================================================================
    process(reg_bpldat, active_bpl_count)
        variable combined_idx : std_logic_vector(7 downto 0);
    begin
        combined_idx := (others => '0');
        
        -- KORREKTUR: Jedes Schieberegister-Bit (31) wird nun starr, fehlerfrei
        -- und lückenlos von 0 bis 7 aufsteigend auf den Index-Vektor gemappt!
        if active_bpl_count >= 1 then combined_idx(0) := reg_bpldat(0)(31); end if;
        if active_bpl_count >= 2 then combined_idx(1) := reg_bpldat(1)(31); end if;
        if active_bpl_count >= 3 then combined_idx(2) := reg_bpldat(2)(31); end if;
        if active_bpl_count >= 4 then combined_idx(3) := reg_bpldat(3)(31); end if;
        if active_bpl_count >= 5 then combined_idx(4) := reg_bpldat(4)(31); end if;
        if active_bpl_count >= 6 then combined_idx(5) := reg_bpldat(5)(31); end if; -- Korrigiert zu bpldat(5)
        if active_bpl_count >= 7 then combined_idx(6) := reg_bpldat(6)(31); end if; -- Korrigiert zu bpldat(6)
        if active_bpl_count >= 8 then combined_idx(7) := reg_bpldat(7)(31); end if; -- Korrigiert zu bpldat(7)
        
        bpl_pixel_idx <= combined_idx;
    end process;

end Behavioral;
