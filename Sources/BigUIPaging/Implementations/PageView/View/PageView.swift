import SwiftUI

/// A container view that manages navigation between related views.
///
/// Pages can be navigated programmatically by updating the selection binding to a specified value
/// or directly by the user with a gesture or action.
///
/// ## Creating a PageView
///
/// There are two ways to initialise a PageView. The simplest is with a ForEach data source:
///
/// ```swift
/// @State private var selection: Int = 1
///
/// var body: some View {
///     PageView(selection: $selection) {
///         ForEach(1...10, id: \.self) { id in
///             Text("Page \(value)")
///         }
///     }
///     .pageViewStyle(.scroll)
/// }
/// ```
/// Alternatively you can you can use the next and previous closure to return a value relative to another value:
///
/// ```swift
/// @State private var selection: Int = 1
///
/// var body: some View {
///     PageView(selection: $selection) { value in
///         value + 1
///     } previous: { value in
///         value > 1 ? value - 1 : nil
///     } content: { value in
///         Text("Page \(value)")
///     }
/// }
/// ```
///
/// ## Transitions and Styles
///
/// The exact navigation gesture or transition depends on the chosen style. The default
/// style is ``PlainPageViewStyle`` that has no transitions or gestures.
///
/// You set a style by using the ``SwiftUI/View/pageViewStyle(_:)`` modifier:
///
/// ```swift
/// PageView(selection: $selection) {
///     ...
/// }
/// .pageViewStyle(.bookStack)
///   ```
///
/// You can create your own custom transitions and interactions by adopting ``PageViewStyle``.
///
public struct PageView<SelectionValue, Page>: View where SelectionValue: Hashable, Page: View {
    
    @Binding var selection: SelectionValue
    let next: (SelectionValue) -> SelectionValue?
    let previous: (SelectionValue) -> SelectionValue?
    @ViewBuilder let pageContent: (SelectionValue) -> Page
    @State private var id = UUID()
    
    /// Creates a new page view that computes its pages using closures to determine the next and previous
    /// page value.
    /// - Parameters:
    ///   - selection: A binding to a selected value.
    ///   - next: A closure that returns the next value from the provided value.
    ///   - previous: A closure that returns the previous value from the provided value.
    ///   - content: A view builder that returns the page content for a given value.
    public init(
        selection: Binding<SelectionValue>,
        next: @escaping (SelectionValue) -> SelectionValue?,
        previous: @escaping (SelectionValue) -> SelectionValue?,
        @ViewBuilder content: @escaping (SelectionValue) -> Page
    ) {
        self._selection = selection
        self.next = next
        self.previous = previous
        self.pageContent = content
    }
    
    @Environment(\.pageViewStyle) private var style
    
    public var body: some View {
        AnyView(style.makeConcreteView(configuration))
            .environment(\.navigatePageView, configuration.navigateAction(id))
            .preference(
                key: PageViewCanNavigatePreference.self,
                value: configuration.canNavigate
            )
            .preference(
                key: PageViewNavigateActionPreference.self,
                value: configuration.navigateAction(id)
            )
    }
    
}

// MARK: - Convenience initialisers

extension PageView {

    /// Creates a new page view that computes its pages on demand from an underlying collection of
    /// hashable data.
    /// - Parameters:
    ///   - selection: A binding to a selected value.
    ///   - content: A `ForEach` containing some hashable data.
    public init<Data>(
        selection: Binding<SelectionValue>,
        content: () -> ForEach<Data, Data.Element, Page>
    ) where Data : RandomAccessCollection, SelectionValue == Data.Element {
        let content = content()
        let data = content.data
        let page = content.content
        self.init(selection: selection) { value in
            guard let index = data.firstIndex(of: value) else {
                return nil
            }
            guard index != data.endIndex else {
                return nil
            }
            let next = data.index(after: index)
            guard data.indices.contains(next) else {
                return nil
            }
            return data[next]
        } previous: { value in
            guard let index = data.firstIndex(of: value) else {
                return nil
            }
            guard index != data.startIndex else {
                return nil
            }
            let previous = data.index(before: index)
            guard data.indices.contains(previous) else {
                return nil
            }
            return data[previous]
        } content: { value in
            page(value)
        }
    }
    
    /// Creates a new page view that computes its pages on demand from an underlying collection of
    /// identifiable data.
    /// - Parameters:
    ///   - selection: A binding to a selected value.
    ///   - content: A `ForEach` containing some identifiable data.
    public init<Data>(
        selection: Binding<SelectionValue>,
        content: () -> ForEach<Data, Data.Element.ID, Page>
    ) where Data : RandomAccessCollection, Data.Element : Identifiable, SelectionValue == Data.Element.ID {
        let content = content()
        let data = content.data
        let page = content.content
        self.init(selection: selection) { id in
            guard let index = data.firstIndex(where: { $0.id == id }) else {
                return nil
            }
            let next = data.index(after: index)
            guard data.indices.contains(next) else {
                return nil
            }
            return data[next].id
        } previous: { id in
            guard let index = data.firstIndex(where: { $0.id == id }) else {
                return nil
            }
            let prev = data.index(before: index)
            guard data.indices.contains(prev) else {
                return nil
            }
            return data[prev].id
        } content: { id in
            let value = data.first(where: { $0.id == id }) ?? data[data.startIndex]
            page(value)
        }
    }
}

// MARK: - Style Handling

extension PageView {
    
    var configuration: PageViewStyleConfiguration {
        .init(selection: configurationSelection) { value in
            // Only we can populate this value, so force unwrapping is fine
            if let next = next(value.wrappedValue as! SelectionValue) {
                return .init(next)
            } else {
                return nil
            }
        } previous: { value in
            if let previous = previous(value.wrappedValue as! SelectionValue) {
                return .init(previous)
            } else {
                return nil
            }
        } content: { value in
            return .init(pageContent(value.wrappedValue as! SelectionValue))
        }
    }
    
    var configurationSelection: Binding<PageViewStyleConfiguration.Value> {
        .init {
            .init(selection)
        } set: { newValue in
            self.selection = newValue.wrappedValue as! SelectionValue
        }
    }
}

struct ConcretePageViewStyle<Style>: View where Style: PageViewStyle {
    
    let configuration: PageViewStyleConfiguration
    let style: Style
    
    var body: some View {
        style.makeBody(configuration: configuration)
    }
}

extension PageViewStyle {
    
    func makeConcreteView(_ configuration: Configuration) -> some View {
        ConcretePageViewStyle(configuration: configuration, style: self)
    }
}

// MARK: - Navigation

extension PageViewStyleConfiguration {
    
    func navigateAction(_ id: UUID) -> PageViewNavigateAction {
        .init(id: id) { direction in
            switch direction {
            case .forwards:
                if let next = next(selection.wrappedValue) {
                    self.selection.wrappedValue = next
                }
            case .backwards:
                if let previous = previous(selection.wrappedValue) {
                    self.selection.wrappedValue = previous
                }
            default:
                break 
            }
        }
    }
    
    var canNavigate: PageViewDirection {
        var directions = PageViewDirection()
        if next(selection.wrappedValue) != nil {
            directions.insert(.forwards)
        }
        if previous(selection.wrappedValue) != nil {
            directions.insert(.backwards)
        }
        return directions
    }
}

struct PageView_Previews: PreviewProvider {
    
    static var previews: some View {
        PageViewExamples()
    }
}
