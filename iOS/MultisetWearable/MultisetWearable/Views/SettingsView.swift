/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

import SwiftUI

/// Settings view for configuring localization parameters
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var mapCode: String
    @State private var mapSetCode: String

    private let config = LocalizationConfig.shared

    init() {
        let config = LocalizationConfig.shared
        _mapCode = State(initialValue: config.mapCode)
        _mapSetCode = State(initialValue: config.mapSetCode)
    }

    var body: some View {
        NavigationStack {
            Form {
                // Credentials Status Section
                Section {
                    HStack {
                        Text("API Status")
                        Spacer()
                        if config.hasCredentials {
                            Label("Configured", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        } else {
                            Label("Not Configured", systemImage: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                        }
                    }

                    if !config.hasCredentials {
                        Text("Add MULTISET_CLIENT_ID and MULTISET_CLIENT_SECRET to your build settings.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("API Credentials")
                }

                // Map Configuration Section
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Map Code")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("Enter map code", text: $mapCode)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Map Set Code")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("Enter map set code", text: $mapSetCode)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }

                    Text("Enter either a map code for single map localization, or a map set code for multi-map localization.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } header: {
                    Text("Map Configuration")
                }

                // Configuration Status
                Section {
                    HStack {
                        Text("Ready to Localize")
                        Spacer()
                        if isConfigurationValid {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        } else {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                        }
                    }

                    if !isConfigurationValid {
                        VStack(alignment: .leading, spacing: 4) {
                            if !config.hasCredentials {
                                Label("Missing API credentials", systemImage: "exclamationmark.circle")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                            if mapCode.isEmpty && mapSetCode.isEmpty {
                                Label("Missing map code", systemImage: "exclamationmark.circle")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                } header: {
                    Text("Status")
                }
            }
            .navigationTitle("Localization Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveSettings()
                        dismiss()
                    }
                }
            }
        }
    }

    private var isConfigurationValid: Bool {
        config.hasCredentials && (!mapCode.isEmpty || !mapSetCode.isEmpty)
    }

    private func saveSettings() {
        config.mapCode = mapCode.trimmingCharacters(in: .whitespacesAndNewlines)
        config.mapSetCode = mapSetCode.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

#Preview {
    SettingsView()
}
