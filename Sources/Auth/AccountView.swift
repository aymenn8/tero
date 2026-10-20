import SwiftUI

struct AccountView: View {
    @Bindable var account: AccountStore
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(spacing: 10) {
                Image(systemName: "person.crop.circle").font(.system(size: 31, weight: .light))
                    .foregroundStyle(.white.opacity(0.65)).frame(width: 68, height: 68)
                    .background(.white.opacity(0.055), in: Circle()).accessibilityHidden(true)
                Text(account.user == nil ? "Your Tero account" : "Connected to Tero")
                    .font(SettingsStyle.font(17, weight: .semibold))
                Text(account.user?.email ?? "Sign in on the web. Come back ready to go.")
                    .font(SettingsStyle.font(11)).foregroundStyle(SettingsStyle.secondary).textSelection(.enabled)
            }.frame(maxWidth: .infinity).padding(.vertical, 7)
            if account.user == nil {
                SettingsGroup(title: "Connect your Mac") {
                    SettingsRow(title: "Sign in", detail: "Use Apple, Google or an email code in your browser.") {
                        Button(account.isSigningIn ? "Opening browser…" : "Sign in") { account.signIn() }
                            .buttonStyle(SettingsPill()).disabled(account.isBusy)
                    }
                    if account.isSigningIn {
                        SettingsDivider()
                        SettingsRow(title: "Waiting for your browser") {
                            Button("Cancel", action: account.cancelSignIn).buttonStyle(SettingsPill())
                        }
                    }
                }
            } else {
                if let usage = account.usage {
                    SettingsGroup(title: "Your plan") {
                        SettingsRow(title: usage.plan == "pro" ? "Tero Pro" : "No subscription") {
                            Text(usage.plan == "pro" ? "Active" : AIConfiguration.active.map { "AI: " + $0.provider.title } ?? "AI not set up").font(SettingsStyle.font(11)).foregroundStyle(SettingsStyle.secondary)
                        }
                        SettingsDivider()
                        if usage.plan == "pro" {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack { Text("Usage"); Spacer(); Text("\(Int(usage.remainingPercent.rounded()))% left").foregroundStyle(SettingsStyle.secondary) }
                                ProgressView(value: usage.remainingPercent, total: 100).tint(.white.opacity(0.8))
                                if let date = usage.resetDate { Text("Resets \(date.formatted(date: .abbreviated, time: .omitted))").font(SettingsStyle.font(11)).foregroundStyle(SettingsStyle.secondary) }
                                if usage.creditsRemainingEUR > 0 { Text("Extra credits: \(usage.creditsRemainingEUR.formatted(.currency(code: "EUR")))").font(SettingsStyle.font(11)).foregroundStyle(SettingsStyle.secondary) }
                            }.padding(15)
                        } else {
                            // Discreet by design: Tero works with the person's own AI key.
                            SettingsRow(title: "AI", detail: "Tero uses your own provider from Settings → AI. Tero Pro includes AI if you prefer.") {
                                Button("Learn more", action: account.openBilling).buttonStyle(.link).font(SettingsStyle.font(11))
                            }
                        }
                    }

                } else {
                    SettingsGroup(title: "Your plan") {
                        SettingsRow(title: account.isBusy ? "Loading your usage…" : "Usage unavailable", detail: "Refresh to get your current plan and allowance.") {
                            Button("Refresh", action: account.prepare).buttonStyle(SettingsPill()).disabled(account.isBusy)
                        }
                    }
                }
                SettingsGroup(title: "Account") {
                    SettingsRow(title: "Manage account", detail: "Profile, subscription, credits and email preferences.") {
                        Button("Open website", action: account.openBilling).buttonStyle(SettingsPill())
                    }
                    SettingsDivider()
                    SettingsRow(title: "Sign out") { Button("Sign out", action: account.signOut).foregroundStyle(.red.opacity(0.9)).buttonStyle(SettingsPill()).disabled(account.isBusy) }
                }
            }
            HStack(spacing: 8) {
                if account.isBusy { ProgressView().controlSize(.mini) }
                if let message = account.message { Text(message).font(SettingsStyle.font(11)).foregroundStyle(SettingsStyle.secondary).fixedSize(horizontal: false, vertical: true) }
                Spacer()
            }
        }.onAppear(perform: account.prepare)
    }
}
