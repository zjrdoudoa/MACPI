import Foundation

extension Notification.Name {
    static let appLanguageDidChange = Notification.Name("MACPIAppLanguageDidChange")
}

enum AppLanguage: String, CaseIterable {
    case automatic
    case zhHans
    case zhHant
    case cantonese
    case english

    private static let defaultsKey = "MACPIAppLanguage"

    var menuTitle: String {
        switch self {
        case .automatic:
            return L10n.text(zh: "跟随系统", zhHant: "跟隨系統", yue: "跟系統", en: "Follow System")
        case .zhHans:
            return "简体中文"
        case .zhHant:
            return "繁體中文"
        case .cantonese:
            return "廣東話"
        case .english:
            return "English"
        }
    }

    static var selected: AppLanguage {
        get {
            guard let rawValue = UserDefaults.standard.string(forKey: defaultsKey),
                  let language = AppLanguage(rawValue: rawValue) else {
                return .automatic
            }
            return language
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey)
            NotificationCenter.default.post(name: .appLanguageDidChange, object: nil)
        }
    }

    static var effective: AppLanguage {
        switch selected {
        case .automatic:
            return resolveAutomaticLanguage()
        case .zhHans:
            return .zhHans
        case .zhHant:
            return .zhHant
        case .cantonese:
            return .cantonese
        case .english:
            return .english
        }
    }

    private static func resolveAutomaticLanguage() -> AppLanguage {
        for preferredLanguage in Locale.preferredLanguages {
            let normalized = preferredLanguage
                .lowercased()
                .replacingOccurrences(of: "_", with: "-")

            if normalized.hasPrefix("yue") || normalized.hasPrefix("zh-hk") || normalized.hasPrefix("zh-mo") {
                return .cantonese
            }
            if normalized.hasPrefix("zh-tw") || normalized.contains("hant") {
                return .zhHant
            }
            if normalized.hasPrefix("zh") {
                return .zhHans
            }
            if normalized.hasPrefix("en") {
                return .english
            }
        }
        return .english
    }
}

enum L10n {
    static func text(
        zh: String,
        zhHant: String? = nil,
        yue: String? = nil,
        en: String
    ) -> String {
        switch AppLanguage.effective {
        case .automatic, .zhHans:
            return zh
        case .zhHant:
            return zhHant ?? traditionalize(zh)
        case .cantonese:
            if let yue {
                return yue
            }
            if let override = cantoneseOverrides[zh] {
                return override
            }
            return zhHant ?? traditionalize(zh)
        case .english:
            return en
        }
    }

    private static func traditionalize(_ text: String) -> String {
        text.applyingTransform(StringTransform("Hans-Hant"), reverse: false) ?? text
    }

    private static let cantoneseOverrides: [String: String] = [
        "插电": "插電",
        "电池": "電池",
        "性能控制中心": "效能控制中心",
        "进程分析": "程序分析",
        "硬件状态": "硬件狀態",
        "诊断输出": "診斷輸出",
        "设置": "設定",
        "Apple Silicon 调度与电源策略": "Apple Silicon 調度同電源策略",
        "查看哪些进程会被加速、跳过或保护": "睇下邊啲程序會被加速、略過或者保護",
        "核心拓扑与实时负载": "核心拓撲同即時負載",
        "自测、Dry Run 与运行日志": "自測、Dry Run 同運行日誌",
        "策略、语言与应用偏好": "策略、語言同 App 偏好",
        "性能策略": "效能策略",
        "平衡": "平衡",
        "性能": "效能",
        "只处理已被系统后台化的进程，不触碰高性能电源档。": "只處理已經俾系統擺去後台嘅程序，唔會掂高效能電源檔。",
        "默认推荐：插电时解除后台调度限制，不修改低电量或电源模式。": "預設推薦：插電時解除後台調度限制，唔會改低電量或者電源模式。",
        "在性能模式基础上追加 renice，适合短时重负载。": "喺效能模式上再加 `renice`，適合短時間重負載。",
        "读取中": "讀取中",
        "服务状态": "服務狀態",
        "启用 MACPI 策略": "啟用 MACPI 策略",
        "电池时恢复原本后台状态": "用電池嗰陣回復原本後台狀態",
        "保护系统关键进程": "保護系統關鍵程序",
        "MACPI GUI 已就绪。\n建议先运行自测，再安装 LaunchDaemon。": "MACPI GUI 準備好。\n建議先跑自測，再安裝 LaunchDaemon。",
        "点击“刷新分析”查看当前进程会被加速、跳过或保护的原因。": "撳「重新整理分析」睇下而家邊啲程序會被加速、略過或者保護。",
        "例如：backupd, mds, photoanalysisd": "例如：backupd, mds, photoanalysisd",
        "刷新": "重新整理",
        "刷新状态": "重新整理狀態",
        "供电状态": "供電狀態",
        "当前策略": "目前策略",
        "插电时优先性能，电池时恢复保守策略": "插電時以效能優先，用電池時回復保守策略",
        "总开关": "總開關",
        "开启": "開啟",
        "关闭": "關閉",
        "插电策略": "插電策略",
        "只处理后台": "只處理後台",
        "清除后台限制": "清走後台限制",
        "电池策略": "電池策略",
        "恢复原状态": "回復原狀態",
        "扫描间隔": "掃描間隔",
        "保护白名单": "保護白名單",
        "系统关键": "系統關鍵",
        "保护": "保護",
        "每核心 CPU 占用率": "每核心 CPU 佔用率",
        "按 Apple Silicon 常见逻辑顺序显示：E 核在前，P 核在后": "會跟 Apple Silicon 常見邏輯次序顯示：E 核喺前，P 核喺後",
        "硬件概览": "硬件概覽",
        "当前机器的核心布局": "呢部機而家嘅核心配置",
        "性能核心": "效能核心",
        "采样核心": "採樣核心",
        "硬件工具": "硬件工具",
        "快速打开系统工具或复制当前硬件摘要": "快速打開系統工具，或者複製而家嘅硬件摘要",
        "打开活动监视器": "打開活動監視器",
        "复制硬件摘要": "複製硬件摘要",
        "刷新图表": "重新整理圖表",
        "应用设置": "App 設定",
        "语言、菜单栏和核心图表显示": "語言、選單列同核心圖表顯示",
        "语言": "語言",
        "菜单栏图标": "選單列圖示",
        "已启用": "已啟用",
        "图表刷新": "圖表更新",
        "诊断操作": "診斷操作",
        "运行自测": "跑自測",
        "复制日志命令": "複製日誌指令",
        "按当前 GUI 策略预估哪些进程会被加速、跳过或保护。": "會按而家 GUI 策略估算邊啲程序會被加速、略過或者保護。",
        "白名单": "白名單",
        "刷新分析": "重新整理分析",
        "复制分析": "複製分析",
        "策略配置": "策略設定",
        "这些参数对应 LaunchDaemon 的运行参数。": "呢啲參數會對應 LaunchDaemon 嘅執行參數。",
        "同 PID 刷新": "同 PID 重新整理",
        "不干预": "唔干預",
        "模式滑杆": "模式滑桿",
        "安装需要管理员权限；GUI 会生成命令，核心服务仍以 root LaunchDaemon 运行。": "安裝需要管理員權限；GUI 會產生命令，而核心服務都係用 root LaunchDaemon 跑。",
        "安装/更新服务": "安裝/更新服務",
        "卸载服务": "移除服務",
        "自测和 dry-run 的输出会显示在这里。": "自測同 dry-run 嘅輸出會顯示喺呢度。",
        "峰值 --%": "峰值 --%",
        "活跃 --": "活躍 --",
        "AC 性能模式": "AC 效能模式",
        "电池保护": "電池保護",
        "供电未知": "供電未知",
        "可用": "可用",
        "未找到": "搵唔到",
        "运行中": "運行中",
        "未安装": "未安裝",
        "服务运行中": "服務運行中",
        "服务未安装": "服務未安裝",
        "正在分析进程...": "分析緊程序...",
        "已复制进程分析结果。": "已複製程序分析結果。",
        "打开 MACPI": "打開 MACPI",
        "退出 MACPI": "離開 MACPI"
    ]
}
