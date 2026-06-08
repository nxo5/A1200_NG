library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity alice_regs is
    Port (
        -- =============================================================
        -- 1. CLOCK- UND RESET-EINGÄNGE
        -- =============================================================
        clk_amiga     : in    std_logic; -- Der von alice_clk generierte 14,18 MHz Systemtakt
        reset         : in    std_logic; -- Globaler System-Reset
        
        -- =============================================================
        -- 2. INTERNE SPEISEBAHNEN (EINGÄNGE VON DER ALICE-HAUPTDATEI)
        -- =============================================================
        internal_addr : in    std_logic_vector(11 downto 0); -- Custom-Register-Raum ($DFF000 bis $DFFFXX)
        internal_data_w: in   std_logic_vector(31 downto 0); -- 32-Bit Schreibdaten von der CPU
        chip_sel      : in    std_logic;                     -- Aktivierungssignal für den Registerbereich
        read_en       : in    std_logic;                     -- Lese-Impuls
        write_en      : in    std_logic;                     -- Schreib-Impuls
        
        -- =============================================================
        -- 3. INTERNE SPEISEBAHNEN (AUSGÄNGE ZUR ALICE-HAUPTDATEI)
        -- =============================================================
        internal_data_r: out  std_logic_vector(31 downto 0); -- Synchronisierte Lesedaten zurück zur CPU
        
        -- =============================================================
        -- 4. INTERNE KONTROLL-REGISTER FÜR DIE ANDEREN ALICE-UNTERMODULE
        -- =============================================================
        dma_enable_reg: out   std_logic_vector(15 downto 0); -- Der Inhalt des DMACON-Registers
        int_enable_reg: out   std_logic_vector(15 downto 0); -- Der Inhalt des INTENA-Registers
        
        -- =============================================================
        -- 5. INTERNE CHIP-DATENZUBRINGER (EINGÄNGE VON ANDEREN UNTERMODULEN)
        -- =============================================================
        h_pos_tick    : in    unsigned(8 downto 0); -- Aktueller Videostrahl für Registerabfrage ($DFF004)
        v_pos_tick    : in    unsigned(8 downto 0); -- Aktuelle Videozeile für Registerabfrage ($DFF006)
        
        -- NEU VERKABELT: Der Status-Eingang vom Grafik-Beschleuniger
        blt_done      : in    std_logic                      -- '1' signalisiert, dass der Blitter fertig ist
    );
end alice_regs;

architecture Behavioral of alice_regs is

    -- Die originalen systemweiten Kontrollregister des Amigas
    signal reg_dmacon : std_logic_vector(15 downto 0) := (others => '0'); 
    signal reg_intena : std_logic_vector(15 downto 0) := (others => '0'); 
    signal reg_intreq : std_logic_vector(15 downto 0) := (others => '0'); 

    -- Synchroner Registerpuffer für den Bus-Lesepfad
    signal reg_data_out_sync : std_logic_vector(31 downto 0) := (others => '0');

    -- NEU: Pipeline-Register für die Koppelung der Blitter-Done-Flanke
    signal blt_done_r1        : std_logic := '1';
    signal blt_done_r2        : std_logic := '1';

begin

    -- Die Schalterstellungen permanent an die anderen internen Alice-Module weiterreichen
    dma_enable_reg <= reg_dmacon;
    int_enable_reg <= reg_intena;

    -- Physische Zuweisung des synchronisierten Puffers nach außen
    internal_data_r <= reg_data_out_sync;

    -- =================================================================
    -- 1. SYNCHRONER SCHREIB-, INTERN- UND INTERRUPT-PROZESS
    -- =================================================================
    process(clk_amiga, reset)
    begin
        if reset = '1' then
            reg_dmacon  <= (others => '0');
            reg_intena  <= (others => '0');
            reg_intreq  <= (others => '0');
            blt_done_r1 <= '1';
            blt_done_r2 <= '1';
        elsif rising_edge(clk_amiga) then
            -- Flanken-Pipeline für den Blitter-Status fortschalten
            blt_done_r1 <= blt_done;
            blt_done_r2 <= blt_done_r1;

            -- A: CPU-SCHREIBZUGRIFFE AUF REGISTER (SET/CLR-Logik)
            if chip_sel = '1' and write_en = '1' then
                case internal_addr is
                    -- DMACONW ($DFF096)
                    when x"096" =>
                        for i in 0 to 14 loop
                            if internal_data_w(i) = '1' then
                                reg_dmacon(i) <= internal_data_w(15); 
                            end if;
                        end loop;
                        
                    -- INTENA ($DFF09A)
                    when x"09A" =>
                        for i in 0 to 14 loop
                            if internal_data_w(i) = '1' then
                                reg_intena(i) <= internal_data_w(15);
                            end if;
                        end loop;
                        
                    -- INTREQ ($DFF09C)
                    when x"09C" =>
                        for i in 0 to 14 loop
                            if internal_data_w(i) = '1' then
                                reg_intreq(i) <= internal_data_w(15);
                            end if;
                        end loop;
                        
                    when others => null;
                end case;
            
            -- B: HARDWARE-AUTOMATISMUS (Zünden des Blitter-Interrupts)
            -- Wenn blt_done von '0' auf '1' springt (steigende Flanke der Fertigmeldung),
            -- setzt Alice das Bit 6 im INTREQ-Register autonom auf '1'.
            elsif blt_done_r1 = '1' and blt_done_r2 = '0' then
                reg_intreq(6) <= '1'; -- Bit 6: BLIT Interrupt anfordern!
            end if;
        end if;
    end process;

    -- =================================================================
    -- 2. TAKTFLANKENSYNCHRONER LESE-PROZESS
    -- =================================================================
    process(clk_amiga, reset)
    begin
        if reset = '1' then
            reg_data_out_sync <= (others => '0');
        elsif rising_edge(clk_amiga) then
            reg_data_out_sync <= (others => '0'); 
            
            if chip_sel = '1' and read_en = '1' then
                case internal_addr is
                    when x"004" =>
                        reg_data_out_sync(15 downto 8) <= std_logic_vector(v_pos_tick(7 downto 0));
                        reg_data_out_sync(7 downto 0)  <= std_logic_vector(h_pos_tick(8 downto 1));
                        
                    when x"002" =>
                        reg_data_out_sync(15 downto 0) <= reg_dmacon;
                        reg_data_out_sync(31 downto 16) <= (others => '0');
                        
                    when x"01C" =>
                        reg_data_out_sync(15 downto 0) <= reg_intena;
                        reg_data_out_sync(31 downto 16) <= (others => '0');
                        
                    when x"01E" =>
                        reg_data_out_sync(15 downto 0) <= reg_intreq;
                        reg_data_out_sync(31 downto 16) <= (others => '0');
                        
                    when others =>
                        reg_data_out_sync <= (others => '0');
                end case;
            end if;
        end if;
    end process;

end Behavioral;
