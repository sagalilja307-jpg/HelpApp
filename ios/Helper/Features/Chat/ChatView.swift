//
//  ChatView.swift
//  Helper
//
//  Created by Saga Lilja on 2026-01-24.
//

import SwiftUI

public struct ChatView: View {
    @Bindable var vm: ChatViewModel
    @FocusState private var focusInput: Bool
    @State private var showContext = false

    init(pipeline: QueryPipeline) {
        self.vm = ChatViewModel(pipeline: pipeline)
    }

    public var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(vm.messages) { msg in
                            bubble(for: msg)
                                .id(msg.id)
                        }
                        if vm.isSending {
                            ProgressView().padding(.vertical, 8)
                        }
                    }
                    .padding(16)
                }
                .onChange(of: vm.messages.count) { oldValue, newValue in
                    if let last = vm.messages.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            if showContext {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Lägg till kontext (valfritt)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    TextEditor(text: $vm.extraContext)
                        .frame(minHeight: 80, maxHeight: 160)
                        .padding(8)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
                }
                .padding([.horizontal, .top])
            }

            HStack(spacing: 8) {
                Button {
                    showContext.toggle()
                } label: {
                    Image(systemName: showContext ? "doc.text.magnifyingglass" : "doc.badge.plus")
                }
                .accessibilityLabel("Visa eller dölj kontextruta")

                TextField("Skriv en fråga…", text: $vm.query, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusInput)
                    .lineLimit(1...4)
                    .onSubmit {
                        Task { await vm.send() }
                    }

                Button {
                    Task { await vm.send() }
                } label: {
                    Image(systemName: vm.isSending ? "hourglass" : "paperplane.fill")
                }
                .disabled(vm.isSending || vm.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
        }
        .navigationTitle("Fråga hjälparen")
        .alert("Fel", isPresented: .constant(vm.error != nil)) {
            Button("OK") { vm.error = nil }
        } message: {
            Text(vm.error ?? "")
        }
    }

    // MARK: - Bubblor

    @ViewBuilder private func bubble(for msg: ChatViewModel.ChatMessage) -> some View {
        let isUser = (msg.role == .user)
        HStack {
            if isUser { Spacer() }
            Text(msg.text)
                .padding(12)
                .background(isUser ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .textSelection(.enabled)
            if !isUser { Spacer() }
        }
    }
}
