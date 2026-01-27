//
//  WhatIfCategoryRowView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/25/26.
//

import SwiftUI

struct WhatIfCategoryRowView: View {

    let categoryName: String
    let categoryHex: String
    let baselineAmount: Double

    @Binding var amount: Double

    let step: Double
    let currencyCode: String

    @State private var text: String = ""
    @FocusState private var isFocused: Bool

    // Controls sizing
    private let buttonSize: CGFloat = 32
    private let fieldWidth: CGFloat = 110
    private let controlSpacing: CGFloat = 10
    private let resetButtonSize: CGFloat = 28
    private let editedBadgeReserveHeight: CGFloat = 20

    private var controlGroupWidth: CGFloat {
        // minus + spacing + field + spacing + reset + spacing + plus
        buttonSize
        + controlSpacing
        + fieldWidth
        + controlSpacing
        + resetButtonSize
        + controlSpacing
        + buttonSize
    }

    private var dotColor: Color {
        Color(hex: categoryHex) ?? .secondary
    }

    private var isDirty: Bool {
        abs(amount - baselineAmount) > 0.000_1
    }
    
    private var badgeTextLeadingInset: CGFloat {
        10 /* dot width */ + 10 /* spacing between dot and text */
    }

    var body: some View {
        GeometryReader { geo in
            let availableWidth = geo.size.width
            let labelWidth = max(120, availableWidth - controlGroupWidth - 12)
            
            HStack(alignment: .center, spacing: 12) {

                // MARK: - Left column (name + actual, badge as overlay)

                HStack(alignment: .center, spacing: 10) {
                    Circle()
                        .fill(dotColor)
                        .frame(width: 10, height: 10)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(categoryName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Text("Actual: \(formatCurrency(baselineAmount))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .frame(maxHeight: .infinity, alignment: .center) // keeps the two lines centered
                }
                .frame(width: labelWidth, alignment: .leading)
                .padding(.bottom, editedBadgeReserveHeight) // reserve the space no matter what
                .overlay(alignment: .bottomLeading) {
                    editedBadge
                        .padding(.leading, badgeTextLeadingInset)
                        .opacity(isDirty ? 1 : 0)
                        .accessibilityHidden(!isDirty)
                }

                Spacer(minLength: 0)

                // MARK: - Controls

                HStack(spacing: controlSpacing) {

                    RepeatPressButton(
                        systemName: "minus",
                        accessibilityLabel: "Decrease",
                        size: buttonSize,
                        onFire: { adjust(-step) }
                    )

                    TextField("", text: $text)
                        .focused($isFocused)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .font(.subheadline.weight(.semibold))
                        .frame(width: fieldWidth)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .onChange(of: text) { _, newValue in
                            guard isFocused else { return }
                            if let parsed = CurrencyFormatter.parseAmount(newValue) {
                                amount = max(0, parsed)
                            }
                        }
                        .onChange(of: amount) { _, newValue in
                            guard !isFocused else { return }
                            text = CurrencyFormatter.editingString(from: newValue)
                        }
                        .onAppear {
                            text = CurrencyFormatter.editingString(from: amount)
                        }

                    RepeatPressButton(
                        systemName: "plus",
                        accessibilityLabel: "Increase",
                        size: buttonSize,
                        onFire: { adjust(step) }
                    )
                }
            }
            .frame(width: availableWidth, alignment: .leading)
        }
        // Increased slightly so the 3rd line (Edited) doesn’t clip.
        .frame(height: 66)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(categoryName)
        .accessibilityValue(formatCurrency(amount))
    }

    // MARK: - Badge

    private var editedBadge: some View {
        Text("Edited")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.thinMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(.secondary.opacity(0.25), lineWidth: 1)
            }
            .accessibilityLabel("Edited")
    }

    // MARK: - Helpers

    private func resetToBaseline() {
        amount = max(0, baselineAmount)

        if !isFocused {
            text = CurrencyFormatter.editingString(from: amount)
        }
    }

    private func adjust(_ delta: Double) {
        let next = max(0, amount + delta)
        amount = next

        if !isFocused {
            text = CurrencyFormatter.editingString(from: amount)
        }
    }

    private func formatCurrency(_ value: Double) -> String {
        value.formatted(
            .currency(code: currencyCode)
            .presentation(.standard)
        )
    }
}

// MARK: - Press-and-hold repeating button

private struct RepeatPressButton: View {

    let systemName: String
    let accessibilityLabel: String
    let size: CGFloat
    let onFire: () -> Void

    private let initialDelay: TimeInterval = 0.35
    private let repeatInterval: TimeInterval = 0.08

    @State private var isPressing: Bool = false
    @State private var timer: Timer? = nil

    var body: some View {
        Button {
            onFire()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: size, height: size)
                .background(.thinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.20)
                .onEnded { _ in
                    startRepeating()
                }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if isPressing == false { isPressing = true }
                }
                .onEnded { _ in
                    stopRepeating()
                }
        )
        .onDisappear { stopRepeating() }
    }

    private func startRepeating() {
        stopRepeating()
        isPressing = true

        onFire()

        DispatchQueue.main.asyncAfter(deadline: .now() + initialDelay) {
            guard isPressing else { return }
            timer = Timer.scheduledTimer(withTimeInterval: repeatInterval, repeats: true) { _ in
                onFire()
            }
            if let timer {
                RunLoop.main.add(timer, forMode: .common)
            }
        }
    }

    private func stopRepeating() {
        isPressing = false
        timer?.invalidate()
        timer = nil
    }
}
