import SwiftUI

struct CookingModeView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("keep_screen_awake") private var keepScreenAwake = true
    
    let recipe: Recipe
    let servings: Int
    
    @State private var currentStepIndex = 0
    @State private var activeTimers: [UUID: TimerState] = [:]
    @State private var countdownTimers: [UUID: Timer] = [:]
    @State private var showIngredients = false
    @State private var showFinishOptions = false
    
    private var sortedSteps: [RecipeStep] {
        recipe.steps.sorted { $0.order < $1.order }
    }
    
    private var currentStep: RecipeStep? {
        guard currentStepIndex < sortedSteps.count else { return nil }
        return sortedSteps[currentStepIndex]
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Top bar
                HStack {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.white)
                    
                    Spacer()
                    
                    Text(recipe.title)
                        .font(.headline)
                        .foregroundStyle(.white)
                    
                    Spacer()
                    
                    Button {
                        showIngredients.toggle()
                    } label: {
                        Image(systemName: "list.bullet")
                            .foregroundStyle(.white)
                    }
                }
                .padding()
                
                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(.gray.opacity(0.3))
                        Rectangle()
                            .fill(Color.rvAccent)
                            .frame(width: geo.size.width * progressFraction)
                            .animation(.easeInOut, value: currentStepIndex)
                    }
                }
                .frame(height: 4)
                
                // Step content
                if let step = currentStep {
                    Spacer()
                    
                    VStack(spacing: 24) {
                        Text("Step \(currentStepIndex + 1) of \(sortedSteps.count)")
                            .font(.subheadline)
                            .foregroundStyle(.gray)
                        
                        Text(step.instruction)
                            .font(.title2.weight(.medium))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                        
                        // Timer
                        if let seconds = step.timerSeconds, seconds > 0 {
                            timerView(for: step, totalSeconds: seconds)
                        }
                    }
                    
                    Spacer()
                    
                    // Navigation
                    HStack(spacing: 40) {
                        Button {
                            withAnimation {
                                currentStepIndex = max(0, currentStepIndex - 1)
                                HapticFeedback.stepComplete()
                            }
                        } label: {
                            Image(systemName: "chevron.left.circle.fill")
                                .font(.system(size: 56))
                                .foregroundStyle(currentStepIndex > 0 ? Color.rvAccent : .gray.opacity(0.3))
                        }
                        .disabled(currentStepIndex == 0)
                        
                        Button {
                            if currentStepIndex < sortedSteps.count - 1 {
                                withAnimation {
                                    currentStepIndex += 1
                                    HapticFeedback.stepComplete()
                                }
                            } else {
                                HapticFeedback.timerComplete()
                                showFinishOptions = true
                            }
                        } label: {
                            Image(systemName: currentStepIndex < sortedSteps.count - 1
                                  ? "chevron.right.circle.fill"
                                  : "checkmark.circle.fill")
                                .font(.system(size: 56))
                                .foregroundStyle(Color.rvAccent)
                        }
                        .accessibilityLabel(currentStepIndex < sortedSteps.count - 1 ? "Next step" : "Finish cooking")
                    }
                    .padding(.bottom, 40)
                } else {
                    Spacer()
                    Text("No steps available")
                        .foregroundStyle(.gray)
                    Spacer()
                }
                
                // Active timers bar
                if !activeTimers.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(Array(activeTimers.keys), id: \.self) { id in
                                if let timer = activeTimers[id] {
                                    ActiveTimerPill(timer: timer)
                                }
                            }
                        }
                        .padding()
                    }
                    .background(.ultraThinMaterial.opacity(0.3))
                }
            }
        }
        .statusBarHidden()
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = keepScreenAwake
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            // Stop countdowns when leaving cooking mode so dismissed timers
            // don't keep ticking (and firing haptics) in the background.
            // Scheduled notifications for still-running timers are kept on
            // purpose: the food on the stove doesn't care that the screen
            // closed, and the alert remains the truth.
            for timer in countdownTimers.values {
                timer.invalidate()
            }
            countdownTimers.removeAll()
        }
        .onChange(of: keepScreenAwake) { _, shouldKeepAwake in
            UIApplication.shared.isIdleTimerDisabled = shouldKeepAwake
        }
        .sheet(isPresented: $showIngredients) {
            NavigationStack {
                ingredientSheet
            }
            .presentationDetents([.medium, .large])
        }
        // Finishing the last step is the natural moment to record a cook —
        // previously "Mark as Cooked" only existed buried in the detail menu.
        .confirmationDialog("Finished cooking?", isPresented: $showFinishOptions, titleVisibility: .visible) {
            Button("Mark as Cooked & Close") {
                recipe.timesCooked += 1
                recipe.dateLastCooked = Date()
                dismiss()
            }
            Button("Close Without Marking") {
                dismiss()
            }
            Button("Keep Cooking", role: .cancel) { }
        }
    }
    
    private var progressFraction: CGFloat {
        guard sortedSteps.count > 0 else { return 0 }
        return CGFloat(currentStepIndex + 1) / CGFloat(sortedSteps.count)
    }
    
    // MARK: - Timer View
    
    @ViewBuilder
    private func timerView(for step: RecipeStep, totalSeconds: Int) -> some View {
        let timerState = activeTimers[step.id]
        
        VStack(spacing: 12) {
            if let state = timerState {
                Text(state.formattedRemaining)
                    .font(.system(size: 48, weight: .bold, design: .monospaced))
                    .foregroundStyle(state.remaining <= 10 ? .red : Color.rvAccent)
                
                HStack(spacing: 20) {
                    Button {
                        toggleTimer(for: step.id)
                    } label: {
                        Image(systemName: state.isRunning ? "pause.circle.fill" : "play.circle.fill")
                            .font(.title)
                            .foregroundStyle(Color.rvAccent)
                    }
                    .accessibilityLabel(state.isRunning ? "Pause timer" : "Resume timer")

                    Button {
                        countdownTimers[step.id]?.invalidate()
                        countdownTimers.removeValue(forKey: step.id)
                        activeTimers.removeValue(forKey: step.id)
                        TimerNotificationService.shared.cancelTimerNotification(stepID: step.id)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.gray)
                    }
                    .accessibilityLabel("Cancel timer")
                }
            } else {
                Button {
                    let state = TimerState(
                        stepID: step.id,
                        label: step.timerLabel ?? "Timer",
                        total: totalSeconds,
                        endDate: Date().addingTimeInterval(TimeInterval(totalSeconds)),
                        remaining: totalSeconds
                    )
                    activeTimers[step.id] = state
                    startCountdown(for: step.id)
                    // A local notification is the only completion signal that
                    // reaches the cook when the phone is locked or face-down.
                    TimerNotificationService.shared.requestAuthorizationIfNeeded()
                    TimerNotificationService.shared.scheduleTimerNotification(
                        stepID: step.id,
                        label: state.label,
                        recipeTitle: recipe.title,
                        fireDate: state.endDate
                    )
                    HapticFeedback.buttonTap()
                } label: {
                    Label(step.timerFormatted ?? "\(totalSeconds)s", systemImage: "timer")
                        .font(.title3.bold())
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.rvAccent)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
            }
        }
    }
    
    private func toggleTimer(for id: UUID) {
        guard var state = activeTimers[id] else { return }
        if state.isRunning {
            state.remaining = max(0, Int(state.endDate.timeIntervalSinceNow.rounded()))
            state.isRunning = false
            TimerNotificationService.shared.cancelTimerNotification(stepID: id)
        } else {
            state.endDate = Date().addingTimeInterval(TimeInterval(state.remaining))
            state.isRunning = true
            TimerNotificationService.shared.scheduleTimerNotification(
                stepID: id,
                label: state.label,
                recipeTitle: recipe.title,
                fireDate: state.endDate
            )
        }
        activeTimers[id] = state
    }

    private func startCountdown(for id: UUID) {
        countdownTimers[id]?.invalidate()
        // Remaining time is derived from a wall-clock end date, not a tick
        // counter, so the countdown stays accurate even when ticks are
        // delayed (scrolling, app briefly backgrounded, screen locked).
        let timer = Timer(timeInterval: 0.5, repeats: true) { timer in
            guard var state = activeTimers[id] else {
                timer.invalidate()
                countdownTimers.removeValue(forKey: id)
                return
            }

            guard state.isRunning else { return }

            let previousRemaining = state.remaining
            state.remaining = max(0, Int(state.endDate.timeIntervalSinceNow.rounded()))
            activeTimers[id] = state

            if state.remaining <= 0 {
                timer.invalidate()
                countdownTimers.removeValue(forKey: id)
                activeTimers.removeValue(forKey: id)
                HapticFeedback.timerComplete()
                // Completed in foreground — the pending notification would
                // arrive as a late, confusing banner once backgrounded.
                TimerNotificationService.shared.cancelTimerNotification(stepID: id)
            } else if previousRemaining > 10 && state.remaining <= 10 {
                HapticFeedback.timerWarning()
            }
        }
        // .common keeps the timer firing while the user scrolls.
        RunLoop.main.add(timer, forMode: .common)
        countdownTimers[id] = timer
    }
    
    // MARK: - Ingredient Sheet
    
    private var ingredientSheet: some View {
        List {
            let scaled = recipe.scaledIngredients(for: servings)
            let sections = Dictionary(grouping: scaled) { $0.section }
            let sortedKeys = sections.keys.sorted { a, b in
                if a.isEmpty { return false }
                if b.isEmpty { return true }
                return a < b
            }
            
            ForEach(sortedKeys, id: \.self) { section in
                Section {
                    ForEach(sections[section] ?? []) { ingredient in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ingredient.displayString)
                                .foregroundStyle(Color.rvInk)
                            
                            if ingredient.isOptional {
                                Text("Optional")
                                    .font(.caption)
                                    .foregroundStyle(Color.rvSubtleText)
                                    .italic()
                            }
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    if !section.isEmpty {
                        ingredientSectionHeader(section)
                            .textCase(nil)
                    }
                }
            }
        }
        .navigationTitle("Ingredients (\(servings) servings)")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(Color.rvBackground)
    }
    
    private func ingredientSectionHeader(_ title: String) -> some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(LinearGradient.rvAccentGradient)
                .frame(width: 24, height: 5)
            
            Text(title.uppercased())
                .font(.caption.weight(.bold))
                .tracking(1)
                .foregroundStyle(Color.rvPrimary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.rvSurface, in: Capsule())
    }
}

// MARK: - Timer State

struct TimerState: Identifiable {
    var id: UUID { stepID }
    let stepID: UUID
    let label: String
    let total: Int
    var endDate: Date
    var remaining: Int
    var isRunning: Bool = true
    
    var formattedRemaining: String {
        let mins = remaining / 60
        let secs = remaining % 60
        return String(format: "%02d:%02d", mins, secs)
    }
    
    var progress: Double {
        guard total > 0 else { return 0 }
        return Double(total - remaining) / Double(total)
    }
}

// MARK: - Active Timer Pill

struct ActiveTimerPill: View {
    let timer: TimerState
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "timer")
                .font(.caption)
            Text(timer.label)
                .font(.caption.bold())
            Text(timer.formattedRemaining)
                .font(.caption.monospacedDigit())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(timer.remaining <= 10 ? .red : Color.rvAccent)
        .foregroundStyle(.white)
        .clipShape(Capsule())
    }
}
