//
//  SafariView.swift
//  PackageTraker
//
//  App 內瀏覽器（SFSafariViewController 包裝）
//

import SwiftUI
import SafariServices

/// 可辨識的 URL 包裝，用於 .sheet(item:)
struct IdentifiableURL: Identifiable {
    let id = UUID()
    let url: URL
}

/// SwiftUI 包裝的 SFSafariViewController，用於 App 內開啟網頁
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        let safari = SFSafariViewController(url: url, configuration: config)
        safari.preferredControlTintColor = .systemGreen
        return safari
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
