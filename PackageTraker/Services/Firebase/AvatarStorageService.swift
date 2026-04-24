//
//  AvatarStorageService.swift
//  PackageTraker
//
//  使用者頭像上傳到 Firebase Storage + 寫入 Firestore photoURL
//

import SwiftUI
import UIKit
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage

enum AvatarStorageError: LocalizedError {
    case notAuthenticated
    case compressionFailed

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return String(localized: "avatar.error.notAuthenticated")
        case .compressionFailed:
            return String(localized: "avatar.error.compressionFailed")
        }
    }
}

@MainActor
final class AvatarStorageService {
    static let shared = AvatarStorageService()

    private init() {}

    /// 上傳頭像並更新 Firestore photoURL，回傳含 cache-busting query 的 URL
    func uploadAvatar(_ image: UIImage) async throws -> String {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw AvatarStorageError.notAuthenticated
        }

        guard let data = compress(image), let cachedImage = UIImage(data: data) else {
            throw AvatarStorageError.compressionFailed
        }

        let ref = Storage.storage().reference().child("users/\(uid)/avatar.jpg")
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        _ = try await ref.putDataAsync(data, metadata: metadata)
        let downloadURL = try await ref.downloadURL()

        let urlString = bustCache(downloadURL)

        try await Firestore.firestore().collection("users").document(uid).setData([
            "photoURL": urlString,
            "lastActive": FieldValue.serverTimestamp()
        ], merge: true)

        // 上傳成功立刻寫入本機 cache，避免顯示時再下載一次
        AvatarCache.shared.replaceAll(with: cachedImage, for: urlString)

        return urlString
    }

    private func compress(_ image: UIImage) -> Data? {
        let resized = resize(image, maxDimension: 512)
        return resized.jpegData(compressionQuality: 0.7)
    }

    private func resize(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        guard max(size.width, size.height) > maxDimension else { return image }
        let ratio = maxDimension / max(size.width, size.height)
        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    private func bustCache(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        let timestamp = URLQueryItem(name: "t", value: "\(Int(Date().timeIntervalSince1970))")
        var items = components.queryItems ?? []
        items.append(timestamp)
        components.queryItems = items
        return components.url?.absoluteString ?? url.absoluteString
    }
}

// MARK: - Avatar Cache

/// 頭像快取（memory + disk），key 為完整 URL（含 timestamp），新版本上傳後會清舊檔
@MainActor
final class AvatarCache {
    static let shared = AvatarCache()

    private let memory = NSCache<NSString, UIImage>()
    private let fileManager = FileManager.default

    private var directory: URL {
        let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Avatars", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private init() {
        memory.countLimit = 4
    }

    func image(for urlString: String) -> UIImage? {
        let key = urlString as NSString
        if let img = memory.object(forKey: key) {
            return img
        }
        let fileURL = directory.appendingPathComponent(filename(for: urlString))
        guard let data = try? Data(contentsOf: fileURL),
              let img = UIImage(data: data) else {
            return nil
        }
        memory.setObject(img, forKey: key)
        return img
    }

    func store(_ image: UIImage, for urlString: String) {
        memory.setObject(image, forKey: urlString as NSString)
        if let data = image.jpegData(compressionQuality: 0.9) {
            let fileURL = directory.appendingPathComponent(filename(for: urlString))
            try? data.write(to: fileURL)
        }
    }

    /// 寫入新頭像並清除舊檔（每位使用者只保留最新一張）
    func replaceAll(with image: UIImage, for urlString: String) {
        clear()
        store(image, for: urlString)
    }

    func clear() {
        memory.removeAllObjects()
        guard let files = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for file in files {
            try? fileManager.removeItem(at: file)
        }
    }

    private func filename(for urlString: String) -> String {
        // 用穩定 hash 避免 URL 特殊字元（query string 含 token / timestamp）
        var hasher = Hasher()
        hasher.combine(urlString)
        let hash = UInt(bitPattern: hasher.finalize())
        return "\(hash).jpg"
    }
}

// MARK: - Shared Avatar View

/// 顯示使用者頭像（優先讀 cache，無則下載並寫入 cache，否則 SF Symbol fallback）
struct AvatarView: View {
    let urlString: String
    let size: CGFloat

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task(id: urlString) {
            await load()
        }
    }

    private var placeholder: some View {
        Image(systemName: "person.crop.circle.fill")
            .resizable()
            .scaledToFit()
            .foregroundStyle(Color(.systemGray3))
    }

    private func load() async {
        guard !urlString.isEmpty, let url = URL(string: urlString) else {
            image = nil
            return
        }

        if let cached = AvatarCache.shared.image(for: urlString) {
            image = cached
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let downloaded = UIImage(data: data) else { return }
            AvatarCache.shared.store(downloaded, for: urlString)
            // 避免使用者已切換成不同 URL 後才回來覆蓋
            if urlString == self.urlString {
                image = downloaded
            }
        } catch {
            // 失敗就維持 placeholder
        }
    }
}
