import SwiftUI

@main
struct MedicineScannerApp: App {
    init() {
        #if targetEnvironment(simulator)
        Self.insertDemoData()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            #if targetEnvironment(simulator)
            DemoScreenRouter()
            #else
            ScannerView()
            #endif
        }
    }

    #if targetEnvironment(simulator)
    struct DemoScreenRouter: View {
        let demoScreen: Int = {
            let args = ProcessInfo.processInfo.arguments
            if let idx = args.firstIndex(of: "-demoScreen"),
               idx + 1 < args.count,
               let val = Int(args[idx + 1]) { return val }
            return 0
        }()

        var body: some View {
            switch demoScreen {
            case 1:
                NavigationStack { HistoryView() }
            case 2:
                NavigationStack {
                    ConfirmationView(
                        photo: MedicineScannerApp.createDemoScaleImage(),
                        medicineName: "プランルカストDS10%",
                        barcodePhoto: MedicineScannerApp.createDemoBarcodeImage(),
                        barcode: "4987107610362",
                        weight: .constant("12.5"),
                        batchCount: 2,
                        onAddToList: {},
                        onRetake: {}
                    ) {}
                }
            case 3:
                NavigationStack { MedicineListView(store: StoreManager.shared) }
            case 4:
                NavigationStack {
                    BatchConfirmationView(viewModel: MedicineScannerApp.createDemoBatchVM())
                }
            case 5:
                // Home screen (camera off)
                ScannerView(forceHome: true)
            default:
                ScannerView()
            }
        }
    }

    static func createDemoScaleImage() -> UIImage {
        let size = CGSize(width: 600, height: 450)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let c = ctx.cgContext
            UIColor(white: 0.22, alpha: 1).setFill()
            c.fill(CGRect(origin: .zero, size: size))
            let scaleRect = CGRect(x: 40, y: 120, width: size.width - 80, height: 200)
            UIColor(white: 0.78, alpha: 1).setFill()
            UIBezierPath(roundedRect: scaleRect, cornerRadius: 14).fill()
            let panRect = CGRect(x: 80, y: 30, width: size.width - 160, height: 130)
            UIColor(white: 0.72, alpha: 1).setFill()
            UIBezierPath(ovalIn: panRect).fill()
            UIColor(white: 0.95, alpha: 0.9).setFill()
            UIBezierPath(ovalIn: CGRect(x: 220, y: 70, width: 120, height: 50)).fill()
            let lcdRect = CGRect(x: 120, y: 180, width: 360, height: 70)
            UIColor(red: 0.82, green: 0.90, blue: 0.82, alpha: 1).setFill()
            UIBezierPath(roundedRect: lcdRect, cornerRadius: 6).fill()
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 44, weight: .bold),
                .foregroundColor: UIColor(red: 0.08, green: 0.18, blue: 0.08, alpha: 1)
            ]
            let txt = "12.53g"
            let sz = (txt as NSString).size(withAttributes: attrs)
            (txt as NSString).draw(at: CGPoint(x: lcdRect.midX - sz.width/2, y: lcdRect.midY - sz.height/2), withAttributes: attrs)
            UIColor(white: 0.25, alpha: 1).setFill()
            c.fill(CGRect(x: 0, y: 330, width: size.width, height: 120))
        }
    }

    static func insertDemoData() {
        let medicines: [(String, String)] = [
            ("4987107610362", "プランルカストDS10%"),
            ("4987123145893", "ムコダインDS50%"),
            ("4987306048478", "カロナール細粒20%"),
            ("4987246601092", "アスベリン散10%"),
        ]
        for (barcode, name) in medicines {
            MedicineService.register(barcode: barcode, name: name)
        }
        let demoBarcode = createDemoBarcodeImage()
        let demoPhotos: [(String, String, String, UIImage)] = [
            ("4987107610362", "プランルカストDS10%", "12.5", createDemoImg(text: "12.5g", color: .systemBlue)),
            ("4987123145893", "ムコダインDS50%", "8.3", createDemoImg(text: "8.3g", color: .systemGreen)),
            ("4987306048478", "カロナール細粒20%", "15.0", createDemoImg(text: "15.0g", color: .systemOrange)),
        ]
        for (barcode, name, weight, photo) in demoPhotos {
            HistoryStore.save(barcode: barcode, medicineName: name, weight: weight, photo: photo, barcodePhoto: demoBarcode)
        }
    }

    static func createDemoBarcodeImage() -> UIImage {
        let size = CGSize(width: 300, height: 100)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            // Draw simple barcode lines
            UIColor.black.setFill()
            var x: CGFloat = 20
            for _ in 0..<30 {
                let w = CGFloat.random(in: 1...3)
                ctx.fill(CGRect(x: x, y: 10, width: w, height: 60))
                x += w + CGFloat.random(in: 1...3)
            }
            // Draw barcode number
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 14, weight: .regular),
                .foregroundColor: UIColor.black
            ]
            let text = "4987107610362"
            let sz = (text as NSString).size(withAttributes: attrs)
            (text as NSString).draw(at: CGPoint(x: (size.width - sz.width) / 2, y: 75), withAttributes: attrs)
        }
    }

    @MainActor
    static func createDemoBatchVM() -> ScannerViewModel {
        let vm = ScannerViewModel()
        vm.scannedItems = [
            ScannedItem(barcode: "4987107610362", medicineName: "プランルカストDS10%", weight: "12.5",
                        photo: createDemoImg(text: "12.5g", color: .systemBlue),
                        barcodePhoto: createDemoBarcodeImage()),
            ScannedItem(barcode: "4987123145893", medicineName: "ムコダインDS50%", weight: "8.3",
                        photo: createDemoImg(text: "8.3g", color: .systemGreen),
                        barcodePhoto: createDemoBarcodeImage()),
            ScannedItem(barcode: "4987306048478", medicineName: "カロナール細粒20%", weight: "15.0",
                        photo: createDemoImg(text: "15.0g", color: .systemOrange),
                        barcodePhoto: nil),
        ]
        return vm
    }

    static func createDemoImg(text: String, color: UIColor) -> UIImage {
        let size = CGSize(width: 400, height: 300)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let colors = [color.withAlphaComponent(0.3).cgColor, color.withAlphaComponent(0.1).cgColor]
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1])!
            ctx.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.monospacedDigitSystemFont(ofSize: 48, weight: .bold), .foregroundColor: UIColor.darkGray]
            let sz = (text as NSString).size(withAttributes: attrs)
            (text as NSString).draw(at: CGPoint(x: (size.width - sz.width)/2, y: 140), withAttributes: attrs)
        }
    }
    #endif
}
