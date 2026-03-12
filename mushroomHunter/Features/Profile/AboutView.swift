//
//  AboutView.swift
//  mushroomHunter
//
//  Purpose:
//  - Presents static app background and support information reachable from profile settings.
//
import SwiftUI

/// About screen with app background copy and support links.
struct AboutView: View {
    /// Email destination if URL construction succeeds.
    private let emailURL: URL? = URL(string: "mailto:kenyu910645@gmail.com")

    /// Website destination if URL construction succeeds.
    private let websiteURL: URL? = URL(string: "https://kenyu910645.github.io/")

    /// About message that explains the app concept and feedback path.
    private let aboutMessageKey: LocalizedStringKey = "about_message"

    /// About content that presents app context and support links.
    var body: some View {
        List {
            Section {
                Text(aboutMessageKey)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("about_intro_text")
            }
            .headerProminence(.increased)

            Section(LocalizedStringKey("about_support_title")) {
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
