import SwiftUI

struct ShellScreenScaffold<Content: View>: View {
    let title: String
    let subtitle: String
    var showsHeader = true
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if showsHeader {
                    VStack(spacing: 10) {
                        Text(title)
                            .font(.largeTitle.weight(.bold))

                        Text(subtitle)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                }

                content
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}
