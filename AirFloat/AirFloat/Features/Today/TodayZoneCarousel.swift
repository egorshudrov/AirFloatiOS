import SwiftUI

struct TodayZoneCarousel: View {
    @Binding var selectedZone: MuscleZone
    let zones: [TodayMuscleZoneModel]

    var body: some View {
        VStack(spacing: 10) {
            TabView(selection: $selectedZone) {
                ForEach(zones) { model in
                    TodayZoneCarouselPage(model: model)
                        .tag(model.zone)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 260)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            HStack(spacing: 7) {
                ForEach(zones) { model in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedZone = model.zone
                        }
                    } label: {
                        Capsule()
                            .fill(model.zone == selectedZone ? model.accentColor : Color.secondary.opacity(0.32))
                            .frame(width: model.zone == selectedZone ? 18 : 7, height: 7)
                            .frame(width: 28, height: 24)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(model.zone.displayName)
                    .accessibilityAddTraits(model.zone == selectedZone ? .isSelected : [])
                    .animation(.easeInOut(duration: 0.18), value: selectedZone)
                }
            }
        }
    }
}

private struct TodayZoneCarouselPage: View {
    let model: TodayMuscleZoneModel

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            GeometryReader { geometry in
                Image(model.zone.previewAssetName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .scaleEffect(model.zone.previewScale)
                    .offset(model.zone.previewOffset)
                    .clipped()
            }
            .clipped()

            LinearGradient(
                colors: [
                    .black.opacity(0.74),
                    .black.opacity(0.22),
                    .clear
                ],
                startPoint: .bottom,
                endPoint: .top
            )

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.zone.displayName)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)

                    Text(model.rank.rawValue)
                        .font(.caption.monospaced().weight(.bold))
                        .foregroundStyle(model.hasData ? model.accentColor : .white.opacity(0.74))
                }

                Spacer()

                Text(model.lastSeenLabel)
                    .font(.caption.monospaced().weight(.semibold))
                    .foregroundStyle(.white.opacity(0.74))
            }
            .padding(16)
        }
    }
}

private extension MuscleZone {
    var previewAssetName: String {
        switch self {
        case .chest:
            return "today_pushups"
        case .core:
            return "today_sit_up"
        case .arms:
            return "today_barbell_press"
        case .legs:
            return "today_squats"
        }
    }

    var previewScale: CGFloat {
        switch self {
        case .chest:
            return 1.08
        case .core:
            return 1.12
        case .arms:
            return 1.18
        case .legs:
            return 1.02
        }
    }

    var previewOffset: CGSize {
        switch self {
        case .chest:
            return CGSize(width: -10, height: 0)
        case .core:
            return CGSize(width: -18, height: 2)
        case .arms:
            return CGSize(width: -14, height: 0)
        case .legs:
            return .zero
        }
    }
}
