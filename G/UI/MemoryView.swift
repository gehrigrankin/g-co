import SwiftUI

/// Shows what G knows about Gehrig. Lets him see, search, and delete memories.
struct MemoryView: View {
    @ObservedObject private var memory = GMemory.shared
    @State private var searchText = ""
    @State private var selectedCategory: GMemory.MemoryCategory?
    @State private var showDeleteConfirmation = false

    var filteredMemories: [GMemory.Memory] {
        var result = memory.memories

        if let category = selectedCategory {
            result = result.filter { $0.category == category }
        }

        if !searchText.isEmpty {
            result = result.filter {
                $0.content.localizedCaseInsensitiveContains(searchText)
            }
        }

        return result.sorted { $0.lastReferencedAt > $1.lastReferencedAt }
    }

    var body: some View {
        NavigationStack {
            List {
                // Stats
                Section {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("\(memory.memories.count)")
                                .font(.title.bold())
                                .foregroundColor(.gAccent)
                            Text("memories")
                                .font(.caption)
                                .foregroundColor(.gTextDim)
                        }
                        Spacer()
                        VStack(alignment: .leading) {
                            Text("\(memory.conversationSummaries.count)")
                                .font(.title.bold())
                                .foregroundColor(.gAccent)
                            Text("conversations")
                                .font(.caption)
                                .foregroundColor(.gTextDim)
                        }
                        Spacer()
                        VStack(alignment: .leading) {
                            let categories = Set(memory.memories.map { $0.category }).count
                            Text("\(categories)")
                                .font(.title.bold())
                                .foregroundColor(.gAccent)
                            Text("categories")
                                .font(.caption)
                                .foregroundColor(.gTextDim)
                        }
                    }
                }

                // Profile summary
                if !memory.profile.summary.isEmpty {
                    Section("What G Knows") {
                        Text(memory.profile.summary)
                            .foregroundColor(.gText)
                    }
                }

                // Category filter
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            CategoryChip(title: "All", isSelected: selectedCategory == nil) {
                                selectedCategory = nil
                            }
                            ForEach(GMemory.MemoryCategory.allCases, id: \.rawValue) { category in
                                let count = memory.memories.filter { $0.category == category }.count
                                if count > 0 {
                                    CategoryChip(
                                        title: "\(category.rawValue) (\(count))",
                                        isSelected: selectedCategory == category
                                    ) {
                                        selectedCategory = selectedCategory == category ? nil : category
                                    }
                                }
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets())
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }

                // Memories list
                Section("Memories (\(filteredMemories.count))") {
                    ForEach(filteredMemories) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(item.category.rawValue)
                                    .font(.caption.bold())
                                    .foregroundColor(.gAccent)
                                    .textCase(.uppercase)
                                Spacer()
                                Text(item.createdAt, style: .relative)
                                    .font(.caption2)
                                    .foregroundColor(.gTextDim)
                            }
                            Text(item.content)
                                .font(.body)
                                .foregroundColor(.gText)
                            HStack {
                                Text("Referenced \(item.referenceCount)x")
                                    .font(.caption2)
                                    .foregroundColor(.gTextDim)
                                Text("•")
                                    .foregroundColor(.gTextDim)
                                Text("Confidence: \(Int(item.confidence * 100))%")
                                    .font(.caption2)
                                    .foregroundColor(.gTextDim)
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                memory.forget(item.id)
                            } label: {
                                Label("Forget", systemImage: "trash")
                            }
                        }
                    }
                }

                // Danger zone
                Section {
                    Button("Forget Everything", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                } footer: {
                    Text("This permanently deletes everything G knows about you.")
                }
            }
            .searchable(text: $searchText, prompt: "Search memories")
            .navigationTitle("G's Memory")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Forget Everything?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Forget", role: .destructive) {
                    memory.forgetEverything()
                }
            } message: {
                Text("G will forget everything it knows about you. This can't be undone.")
            }
        }
    }
}

struct CategoryChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.gAccent : Color.gSurface)
                .foregroundColor(isSelected ? .black : .gText)
                .cornerRadius(16)
        }
    }
}
