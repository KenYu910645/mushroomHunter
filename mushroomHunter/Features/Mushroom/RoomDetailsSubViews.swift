//
//  RoomDetailsSubViews.swift
//  mushroomHunter
//
//  Purpose:
//  - Provides reusable Mushroom room-detail subviews and UI helpers.
//
//  Defined in this file:
//  - Invite sheet, QR rendering helpers, and small supporting views.
//
import SwiftUI
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

struct RoomInviteSheet: View {
    @Environment(\.dismiss) private var dismiss // State or dependency property.
    let roomTitle: String
    let inviteURL: URL?
    let onCopyInviteLink: (String) -> Void

    private let qrContext = CIContext()
    private let qrFilter = CIFilter.qrCodeGenerator()

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text(String(format: NSLocalizedString("room_invite_hint", comment: ""), roomTitle))
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
                            Label(LocalizedStringKey("room_invite_share_button"), systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            onCopyInviteLink(link)
                        } label: {
                            Label(LocalizedStringKey("room_invite_copy_button"), systemImage: "doc.on.doc")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.horizontal)
                } else {
                    ContentUnavailableView(
                        LocalizedStringKey("room_load_error_title"),
                        systemImage: "qrcode",
                        description: Text(LocalizedStringKey("room_invite_link_unavailable"))
                    )
                }

                Spacer()
            }
            .padding(.top, 20)
            .navigationTitle(LocalizedStringKey("room_invite_title"))
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

    private func qrImage(from string: String) -> UIImage? {
        let data = Data(string.utf8)
        qrFilter.setValue(data, forKey: "inputMessage")
        qrFilter.setValue("M", forKey: "inputCorrectionLevel")

        guard let outputImage = qrFilter.outputImage else { return nil }
        let outputSize = outputImage.extent.size
        guard outputSize.width > 0, outputSize.height > 0 else { return nil }

        let targetSize: CGFloat = 260
        let scaleX = targetSize / outputSize.width
        let scaleY = targetSize / outputSize.height
        let transformedImage = outputImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        guard let cgImage = qrContext.createCGImage(transformedImage, from: transformedImage.extent) else { return nil }

        return UIImage(cgImage: cgImage)
    }
}

struct AttendeeRow: View {
    let attendee: RoomAttendee
    let isHostAttendee: Bool
    let isHostViewing: Bool
    let isPendingConfirmation: Bool
    let isRejectedConfirmation: Bool
    let onKick: () -> Void
    let onResolve: () -> Void
    let onCopyFriendCode: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(attendee.name)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                HStack(spacing: 6) {
                    Text(attendee.friendCodeFormatted)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Button {
                        onCopyFriendCode(attendee.friendCode)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(LocalizedStringKey("room_copy_attendee_code_accessibility"))
                }
            }

            HStack(spacing: 10) {
                if isHostAttendee {
                    Text(LocalizedStringKey("room_status_host"))
                        .font(.footnote)
                        .foregroundStyle(.blue)
                } else {
                    if isPendingConfirmation {
                        Text(LocalizedStringKey("room_status_waiting_confirm"))
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }

                    if isRejectedConfirmation {
                        Text(LocalizedStringKey("room_status_rejected"))
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    if !isPendingConfirmation, !isRejectedConfirmation {
                        Text(LocalizedStringKey("room_status_ready"))
                            .font(.footnote)
                            .foregroundStyle(.green)
                    }
                }

                Spacer()

                if !isHostAttendee {
                    HStack(spacing: 4) {
                        Image("HoneyIcon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                        Text(String(format: NSLocalizedString("room_bid_honey_format", comment: ""), attendee.depositHoney))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }

                Label("\(attendee.stars)", systemImage: "star.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if isHostViewing && !isHostAttendee {
                    Menu {
                        Button(role: .destructive) {
                            onKick()
                        } label: {
                            Label(LocalizedStringKey("room_kick"), systemImage: "person.fill.xmark")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack {
                Spacer()
                if isHostViewing, isRejectedConfirmation, !isHostAttendee {
                    Button(LocalizedStringKey("room_reject_resolve")) {
                        onResolve()
                    }
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
