//
//  AboutView.swift
//  mushroomHunter
//
//  Purpose:
//  - Presents static support and contact information reachable from profile settings.
//
import SwiftUI

/// About screen with support contact channels.
struct AboutView: View {
    /// Phone destination if URL construction succeeds.
    private let phoneURL: URL? = URL(string: "tel://886930200769")

    /// Email destination if URL construction succeeds.
    private let emailURL: URL? = URL(string: "mailto:kenyu910645@gmail.com")

    /// Website destination if URL construction succeeds.
    private let websiteURL: URL? = URL(string: "https://kenyu910645.github.io/")

    /// About content that presents support contact links.
    var body: some View {
        List {
            Section {
                Text(LocalizedStringKey("about_intro"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("about_intro_text")
            }

            Section {
                LabeledContent(LocalizedStringKey("about_phone_label")) {
                    if let phoneURL {
                        Link("+886 930200769", destination: phoneURL)
                    } else {
                        Text("+886 930200769")
                    }
                }

                LabeledContent(LocalizedStringKey("about_email_label")) {
                    if let emailURL {
                        Link("kenyu910645@gmail.com", destination: emailURL)
                    } else {
                        Text("kenyu910645@gmail.com")
                    }
                }

                LabeledContent(LocalizedStringKey("about_website_label")) {
                    if let websiteURL {
                        Link("kenyu910645.github.io", destination: websiteURL)
                    } else {
                        Text("kenyu910645.github.io")
                    }
                }
            }
        }
        .navigationTitle(LocalizedStringKey("about_title"))
    }
}
