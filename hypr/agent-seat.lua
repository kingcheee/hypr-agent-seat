-- hypr-agent-seat — Hyprland 0.56+ Lua 설정 조각.
-- hyprland.lua 끝에서 불러온다:  require("hypr.agent-seat")  (이 파일을 ~/.config/hypr/agent-seat.lua로 복사했을 때)
--
-- 에이전트 워크스페이스(99)를 헤드리스 출력 AGENT-1에 띄워 프레임이 계속 돌게 하고,
-- 그 창들이 activate 요청으로 사용자 포커스를 가져가지 못하게 한다.

-- 1. 실제 모니터 위치를 못 박는다.
--    position = "auto"인 모니터는 AGENT-1이 생길 때 자리가 다시 계산되어 밀린다(실측: x=0 → x=11200).
--    아래 output·scale은 자기 모니터에 맞게 바꾼다(hyprctl monitors).
hl.monitor({ output = "eDP-1", mode = "preferred", position = "0x0", scale = 1 })

-- 2. 에이전트 전용 헤드리스 출력. 실제 화면과 붙어 있지 않은 좌표에 둬서 커서가 넘어가지 못하게 한다.
hl.monitor({ output = "AGENT-1", mode = "1920x1080@60", position = "10000x0", scale = 1 })

-- 3. 에이전트 워크스페이스는 AGENT-1이 보여준다.
hl.workspace_rule({ workspace = "99", monitor = "AGENT-1", default = true })

-- 4. 에이전트 워크스페이스의 창은 activate 요청으로 사용자 포커스를 가져가지 못한다.
--    Electron 입력칸에 접근성 포커스를 주면 Chromium이 activate를 요청하고,
--    misc.focus_on_activate=true(Omarchy 기본값)면 사용자 키보드가 그 창으로 넘어간다.
hl.window_rule({ match = { workspace = "99" }, focus_on_activate = false })

-- 5. 로그인 때 출력을 만든다. 다른 자동 실행 창이 자리 잡은 뒤로 늦춘다.
hl.on("hyprland.start", function()
  hl.exec_cmd("sleep 6; agent-display up")
end)
