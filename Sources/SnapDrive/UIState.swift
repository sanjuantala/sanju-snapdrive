import SwiftUI

// Explicit wrapper alias also works with SDKs that expose the newer State macro.
typealias ViewState<Value> = SwiftUI.State<Value>
