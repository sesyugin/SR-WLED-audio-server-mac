import AppKit
import SwiftUI
import SRWLEDCore
import SRWLEDVisuals

/// Окно «О программе»: что это, кто сделал и на чьих плечах стоит.
struct AboutWindow: View {
    @ObservedObject var model: AppModel

    private var version: String {
        let bundle = Bundle.main
        let short = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
        let build = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                Divider().opacity(0.4)

                VStack(alignment: .leading, spacing: 22) {
                    about
                    author
                    credits
                    legal
                }
                .padding(26)
            }
        }
        .frame(width: 520, height: 620)
        .background(Color(red: 0.043, green: 0.035, blue: 0.055))
        .environment(\.layoutDirection, model.language.isRightToLeft ? .rightToLeft : .leftToRight)
    }

    // MARK: Шапка

    private var header: some View {
        ZStack {
            // Живая сцена в шапке — приложение показывает себя само.
            CrownScene(sampler: { model.sampleBands() },
                       isRunning: model.isRunning,
                       palette: model.palette)
                .frame(height: 170)
                .clipped()

            // Затемнение между сценой и надписью. Сцена ярче всего ровно
            // посередине — там, где стоит имя, — и подпись в ней тонула:
            // тень вокруг букв с этим не справляется, потому что спорит
            // не с фоном, а со светом. Книзу гуще: там мелкая подпись.
            LinearGradient(colors: [.black.opacity(0.10),
                                    .black.opacity(0.34),
                                    .black.opacity(0.66)],
                           startPoint: .top, endPoint: .bottom)

            VStack(spacing: 12) {
                BrandMark()
                    .frame(width: 92, height: 52)
                VStack(spacing: 5) {
                    Text(Brand.name)
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .kerning(1.5)
                        .foregroundStyle(.white)
                    Text(Brand.tagline.uppercased())
                        .font(.system(size: 9, weight: .semibold))
                        .kerning(2.6)
                        .foregroundStyle(.white.opacity(0.72))
                }
            }
            .shadow(color: .black.opacity(0.7), radius: 16, y: 3)
        }
        .frame(height: 170)
    }

    // MARK: Разделы

    private var about: some View {
        section(model.localized(.aboutWhat)) {
            Text(model.localized(.aboutBody))
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)

            row(model.localized(.aboutVersion), version)
            row(model.localized(.aboutPlatform), model.localized(.aboutPlatformValue))
        }
    }

    private var author: some View {
        section(model.localized(.aboutAuthor)) {
            Text(model.localized(.authorName))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
            Text(model.localized(.authorBio))
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                linkButton(model.localized(.linkMail), "mailto:sesyuginzd@gmail.com")
                linkButton("Telegram", "https://t.me/SesyuginZD")
                linkButton("GitHub", Brand.repository)
            }
            .padding(.top, 2)
        }
    }

    private var credits: some View {
        section(model.localized(.aboutCredits)) {
            creditRow("SR-WLED-audio-server-win",
                      model.localized(.creditOriginal),
                      "https://github.com/Victoare/SR-WLED-audio-server-win")
            creditRow("WLED",
                      model.localized(.creditWLED),
                      "https://github.com/wled/WLED")
            creditRow("WLED MoonModules",
                      model.localized(.creditMM),
                      "https://github.com/MoonModules/WLED-MM")
        }
    }

    private var legal: some View {
        section(model.localized(.aboutLicense)) {
            Text(model.localized(.licenseNote))
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Мелочи

    private func section<Content: View>(_ title: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .kerning(1.6)
                .foregroundStyle(Brand.accent.opacity(0.85))
            content()
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 11))
                // 0.45 давало ровно 4.50:1 на Brand.ink — впритык к норме
                // и ниже неё при малейшем сдвиге фона. 0.5 даёт 5.3:1.
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 90, alignment: .leading)
            Text(value)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.8))
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }

    private func linkButton(_ title: String, _ url: String) -> some View {
        Button(title) {
            if let link = URL(string: url) { NSWorkspace.shared.open(link) }
        }
        .buttonStyle(.plain)
        .font(.system(size: 11, weight: .medium))
        .padding(.horizontal, 13)
        .padding(.vertical, 6)
        .background(.white.opacity(0.09), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.16), lineWidth: 1))
        .foregroundStyle(.white.opacity(0.9))
        .hoverFillOnDark(cornerRadius: 14, opacity: 0.10)
    }

    private func creditRow(_ title: String, _ detail: String, _ url: String) -> some View {
        Button {
            if let link = URL(string: url) { NSWorkspace.shared.open(link) }
        } label: {
            HStack(alignment: .top, spacing: 9) {
                Circle()
                    .fill(Brand.accent.opacity(0.7))
                    .frame(width: 5, height: 5)
                    .padding(.top, 5)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.top, 3)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverFillOnDark(cornerRadius: 7, opacity: 0.08)
        .padding(.horizontal, -6)
    }
}
