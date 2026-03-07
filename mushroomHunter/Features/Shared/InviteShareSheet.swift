//
//  InviteShareSheet.swift
//  mushroomHunter
//
//  Purpose:
//  - Provides a reusable QR/share sheet used by room and postcard invite flows.
//
//  Defined in this file:
//  - InviteShareSheet generic view and QR image generation helper.
//
import SwiftUI
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

struct InviteShareSheet: View {
    @Environment(\.dismiss) private var dismiss // Dismiss action for closing the invite sheet.
    let titleKey: LocalizedStringKey // Localized navigation title key.
    let hintText: String // Context text shown above the QR code.
    let inviteURL: URL? // Generated invite URL encoded into QR and share link.
    let shareButtonKey: LocalizedStringKey // Localized label for share action button.
    let copyButtonKey: LocalizedStringKey // Localized label for copy-link action button.
    let unavailableDescriptionKey: LocalizedStringKey // Description displayed when invite URL is unavailable.
    let onCopyInviteLink: (String) -> Void // Callback invoked after user taps copy.

    private let qrContext = CIContext() // CoreImage context used to render QR output.
    private let qrFilter = CIFilter.qrCodeGenerator() // QR code generator filter.

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text(hintText)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                if let link = inviteURL?.absoluteString,
                   let qr = qrImage(from: link) {
                    Image(uiImage: qr)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 260, maxHeight: 260)
                        .padding(6)
                        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(.quaternary, lineWidth: 1)
                        )

                    Text(link)
                        .font(.footnote.monospaced())
                        .multilineTextAlignment(.center)
                        .textSelection(.enabled)
                        .padding(.horizontal)

                    HStack(spacing: 12) {
                        ShareLink(item: link) {
                            Label(shareButtonKey, systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            onCopyInviteLink(link)
                        } label: {
                            Label(copyButtonKey, systemImage: "doc.on.doc")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.horizontal)
                } else {
                    ContentUnavailableView(
                        LocalizedStringKey("room_load_error_title"),
                        systemImage: "qrcode",
                        description: Text(unavailableDescriptionKey)
                    )
                }

                Spacer()
            }
            .padding(.top, 20)
            .navigationTitle(titleKey)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(LocalizedStringKey("common_done")) {
                        dismiss()
                    }
                }
            }
        }
    }

    private func qrImage(from string: String) -> UIImage? { // Builds a crisp QR UIImage for the supplied invite string.
        let data = Data(string.utf8)
        qrFilter.setValue(data, forKey: "inputMessage")
        qrFilter.setValue("M", forKey: "inputCorrectionLevel")

        guard let outputImage = qrFilter.outputImage else { return nil }
        let outputSize = outputImage.extent.size
        guard outputSize.width > 0, outputSize.height > 0 else { return nil }

        let outputEdge: CGFloat = 260
        let scaleX = outputEdge / outputSize.width
        let scaleY = outputEdge / outputSize.height
        let transformedImage = outputImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        guard let cgImage = qrContext.createCGImage(transformedImage, from: transformedImage.extent) else { return nil }

        return UIImage(cgImage: cgImage)
    }
}
