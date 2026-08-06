import CoreServices
import EscapementCore
import Foundation

/// FSEvents watcher for source roots (SPEC §5.2): 2 s debounce, reports the
/// changed subtrees so the scanner can rescan only what moved.
/// MainActor-bound: the stream delivers on the main queue and state stays simple.
@MainActor
public final class FolderWatcher {
    private var stream: FSEventStreamRef?
    private var pending: Set<String> = []
    private var debounce: Task<Void, Never>?
    private let onChange: ([URL]) -> Void

    public init(roots: [URL], onChange: @escaping ([URL]) -> Void) {
        self.onChange = onChange
        guard !roots.isEmpty else { return }

        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
            let pathList = Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as! [String]
            for i in 0..<count {
                watcher.noteChange(path: pathList[i])
            }
        }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil)
        stream = FSEventStreamCreate(
            nil, callback, &context,
            roots.map(\.path) as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0,
            FSEventStreamCreateFlags(
                kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagWatchRoot))
        if let stream {
            FSEventStreamSetDispatchQueue(stream, .main)
            FSEventStreamStart(stream)
        }
    }

    private func noteChange(path: String) {
        pending.insert(path)
        debounce?.cancel()
        debounce = Task { [weak self] in
            // Дебаунс 2 секунды (SPEC §5.2)
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self else { return }
            let changed = self.pending.map { URL(fileURLWithPath: $0) }
            self.pending.removeAll()
            guard !changed.isEmpty else { return }
            self.onChange(changed)
        }
    }

    public func stop() {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        stream = nil
        debounce?.cancel()
    }

    // ponytail: без deinit-очистки — владелец обязан звать stop(); в App
    // watcher живёт всё время работы приложения, утечка невозможна.
}
