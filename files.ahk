#Include utils.ahk
#Include PatternMatch.ahk

; 扫描文件 (支持递归 'R')
scanFiles(dir, pattern := '*', mode := 'F') {
    fun(consumer) {
        loop files dir '\' pattern, mode {
            consumer([A_LoopFileName, A_LoopFilePath, A_LoopFileTimeModified, A_LoopFileAttrib, A_LoopFileSize, A_LoopFileExt])
        }
    }
    if pattern == '*.*' and InStr(mode, 'F') and not InStr(mode, 'D') {
        return CallbackSeq(fun).filter(a => fileIsDir(a) or fileExt(a))
    } else {
        return CallbackSeq(fun)
    }
}

scanFilesLatest(dir, pattern := '*', mode := 'F') {
    return scanFiles(dir, pattern, mode).sortBy(fileModifiedTime, 'R')
}

; 结构化备份 (保持目录层级)
filesBackupStructured(desDir, subName, srcDir, filePathSeq) {
    targetBase := desDir '\' subName
    if !DirExist(targetBase)
        DirCreate(targetBase)
    
    srcLen := StrLen(srcDir)
    
    doCopy(srcPath) {
        ; 计算相对路径
        relPath := SubStr(srcPath, srcLen + 1)
        if (SubStr(relPath, 1, 1) != "\")
            relPath := "\" relPath
            
        destPath := targetBase relPath
        
        SplitPath(destPath, , &parentDir)
        if !DirExist(parentDir)
            DirCreate(parentDir)
            
        FileCopy(srcPath, destPath, 1) ; 覆盖
    }

    filePathSeq.consume(doCopy)
}

fileName(a) => a[1]
filePath(a) => a[2]
fileModifiedTime(a) => a[3]
fileAttrib(a) => a[4]
fileSize(a) => a[5]
fileExt(a) => a[6]
fileIsDir(a) => InStr(a[4], 'D')