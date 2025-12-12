#Requires AutoHotkey v2.0
#Include PatternMatch.ahk

; ========================================================
; 定义类似 .gitignore 的规则字符串
; ========================================================
patternStr := "
(
# --- 基础规则 ---
*.log
/temp
build/
src/**/test

# --- [修复] 之前丢失的规则 ---
!important.log      ; 必须加回来，否则 important.log 会被 *.log 匹配
doc/?.txt           ; 必须加回来，否则 doc/a.txt 无法匹配

# --- 优先级覆盖测试 ---
ignore_me.txt
!ignore_me.txt      ; 重新包含 (取反)
*.secret
!public.secret      ; 特例：虽然是 .secret 但不忽略

# --- 特殊字符安全性测试 ---
c++.cpp             ; 包含 + 号
v1.0(beta).zip      ; 包含 . 和 ()
file[1].txt         ; 包含 []

# --- 深度与无锚点测试 ---
vendor              ; 任意深度的 vendor 目录或文件
/config/local       ; 必须是根目录下的 config/local
)"

; 初始化匹配器
matcher := PatternMatch(patternStr)

; 定义日志文件路径
logFile := "test_result.txt"
if FileExist(logFile)
    FileDelete(logFile)

; ========================================================
; 辅助函数：追加文本到日志文件 (UTF-8)
; ========================================================
Log(text) {
    ; 第三个参数指定编码为 UTF-8
    ; 在 AHK v2 中，这通常会添加 BOM，这是 AHK 推荐的格式，也能完美支持 Emoji
    FileAppend(text, logFile, "UTF-8")
}

; ========================================================
; 测试函数
; ========================================================
RunTest(path, expected) {
    result := matcher.IsMatch(path)
    status := (result == expected) ? "PASS" : "FAIL"
    icon := (status == "PASS") ? "✅" : "❌"
    
    expectStr := expected ? "True" : "False"
    gotStr := result ? "True" : "False"
    
    output := Format("{1} [{2}] Path: '{3}'`n      Expected: {4}, Got: {5}`n", 
        icon, status, path, expectStr, gotStr)
    
    Log(output . "`n")
}

Log("====== Starting Tests ======`n`n")

; ========================================================
; 1. 基础测试
; ========================================================
RunTest("error.log", true)
RunTest("path/to/debug.log", true)
RunTest("readme.txt", false)

; 2. 测试取反 !important.log
RunTest("important.log", false)        
RunTest("logs/important.log", false)   

; 3. 测试根目录锚定 /temp
RunTest("temp", true)
RunTest("temp/cache", true) 
RunTest("sub/temp", false)

; 4. 测试目录匹配 build/
RunTest("build", true)          
RunTest("build/main.o", true)   
RunTest("my-build/test", false) 

; 5. 测试递归通配符 **
RunTest("src/foo/test", true)
RunTest("src/foo/bar/test", true)
RunTest("src/test", true)
RunTest("dist/test", false)

; 6. 测试单字通配符 ?
RunTest("doc/a.txt", true)
RunTest("doc/b.txt", true)
RunTest("doc/ab.txt", false)

Log("`n--- 补充测试用例 ---`n")

; ========================================================
; 补充测试
; ========================================================
RunTest("ignore_me.txt", false)

RunTest("my.secret", true)
RunTest("public.secret", false)

RunTest("c++.cpp", true)
RunTest("cxx.cpp", false)

RunTest("v1.0(beta).zip", true)
RunTest("v10beta.zip", false)

RunTest("file[1].txt", true)

RunTest("ERROR.LOG", true)
RunTest("Build", true)

RunTest("vendor", true)
RunTest("third_party/vendor", true)
RunTest("src/lib/vendor/index.js", true)

RunTest("config/local", true)
RunTest("src/config/local", false)
RunTest("config/local/settings", true)

Log("`n====== Tests Finished ======")

try {
    Run(logFile)
}