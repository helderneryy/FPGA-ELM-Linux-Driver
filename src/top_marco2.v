module top_marco2 (

	// Clock
	input CLOCK_50,

	// Pinos da FPGA
	output [9:0] LEDR,
	input [3:0] KEY,
	input [9:0] SW,
	output [6:0] HEX0,
	output [6:0] HEX1,
	output [6:0] HEX2,
	output [6:0] HEX3,
	output [6:0] HEX4,
	output [6:0] HEX5,

	// Pinos do HPS DDR3 do HPS (memória do ARM)
	output [14:0] HPS_DDR3_ADDR,
	output [2:0] HPS_DDR3_BA,
	output HPS_DDR3_CK_P,
	output HPS_DDR3_CK_N,
	output HPS_DDR3_CKE,
	output HPS_DDR3_CS_N,
	output HPS_DDR3_RAS_N,
	output HPS_DDR3_CAS_N,
	output HPS_DDR3_WE_N,
	output HPS_DDR3_RESET_N,
	inout [31:0] HPS_DDR3_DQ,
	inout [3:0] HPS_DDR3_DQS_P,
	inout [3:0] HPS_DDR3_DQS_N,
	output HPS_DDR3_ODT,
	output [3:0] HPS_DDR3_DM,
	input HPS_DDR3_RZQ,
	
	// Pinos HPS I/O
	output HPS_ENET_GTX_CLK,
   inout HPS_ENET_MDIO,
   output HPS_ENET_MDC,
   input HPS_ENET_RX_CLK,
   input [3:0] HPS_ENET_RX_DATA,
   input HPS_ENET_RX_DV,
   output [3:0] HPS_ENET_TX_DATA,
   output HPS_ENET_TX_EN,
   inout HPS_ENET_INT_N,
   output HPS_FLASH_DCLK,
   output HPS_FLASH_NCSO,
   inout [3:0] HPS_FLASH_DATA,
   inout HPS_SD_CMD,
   output HPS_SD_CLK,
   inout [3:0] HPS_SD_DATA,
   input HPS_USB_CLKOUT,
   inout [7:0] HPS_USB_DATA,
   input HPS_USB_DIR,
   input HPS_USB_NXT,
   output HPS_USB_STP,
   output HPS_SPIM_CLK,
   input HPS_SPIM_MISO,
   output HPS_SPIM_MOSI,
   output HPS_SPIM_SS,
   input HPS_UART_RX,
   output HPS_UART_TX,
   inout HPS_I2C1_SDAT,
   inout HPS_I2C1_SCLK,
   inout HPS_I2C2_SDAT,
   inout HPS_I2C2_SCLK,
   inout HPS_CONV_USB_N,
   inout HPS_GSENSOR_INT,
   inout HPS_I2C_CONTROL,
   inout HPS_KEY,
   inout HPS_LED,
   inout HPS_LTC_GPIO
	
	

);

// Fios que conectam HPS e co-processador
wire [31:0] pio_data_in_wire;
wire [2:0] pio_signals_wire;
wire [31:0] pio_data_out_wire;

/* Sinais de reset entre HPS e FPGA
hps_reset_req: HPS solicita reset à FPGA (3 tipos: warm, debug, cold)
hps_fpga_reset_n: FPGA sinaliza ao HPS que está pronta (ativo em baixo) */
wire hps_fpga_reset_n;
wire [2:0] hps_reset_req;

/* Instancia o sistema HPS gerado pelo Platform Designer +
Conecta o processador ARM aos PIOs via bridge lightweight +
Os PIOs fazem a ponte entre o HPS e o CoProcessor via MMIO */
soc_system u0 (
    .clk_clk (CLOCK_50),
    .hps_0_f2h_cold_reset_req_reset_n (~hps_reset_req[2]),
    .hps_0_f2h_debug_reset_req_reset_n (~hps_reset_req[1]),
    .hps_0_f2h_stm_hw_events_stm_hwevents (27'b0),
    .hps_0_f2h_warm_reset_req_reset_n (~hps_reset_req[0]),
    .hps_0_h2f_reset_reset_n (hps_fpga_reset_n),
    .hps_0_hps_io_hps_io_emac1_inst_TX_CLK (HPS_ENET_GTX_CLK),
    .hps_0_hps_io_hps_io_emac1_inst_TXD0 (HPS_ENET_TX_DATA[0]),
    .hps_0_hps_io_hps_io_emac1_inst_TXD1 (HPS_ENET_TX_DATA[1]),
    .hps_0_hps_io_hps_io_emac1_inst_TXD2 (HPS_ENET_TX_DATA[2]),
    .hps_0_hps_io_hps_io_emac1_inst_TXD3 (HPS_ENET_TX_DATA[3]),
    .hps_0_hps_io_hps_io_emac1_inst_RXD0 (HPS_ENET_RX_DATA[0]),
    .hps_0_hps_io_hps_io_emac1_inst_MDIO (HPS_ENET_MDIO),
    .hps_0_hps_io_hps_io_emac1_inst_MDC (HPS_ENET_MDC),
    .hps_0_hps_io_hps_io_emac1_inst_RX_CTL (HPS_ENET_RX_DV),
    .hps_0_hps_io_hps_io_emac1_inst_TX_CTL (HPS_ENET_TX_EN),
    .hps_0_hps_io_hps_io_emac1_inst_RX_CLK (HPS_ENET_RX_CLK),
    .hps_0_hps_io_hps_io_emac1_inst_RXD1 (HPS_ENET_RX_DATA[1]),
    .hps_0_hps_io_hps_io_emac1_inst_RXD2 (HPS_ENET_RX_DATA[2]),
    .hps_0_hps_io_hps_io_emac1_inst_RXD3 (HPS_ENET_RX_DATA[3]),
    .hps_0_hps_io_hps_io_qspi_inst_IO0 (HPS_FLASH_DATA[0]),
    .hps_0_hps_io_hps_io_qspi_inst_IO1 (HPS_FLASH_DATA[1]),
    .hps_0_hps_io_hps_io_qspi_inst_IO2 (HPS_FLASH_DATA[2]),
    .hps_0_hps_io_hps_io_qspi_inst_IO3 (HPS_FLASH_DATA[3]),
    .hps_0_hps_io_hps_io_qspi_inst_SS0 (HPS_FLASH_NCSO),
    .hps_0_hps_io_hps_io_qspi_inst_CLK (HPS_FLASH_DCLK),
    .hps_0_hps_io_hps_io_sdio_inst_CMD (HPS_SD_CMD),
    .hps_0_hps_io_hps_io_sdio_inst_D0 (HPS_SD_DATA[0]),
    .hps_0_hps_io_hps_io_sdio_inst_D1 (HPS_SD_DATA[1]),
    .hps_0_hps_io_hps_io_sdio_inst_CLK (HPS_SD_CLK),
    .hps_0_hps_io_hps_io_sdio_inst_D2 (HPS_SD_DATA[2]),
    .hps_0_hps_io_hps_io_sdio_inst_D3 (HPS_SD_DATA[3]),
    .hps_0_hps_io_hps_io_usb1_inst_D0 (HPS_USB_DATA[0]),
    .hps_0_hps_io_hps_io_usb1_inst_D1 (HPS_USB_DATA[1]),
    .hps_0_hps_io_hps_io_usb1_inst_D2 (HPS_USB_DATA[2]),
    .hps_0_hps_io_hps_io_usb1_inst_D3 (HPS_USB_DATA[3]),
    .hps_0_hps_io_hps_io_usb1_inst_D4 (HPS_USB_DATA[4]),
    .hps_0_hps_io_hps_io_usb1_inst_D5 (HPS_USB_DATA[5]),
    .hps_0_hps_io_hps_io_usb1_inst_D6 (HPS_USB_DATA[6]),
    .hps_0_hps_io_hps_io_usb1_inst_D7 (HPS_USB_DATA[7]),
    .hps_0_hps_io_hps_io_usb1_inst_CLK (HPS_USB_CLKOUT),
    .hps_0_hps_io_hps_io_usb1_inst_STP (HPS_USB_STP),
    .hps_0_hps_io_hps_io_usb1_inst_DIR (HPS_USB_DIR),
    .hps_0_hps_io_hps_io_usb1_inst_NXT (HPS_USB_NXT),
    .hps_0_hps_io_hps_io_spim1_inst_CLK (HPS_SPIM_CLK),
    .hps_0_hps_io_hps_io_spim1_inst_MOSI (HPS_SPIM_MOSI),
    .hps_0_hps_io_hps_io_spim1_inst_MISO (HPS_SPIM_MISO),
    .hps_0_hps_io_hps_io_spim1_inst_SS0 (HPS_SPIM_SS),
    .hps_0_hps_io_hps_io_uart0_inst_RX (HPS_UART_RX),
    .hps_0_hps_io_hps_io_uart0_inst_TX (HPS_UART_TX),
    .hps_0_hps_io_hps_io_i2c0_inst_SDA (HPS_I2C1_SDAT),
    .hps_0_hps_io_hps_io_i2c0_inst_SCL (HPS_I2C1_SCLK),
    .hps_0_hps_io_hps_io_i2c1_inst_SDA (HPS_I2C2_SDAT),
    .hps_0_hps_io_hps_io_i2c1_inst_SCL (HPS_I2C2_SCLK),
    .hps_0_hps_io_hps_io_gpio_inst_GPIO09 (HPS_CONV_USB_N),
    .hps_0_hps_io_hps_io_gpio_inst_GPIO35 (HPS_ENET_INT_N),
    .hps_0_hps_io_hps_io_gpio_inst_GPIO40 (HPS_LTC_GPIO),
    .hps_0_hps_io_hps_io_gpio_inst_GPIO48 (HPS_I2C_CONTROL),
    .hps_0_hps_io_hps_io_gpio_inst_GPIO53 (HPS_LED),
    .hps_0_hps_io_hps_io_gpio_inst_GPIO54 (HPS_KEY),
    .hps_0_hps_io_hps_io_gpio_inst_GPIO61 (HPS_GSENSOR_INT),
    .memory_mem_a (HPS_DDR3_ADDR),
    .memory_mem_ba (HPS_DDR3_BA),
    .memory_mem_ck (HPS_DDR3_CK_P),
    .memory_mem_ck_n (HPS_DDR3_CK_N),
    .memory_mem_cke (HPS_DDR3_CKE),
    .memory_mem_cs_n (HPS_DDR3_CS_N),
    .memory_mem_ras_n (HPS_DDR3_RAS_N),
    .memory_mem_cas_n (HPS_DDR3_CAS_N),
    .memory_mem_we_n (HPS_DDR3_WE_N),
    .memory_mem_reset_n (HPS_DDR3_RESET_N),
    .memory_mem_dq (HPS_DDR3_DQ),
    .memory_mem_dqs (HPS_DDR3_DQS_P),
    .memory_mem_dqs_n (HPS_DDR3_DQS_N),
    .memory_mem_odt (HPS_DDR3_ODT),
    .memory_mem_dm (HPS_DDR3_DM),
    .memory_oct_rzqin (HPS_DDR3_RZQ),
    .reset_reset_n (1'b1), // Fixo em 1 para o HPS sempre funcionar, já que o reset é ativo em nível baixo
    .pio_data_in_external_connection_export (pio_data_in_wire),
    .pio_signals_external_connection_export (pio_signals_wire),
    .pio_data_out_external_connection_export (pio_data_out_wire)
);

/* Instancia o CoProcessor conectando aos PIOs via wires
Os wires recebem/enviam dados do HPS através dos PIOs */
CoProcessor copro (
    .clk (CLOCK_50),
    .data_in (pio_data_in_wire),
    .enable (pio_signals_wire[0]),
    .clr_operation (pio_signals_wire[1]),
    .rst (pio_signals_wire[2]),
    .data_out (pio_data_out_wire)
);

endmodule