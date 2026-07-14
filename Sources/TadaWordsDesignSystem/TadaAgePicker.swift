import SwiftUI

/// A large, direct-manipulation age control shared by kid and parent profile
/// forms. The caller supplies the domain-supported values.
public struct TadaAgePicker: View {
    @Binding private var selection: Int?
    private let ages: ClosedRange<Int>
    private let prompt: String
    private let tint: Color

    public init(
        selection: Binding<Int?>,
        ages: ClosedRange<Int>,
        prompt: String,
        tint: Color
    ) {
        _selection = selection
        self.ages = ages
        self.prompt = prompt
        self.tint = tint
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: TadaPrimitiveTokens.Spacing.small) {
            HStack {
                Text(prompt)
                    .font(.system(.headline, design: .rounded, weight: .bold))
                if selection == nil {
                    Text("Choose one")
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(tint.opacity(0.10), in: Capsule())
                }
            }

            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 10) {
                        ForEach(Array(ages), id: \.self) { age in
                            ageButton(age)
                                .id(age)
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 2)
                }
                .scrollIndicators(.visible)
                .onAppear {
                    guard let selection else { return }
                    proxy.scrollTo(selection, anchor: .center)
                }
                .onChange(of: selection) { _, age in
                    guard let age else { return }
                    withAnimation(.easeOut(duration: TadaPrimitiveTokens.Motion.quick)) {
                        proxy.scrollTo(age, anchor: .center)
                    }
                }
            }
        }
    }

    private func ageButton(_ age: Int) -> some View {
        let isSelected = selection == age
        return Button {
            selection = age
        } label: {
            Text("\(age)")
                .font(.system(.title3, design: .rounded, weight: .heavy))
                .frame(width: 48, height: 48)
                .foregroundStyle(isSelected ? Color.white : tint)
                .background(
                    isSelected ? tint : tint.opacity(0.10),
                    in: Circle()
                )
                .overlay {
                    Circle()
                        .strokeBorder(
                            isSelected ? Color.white.opacity(0.78) : tint.opacity(0.24),
                            lineWidth: isSelected ? 2 : 1
                        )
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Age \(age)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
