import SwiftUI
import PhotosUI

/// PHPicker supports older iPhones without requesting access to the entire library.
/// limit 大於 1 就可以一次挑好幾張（背景照片批次加入）
struct KeyboardPhotoPicker: UIViewControllerRepresentable {
    var limit: Int = 1
    var onSelect: ([UIImage]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onSelect: onSelect) }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = limit
        if limit > 1, #available(iOS 15.0, *) { configuration.selection = .ordered }
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: PHPickerViewController, context: Context) {}

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let onSelect: ([UIImage]) -> Void
        init(onSelect: @escaping ([UIImage]) -> Void) { self.onSelect = onSelect }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            let providers = results.map(\.itemProvider).filter { $0.canLoadObject(ofClass: UIImage.self) }
            guard !providers.isEmpty else {
                onSelect([])
                return
            }
            // 照挑的順序放好
            var images = [UIImage?](repeating: nil, count: providers.count)
            let group = DispatchGroup()
            for (i, provider) in providers.enumerated() {
                group.enter()
                provider.loadObject(ofClass: UIImage.self) { object, _ in
                    DispatchQueue.main.async {
                        images[i] = object as? UIImage
                        group.leave()
                    }
                }
            }
            group.notify(queue: .main) { [onSelect] in onSelect(images.compactMap { $0 }) }
        }
    }
}
