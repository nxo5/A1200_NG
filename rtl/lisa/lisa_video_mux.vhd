library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity lisa_video_mux is
    Port (
        -- =============================================================
        -- 1. SCHNITTSTELLE ZUM REGISTER-PFAD (VON LISA.VHD)
        -- =============================================================
        reg_addr      : in    std_logic_vector(11 downto 0); -- Custom-Reg-Adresse ($DFFXXX)
        reg_data_w    : in    std_logic_vector(31 downto 0); -- 32-Bit Schreibdaten der CPU
        reg_write_en  : in    std_logic;                     -- CPU schreibt in ein Kontrollregister
        
        -- =============================================================
        -- 2. INTERNE ZUBRINGER VOM SHIFTER UND DEN SPRITES (EINGÄNGE)
        -- =============================================================
        bpl_pixel_idx : in    std_logic_vector(7 downto 0);  -- Serialisierter Index der Bitplanes
        sprite_pixel_idx : in std_logic_vector(3 downto 0);  -- Index des aktiven Sprites
        sprite_active    : in std_logic;                     -- Sprite-Pixel vorhanden
        sprite_bank_offset: in std_logic_vector(1 downto 0); -- Der AGA-Bank-Offset (SPRES)
        
        -- =============================================================
        -- 3. INTERNER FREIGABE-AUSGANG DIREKT ZUR PALETTE (AUSGANG)
        -- =============================================================
        final_color_idx : out  std_logic_vector(7 downto 0); -- Der finale Paletten-Index
        
        -- CONTROL-EINGÄNGE FÜR DIE AUSTASTUNG (VON LISA.VHD)
        hblank        : in    std_logic;                     -- '1' erzwingt harten Austast-Nullwert
        vblank        : in    std_logic
    );
end lisa_video_mux;

architecture Behavioral of lisa_video_mux is

    -- Originale Amiga-Steuerregister
    signal reg_bplcon0 : std_logic_vector(15 downto 0) := (others => '0'); 
    signal reg_bplcon2 : std_logic_vector(15 downto 0) := (others => '0'); 
    signal reg_bplcon3 : std_logic_vector(15 downto 0) := (others => '0'); 
    
    -- Extrahierte Steuersignale für die Mischebene
    signal dual_playfield_en : std_logic := '0';
    signal pf2_priority      : std_logic := '0';
    signal sprite_priority   : unsigned(2 downto 0) := (others => '0');
    signal pf2_color_offset  : std_logic_vector(2 downto 0) := "000";

begin

    -- =================================================================
    -- 1. REGISTERAUSWERTUNG (Konfiguration der Ebenen-Prioritäten)
    -- =================================================================
    process(reg_addr, reg_data_w, reg_write_en)
    begin
        if reg_write_en = '1' then
            case reg_addr is
                when x"100" => 
                    reg_bplcon0 <= reg_data_w(15 downto 0);
                    dual_playfield_en <= reg_data_w(10); 
                when x"104" => 
                    reg_bplcon2 <= reg_data_w(15 downto 0);
                    pf2_priority <= reg_data_w(6);       
                    sprite_priority <= unsigned(reg_data_w(2 downto 0)); 
                when x"106" =>
                    reg_bplcon3 <= reg_data_w(15 downto 0);
                    pf2_color_offset <= reg_data_w(12 downto 10); 
                when others => null;
            end case;
        end if;
    end process;

    -- =================================================================
    -- 2. ORIGINALGETREUE DUAL-PLAYFIELD UND SPRITE-ENTSCHEIDUNG
    -- =================================================================
    process(bpl_pixel_idx, sprite_active, sprite_pixel_idx, sprite_priority, sprite_bank_offset,
            dual_playfield_en, pf2_priority, pf2_color_offset, hblank, vblank)
        
        variable bpl_vector : std_logic_vector(7 downto 0);
        variable pf1_idx    : std_logic_vector(3 downto 0);
        variable pf2_idx    : std_logic_vector(3 downto 0);
        variable selected_pf_color : std_logic_vector(7 downto 0);
        variable pf1_has_pixel     : std_logic;
        variable pf2_has_pixel     : std_logic;
        
    begin
        bpl_vector := bpl_pixel_idx;

        -- A: Physische Austastlücken (HBlank/VBlank) erzwingen harte Digital-Null
        if hblank = '1' or vblank = '1' then
            final_color_idx <= (others => '0'); 
            
        else
            -- B: EBENEN-DEKODIERUNG (Echter Amiga-Dual-Playfield-Split)
            if dual_playfield_en = '1' then
                pf1_idx := bpl_vector(7) & bpl_vector(5) & bpl_vector(3) & bpl_vector(1);
                pf2_idx := bpl_vector(6) & bpl_vector(4) & bpl_vector(2) & bpl_vector(0);
                
                if pf1_idx /= "0000" then pf1_has_pixel := '1'; else pf1_has_pixel := '0'; end if;
                if pf2_idx /= "0000" then pf2_has_pixel := '1'; else pf2_has_pixel := '0'; end if;
                
                -- Playfield-Prioritäten-Entscheidung (PF2PRI-Auswertung)
                if pf2_priority = '1' and pf2_has_pixel = '1' then
                    selected_pf_color := "0" & pf2_color_offset & pf2_idx;
                elsif pf1_has_pixel = '1' then
                    selected_pf_color := "0000" & pf1_idx;
                elsif pf2_has_pixel = '1' then
                    selected_pf_color := "0" & pf2_color_offset & pf2_idx;
                else
                    selected_pf_color := (others => '0');
                end if;
            else
                selected_pf_color := bpl_vector;
            end if;

            -- C: SPRITE-OVERLAY-ENTSCHEIDUNG
            if sprite_active = '1' then
                if selected_pf_color = x"00" or sprite_priority = 7 then
                    final_color_idx <= sprite_bank_offset & "01" & sprite_pixel_idx;
                else
                    final_color_idx <= selected_pf_color;
                end if;
            else
                final_color_idx <= selected_pf_color;
            end if;
        end if;
    end process;

end Behavioral;
