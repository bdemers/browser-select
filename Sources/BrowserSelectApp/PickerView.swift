import SwiftUI

/// The browser picker UI: a horizontal grid of installed browsers with icon + name.
///
/// Interaction:
/// - Click a browser to open the pending URL in it.
/// - Left/Right arrows move the keyboard highlight; Return opens the highlighted one.
/// - Escape cancels and hides the picker.
struct PickerView: View {
    @ObservedObject var model: PickerModel

    private let cell: CGFloat = 88
    private let iconSize: CGFloat = 48
    private let gridSpacing: CGFloat = 10
    private let contentPadding: CGFloat = 20
    private let maxColumns = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let url = model.pendingURL {
                // URL header. Left-aligned with the grid; the window sizes to fit so the
                // top/left/right margins are symmetric (no title-bar safe-area gap — see
                // `.ignoresSafeArea()` below).
                Text(url.absoluteString)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if model.browsers.isEmpty {
                Text("No browsers found")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: cell)
            } else {
                LazyVGrid(columns: columns, spacing: gridSpacing) {
                    ForEach(Array(model.browsers.enumerated()), id: \.element.id) { index, browser in
                        cellView(browser, isSelected: index == model.selectedIndex)
                            .onTapGesture { model.open(browser) }
                    }
                }
            }
        }
        .padding(contentPadding)
        .frame(width: contentWidth)
        // Rounded card drawn by us: the host window is borderless and transparent, so this
        // background defines the visible shape (the window's shadow follows it). Fills the
        // whole frame, keeping all four margins symmetric.
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .background(KeyHandling(model: model))
    }

    /// Columns shown: as many as there are browsers, capped at `maxColumns`. Drives both the
    /// grid and `contentWidth` so the window is sized exactly to the laid-out content.
    private var columnCount: Int {
        min(max(model.browsers.count, 1), maxColumns)
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.fixed(cell), spacing: gridSpacing), count: columnCount)
    }

    private var contentWidth: CGFloat {
        CGFloat(columnCount) * cell
            + CGFloat(columnCount - 1) * gridSpacing
            + contentPadding * 2
    }

    private func cellView(_ browser: DisplayBrowser, isSelected: Bool) -> some View {
        VStack(spacing: 6) {
            Image(nsImage: browser.icon)
                .resizable()
                .frame(width: iconSize, height: iconSize)
            Text(browser.name)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(width: cell, height: cell)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Color.accentColor.opacity(0.25) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .contentShape(Rectangle())
    }
}

/// Bridges hardware keyboard events into the SwiftUI picker. SwiftUI's `.keyboardShortcut`
/// is awkward for raw arrow navigation in an accessory window, so we drop down to an
/// `NSView` that becomes first responder and forwards key codes to the model.
private struct KeyHandling: NSViewRepresentable {
    let model: PickerModel

    func makeNSView(context: Context) -> NSView {
        let view = KeyCatcherView()
        view.model = model
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? KeyCatcherView)?.model = model
        DispatchQueue.main.async { nsView.window?.makeFirstResponder(nsView) }
    }

    final class KeyCatcherView: NSView {
        var model: PickerModel?
        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            guard let model else { return super.keyDown(with: event); }
            let count = model.browsers.count
            switch event.keyCode {
            case 53: // Escape
                model.cancel()
            case 36, 76: // Return / keypad Enter
                if count > 0, model.selectedIndex < count {
                    model.open(model.browsers[model.selectedIndex])
                }
            case 123, 126: // Left / Up
                if count > 0 { model.selectedIndex = (model.selectedIndex - 1 + count) % count }
            case 124, 125: // Right / Down
                if count > 0 { model.selectedIndex = (model.selectedIndex + 1) % count }
            default:
                super.keyDown(with: event)
            }
        }
    }
}
