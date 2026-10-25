# 실측 기록

환경: Omarchy 4.0.4(Arch) · Hyprland 0.56.2(Lua 설정) · 노트북 1대(eDP-1, scale 1.6) · hypruse 0.13.0 · Kiro 1.3.11(Electron, VS Code 계열).
매 동작 전후로 `hyprctl activewindow`·`activeworkspace`·`cursorpos`를 찍어 사용자 포커스가 바뀌었는지 판정했다.

## 1. 숨은 워크스페이스(ws99가 어느 모니터에도 안 보일 때)

| 동작 | 방법 | 결과 | 사용자 포커스 |
|---|---|---|---|
| 메뉴·탭·버튼 목록 | `hypruse ui` | 메뉴바 7개, activity bar 탭 8개, 버튼 — 이름과 좌표 | 무관 |
| 탭·버튼 누르기 | `hypruse click_ui` (AT-SPI 액션) | 성공 — 트리 반영은 몇 초 늦음 | 안 바뀜 |
| 검색칸 타이핑 | `click_ui` + `keyboard type --window` (`sendshortcut`) | **실패** | 안 바뀜 |
| 검색칸 타이핑 | CDP `Input.insertText`(+`Emulation.setFocusEmulationEnabled`) | **실패** | 안 바뀜 |
| 검색칸 타이핑 | CDP `execCommand('insertText')` / 합성 `input` 이벤트 | **실패** — execCommand false | 안 바뀜 |
| 검색칸 포커스 | AT-SPI `Component.grab_focus` 직접 호출 | 앱 포커스는 가지만 **사용자 키보드 포커스를 뺏음** | **뺏김** |
| 창 캡처 | `hypruse screenshot --window` | 빈 화면 | 무관 |

원인: 숨은 창의 페이지 안에서 1초간 잰 값 — `requestAnimationFrame` **0회**, `setInterval` 10회, `visibilityState: "visible"`.
Hyprland는 보이지 않는 워크스페이스의 창에 `wl_surface.frame`을 보내지 않고, Chromium의 rAF는 그 프레임에 묶여 있다.
Monaco(VS Code 계열의 입력칸·에디터)는 화면 갱신을 rAF로 하므로 입력이 DOM·접근성 트리·캡처 어디에도 반영되지 않는다.

## 2. 헤드리스 출력 만들기

- 규칙 없이 `hyprctl output create headless AGENT-1` → 새 출력이 포커스를 가져가고, 커서가 그리로 넘어가고, 빈 워크스페이스가 붙어 활성 ws가 바뀌고, `position = "auto"`였던 노트북 화면이 x=11200으로 밀렸다.
- 모니터 위치·워크스페이스 규칙을 먼저 넣고, 만든 직후 원래 창·커서로 되돌리면 측정상 변화 없음(`agent-display up`).
- `hl.dsp.workspace.move`는 `{ monitor = … }`만 받는다(활성 ws를 옮긴다). 특정 ws를 특정 출력에 두려면 `hl.workspace_rule`.
- 출력을 지우면 커서가 화면 중앙으로 옮겨진다 → `agent-display down`이 되돌린다.

## 3. 헤드리스 출력 위의 ws99

| 측정 | 숨은 ws99 | AGENT-1 위 ws99 |
|---|---|---|
| 페이지 rAF | 0 /초 | **61 /초** |
| 탭·버튼 누르기 | 성공(지연) | 성공 |
| 검색칸 타이핑 (`hypruse keyboard type --window`) | 실패 | **성공** — 결과 목록까지 갱신 |
| 창 캡처 | 빈 화면 | **실시간**(`visible: true`) |
| 앱 실행 중 사용자 포커스 | 무변경 | 무변경 |

## 4. 사용자와 동시 타이핑

에이전트가 Kiro 검색칸에 `R01-focusless … R15-focusless`를 약 30초 동안 치는 동안, 사용자는 다른 창의 nvim에 한글로 계속 타이핑했다.

| 라운드 | 결과 |
|---|---|
| 1 | 사용자 포커스 무변경. 테스트 스크립트가 이미 열린 activity bar 탭을 또 눌러 패널을 닫는 바람에 첫 10글자 유실(앱 내부 문제) |
| 2 | **사고** — `click_ui`가 검색칸(entry)에 접근성 포커스를 주자 Chromium이 activate를 요청했고, `focus_on_activate=true`가 받아 사용자 키보드가 ws99의 Kiro로 넘어갔다. 사용자 글자가 Kiro 검색칸에 섞이고 에이전트 입력 1개 유실. 사용자가 워크스페이스 단축키로 빠져나오는 사이 AGENT-1이 다른 ws를 보여주게 됨 → `agent-display show`로 복구 |
| 3 | ws99 창에 `focus_on_activate = false` 규칙 적용 후 같은 시험: 15번 측정 모두 사용자 창 유지, Kiro에 15개 전부 순서대로, 사용자 nvim에 에이전트 글자 0건(한글 IME 조합도 무손상) |

## 교훈

- Chromium/Electron 입력칸에 앱 포커스를 주는 경로는 activate 요청을 동반한다. 에이전트 ws에 `focus_on_activate = false`가 없으면 사용자 포커스를 뺏는다.
- AT-SPI `grab_focus`를 직접 부르지 않는다.
- 이미 열린 activity bar 탭을 다시 누르면 패널이 닫힌다(토글). 상태를 먼저 읽는다.
- 글자가 든 검색칸은 접근성 트리에서 placeholder 이름으로 잡히지 않는다. "Clear … Search Results" 버튼으로 비운 뒤 잡는다.
- hypruse `launch`에 워크스페이스를 지정하지 않으면 "화면에 보이는" ws를 피하므로 ws99(AGENT-1에 표시 중)를 건너뛰고 숨은 ws로 간다 → 다시 rAF 0. `workspace="99"`를 명시한다.
- 같은 이유로 `HYPRUSE_BACKGROUND=1`(보장 모드)은 보이는 ws99로의 launch를 거부한다. 자동 모드로 쓴다.
- Electron 앱이 띄운 자식 프로세스(dconf)가 `--remote-debugging-port` 소켓을 물려받아 앱 종료 뒤에도 포트를 쥐고 있었다.
