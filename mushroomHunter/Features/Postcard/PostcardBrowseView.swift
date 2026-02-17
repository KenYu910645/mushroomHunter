//
//  PostcardBrowseView.swift
//  mushroomHunter
//
//  Purpose:
//  - Renders postcard listing browse/search UI and listing cards.
//
import SwiftUI

// MARK: - Browse

struct PostcardBrowseView: View {
    @EnvironmentObject private var session: UserSessionStore // State or dependency property.
    @StateObject private var vm = PostcardBrowseViewModel() // State or dependency property.
    @State private var showSearchAlert: Bool = false // State or dependency property.
    @State private var searchFieldFocused: Bool = false // State or dependency property.
    @State private var isRegisterSheetPresented: Bool = false // State or dependency property.
    @State private var browseDataRefreshToken: Int = 0 // State or dependency property.
    @Environment(\.colorScheme) private var scheme // State or dependency property.
    private let cardColumnSpacing: CGFloat = 8

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if let err = vm.errorMessage {
                        Text(err)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                    }

                    headerBar

                    LazyVGrid(columns: gridColumns, spacing: 12) {
                        ForEach(vm.filteredListings) { listing in
                            NavigationLink {
                                PostcardView(listing: listing)
                            } label: {
                                PostcardCardView(listing: listing)
                            }
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .buttonStyle(.plain)
                            .contentShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding(.horizontal)

                    if vm.filteredListings.isEmpty && !vm.isLoading {
                        ContentUnavailableView(
                            LocalizedStringKey("postcard_empty_title"),
                            systemImage: "magnifyingglass",
                            description: Text(LocalizedStringKey("postcard_empty_description"))
                        )
                        .padding(.top, 24)
                    }
                }
                .padding(.vertical, 8)
            }
            .navigationTitle(LocalizedStringKey("postcard_title"))
            .background(Theme.backgroundGradient(for: scheme))
            .overlay {
                if vm.isLoading && vm.filteredListings.isEmpty {
                    ProgressView("Loading postcards…")
                }
            }
        }
        .sheet(isPresented: $isRegisterSheetPresented) {
            NavigationStack {
                PostcardFormView(onSubmitted: {
                    isRegisterSheetPresented = false
                    browseDataRefreshToken += 1
                })
                .navigationTitle(LocalizedStringKey("postcard_register_title"))
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            isRegisterSheetPresented = false
                        } label: {
                            Image(systemName: "xmark")
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showSearchAlert) {
            NavigationStack {
                Form {
                    Section {
                        SelectAllTextField(
                            placeholderKey: "postcard_search_placeholder",
                            text: $vm.query,
                            isFirstResponder: $searchFieldFocused,
                            textContentType: .none,
                            autocapitalization: .none,
                            autocorrection: .no,
                            textAlignment: .left
                        )
                        .frame(height: 22)
                    } header: {
                        Text(LocalizedStringKey("postcard_search_title"))
                    } footer: {
                        Text(LocalizedStringKey("postcard_search_message"))
                    }

                    Section {
                        Button(LocalizedStringKey("common_clear")) { vm.query = "" }
                        Button(LocalizedStringKey("common_done")) { showSearchAlert = false }
                    }
                }
                .navigationTitle(LocalizedStringKey("postcard_search_title"))
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(LocalizedStringKey("common_close")) {
                            showSearchAlert = false
                        }
                    }
                }
                .onAppear {
                    searchFieldFocused = true
                }
                .onDisappear {
                    searchFieldFocused = false
                }
            }
        }
        .onChange(of: vm.query) { _, _ in
            vm.scheduleSearch()
        }
        .onChange(of: vm.selectedCountry) { _, _ in
            vm.normalizeProvinceSelection()
        }
        .onAppear {
            Task {
                await session.refreshProfileFromBackend()
                await vm.refresh()
            }
        }
        .task(id: browseDataRefreshToken) {
            await vm.refresh()
        }
        .refreshable {
            await vm.refresh()
        }
    }

    private var gridColumns: [GridItem] {
        [
            GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: cardColumnSpacing, alignment: .top),
            GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: cardColumnSpacing, alignment: .top)
        ]
    }

    private var headerBar: some View {
        BrowseViewTopActionBar(
            honey: session.honey,
            onSearch: { showSearchAlert = true },
            onCreate: { isRegisterSheetPresented = true },
            searchAccessibilityLabel: "postcard_search_accessibility",
            createAccessibilityLabel: "postcard_register_accessibility",
            searchButtonIdentifier: nil,
            createButtonIdentifier: nil
        )
        .padding(.horizontal)
    }
}

private struct PostcardCardView: View {
    let listing: PostcardListing
    @Environment(\.colorScheme) private var scheme // State or dependency property.
    private let imageAspectRatio: CGFloat = 1.0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white)
                    .aspectRatio(imageAspectRatio, contentMode: .fit)

                if let urlString = listing.imageUrl, let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure:
                            Image(systemName: "photo")
                                .font(.title)
                                .foregroundStyle(.secondary)
                        case .empty:
                            ProgressView()
                        @unknown default:
                            Image(systemName: "photo")
                                .font(.title)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .aspectRatio(imageAspectRatio, contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    Image(systemName: "photo")
                        .font(.title)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)

            Text(listing.title)
                .font(.headline)
                .lineLimit(1)

            HStack(spacing: 6) {
                Image(systemName: "mappin.and.ellipse")
                Text(listing.location.shortLabel)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack {
                HStack(spacing: 4) {
                    Text("\(listing.priceHoney)")
                        .font(.subheadline)
                    Image("HoneyIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 14, height: 14)
                }
                Spacer()
                Text(String(format: NSLocalizedString("postcard_stock_format", comment: ""), listing.stock))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.cardBackground(for: scheme))
                .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 2)
        )
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }
}
