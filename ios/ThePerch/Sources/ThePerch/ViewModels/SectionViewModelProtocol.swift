import Foundation

/// Common protocol for section-level ViewModels that manage a list of records.
/// DashboardViewModel is intentionally excluded — it manages sections, not records.
@MainActor
protocol SectionViewModelProtocol: AnyObject {
    var isLoading: Bool { get }
    var error: SupabaseServiceError? { get }
    var records: [Record] { get }
    func loadRecords(forceRefresh: Bool) async
    func refresh() async
}
