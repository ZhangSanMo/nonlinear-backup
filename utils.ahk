#Requires AutoHotkey v2.0

; === 集中引用基础库 ===
; 这些库里面已经包含了 repr, doCopy, dumps 等函数
#Include seq.ahk
#Include arrays.ahk
#Include strings.ahk

; === 通用工具函数 ===

; 空函数，用于占位 (strings.ahk 中没有这个)
nothing(*) {
}

; 显示提示信息 (原 gui.ahk 中的逻辑)
display(x, sec := 3, followGui := false) {
    msg := repr(x) ; 调用 strings.ahk 中的 repr
    static displaying := ''
    displaying := displaying ? displaying '`n' msg : msg
    if followGui {
        ToolTip(displaying, 0, -14)
    } else {
        ToolTip(displaying)
    }
    SetTimer(() => (displaying := '', ToolTip()), -1000 * sec)
    return msg
}

; 严重错误退出 (替代原 quit)
fatalExit(msg) {
    display(msg)
    SetTimer(ExitApp, -2900)
    ; 阻塞等待退出
    Sleep(3000)
    ExitApp
}

; 获取当前进程名（不含后缀）
procName() {
    return SubStr(WinGetProcessName('A'), 1, -4)
}

; 检查窗口是否激活
; 依赖 strings.ahk 中的 isWildcardMatch
isWinActive(procName, titlePattern?) {
    toExe(name) => 'ahk_exe ' name '.exe'
    
    return WinActive(toExe(procName)) and (
        not IsSet(titlePattern) or not titlePattern
        or WinGetTitle('A').isWildcardMatch(titlePattern)
    )
}