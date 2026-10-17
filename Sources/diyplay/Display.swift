import CoreGraphics
import Foundation
import IOKit

struct DisplayRecord {
    var name: String
    var vendor: Int
    var product: Int
    var pixelsW: Int
    var pixelsH: Int
    var timingId: Int?
}

struct UIMode {
    var pointsW: Int
    var pointsH: Int
    var pixelsW: Int
    var pixelsH: Int
    var hz: Double
    var hidpi: Bool
    var ref: CGDisplayMode
}

struct Snapshot {
    var display: DisplayRecord
    var native: (w: Int, h: Int)
    var presetId: String?
    var slider: [(w: Int, h: Int, label: String)]
    var ui: UIMode?
    var overrideInstalled: Bool

    var healthy: Bool {
        display.pixelsW == native.w && display.pixelsH == native.h
    }

    var problems: [String] {
        var bad: [String] = []
        if !healthy {
            bad.append("识别到 \(display.pixelsW)×\(display.pixelsH)，设定物理 \(native.w)×\(native.h)")
        }
        if !overrideInstalled { bad.append("缺少 display override") }
        return bad
    }
}

enum DisplayError: LocalizedError {
    case noDisplay
    case noMode(Int, Int)
    case configure(CGError)
    case overrideNotWritable
    case badSize

    var errorDescription: String? {
        switch self {
        case .noDisplay: return "没有显示器"
        case .noMode(let w, let h):
            return "没有 \(w)×\(h) 模式。改物理分辨率后请睡眠或拔插 HDMI 一次。"
        case .configure(let e): return "切分辨率失败 \(e.rawValue)"
        case .overrideNotWritable:
            return "无法写入 override。先运行一次 make install（需要 sudo）。"
        case .badSize: return "分辨率格式应为 宽x高，例如 2824x2160"
        }
    }
}

enum DisplayControl {
    private static let nativeWKey = "diyplay.nativeW."
    private static let nativeHKey = "diyplay.nativeH."
    private static let presetKey = "diyplay.preset."
    private static let uiWKey = "diyplay.uiW."
    private static let uiHKey = "diyplay.uiH."

    static func listDisplays() -> [DisplayRecord] {
        var result: [DisplayRecord] = []
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IOMobileFramebufferShim"),
            &iterator
        ) == KERN_SUCCESS else { return result }
        defer { IOObjectRelease(iterator) }
        while true {
            let svc = IOIteratorNext(iterator)
            if svc == 0 { break }
            defer { IOObjectRelease(svc) }
            guard let props = copyProps(svc) else { continue }
            let product = (props["DisplayAttributes"] as? NSDictionary)?["ProductAttributes"] as? NSDictionary
            let name = product?["ProductName"] as? String
            let vendor = intVal(product?["LegacyManufacturerID"])
            let prod = intVal(product?["ProductID"])
            let w = intVal(props["DisplayWidth"])
            let h = intVal(props["DisplayHeight"])
            guard w > 0, h > 0, let name, !name.isEmpty else { continue }
            result.append(
                DisplayRecord(
                    name: name,
                    vendor: vendor,
                    product: prod,
                    pixelsW: w,
                    pixelsH: h,
                    timingId: intVal(props["DPTimingModeId"])
                )
            )
        }
        return result
    }

    static func activeDisplay() -> DisplayRecord? {
        let all = listDisplays()
        guard let display = mainExternalDisplay() else { return all.first }
        return selectActiveDisplay(
            from: all,
            mainVendor: Int(CGDisplayVendorNumber(display)),
            mainProduct: Int(CGDisplayModelNumber(display))
        )
    }

    static func selectActiveDisplay(
        from displays: [DisplayRecord],
        mainVendor: Int,
        mainProduct: Int
    ) -> DisplayRecord? {
        displays.first { $0.vendor == mainVendor && $0.product == mainProduct } ?? displays.first
    }

    static func snapshot() -> Snapshot? {
        guard let d = activeDisplay() else { return nil }
        let native = selectedNative(d)
        let preset = resolvedPreset(d)
        let slider = slider(
            for: d,
            native: native,
            presetId: preset?.id,
            availableLooksLike: availableLooksLike()
        )
        return Snapshot(
            display: d,
            native: native,
            presetId: preset?.id,
            slider: slider,
            ui: currentUI(),
            overrideInstalled: FileManager.default.fileExists(atPath: OverrideFile.path(vendor: d.vendor, product: d.product))
        )
    }

    static func resolvedPreset(_ d: DisplayRecord) -> NativePreset? {
        let bank = PresetBank.presets(vendor: d.vendor, product: d.product)
        if let id = UserDefaults.standard.string(forKey: presetKey + d.key),
           let hit = bank.first(where: { $0.id == id })
        {
            return hit
        }
        let native = selectedNative(d)
        return bank.first { $0.width == native.w && $0.height == native.h }
    }

    static func selectedNative(_ d: DisplayRecord) -> (w: Int, h: Int) {
        let w = UserDefaults.standard.integer(forKey: nativeWKey + d.key)
        let h = UserDefaults.standard.integer(forKey: nativeHKey + d.key)
        if w > 0, h > 0 { return (w, h) }
        let bank = PresetBank.presets(vendor: d.vendor, product: d.product)
        if let hit = bank.first(where: { $0.width == d.pixelsW && $0.height == d.pixelsH }) {
            return hit.size
        }
        return (d.pixelsW, d.pixelsH)
    }

    static func preferredUI(_ d: DisplayRecord) -> (w: Int, h: Int) {
        let native = selectedNative(d)
        let steps = slider(
            for: d,
            native: native,
            presetId: resolvedPreset(d)?.id,
            availableLooksLike: availableLooksLike()
        )
        let w = UserDefaults.standard.integer(forKey: uiWKey + d.key)
        let h = UserDefaults.standard.integer(forKey: uiHKey + d.key)
        if steps.contains(where: { $0.w == w && $0.h == h }) { return (w, h) }
        if steps.isEmpty, let current = currentUI() { return (current.pointsW, current.pointsH) }
        return daily(from: steps, native: native)
    }

    static func setNative(_ d: DisplayRecord, width: Int, height: Int, presetId: String?) throws {
        guard width >= 640, height >= 480 else { throw DisplayError.badSize }
        try PhoneRemote.shared.restore()
        let steps = slider(for: d, native: (width, height), presetId: presetId)
        let ui = daily(from: steps, native: (width, height))
        try OverrideFile.write(
            vendor: d.vendor,
            product: d.product,
            native: (width, height),
            slider: steps.map { ($0.w, $0.h) },
            defaultUI: ui
        )
        let defaults = UserDefaults.standard
        defaults.set(width, forKey: nativeWKey + d.key)
        defaults.set(height, forKey: nativeHKey + d.key)
        defaults.set(presetId, forKey: presetKey + d.key)
        defaults.set(ui.w, forKey: uiWKey + d.key)
        defaults.set(ui.h, forKey: uiHKey + d.key)
        do {
            try apply(looksLike: ui)
        } catch DisplayError.noMode {
            throw DisplayError.noMode(ui.w, ui.h)
        }
    }

    static func apply(looksLike: (w: Int, h: Int)) throws {
        try PhoneRemote.shared.restore()
        guard let display = mainExternalDisplay() else { throw DisplayError.noDisplay }
        guard let mode = findMode(display: display, pointsW: looksLike.w, pointsH: looksLike.h) else {
            throw DisplayError.noMode(looksLike.w, looksLike.h)
        }
        var config: CGDisplayConfigRef?
        var err = CGBeginDisplayConfiguration(&config)
        guard err == .success, let config else { throw DisplayError.configure(err) }
        err = CGConfigureDisplayWithDisplayMode(config, display, mode.ref, nil)
        guard err == .success else {
            CGCancelDisplayConfiguration(config)
            throw DisplayError.configure(err)
        }
        err = CGCompleteDisplayConfiguration(config, .permanently)
        guard err == .success else { throw DisplayError.configure(err) }
        if let d = activeDisplay() {
            UserDefaults.standard.set(looksLike.w, forKey: uiWKey + d.key)
            UserDefaults.standard.set(looksLike.h, forKey: uiHKey + d.key)
        }
        usleep(300_000)
    }

    static func applyIfNeeded() {
        guard !PhoneRemote.shared.ownsConfiguration else { return }
        guard let d = activeDisplay() else { return }
        let snap = snapshot()
        let want = preferredUI(d)
        let uiOK = snap?.ui.map { $0.pointsW == want.w && $0.pointsH == want.h } ?? false
        if snap?.healthy == true, uiOK { return }
        let configured = UserDefaults.standard.object(forKey: nativeWKey + d.key) != nil
        if !configured, snap?.healthy == true { return }
        try? apply(looksLike: want)
    }

    static func slider(
        for d: DisplayRecord,
        native: (w: Int, h: Int),
        presetId: String?,
        availableLooksLike: Set<String>? = nil
    ) -> [(w: Int, h: Int, label: String)] {
        let proposed: [(w: Int, h: Int, label: String)]
        if let presetId,
           let preset = PresetBank.presets(vendor: d.vendor, product: d.product).first(where: { $0.id == presetId }),
           preset.width == native.w, preset.height == native.h
        {
            proposed = preset.resolvedSlider
        } else {
            proposed = Ladder.hidpi(nativeW: native.w, nativeH: native.h)
        }
        guard let availableLooksLike else { return proposed }
        var compatible = proposed.filter { availableLooksLike.contains("\($0.w)x\($0.h)") }
        guard !compatible.isEmpty, !compatible.contains(where: { $0.label == "日常" }) else {
            return compatible
        }

        let target = daily(from: proposed, native: native)
        let nearest = compatible.indices.min { left, right in
            let leftDistance = abs(compatible[left].w - target.w) + abs(compatible[left].h - target.h)
            let rightDistance = abs(compatible[right].w - target.w) + abs(compatible[right].h - target.h)
            return leftDistance < rightDistance
        }
        if let nearest { compatible[nearest].label = "日常" }
        return compatible
    }

    static func daily(from steps: [(w: Int, h: Int, label: String)], native: (w: Int, h: Int)) -> (w: Int, h: Int) {
        if let hit = steps.first(where: { $0.label == "日常" }) { return (hit.w, hit.h) }
        if steps.count >= 3 { return (steps[steps.count - 2].w, steps[steps.count - 2].h) }
        if let first = steps.first { return (first.w, first.h) }
        return (max(native.w / 2, 640), max(native.h / 2, 480))
    }

    static func mainExternalDisplay() -> CGDirectDisplayID? {
        if let normal = PhoneRemote.shared.normalDisplayID { return normal }
        var n: UInt32 = 0
        CGGetOnlineDisplayList(16, nil, &n)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(n))
        CGGetOnlineDisplayList(n, &ids, &n)
        let online = ids.prefix(Int(n))
        if let main = online.first(where: { CGDisplayIsMain($0) == 1 }) { return main }
        return online.first
    }

    static func currentUI() -> UIMode? {
        guard let display = mainExternalDisplay() else { return nil }
        guard let ref = CGDisplayCopyDisplayMode(display) else { return nil }
        return describe(ref)
    }

    static func availableLooksLike() -> Set<String> {
        PhoneRemote.shared.normalAvailableLooksLike ?? availableLooksLike(display: mainExternalDisplay())
    }

    static func availableLooksLike(display: CGDirectDisplayID?) -> Set<String> {
        guard let display else { return [] }
        let opts = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue!] as CFDictionary
        guard let all = CGDisplayCopyAllDisplayModes(display, opts) as? [CGDisplayMode] else { return [] }
        return Set(all.map { "\(Int($0.width))x\(Int($0.height))" })
    }

    static func findMode(display: CGDirectDisplayID, pointsW: Int, pointsH: Int) -> UIMode? {
        let opts = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue!] as CFDictionary
        guard let all = CGDisplayCopyAllDisplayModes(display, opts) as? [CGDisplayMode] else { return nil }
        let scored = all.map(describe).filter { $0.pointsW == pointsW && $0.pointsH == pointsH }
        return scored.max {
            let l = ($0.hidpi ? 1 : 0, $0.pixelsW * $0.pixelsH, Int($0.hz))
            let r = ($1.hidpi ? 1 : 0, $1.pixelsW * $1.pixelsH, Int($1.hz))
            return l < r
        }
    }

    static func describe(_ mode: CGDisplayMode) -> UIMode {
        let pw = Int(mode.pixelWidth)
        let ph = Int(mode.pixelHeight)
        let w = Int(mode.width)
        let h = Int(mode.height)
        return UIMode(
            pointsW: w,
            pointsH: h,
            pixelsW: pw == 0 ? w : pw,
            pixelsH: ph == 0 ? h : ph,
            hz: mode.refreshRate,
            hidpi: pw >= w * 2 && pw > 0,
            ref: mode
        )
    }

    private static func copyProps(_ svc: io_service_t) -> NSDictionary? {
        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(svc, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS else {
            return nil
        }
        return unmanaged?.takeRetainedValue() as NSDictionary?
    }

    private static func intVal(_ v: Any?) -> Int {
        if let n = v as? Int { return n }
        if let n = v as? NSNumber { return n.intValue }
        return 0
    }
}

extension DisplayRecord {
    var key: String { "\(vendor)-\(product)" }
    var sizeText: String { "\(pixelsW)×\(pixelsH)" }
}
