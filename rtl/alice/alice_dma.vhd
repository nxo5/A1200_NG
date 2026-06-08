library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity alice_dma is
    Port (
        -- =============================================================
        -- 1. CLOCK- UND RESET-EINGÄNGE
        -- =============================================================
        clk_amiga     : in    std_logic; -- Der von alice_clk generierte 14,18 MHz Systemtakt
        reset         : in    std_logic; -- Globaler System-Reset
        
        -- =============================================================
        -- 2. INTERNE SPEISEBAHNEN VOM REGISTER- UND BEAM-MODUL (EINGÄNGE)
        -- =============================================================
        dma_enable_reg: in    std_logic_vector(15 downto 0); -- Inhalt des DMACON-Registers
        h_pos_tick    : in    unsigned(8 downto 0); -- Aktueller Videostrahl vom Beam-Counter
        v_pos_tick    : in    unsigned(8 downto 0); -- Aktuelle Videozeile vom Beam-Counter
        
        -- =============================================================
        -- 3. INTERNE KONTROLL-AUSGÄNGE ZUR CHIP-ZENTRALE (AUSGÄNGE)
        -- =============================================================
        dma_cpu_hold  : out   std_logic; -- Meldet an alice_clk, wenn die CPU pausieren muss
        
        -- =============================================================
        -- 4. INTERNE ADRESS- UND TRANSFERBAHNEN ZUR ALICE-HAUPTDATEI
        -- =============================================================
        internal_dma_req  : out   std_logic; -- '1' wenn ein Custom-Chip Daten anfordert
        internal_dma_rw   : out   std_logic; -- '1' für Lesen, '0' für Schreiben
        internal_dma_addr : out   std_logic_vector(31 downto 0); -- Generierte 32-Bit Wunschadresse
        
        -- =============================================================
        -- 5. NEU: PHYSISCHE KOPPLUNG DER CO-PROZESSOR-ANFORDURUNGEN (EINGÄNGE)
        -- =============================================================
        -- Blitter-Kanäle (Vom Blitter-Dach durchgereicht)
        blt_dma_req   : in    std_logic;
        blt_dma_rw    : in    std_logic;
        blt_dma_addr  : in    std_logic_vector(31 downto 0);
        blt_granted   : out   std_logic; -- Signalisiert dem Blitter die Slot-Freigabe
        
        -- Copper-Kanäle (Vom Copper-Dach durchgereicht)
        cop_dma_req   : in    std_logic;
        cop_dma_addr  : in    std_logic_vector(31 downto 0);
        cop_granted   : out   std_logic  -- Signalisiert dem Copper die Slot-Freigabe
    );
end alice_dma;

architecture Behavioral of alice_dma is

    -- Lokale Statussignale für die globalen DMACON-Schalter (Bits extrahieren)
    signal dma_master_en : std_logic; -- Bit 9: DMAEN (Globaler DMA-Hauptschalter)
    signal dma_blitter_en: std_logic; -- Bit 6: BLTEN (Blitter-DMA erlauben)
    signal dma_copper_en : std_logic; -- Bit 7: COPEN (Copper-DMA erlauben)
    signal blitter_nasty : std_logic; -- Bit 10: BLTPRI (Blitter-Nasty-Modus aktiv)

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
    -- Im Amiga-System besitzen Video-Refresh und Bitplanes unumstößliche
    -- Exklusiv-Slots, um Bildstörungen zu vermeiden. Wir simulieren dieses Raster 
    -- beispielhaft anhand der horizontalen Strahlposition (z.B. alle ungeraden CCKs).
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
                -- A: DISPLAY-DMA HAT VORRANG
                -- Hier würde die Adresse für die Grafikausgabe generiert werden.
                null;
                
            else
                -- B: FREIE ZEITSCHEIBE - CO-PROZESSOREN AN DER REIHE
                -- Priorität 1: Der Kupfer-Coprozessor (Copper)
                if cop_dma_req = '1' and dma_copper_en = '1' then
                    internal_dma_req  <= '1';
                    internal_dma_rw   <= '1'; -- Copper liest immer Befehle
                    internal_dma_addr <= cop_dma_addr;
                    cop_granted       <= '1'; -- Slot freigegeben!
                    dma_cpu_hold      <= '1'; -- CPU-Takt einfrieren, falls sie zugreifen wollte
                    
                -- Priorität 2: Der Grafik-Beschleuniger (Blitter)
                elsif blt_dma_req = '1' and dma_blitter_en = '1' then
                    internal_dma_req  <= '1';
                    internal_dma_rw   <= blt_dma_rw;
                    internal_dma_addr <= blt_dma_addr;
                    blt_granted       <= '1'; -- Slot freigegeben!
                    
                    -- Wenn der "Blitter-Nasty"-Modus (BLTPRI) aktiv ist, 
                    -- zwingt der Blitter die CPU in eine harte Dauerpause.
                    if blitter_nasty = '1' then
                        dma_cpu_hold <= '1';
                    end if;
                end if;
            end if;
        end if;
    end process;

end Behavioral;
