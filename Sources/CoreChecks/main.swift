import CoreGraphics
import Foundation
@testable import LauncherCore

struct NamingTests {
    func slugFoldsAccentsAndSpaces() {
        check(InstanceName.slug(from: "Lavoro Ufficio") == "lavoro-ufficio")
        check(InstanceName.slug(from: "  Città  #2 ") == "citta-2")
        check(InstanceName.slug(from: "ÄÖÜ") == "aou")
        check(InstanceName.slug(from: "!!!") == "")
    }

    func validation() {
        check(InstanceName.validate("work", existing: []) == nil)
        check(InstanceName.validate("", existing: []) == .empty)
        check(InstanceName.validate("Work", existing: []) == .invalidCharacters)
        check(InstanceName.validate("a b", existing: []) == .invalidCharacters)
        check(InstanceName.validate("default", existing: []) == .reserved)
        check(InstanceName.validate("work", existing: ["work"]) == .taken)
    }

    func displayNames() {
        check(LauncherBuilder.isValidDisplayName("Work"))
        check(!LauncherBuilder.isValidDisplayName("  "))
        check(!LauncherBuilder.isValidDisplayName("a/b"))
        check(!LauncherBuilder.isValidDisplayName(".hidden"))
    }

    func tintDegreesRoundTrip() {
        var tint = Tint(hueShift: 135)
        check(abs(tint.degrees - 189.84) < 0.01)
        tint.degrees = 90
        check(tint.hueShift == 64)
        check(Tint(hueShift: 256).isStock)
        check(!Tint(hueShift: 0, satGain: 0).isStock)
    }
}

struct ConfigTests {
    func parsesLegacyScriptConfig() {
        let config = LauncherConfig.parse("INSTANCE_NAME=work\n")
        check(config == LauncherConfig(instance: "work", tint: nil))
    }

    func roundTripsTint() {
        let original = LauncherConfig(instance: "personal", tint: Tint(hueShift: -7, satGain: 1.08))
        check(LauncherConfig.parse(original.text) == original)
    }

    func toleratesQuotesAndComments() {
        let config = LauncherConfig.parse("# hi\nINSTANCE_NAME=\"x\"\nHUE_SHIFT=80\n")
        check(config?.instance == "x")
        check(config?.tint == Tint(hueShift: 80))
        check(LauncherConfig.parse("FOO=1") == nil)
    }

    func roundTripsBadge() {
        let original = LauncherConfig(instance: "work", tint: .stock, badge: Badge(color: .green, text: "wrk"))
        check(original.text.contains("BADGE_TEXT='WRK'"))
        check(LauncherConfig.parse(original.text) == original)
        let dotOnly = LauncherConfig(instance: "work", tint: nil, badge: Badge(color: .blue))
        check(!dotOnly.text.contains("BADGE_TEXT"))
        check(LauncherConfig.parse(dotOnly.text) == dotOnly)
        // Unknown colors (e.g. a hand-edited file) mean no badge.
        check(LauncherConfig.parse("INSTANCE_NAME=x\nBADGE_COLOR=red\n")?.badge == nil)
    }

    func normalizesBadgeText() {
        check(Badge.normalize("work") == "WOR")
        check(Badge.normalize("a'b c;") == "ABC")
        check(Badge.normalize("$(x)") == "X")
        check(Badge.normalize("é1") == "É1")
        check(Badge(color: .blue, text: "lavoro").text == "LAV")
    }

    func badgeStaysInsideTheIcon() {
        let size = 128
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        // A white rounded square inset like a real macOS icon.
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        ctx.addPath(CGPath(roundedRect: CGRect(x: 12.5, y: 12.5, width: 103, height: 103),
                           cornerWidth: 23, cornerHeight: 23, transform: nil))
        ctx.fillPath()
        let icon = ctx.makeImage()!
        guard let out = IconTinter.applying(Badge(color: .black), to: icon),
              let before = icon.dataProvider?.data as Data?,
              let data = out.dataProvider?.data as Data? else { return check(false) }
        // CGImage rows go top to bottom.
        func px(_ d: Data, _ x: Int, _ y: Int) -> (UInt8, UInt8) { (d[(y * size + x) * 4], d[(y * size + x) * 4 + 3]) }
        check(px(data, 96, 96).0 < 60)           // dark badge in the bottom-right corner
        check(px(data, 30, 30).0 == 255)         // top-left untouched
        check(px(data, 96, 30).0 == 255)         // top-right untouched (Dock badges go there)
        // Silhouette unchanged: macOS 26 boxes icons whose shape is not standard.
        var outside = 0
        for y in 0..<size { for x in 0..<size where px(before, x, y).1 == 0 && px(data, x, y).1 != 0 { outside += 1 } }
        check(outside == 0)
    }
}

struct CloneTests {
    func findsStrayClones() {
        let base = "/Users/me/Library/Application Support/Double Trouble/Clones.noindex"
        let ps = """
          101 00:12 \(base)/work/Claude.app/Contents/MacOS/Claude
          102 01:02:03 \(base)/work/Claude.app/Contents/MacOS/Claude --user-data-dir=/Users/me/.claude-instances/work
          103 00:05 \(base)/work/Claude.app/Contents/Frameworks/Claude Helper.app/Contents/MacOS/Claude Helper --type=gpu-process
          104 2-00:00:01 \(base)/default/Claude.app/Contents/MacOS/Claude
          105 00:30 /Applications/Claude.app/Contents/MacOS/Claude
        """
        let strays = ProcessInspector.strays(psOutput: ps, clonesBase: base)
        check(strays == [ProcessInspector.Stray(instance: "work", pid: 101, seconds: 12)])
        check(ProcessInspector.elapsedSeconds("2-00:00:01") == 172801)
        check(ProcessInspector.elapsedSeconds("01:02:03") == 3723)
        check(ProcessInspector.elapsedSeconds("x") == nil)
    }

    func clonesAreStillDetectedAsRunning() {
        let clone = "/Users/me/Library/Application Support/Double Trouble/Clones.noindex/work/Claude.app"
        let flag = "--user-data-dir=/Users/me/.claude-instances/work"
        let ps = "201 \(clone)/Contents/MacOS/Claude \(flag)\n"
            + "202 \(clone)/Contents/Frameworks/Claude Helper (Renderer).app/Contents/MacOS/Claude Helper (Renderer) --type=renderer \(flag)\n"
        let running = ProcessInspector.parse(psOutput: ps, instancesBase: "/Users/me/.claude-instances")
        check(running["work"] == RunningState(pid: 201, windows: 1))
        check(running["default"] == nil)
    }

    func upgradesOldScriptsOnly() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cl-up-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let macOS = root.appendingPathComponent("Claude X.app/Contents/MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        try "INSTANCE_NAME=x\n".write(to: macOS.appendingPathComponent("config.sh"), atomically: true, encoding: .utf8)
        try "#!/bin/bash\nold\n".write(to: macOS.appendingPathComponent("claude-launcher"), atomically: true, encoding: .utf8)
        let app = root.appendingPathComponent("Claude X.app")
        let first = try LauncherBuilder.upgradeScript(of: app)
        check(first)
        let written = try String(contentsOf: macOS.appendingPathComponent("claude-launcher"), encoding: .utf8)
        check(written == LauncherScript.text)
        let second = try LauncherBuilder.upgradeScript(of: app)
        check(!second)
        check(LauncherScript.text.contains(LauncherScript.marker))
        // The script hardcodes the clones folder: it must match Paths.
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        check(LauncherScript.text.contains("slot=\"$HOME" + Paths.live.clones.path.dropFirst(home.count) + "/$INSTANCE_NAME\""))
    }
}

struct MigrationTests {
    func movesLaunchersAndDropsIdleClones() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("cl-mig-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let fm = FileManager.default
        let old = home.appendingPathComponent("Library/Application Support/Claude Launcher")
        try fm.createDirectory(at: old.appendingPathComponent("Launchers/Claude A.app"), withIntermediateDirectories: true)
        try fm.createDirectory(at: old.appendingPathComponent("Clones.noindex/a/Claude.app"), withIntermediateDirectories: true)
        Paths.migrateLegacySupportFolder(home: home)
        let new = home.appendingPathComponent("Library/Application Support/Double Trouble")
        check(fm.fileExists(atPath: new.appendingPathComponent("Launchers/Claude A.app").path))
        check(!fm.fileExists(atPath: old.path))
        Paths.migrateLegacySupportFolder(home: home) // nothing left: no-op
        check(fm.fileExists(atPath: new.appendingPathComponent("Launchers/Claude A.app").path))
    }
}

/// Runs pieces of the real launcher script in bash, against fake data.
struct ScriptTests {
    /// The script's functions, without the final dispatch and without sourcing config.sh.
    func functions() -> String {
        let text = LauncherScript.text
        let cut = text.range(of: "[ \"$INSTANCE_NAME\" = \"default\" ] && plain=")!.lowerBound
        return String(text[..<cut]).replacingOccurrences(of: ". \"$here/config.sh\"", with: ":")
    }

    func bash(_ body: String, env: [String: String]) throws -> String {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("dt-sh-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("t.sh")
        try (functions() + "\n" + body + "\n").write(to: file, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [file.path]
        process.environment = env.merging(["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]) { a, _ in a }
        let out = Pipe()
        process.standardOutput = out
        try process.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func scanMatchesRealProcessLayout() throws {
        let home = "/Users/me"
        let clone = "\(home)/Library/Application Support/Double Trouble/Clones.noindex/work/Claude.app"
        let renderer = "Contents/Frameworks/Claude Helper (Renderer).app/Contents/MacOS/Claude Helper (Renderer)"
        let flag = "--user-data-dir=\(home)/.claude-instances/work"
        let ps = """
          100 /Applications/Claude.app/Contents/MacOS/Claude
          101 /Applications/Claude.app/\(renderer) --type=renderer
          102 /Applications/Claude.app/Contents/Frameworks/Electron Framework.framework/Helpers/chrome_crashpad_handler
          200 \(clone)/Contents/MacOS/Claude \(flag)
          201 \(clone)/\(renderer) --type=renderer \(flag) --lang=en
          202 \(clone)/Contents/Frameworks/Claude Helper.app/Contents/MacOS/Claude Helper --type=gpu-process \(flag)
          300 /Applications/Claude.app/Contents/MacOS/Claude \(flag)2
          400 grep -F -- \(flag) Claude.app/Contents/
          500 /Applications/Claude Work.app/Contents/MacOS/claude-launcher
        """
        let fake = "ps() { cat <<'PS'\n\(ps)\nPS\n}"
        func scan(_ instance: String, plain: String) throws -> String {
            try bash(fake + "\nscan \(plain) | tr '\\n' ' '", env: ["HOME": home, "INSTANCE_NAME": instance])
        }
        checkTrying(try scan("work", plain: "no") == "main 200 window")
        checkTrying(try scan("work2", plain: "no") == "main 300")     // "work" must not match "work2"
        checkTrying(try scan("other", plain: "no") == "")
        checkTrying(try scan("default", plain: "yes") == "main 100 window")
    }

    func olderComparesNumerically() throws {
        let out = try bash("""
            older 4.9.0 4.10.0 && echo a
            older 4.10.0 4.9.0 || echo b
            older 4.1.0 4.1.0 || echo c
            """, env: [:])
        check(out == "a\nb\nc")
    }

    func copyLifecycle() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("dt-copy-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        func fakeApp(_ url: URL, version: String) throws {
            try fm.createDirectory(at: url.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
            let binary = url.appendingPathComponent("Contents/MacOS/Claude")
            try "#!/bin/sh\n".write(to: binary, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
            try setVersion(url, version)
        }
        func setVersion(_ url: URL, _ version: String) throws {
            let plist = try PropertyListSerialization.data(fromPropertyList: ["CFBundleVersion": version], format: .xml, options: 0)
            try plist.write(to: url.appendingPathComponent("Contents/Info.plist"))
        }
        let source = root.appendingPathComponent("Claude.app")
        try fakeApp(source, version: "4.100.0")
        let slot = root.appendingPathComponent("slot")
        let copy = slot.appendingPathComponent("Claude.app")
        // A real .icns, so setting the Finder icon is exercised too.
        let icon = root.appendingPathComponent("icon.icns")
        try IconTinter.writeTintedIcon(ofApp: URL(fileURLWithPath: "/System/Applications/Calculator.app"), to: icon, tint: .stock)
        let env = ["HOME": root.path, "INSTANCE_NAME": "work"]
        let vars = "claude_app='\(source.path)'; slot='\(slot.path)'; copy='\(copy.path)'; icon='\(icon.path)'"
        func prepare() throws -> String {
            try bash(vars + "\nprepare_copy && echo ok; version_of \"$copy\"; [ -e \"$copy/Icon\"$'\\r' ] && echo icon", env: env)
        }
        func inode() -> Int { ((try? fm.attributesOfItem(atPath: copy.appendingPathComponent("Contents/Info.plist").path))?[.systemFileNumber] as? Int) ?? -1 }

        checkTrying(try prepare() == "ok\n4.100.0\nicon")                 // first clone, with icon
        let first = inode()
        checkTrying(try prepare() == "ok\n4.100.0\nicon")
        check(inode() == first)                                     // nothing to do: not cloned again
        try setVersion(source, "4.101.0")
        checkTrying(try prepare() == "ok\n4.101.0\nicon")                 // Claude.app updated: cloned again
        try setVersion(copy, "4.102.0")
        try fm.removeItem(at: copy.appendingPathComponent("Icon\r"))
        checkTrying(try prepare() == "ok\n4.102.0\nicon")                 // copy updated itself: kept, icon back
        try setVersion(source, "4.102.0")
        let beforeCatchUp = inode()
        checkTrying(try prepare() == "ok\n4.102.0\nicon")
        check(inode() != beforeCatchUp)                             // Claude.app caught up: cloned again
        try fm.removeItem(at: root.appendingPathComponent("Claude.app"))
        try fm.removeItem(at: slot)
        let missing = (try? prepare()) ?? "error"
        check(missing == "")                                        // nothing to clone: fails, caller falls back
    }
}

struct TintTests {
    func stockLeavesPixelsAlone() {
        let (r, g, b) = IconTinter.tint(r: 217, g: 119, b: 87, with: .stock)
        check(r == 217 && g == 119 && b == 87)
    }

    func rotatesOrangeTowardsBlue() {
        let (r, g, b) = IconTinter.tint(r: 217, g: 119, b: 87, with: Tint(hueShift: 135))
        check(b > r && b > g)
    }

    func zeroSaturationIsGray() {
        let (r, g, b) = IconTinter.tint(r: 217, g: 119, b: 87, with: Tint(hueShift: 0, satGain: 0))
        check(r == g && g == b)
    }

    func grayStaysGray() {
        let (r, g, b) = IconTinter.tint(r: 120, g: 120, b: 120, with: Tint(hueShift: 100, satGain: 2))
        check(r == 120 && g == 120 && b == 120)
    }
}

struct ProcessTests {
    let base = "/Users/me/.claude-instances"
    let bin = "/Applications/Claude.app/Contents/MacOS/Claude"
    // As seen in ps: windows are renderer helpers, not the app binary.
    let renderer = "/Applications/Claude.app/Contents/Frameworks/Claude Helper (Renderer).app/Contents/MacOS/Claude Helper (Renderer)"
    let helper = "/Applications/Claude.app/Contents/Frameworks/Claude Helper.app/Contents/MacOS/Claude Helper"
    let crashpad = "/Applications/Claude.app/Contents/Frameworks/Electron Framework.framework/Helpers/chrome_crashpad_handler"

    func findsInstancesAndWindows() {
        let ps = """
          101 \(bin) --user-data-dir=\(base)/work
          102 \(renderer) --type=renderer --user-data-dir=\(base)/work --lang=it
          103 \(helper) --type=gpu-process --user-data-dir=\(base)/work
          104 \(crashpad) --user-data-dir=\(base)/work
          201 \(bin) --user-data-dir=\(base)/work2
          301 \(bin)
          302 \(renderer) --type=renderer
          303 \(renderer) --type=renderer
          400 /Applications/Claude Work.app/Contents/MacOS/claude-launcher
          500 grep -F -- --user-data-dir=\(base)/work
        """
        let state = ProcessInspector.parse(psOutput: ps, instancesBase: base)
        check(state["work"] == RunningState(pid: 101, windows: 1))
        check(state["work2"] == RunningState(pid: 201, windows: 0))
        check(state["default"] == RunningState(pid: 301, windows: 2))
        check(state.count == 3)
    }
}

struct BuilderTests {
    /// A fake world in a temp folder, with a real-looking Claude.app and icon.
    func makeWorld() throws -> (Paths, URL) {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("cl-tests-\(UUID().uuidString)")
        let paths = Paths(
            claudeApp: root.appendingPathComponent("Applications/Claude.app"),
            instancesBase: root.appendingPathComponent("instances"),
            defaultProfile: root.appendingPathComponent("default-profile"),
            staging: root.appendingPathComponent("staging"),
            applications: root.appendingPathComponent("Applications"),
            userApplications: root.appendingPathComponent("UserApplications"))
        let resources = paths.claudeApp.appendingPathComponent("Contents/Resources")
        try fm.createDirectory(at: resources, withIntermediateDirectories: true)
        let realIcon = URL(fileURLWithPath: "/Applications/Claude.app/Contents/Resources/electron.icns")
        if fm.fileExists(atPath: realIcon.path) {
            try fm.copyItem(at: realIcon, to: resources.appendingPathComponent("electron.icns"))
        }
        return (paths, root)
    }

    func builder(_ paths: Paths) -> LauncherBuilder {
        var b = LauncherBuilder(paths: paths)
        b.registerWithSystem = false
        return b
    }

    func createScanEditMoveLifecycle() throws {
        let (paths, root) = try makeWorld()
        defer { try? FileManager.default.removeItem(at: root) }
        let b = builder(paths)
        let scanner = Scanner(paths: paths)

        let created = try b.create(LauncherSpec(instance: "work", displayName: "Work", tint: Tint(hueShift: 135),
                                                badge: Badge(color: .teal, text: "W")),
                                   in: paths.staging)
        check(created.lastPathComponent == "Claude Work.app")
        check(FileManager.default.isExecutableFile(atPath: created.appendingPathComponent("Contents/MacOS/claude-launcher").path))
        check(FileManager.default.fileExists(atPath: paths.instancesBase.appendingPathComponent("work").path))

        var records = scanner.scan()
        check(records.count == 1)
        check(records[0].primary?.displayName == "Work")
        check(records[0].primary?.tint == Tint(hueShift: 135))
        check(records[0].primary?.badge == Badge(color: .teal, text: "W"))
        check(records[0].primary?.location == .staging)
        check(!records[0].isInstalled)

        // Same name twice is refused.
        expectThrows {
            try b.create(LauncherSpec(instance: "other", displayName: "Work", tint: .stock), in: paths.staging)
        }

        let renamed = try b.update(created, to: LauncherSpec(instance: "work", displayName: "Ufficio", tint: Tint(hueShift: 80)))
        check(!FileManager.default.fileExists(atPath: created.path))
        let installed = try b.move(renamed, to: paths.applications)

        records = scanner.scan()
        check(records.count == 1)
        check(records[0].primary?.url.path == installed.path)
        check(records[0].primary?.displayName == "Ufficio")
        check(records[0].primary?.tint == Tint(hueShift: 80))
        check(records[0].primary?.badge == nil)
        check(records[0].isInstalled)
    }

    func orphanProfilesAndRedundantCopies() throws {
        let (paths, root) = try makeWorld()
        defer { try? FileManager.default.removeItem(at: root) }
        let b = builder(paths)
        try FileManager.default.createDirectory(at: paths.instancesBase.appendingPathComponent("lost"),
                                                withIntermediateDirectories: true)
        let spec = LauncherSpec(instance: "work", displayName: "Work", tint: .stock)
        try b.create(spec, in: paths.staging)
        try b.create(spec, in: paths.applications)

        let records = Scanner(paths: paths).scan()
        check(records.map(\.name) == ["work", "lost"])
        check(records[1].isOrphan)
        check(records[0].primary?.location == .applications)
        check(Scanner.redundantStagingCopies(in: records).map(\.lastPathComponent) == ["Claude Work.app"])
    }

    func readsLauncherMadeByOriginalScript() throws {
        let (paths, root) = try makeWorld()
        defer { try? FileManager.default.removeItem(at: root) }
        let app = paths.applications.appendingPathComponent("Claude Personal.app")
        let macOS = app.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        try "INSTANCE_NAME=personal\n".write(to: macOS.appendingPathComponent("config.sh"), atomically: true, encoding: .utf8)
        let plist: NSDictionary = ["CFBundleName": "Claude Personal", "CFBundleDisplayName": "Claude Personal"]
        plist.write(to: app.appendingPathComponent("Contents/Info.plist"), atomically: true)

        let records = Scanner(paths: paths).scan()
        check(records.first?.displayName == "Personal")
        check(records.first?.primary?.tint == nil)
    }

    func estimatesTintOfLegacyIcons() throws {
        guard let icon = Paths.live.claudeIcon, let base = IconTinter.loadImage(icon, pixelSize: 128) else { return }
        for original in [Tint(hueShift: 135), Tint(hueShift: -7, satGain: 1.08), Tint(hueShift: 80), Tint(hueShift: 0)] {
            let tinted = try require(IconTinter.tint(base, with: original))
            let guess = try require(IconTinter.estimateTint(of: tinted, base: base))
            check(abs(guess.hueShift - original.hueShift) <= 3)
        }
        let gray = try require(IconTinter.tint(base, with: Tint(hueShift: 0, satGain: 0)))
        check(IconTinter.estimateTint(of: gray, base: base)?.satGain == 0)
    }

    func stockIconMatchesWhatMacOSShows() throws {
        let app = URL(fileURLWithPath: "/Applications/Claude.app")
        guard FileManager.default.fileExists(atPath: app.path) else { return }
        let (paths, root) = try makeWorld()
        defer { try? FileManager.default.removeItem(at: root) }
        let out = root.appendingPathComponent("stock.icns")
        try IconTinter.writeTintedIcon(ofApp: app, to: out, tint: .stock)
        let written = try require(IconTinter.loadImage(out, pixelSize: 256))
        let shown = try require(IconTinter.appIcon(app, pixelSize: 256))
        let a = try require(IconTinter.colorStats(written)), b = try require(IconTinter.colorStats(shown))
        check(abs(a.hue - b.hue) < 0.005 && abs(a.saturation - b.saturation) < 0.01)
        _ = paths
    }

    func tintedIconIsWritten() throws {
        let (paths, root) = try makeWorld()
        defer { try? FileManager.default.removeItem(at: root) }
        let out = root.appendingPathComponent("out.icns")
        try IconTinter.writeTintedIcon(ofApp: URL(fileURLWithPath: "/Applications/Claude.app"), to: out, tint: Tint(hueShift: 135))
        let image = try require(IconTinter.loadImage(out, pixelSize: 256))
        check(image.width >= 256)
    }
}


struct CodeTests {
    func makeWorld() throws -> (CodePaths, URL) {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent("cl-code-\(UUID().uuidString)")
        try fm.createDirectory(at: home.appendingPathComponent(".config/fish/functions"), withIntermediateDirectories: true)
        let paths = CodePaths(home: home, bin: home.appendingPathComponent(".local/bin"),
                              shellFiles: [home.appendingPathComponent(".config/fish/config.fish"),
                                           home.appendingPathComponent(".zshrc")],
                              fishFunctions: home.appendingPathComponent(".config/fish/functions"))
        return (paths, home)
    }

    func scriptRoundTrip() {
        let home = URL(fileURLWithPath: "/Users/me")
        let text = CodeScript.text(displayName: "Lavoro d'ufficio", configDir: URL(fileURLWithPath: "/Users/me/.claude-o'brien"))
        let parsed = CodeScript.parse(text, home: home)
        check(parsed?.displayName == "Lavoro d'ufficio")
        check(parsed?.configDir.path == "/Users/me/.claude-o'brien")
        check(CodeScript.parse("#!/bin/sh\nexport CLAUDE_CONFIG_DIR=/x\n", home: home) == nil)
    }

    func parsesAliasesInEveryShell() {
        let home = URL(fileURLWithPath: "/Users/me")
        let fish = ShellAliases.parseAliasLine("alias claude-work='CLAUDE_CONFIG_DIR=$HOME/.claude-work claude'", home: home)
        check(fish?.command == "claude-work")
        check(fish?.configDir?.path == "/Users/me/.claude-work")
        let fish2 = ShellAliases.parseAliasLine("  alias claude-x \"CLAUDE_CONFIG_DIR=~/.claude-x claude\"", home: home)
        check(fish2?.command == "claude-x" && fish2?.configDir?.path == "/Users/me/.claude-x")
        let zsh = ShellAliases.parseAliasLine("alias claude-y=\"CLAUDE_CONFIG_DIR=\\\"/opt/y\\\" claude\"", home: home)
        check(zsh?.command == "claude-y")
        check(ShellAliases.parseAliasLine("alias ll='ls -la'", home: home) == nil)
        check(ShellAliases.parseAliasLine("# alias claude-work='CLAUDE_CONFIG_DIR=x claude'", home: home) == nil)
        let fn = ShellAliases.configDir(in: "function claude-z\n  set -x CLAUDE_CONFIG_DIR $HOME/.claude-z\n  claude $argv\nend", home: home)
        check(fn?.path == "/Users/me/.claude-z")
    }

    func createScanAdoptDelete() throws {
        let fm = FileManager.default
        let (paths, home) = try makeWorld()
        defer { try? fm.removeItem(at: home) }

        // Main profile with settings and a login; an existing aliased profile.
        let main = paths.mainConfigDir
        try fm.createDirectory(at: main.appendingPathComponent("skills/s1"), withIntermediateDirectories: true)
        try "{}".write(to: main.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)
        try "x".write(to: main.appendingPathComponent("history.jsonl"), atomically: true, encoding: .utf8)
        try #"{"oauthAccount":{"emailAddress":"me@home.it"}}"#.write(to: home.appendingPathComponent(".claude.json"), atomically: true, encoding: .utf8)
        let work = home.appendingPathComponent(".claude-work")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        try #"{"oauthAccount":{"emailAddress":"me@work.io","organizationName":"Acme"}}"#.write(to: work.appendingPathComponent(".claude.json"), atomically: true, encoding: .utf8)
        try "set -g x 1\nalias claude-work='CLAUDE_CONFIG_DIR=$HOME/.claude-work claude'\n".write(
            to: paths.shellFiles[0], atomically: true, encoding: .utf8)
        try fm.createDirectory(at: home.appendingPathComponent(".claude-instances/desktop"), withIntermediateDirectories: true)

        let scanner = CodeScanner(paths: paths)
        var envs = scanner.scan()
        check(envs.map(\.displayName) == ["Principale", "Work"])
        check(envs[0].isMain && envs[0].account?.email == "me@home.it")
        check(envs[1].needsCommand && envs[1].aliases.count == 1)
        check(envs[1].account == CodeAccount(email: "me@work.io", organization: "Acme"))

        // Adopt: script + alias disabled.
        let manager = CodeManager(paths: paths)
        try manager.writeScript(command: "claude-work", displayName: "Work", configDir: work)
        try ShellAliases.disable(envs[1].aliases[0])
        envs = scanner.scan()
        check(envs[1].command == "claude-work" && envs[1].aliases.isEmpty && !envs[1].needsCommand)
        check(fm.isExecutableFile(atPath: paths.bin.appendingPathComponent("claude-work").path))
        let fish = try String(contentsOf: paths.shellFiles[0], encoding: .utf8)
        check(fish.contains("# [disabled by Double Trouble") && fish.hasPrefix("set -g x 1\n"))
        let backups = try fm.contentsOfDirectory(atPath: home.appendingPathComponent(".config/fish").path)
        check(backups.contains { $0.hasPrefix("config.fish.bak-claude-launcher-") })

        // Create with copied config: settings and skills yes, history no.
        check(CodeManager.validate(name: "work", existingDirs: [], paths: paths) == .taken)
        check(CodeManager.validate(name: "instances", existingDirs: [], paths: paths) == .reserved)
        check(CodeManager.validate(name: "client", existingDirs: [], paths: paths) == nil)
        try manager.create(name: "client", displayName: "Cliente", copyConfigFrom: paths.mainConfigDir)
        let client = paths.configDir(for: "client")
        check(fm.fileExists(atPath: client.appendingPathComponent("settings.json").path))
        check(fm.fileExists(atPath: client.appendingPathComponent("skills/s1").path))
        check(!fm.fileExists(atPath: client.appendingPathComponent("history.jsonl").path))
        envs = scanner.scan()
        check(envs.map(\.displayName) == ["Principale", "Cliente", "Work"])
        check(envs[1].account == nil)

        // Copy from a non-main profile: only what that profile has.
        try "x".write(to: work.appendingPathComponent("CLAUDE.md"), atomically: true, encoding: .utf8)
        try manager.create(name: "client2", displayName: "Cliente 2", copyConfigFrom: work)
        let client2 = paths.configDir(for: "client2")
        check(fm.fileExists(atPath: client2.appendingPathComponent("CLAUDE.md").path))
        check(!fm.fileExists(atPath: client2.appendingPathComponent("settings.json").path))
        check(!fm.fileExists(atPath: client2.appendingPathComponent(".claude.json").path))
        try manager.create(name: "empty", displayName: "Vuoto", copyConfigFrom: nil)
        check((try? fm.contentsOfDirectory(atPath: paths.configDir(for: "empty").path))?.isEmpty == true)
        envs = scanner.scan()
        try manager.delete(envs.first { $0.name == "client2" }!, includingConfig: true)
        try manager.delete(envs.first { $0.name == "empty" }!, includingConfig: true)
        envs = scanner.scan()

        // Someone else's script is never overwritten.
        try "#!/bin/sh\necho hi\n".write(to: paths.bin.appendingPathComponent("claude-other"), atomically: true, encoding: .utf8)
        expectThrows { try manager.writeScript(command: "claude-other", displayName: "x", configDir: client) }

        try manager.delete(envs[1], includingConfig: true)
        check(!fm.fileExists(atPath: client.path))
        check(scanner.scan().map(\.displayName) == ["Principale", "Work"])
    }
}

// Minimal test harness: Swift Testing / XCTest are not usable with the
// Command Line Tools alone. Run with `swift run CoreChecks`.
nonisolated(unsafe) var failures = 0
nonisolated(unsafe) var checks = 0

func check(_ condition: @autoclosure () -> Bool, file: StaticString = #file, line: UInt = #line) {
    checks += 1
    if !condition() { failures += 1; print("  ✗ \(file):\(line)") }
}

/// `check` for expressions that can throw: an error counts as a failure.
func checkTrying(_ condition: @autoclosure () throws -> Bool, file: StaticString = #file, line: UInt = #line) {
    checks += 1
    do {
        if try !condition() { failures += 1; print("  ✗ \(file):\(line)") }
    } catch {
        failures += 1; print("  ✗ \(file):\(line) threw \(error)")
    }
}

func expectThrows(file: StaticString = #file, line: UInt = #line, _ body: () throws -> Void) {
    checks += 1
    do { try body(); failures += 1; print("  ✗ expected error at \(file):\(line)") } catch {}
}

struct RequireError: Error {}
func require<T>(_ value: T?, file: StaticString = #file, line: UInt = #line) throws -> T {
    guard let value else { failures += 1; print("  ✗ require failed \(file):\(line)"); throw RequireError() }
    return value
}

func run(_ name: String, _ body: () throws -> Void) {
    let before = failures
    do { try body() } catch { failures += 1; print("  ✗ \(name) threw \(error)") }
    print(failures == before ? "✓ \(name)" : "✗ \(name)")
}

run("NamingTests.slugFoldsAccentsAndSpaces") { NamingTests().slugFoldsAccentsAndSpaces() }
run("NamingTests.validation") { NamingTests().validation() }
run("NamingTests.displayNames") { NamingTests().displayNames() }
run("NamingTests.tintDegreesRoundTrip") { NamingTests().tintDegreesRoundTrip() }
run("ConfigTests.parsesLegacyScriptConfig") { ConfigTests().parsesLegacyScriptConfig() }
run("ConfigTests.roundTripsTint") { ConfigTests().roundTripsTint() }
run("ConfigTests.toleratesQuotesAndComments") { ConfigTests().toleratesQuotesAndComments() }
run("ConfigTests.roundTripsBadge") { ConfigTests().roundTripsBadge() }
run("ConfigTests.normalizesBadgeText") { ConfigTests().normalizesBadgeText() }
run("ConfigTests.badgeStaysInsideTheIcon") { ConfigTests().badgeStaysInsideTheIcon() }
run("CloneTests.findsStrayClones") { CloneTests().findsStrayClones() }
run("CloneTests.clonesAreStillDetectedAsRunning") { CloneTests().clonesAreStillDetectedAsRunning() }
run("CloneTests.upgradesOldScriptsOnly") { try CloneTests().upgradesOldScriptsOnly() }
run("MigrationTests.movesLaunchersAndDropsIdleClones") { try MigrationTests().movesLaunchersAndDropsIdleClones() }
run("ScriptTests.scanMatchesRealProcessLayout") { try ScriptTests().scanMatchesRealProcessLayout() }
run("ScriptTests.olderComparesNumerically") { try ScriptTests().olderComparesNumerically() }
run("ScriptTests.copyLifecycle") { try ScriptTests().copyLifecycle() }
run("TintTests.stockLeavesPixelsAlone") { TintTests().stockLeavesPixelsAlone() }
run("TintTests.rotatesOrangeTowardsBlue") { TintTests().rotatesOrangeTowardsBlue() }
run("TintTests.zeroSaturationIsGray") { TintTests().zeroSaturationIsGray() }
run("TintTests.grayStaysGray") { TintTests().grayStaysGray() }
run("ProcessTests.findsInstancesAndWindows") { ProcessTests().findsInstancesAndWindows() }
run("BuilderTests.createScanEditMoveLifecycle") { try BuilderTests().createScanEditMoveLifecycle() }
run("BuilderTests.orphanProfilesAndRedundantCopies") { try BuilderTests().orphanProfilesAndRedundantCopies() }
run("BuilderTests.readsLauncherMadeByOriginalScript") { try BuilderTests().readsLauncherMadeByOriginalScript() }
run("BuilderTests.estimatesTintOfLegacyIcons") { try BuilderTests().estimatesTintOfLegacyIcons() }
run("BuilderTests.stockIconMatchesWhatMacOSShows") { try BuilderTests().stockIconMatchesWhatMacOSShows() }
run("BuilderTests.tintedIconIsWritten") { try BuilderTests().tintedIconIsWritten() }
run("CodeTests.scriptRoundTrip") { CodeTests().scriptRoundTrip() }
run("CodeTests.parsesAliasesInEveryShell") { CodeTests().parsesAliasesInEveryShell() }
run("CodeTests.createScanAdoptDelete") { try CodeTests().createScanAdoptDelete() }
print("\n\(checks) controlli, \(failures) falliti")
exit(failures == 0 ? 0 : 1)
