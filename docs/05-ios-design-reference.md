# 05 — iOS & iPadOS Design Reference

> **Reference Type**: Permanent design reference
> **Last Updated**: 2026-06-02
> **Apple HIG Version**: 2026 (Liquid Glass era)

---

## Design Philosophy

This app is a **productivity tool for professionals**. Every design decision must prioritize:

1. **Information density** — show as much context as possible without overwhelming
2. **Persistent context** — users should never lose their place
3. **Real-time feedback** — agent output, heatmaps, and simulation results stream live
4. **Minimal modality** — avoid interrupting workflows with sheets/alerts

---

## Navigation Architecture

### NavigationSplitView (3-Column)

The app uses a 3-column NavigationSplitView matching the 4-workspace architecture:

```
┌──────────────┬──────────────────────┬────────────────────────────┐
│   SIDEBAR    │     CONTENT          │         DETAIL             │
│              │                      │                            │
│  🏠 Dashboard│  Project List        │  Telemetry Charts          │
│  📥 Ingestion│  Document List       │  Node Graph / RAG Vault    │
│  🎨 Canvas   │  Module Outline      │  Agent Debate + Heatmap    │
│  🧪 Simulation│ Persona List        │  Simulation Results        │
│              │                      │                            │
│  ⚙️ Settings │                      │                            │
│              │                      │                            │
└──────────────┴──────────────────────┴────────────────────────────┘
```

**Behavior**:
- iPad regular width → all 3 columns of `NavigationSplitView` visible
- iPad compact (split view) → content + detail, sidebar collapsible
- iPhone → native `TabView` with bottom tabs wrapping `NavigationStack` layers to ensure perfect ergonomic layout on mobile screens

### Implementation Pattern

```swift
struct ContentView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var selectedWorkspace: Workspace = .dashboard
    
    var body: some View {
        if sizeClass == .compact {
            // iPhone Universal Layout
            TabView(selection: $selectedWorkspace) {
                NavigationStack {
                    DashboardDetailView()
                }
                .tabItem { Label("Dashboard", systemImage: "chart.bar.fill") }
                .tag(Workspace.dashboard)
                
                NavigationStack {
                    DocumentListView()
                }
                .tabItem { Label("Ingestion", systemImage: "arrow.down.doc.fill") }
                .tag(Workspace.ingestion)
                
                NavigationStack {
                    AgentCanvasView()
                }
                .tabItem { Label("Canvas", systemImage: "rectangle.and.pencil.and.ellipsis") }
                .tag(Workspace.canvas)
                
                NavigationStack {
                    SimulationDetailView()
                }
                .tabItem { Label("Simulation", systemImage: "play.desktopcomputer") }
                .tag(Workspace.simulation)
            }
        } else {
            // iPad Universal Layout (3-Column)
            NavigationSplitView {
                // Sidebar: Workspace selector
                List(selection: $selectedWorkspace) {
                    Label("Dashboard", systemImage: "chart.bar")
                        .tag(Workspace.dashboard)
                    Label("Ingestion Vault", systemImage: "doc.text.magnifyingglass")
                        .tag(Workspace.ingestion)
                    Label("Agentic Canvas", systemImage: "paintbrush.pointed")
                        .tag(Workspace.canvas)
                    Label("Simulation", systemImage: "person.3")
                        .tag(Workspace.simulation)
                }
                .navigationTitle("Workspaces")
            } content: {
                // Content: list for selected workspace
                switch selectedWorkspace {
                case .ingestion: DocumentListView()
                case .canvas: ModuleOutlineView()
                // ...
                }
            } detail: {
                // Detail: active item for selected workspace
                switch selectedWorkspace {
                case .ingestion: NodeGraphView() // Includes graph + grounding RAG
                case .canvas: AgentCanvasView() // Includes debate UI
                // ...
                }
            }
        }
    }
}
```

---

## Design System Tokens

### Color Palette

```swift
extension Color {
    // Brand
    static let brand = Color(hex: "#6366F1")          // Indigo
    static let brandLight = Color(hex: "#818CF8")
    static let brandDark = Color(hex: "#4F46E5")

    // Semantic
    static let success = Color(hex: "#10B981")         // Green
    static let warning = Color(hex: "#F59E0B")         // Amber
    static let error = Color(hex: "#EF4444")           // Red
    static let info = Color(hex: "#3B82F6")            // Blue

    // Heatmap
    static let heatmapGreen = Color(hex: "#4CAF50")
    static let heatmapYellow = Color(hex: "#FFC107")
    static let heatmapOrange = Color(hex: "#FF9800")
    static let heatmapRed = Color(hex: "#F44336")

    // Agent Roles
    static let agentPlanning = Color(hex: "#8B5CF6")   // Purple
    static let agentContent = Color(hex: "#3B82F6")    // Blue
    static let agentAssessment = Color(hex: "#10B981")  // Green
    static let agentCritique = Color(hex: "#F59E0B")   // Amber

    // Bloom's Levels
    static let bloomRemember = Color(hex: "#94A3B8")
    static let bloomUnderstand = Color(hex: "#60A5FA")
    static let bloomApply = Color(hex: "#34D399")
    static let bloomAnalyze = Color(hex: "#FBBF24")
    static let bloomEvaluate = Color(hex: "#F97316")
    static let bloomCreate = Color(hex: "#EF4444")

    // Surfaces (adapt to dark/light mode)
    static let surfacePrimary = Color(.systemBackground)
    static let surfaceSecondary = Color(.secondarySystemBackground)
    static let surfaceTertiary = Color(.tertiarySystemBackground)
}
```

### Typography

```swift
extension Font {
    // Headers
    static let displayLarge = Font.system(size: 34, weight: .bold, design: .rounded)
    static let displayMedium = Font.system(size: 28, weight: .bold, design: .rounded)
    static let titleLarge = Font.system(size: 22, weight: .semibold)
    static let titleMedium = Font.system(size: 17, weight: .semibold)

    // Body
    static let bodyLarge = Font.system(size: 17)
    static let bodyMedium = Font.system(size: 15)
    static let bodySmall = Font.system(size: 13)

    // Monospace (for code, agent output)
    static let codeLarge = Font.system(size: 15, design: .monospaced)
    static let codeSmall = Font.system(size: 13, design: .monospaced)

    // Agent labels
    static let agentLabel = Font.system(size: 12, weight: .bold, design: .rounded)
}
```

### Spacing Scale

```swift
enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
}
```

---

## Component Patterns

### Agent Message Bubble

```swift
struct AgentMessageView: View {
    let message: AgentMessage

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            // Agent avatar
            Circle()
                .fill(agentColor)
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: agentIcon)
                        .font(.caption)
                        .foregroundStyle(.white)
                )

            VStack(alignment: .leading, spacing: Spacing.xs) {
                // Agent name + timestamp
                HStack {
                    Text(message.agentRole.displayName)
                        .font(.agentLabel)
                        .foregroundStyle(agentColor)
                    Spacer()
                    Text(message.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                // Message content
                Text(message.content)
                    .font(.bodyMedium)
                    .textSelection(.enabled)
            }
        }
        .padding(Spacing.md)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
```

### HITL Approval Card

```swift
struct HITLApprovalCard: View {
    let checkpoint: HITLCheckpoint
    let onApprove: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Header with warning icon
            Label("Approval Required", systemImage: "hand.raised.fill")
                .font(.titleMedium)
                .foregroundStyle(.warning)

            // Content preview
            Text(checkpoint.description)
                .font(.bodyMedium)

            // Action buttons
            HStack(spacing: Spacing.md) {
                Button("Reject", role: .destructive) { onReject() }
                    .buttonStyle(.bordered)

                Button("Approve") { onApprove() }
                    .buttonStyle(.borderedProminent)
                    .tint(.success)
            }
        }
        .padding(Spacing.lg)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 8)
    }
}
```

---

## Liquid Glass Design (2026)

### Principles

- **Floating controls**: Buttons and toolbars rendered in glass material, floating above content
- **Depth and layers**: Influence from visionOS — think in layers even on flat screens
- **Translucent sidebar**: Use `.ultraThinMaterial` or `.regularMaterial` for sidebar backgrounds
- **Inset tab bar**: Navigation uses inset capsule style (not traditional tab bar)

### Implementation

```swift
// Translucent sidebar
List { ... }
    .scrollContentBackground(.hidden)
    .background(.ultraThinMaterial)

// Floating toolbar
.toolbar {
    ToolbarItem(placement: .bottomBar) {
        HStack {
            Button { } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(.thinMaterial)
            .clipShape(Capsule())
        }
    }
}
```

---

## Performance Guidelines

| Pattern | Rule |
|:---|:---|
| **Lists** | Always use `LazyVStack` / `LazyVGrid` for scrollable content |
| **State** | Use `@State` for view-local, `@Observable` for shared state |
| **Images** | Use `AsyncImage` with caching for any remote images |
| **Canvas** | Use SwiftUI `Canvas` for node graphs and heatmaps (immediate-mode) |
| **Animations** | Prefer `withAnimation(.spring)` — avoid `.linear` (feels robotic) |
| **Throttling** | Throttle WebSocket UI updates to max 10 Hz (100ms debounce) |
| **Previews** | Every view MUST have at least one preview with sample data |

---

## Accessibility

| Feature | Implementation |
|:---|:---|
| **Dynamic Type** | All text uses semantic Font tokens (never hardcoded sizes) |
| **VoiceOver** | Every interactive element has `.accessibilityLabel` |
| **Color Contrast** | All semantic colors pass WCAG AA contrast ratio |
| **Reduce Motion** | Check `@Environment(\.accessibilityReduceMotion)` |
| **Dark Mode** | All colors use adaptive system colors or Asset Catalog colors |

---

## Key Apple HIG References

| Topic | URL |
|:---|:---|
| **Human Interface Guidelines** | https://developer.apple.com/design/human-interface-guidelines/ |
| **iPadOS Navigation** | https://developer.apple.com/design/human-interface-guidelines/patterns/navigation |
| **Liquid Glass** | https://developer.apple.com/design/human-interface-guidelines/materials |
| **NavigationSplitView** | https://developer.apple.com/documentation/swiftui/navigationsplitview |
| **Canvas** | https://developer.apple.com/documentation/swiftui/canvas |
| **SF Symbols** | https://developer.apple.com/sf-symbols/ |
