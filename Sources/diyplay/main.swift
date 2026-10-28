import Foundation

@main
struct Main {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        if args.isEmpty || args.first == "app" || args.first == "--background" {
            MenuBarApp.run(background: args.contains("--background"))
            return
        }
        CLI.run(args)
    }
}

enum CLI {
    static func run(_ args: [String]) {
        let cmd = args[0]
        switch cmd {
        case "status", "doctor":
            doctor(strict: cmd == "doctor")
        case "displays":
            for d in DisplayControl.listDisplays() {
                print("\(d.name)  vendor=\(d.vendor) product=\(d.product)  \(d.sizeText)")
            }
        case "apply":
            guard let d = DisplayControl.activeDisplay() else { fail("没有显示器") }
            apply(DisplayControl.preferredUI(d))
        case "native":
            guard args.count >= 2, let parsed = parseRes(args[1]),
                  let d = DisplayControl.activeDisplay()
            else {
                fputs("usage: diyplay native 2824x2160\n", stderr)
                exit(2)
            }
            do {
                try DisplayControl.setNative(d, width: parsed.w, height: parsed.h, presetId: nil)
                doctor(strict: false)
            } catch {
                fail(error.localizedDescription)
            }
        case "preset":
            guard args.count >= 2, let d = DisplayControl.activeDisplay(),
                  let preset = PresetBank.presets(vendor: d.vendor, product: d.product).first(where: { $0.id == args[1] })
            else {
                fputs("usage: diyplay preset phone|half|full\n", stderr)
                exit(2)
            }
            do {
                try DisplayControl.setNative(d, width: preset.width, height: preset.height, presetId: preset.id)
                doctor(strict: false)
            } catch {
                fail(error.localizedDescription)
            }
        case "res":
            guard args.count >= 2, let parsed = parseUI(args[1]) else {
                fputs("usage: diyplay res WxH[@2x|@1x]\n", stderr)
                exit(2)
            }
            apply(parsed.size, hiDPI: parsed.hiDPI)
        case "help", "-h", "--help":
            help()
        default:
            fputs("unknown command: \(cmd)\n", stderr)
            help()
            exit(2)
        }
    }

    static func help() {
        print("""
        diyplay — 菜单栏显示工具（识别显示器 + 物理分辨率 + HiDPI）

        不带参数：菜单栏与分辨率面板。--background：仅后台启动。

        displays
        status / doctor
        native WxH          设定物理分辨率
        preset phone|half|full   32C1U 预设
        res WxH[@2x|@1x]   看起来的大小；@2x 选 HiDPI，@1x 选像素 1:1
        apply
        """)
    }

    static func parseRes(_ s: String) -> (w: Int, h: Int)? {
        parseUI(s)?.size
    }

    /// "1920x2160" → either variant; "1920x2160@2x" / "@1x" → that variant.
    static func parseUI(_ s: String) -> (size: (w: Int, h: Int), hiDPI: Bool?)? {
        var body = s.lowercased().replacingOccurrences(of: "×", with: "x")
        var hiDPI: Bool?
        if let at = body.firstIndex(of: "@") {
            switch String(body[body.index(after: at)...]) {
            case "2x", "hi", "hidpi": hiDPI = true
            case "1x", "lo": hiDPI = false
            default: return nil
            }
            body = String(body[..<at])
        }
        let p = body.split(separator: "x")
        guard p.count == 2, let w = Int(p[0]), let h = Int(p[1]) else { return nil }
        return ((w, h), hiDPI)
    }

    static func doctor(strict: Bool) {
        guard let snap = DisplayControl.snapshot() else {
            print("display:     (none)")
            if strict { exit(1) }
            return
        }
        print("display:     \(snap.display.name)  vendor=\(snap.display.vendor) product=\(snap.display.product)")
        print("identified:  \(snap.display.sizeText)  timingId=\(snap.display.timingId.map(String.init) ?? "?")")
        print("physical:    \(snap.native.w)x\(snap.native.h)  preset=\(snap.presetId ?? "-")")
        if let ui = snap.ui {
            print("ui:          \(ui.pointsW)x\(ui.pointsH)  pixels \(ui.pixelsW)x\(ui.pixelsH)  \(String(format: "%.0f", ui.hz))Hz  hidpi=\(ui.hidpi)  \(ui.scaleText)")
            let variants = DisplayControl.variants(
                display: DisplayControl.mainExternalDisplay(),
                pointsW: ui.pointsW,
                pointsH: ui.pointsH
            )
            let hi = variants.hi.map { "\($0.pixelsW)x\($0.pixelsH)" } ?? "无"
            let lo = variants.lo.map { "\($0.pixelsW)x\($0.pixelsH)" } ?? "无"
            print("variants:    1x=\(lo)  hidpi=\(hi)")
        } else {
            print("ui:          (unavailable)")
        }
        print("override:    \(OverrideFile.path(vendor: snap.display.vendor, product: snap.display.product))")
        if snap.problems.isEmpty {
            print("doctor:      ok")
        } else {
            for b in snap.problems { print("doctor:      FAIL \(b)") }
            if strict { exit(1) }
        }
    }

    static func apply(_ looksLike: (w: Int, h: Int), hiDPI: Bool? = nil) {
        do {
            try DisplayControl.apply(looksLike: looksLike, hiDPI: hiDPI)
            doctor(strict: false)
        } catch {
            fail(error.localizedDescription)
        }
    }

    static func fail(_ message: String) -> Never {
        fputs("\(message)\n", stderr)
        exit(1)
    }
}
