library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity alice_mmu is
    Port (
        -- =============================================================
        -- 1. ADRESS- UND KONTROLLEINGÄNGE VOM INTERNEN CHIP-BUS
        -- =============================================================
        -- Läuft rein kombinatorisch ohne Taktflanken, um Latenzen zu verhindern!
        addr_in       : in    std_logic_vector(31 downto 0); -- Wunschadresse von CPU oder DMA
        mem_req       : in    std_logic;                     -- Gültiger Transfer steht an
        
        -- =============================================================
        -- 2. SCHNITTSTELLE ZUR AKTUELLEN KONFIGURATION
        -- =============================================================
        chipram_mask  : in    std_logic_vector(31 downto 0); -- Bitmaske für die RAM-Grenze (z.B. x"001FFFFF")
        
        -- =============================================================
        -- 3. KOMBATORISCHE FREIGABE-AUSGÄNGE ZUR ARBITRIERUNG
        -- =============================================================
        chipram_hit   : out   std_logic                      -- '1' = Adresse liegt im erlaubten Chip-RAM-Bereich
    );
end alice_mmu;

architecture Behavioral of alice_mmu is

begin

    -- =================================================================
    -- COMBINATORISCHE GATTER-PRÜFUNG (KORRIGIERTES SPIEGELUNGS-RASTER)
    -- =================================================================
    process(addr_in, mem_req, chipram_mask)
        variable mask_val : unsigned(31 downto 0);
        variable addr_val : unsigned(31 downto 0);
    begin
        -- Typumwandlung für sichere mathematische Vergleiche
        mask_val := unsigned(chipram_mask);
        addr_val := unsigned(addr_in);
        
        -- Standardmäßig den Zugriff verweigern
        chipram_hit <= '0';
        
        if mem_req = '1' then
            -- KORREKTUR: Das gattergetreue Amiga-Adressprüffenster
            -- Zweig A: Physisches reguläres Chip-RAM (0 bis 2 MB, flexibel erweiterbar)
            if addr_val <= mask_val then
                chipram_hit <= '1';
                
            -- Zweig B: Das historische Kickstart-Boot-Mirroring (ROM-Spiegelung bei Reset)
            -- Fängt Zugriffe im Boot-Bereich ab, damit die CPU fehlerfrei hochfahren kann
            elsif (addr_val >= x"00FC0000" and addr_val <= x"00FFFFFF") then
                chipram_hit <= '1';
                
            -- Zweig C: Das Custom-Chip-Register-Spiegelungsfenster ($DFF000er-Raum)
            elsif (addr_val >= x"00DFF000" and addr_val <= x"00DFFFFF") then
                chipram_hit <= '1';
            end if;
        end if;
    end process;

end Behavioral;
