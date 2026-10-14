# Project Rules & Style Guidelines

## Style Guide (Default Xcode & macOS System Standards)

Project ini mengikuti panduan gaya dan konvensi standar default dari Xcode dan macOS:

### 1. Formatting & Indentation
- Gunakan indentasi **4 spasi** (Xcode default).
- Baris kosong yang rapi untuk memisahkan fungsi, properti, dan ekstensi.
- Hindari trailing whitespace.

### 2. Naming Conventions
- **Types, Protocols, Structs, Classes, Enums**: `PascalCase` (contoh: `ContentView`, `Item`, `UserSession`).
- **Properties, Functions, Variables, Enum Cases**: `camelCase` (contoh: `fetchData()`, `userProfile`, `isLoading`).

### 3. UI, Typography & System Styling (macOS Native)
- **Gunakan font sesuai dengan ukuran dan tipe bawaan dari Mac**:
  - Gunakan typography text styles bawaan macOS / SwiftUI Dynamic Type (seperti `.largeTitle`, `.title`, `.title2`, `.title3`, `.headline`, `.body`, `.callout`, `.subheadline`, `.footnote`, `.caption`).
  - Gunakan font sistem bawaan San Francisco / SF Pro (`Font.system(...)` atau standar SwiftUI styles) dan SF Mono (`.monospaced()`) untuk terminal, logs, host/port, atau path teknis.
  - Hindari penggunaan custom hardcoded font size atau font eksternal non-standar, pastikan selalu selaras dengan panduan macOS Human Interface Guidelines (HIG).

### 4. Toolbar & Controls Standard (Native macOS / ForkLift Style)
- **Gunakan Toolbar & Komponen Kontrol Native Xcode/macOS**:
  - Gunakan `ToolbarItem` dan `ToolbarItemGroup` native dengan penempatan standard (`.navigation`, `.principal`, `.primaryAction`).
  - Untuk kelompok tombol view mode gunakan segmented picker native (`.pickerStyle(.segmented)`).
  - Gunakan modifier `.searchable(text: ..., placement: .toolbar, prompt: "Search")` native macOS untuk kolom pencarian toolbar.
  - **Dilarang mengubah struktur desain toolbar dan sidebar yang sudah disetujui (Locked/Frozen)**.

### 5. SwiftUI & State Management
- Gunakan `@State private var` untuk state lokal di dalam SwiftUI View.
- Gunakan `let` untuk properti konstan yang tidak bermutasi.
- Terapkan pemisahan view dan logic secara modular (deklaratif di properti `body`).

### 6. Swift Best Practices & Safety
- Manfaatkan sistem tipe data Swift yang kuat (Strong Type Safety).
- Hindari force unwrapping (`!`), gunakan `if let`, `guard let`, atau nil-coalescing (`??`).
- Gunakan concurrency modern Swift (`async`/`await`, `Task`, `@MainActor`) dibandingkan completion handler atau Combine framework (kecuali dibutuhkan).
- Import yang ringkas di bagian atas file (misal: `import SwiftUI`, `import Foundation`).

### 7. Testing
- Gunakan **Swift Testing framework** (`import Testing`, `@Test`, `#expect`) untuk unit test.
- Gunakan **XCUIAutomation** framework untuk UI tests.
