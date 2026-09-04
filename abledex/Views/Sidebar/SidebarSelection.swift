//
//  SidebarSelection.swift
//  abledex
//

import Foundation

/// What the sidebar is currently pointed at.
///
/// Only navigation lives here. The status/tag/plugin rows below are scoping
/// filters that narrow whichever destination is open, so they highlight
/// themselves rather than taking the source list's selection.
enum SidebarSelection: Hashable {
    case filter(ProjectFilter)
    case collection(UUID)
}
