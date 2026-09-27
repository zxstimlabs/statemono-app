import SwiftUI

/// Telegram's in-chat search panel, shown under the header.
struct SearchBar: View {
    @Bindable var search: ChatSearch
    var dateRange: ClosedRange<Date>
    var onJumpToDate: (Date) -> Void
    var onClose: () -> Void

    @FocusState private var isFocused: Bool
    @State private var showsCalendar = false
    @State private var calendarDate = Date.now

    var body: some View {
        VStack(alignment: .leading, spacing: 6.5) {
            HStack(spacing: 6) {
                field
                HStack(spacing: 0) {
                    iconButton("chevron.up", size: 16, enabled: search.canShowOlder) { search.showOlder() }
                    iconButton("chevron.down", size: 16, enabled: search.canShowNewer) { search.showNewer() }
                    iconButton("calendar", size: 16) {
                        calendarDate = min(max(.now, dateRange.lowerBound), dateRange.upperBound)
                        showsCalendar = true
                    }
                    .popover(isPresented: $showsCalendar, arrowEdge: .bottom) {
                        DatePicker("", selection: $calendarDate, in: dateRange, displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .labelsHidden()
                            .padding(12)
                            .onChange(of: calendarDate) { _, date in
                                showsCalendar = false
                                onJumpToDate(date)
                            }
                    }
                    iconButton("xmark", size: 14, action: onClose)
                }
            }
            TagChip(title: "Unlock", systemImage: "lock.fill") {}
        }
        .padding(EdgeInsets(top: 4.5, leading: 3.5, bottom: 6, trailing: 4))
        .chromeBackground(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onAppear { isFocused = true }
    }

    private var field: some View {
        HStack(spacing: 11.5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondaryText)
            TextField("", text: $search.query, prompt: Text("Search").foregroundStyle(Theme.secondaryText))
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .focused($isFocused)
                .onSubmit { search.showOlder() }
            Button {
                search.query = ""
                isFocused = true
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 13)
        .padding(.trailing, 8)
        .frame(height: 27.5)
        .background(Theme.searchFieldFill, in: Capsule())
    }

    private func iconButton(_ systemImage: String, size: CGFloat, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        ChromeIconButton(systemImage: systemImage, size: size, action: action)
            .frame(width: 32, height: 27.5)
            .disabled(!enabled)
            .opacity(enabled ? 1 : 0.35)
    }
}

/// A Telegram saved-message tag: rounded on the left, a soft arrow point on the right.
struct TagChip: View {
    let title: LocalizedStringKey
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11.5) {
                Image(systemName: systemImage)
                    .font(.system(size: 12))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(Theme.tag)
            .padding(.leading, 10)
            .padding(.trailing, 13.5)
            .frame(height: 23.5)
            .background(TagShape().fill(Theme.tag.opacity(0.18)))
            .contentShape(TagShape())
        }
        .buttonStyle(.plain)
    }
}

struct TagShape: Shape {
    func path(in rect: CGRect) -> Path {
        let r: CGFloat = 4.5
        let (left, top, right, bottom, mid) = (rect.minX, rect.minY, rect.maxX, rect.maxY, rect.midY)
        var path = Path()
        path.move(to: CGPoint(x: left + r, y: top))
        path.addLine(to: CGPoint(x: right - 9.5, y: top))
        path.addQuadCurve(to: CGPoint(x: right, y: mid), control: CGPoint(x: right - 5, y: top + 3))
        path.addQuadCurve(to: CGPoint(x: right - 9.5, y: bottom), control: CGPoint(x: right - 5, y: bottom - 3))
        path.addLine(to: CGPoint(x: left + r, y: bottom))
        path.addArc(tangent1End: CGPoint(x: left, y: bottom), tangent2End: CGPoint(x: left, y: bottom - r), radius: r)
        path.addLine(to: CGPoint(x: left, y: top + r))
        path.addArc(tangent1End: CGPoint(x: left, y: top), tangent2End: CGPoint(x: left + r, y: top), radius: r)
        path.closeSubpath()
        return path
    }
}
