#Include utils.ahk

globalGui := unset

makeGlobalGui(title?, font := 'consolas', fontOpt := 's10') {
    global globalGui
    if IsSet(globalGui) {
        globalGui.Destroy()
    }
    globalGui := makeGui(title?, exitGui)
    globalGui.SetFont(fontOpt, font)
    return globalGui
}

makeGui(title?, onEscape?) {
    g := Gui()
    if IsSet(title) {
        g.Title := title
    } else {
        g.Opt('-Caption')
    }
    if IsSet(onEscape) {
        g.OnEvent('Escape', onEscape)
        g.OnEvent('Close', onEscape)
    }
    return g
}

exitGui(g?, preAction?) {
    global globalGui
    if IsSet(preAction) {
        preAction(globalGui)
    }
    if IsSet(globalGui)
        globalGui.Destroy()
    globalGui := unset
}

showGui() {
    globalGui.Show('AutoSize')
}

wrapCmd(gc, callback) {
    cmd() {
        msg := callback(gc)
        if msg {
            display(msg, 2, true)
            return
        }
    }
    return cmd
}

popupYesNo(title, text) {
    return MsgBox(text, title, 'YesNo') == 'Yes'
}

estimateLen(str) {
    static edgeMap := (['│', '└', '┴', '─', '╪', '┼']).toMapWith(Ord)
    return seqSplit(str, '').sum(c => Ord(c) < 128 or edgeMap.Has(c) ? 7.5 : 15)
}

listViewAll(titles, rows, guiMaker := makeGlobalGui, maxHeight := 30) {
    if rows.Length = 0 {
        throw ValueError('Empty list')
    }
    colNum := rows[1].Length
    if titles.Length != colNum {
        throw ValueError('Title length mismatched with columns (' titles.Length ' != ' colNum ')')
    }
    g := guiMaker()

    estColWidth(i) {
        rows.maxBy(&_, r => estimateLen(r[i]), &maxLen)
        return Max(maxLen, estimateLen(titles[i]))
    }
    width := 11 * colNum + range(1, colNum).sum(estColWidth)
    height := Min(rows.Length, maxHeight)
    if height < rows.Length {
        width += 11
    }
    lv := g.AddListView('NoSortHdr w' width ' r' height, titles)
    rows.consume(row => lv.Add(, row*))

    lv.ModifyCol()
    lv.ModifyCol(colNum, 'AutoHdr')
    showGui()
    return lv
}

lvSelect(lv, i, positive := true) {
    lv.Modify(i, positive ? 'Select Focus' : '-Select -Focus')
}

lvGetAllSelected(lv) {
    fun() {
        j := 0
        return (&i) => i := j := lv.GetNext(j)
    }
    return EnumSeq(fun)
}

gcGetWinId(gc, &id) {
    try {
        return id := 'ahk_id ' ControlGetHwnd(gc)
    } catch Error {
    }
}