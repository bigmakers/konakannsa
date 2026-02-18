import UIKit

/// Abstraction layer for direct receipt printer communication.
/// Currently supports Citizen CT-S251 via AirPrint fallback.
/// When CitizenConnect SDK is integrated, replace the AirPrint path
/// with direct Bluetooth/Wi-Fi printing.
///
/// ## Integration Steps for CitizenConnect SDK:
/// 1. Download SDK from Citizen developer portal
/// 2. Add CJPOSLibSwift.xcframework to the project
/// 3. Add `import CJPOSLibSwift` below
/// 4. Uncomment the Citizen-specific code paths
enum ReceiptPrinterService {

    // MARK: - Printer Type

    enum PrinterType: String {
        case airprint   // Standard AirPrint (any printer)
        case citizenBLE // Citizen CT-S251 via Bluetooth LE
        case citizenWiFi // Citizen CT-S251 via Wi-Fi
    }

    // MARK: - Print Journal

    /// Prints a journal image to the configured printer.
    /// Falls back to AirPrint if no direct printer SDK is available.
    static func printJournal(
        image: UIImage,
        printerType: PrinterType = .airprint,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        switch printerType {
        case .airprint:
            printViaAirPrint(image: image, jobName: "秤量ジャーナル", completion: completion)

        case .citizenBLE, .citizenWiFi:
            // TODO: Replace with CitizenConnect SDK calls when integrated
            //
            // Example CitizenConnect integration:
            // ```
            // import CJPOSLibSwift
            //
            // let printer = CJPOSPrinter()
            // printer.connect(printerType == .citizenBLE ? .bluetooth : .wifi)
            // printer.setEncoding(.shiftJIS)
            // printer.printBitmap(image, width: 384) // 58mm = 384 dots at 203dpi
            // printer.cutPaper(.partialCut)
            // printer.disconnect()
            // ```
            //
            // For now, fall back to AirPrint
            printViaAirPrint(image: image, jobName: "秤量ジャーナル", completion: completion)
        }
    }

    // MARK: - Print Photo Layout

    /// Prints a photo composite layout.
    static func printComposite(
        image: UIImage,
        jobName: String = "お薬一覧",
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        printViaAirPrint(image: image, jobName: jobName, completion: completion)
    }

    // MARK: - AirPrint

    private static func printViaAirPrint(
        image: UIImage,
        jobName: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let printController = UIPrintInteractionController.shared
        let printInfo = UIPrintInfo.printInfo()
        printInfo.outputType = .general
        printInfo.jobName = jobName

        printController.printInfo = printInfo
        printController.printingItem = image

        printController.present(animated: true) { _, completed, error in
            if let error {
                completion(.failure(error))
            } else if completed {
                completion(.success(()))
            } else {
                // User cancelled
                completion(.failure(PrintError.cancelled))
            }
        }
    }

    // MARK: - Errors

    enum PrintError: LocalizedError {
        case cancelled
        case printerNotFound
        case connectionFailed

        var errorDescription: String? {
            switch self {
            case .cancelled: return "印刷がキャンセルされました。"
            case .printerNotFound: return "プリンタが見つかりません。"
            case .connectionFailed: return "プリンタへの接続に失敗しました。"
            }
        }
    }
}
