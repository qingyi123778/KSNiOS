#!/usr/bin/env python3
"""把 Resources/ksn.js 转成 C 字符串常量头文件。
Theos 打包时不想带资源目录，直接内嵌进二进制，运行时零文件依赖。
"""
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "Resources", "ksn.js")
OUT = os.path.join(ROOT, "Sources", "KSNJSData.h")


def escape(line):
    return line.replace("\\", "\\\\").replace('"', '\\"')


def main():
    if not os.path.exists(SRC):
        sys.exit("[embed] 找不到 %s" % SRC)

    with open(SRC, "r", encoding="utf-8") as f:
        text = f.read()

    lines = text.splitlines()
    body = "\n".join('    "%s\\n"' % escape(l) for l in lines)

    out = [
        "/* 自动生成，勿手改。源文件 Resources/ksn.js */",
        "#ifndef KSN_JS_DATA_H",
        "#define KSN_JS_DATA_H",
        "",
        "static const char kKSNJSSource[] =",
        body,
        ";",
        "",
        "#endif",
        "",
    ]

    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(out))

    print("[embed] %s -> %s  (%d lines, %d bytes)" % (SRC, OUT, len(lines), len(text)))


if __name__ == "__main__":
    main()
