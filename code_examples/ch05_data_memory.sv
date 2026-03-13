//=============================================================================
// 모듈명  : data_memory
// 파일명  : ch05_data_memory.sv
// 설명    : RV32I 데이터 메모리 (DMEM)
//           - 바이트 인에이블(byte enable) 기반 쓰기
//           - LB/LBU/LH/LHU/LW 로드 시 부호/제로 확장
//           - SB/SH/SW 스토어 지원
//           - 리틀 엔디언(little-endian) 바이트 순서
//           - 동기 쓰기, 비동기 읽기 (단일 사이클 프로세서 호환)
// 저자    : RISC-V 프로세서 설계 완전정복
// 표준    : SystemVerilog IEEE 1800-2017
//=============================================================================

module data_memory #(
   parameter ADDR_WIDTH = 12,                    // 주소 비트 수 (12비트 = 4096 워드)
   parameter MEM_DEPTH  = 2**ADDR_WIDTH          // 메모리 깊이 (4096 워드 = 16 KB)
)(
   input  logic        clk_i,                    // 시스템 클록
   input  logic        rst_ni,                   // 비동기 리셋 (액티브 로우)

   // 메모리 인터페이스
   input  logic [31:0] addr_i,                   // 바이트 주소
   input  logic [31:0] wdata_i,                  // 쓰기 데이터
   input  logic        mem_write_i,              // 쓰기 인에이블 (1=쓰기, 0=읽기)
   input  logic [2:0]  funct3_i,                 // funct3 필드 (접근 크기/부호 결정)
   output logic [31:0] rdata_o                   // 읽기 데이터 (부호/제로 확장 완료)
);

   //--------------------------------------------------------------------------
   // funct3 인코딩 상수 정의
   //--------------------------------------------------------------------------
   localparam logic [2:0] FUNCT3_LB  = 3'b000;  // Load Byte (부호 확장)
   localparam logic [2:0] FUNCT3_LH  = 3'b001;  // Load Halfword (부호 확장)
   localparam logic [2:0] FUNCT3_LW  = 3'b010;  // Load Word
   localparam logic [2:0] FUNCT3_LBU = 3'b100;  // Load Byte Unsigned (제로 확장)
   localparam logic [2:0] FUNCT3_LHU = 3'b101;  // Load Halfword Unsigned (제로 확장)
   // 스토어 명령어도 동일한 funct3[1:0] 비트 사용
   // SB = 3'b000, SH = 3'b001, SW = 3'b010

   //--------------------------------------------------------------------------
   // 메모리 배열 선언 (바이트 단위로 4개 뱅크)
   //   - 바이트 인에이블 BRAM 추론을 위해 바이트 배열로 선언
   //   - bank[0]: Byte 0 (최하위, addr[1:0]=00)
   //   - bank[1]: Byte 1 (addr[1:0]=01)
   //   - bank[2]: Byte 2 (addr[1:0]=10)
   //   - bank[3]: Byte 3 (최상위, addr[1:0]=11)
   //--------------------------------------------------------------------------
   logic [7:0] mem_bank0 [0:MEM_DEPTH-1];  // Byte 0 (LSB)
   logic [7:0] mem_bank1 [0:MEM_DEPTH-1];  // Byte 1
   logic [7:0] mem_bank2 [0:MEM_DEPTH-1];  // Byte 2
   logic [7:0] mem_bank3 [0:MEM_DEPTH-1];  // Byte 3 (MSB)

   //--------------------------------------------------------------------------
   // 내부 신호
   //--------------------------------------------------------------------------
   logic [ADDR_WIDTH-1:0] word_addr;             // 워드 주소 (addr_i[ADDR_WIDTH+1:2])
   logic [1:0]            byte_offset;           // 바이트 오프셋 (addr_i[1:0])
   logic [3:0]            byte_we;               // 바이트 쓰기 인에이블
   logic [31:0]           mem_word;              // 메모리에서 읽은 원본 워드

   //--------------------------------------------------------------------------
   // 주소 분해
   //--------------------------------------------------------------------------
   assign word_addr   = addr_i[ADDR_WIDTH+1:2];
   assign byte_offset = addr_i[1:0];

   //--------------------------------------------------------------------------
   // 바이트 쓰기 인에이블 생성
   //   - funct3[1:0]과 byte_offset에 따라 활성화할 바이트 뱅크 결정
   //   - SB: 1바이트, SH: 2바이트, SW: 4바이트
   //--------------------------------------------------------------------------
   always_comb begin
      byte_we = 4'b0000;
      if (mem_write_i) begin
         case (funct3_i[1:0])
            2'b00: begin  // SB: 1바이트 쓰기
               case (byte_offset)
                  2'b00: byte_we = 4'b0001;
                  2'b01: byte_we = 4'b0010;
                  2'b10: byte_we = 4'b0100;
                  2'b11: byte_we = 4'b1000;
               endcase
            end
            2'b01: begin  // SH: 2바이트 쓰기 (하프워드 정렬 가정)
               case (byte_offset[1])
                  1'b0: byte_we = 4'b0011;   // 하위 하프워드
                  1'b1: byte_we = 4'b1100;   // 상위 하프워드
               endcase
            end
            2'b10: begin  // SW: 4바이트 쓰기
               byte_we = 4'b1111;
            end
            default: byte_we = 4'b0000;
         endcase
      end
   end

   //--------------------------------------------------------------------------
   // 동기 쓰기 (클록 상승 에지)
   //   - 바이트 인에이블에 따라 해당 바이트 뱅크만 갱신
   //   - SB: wdata_i[7:0]를 해당 바이트 위치에 기록
   //   - SH: wdata_i[15:0]를 해당 하프워드 위치에 기록
   //   - SW: wdata_i[31:0] 전체 기록
   //--------------------------------------------------------------------------
   always_ff @(posedge clk_i) begin
      if (byte_we[0]) begin
         case (funct3_i[1:0])
            2'b00:   mem_bank0[word_addr] <= wdata_i[7:0];            // SB
            2'b01:   mem_bank0[word_addr] <= wdata_i[7:0];            // SH 하위 바이트
            default: mem_bank0[word_addr] <= wdata_i[7:0];            // SW
         endcase
      end
      if (byte_we[1]) begin
         case (funct3_i[1:0])
            2'b00:   mem_bank1[word_addr] <= wdata_i[7:0];            // SB (byte_offset=01)
            2'b01:   mem_bank1[word_addr] <= wdata_i[15:8];           // SH 상위 바이트
            default: mem_bank1[word_addr] <= wdata_i[15:8];           // SW
         endcase
      end
      if (byte_we[2]) begin
         case (funct3_i[1:0])
            2'b00:   mem_bank2[word_addr] <= wdata_i[7:0];            // SB (byte_offset=10)
            2'b01:   mem_bank2[word_addr] <= wdata_i[7:0];            // SH 하위 바이트 (상위 HW)
            default: mem_bank2[word_addr] <= wdata_i[23:16];          // SW
         endcase
      end
      if (byte_we[3]) begin
         case (funct3_i[1:0])
            2'b00:   mem_bank3[word_addr] <= wdata_i[7:0];            // SB (byte_offset=11)
            2'b01:   mem_bank3[word_addr] <= wdata_i[15:8];           // SH 상위 바이트 (상위 HW)
            default: mem_bank3[word_addr] <= wdata_i[31:24];          // SW
         endcase
      end
   end

   //--------------------------------------------------------------------------
   // 비동기 읽기 — 메모리 워드 조합
   //--------------------------------------------------------------------------
   assign mem_word = {mem_bank3[word_addr],
                      mem_bank2[word_addr],
                      mem_bank1[word_addr],
                      mem_bank0[word_addr]};

   //--------------------------------------------------------------------------
   // 로드 데이터 확장 (부호 확장 / 제로 확장)
   //   - funct3에 따라 읽은 워드에서 해당 바이트/하프워드 추출 후 확장
   //   - funct3[2]: 0=부호 확장(signed), 1=제로 확장(unsigned)
   //--------------------------------------------------------------------------
   always_comb begin
      rdata_o = 32'h0;
      case (funct3_i)
         FUNCT3_LB: begin  // LB: 부호 확장 바이트
            case (byte_offset)
               2'b00: rdata_o = {{24{mem_word[7]}},  mem_word[7:0]};
               2'b01: rdata_o = {{24{mem_word[15]}}, mem_word[15:8]};
               2'b10: rdata_o = {{24{mem_word[23]}}, mem_word[23:16]};
               2'b11: rdata_o = {{24{mem_word[31]}}, mem_word[31:24]};
            endcase
         end
         FUNCT3_LH: begin  // LH: 부호 확장 하프워드
            case (byte_offset[1])
               1'b0: rdata_o = {{16{mem_word[15]}}, mem_word[15:0]};
               1'b1: rdata_o = {{16{mem_word[31]}}, mem_word[31:16]};
            endcase
         end
         FUNCT3_LW: begin  // LW: 워드 전체
            rdata_o = mem_word;
         end
         FUNCT3_LBU: begin  // LBU: 제로 확장 바이트
            case (byte_offset)
               2'b00: rdata_o = {24'b0, mem_word[7:0]};
               2'b01: rdata_o = {24'b0, mem_word[15:8]};
               2'b10: rdata_o = {24'b0, mem_word[23:16]};
               2'b11: rdata_o = {24'b0, mem_word[31:24]};
            endcase
         end
         FUNCT3_LHU: begin  // LHU: 제로 확장 하프워드
            case (byte_offset[1])
               1'b0: rdata_o = {16'b0, mem_word[15:0]};
               1'b1: rdata_o = {16'b0, mem_word[31:16]};
            endcase
         end
         default: rdata_o = mem_word;  // 안전 기본값
      endcase
   end

   //--------------------------------------------------------------------------
   // 메모리 초기화 (시뮬레이션용)
   //   - 모든 바이트 뱅크를 0으로 초기화
   //--------------------------------------------------------------------------
   initial begin
      for (int i = 0; i < MEM_DEPTH; i++) begin
         mem_bank0[i] = 8'h00;
         mem_bank1[i] = 8'h00;
         mem_bank2[i] = 8'h00;
         mem_bank3[i] = 8'h00;
      end
   end

endmodule
