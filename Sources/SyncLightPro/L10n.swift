import Foundation
import SwiftUI

/// App-wide language switching (Vietnamese / English).
enum AppLanguage: String, CaseIterable, Identifiable {
    case vi, en
    var id: String { rawValue }
    var label: String { self == .vi ? "Tiếng Việt" : "English" }
}

/// Simple bilingual string table.
struct L10n {
    let lang: AppLanguage

    private func t(_ vi: String, _ en: String) -> String {
        lang == .vi ? vi : en
    }

    var appTitle: String { t("SyncLight Pro", "SyncLight Pro") }
    var openWindow: String { t("Mở cửa sổ điều khiển", "Open Controls") }
    var quit: String { t("Thoát", "Quit") }
    var connect: String { t("Kết nối đèn", "Connect") }
    var disconnect: String { t("Ngắt kết nối", "Disconnect") }
    var connectAll: String { t("Kết nối tất cả", "Connect all") }
    var disconnectAll: String { t("Ngắt tất cả", "Disconnect all") }
    var connected: String { t("Đã kết nối", "Connected") }
    var notConnected: String { t("Chưa kết nối", "Not connected") }
    var noDevice: String { t("Không tìm thấy đèn", "No light found") }
    var light: String { t("Đèn", "Light") }
    var lights: String { t("Đèn đang dùng", "Lights") }
    var noLights: String { t("Chưa có đèn nào được kết nối.", "No lights connected yet.") }
    var selectLight: String { t("Chọn đèn", "Select light") }
    var assignDisplay: String { t("Gắn màn hình", "Assign display") }
    var activeLight: String { t("Đang điều khiển", "Editing") }

    var tabColor: String { t("Màu", "Color") }
    var tabEffects: String { t("Hiệu ứng", "Effects") }
    var tabSync: String { t("Đồng bộ màn hình", "Screen Sync") }
    var tabSettings: String { t("Cài đặt", "Settings") }

    var brightness: String { t("Độ sáng", "Brightness") }
    var dynamicSpeed: String { t("Tốc độ", "Speed") }
    var soundSensitivity: String { t("Độ nhạy âm thanh", "Sound Sensitivity") }
    var effectDynamic: String { t("Hiệu ứng màu", "Color Effects") }
    var effectPickup: String { t("Theo nhạc", "Sound Pickup") }
    var effectDynamicDesc: String { t("Hiệu ứng chạy sẵn trên đèn (không cần âm thanh).", "Effects that run on the light itself (no audio needed).") }
    var effectPickupDesc: String { t("Hiệu ứng phản ứng theo âm thanh đang phát trên máy (cần quyền ghi màn hình).", "Effects that react to audio playing on your Mac (needs Screen Recording permission).") }
    var pickColor: String { t("Chọn màu", "Pick Color") }
    var hue: String { t("Màu sắc", "Hue") }
    var saturation: String { t("Độ bão hòa", "Saturation") }

    var syncOn: String { t("Bật đồng bộ", "Enable Sync") }
    var syncOff: String { t("Tắt đồng bộ", "Disable Sync") }
    var syncDesc: String { t("Đồng bộ đèn theo màu màn hình theo thời gian thực.", "Sync the light color with the screen in real time.") }
    var samplingFPS: String { t("Tốc độ lấy mẫu", "Sampling FPS") }
    var display: String { t("Màn hình", "Display") }
    var mainDisplay: String { t("Màn hình chính", "Main Display") }
    var displayOfAll: String { t("Gắn màn hình cho từng đèn", "Assign a display to each light") }
    var direction: String { t("Chiều đèn", "Strip Direction") }
    var leftToRight: String { t("Trái sang phải", "Left to right") }
    var rightToLeft: String { t("Phải sang trái", "Right to left") }

    var language: String { t("Ngôn ngữ", "Language") }
    var about: String { t("Giới thiệu", "About") }
    var armNotice: String { t("Tối ưu cho Apple Silicon (arm64)", "Optimized for Apple Silicon (arm64)") }
    var screenPermission: String { t("Cần quyền ghi màn hình. Hãy cấp trong System Settings > Privacy.", "Screen Recording permission required. Grant it in System Settings > Privacy.") }
    var permissionBtn: String { t("Mở cài đặt quyền", "Open Permission Settings") }
    var autoOff: String { t("Tự tắt sau", "Auto off after") }
    var minutes: String { t("phút", "min") }
    var apply: String { t("Áp dụng", "Apply") }
    var usbPowerOpt: String { t("Tối ưu nguồn USB", "USB Power Optimization") }
    var usbPowerOptDesc: String { t("Giảm độ sáng khi tổng màu vượt ngưỡng để tránh quá dòng, chống nhấp nháy.", "Reduce brightness when total colour exceeds the limit, preventing over-current and flicker.") }
    var startOnBoot: String { t("Khởi động cùng hệ thống", "Start on boot") }
    var startOnBootDesc: String { t("Chạy nền ở menu bar khi đăng nhập, không mở cửa sổ.", "Run in the menu bar at login without opening a window.") }
    var version: String { t("Phiên bản", "Version") }
    var firmware: String { t("Phần mềm đèn", "Firmware") }
    var leds: String { t("Số bóng LED", "LED count") }
}
