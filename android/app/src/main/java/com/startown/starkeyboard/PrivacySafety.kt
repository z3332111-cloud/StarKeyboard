package com.startown.starkeyboard

import android.app.Activity
import android.app.AlertDialog
import android.widget.ScrollView
import android.widget.TextView

object PrivacySafety {
    fun show(activity: Activity) {
        val padding = (20 * activity.resources.displayMetrics.density).toInt()
        val body = TextView(activity).apply {
            text = "先知道這些\n這頁說明已確認的風險與目前的保護措施，不是完整的安全稽核，也不保證沒有漏洞。密碼、驗證碼、身分資料與私密訊息，請避免存進剪貼簿紀錄、快捷片語或外部翻譯。\n\n鍵盤權限代表什麼\nAndroid 輸入法可讀取你在一般輸入欄交給它的文字；系統警告適用於所有第三方鍵盤。可在系統鍵盤設定停用糯糯鍵盤。敏感剪貼簿標記需要來源 App 主動提供，不能視為完整的密碼偵測。\n\n剪貼簿會保存什麼\n自動記錄預設關閉，可在鍵盤 ⚙ → 隱私與安全自行開啟。開啟後，鍵盤使用期間會將複製的文字存到本機，預設保留 200 筆未釘選紀錄；釘選內容會另外保留。關閉自動記錄後，仍可按「＋」手動儲存。\n\n敏感內容無法全部辨識\n會跳過來源 App 標示為敏感的內容；iPhone 也會跳過標示為暫存的內容。但這些標記不是每個 App 都會提供，沒有標記的密碼仍可能被保存。密碼欄位保護不能阻止你把密碼複製到剪貼簿。\n\n清理舊紀錄\n這次更新不會自動刪除舊紀錄。請打開鍵盤 → 剪貼簿，檢查並刪除敏感項目。「清除」只清掉未釘選內容，釘選內容需逐筆刪除；選字學習可在 ⚙ → 清除選字學習紀錄重設。關閉自動記錄不會刪掉已存內容。\n\n本機檔案與備份\n紀錄保存在 App 私有目錄，沒有另設 App 密碼加密；裝置解鎖或遭控制時仍有風險。本版停用 Android 備份，並設定雲端備份及裝置移轉排除規則。不同手機廠商的行為可能有差異；舊備份不會自動刪除，解除安裝會失去本機資料。\n\n手動匯入與匯出\n剪貼簿搬家匯出的 JSON 是明文，會離開 App 私有儲存區；若存到雲端硬碟，該服務可能同步或備份。請勿匯出密碼、驗證碼等敏感內容，用完後自行刪除不需要的檔案。匯入檔案不會自動偵測密碼。\n\n外部翻譯與網路\n外部網路翻譯預設關閉。開啟後，你按「翻譯」時會先嘗試本機翻譯；本機不可用時，最多 450 字原文會以 HTTPS 傳給 MyMemory，放在網址查詢參數中，可能留在服務商的紀錄裡。關閉此開關會阻止這條外傳路徑。本機翻譯可能仍需連網下載語言模型。\n\n檢查更新\nApp 與鍵盤會透過 HTTPS 向 GitHub 檢查版本資訊。這個請求不包含剪貼簿或打字內容，但 GitHub 仍能看到 IP 位址及一般連線資訊。\n\n安裝來源與信任\n請只從原安裝網站或本專案的 GitHub Releases 下載。iPhone 的 IPA 需由 Sideloadly 以你的帳號簽署；不要把 Apple ID、驗證碼或密碼貼進鍵盤紀錄。從可信網址下載、保護 GitHub 帳號及啟用兩步驟驗證，都不能完全消除供應鏈風險。\n\n進階：建置與檢查範圍\n雲端建置使用外部字典、字體和第三方工具。目前流程仍有未固定的外部程式版本與較寬的發布權限，這些供應鏈風險尚未在本次修復。後續應固定 commit SHA，並分開唯讀建置工作與可寫入 Release 的發布工作；GitHub 權限不能在單一步驟單獨升級。SQLite 查詢使用參數綁定能降低注入風險，但不代表整個 App 沒有漏洞。本次未重新完成全 Git 歷史的金鑰掃描，不能據此保證歷史上沒有憑證外洩。"
            textSize = 16f
            setTextIsSelectable(true)
            setPadding(padding, padding, padding, padding)
            setLineSpacing(0f, 1.25f)
        }
        AlertDialog.Builder(activity).setTitle("隱私與安全")
            .setView(ScrollView(activity).apply { addView(body) })
            .setPositiveButton("知道了", null).show()
    }
}
