# MT5 자동매매 EA 개발 프로젝트 (EA_F2)

Eightcap MetaTrader 5 기반 자동매매 Expert Advisor(EA) 개발, 백테스트 분석 및 모델 연동(MCP) 프로젝트입니다.

## 1. 개요
- **플랫폼**: MetaTrader 5 (Eightcap Global MT5 Terminal)
- **터미널 경로**: `C:\Program Files\Eightcap Global MT5 Terminal_Test`
- **언어**: MQL5 (EA 및 지표), Python 3.11 (백테스트 분석, 데이터 수집, MCP 도구)
- **아키텍처**:
  - `src/`: MQL5 소스 코드 (`.mq5`, `.mqh`)
  - `mcp_server/`: Antigravity AI 에이전트 연동용 MT5 MCP 서버
  - `PRD.md`: 자동매매 시스템 요구사항 및 전략 정의서

## 2. 시작하기
### 가상환경 활성화 및 실행
```powershell
.\.venv\Scripts\Activate.ps1
```

### MT5 MCP 서버 테스트
```powershell
.\.venv\Scripts\python.exe mcp_server\mt5_mcp_server.py
```
