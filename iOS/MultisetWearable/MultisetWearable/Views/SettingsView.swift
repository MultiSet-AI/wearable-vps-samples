/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

import SwiftUI

/// Settings view showing configuration status
/// Credentials and map codes are configured in LocalizationConfig.swift before building
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    private let config = LocalizationConfig.shared

    var body: some View {
        NavigationStack {
            Form {
                // Configuration Status Section
                Section {
                    HStack {
                        Text("Client ID")
                        Spacer()
                        if !LocalizationConfig.clientId.isEmpty {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        } else {
                            Text("Not configured")
                                .foregroundColor(.orange)
                        }
                    }

                    HStack {
                        Text("Client Secret")
                        Spacer()
                        if !LocalizationConfig.clientSecret.isEmpty {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        } else {
                            Text("Not configured")
                                .foregroundColor(.orange)
                        }
                    }

                    HStack {
                        Text("Map Code")
                        Spacer()
                        if !LocalizationConfig.mapCode.isEmpty {
                            Text(LocalizationConfig.mapCode)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        } else if !LocalizationConfig.mapSetCode.isEmpty {
                            Text("Using Map Set")
                                .foregroundColor(.secondary)
                        } else {
                            Text("Not configured")
                                .foregroundColor(.orange)
                        }
                    }

                    if !LocalizationConfig.mapSetCode.isEmpty {
                        HStack {
                            Text("Map Set Code")
                            Spacer()
                            Text(LocalizationConfig.mapSetCode)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                } header: {
                    Text("API Configuration")
                } footer: {
                    Text("Configure credentials in LocalizationConfig.swift before building the app.")
                }

                // Overall Status
                Section {
                    HStack {
                        Text("Ready to Localize")
                        Spacer()
                        if config.isConfigured {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        } else {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                        }
                    }

                    if !config.isConfigured {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(config.missingConfiguration) { error in
                                Label(error.message, systemImage: "exclamationmark.circle")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                } header: {
                    Text("Status")
                }

                // Help Section
                Section {
                    Link(destination: URL(string: "https://developer.multiset.ai/credentials")!) {
                        HStack {
                            Image(systemName: "link")
                            Text("Get credentials from MultiSet Developer Portal")
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Help")
                }
            }
            .navigationTitle("Configuration Status")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    SettingsView()
}
