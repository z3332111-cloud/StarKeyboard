# 糯糯鍵盤・私藏酒廊
新主題沿用第一版酒紅玻璃的玫瑰、醒酒瓶、雞尾酒杯與寬鍵，另採用微調輪廓的酒杯和黑領結。123 模式鍵是單獨的厚邊凹心黑巧克力鍵，右下角帶一點銅箔。空白鍵兩杯相碰，換行鍵有唇印餐巾。鍵帽中央的注音、英文或功能符號由程式繪製。
 
StarKeyboard 是可供接手的 iOS 原始碼，包含之前的皇家、午夜酒廊與微醺可可主題。新主題 ID 為 lounge-reserve，設定選單顯示「私藏酒廊」。在 Keyboard/Resources/RoyalCaps.xcassets 搜尋 lounge-reserve，即可找到九個獨立透明 PNG。註冊與配色在 ThemePacks.swift，按鍵對應與字面位置在 RoyalKeyArt.swift。十欄注音配置與四款宮廷主題皆沿用前一份專案。
 
Lounge_Reserve_Keyboard.png 是以這九張圖排成的十欄注音設計預覽。實際鍵高、工具列和按鍵間距隨裝置與使用者設定調整。依 .github/workflows/build.yml 產生字典，再以 XcodeGen 生成 Xcode 專案。目前尚未在 Xcode 或 iPhone 上實測新主題。

杯型鍵位置為 5／ㄓ 威士忌杯、M／ㄩ 紅酒杯、S／ㄋ 香檳杯。支援英文大小寫。Lounge_Reserve_Glasses.png 為新版預覽。
