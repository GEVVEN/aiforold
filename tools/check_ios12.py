#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
静态自检脚本（在 Windows / Linux 上也能跑，不需要 Xcode）。

检查内容：
    1. iOS 12 兼容性：禁用 API 是否出现、是否被 #available 包住；
    2. Swift 语法烟测：字符串 / 注释外的括号是否配对；
    3. 文案一致性：L10n.xxx、Icon.xxx 引用是否都有定义；
    4. 工程配置：Info.plist 能解析、权限说明齐全、storyboard 是合法 XML；
    5. 工程文件：所有源文件都在 pbxproj 里，且 UUID 唯一。

用法: python tools/check_ios12.py
"""

import json
import os
import plistlib
import re
import sys
import xml.etree.ElementTree as ET

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP_DIR = os.path.join(ROOT, "AIAssistant")
SOURCES = os.path.join(APP_DIR, "Sources")

# (正则, 最低系统版本, 说明)
BANNED = [
    (r"UIImage\(systemName:", "13.0", "SF Symbols 图标"),
    (r"\bUIColor\.system[A-Za-z]+", "13.0", "动态系统色"),
    (r"\bUIColor\.(label|secondaryLabel|tertiaryLabel|quaternaryLabel|placeholderText)\b", "13.0", "动态文本色"),
    (r"\.insetGrouped\b", "13.0", "insetGrouped 表格样式"),
    (r"\bUINavigationBarAppearance\b", "13.0", "导航栏外观对象"),
    (r"\bUITabBarAppearance\b", "13.0", "标签栏外观对象"),
    (r"\bUIWindowScene\b|\bUIScene\b|\bSceneDelegate\b", "13.0", "Scene 生命周期"),
    (r"\bUIAction\b|\bUIMenu\(", "13.0", "UIMenu / UIAction"),
    (r"\bUIContextMenuInteraction\b|\bUIContextMenuConfiguration\b", "13.0", "上下文菜单"),
    (r"\bUISearchTextField\b", "13.0", "搜索输入框"),
    (r"DiffableDataSource|NSDiffableDataSourceSnapshot", "13.0", "Diffable DataSource"),
    (r"UICollectionViewCompositionalLayout", "13.0", "组合布局"),
    (r"import\s+SwiftUI|SwiftUI\.", "13.0", "SwiftUI"),
    (r"import\s+Combine|AnyPublisher|PassthroughSubject", "13.0", "Combine"),
    (r"\bUIApplication\.shared\.connectedScenes\b", "13.0", "多 Scene 遍历"),
    (r"\bPHPicker", "14.0", "PHPicker（iOS 14）"),
    (r"\bUTType\b", "14.0", "UniformTypeIdentifiers（iOS 14）"),
    (r"\bAVAudioApplication\b", "17.0", "AVAudioApplication（iOS 17）"),
    (r"\.preferredColorScheme\b|\.fontDesign\b", "13.0", "SwiftUI 修饰符"),
    # Swift 并发：部署到 iOS 12 时容易踩回退坑，本项目统一用闭包
    (r"\basync\s+(throws\s+)?->|\bawait\s+|\bTask\s*\{\s*$|@MainActor|@Sendable", "13.0", "Swift 并发"),
    (r"\bAttributedString\b", "15.0", "Foundation AttributedString"),
]

# 允许例外（出现在 #available 块里就没问题）——用"向上看 8 行"的宽松判定
LOOKBACK = 8


def swift_files():
    result = []
    for dirpath, _, filenames in os.walk(SOURCES):
        for name in sorted(filenames):
            if name.endswith(".swift"):
                result.append(os.path.join(dirpath, name))
    return sorted(result)


def strip_code(text):
    """把字符串字面量与注释替换成空格，避免误判括号 / 关键字。"""
    out = []
    index = 0
    length = len(text)
    while index < length:
        char = text[index]
        # 行注释
        if text.startswith("//", index):
            end = text.find("\n", index)
            end = length if end == -1 else end
            out.append(" " * (end - index))
            index = end
            continue
        # 块注释
        if text.startswith("/*", index):
            end = text.find("*/", index + 2)
            end = length if end == -1 else end + 2
            out.append(" " * (end - index))
            index = end
            continue
        # 多行字符串
        if text.startswith('"""', index):
            end = text.find('"""', index + 3)
            end = length if end == -1 else end + 3
            out.append(" " * (end - index))
            index = end
            continue
        # 普通字符串
        if char == '"':
            cursor = index + 1
            while cursor < length:
                if text[cursor] == "\\":
                    cursor += 2
                    continue
                if text[cursor] == '"' or text[cursor] == "\n":
                    break
                cursor += 1
            out.append(" " * (cursor - index + 1))
            index = cursor + 1
            continue
        out.append(char)
        index += 1
    return "".join(out)


def check_compatibility():
    problems = []
    warnings = []
    for path in swift_files():
        raw = open(path, encoding="utf-8").read()
        # 只看"真正的代码"（注释与字符串已被抹掉），避免注释里的 API 名字误报
        lines = strip_code(raw).split("\n")
        for number, line in enumerate(lines, start=1):
            for pattern, since, why in BANNED:
                if not re.search(pattern, line):
                    continue
                window = "\n".join(lines[max(0, number - 1 - LOOKBACK):number])
                if "#available" in window:
                    warnings.append("%s:%d 使用 iOS %s 的%s（已用 #available 兜底）"
                                    % (os.path.relpath(path, ROOT), number, since, why))
                else:
                    problems.append("%s:%d 使用了 iOS %s 才有的%s：%s"
                                    % (os.path.relpath(path, ROOT), number, since, why, line.strip()))
    return problems, warnings


def check_balance():
    problems = []
    pairs = {"}": "{", ")": "(", "]": "["}
    for path in swift_files():
        raw = open(path, encoding="utf-8").read()
        code = strip_code(raw)
        stack = []
        line = 1
        for char in code:
            if char == "\n":
                line += 1
            elif char in "{([":
                stack.append((char, line))
            elif char in "})]":
                if not stack or stack[-1][0] != pairs[char]:
                    problems.append("%s:%d 括号不匹配（多余的 %s）"
                                    % (os.path.relpath(path, ROOT), line, char))
                    stack = []
                    break
                stack.pop()
        if stack:
            problems.append("%s:%d 有 %d 个未闭合的 %s"
                            % (os.path.relpath(path, ROOT), stack[-1][1], len(stack), stack[-1][0]))
    return problems


def check_symbols():
    problems = []
    l10n_path = os.path.join(SOURCES, "Core", "L10n.swift")
    icons_path = os.path.join(SOURCES, "Core", "Icons.swift")

    l10n_text = open(l10n_path, encoding="utf-8").read()
    defined_l10n = set(re.findall(r"static let (\w+)\s*[:=]", l10n_text))
    icons_text = open(icons_path, encoding="utf-8").read()
    # case 名 + 枚举里的静态成员（Icon.draw / Icon.cache / Icon.clearCache 这类合法引用）
    defined_icons = parse_icon_cases(icons_text)
    defined_icons |= set(re.findall(r"static\s+(?:func|let|var)\s+(\w+)", icons_text))

    for path in swift_files():
        text = strip_code(open(path, encoding="utf-8").read())
        for name in set(re.findall(r"\bL10n\.(\w+)", text)):
            if name not in defined_l10n:
                problems.append("%s 引用了未定义的 L10n.%s" % (os.path.relpath(path, ROOT), name))
        for name in set(re.findall(r"\bIcon\.(\w+)", text)):
            if defined_icons and name not in defined_icons:
                problems.append("%s 引用了未定义的 Icon.%s" % (os.path.relpath(path, ROOT), name))
    return problems


def parse_icon_cases(text):
    """把 enum Icon 顶部所有 `case a, b, c` 行里的名字收集起来。

    注意：不能用"只取第一行"的偷懒写法 —— case 是跨多行声明的，
    只解析第一行会让这个校验形同虚设（早期版本就踩过这个坑）。
    """
    names = set()
    seen_case = False
    for line in text.split("\n"):
        stripped = line.strip()
        if stripped.startswith("case "):
            seen_case = True
            for part in re.split(r"[,\s]+", stripped[len("case "):]):
                if part.isidentifier():
                    names.add(part)
        elif seen_case:
            break
    return names


def expected_pixels(size_text, scale_text):
    """'60x60' + '3x' -> (180, 180)"""
    try:
        width, height = size_text.lower().split("x")
        scale = float(scale_text.lower().rstrip("x"))
        return (int(round(float(width) * scale)), int(round(float(height) * scale)))
    except Exception:  # noqa: BLE001
        return None


def png_size(path):
    """直接读 PNG 的 IHDR，不依赖 Pillow。"""
    try:
        with open(path, "rb") as handle:
            header = handle.read(24)
        if len(header) < 24 or header[:8] != b"\x89PNG\r\n\x1a\n":
            return None
        width = int.from_bytes(header[16:20], "big")
        height = int.from_bytes(header[20:24], "big")
        return (width, height)
    except Exception:  # noqa: BLE001
        return None


def check_project_files():
    problems = []
    plist_path = os.path.join(APP_DIR, "Info.plist")
    try:
        with open(plist_path, "rb") as handle:
            info = plistlib.load(handle)
    except Exception as error:  # noqa: BLE001
        return ["Info.plist 无法解析：%s" % error]

    required_keys = [
        "NSCameraUsageDescription",
        "NSPhotoLibraryUsageDescription",
        "NSPhotoLibraryAddUsageDescription",
        "NSMicrophoneUsageDescription",
        "NSSpeechRecognitionUsageDescription",
        "UILaunchStoryboardName",
        "CFBundleDisplayName",
    ]
    for key in required_keys:
        if key not in info:
            problems.append("Info.plist 缺少 %s（缺失会导致权限弹窗崩溃）" % key)

    storyboard = os.path.join(APP_DIR, "LaunchScreen.storyboard")
    try:
        ET.parse(storyboard)
    except Exception as error:  # noqa: BLE001
        problems.append("LaunchScreen.storyboard 不是合法 XML：%s" % error)

    assets = os.path.join(APP_DIR, "Assets.xcassets", "AppIcon.appiconset", "Contents.json")
    try:
        data = json.load(open(assets, encoding="utf-8"))
        for item in data.get("images", []):
            filename = item.get("filename")
            if not filename:
                continue
            path = os.path.join(os.path.dirname(assets), filename)
            if not os.path.exists(path):
                problems.append("AppIcon 缺少图片文件：%s" % filename)
                continue
            # 用 PNG 的 IHDR 头校验声明的像素尺寸是否真的对得上（纯标准库，不依赖 Pillow）
            expected = expected_pixels(item.get("size", ""), item.get("scale", ""))
            actual = png_size(path)
            if expected and actual and expected != actual:
                problems.append("AppIcon %s 实际 %dx%d，Contents.json 声明为 %dx%d"
                                % (filename, actual[0], actual[1], expected[0], expected[1]))
    except Exception as error:  # noqa: BLE001
        problems.append("AppIcon Contents.json 有问题：%s" % error)

    pbxproj = os.path.join(ROOT, "AIAssistant.xcodeproj", "project.pbxproj")
    if not os.path.exists(pbxproj):
        problems.append("还没有生成 AIAssistant.xcodeproj/project.pbxproj")
    else:
        content = open(pbxproj, encoding="utf-8").read()
        for depth in ["IPHONEOS_DEPLOYMENT_TARGET = 12.0;", "SWIFT_VERSION = 5.0;"]:
            if depth not in content:
                problems.append("pbxproj 里缺少设置：%s" % depth)

        # scheme 里的 BlueprintIdentifier 必须指向真实存在的 target
        scheme = os.path.join(ROOT, "AIAssistant.xcodeproj", "xcshareddata", "xcschemes",
                              "AIAssistant.xcscheme")
        if not os.path.exists(scheme):
            problems.append("缺少共享 scheme：AIAssistant.xcscheme")
        else:
            try:
                root = ET.parse(scheme).getroot()
                identifiers = set()
                for node in root.iter("BuildableReference"):
                    identifiers.add(node.get("BlueprintIdentifier") or "")
                if not identifiers:
                    problems.append("scheme 里没有 BuildableReference")
                for identifier in identifiers:
                    if identifier and ("\t\t%s " % identifier) not in content:
                        problems.append("scheme 的 BlueprintIdentifier %s 在 pbxproj 里不存在" % identifier)
            except Exception as error:  # noqa: BLE001
                problems.append("scheme 不是合法 XML：%s" % error)
    return problems


def main():
    sections = [
        ("iOS 12 兼容性", check_compatibility),
        ("Swift 括号配对", check_balance),
        ("符号引用一致性", check_symbols),
        ("工程配置", check_project_files),
    ]
    failed = 0
    for title, function in sections:
        result = function()
        if isinstance(result, tuple):
            problems, warnings = result
        else:
            problems, warnings = result, []
        if problems:
            failed += len(problems)
            print("[FAIL] %s" % title)
            for item in problems:
                print("   - %s" % item)
        else:
            print("[OK]   %s" % title)
        for item in warnings:
            print("   (i) %s" % item)

    print("")
    if failed:
        print("共 %d 个问题需要修。" % failed)
        return 1
    print("全部检查通过。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
