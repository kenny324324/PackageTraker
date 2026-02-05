import SwiftUI

/// 購買平台選擇器 Sheet
struct PlatformPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    @Binding var selectedPlatform: String
    @State private var searchText = ""
    @State private var customInput = ""
    @State private var showCustomInput = false
    
    /// 過濾後的平台列表
    private var filteredPlatforms: [String] {
        PurchasePlatform.filter(by: searchText)
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 搜索框
                searchBar
                
                // 平台列表
                platformList
            }
            .adaptiveBackground()
            .navigationTitle(String(localized: "platform.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "common.cancel")) {
                        dismiss()
                    }
                    .foregroundStyle(.white)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Views
    
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField(String(localized: "platform.searchPlaceholder"), text: $searchText)
                .textFieldStyle(.plain)
            
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(Color.secondaryCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding()
    }
    
    private var platformList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // 自訂輸入選項（當搜索文字不在列表中時顯示）
                if !searchText.isEmpty && !filteredPlatforms.contains(searchText) {
                    customInputRow
                    Divider()
                }
                
                // 平台列表
                ForEach(filteredPlatforms, id: \.self) { platform in
                    platformRow(platform)
                    
                    if platform != filteredPlatforms.last {
                        Divider()
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
    }
    
    private var customInputRow: some View {
        Button {
            selectedPlatform = searchText
            dismiss()
        } label: {
            HStack {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(.green)

                Text(String(format: String(localized: "platform.use"), searchText))
                    .foregroundStyle(.primary)

                Spacer()

                Text(String(localized: "platform.custom"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    private func platformRow(_ platform: String) -> some View {
        Button {
            selectedPlatform = platform
            dismiss()
        } label: {
            HStack {
                Text(platform)
                    .foregroundStyle(.primary)
                
                Spacer()
                
                if selectedPlatform == platform {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.green)
                }
            }
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    PlatformPickerSheet(selectedPlatform: .constant("蝦皮購物"))
}
