import UIKit

/// 背景（照片、漸層）的容器：填滿鍵盤、不淡出邊緣，上面才不會多露出一段系統底板。
/// 按鍵、文字與觸控區域放在此視圖外。
final class KeyboardBackdropView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isOpaque = false
        clipsToBounds = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
