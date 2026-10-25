# hypr-agent-seat

Hyprland에서 AI 에이전트가 **내 포커스·커서·타이핑을 건드리지 않고** 다른 앱 창을 클릭하고 타이핑하게 하는 구성.

내가 한 창에서 일하는 동안 에이전트는 자기 방(눈에 안 보이는 가상 모니터)에서 Electron·GTK·Qt 앱을 조작한다.
조작 도구는 [hypruse](https://github.com/IlyasKhallouki/hypruse)(MCP 서버)이고, 이 repo는 그 위에 얹는 Hyprland 쪽 구성
— 가상 모니터, 워크스페이스·창 규칙, 관리 스크립트 — 과 그걸 만들며 잰 실측 기록이다.

브라우저의 Claude in Chrome처럼 "배경에서 조작"하는 경험을 데스크톱 앱 전체로 넓히는 게 목표였다.

## 원리

### 문제 1 — 키보드·마우스는 한 벌뿐이다

ydotool·wtype 같은 기존 도구는 가짜 키보드를 하나 더 꽂는 방식이다. 그런데 키 입력은 언제나 지금 포커스된 창으로 간다.
다른 창에 입력하려면 그 창을 앞으로 끌어와야 하고, 그게 곧 포커스를 뺏는 일이다.
Wayland의 가상 입력 프로토콜(`virtual-keyboard`, `virtual-pointer`, libei)에는 대상 창을 지정하는 인자가 아예 없다.

### 해결 1 — 키보드 대신 앱에 직접 말을 건다 (hypruse)

- **버튼·메뉴·탭**은 접근성 통로(AT-SPI)로 누른다. 스크린리더가 버튼을 대신 누를 때 쓰는 통로라 키보드를 거치지 않는다 — 앱에 "이 버튼 눌러"라고 직접 전화를 거는 셈이다.
- **글자**는 Hyprland의 `sendshortcut`으로 "이 창에만 이 키를 넣어 줘"라고 부탁한다. 컴포지터가 한 단계 안에서 그 창에 키를 넣고 돌아오므로 사람의 타이핑과 섞이지 않는다.

### 문제 2 — 안 보이는 창은 잠든다

Hyprland는 화면에 안 보이는 워크스페이스의 창에 "다음 장면을 그려라"(`wl_surface.frame`) 신호를 보내지 않는다.
그러면 Electron 앱 안의 `requestAnimationFrame`이 멈춘다(실측 초당 0회). VS Code 계열 입력칸(Monaco)은 rAF로 화면을 갱신하므로,
버튼은 눌려도 **입력칸에 글자가 반영되지 않고 캡처도 빈 화면**이 된다.

### 해결 2 — 눈에 안 보이는 모니터를 하나 꽂는다

헤드리스(가상) 출력 `AGENT-1`을 만들고 에이전트 워크스페이스 99를 거기 띄운다.
컴포지터 입장에서는 "보이는 화면"이라 앱이 계속 그린다(실측 rAF 초당 61회).
실제 화면과 떨어진 좌표(x=10000)에 둬서 마우스가 넘어갈 수 없다. 보고 싶을 때만 미러 창으로 들여다본다.

### 문제 3 — 앱이 "나 좀 봐줘"라고 한다

입력칸에 포커스를 주면 Chromium이 창 활성화(activate)를 요청하고, `misc:focus_on_activate`가 켜져 있으면(Omarchy 기본값)
컴포지터가 그 요청을 들어줘 사람의 키보드가 에이전트 창으로 넘어간다. 실제로 이 사고가 났다.
→ 에이전트 워크스페이스의 창은 `focus_on_activate = false`로 그 요청을 무시하게 한다.

비유하면, 사무실에 키보드가 하나뿐이라 직원(에이전트)에게 전용 방(가상 모니터)을 내주고, 인터폰(접근성 통로)으로 일을 시키되,
"잠깐 나와 보세요" 벨(activate)은 끊어 둔 구조다.

```
 사람 ──키보드·마우스──▶ 실제 모니터 (내 워크스페이스들)
                          │  ← 포커스·커서는 여기서 안 움직인다
 에이전트 ──MCP──▶ hypruse ─┬─ AT-SPI 액션 ─────▶ 앱 (버튼·메뉴·탭)
                           ├─ sendshortcut ─────▶ 앱 (키 입력)
                           └─ grim -T ──────────▶ 창 캡처
                                                  │
                     AGENT-1 (헤드리스, x=10000) ── ws99 ← 앱이 사는 곳, 프레임이 돈다
                                                  └─ focus_on_activate = false
```

## 구성

| 파일 | 하는 일 |
|---|---|
| `bin/agent-display` | 헤드리스 출력 만들기(`up`)·ws99 다시 보이기(`show`)·지우기(`down`)·미러 창(`view`)·상태(`status`). 만들 때 가져간 포커스·커서를 바로 되돌린다 |
| `hypr/agent-seat.lua` | 실제 모니터 위치 고정, AGENT-1 규칙, ws99 → AGENT-1, ws99 `focus_on_activate = false`, 로그인 때 `agent-display up` |
| `examples/kiro-on-agent-seat.sh` | Electron 앱(Kiro)을 접근성 트리를 켠 채 ws99에 띄우는 예 |
| `docs/MEASUREMENTS.md` | 실측 기록 — 숨은 ws vs 가상 모니터, 포커스 사고와 해결, 사람과 동시 타이핑 |

## 요구 사항

- Hyprland 0.56 이상, **Lua 설정**(`hyprland.lua`). hyprlang(`hyprland.conf`) 문법으로는 옮겨 써야 한다.
- [hypruse](https://github.com/IlyasKhallouki/hypruse) 0.13 이상 (`uv tool install hypruse` 또는 AUR `hypruse`), `grim` 1.5+, `wtype`
- `wl-mirror` (미러 창, 선택), `python3`
- 시험한 환경: Omarchy 4.0.4 · Hyprland 0.56.2 · 노트북 화면 1대

## 설치

```bash
git clone https://github.com/kingcheee/hypr-agent-seat
cd hypr-agent-seat

install -Dm755 bin/agent-display ~/.local/bin/agent-display
cp hypr/agent-seat.lua ~/.config/hypr/agent-seat.lua
# agent-seat.lua의 1번(실제 모니터 output·scale)을 자기 환경에 맞게 고친다: hyprctl monitors
echo 'require("hypr.agent-seat")' >> ~/.config/hypr/hyprland.lua   # 설정 파일 위치에 맞게
hyprctl configerrors

uv tool install hypruse
agent-display up && agent-display status     # → AGENT-1 up at 10000,0 showing ws 99
```

MCP 등록 — 에이전트 워크스페이스를 99 하나로 묶고, 자동 모드로 쓴다(아래 「주의」).

```bash
# Claude Code
claude mcp add -s user hypruse -e HYPRUSE_AGENT_WORKSPACES=99 -e HYPRUSE_JOURNAL=1 -- hypruse
```

```jsonc
// Antigravity CLI(agy): ~/.gemini/config/mcp_config.json
{ "mcpServers": { "hypruse": { "command": "hypruse", "args": [],
    "env": { "HYPRUSE_AGENT_WORKSPACES": "99", "HYPRUSE_JOURNAL": "1" } } } }
// 헤드리스 agy -p로 쓰려면 ~/.gemini/antigravity-cli/settings.json의 permissions.allow에 "mcp(hypruse/*)"
```

## 쓰기

```bash
agent-display view                       # 에이전트가 하는 일을 미러 창으로 본다
examples/kiro-on-agent-seat.sh           # Kiro를 ws99에 접근성 트리를 켠 채 띄운다

hypruse ui --window <주소>                                 # 누를 수 있는 것들의 이름
hypruse click_ui "Extensions (Ctrl+Shift+X)" --window <주소>
hypruse click_ui "Search Extensions in Marketplace" --window <주소>
hypruse keyboard type "hyprland" --window <주소>
```

MCP로 붙은 에이전트에게는 "앱은 workspace 99에 띄우고, 누를 때는 click_ui, 칠 때는 keyboard에 window를 지정하라"고 알려 주면 된다.

## 주의

- **launch에는 워크스페이스 99를 명시한다.** 지정하지 않으면 hypruse는 "화면에 보이는" ws를 피하므로 AGENT-1이 보여주는 ws99를 건너뛰고 숨은 ws로 간다 — 다시 rAF 0이 된다.
- 같은 이유로 `HYPRUSE_BACKGROUND=1`(보장 모드)은 쓰지 않는다. 보이는 ws99로의 launch를 거부한다. 자동 모드에서도 사용자 창이 아닌 창에 대한 동작은 배경으로 처리된다.
- **Electron 앱은 `ACCESSIBILITY_ENABLED=1`과 `--force-renderer-accessibility`를 같이 줘야** 접근성 트리가 생긴다. 플래그만으로는 AT-SPI에 붙지 않았다.
- **AT-SPI `grab_focus`를 직접 부르지 않는다.** Chromium 창에서 사람의 포커스를 뺏는다.
- AGENT-1이 다른 워크스페이스를 보여주게 되면(예: 사고로 포커스가 넘어간 사이 워크스페이스 단축키를 누름) `agent-display show`.
- 오른쪽 클릭·더블클릭, 접근성 트리가 없는 앱(터미널·캔버스 앱)의 임의 좌표 클릭은 배경에서 안 된다(hypruse의 한계).
- `hyprctl output create`·`remove`는 런타임 변경이다. 영구화는 `agent-seat.lua`의 로그인 훅이 맡는다.

## 크레딧

- 조작 도구: [IlyasKhallouki/hypruse](https://github.com/IlyasKhallouki/hypruse) (MIT)
- 미러: [Ferdi265/wl-mirror](https://github.com/Ferdi265/wl-mirror)

## 라이선스

MIT
