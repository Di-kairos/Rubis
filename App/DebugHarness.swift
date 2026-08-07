#if DEBUG

import AppKit
import QuartzCore
import SwiftUI

/// Замеры, которые невозможно сделать снаружи процесса: снимок собственного
/// окна (не требует прав Screen Recording, в отличие от `screencapture`) и
/// прогон скролла с подсчётом реальных кадров.
///
/// Только DEBUG, включается переменными окружения:
/// - `RUBIS_SNAPSHOT_PATH` — куда положить PNG окна;
/// - `RUBIS_SCROLL_BENCH` — прогнать скролл и напечатать статистику кадров;
/// - `RUBIS_HARNESS_DELAY` — сколько секунд ждать загрузки (по умолчанию 6);
/// - `RUBIS_HARNESS_EXIT` — выйти после замера (для скриптов).
@MainActor
enum DebugHarness {
    static func startIfRequested() {
        let env = ProcessInfo.processInfo.environment
        let snapshotPath = env["RUBIS_SNAPSHOT_PATH"]
        let benchmark = env["RUBIS_SCROLL_BENCH"] != nil
        guard snapshotPath != nil || benchmark else { return }

        // Тёмная тема для снимка: `RUBIS_APPEARANCE=dark`.
        if env["RUBIS_APPEARANCE"] == "dark" {
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }

        let delay = Double(env["RUBIS_HARNESS_DELAY"] ?? "") ?? 6
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            MainActor.assumeIsolated {
                if let snapshotPath { writeSnapshot(to: snapshotPath) }
                if benchmark {
                    ScrollBenchmark.shared.run {
                        if let snapshotPath {
                            writeSnapshot(to: snapshotPath + ".after-scroll.png")
                        }
                        finish(env)
                    }
                } else {
                    finish(env)
                }
            }
        }
    }

    private static func finish(_ env: [String: String]) {
        guard env["RUBIS_HARNESS_EXIT"] != nil else { return }
        exit(0)
    }

    /// Снимок содержимого окна средствами самого окна — TCC здесь ни при чём.
    private static func writeSnapshot(to path: String) {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }),
            let view = window.contentView,
            let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        else {
            print("[harness] no window to snapshot")
            return
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        do {
            try data.write(to: URL(fileURLWithPath: path))
            print("[harness] snapshot → \(path) (\(rep.pixelsWide)×\(rep.pixelsHigh))")
        } catch {
            print("[harness] snapshot failed: \(error)")
        }
    }
}

/// Гонит список с постоянной скоростью, шагая на каждом кадре дисплея, и
/// считает интервалы между вызовами display link.
///
/// Что это меряет честно: ритм главного потока под нагрузкой скролла — если
/// создание строк или layout не укладываются в кадр, следующий вызов приходит
/// с опозданием, и это видно как пропуск. Чего это не меряет: завершение
/// отрисовки на GPU. Для «список тормозит при прокрутке» первого достаточно,
/// потому что вся работа SwiftUI по строкам идёт как раз на главном потоке.
@MainActor
final class ScrollBenchmark {
    static let shared = ScrollBenchmark()

    private var link: CADisplayLink?
    private var intervals: [CFTimeInterval] = []
    private var lastTimestamp: CFTimeInterval = 0
    private var scrollView: NSScrollView?
    private var completion: (() -> Void)?
    private var pointsPerFrame: CGFloat = 0
    private var startTimestamp: CFTimeInterval = 0
    /// Сколько секунд крутить: длина списка тут ни при чём, важна выборка кадров.
    private let duration =
        Double(ProcessInfo.processInfo.environment["RUBIS_SCROLL_SECONDS"] ?? "") ?? 6

    func run(completion: @escaping () -> Void) {
        guard let window = NSApp.windows.first(where: { $0.isVisible }),
            let view = window.contentView,
            let target = Self.largestScrollView(in: view)
        else {
            print("[bench] no scroll view found")
            completion()
            return
        }
        let documentHeight = target.documentView?.bounds.height ?? 0
        let visibleHeight = target.contentView.bounds.height
        guard documentHeight > visibleHeight else {
            print("[bench] content fits, nothing to scroll")
            completion()
            return
        }

        scrollView = target
        self.completion = completion
        startTimestamp = 0
        intervals.removeAll()
        lastTimestamp = 0
        // Скорость как у быстрого флика трекпадом, а не «весь список за 6 с»:
        // при прыжке на сотню строк за кадр меряется не скролл, а случайный
        // доступ. По умолчанию 2000 pt/с — это ~60 строк в секунду.
        let refresh = Double(target.window?.screen?.maximumFramesPerSecond ?? 60)
        let velocity =
            Double(ProcessInfo.processInfo.environment["RUBIS_SCROLL_PTS_PER_SEC"] ?? "")
            ?? 2_000
        pointsPerFrame = CGFloat(velocity / refresh)
        print(
            "[bench] document \(Int(documentHeight)) pt, viewport \(Int(visibleHeight)) pt, "
                + "\(Int(velocity)) pt/s → \(String(format: "%.1f", pointsPerFrame)) pt/frame")

        let link = view.displayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func tick(_ link: CADisplayLink) {
        // Окно закрыли на середине прогона — иначе link тикал бы вечно.
        guard let scrollView, let documentView = scrollView.documentView else {
            report()
            return
        }
        if lastTimestamp > 0 { intervals.append(link.timestamp - lastTimestamp) }
        lastTimestamp = link.timestamp
        if startTimestamp == 0 { startTimestamp = link.timestamp }

        let maxOffset = documentView.bounds.height - scrollView.contentView.bounds.height
        let next = scrollView.contentView.bounds.origin.y + pointsPerFrame
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: min(next, maxOffset)))
        scrollView.reflectScrolledClipView(scrollView.contentView)

        if next >= maxOffset || link.timestamp - startTimestamp >= duration { report() }
    }

    private func report() {
        link?.invalidate()
        link = nil
        let sorted = intervals.sorted()
        guard !sorted.isEmpty else {
            print("[bench] no frames captured")
            completion?()
            completion = nil
            return
        }
        // Частота того экрана, где реально висит окно, а не главного.
        let refresh = screenRefreshRate
        let budget = 1.0 / Double(refresh)
        let dropped = intervals.filter { $0 > budget * 1.5 }.count
        let average = intervals.reduce(0, +) / Double(intervals.count)
        let percentile95 = sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * 0.95))]

        print(
            """
            [bench] display \(refresh) Hz, frames \(intervals.count)
            [bench] average \(ms(average)) ms → \(String(format: "%.0f", 1 / average)) fps
            [bench] p95 \(ms(percentile95)) ms, worst \(ms(sorted[sorted.count - 1])) ms
            [bench] dropped (>1.5× budget) \(dropped) / \(intervals.count) \
            (\(String(format: "%.2f", Double(dropped) / Double(intervals.count) * 100))%)
            """)
        completion?()
        completion = nil
    }

    private var screenRefreshRate: Int {
        scrollView?.window?.screen?.maximumFramesPerSecond
            ?? NSScreen.main?.maximumFramesPerSecond ?? 60
    }

    private func ms(_ seconds: CFTimeInterval) -> String {
        String(format: "%.2f", seconds * 1000)
    }

    /// Самый высокий скроллер в окне — это список, а не сайдбар.
    private static func largestScrollView(in view: NSView) -> NSScrollView? {
        var found: [NSScrollView] = []
        var stack = [view]
        while let current = stack.popLast() {
            if let scroll = current as? NSScrollView { found.append(scroll) }
            stack.append(contentsOf: current.subviews)
        }
        return found.max {
            ($0.documentView?.bounds.height ?? 0) < ($1.documentView?.bounds.height ?? 0)
        }
    }
}

#endif
