// © www.3DaysOfSwiftConcurrency.com. All rights reserved.

import SwiftUI

struct HabitsView: View {
    @State private var viewModel = HabitsViewModel()
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        @Bindable var viewModel = viewModel

        NavigationStack {
            Group {
                if viewModel.isLoadingPurchase {
                    SwiftUI.ProgressView("Checking your purchase…")
                } else if !viewModel.hasUnlockedHabits || viewModel.isPurchasing {
                    paywall
                } else if viewModel.habitLoadState == .idle || viewModel.habitLoadState == .loading {
                    SwiftUI.ProgressView("Loading your habits…")
                } else if case .failed(let message) = viewModel.habitLoadState {
                    habitLoadFailure(message)
                } else if viewModel.habits.isEmpty {
                    emptyState
                } else {
                    habitList
                }
            }
            .background(themeManager.palette.background)
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(isPresented: $viewModel.isChoosingHabits) {
            HabitLibraryView()
        }
        .alert("Trend Habits", isPresented: Binding(
            get: { viewModel.purchaseMessage != nil },
            set: { if !$0 { viewModel.dismissPurchaseMessage() } }
        )) {
            Button("OK") { viewModel.dismissPurchaseMessage() }
        } message: {
            Text(viewModel.purchaseMessage ?? "")
        }
        .fullScreenCover(isPresented: $viewModel.showsPurchaseJourney) {
            PurchaseJourneyView()
        }
        .onChange(of: viewModel.newlyCompletedPurchaseID) { _, completionID in
            viewModel.purchaseCompleted(completionID)
        }
    }

    private var paywall: some View {
        ScrollView {
            VStack(spacing: 24) {
                ZStack {
                    Circle().fill(themeManager.palette.accent.opacity(0.14))
                    Image(systemName: "dumbbell.fill")
                        .font(.system(size: 58, weight: .medium))
                        .foregroundStyle(themeManager.palette.accent)
                }
                .frame(width: 144, height: 144)

                Text(viewModel.unlockTitle)
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: 16) {
                    benefit("Track gym visits, yoga and meditation", symbol: "figure.yoga")
                    benefit("Daily check-ins on your Today screen", symbol: "sun.max.fill")
                    benefit("Track morning mood, runs, sauna and your own custom habits", symbol: "gift.fill")
                    benefit("Track your consistency over time", symbol: "chart.xyaxis.line")
                    benefit("See trends in your habits", symbol: "chart.line.uptrend.xyaxis")
                    benefit("Pay once—no subscription", symbol: "infinity")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .background(themeManager.palette.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))

                Button {
                    viewModel.purchaseHabits()
                } label: {
                    if viewModel.isPurchasing {
                        SwiftUI.ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text("Unlock for \(viewModel.productPrice)")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(viewModel.isPurchasing)

                Button("Restore Purchases") {
                    viewModel.restorePurchases()
                }
                .font(.footnote.weight(.semibold))
                .disabled(viewModel.isPurchasing)

                Text("Payment will be charged to your App Store account. This non-consumable purchase can be restored on your devices.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
        }
    }

    private func benefit(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .foregroundStyle(.primary)
            .symbolRenderingMode(.hierarchical)
    }

    private var emptyState: some View {
        VStack(spacing: 22) {
            Spacer()
            ZStack {
                Circle()
                    .fill(themeManager.palette.accent.opacity(0.14))
                Image(systemName: "scope")
                    .font(.system(size: 58, weight: .medium))
                    .foregroundStyle(themeManager.palette.accent)
            }
            .frame(width: 132, height: 132)

            Text("Choose what matters now")
                .font(.title.bold())
                .multilineTextAlignment(.center)
            Text("Begin with one or two daily signals. A smaller focus makes the direction easier to see.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)

            Button("Choose my habits") { viewModel.isChoosingHabits = true }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func habitLoadFailure(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Couldn’t load your habits", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try again") {
                Task { await viewModel.loadHabits() }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var habitList: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                DailyHabitsView()
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
    }
}
