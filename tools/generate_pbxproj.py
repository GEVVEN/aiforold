#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
生成 AIAssistant.xcodeproj/project.pbxproj 与共享 scheme。

为什么要用脚本生成?
    手写 .pbxproj 里每个文件要 3 处 UUID 引用，改一个文件就得改三处，
    极容易写坏；用脚本扫描目录 + 确定性 UUID，增删源文件只要重跑一次。

用法:
    python tools/generate_pbxproj.py            # 生成
    python tools/generate_pbxproj.py --check    # 只校验工程与源码是否一致
"""

import hashlib
import os
import sys

PROJECT_NAME = "AIAssistant"
APP_DIR = "AIAssistant"                  # .xcodeproj 同级的源码目录
BUNDLE_ID = "com.example.aiassistant"
DEPLOYMENT_TARGET = "12.0"
MARKETING_VERSION = "1.0.0"
CURRENT_PROJECT_VERSION = "1"
SWIFT_VERSION = "5.0"
# 只用 iPhone / iPad（"1,2"）；iPhone 5s 属于 1
TARGETED_DEVICE_FAMILY = "1,2"

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
XCODEPROJ = os.path.join(ROOT, PROJECT_NAME + ".xcodeproj")
PBXPROJ = os.path.join(XCODEPROJ, "project.pbxproj")

FILE_TYPES = {
    ".swift": "sourcecode.swift",
    ".storyboard": "file.storyboard",
    ".xcassets": "folder.assetcatalog",
    ".plist": "text.plist.xml",
    ".png": "image.png",
    ".md": "net.daringfireball.markdown",
    ".strings": "text.plist.strings",
    ".bundle": "wrapper.plug-in",
}

RESOURCE_EXTENSIONS = {".storyboard", ".xcassets", ".strings", ".bundle"}
# 这些目录本身就是一个"文件包"，不能递归进去单独引用里面的碎文件
PACKAGE_EXTENSIONS = {".xcassets", ".bundle", ".xcdatamodeld", ".lproj", ".framework"}


def pbx_quote(value):
    """pbxproj 的字符串：含特殊字符时要加引号。"""
    if value == "":
        return '""'
    if all(char.isalnum() or char in "._/$-" for char in value):
        return value
    return '"%s"' % value


def uid(*parts):
    """确定性 UUID：同样的输入永远得到同样的 24 位十六进制。"""
    key = "|".join(parts)
    return hashlib.md5(key.encode("utf-8")).hexdigest()[:24].upper()


class Node:
    """目录树节点。"""

    def __init__(self, name, rel_path):
        self.name = name
        self.rel_path = rel_path          # 相对于 ROOT 的路径，用于 UUID
        self.dirs = {}
        self.files = []                   # [(filename, rel_path)]

    def child(self, name):
        if name not in self.dirs:
            rel = os.path.join(self.rel_path, name) if self.rel_path else name
            self.dirs[name] = Node(name, rel)
        return self.dirs[name]


def scan():
    """扫描 APP_DIR，返回 (文件树, 源文件列表, 资源文件列表)。"""
    app_path = os.path.join(ROOT, APP_DIR)
    if not os.path.isdir(app_path):
        raise SystemExit("找不到源码目录: %s" % app_path)

    tree = Node(APP_DIR, APP_DIR)
    sources, resources, all_files = [], [], []

    for dirpath, dirnames, filenames in os.walk(app_path):
        packages = sorted(
            d for d in dirnames if os.path.splitext(d)[1].lower() in PACKAGE_EXTENSIONS
        )
        dirnames[:] = sorted(
            d for d in dirnames
            if d not in packages and d != "__pycache__" and not d.startswith(".")
        )
        rel_dir = os.path.relpath(dirpath, app_path)

        node = tree
        if rel_dir != ".":
            for part in rel_dir.split(os.sep):
                node = node.child(part)

        # 资源包（.xcassets 等）作为单个文件引用
        for package in packages:
            if os.path.splitext(package)[1].lower() not in FILE_TYPES:
                continue
            rel_path = os.path.join(APP_DIR, rel_dir, package).replace("\\", "/").replace("./", "")
            node.files.append((package, rel_path))
            all_files.append(rel_path)
            resources.append(rel_path)

        for filename in sorted(filenames):
            if filename.startswith("."):
                continue
            ext = os.path.splitext(filename)[1].lower()
            if ext not in FILE_TYPES:
                continue
            rel_path = os.path.join(APP_DIR, rel_dir, filename).replace("\\", "/")
            rel_path = rel_path.replace("./", "")
            node.files.append((filename, rel_path))
            all_files.append(rel_path)

            if ext == ".swift":
                sources.append(rel_path)
            elif ext in RESOURCE_EXTENSIONS:
                resources.append(rel_path)
            # Info.plist 只做引用，不进任何 build phase

    return tree, sources, resources, all_files


class Emitter:
    def __init__(self):
        self.entries = {}

    def add(self, section, key, body):
        self.entries.setdefault(section, []).append("\t\t%s %s" % (key, body))

    def render(self):
        out = []
        order = [
            "PBXBuildFile", "PBXFileReference", "PBXFrameworksBuildPhase",
            "PBXGroup", "PBXNativeTarget", "PBXProject", "PBXResourcesBuildPhase",
            "PBXSourcesBuildPhase", "XCBuildConfiguration", "XCConfigurationList",
        ]
        for section in order:
            out.append("/* Begin %s section */" % section)
            for line in self.entries.get(section, []):
                out.append(line)
            out.append("/* End %s section */" % section)
            out.append("")
        return "\n".join(out)


def build_settings(debug):
    common = {
        "ALWAYS_SEARCH_USER_PATHS": "NO",
        "CLANG_ANALYZER_NONNULL": "YES",
        "CLANG_ENABLE_MODULES": "YES",
        "CLANG_ENABLE_OBJC_ARC": "YES",
        "CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING": "YES",
        "CLANG_WARN_BOOL_CONVERSION": "YES",
        "CLANG_WARN_COMMA": "YES",
        "CLANG_WARN_CONSTANT_CONVERSION": "YES",
        "CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS": "YES",
        "CLANG_WARN_DIRECT_OBJC_ISA_USAGE": "YES",
        "CLANG_WARN_DOCUMENTATION_COMMENTS": "YES",
        "CLANG_WARN_EMPTY_BODY": "YES",
        "CLANG_WARN_ENUM_CONVERSION": "YES",
        "CLANG_WARN_INFINITE_RECURSION": "YES",
        "CLANG_WARN_INT_CONVERSION": "YES",
        "CLANG_WARN_OBJC_LITERAL_CONVERSION": "YES",
        "CLANG_WARN_OBJC_ROOT_CLASS": "YES",
        "CLANG_WARN_SUSPICIOUS_MOVE": "YES",
        "CLANG_WARN_UNREACHABLE_CODE": "YES",
        "CLANG_WARN__DUPLICATE_METHOD_MATCH": "YES",
        "COPY_PHASE_STRIP": "NO",
        "ENABLE_STRICT_OBJC_MSGSEND": "YES",
        "GCC_C_LANGUAGE_STANDARD": "gnu17",
        "GCC_NO_COMMON_BLOCKS": "YES",
        "GCC_WARN_64_TO_32_BIT_CONVERSION": "YES",
        "GCC_WARN_ABOUT_RETURN_TYPE": "YES",
        "GCC_WARN_UNDECLARED_SELECTOR": "YES",
        "GCC_WARN_UNINITIALIZED_AUTOS": "YES",
        "GCC_WARN_UNUSED_FUNCTION": "YES",
        "GCC_WARN_UNUSED_VARIABLE": "YES",
        "IPHONEOS_DEPLOYMENT_TARGET": DEPLOYMENT_TARGET,
        "SDKROOT": "iphoneos",
        "SWIFT_VERSION": SWIFT_VERSION,
        "ENABLE_USER_SCRIPT_SANDBOXING": "NO",
    }
    if debug:
        common.update({
            "DEBUG_INFORMATION_FORMAT": "dwarf",
            "ENABLE_TESTABILITY": "YES",
            "GCC_DYNAMIC_NO_PIC": "NO",
            "GCC_OPTIMIZATION_LEVEL": "0",
            "GCC_PREPROCESSOR_DEFINITIONS": '(\n\t\t\t\t\t"DEBUG=1",\n\t\t\t\t\t"$(inherited)",\n\t\t\t\t)',
            "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE",
            "ONLY_ACTIVE_ARCH": "YES",
            "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG",
            "SWIFT_OPTIMIZATION_LEVEL": '"-Onone"',
        })
    else:
        common.update({
            "DEBUG_INFORMATION_FORMAT": '"dwarf-with-dsym"',
            "ENABLE_NS_ASSERTIONS": "NO",
            "MTL_ENABLE_DEBUG_INFO": "NO",
            "SWIFT_COMPILATION_MODE": "wholemodule",
            "SWIFT_OPTIMIZATION_LEVEL": '"-O"',
            "VALIDATE_PRODUCT": "YES",
        })
    return common


def target_settings():
    return {
        "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
        "CODE_SIGN_STYLE": "Automatic",
        "CURRENT_PROJECT_VERSION": CURRENT_PROJECT_VERSION,
        "GENERATE_INFOPLIST_FILE": "NO",
        "INFOPLIST_FILE": "%s/Info.plist" % APP_DIR,
        "LD_RUNPATH_SEARCH_PATHS": '(\n\t\t\t\t\t"$(inherited)",\n\t\t\t\t\t"@executable_path/Frameworks",\n\t\t\t\t)',
        "MARKETING_VERSION": MARKETING_VERSION,
        "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE_ID,
        "PRODUCT_NAME": '"$(TARGET_NAME)"',
        "SWIFT_EMIT_LOC_STRINGS": "NO",
        "TARGETED_DEVICE_FAMILY": '"%s"' % TARGETED_DEVICE_FAMILY,
    }


def render_settings(settings, indent="\t\t\t\t"):
    lines = []
    for key in sorted(settings):
        lines.append("%s%s = %s;" % (indent, key, settings[key]))
    return "\n".join(lines)


def generate():
    tree, sources, resources, all_files = scan()

    em = Emitter()
    file_ref = {}       # rel_path -> uuid
    build_file = {}     # rel_path -> uuid

    # ---- PBXBuildFile + PBXFileReference
    for rel_path in all_files:
        ext = os.path.splitext(rel_path)[1].lower()
        file_type = FILE_TYPES.get(ext, "folder")
        name = os.path.basename(rel_path)
        ref = uid("ref", rel_path)
        file_ref[rel_path] = ref

        em.add("PBXFileReference", "%s /* %s */" % (ref, name),
               '= {isa = PBXFileReference; lastKnownFileType = %s; path = %s; sourceTree = "<group>"; };'
               % (file_type, pbx_quote(name)))

        if rel_path in sources or rel_path in resources:
            build = uid("build", rel_path)
            build_file[rel_path] = build
            phase = "Sources" if rel_path in sources else "Resources"
            em.add("PBXBuildFile", "%s /* %s in %s */" % (build, name, phase),
                   "= {isa = PBXBuildFile; fileRef = %s /* %s */; };" % (ref, name))

    # product
    product_ref = uid("ref", "PRODUCT")
    em.add("PBXFileReference", "%s /* %s.app */" % (product_ref, PROJECT_NAME),
           "= {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; "
           "path = %s.app; sourceTree = BUILT_PRODUCTS_DIR; };" % PROJECT_NAME)

    # ---- PBXGroup（递归）
    products_group = uid("group", "Products")

    def emit_group(node, parent_uuid):
        group_uuid = uid("group", node.rel_path)
        children = []
        for name in sorted(node.dirs):
            child_uuid = emit_group(node.dirs[name], group_uuid)
            children.append((child_uuid, node.dirs[name].name))
        for filename, rel_path in sorted(node.files, key=lambda item: item[0]):
            children.append((file_ref[rel_path], filename))

        body_lines = ["= {", "\t\t\tisa = PBXGroup;", "\t\t\tchildren = ("]
        for child_uuid, name in children:
            body_lines.append("\t\t\t\t%s /* %s */," % (child_uuid, name))
        body_lines.append("\t\t\t);")
        body_lines.append("\t\t\tpath = %s;" % pbx_quote(node.name))
        body_lines.append('\t\t\tsourceTree = "<group>";')
        body_lines.append("\t\t};")
        em.add("PBXGroup", "%s /* %s */" % (group_uuid, node.name), "\n".join(body_lines))
        return group_uuid

    app_group = emit_group(tree, None)

    root_group = uid("group", "ROOT")
    em.add("PBXGroup", "%s /* %s */" % (root_group, PROJECT_NAME),
           "\n".join([
               "= {",
               "\t\t\tisa = PBXGroup;",
               "\t\t\tchildren = (",
               "\t\t\t\t%s /* %s */," % (app_group, APP_DIR),
               "\t\t\t\t%s /* Products */," % products_group,
               "\t\t\t);",
               '\t\t\tsourceTree = "<group>";',
               "\t\t};",
           ]))

    em.add("PBXGroup", "%s /* Products */" % products_group,
           "\n".join([
               "= {",
               "\t\t\tisa = PBXGroup;",
               "\t\t\tchildren = (",
               "\t\t\t\t%s /* %s.app */," % (product_ref, PROJECT_NAME),
               "\t\t\t);",
               "\t\t\tname = Products;",
               '\t\t\tsourceTree = "<group>";',
               "\t\t};",
           ]))

    # ---- build phases
    sources_phase = uid("phase", "sources")
    frameworks_phase = uid("phase", "frameworks")
    resources_phase = uid("phase", "resources")

    source_lines = ["= {", "\t\t\tisa = PBXSourcesBuildPhase;", "\t\t\tbuildActionMask = 2147483647;", "\t\t\tfiles = ("]
    for rel_path in sources:
        source_lines.append("\t\t\t\t%s /* %s in Sources */," % (build_file[rel_path], os.path.basename(rel_path)))
    source_lines += ["\t\t\t);", "\t\t\trunOnlyForDeploymentPostprocessing = 0;", "\t\t};"]
    em.add("PBXSourcesBuildPhase", "%s /* Sources */" % sources_phase, "\n".join(source_lines))

    em.add("PBXFrameworksBuildPhase", "%s /* Frameworks */" % frameworks_phase,
           "\n".join(["= {", "\t\t\tisa = PBXFrameworksBuildPhase;",
                      "\t\t\tbuildActionMask = 2147483647;", "\t\t\tfiles = (", "\t\t\t);",
                      "\t\t\trunOnlyForDeploymentPostprocessing = 0;", "\t\t};"]))

    resource_lines = ["= {", "\t\t\tisa = PBXResourcesBuildPhase;", "\t\t\tbuildActionMask = 2147483647;", "\t\t\tfiles = ("]
    for rel_path in resources:
        resource_lines.append("\t\t\t\t%s /* %s in Resources */," % (build_file[rel_path], os.path.basename(rel_path)))
    resource_lines += ["\t\t\t);", "\t\t\trunOnlyForDeploymentPostprocessing = 0;", "\t\t};"]
    em.add("PBXResourcesBuildPhase", "%s /* Resources */" % resources_phase, "\n".join(resource_lines))

    # ---- configs
    project_debug = uid("config", "project", "debug")
    project_release = uid("config", "project", "release")
    target_debug = uid("config", "target", "debug")
    target_release = uid("config", "target", "release")
    project_config_list = uid("configlist", "project")
    target_config_list = uid("configlist", "target")

    em.add("XCBuildConfiguration", "%s /* Debug */" % project_debug,
           "= {\n\t\t\tisa = XCBuildConfiguration;\n\t\t\tbuildSettings = {\n%s\n\t\t\t};\n\t\t\tname = Debug;\n\t\t};"
           % render_settings(build_settings(True)))
    em.add("XCBuildConfiguration", "%s /* Release */" % project_release,
           "= {\n\t\t\tisa = XCBuildConfiguration;\n\t\t\tbuildSettings = {\n%s\n\t\t\t};\n\t\t\tname = Release;\n\t\t};"
           % render_settings(build_settings(False)))
    em.add("XCBuildConfiguration", "%s /* Debug */" % target_debug,
           "= {\n\t\t\tisa = XCBuildConfiguration;\n\t\t\tbuildSettings = {\n%s\n\t\t\t};\n\t\t\tname = Debug;\n\t\t};"
           % render_settings(target_settings()))
    em.add("XCBuildConfiguration", "%s /* Release */" % target_release,
           "= {\n\t\t\tisa = XCBuildConfiguration;\n\t\t\tbuildSettings = {\n%s\n\t\t\t};\n\t\t\tname = Release;\n\t\t};"
           % render_settings(target_settings()))

    em.add("XCConfigurationList", "%s /* Build configuration list for PBXProject */" % project_config_list,
           "\n".join(["= {", "\t\t\tisa = XCConfigurationList;", "\t\t\tbuildConfigurations = (",
                      "\t\t\t\t%s /* Debug */," % project_debug,
                      "\t\t\t\t%s /* Release */," % project_release,
                      "\t\t\t);", "\t\t\tdefaultConfigurationIsVisible = 0;",
                      "\t\t\tdefaultConfigurationName = Release;", "\t\t};"]))
    em.add("XCConfigurationList", "%s /* Build configuration list for PBXNativeTarget */" % target_config_list,
           "\n".join(["= {", "\t\t\tisa = XCConfigurationList;", "\t\t\tbuildConfigurations = (",
                      "\t\t\t\t%s /* Debug */," % target_debug,
                      "\t\t\t\t%s /* Release */," % target_release,
                      "\t\t\t);", "\t\t\tdefaultConfigurationIsVisible = 0;",
                      "\t\t\tdefaultConfigurationName = Release;", "\t\t};"]))

    # ---- target / project
    target_uuid = uid("target", PROJECT_NAME)
    em.add("PBXNativeTarget", "%s /* %s */" % (target_uuid, PROJECT_NAME),
           "\n".join([
               "= {",
               "\t\t\tisa = PBXNativeTarget;",
               "\t\t\tbuildConfigurationList = %s /* Build configuration list for PBXNativeTarget \"%s\" */;" % (target_config_list, PROJECT_NAME),
               "\t\t\tbuildPhases = (",
               "\t\t\t\t%s /* Sources */," % sources_phase,
               "\t\t\t\t%s /* Frameworks */," % frameworks_phase,
               "\t\t\t\t%s /* Resources */," % resources_phase,
               "\t\t\t);",
               "\t\t\tbuildRules = (",
               "\t\t\t);",
               "\t\t\tdependencies = (",
               "\t\t\t);",
               "\t\t\tname = %s;" % PROJECT_NAME,
               "\t\t\tproductName = %s;" % PROJECT_NAME,
               "\t\t\tproductReference = %s /* %s.app */;" % (product_ref, PROJECT_NAME),
               '\t\t\tproductType = "com.apple.product-type.application";',
               "\t\t};",
           ]))

    project_uuid = uid("project", PROJECT_NAME)
    em.add("PBXProject", "%s /* Project object */" % project_uuid,
           "\n".join([
               "= {",
               "\t\t\tisa = PBXProject;",
               "\t\t\tattributes = {",
               "\t\t\t\tBuildIndependentTargetsInParallel = 1;",
               "\t\t\t\tLastSwiftUpdateCheck = 1540;",
               "\t\t\t\tLastUpgradeCheck = 1540;",
               "\t\t\t\tTargetAttributes = {",
               "\t\t\t\t\t%s = {" % target_uuid,
               "\t\t\t\t\t\tCreatedOnToolsVersion = 15.4;",
               "\t\t\t\t\t};",
               "\t\t\t\t};",
               "\t\t\t};",
               "\t\t\tbuildConfigurationList = %s /* Build configuration list for PBXProject \"%s\" */;" % (project_config_list, PROJECT_NAME),
               '\t\t\tcompatibilityVersion = "Xcode 14.0";',
               "\t\t\tdevelopmentRegion = \"zh-Hans\";",
               "\t\t\thasScannedForEncodings = 0;",
               "\t\t\tknownRegions = (",
               "\t\t\t\t\"zh-Hans\",",
               "\t\t\t\ten,",
               "\t\t\t\tBase,",
               "\t\t\t);",
               "\t\t\tmainGroup = %s;" % root_group,
               "\t\t\tproductRefGroup = %s /* Products */;" % products_group,
               '\t\t\tprojectDirPath = "";',
               '\t\t\tprojectRoot = "";',
               "\t\t\ttargets = (",
               "\t\t\t\t%s /* %s */," % (target_uuid, PROJECT_NAME),
               "\t\t\t);",
               "\t\t};",
           ]))

    content = "// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {\n\t};\n\tobjectVersion = 56;\n\tobjects = {\n\n"
    content += em.render()
    content += "\n\t};\n\trootObject = %s /* Project object */;\n}\n" % project_uuid
    return content, sources, resources, all_files


def write_scheme():
    scheme_dir = os.path.join(XCODEPROJ, "xcshareddata", "xcschemes")
    os.makedirs(scheme_dir, exist_ok=True)
    # BuildableReference 的 BlueprintIdentifier 必须就是 target 的 UUID，
    # 否则 Xcode 的 Run / Archive 动作会找不到可执行产物。
    target_uuid = uid("target", PROJECT_NAME)
    scheme = """<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "1540" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{target}"
               BuildableName = "{name}.app"
               BlueprintName = "{name}"
               ReferencedContainer = "container:{name}.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
      </Testables>
   </TestAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{target}"
            BuildableName = "{name}.app"
            BlueprintName = "{name}"
            ReferencedContainer = "container:{name}.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{target}"
            BuildableName = "{name}.app"
            BlueprintName = "{name}"
            ReferencedContainer = "container:{name}.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
""".format(name=PROJECT_NAME, target=target_uuid)
    path = os.path.join(scheme_dir, PROJECT_NAME + ".xcscheme")
    with open(path, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(scheme)
    return path


def check():
    if not os.path.exists(PBXPROJ):
        print("[FAIL] 还没有生成 project.pbxproj，请先运行 python tools/generate_pbxproj.py")
        return 1
    content = open(PBXPROJ, encoding="utf-8").read()
    _, sources, resources, all_files = scan()

    problems = []
    for rel_path in all_files:
        name = os.path.basename(rel_path)
        if ("path = %s;" % name) not in content:
            problems.append("工程里缺少文件引用: %s" % rel_path)
    # 反向检查：工程里引用但磁盘上不存在的文件
    import re
    for match in re.finditer(r"lastKnownFileType = [^;]+; path = ([^;]+);", content):
        name = match.group(1).strip().strip('"')
        if name.endswith(".app"):
            continue
        found = any(os.path.basename(p) == name for p in all_files)
        if not found:
            problems.append("工程引用了不存在的文件: %s" % name)
    # UUID 唯一性
    uuids = re.findall(r"^\t\t([0-9A-F]{24}) ", content, re.MULTILINE)
    if len(uuids) != len(set(uuids)):
        problems.append("存在重复 UUID")

    if problems:
        print("[FAIL] 工程校验未通过：")
        for item in problems:
            print("   -", item)
        return 1
    print("[OK] 工程与源码一致：%d 个源文件，%d 个资源" % (len(sources), len(resources)))
    return 0


def main():
    if "--check" in sys.argv:
        return check()

    content, sources, resources, all_files = generate()
    os.makedirs(XCODEPROJ, exist_ok=True)
    with open(PBXPROJ, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(content)
    scheme = write_scheme()
    print("[OK] 已生成 %s" % os.path.relpath(PBXPROJ, ROOT))
    print("[OK] 已生成 %s" % os.path.relpath(scheme, ROOT))
    print("     源文件 %d 个，资源 %d 个，总文件 %d 个" % (len(sources), len(resources), len(all_files)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
