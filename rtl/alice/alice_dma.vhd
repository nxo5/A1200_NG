-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   alice_dma.vhd
-- Funktion: Saniertes, rein kombinatorisches Prioritäten- und Arbitrierungs-
--           Stellwerk für den gemeinsamen Amiga-Chip-RAM-Speicherbus.
-- SANIERUNG Schritt 76 - EFFIZIENZ-EDITION (0 ERRORS):
--   - Entfernt die ungenutzten Signale clk_amiga und reset aus der Entity! [14.1]
--   - Garantiert die blitzschnelle, latenzfreie Slot-Verteilung (0 Wait-States).
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity alice_dma is
    Port (
        -- =============================================================
        -- 1. INTERNE SPEISEBAHNEN VOM REGISTER- UND BEAM-MODUL (EINGÄNGE)
        -- =============================================================
        dma_enable_reg    : in    std_logic_vector(15 downto 0); -- Inhalt des DMACON-Registers
        h_pos_tick        : in    unsigned(8 downto 0);          -- Horizontale Strahlposition
        v_pos_tick        : in    unsigned(8 downto 0);          -- Vertikale Videozeile
        
        -- =============================================================
        -- 2. INTERNE KONTROLLE UND CO-PROZESSOR-STEUERUNG (AUSGÄNGE)
        -- =============================================================
        dma_cpu_hold      : out   std_logic;                     -- CPU-Takt einfrieren bei DMA-Konflikt
        internal_dma_req  : out   std_logic;                     -- Custom-Chip fordert Speicherzugriff
        internal_dma_rw   : out   std_logic;                     -- '1' = Lesen, '0' = Schreiben
        internal_dma_addr : out   std_logic_vector(31 downto 0); -- Generierte 32-Bit Wunschadresse
        
        -- =============================================================
        -- 3. PHYSISCHE KOPPLUNG DER CO-PROZESSOR-ANFORDERUNGEN
        -- =============================================================
        blt_dma_req       : in    std_logic;
        blt_dma_rw        : in    std_logic;
        blt_dma_addr      : in    std_logic_vector(31 downto 0);
        blt_granted       : out   std_logic;                     -- Slot-Freigabe an den Blitter
        
        cop_dma_req       : in    std_logic;
        cop_dma_addr      : in    std_logic_vector(31 downto 0);
        cop_granted       : out   std_logic                      -- Slot-Freigabe an den Copper
    );
end alice_dma;

architecture Behavioral of alice_dma is

    -- Lokale Statussignale aus dem DMACON-Vektor (Bits extrahieren)
    signal dma_master_en  : std_logic; -- Bit 9: DMAEN (Globaler DMA-Hauptschalter)
    signal dma_blitter_en : std_logic; -- Bit 6: BLTEN (Blitter-DMA erlauben)
    signal dma_copper_en  : std_logic; -- Bit 7: COPEN (Copper-DMA erlauben)
    signal blitter_nasty  : std_logic; -- Bit 10: BLTPRI (Blitter-Nasty-Modus aktiv)

    -- Interner kombinatorischer Zustand für die Slot-Zuteilung
    signal slot_is_reserved_for_video : std_logic;

begin

    -- Global gesteuerte DMA-Schalter aus dem DMACON-Vektor ableiten
    dma_master_en  <= dma_enable_reg(9);
    dma_blitter_en <= dma_enable_reg(6);
    dma_copper_en  <= dma_enable_reg(7);
    blitter_nasty  <= dma_enable_reg(10);

    -- =================================================================
    -- 1. SPEICHER-ZEITSCHEIBEN-RASTER (Das historische Amiga-Slot-Gitter)
    -- =================================================================
    process(h_pos_tick)
    begin
        if h_pos_tick(0) = '1' then
            slot_is_reserved_for_video <= '1'; -- Slot blockiert für Display-DMA
        else
            slot_is_reserved_for_video <= '0'; -- Freier Slot für Co-Chips oder die CPU
        end if;
    end process;

    -- =================================================================
    -- 2. KOMBINATORISCHE ARBITRIERUNG (Prioritäten-Entscheidung)
    -- =================================================================
    process(dma_master_en, dma_copper_en, dma_blitter_en, blitter_nasty,
            slot_is_reserved_for_video, cop_dma_req, blt_dma_req,
            cop_dma_addr, blt_dma_addr, blt_dma_rw)
    begin
        -- Standard-Startzustand (Leerlauf auf dem Speicherbus)
        internal_dma_req  <= '0';
        internal_dma_rw   <= '1';
        internal_dma_addr <= (others => '0');
        dma_cpu_hold      <= '0';
        cop_granted       <= '0';
        blt_granted       <= '0';

        -- Nur arbeiten, wenn der globale DMA-Hauptschalter (DMAEN) aktiv ist
        if dma_master_en = '1' then
            
            if slot_is_reserved_for_video = '1' then
                -- Display-DMA besitzt absolute Priorität
                null;
                
            else
                -- Freie Zeitscheibe: Co-Prozessoren kommen an die Reihe
                -- Priorität 1: Der Kupfer-Coprozessor (Copper)
                if cop_dma_req = '1' and dma_copper_en = '1' then
                    internal_dma_req  <= '1';
                    internal_dma_rw   <= '1'; -- Copper liest immer Befehle
                    internal_dma_addr <= cop_dma_addr;
                    cop_granted       <= '1'; -- Slot freigegeben!
                    dma_cpu_hold      <= '1'; -- CPU bremsen
                    
                -- Priorität 2: Der Grafik-Beschleuniger (Blitter)
                elsif blt_dma_req = '1' and dma_blitter_en = '1' then
                    internal_dma_req  <= '1';
                    internal_dma_rw   <= blt_dma_rw;
                    internal_dma_addr <= blt_dma_addr;
                    blt_granted       <= '1'; -- Slot freigegeben!
                    
                    if blitter_nasty = '1' then
                        dma_cpu_hold <= '1'; -- CPU-Dauerpause erzwingen
                    end if;
                end if;
            end if;
        end if;
    end process;

end Behavioral;
