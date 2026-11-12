// Macros whose implementation exists only in the newer, Apple-silicon-only Xcode.
// Compiled only with run.sh --missing, which is expected to fail with
// "plugin ... not found" / "could not be found in library plugin".
#if MACROCHECK_MISSING
import FoundationModels
import StateReporting

@available(macOS 27, iOS 27, *)
@ReportableMetadata
struct DownloadStatus {
    var name: String
}

@available(macOS 27, iOS 27, *)
struct SessionSettings {
    @SessionPropertyEntry var temperature: Double = 0.5
}
#endif
