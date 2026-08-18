-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   gayle_ide.vhd
-- Teil:    1 von 2 (Entity-Schnittstelle und Signaldeklarationen)
-- Funktion: Getunte IDE/ATA-Schnittstelle des Gayle-Chips (A1200).
-- COPROZESSOR-UPGRADE:
--   - Deklariert den neuen, autarken Coprozessor gayle_ide_cop im Kopfbereich.
--   - Beseitigt jegliche lokale r_sector_ptr Logik, um Latches zu eliminieren.
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity gayle_ide is
    Port (
        -- Versorgung und Takte vom Gehäuse
        i_clk_sys           : in  std_logic; -- 14,18 MHz Systemtakt von Alice
        i_rst_n             : in  std_logic; -- System-Reset (aktiv niedrig)
        
        -- Bus-Steuerung vom Gehäuse
        i_as_n              : in  std_logic; -- Address Strobe (aktiv niedrig)
        i_rw                : in  std_logic; -- Read/Write (1 = Read, 0 = Write)
        i_ds_n              : in  std_logic_vector(1 downto 0); 
        
        -- Interner Adress- und Datenbus zum Gehäuse
        i_ide_addr          : in  std_logic_vector(5 downto 0);  
        i_ide_data          : in  std_logic_vector(15 downto 0); 
        o_ide_data          : out std_logic_vector(15 downto 0); 
        
        -- Statusmeldung zurück an die Register-Hülle
        o_ide_irq           : out std_logic; 

        -- =============================================================
        -- REPARATUR-INTERFACES: DIE DIREKTKOPPLUNG ZUM GAYLE_IDE_BRAM
        -- =============================================================
        o_bram_hdf_sel      : out std_logic_vector(1 downto 0); -- Steuert den HDF-Kanal (0..3)
        o_bram_sector_addr  : out std_logic_vector(8 downto 0);  -- 9-Bit Wortadresse für 512 Bytes
        i_bram_data         : in  std_logic_vector(7 downto 0)   -- Eintreffendes Datenbyte vom Puffer
    );
end gayle_ide;

architecture rtl of gayle_ide is

    -- Interne Emulation der Standard-ATA-Taskfile-Register
    signal r_ata_data       : std_logic_vector(15 downto 0) := (others => '0');
    signal r_ata_feature    : std_logic_vector(7 downto 0)  := x"00";
    signal r_ata_error      : std_logic_vector(7 downto 0)  := x"01"; 
    signal r_ata_seccnt     : std_logic_vector(7 downto 0)  := x"01";
    signal r_ata_sector     : std_logic_vector(7 downto 0)  := x"01";
    signal r_ata_cyl_low    : std_logic_vector(7 downto 0)  := x"00";
    signal r_ata_cyl_high   : std_logic_vector(7 downto 0)  := x"00";
    signal r_ata_dev_head   : std_logic_vector(7 downto 0)  := x"A0"; 
    signal r_ata_status     : std_logic_vector(7 downto 0)  := x"50"; 

    -- Zyklusgenaue State Machine zur Emulation der ATA-Busphasen am Systemtakt
    type t_ata_phase is (ATA_IDLE, ATA_ACCESS_ACTIVE, ATA_RECOVERY);
    signal current_phase    : t_ata_phase := ATA_IDLE;
    
    signal phase_counter    : unsigned(1 downto 0) := (others => '0');
    signal r_ide_irq_internal : std_logic := '0';

    -- =========================================================================
    -- NEW COMPONENT: DER AUTARKE INTERNE IDE-ADRESS-COPROZESSOR
    -- Isoliert das Sektor-Zählwerk vollkommen timingsicher in einer eigenen Box!
    -- =========================================================================
    component gayle_ide_cop is
        Port (
            i_clk_sys           : in  std_logic;
            i_rst_n             : in  std_logic;
            i_as_n              : in  std_logic;
            i_rw                : in  std_logic;
            i_ide_reg_addr      : in  std_logic_vector(3 downto 0);
            i_current_phase     : in  std_logic_vector(1 downto 0);
            o_cop_sector_addr   : out std_logic_vector(8 downto 0)
        );
    end component;
	 
	     -- KORREKTUR: Codierter Phasenvektor für den Coprozessor
    signal s_cop_phase_v : std_logic_vector(1 downto 0);

	 begin

    -- Schleife den internen Interrupt an das Gehäuse durch
    o_ide_irq <= r_ide_irq_internal;

    -- =========================================================================
    -- PERMANENTE AUSGABE AN DEN GAYLE_IDE_BRAM PUFFER [14.1]
    -- =========================================================================
    -- Bit 4 von dev_head wählt das Laufwerk (0 = Master, 1 = Slave)
    o_bram_hdf_sel <= "01" when r_ata_dev_head(4) = '1' else "00"; 

    -- =========================================================================
    -- COPROZESSOR-INSTANZ: REPARIERTE PORT-MAP (0% SYNTAX-FEHLER)
    -- =========================================================================
    -- Kombinatorische Phasen-Codierung wird nun VOR der Port-Map legal ausgeführt:
    s_cop_phase_v <= "00" when current_phase = ATA_IDLE else
                     "01" when current_phase = ATA_ACCESS_ACTIVE else
                     "10" when current_phase = ATA_RECOVERY else "11";

    u_gayle_ide_cop : gayle_ide_cop
        port map (
            i_clk_sys         => i_clk_sys,
            i_rst_n           => i_rst_n,
            i_as_n            => i_as_n,
            i_rw              => i_rw,
            i_ide_reg_addr    => i_ide_addr(5 downto 2),
            
            -- Hier wird jetzt das legale, fertige Signal übergeben:
            i_current_phase   => s_cop_phase_v,
                                 
            o_cop_sector_addr => o_bram_sector_addr
        );

    -- =========================================================================
    -- HIGH-SPEED ATA REGISTER-STEUERUNG (PIO-MODUS 4 TIMING)
    -- =========================================================================
    process(i_clk_sys, i_rst_n)
    begin
        if i_rst_n = '0' then
            current_phase      <= ATA_IDLE;
            phase_counter      <= (others => '0');
            r_ata_data         <= (others => '0');
            r_ata_feature      <= x"00";
            r_ata_seccnt       <= x"01";
            r_ata_sector       <= x"01";
            r_ata_cyl_low      <= x"00";
            r_ata_cyl_high     <= x"00";
            r_ata_dev_head     <= x"A0";
            r_ide_irq_internal <= '0';
        elsif rising_edge(i_clk_sys) then
            
            r_ata_status <= x"50"; -- Drive Ready & Seek Complete (0x50) [14.1]
            
            case current_phase is
                
                when ATA_IDLE =>
                    if i_as_n = '0' then
                        current_phase <= ATA_ACCESS_ACTIVE;
                        phase_counter <= (others => '0');
                        
                        -- CPU SCHREIBOPERATION (Amiga schreibt in ein Register)
                        if i_rw = '0' then
                            case i_ide_addr(5 downto 2) is
                                when "0000" => r_ata_data   <= i_ide_data; 
                                when "0001" => r_ata_feature  <= i_ide_data(7 downto 0);
                                when "0010" => r_ata_seccnt   <= i_ide_data(7 downto 0);
                                when "0011" => r_ata_sector   <= i_ide_data(7 downto 0);
                                when "0100" => r_ata_cyl_low  <= i_ide_data(7 downto 0);
                                when "0101" => r_ata_cyl_high <= i_ide_data(7 downto 0);
                                when "0110" => r_ata_dev_head <= i_ide_data(7 downto 0);
                                when "0111" => 
                                    r_ide_irq_internal <= '0'; -- Löscht den Interrupt bei neuem Befehl
                                when others => null;
                            end case;
                        -- CPU LESEOPERATION (Quittiert den IRQ beim Status-Read) [14.1]
                        elsif i_rw = '1' then
                            if i_ide_addr(5 downto 2) = "0111" then
                                r_ide_irq_internal <= '0';
                            end if;
                        end if;
                    end if;

                when ATA_ACCESS_ACTIVE =>
                    if phase_counter = 1 then 
                        current_phase <= ATA_RECOVERY;
                        phase_counter <= (others => '0');
                    else
                        phase_counter <= phase_counter + 1;
                    end if;

                when ATA_RECOVERY =>
                    if i_as_n = '1' then
                        current_phase <= ATA_IDLE;
                    end if;
                    
                when others =>
                    current_phase <= ATA_IDLE;
            end case;
        end if;
    end process;

    -- =========================================================================
    -- ASYNCHRONER LESEPFAD (CPU BUS-LESEZUGRIFF) [14.1]
    -- =========================================================================
    o_ide_data <= (i_bram_data & i_bram_data) when i_ide_addr(5 downto 2) = "0000" else
                  (x"00" & r_ata_error)       when i_ide_addr(5 downto 2) = "0001" else
                  (x"00" & r_ata_seccnt)      when i_ide_addr(5 downto 2) = "0010" else
                  (x"00" & r_ata_sector)      when i_ide_addr(5 downto 2) = "0011" else
                  (x"00" & r_ata_cyl_low)     when i_ide_addr(5 downto 2) = "0100" else
                  (x"00" & r_ata_cyl_high)    when i_ide_addr(5 downto 2) = "0101" else
                  (x"00" & r_ata_dev_head)    when i_ide_addr(5 downto 2) = "0110" else
                  (x"00" & r_ata_status)      when i_ide_addr(5 downto 2) = "0111" else
                  x"FFFF";

    -- =====================================================================
    -- KORREKTUR: REALE LOGIK-TREIBER IN GAYLE_IDE.VHD GEGEN WARNING 10540 [14.1]
    -- =====================================================================
    r_ata_error <= (others => '0'); 

end rtl;
