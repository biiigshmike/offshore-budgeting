import SwiftUI

struct DetailListEmptyRow: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.title3.bold())
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 24)
    }
}
