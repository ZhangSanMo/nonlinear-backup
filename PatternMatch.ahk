#Requires AutoHotkey v2.0

class PatternMatch {
    rules := []

    /**
     * 构造函数
     * @param patterns (String|Array) 模式字符串（换行符分隔）或模式数组
     */
    __New(patterns) {
        if (Type(patterns) = "String")
            patterns := StrSplit(patterns, ["`r`n", "`n", "`r"])
        
        for pat in patterns {
            this.AddRule(pat)
        }
    }

    /**
     * 添加单条规则
     */
    AddRule(patternStr) {
        ; 1. 移除行内注释 (找到第一个 ; 并截断)
        if (pos := InStr(patternStr, ";"))
            patternStr := SubStr(patternStr, 1, pos - 1)
        
        patternStr := Trim(patternStr)
        
        ; 2. 忽略空行和以 # 开头的整行注释
        if (patternStr = "" || SubStr(patternStr, 1, 1) = "#")
            return

        isNegative := false
        
        ; 3. 处理取反 !
        if (SubStr(patternStr, 1, 1) = "!") {
            isNegative := true
            patternStr := Trim(SubStr(patternStr, 2))
        }
        
        if (patternStr = "")
            return

        regex := this.GlobToRegex(patternStr)
        
        this.rules.Push({
            pattern: patternStr,
            regex: regex,
            negative: isNegative
        })
    }

    /**
     * 检查输入字符串是否匹配定义的模式
     * @param inputPath (String) 待检查的路径
     * @return (Boolean) true=匹配(忽略), false=不匹配(保留)
     */
    IsMatch(inputPath) {
        inputPath := StrReplace(inputPath, "\", "/")
        
        ; 默认不匹配
        matched := false
        
        for rule in this.rules {
            if RegExMatch(inputPath, rule.regex) {
                matched := !rule.negative
            }
        }
        return matched
    }

    /**
     * 核心逻辑：Glob -> Regex 转换
     */
    GlobToRegex(pat) {
        ; 1. 统一斜杠
        pat := StrReplace(pat, "\", "/")
        
        ; ==========================================================
        ; 核心策略：令牌化 (Tokenization)
        ; 先把通配符替换成安全的唯一占位符，防止被后续的正则转义破坏
        ; ==========================================================
        
        pat := StrReplace(pat, "/**/", "__GLOB_RECURSIVE_SLASH__")
        pat := StrReplace(pat, "**", "__GLOB_RECURSIVE__")
        pat := StrReplace(pat, "*", "__GLOB_STAR__")
        pat := StrReplace(pat, "?", "__GLOB_QUESTION__")
        
        ; ==========================================================
        ; 2. 安全转义正则元字符
        ; 此时字符串里没有通配符了，剩下的特殊字符必须转义
        ; ==========================================================
        pat := StrReplace(pat, "\", "\\") ; 先转义反斜杠
        escapeChars := ".+^$()[]{}|"
        Loop Parse, escapeChars
            pat := StrReplace(pat, A_LoopField, "\" . A_LoopField)
            
        ; ==========================================================
        ; 3. 还原令牌为正则语法
        ; ==========================================================
        
        ; /**/ -> /(?:.*/)? (匹配 /foo/bar/ 或 /)
        pat := StrReplace(pat, "__GLOB_RECURSIVE_SLASH__", "/(?:.*/)?")
        ; ** -> .* (匹配任意字符)
        pat := StrReplace(pat, "__GLOB_RECURSIVE__", ".*")
        ; * -> [^/]* (匹配非斜杠字符)
        pat := StrReplace(pat, "__GLOB_STAR__", "[^/]*")
        ; ? -> [^/] (匹配单个非斜杠字符)
        pat := StrReplace(pat, "__GLOB_QUESTION__", "[^/]")
        
        ; ==========================================================
        ; 4. 处理锚点 (Anchors)
        ; ==========================================================
        
        ; 结尾处理：如果没显式指定目录(/结尾)，则匹配文件或同名目录及其内容
        if (SubStr(pat, -1) = "/") {
            pat := SubStr(pat, 1, StrLen(pat)-1) . "(?:$|/.*)"
        } else {
            pat := pat . "(?:$|/.*)"
        }

        ; 开头处理：/ 开头为绝对路径，否则为相对路径
        if (SubStr(pat, 1, 1) = "/") {
            pat := "^" . SubStr(pat, 2)
        } else {
            pat := "(?:^|/)" . pat
        }

        return "i)" . pat ; 忽略大小写
    }
}