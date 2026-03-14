///////////////////////////////////////////////////////////////////////////////
// ch21_power_monitor.sv
// INA226 온보드 전류/전력 센서 인터페이스
//
// Basys 3는 온보드 INA226 센서를 탑재하고 있어서, I2C를 통해
// 실시간 전류(mA)와 전력(mW)을 측정할 수 있습니다.
//
// 특징:
//   - I2C 주소: 0x40 (7-bit)
//   - Current Register (0x04): 현재 값 (mA)
//   - Power Register (0x03): 전력 값 (mW)
//   - 갱신 주기: ~1ms (typical)
//
// 사용 예시:
//   INA226을 I2C로 폴링하여 current_ma, power_mw를 주기적으로 업데이트
//   실제 구현은 I2C Master 컨트롤러 필요
///////////////////////////////////////////////////////////////////////////////

module power_monitor (
  input  logic        clk,              // 시스템 클록
  input  logic        rst_n,            // 리셋 (액티브 로우)

  // I2C 인터페이스 (Basys 3 온보드)
  inout  wire         sda,              // I2C 데이터 라인
  inout  wire         scl,              // I2C 클록 라인

  // 측정 결과 출력
  output logic [15:0] current_ma,       // 현재 (mA)
  output logic [15:0] power_mw,         // 전력 (mW)
  output logic        data_valid        // 데이터 유효 신호
);

  ///////////////////////////////////////////////////////////////////////////
  // INA226 레지스터 주소
  ///////////////////////////////////////////////////////////////////////////

  localparam [7:0] INA226_ADDR_CONFIG    = 8'h00;  // 구성 레지스터
  localparam [7:0] INA226_ADDR_SHUNT_V   = 8'h01;  // Shunt 전압 (mV)
  localparam [7:0] INA226_ADDR_BUS_V     = 8'h02;  // 버스 전압 (V)
  localparam [7:0] INA226_ADDR_POWER     = 8'h03;  // 전력 (mW)
  localparam [7:0] INA226_ADDR_CURRENT   = 8'h04;  // 전류 (mA)
  localparam [7:0] INA226_ADDR_CALIB     = 8'h05;  // 캘리브레이션
  localparam [7:0] INA226_I2C_ADDR       = 8'h40;  // I2C 7-bit 주소 (0x40)

  ///////////////////////////////////////////////////////////////////////////
  // 상태 머신: I2C 폴링 로직
  ///////////////////////////////////////////////////////////////////////////

  typedef enum logic [2:0] {
    IDLE,              // 대기 상태
    I2C_START,         // I2C START 조건
    I2C_WRITE_ADDR,    // 주소 + Write 비트 전송
    I2C_WRITE_REG,     // 레지스터 주소 전송
    I2C_RESTART,       // RESTART 조건
    I2C_READ_DATA,     // 데이터 읽기
    I2C_STOP           // STOP 조건
  } state_t;

  state_t state_curr, state_next;

  ///////////////////////////////////////////////////////////////////////////
  // 내부 신호
  ///////////////////////////////////////////////////////////////////////////

  logic [7:0]  i2c_byte_out;            // I2C로 보낼 바이트
  logic [7:0]  i2c_byte_in;             // I2C에서 읽은 바이트
  logic        i2c_busy;                // I2C Master 동작 중 플래그
  logic        i2c_start_req;           // START 요청
  logic        i2c_stop_req;            // STOP 요청
  logic        i2c_write_req;           // Write 요청
  logic        i2c_read_req;            // Read 요청

  logic [15:0] power_raw;               // 레지스터에서 읽은 원본 값
  logic [15:0] current_raw;             // 레지스터에서 읽은 원본 값

  logic [19:0] poll_counter;            // 폴링 카운터 (갱신 주기 제어)
  localparam   POLL_PERIOD = 20'd100000; // ~100ms (100MHz 클록 기준)

  ///////////////////////////////////////////////////////////////////////////
  // FSM: 메인 상태 머신
  ///////////////////////////////////////////////////////////////////////////

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_curr <= IDLE;
      poll_counter <= 20'b0;
    end
    else begin
      state_curr <= state_next;
      poll_counter <= (poll_counter == POLL_PERIOD) ? 20'b0 : poll_counter + 1'b1;
    end
  end

  ///////////////////////////////////////////////////////////////////////////
  // FSM: 다음 상태 결정 (조합 로직)
  ///////////////////////////////////////////////////////////////////////////

  always_comb begin
    state_next = state_curr;

    case (state_curr)
      IDLE: begin
        // 100ms마다 한 번씩 I2C 폴링 시작
        if (poll_counter == POLL_PERIOD) begin
          state_next = I2C_START;
        end
      end

      I2C_START: begin
        // I2C START 조건 생성 후 다음 상태로
        if (!i2c_busy) state_next = I2C_WRITE_ADDR;
      end

      I2C_WRITE_ADDR: begin
        // INA226 주소 (0x40) + Write 비트 (0) 전송
        if (!i2c_busy) state_next = I2C_WRITE_REG;
      end

      I2C_WRITE_REG: begin
        // Current 레지스터 주소 (0x04) 전송
        if (!i2c_busy) state_next = I2C_RESTART;
      end

      I2C_RESTART: begin
        // I2C RESTART 조건 (START 후 STOP 없이 다시 START)
        if (!i2c_busy) state_next = I2C_READ_DATA;
      end

      I2C_READ_DATA: begin
        // 2바이트 읽기 (current_ma [15:8], [7:0])
        // 이 예시에서는 간략화함
        if (!i2c_busy) state_next = I2C_STOP;
      end

      I2C_STOP: begin
        // I2C STOP 조건
        if (!i2c_busy) state_next = IDLE;
      end

      default: state_next = IDLE;
    endcase
  end

  ///////////////////////////////////////////////////////////////////////////
  // I2C 요청 신호 생성
  ///////////////////////////////////////////////////////////////////////////

  always_comb begin
    i2c_start_req = (state_curr == IDLE && poll_counter == POLL_PERIOD);
    i2c_stop_req  = (state_curr == I2C_STOP);
    i2c_write_req = (state_curr == I2C_WRITE_ADDR ||
                     state_curr == I2C_WRITE_REG);
    i2c_read_req  = (state_curr == I2C_READ_DATA);

    case (state_curr)
      I2C_WRITE_ADDR: i2c_byte_out = {INA226_I2C_ADDR, 1'b0}; // 7-bit addr + Write
      I2C_WRITE_REG:  i2c_byte_out = INA226_ADDR_CURRENT;      // Current reg addr
      default:        i2c_byte_out = 8'b0;
    endcase
  end

  ///////////////////////////////////////////////////////////////////////////
  // 데이터 갱신 (실제 I2C 읽기 시뮬레이션)
  ///////////////////////////////////////////////////////////////////////////

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      current_ma   <= 16'b0;
      power_mw     <= 16'b0;
      data_valid   <= 1'b0;
    end
    else if (state_curr == I2C_STOP && !i2c_busy) begin
      // I2C 읽기 완료 후 데이터 갱신
      // 실제로는 i2c_byte_in 값을 처리해야 함
      current_ma   <= current_raw;
      power_mw     <= power_raw;
      data_valid   <= 1'b1;
    end
    else begin
      data_valid   <= 1'b0;  // 1 사이클 펄스
    end
  end

  ///////////////////////////////////////////////////////////////////////////
  // 실제 구현 참고사항
  ///////////////////////////////////////////////////////////////////////////

  // 위의 코드는 프레임워크이며, 실제 구현 시 다음이 필요합니다:
  //
  // 1. I2C Master 컨트롤러 모듈 포함:
  //    - START/STOP 조건 생성
  //    - 데이터 전송 (8-bit byte @ 400kHz)
  //    - SDA/SCL 오픈드레인 구동
  //
  // 2. 바이트 시리얼화:
  //    - 16-bit 데이터 → 2×8-bit I2C 전송
  //
  // 3. 캐시 처리:
  //    - INA226은 내부 ADC 변환 시간 있음 (~1ms)
  //    - 갱신 주기를 충분히 길게 설정
  //
  // 참고: Basys 3 보드 문서에서 INA226 Slave 주소 및 연결도 확인 필수

endmodule

///////////////////////////////////////////////////////////////////////////////
// 테스트벤치 예시 (시뮬레이션용)
///////////////////////////////////////////////////////////////////////////////

`ifdef SIMULATION

module power_monitor_tb;
  logic        clk;
  logic        rst_n;
  wire         sda, scl;
  logic [15:0] current_ma;
  logic [15:0] power_mw;
  logic        data_valid;

  power_monitor dut (
    .clk(clk),
    .rst_n(rst_n),
    .sda(sda),
    .scl(scl),
    .current_ma(current_ma),
    .power_mw(power_mw),
    .data_valid(data_valid)
  );

  // 클록 생성
  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;  // 100MHz
  end

  // 테스트 시나리오
  initial begin
    rst_n = 1'b0;
    #10 rst_n = 1'b1;

    // 시뮬레이션 시간: 1ms 이상
    // 폴링 주기 동안 대기, 데이터 갱신 확인
    #100000;

    if (data_valid) begin
      $display("✓ Data valid: current=%0d mA, power=%0d mW",
               current_ma, power_mw);
    end else begin
      $display("✗ Data not updated");
    end

    $finish;
  end
endmodule

`endif
