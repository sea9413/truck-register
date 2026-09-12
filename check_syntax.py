#!/usr/bin/env python3
# 纯标准库 JS 结构检查：对 index.html 内联 <script> 做括号配对校验。
# 两步：① 线性清洗掉字符串/模板/注释/正则字面量（带迭代上限，避免死循环）；② 对纯净结构串做括号配对。
# 不是真 parser，挡不住"少了逗号"等语义错误，但能抓"漏写 }、字符串没闭合"等结构性低级错。
# 用法: python check_syntax.py [path/to/index.html]
import re, sys, os

try:
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
except Exception:
    pass


def extract_scripts(html):
    out = []
    for m in re.finditer(r'<script\b([^>]*)>(.*?)</script>', html, re.S | re.I):
        if re.search(r'\bsrc\s*=', m.group(1), re.I):
            continue
        out.append(m.group(2))
    return out


def sanitize(js):
    """把字符串/模板/注释/正则字面量替换成空格，返回仅含可见代码结构字符的串。"""
    out = []
    i, n = 0, len(js)
    guard = 0
    while i < n:
        guard += 1
        if guard > n * 12:
            raise RuntimeError("scan guard tripped (possible infinite loop)")
        c = js[i]
        if c == '\n':
            out.append(c)
            i += 1
            continue
        # 行注释
        if c == '/' and i + 1 < n and js[i + 1] == '/':
            while i < n and js[i] != '\n':
                i += 1
            continue
        # 块注释
        if c == '/' and i + 1 < n and js[i + 1] == '*':
            i += 2
            while i < n and not (js[i] == '*' and i + 1 < n and js[i + 1] == '/'):
                if js[i] == '\n':
                    out.append('\n')
                i += 1
            i += 2
            continue
        # 正则字面量（启发式：回跳空格后，上一个有意义的字符是 标识符/数字/)/]/}/引号 时为「除号」，否则为正则）
        if c == '/':
            k = i - 1
            while k >= 0 and js[k] == ' ':
                k -= 1
            prevC = js[k] if k >= 0 else ''
            prevIsValue = prevC and (prevC.isalnum() or prevC in ')]}\'"')
            if prevIsValue:
                out.append(c)
                i += 1
                continue
            j = i + 1
            inClass = False
            while j < n:
                if js[j] == '\\':
                    j += 2
                    continue
                if js[j] == '[':
                    inClass = True
                    j += 1
                    continue
                if js[j] == ']':
                    inClass = False
                    j += 1
                    continue
                if js[j] == '\n':
                    i = j + 1
                    break
                if js[j] == '/' and not inClass:
                    j += 1
                    while j < n and js[j].isalpha():
                        j += 1
                    i = j
                    break
                j += 1
            else:
                i += 1
            continue
        # 普通字符串
        if c in ('"', "'"):
            q = c
            i += 1
            while i < n:
                if js[i] == '\\':
                    i += 2
                    continue
                if js[i] == '\n':
                    out.append('\n')
                if js[i] == q:
                    i += 1
                    break
                i += 1
            continue
        # 模板字面量（含 ${ } 内 JS）
        if c == '`':
            i += 1
            while i < n:
                if js[i] == '\\':
                    i += 2
                    continue
                if js[i] == '`':
                    i += 1
                    break
                if js[i] == '$' and i + 1 < n and js[i + 1] == '{':
                    depth = 1
                    i += 2
                    while i < n and depth:
                        if js[i] == '{':
                            depth += 1
                        elif js[i] == '}':
                            depth -= 1
                        i += 1
                    continue
                if js[i] == '\n':
                    out.append('\n')
                i += 1
            continue
        out.append(c)
        i += 1
    return ''.join(out)


def check_balanced(clean, tag):
    pairs = {'}': '{', ')': '(', ']': '['}
    opens = set(pairs.values())
    stack = []
    line = 1
    for ch in clean:
        if ch == '\n':
            line += 1
            continue
        if ch in opens:
            stack.append((ch, line))
        elif ch in pairs:
            if not stack or stack[-1][0] != pairs[ch]:
                return f"[{tag}] unbalanced '{ch}' at line {line} (top={stack[-1] if stack else 'empty'})"
            stack.pop()
    if stack:
        return f"[{tag}] unclosed {stack[-1][0]} at line {stack[-1][1]}"
    return None


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), 'index.html')
    try:
        with open(path, encoding='utf-8') as f:
            html = f.read()
    except OSError as e:
        print("read fail:", e)
        sys.exit(2)
    scripts = extract_scripts(html)
    print(f"found {len(scripts)} inline <script> block(s)")
    ok = True
    for idx, js in enumerate(scripts):
        try:
            clean = sanitize(js)
        except RuntimeError as e:
            print("[ERR]", f"script#{idx + 1} {e}")
            ok = False
            continue
        err = check_balanced(clean, f"script#{idx + 1}")
        if err:
            print("[ERR]", err)
            ok = False
        else:
            print(f"[OK] script#{idx + 1} bracket/quote balanced ({len(js)} chars)")
    sys.exit(0 if ok else 1)


if __name__ == '__main__':
    main()
