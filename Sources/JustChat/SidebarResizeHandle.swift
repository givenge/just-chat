import AppKit
import SwiftUI

struct SidebarResizeHandle: View {
  @Binding var width: Double
  var onEnded: () -> Void
  @State private var startWidth: Double?
  @State private var isHovering = false

  var body: some View {
    Color.justSidebarBackground
      .frame(width: 8)
      .overlay(alignment: .trailing) {
        Rectangle()
          .fill(Color.justBorderSoft.opacity(0.65))
          .frame(width: 1)
      }
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { value in
            if startWidth == nil {
              startWidth = width
            }
            let base = startWidth ?? width
            width = min(max(base + value.translation.width, 240), 460)
          }
          .onEnded { _ in
            startWidth = nil
            onEnded()
          }
      )
      .onHover { hovering in
        if hovering, !isHovering {
          NSCursor.resizeLeftRight.push()
          isHovering = true
        } else if !hovering, isHovering {
          NSCursor.pop()
          isHovering = false
        }
      }
      .onDisappear {
        if isHovering {
          NSCursor.pop()
          isHovering = false
        }
      }
  }
}
