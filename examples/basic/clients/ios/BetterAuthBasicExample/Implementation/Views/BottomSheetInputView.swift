import SwiftUI

struct BottomSheetInputView: View {
    let title: String
    let fields: [(placeholder: String, binding: Binding<String>)]
    let actionTitle: String
    let isLoading: Bool
    let onSubmit: () async -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text(title)
                .font(.headline)
                .padding(.top)

            ForEach(0..<fields.count, id: \.self) { index in
                TextField(fields[index].placeholder, text: fields[index].binding)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.horizontal)
            }

            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.gray.opacity(0.2))
                .foregroundColor(.primary)
                .cornerRadius(10)

                Button(action: {
                    Task {
                        await onSubmit()
                        dismiss()
                    }
                }) {
                    HStack {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .frame(width: 20, height: 20)
                        }
                        Text(actionTitle)
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isLoading ? Color.gray : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .disabled(isLoading)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .presentationDetents([.height(200 + CGFloat(fields.count * 50))])
        .presentationDragIndicator(.visible)
    }
}
