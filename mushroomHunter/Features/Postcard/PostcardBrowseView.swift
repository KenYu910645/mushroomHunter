//
//  PostcardBrowseView.swift
//  mushroomHunter
//
//  Purpose:
//  - Hosts the postcard tab browse flow with search, register sheet, and listing grid.
//
import SwiftUI

// MARK: - Browse

/// Root postcard browse screen used by the Postcard tab.
struct PostcardBrowseView: View {
    /// Shared session state used for wallet values and profile refresh.
    @EnvironmentObject private var session: UserSessionStore
    /// Browse view model that loads and filters postcard listings.
    @StateObject private var vm = PostcardBrowseViewModel()
    /// Controls presentation of the search sheet.
    @State private var isSearchSheetPresented: Bool = false
    /// Controls initial focus for the search text field.
    @State private var isSearchFieldFocused: Bool = false
    /// Controls presentation of the postcard register sheet.
    @State private var isRegisterSheetPresented: Bool = false
    /// Refresh trigger incremented after creating a postcard.
    @State private var browseDataRefreshToken: Int = 0
    /// Current color scheme used for theme background rendering.
    @Environment(\.colorScheme) private var scheme
    /// Spacing used between postcard grid columns.
    private let cardColumnSpacing: CGFloat = 8

    /// Main postcard browse UI tree.
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
        .sheet(isPresented: $isSearchSheetPresented) {
            NavigationStack {
                Form {
                    Section {
                        SelectAllTextField(
                            placeholderKey: "postcard_search_placeholder",
                            text: $vm.query,
                            isFirstResponder: $isSearchFieldFocused,
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
                        Button(LocalizedStringKey("common_done")) { isSearchSheetPresented = false }
                    }
                }
                .navigationTitle(LocalizedStringKey("postcard_search_title"))
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(LocalizedStringKey("common_close")) {
                            isSearchSheetPresented = false
                        }
                    }
                }
                .onAppear {
                    isSearchFieldFocused = true
                }
                .onDisappear {
                    isSearchFieldFocused = false
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

    /// Grid layout used by postcard cards.
    private var gridColumns: [GridItem] {
        [
            GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: cardColumnSpacing, alignment: .top),
            GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: cardColumnSpacing, alignment: .top)
        ]
    }

    /// Shared top action bar for honey amount, search, and create actions.
    private var headerBar: some View {
        BrowseViewTopActionBar(
            honey: session.honey,
            onSearch: { isSearchSheetPresented = true },
            onCreate: { isRegisterSheetPresented = true },
            searchAccessibilityLabel: "postcard_search_accessibility",
            createAccessibilityLabel: "postcard_register_accessibility",
            searchButtonIdentifier: nil,
            createButtonIdentifier: nil
        )
        .padding(.horizontal)
    }
}

/// Card tile shown for each postcard listing in the browse grid.
private struct PostcardCardView: View {
    /// Listing displayed by this card.
    let listing: PostcardListing
    /// Current color scheme used for card background styling.
    @Environment(\.colorScheme) private var scheme
    /// Fixed aspect ratio used for postcard thumbnail area.
    private let imageAspectRatio: CGFloat = 1.0

    /// Card content for a single postcard listing.
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
