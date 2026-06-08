library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity alice_clk is
    Port (
        -- =============================================================
        -- 1. PHYSIKALISCHE MASTER-TAKTE VOM FPGA-BOARD (EINGÄNGE)
        -- =============================================================
        clk_sys       : in    std_logic; -- Der schnelle Basistakt des FPGA (z.B. 114 MHz)
        reset         : in    std_logic; -- Globaler System-Reset
        
        -- =============================================================
        -- 2. ORIGINALE SYSTEM-TAKTAUSGÄNGE FÜR DIE CORES (AUSGÄNGE)
        -- =============================================================
        clk_amiga     : out   std_logic; -- Der generierte 14,18 MHz Systemtakt für das Silizium
        clk_cpu       : out   std_logic; -- Der synchronisierte CPU-Takt (Von Alice blockierbar!)
        
        -- =============================================================
        -- 3. INTERNE UND EXTERNE PERIPHERIE-TAKTE (AUSGÄNGE)
        -- =============================================================
        e_clock_ce    : out   std_logic; -- Das verlangsamte E-Clock Takt-Enable (~1,418 MHz)
        cck_tick      : out   std_logic; -- Color Clock Tick (Taktpuls für die Grafik-Pipeline)
        ce_pix        : out   std_logic; -- Pixel-Clock-Enable für das MiSTer-Videosystem
        
        -- =============================================================
        -- 4. INTERNE KONTROLLE UND BLOCKIERUNG (Schnittstelle zum DMA)
        -- =============================================================
        dma_cpu_hold  : in    std_logic; -- '1' friert clk_cpu im nächsten Zyklus ein
        clk_ctrl_reg  : in    std_logic_vector(7 downto 0) -- Register-Zugang
    );
end alice_clk;

architecture Behavioral of alice_clk is

    -- Modulo-Zähler zur Erzeugung des 14,18 MHz Amiga-Taktes aus der clk_sys Domäne
    -- Hinweis: Wir nehmen hier beispielhaft ein gängiges 114-MHz-Raster an (Teilung durch 8)
    signal sys_clk_cnt   : unsigned(2 downto 0) := (others => '0');
    signal int_clk_amiga : std_logic := '0';

    -- NEU: Der historische Modulo-10-Teiler für das E-Clock Getriebe (0 bis 9)
    signal e_clock_cnt   : integer range 0 to 9 := 0;
    
    -- Interner Puffer für den CPU-Takt
    signal int_clk_cpu   : std_logic := '0';

begin

    -- Physikalische Durchschaltung der internen Taktsignale an die Ausgänge
    clk_amiga <= int_clk_amiga;

    -- =================================================================
    -- 1. GENERIERUNG DES 14,18-MHZ-AMIGA-BASISTAKTES (CLK_AMIGA)
    -- =================================================================
    -- Wir teilen den schnellen 114-MHz-Haupttakt des FPGA-Systems stabil 
    -- durch 8, um das synchrone PAL-Taktraster (14,1875 MHz) zu erhalten.
    process(clk_sys, reset)
    begin
        if reset = '1' then
            sys_clk_cnt   <= (others => '0');
            int_clk_amiga <= '0';
        elsif rising_edge(clk_sys) then
            if sys_clk_cnt = 3 then
                int_clk_amiga <= not int_clk_amiga; -- Taktflanke invertieren (Symmetrisch)
                sys_clk_cnt   <= (others => '0');
            else
                sys_clk_cnt <= sys_clk_cnt + 1;
            end if;
        end if;
    end process;

    -- =================================================================
    -- 2. HARDWARE-KOPPLUNG: E-CLOCK-GETRIEBE UND CPU-TAKTSTEUERUNG
    -- =================================================================
    -- Dieser Prozess läuft synchron in der generierten 14,18-MHz-Domäne.
    -- Er berechnet das 10er-Raster für die CIAs und bremst den CPU-Takt.
    process(int_clk_amiga, reset)
    begin
        if reset = '1' then
            e_clock_cnt <= 0;
            e_clock_ce  <= '0';
            int_clk_cpu <= '0';
            cck_tick    <= '0';
            ce_pix      <= '0';
        elsif rising_edge(int_clk_amiga) then
            -- Standard-Aktivierungsimpulse zurücksetzen
            e_clock_ce <= '0';
            cck_tick   <= '0';
            ce_pix     <= '0';

            -- A: Das mathematisch exakte Modulo-10-E-Clock-Raster
            -- Erzeugt einen Puls, der exakt 1 Amiga-Takt lang aktiv ist.
            if e_clock_cnt = 9 then
                e_clock_cnt <= 0;
                e_clock_ce  <= '1'; -- Signalisiert den CIA-Untermodulen den Herzschlag!
            else
                e_clock_cnt <= e_clock_cnt + 1;
            end if;

            -- B: Color-Clock-Tick und Pixeltakt-Aktivierung (1:4 Teilung zum Video)
            if e_clock_cnt = 0 or e_clock_cnt = 4 or e_clock_cnt = 8 then
                cck_tick <= '1'; -- Synchronisationspuls für die Grafik-Pipeline
                ce_pix   <= '1';
            end if;

            -- C: DIE ZYKLUSGENAUE CPU-TAKTBREMSE (Originalgetreues Hold-Verhalten)
            -- Wenn der DMA-Arbitrierungsblock meldet, dass die Custom-Chips den Bus
            -- beanspruchen (dma_cpu_hold = '1'), friert Alice den CPU-Takt im '0'-Zustand
            -- augenblicklich ein, bis der Grafik-Slot wieder freigegeben wird.
            if dma_cpu_hold = '1' then
                int_clk_cpu <= '0'; -- Takt einfrieren / CPU pausiert ohne Phasenverlust
            else
                int_clk_cpu <= not int_clk_cpu; -- Normaler CPU-Taktfortschritt (Teilung durch 2)
            end if;
        end if;
    end process;

    -- Den kontrollierten CPU-Takt permanent an das Interface-Pin ausgeben
    clk_cpu <= int_clk_cpu;

end Behavioral;
