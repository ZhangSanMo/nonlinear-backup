#SingleInstance Force
#Include utils.ahk
#Include gui.ahk
#Include files.ahk

; 初始化全局应用实例
global App := BackupApp()
; 设置ICON图标
;@Ahk2Exe-SetMainIcon backup.ico

; ==============================================================================
; 快捷键定义 (Hotkeys)
; ==============================================================================

; 仅在备份程序的 GUI 激活时生效
#HotIf WinActive(App.title ' ahk_class AutoHotkeyGUI')
Enter:: App.execCmd('Enter')
^Up::   App.execCmd('CtrlUp')
^Down:: App.execCmd('CtrlDown')
Del::   App.execCmd('Del')
RButton::App.execCmd('RButton')
F1::    App.showHelp()
#HotIf

; 全局快捷键
#F5:: Reload  ; 重载脚本
#F6:: App.runHelper(bh => bh.saveFiles())       ; 新建备份
#F7:: App.runHelper(bh => bh.showSaves(false))  ; 查看存档树
#F8:: doCopy(display(procName()))               ; 复制当前进程名
#F9:: doCopy(display(WinGetTitle('A')))         ; 复制当前窗口标题

; ==============================================================================
; 主应用类 (BackupApp)
; ==============================================================================

class BackupApp {
    appName := '非线性备份'
    backupIni := 'backup.ini'
    
    ; 运行时状态
    cmdMap := Map()
    procMap := Map()
    treeListView := ""
    configLoaded := false ; 标记配置是否成功加载

    __New() {
        this.title := this.appName
        this.initCmdMap()
        this.loadConfig()
    }

    ; 初始化按键映射 (默认不做任何事)
    initCmdMap() {
        this.cmdMap := (['Enter', 'CtrlUp', 'CtrlDown', 'Del', 'RButton']).toMapWith(name => nothing)
    }

    ; 加载并解析 backup.ini
    loadConfig() {
        if not FileExist(this.backupIni) {
            this.createDefaultConfig()
            display('已生成默认配置文件: ' this.backupIni '`n请修改配置后按 Win+F5 重载', 5)
            return ; 此时不加载，等待用户修改
        }

        ; 读取配置文件，按小节分组
        lines := seqReadlines(this.backupIni)
            .filter(ln => ln and not ln.startsWith(';'))
            .mapSub(ln => ln.surroundedWith('[', ']'), (h, r) => this.parseSection(h, r))
            .toArr() 
        
        this.procMap := Map()
        for item in lines {
            name := item[1] ; 进程名 (e.g., "Code")
            cfg := item[2]  ; 配置 Map
            if !this.procMap.Has(name)
                this.procMap[name] := []
            this.procMap[name].Push(cfg)
        }

        if this.procMap.Count == 0 {
            display('配置文件中无有效配置，请检查 ' this.backupIni, 3)
            return
        }
        
        this.configLoaded := true
    }
    
    ; 创建默认配置文件
    createDefaultConfig() {
        defaultContent := "
        (
        ; 示例配置
        ; [进程名:存档名]
        ; dir = 需要备份的文件夹路径 ({user} 代表当前用户名)
        ; title = (可选) 窗口标题匹配规则，支持通配符*
        ; pattern = (可选) 包含的文件规则，默认为*
        
        [Notepad:NewProject]
        dir = C:\Users\{user}\Documents\TestSave
        title = *无标题*
        pattern = *.txt|*.log
        )"
        FileAppend(defaultContent, this.backupIni, "UTF-8")
    }

    ; 解析单个配置块 [Header]...
    parseSection(head, rest) {
        fullSection := SubStr(head, 2, StrLen(head) - 2)
        parts := StrSplit(fullSection, ':', , 2)
        procName := parts[1]
        
        ; 解析键值对
        configMap := rest
            .map(StrSplit.Bind(, '=', ' `t', 2))
            .filter(a => a.Length == 2)
            .toMap(a => a[1], a => a[2])
            
        ; 校验必要字段 dir
        if not configMap.getVal('dir', &dir) {
            display('配置 [' fullSection '] 缺失必要的 dir 字段，已跳过', 3)
            return [procName, Map()] ; 返回空Map稍后处理
        }
        
        dir := StrReplace(dir, '{user}', A_UserName)
        
        configMap['dir'] := dir
        configMap['section_name'] := fullSection
        
        return [procName, configMap]
    }

    ; 执行当前 GUI 绑定的命令
    execCmd(key) {
        if this.cmdMap.Has(key)
            this.cmdMap[key].Call()
    }

    ; 退出 GUI 并显示消息
    exitGuiWith(msg, sec) {
        exitGui(, g => display(msg, sec, true))
        this.initCmdMap() ; 重置命令防止误触
    }

    ; 核心入口：根据当前环境选择配置并运行操作
    runHelper(action) {
        if !this.configLoaded {
            display('配置未加载或格式错误，请检查 ' this.backupIni, 2)
            return
        }

        proc := procName()
        if not this.procMap.Has(proc) {
            display('当前进程 [' proc '] 未在配置中找到', 1)
            return
        }
            
        configs := this.procMap[proc]
        targetConfig := unset
        activeTitle := WinGetTitle('A')
        
        ; 匹配逻辑：
        ; 1. 优先匹配 match_title (支持正则/通配符)
        ; 2. 否则使用第一个没有 match_title 的配置作为默认
        for cfg in configs {
            ; 跳过无效配置（比如之前解析失败返回空Map的）
            if cfg.Count == 0 
                continue

            matchTitle := cfg.Get('title', '')
            if matchTitle != '' {
                if activeTitle.isWildcardMatch(matchTitle) {
                    targetConfig := cfg
                    break 
                }
            } else if not IsSet(targetConfig) {
                targetConfig := cfg 
            }
        }
        
        if IsSet(targetConfig) {
            ; 延迟检查：在实际要运行操作前，检查源目录是否存在
            srcDir := targetConfig.Get('dir', '')
            if !srcDir || !FileExist(srcDir) {
                display('错误：待存档目录不存在`n' srcDir, 3)
                return
            }

            configTitle := targetConfig.Get('title', '')
            if not configTitle or activeTitle.isWildcardMatch(configTitle) {
                action(NonlinearBackup(proc, targetConfig, this))
            }
        } else {
             display('未找到匹配当前窗口的配置', 1)
        }
    }

    showHelp() {
        g := makeGui('快捷键列表', g => g.Destroy())
        g.SetFont('s9', 'consolas')
        g.Opt('ToolWindow')
        content := "
        (
            游戏或工作界面
            Win+F5  : 重新加载配置
            Win+F6  : 新建存档备份
            Win+F7  : 打开存档树
            Win+F8  : 获取当前程序名
            Win+F9  : 获取当前窗口标题
            
            本应用界面
            ESC     : 退出当前窗口
            F1      : 快捷键列表
            
            存档树界面
            ↑/↓     : 选择存档
            Ctrl+↑  : 跳转最新子节点
            Ctrl+↓  : 跳转父节点
            Enter   : 载入/保存
            Delete  : 删除存档
            RButton : 重设父节点
        )"
        g.AddText('w210', content)
        g.Show()
    }
}

; ==============================================================================
; 备份逻辑类 (NonlinearBackup)
; ==============================================================================

class NonlinearBackup {
    static autoFunc := 'autoFunc'
    static autoText := 'autoText'

    __New(proc, config, appInstance) {
        this.proc := proc
        this.config := config
        this.app := appInstance
        this.src := config['dir']
        
        ; 计算目标存储路径
        saveRoot := A_WorkingDir '\Save'
        
        ; 如果配置头是 [Code:ProjectA]，文件夹名为 Code_ProjectA
        if (config.Has('section_name') && InStr(config['section_name'], ':')) {
            safeTag := RegExReplace(StrSplit(config['section_name'], ':',,2)[2], '[\\/:*?"<>|]', '_')
            this.target := saveRoot '\' proc '_' safeTag
        } else {
            this.target := saveRoot '\' proc
        }
        
        if !DirExist(this.target)
            DirCreate(this.target)

        ; 初始化 PatternMatch (支持 | 分隔多行规则)
        rawPattern := config.Get('pattern', '*')
        patternLines := StrReplace(rawPattern, '|', '`n')
        this.matcher := PatternMatch(patternLines)
        
        this.hotkey := config.Get('hotkey', '')
        this.keywait := config.getNum('keywait', &kw) ? kw : 0
        this.load()
    }

    static clearAuto(config) {
        config.Delete(NonlinearBackup.autoFunc)
        config.Delete(NonlinearBackup.autoText)
    }

    getAppTitle() {
        title := this.app.appName
        if this.config.getVal(NonlinearBackup.autoText, &text) {
            title .= ' (' text ')'
        }
        return title
    }

    loadHead() {
        return scanFiles(this.target).find(&res, f => not fileExt(f)) ? fileName(res) : ''
    }

    ; 加载所有存档节点
    load() {
        this.saves := scanFilesLatest(this.target, , 'D').mapOut(fileName)
        this.entries := this.saves.mapOut(f => StrSplit(f, '#', , 3))
        this.nodeIndexMap := this.entries.toIndexMap(e => e[1])
        this.entries.Push(['', '', '[双击打开路径]'])
    }

    getIndex(node, &index) {
        return node and this.nodeIndexMap.getVal(node, &index)
    }

    ; 执行保存逻辑
    doSave(saveName, auto, &msg) {
        ; 此处虽然外层已经检查过目录，但防止运行中被删除，可再做简单的容错
        if !FileExist(this.src) {
            msg := '源目录已失效'
            return false
        }

        ; 1. 递归扫描所有源文件
        allFiles := scanFiles(this.src, '*', 'FR')
        
        ; 2. 使用 PatternMatch 过滤 (基于相对路径)
        srcLen := StrLen(this.src)
        srcFiles := allFiles.filter(f => this.matcher.IsMatch(SubStr(filePath(f), srcLen + 1))).toArr()

        if srcFiles.Length == 0 {
             msg := '没有匹配的文件'
             return false
        }

        if not srcFiles.map(fileModifiedTime).max(&latestTime) {
            msg := '无法获取文件时间'
            return false
        }
        
        timestamp := timeEncode(latestTime)
        
        ; 检查是否与最新存档重复
        if this.entries.first(&fst) and timestamp == fst[1] {
            if not auto {
                if popupYesNo('重命名存档', '内容未变，已有存档: ' fst[3] '`n是否重命名?') {
                    this.renameSave(this.saves[1], fst[1], fst[2], saveName)
                    this.app.exitGuiWith(saveName ' - 已重命名', 3)
                }
            }
            return false
        }

        head := this.loadHead()
        if timestamp == head {
             if not auto and this.getIndex(head, &headIndex) {
                 if popupYesNo('重命名存档', 'HEAD 指针重合: ' this.entries[headIndex][3] '`n是否重命名?') {
                    this.renameSave(this.saves[headIndex], head, this.entries[headIndex][2], saveName)
                    this.app.exitGuiWith(saveName ' - 已重命名', 3)
                 }
            }
            return false
        }

        if not auto and this.entries.any(e => e[3] == saveName) {
            msg := '存档名称已存在'
            return false
        }

        if this.hotkey {
            if isWinActive(this.proc) {
                SendInput(this.hotkey)
                Sleep((this.keywait or 1) * 1000)
            }
        }
        
        ; 3. 执行结构化备份
        filesBackupStructured(this.target, timestamp '#' head '#' saveName, this.src, srcFiles.map(filePath))
        
        this.setHead(timestamp)
        
        ; 刷新 TreeView 如果存在
        lv := this.app.treeListView 
        if lv && WinExist(gcGetWinId(lv, &id) ? id : 0) {
            selections := lvGetAllSelected(lv).mapOut(i => i + 1)
            this.showSaves(true, selections*)
        }
        
        return true
    }
    
    ; ... (其余 NonlinearBackup 方法，checkAuto, saveFiles, showSaves 等保持原样，无需变动) ...
    checkAuto(saveName, &msg) {
        if not saveName.startsWith('=') {
            return false
        }
        sub := SubStr(saveName, 2)
        if sub.isFullMatch('[+-]?[0-9]+[hHmMsS]') {
            config := this.config
            len := StrLen(sub)
            num := Integer(SubStr(sub, 1, len - 1))
            
            if num == 0 {
                if config.getVal(NonlinearBackup.autoFunc, &timer) {
                    SetTimer(timer, 0)
                    NonlinearBackup.clearAuto(config)
                    this.app.exitGuiWith('关闭自动备份', 3)
                    return true
                }
                msg := '自动备份未开启'
                return true
            }
            
            unit := SubStr(sub, len)
            millis := num * 1000
            if unit = 'm' {
                millis *= 60
            } else if unit = 'h' {
                millis *= 3600
            }
            
            if config.getVal(NonlinearBackup.autoFunc, &old) {
                SetTimer(old, 0)
            }
            
            f() {
                if this.doSave(String(A_Now), true, &_) {
                    display(this.proc ' - 已自动备份')
                }
                this.load()
                if num < 0 { ; 负数表示仅运行一次
                    NonlinearBackup.clearAuto(config)
                }
            }
            
            config[NonlinearBackup.autoFunc] := f
            config[NonlinearBackup.autoText] := sub
            SetTimer(f, millis)
            this.app.exitGuiWith((num > 0 ? '开启自动备份：' : '预约备份：') sub, 3)
            return true
        } 
        msg := '自动备份语法错误'
        return true
    }

    saveFiles() {
        g := makeGlobalGui(this.getAppTitle(), '微软雅黑')
        gc := g.AddEdit('r1 w300', '新建备份')
        showGui()

        onEnter(ed) {
            saveName := ed.Value
            if this.checkAuto(saveName, &autoMsg) {
                return IsSet(autoMsg) ? autoMsg : ''
            }
            
            if saveName.isFullMatch('\s*') {
                return '不允许空名'
            }

            if saveName.hasMatch('[\\/:*?"<>|]') {
                return '包含非法字符'
            }
            
            if not this.doSave(saveName, false, &saveMsg) {
                if IsSet(saveMsg) and saveMsg
                    return saveMsg
            } else {
                this.app.exitGuiWith(saveName ' - 已保存', 3)
            }
        }
        this.app.cmdMap['Enter'] := wrapCmd(gc, onEnter)
    }

    showSaves(reload, selections*) {
        if reload
            this.load()
        size := this.entries.Length
        if size <= 1 {
            display('暂无备份')
            return
        }
        
        ; 检查未归档备份 (Bad Nodes)
        bad := this.entries.filter(e => e.Length < 3).mapOut(e => e[1])
        if bad.Length > 0 {
            if popupYesNo('归档确认', '发现未归档备份，是否统一归档(Y)或删除(N)?') {
                bad.reverse().fold('', (parent, folder) => (
                    id := timeEncode(FileGetTime(this.target '\' folder)),
                    this.renameSave(folder, id, parent, folder),
                    id
                ))
                msg := '备份已归档'
            } else {
                for folder in bad {
                    DirDelete(this.target '\' folder, true)
                }
                msg := '已删除未归档备份'
            }
            this.showSaves(true, 1)
            display(msg, 3, true)
            return
        }

        ; 构建树形结构文本 (Tree Building)
        rg := range(1, size - 1)
        parentArr := rg.mapOut(i => this.nodeIndexMap.Get(this.entries[i][2], size))
        childrenMap := rg.groupBy(itemGet(parentArr))
        tree := arrRepeatBy(size, () => arrRepeat(size, ' '))

        headIndex := this.nodeIndexMap.Get(this.loadHead(), 0)
        
        fillNode(i, j) {
            tree[i][j] := headIndex == i ? '╪' : '┼'
            if not childrenMap.getVal(i, &children) {
                return j
            }
            first := children[1]
            for k in range(first + 1, i - 1) {
                tree[k][j] := '│'
            }
            end := fillNode(first, j)
            count := children.Length
            for cIndex in range(2, count) {
                for k in range(j + 1, end) {
                    tree[i][k] := '─'
                }
                j := end + 1
                tree[i][j] := cIndex < count ? '┴' : '└'
                c := children[cIndex]
                for k in range(c + 1, i - 1) {
                    tree[k][end + 1] := '│'
                }
                end := fillNode(c, end + 1)
            }
            return end
        }
        end := fillNode(size, 1)

        beautifyRow(row) {
            a := arrRepeat((end << 1) - 1, ' ')
            for i in range(1, end) {
                s := row[i]
                a[(i << 1) - 1] := s
                if s == '└' or s == '┴' or s == '─' {
                    a[(i << 1) - 2] := '─'
                }
            }
            return a.reverse().join()
        }
        
        rows := this.entries.mapIndexedOut((i, e) => [beautifyRow(tree[i]) ' ' e[3], readableTime(timeDecode(e[1]))])

        this.app.treeListView := lv := listViewAll(['存档树', '时间'], rows, makeGlobalGui.Bind(this.getAppTitle()))
        lv.OnEvent('DoubleClick', (gc, index) => index == size ? Run(this.target) : 0)
        
        if selections.Length > 0 {
            for i in selections {
                lvSelect(lv, i)
            }
        } else {
            lvSelect(lv, headIndex or 1)
        }

        ; === 绑定树操作事件 ===
        
        ; 回车：还原存档
        onEnter(lv) {
            selected := lvGetAllSelected(lv).toArr()
            if selected.Length == 1 {
                index := selected[1]
                if index < size {
                    backupPath := this.target '\' this.saves[index]
                    
                    ; --- Robocopy 实现开始 ---
                    ; /MIR : 镜像模式（会删除源目录中没有但目标目录中有的文件，完全还原状态，慎用！）
                    ; /E   : 复制子目录，包括空的
                    ; /IS  : 即使文件相同也覆盖
                    ; /R:1 : 遇到错误重试 1 次
                    ; /W:1 : 重试等待 1 秒
                    exitCode := RunWait('robocopy "' backupPath '" "' this.src '" /E /IS /IT /R:1 /W:1', , "Hide")

                    ; 关键点：Robocopy 只要返回值小于 8，都代表“成功”
                    if (exitCode >= 8) {
                        return '还原失败 (Robocopy代码 ' exitCode ')'
                    }
                    ; --- Robocopy 实现结束 ---

                    this.changeHead(index)
                    this.app.exitGuiWith(this.entries[index][3] ' - 已还原', 3)
                } else {
                    return '虚拟根节点'
                }
            }
        }
        this.app.cmdMap['Enter'] := wrapCmd(lv, onEnter)

        ; 右键：修改父节点
        onRButton(lv) {
            selected := lvGetAllSelected(lv).toArr()
            if selected.Length == 2 {
                i := selected[1]
                j := selected[2]
                p := parentArr[i]
                if p == j and p == size {
                    return
                }
                this.changeParent(i, p == j ? size : j, true)
                this.showSaves(false, i, j)
            }
        }
        this.app.cmdMap['RButton'] := wrapCmd(lv, onRButton)

        ; Ctrl+Up：跳到最新子节点
        onCtrlUp(lv) {
            index := lv.GetNext()
            if childrenMap.getVal(index, &cr) {
                SendInput('{Up ' index - cr[1] '}')
            }
        }
        this.app.cmdMap['CtrlUp'] := wrapCmd(lv, onCtrlUp)

        ; Ctrl+Down：跳到父节点
        onCtrlDown(lv) {
            index := lv.GetNext()
            if index < size {
                SendInput('{Down ' parentArr[index] - index '}')
            }
        }
        this.app.cmdMap['CtrlDown'] := wrapCmd(lv, onCtrlDown)

        ; Delete：删除存档 (逻辑包含树结构重组)
        onDel(lv) {
            selectionSet := lvGetAllSelected(lv).toSet()
            if selectionSet.Has(0) or selectionSet.Has(size) {
                return
            }
            newParentMap := Map()
            for index in selectionSet {
                if childrenMap.getVal(index, &children) {
                    restChildren := children.filterOut(notIn(selectionSet))
                    if restChildren.Length == 0 {
                        continue
                    }
                    if restChildren.Length > 1 {
                        selectionSet.consume(i => lvSelect(lv, i))
                        return this.entries[index][3] ' 存在多个子节点，无法删除'
                    }
                    rest := restChildren[1]
                    newParentMap[rest] := moveUntil(rest, itemGet(parentArr), notIn(selectionSet))
                }
            }
            if not popupYesNo('删除存档', '是否删除以下存档？`n' selectionSet.join('`n', i => '- ' this.entries[i][3])) {
                return
            }
            
            ; 移动 Head 指针
            if this.getIndex(this.loadHead(), &headIndex) {
                headIndex := moveWhile(headIndex, itemGet(parentArr), isIn(selectionSet))
            }
            
            ; 物理删除
            for index in selectionSet {
                try DirDelete(this.target '\' this.saves[index], true)
            }
            
            ; 重连父子关系
            for i, p in newParentMap {
                if p < size {
                    this.changeParent(i, p)
                }
            }
            
            if IsSet(headIndex) {
                this.changeHead(headIndex)
            }
            
            this.app.exitGuiWith('存档已删除', 4)
            this.showSaves(true, 1)
        }
        this.app.cmdMap['Del'] := wrapCmd(lv, onDel)
    }
    
    ; 辅助：重命名/移动文件夹
    renameSave(from, id, parent, name) {
        DirMove(this.target '\' from, this.target '\' id '#' parent '#' name, 'R')
    }

    ; 辅助：设置 Head 指针文件
    setHead(timestamp) {
        head := this.loadHead()
        if head {
            if timestamp != head {
                try {
                    FileMove(this.target '\' head, this.target '\' timestamp)
                } catch Error {
                    ; 容错处理
                }
            }
        } else {
            FileAppend('', this.target '\' timestamp)
        }
    }

    changeHead(index) {
        this.setHead(this.entries[index][1])
    }

    changeParent(index, parent, inplace := false) {
        src := this.entries[index]
        des := this.entries[parent]
        this.renameSave(this.saves[index], src[1], des[1], src[3])
        if inplace {
            src[2] := des[1]
            this.saves[index] := src.join('#')
        }
    }
}