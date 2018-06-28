import Foundation
import UIKit

let FBSnapshotTestControllerErrorDomain = "FBSnapshotTestControllerErrorDomain"
let FBReferenceImageFilePathKey = "FBReferenceImageFilePathKey"
let FBReferenceImageKey = "FBReferenceImageKey"
let FBCapturedImageKey = "FBCapturedImageKey"
let FBDiffedImageKey = "FBDiffedImageKey"

enum FBTestSnapshotFileNameType: Int {
    case reference
    case failedReference
    case failedTest
    case failedTestDiff
}

enum FBSnapshotTestControllerErrorCode: Int {
    case unknown
    case needsRecord
    case pngCreationFailed
    case imagesDifferentSizes
    case imagesDifferent
}

/**
 Provides the heavy-lifting for FBSnapshotTestCase. It loads and saves images, along with performing the actual pixel-
 by-pixel comparison of images.
 Instances are initialized with the test class, and directories to read and write to.
 */
class FBSnapshotTestController: NSObject {
    /**
     Record snapshots.
     */

    var recordMode = false
    /**
     When @c YES appends the name of the device model and OS to the snapshot file name.
     The default value is @c NO.
     */
    var deviceAgnostic = false
    /**
     When set, allows fine-grained control over how agnostic you want the file names to be.
     Allows you to combine which agnostic options you want in your snapshot file names.
     The default value is FBSnapshotTestCaseAgnosticOptionNone.

     @attention If deviceAgnostic is YES, this bitmask is ignored. deviceAgnostic will be deprecated in a future version of FBSnapshotTestCase.
     */
    var agnosticOptions: FBSnapshotTestCaseAgnosticOption?
    /**
     Uses drawViewHierarchyInRect:afterScreenUpdates: to draw the image instead of renderInContext:
     */
    var usesDrawViewHierarchyInRect = false
    /**
     The directory in which referfence images are stored.
     */
    var referenceImagesDirectory = ""

    private var testName = ""
    private var fileManager: FileManager?

    // MARK: - Initializers

    /**
     @param testClass The subclass of FBSnapshotTestCase that is using this controller.
     @returns An instance of FBSnapshotTestController.
     */
    convenience init(testClass: AnyClass) {
        self.init(testName: NSStringFromClass(testClass.self))
    }

    /**
     Designated initializer.
     @param testName The name of the tests.
     @returns An instance of FBSnapshotTestController.
     */
    init(testName: String?) {
        super.init()

        self.testName = testName
        deviceAgnostic = false
        agnosticOptions = .none
        fileManager = FileManager()

    }

    /**
     Performs the comparison of the layer.
     @param layer The Layer to snapshot.
     @param selector The test method being run.
     @param identifier An optional identifier, used is there are muliptle snapshot tests in a given -test method.
     @param errorPtr An error to log in an XCTAssert() macro if the method fails (missing reference image, images differ, etc).
     @returns YES if the comparison (or saving of the reference image) succeeded.
     */
    func compareSnapshotOf(_ layer: CALayer?, selector: Selector, identifier: String?) -> Bool {
        guard let layer = layer else { return false }

        return self.compareSnapshotOfViewOrLayer(layer, selector: selector, identifier: identifier, tolerance: 0) ?? false
    }

    /**
     Performs the comparison of the view.
     @param view The view to snapshot.
     @param selector The test method being run.
     @param identifier An optional identifier, used is there are muliptle snapshot tests in a given -test method.
     @param errorPtr An error to log in an XCTAssert() macro if the method fails (missing reference image, images differ, etc).
     @returns YES if the comparison (or saving of the reference image) succeeded.
     */
    func compareSnapshotOf(_ view: UIView?, selector: Selector, identifier: String?) -> Bool {
        guard let view = view else { return false }

        return self.compareSnapshotOfViewOrLayer(view, selector: selector, identifier: identifier, tolerance: 0) ?? false
    }

    /**
     Performs the comparison of a view or layer.
     @param viewOrLayer The view or layer to snapshot.
     @param selector The test method being run.
     @param identifier An optional identifier, used is there are muliptle snapshot tests in a given -test method.
     @param tolerance The percentage of pixels that can differ and still be considered 'identical'
     @param errorPtr An error to log in an XCTAssert() macro if the method fails (missing reference image, images differ, etc).
     @returns YES if the comparison (or saving of the reference image) succeeded.
     */
    func compareSnapshotOfViewOrLayer(_ viewOrLayer: Any?, selector: Selector, identifier: String?, tolerance: CGFloat) -> Bool {
        if recordMode {
            return try? self._recordSnapshotOfViewOrLayer(viewOrLayer, selector: selector, identifier: identifier) ?? false
        } else {
            return try? self._performPixelComparison(withViewOrLayer: viewOrLayer, selector: selector, identifier: identifier, tolerance: tolerance) ?? false
        }
    }

    /**
     Loads a reference image.
     @param selector The test method being run.
     @param identifier The optional identifier, used when multiple images are tested in a single -test method.
     @param errorPtr An error, if this methods returns nil, the error will be something useful.
     @returns An image.
     */
    func referenceImage(for selector: Selector, identifier: String?) throws -> UIImage? {
        let filePath = _referenceFilePath(for: selector, identifier: identifier)
        let image = UIImage(contentsOfFile: filePath ?? "")
        if nil == image && nil != errorPtr {
            let exists: Bool? = fileManager?.fileExists(atPath: filePath ?? "")
            if !(exists ?? false) {
                errorPtr = NSError(domain: FBSnapshotTestControllerErrorDomain, code: FBSnapshotTestControllerErrorCode.needsRecord.rawValue, userInfo: [FBReferenceImageFilePathKey: filePath, NSLocalizedDescriptionKey: "Unable to load reference image.", NSLocalizedFailureReasonErrorKey: "Reference image not found. You need to run the test in record mode"])
            } else {
                errorPtr = NSError(domain: FBSnapshotTestControllerErrorDomain, code: FBSnapshotTestControllerErrorCode.unknown.rawValue, userInfo: nil)
            }
        }
        return image
    }

    /**
     Performs a pixel-by-pixel comparison of the two images with an allowable margin of error.
     @param referenceImage The reference (correct) image.
     @param image The image to test against the reference.
     @param tolerance The percentage of pixels that can differ and still be considered 'identical'
     @param errorPtr An error that indicates why the comparison failed if it does.
     @returns YES if the comparison succeeded and the images are the same(ish).
     */
    func compareReferenceImage(_ referenceImage: UIImage?, to image: UIImage?, tolerance: CGFloat) throws {
        let sameImageDimensions = referenceImage?.size.equalTo(image?.size)
        if sameImageDimensions && referenceImage?.fb_compare(with: image, tolerance: tolerance) != nil {
            return true
        }
        if nil != errorPtr {
            let errorDescription = sameImageDimensions ? "Images different" : "Images different sizes"
            let errorReason = sameImageDimensions ? String(format: "image pixels differed by more than %.2f%% from the reference image", tolerance * 100) : "referenceImage:\(NSStringFromCGSize(referenceImage?.size)), image:\(NSStringFromCGSize(image?.size))"
            let errorCode: FBSnapshotTestControllerErrorCode = sameImageDimensions ? .imagesDifferent : .imagesDifferentSizes
            errorPtr = NSError(domain: FBSnapshotTestControllerErrorDomain, code: errorCode.rawValue, userInfo: [NSLocalizedDescriptionKey: errorDescription, NSLocalizedFailureReasonErrorKey: errorReason, FBReferenceImageKey: referenceImage, FBCapturedImageKey: image, FBDiffedImageKey: referenceImage?.fb_diff(with: image)])
        }
        return false
    }

    /**
     Saves the reference image and the test image to `failedOutputDirectory`.
     @param referenceImage The reference (correct) image.
     @param testImage The image to test against the reference.
     @param selector The test method being run.
     @param identifier The optional identifier, used when multiple images are tested in a single -test method.
     @param errorPtr An error that indicates why the comparison failed if it does.
     @returns YES if the save succeeded.
     */
    func saveFailedReferenceImage(_ referenceImage: UIImage?, test testImage: UIImage?, selector: Selector, identifier: String?) throws {
        let referencePNGData: Data? = UIImagePNGRepresentation(referenceImage)
        let testPNGData: Data? = UIImagePNGRepresentation(testImage)
        let referencePath = _failedFilePath(for: selector, identifier: identifier, fileNameType: .failedReference)
        var creationError: Error? = nil
        let didCreateDir = try? fileManager?.createDirectory(atPath: URL(fileURLWithPath: referencePath ?? "").deletingLastPathComponent().absoluteString, withIntermediateDirectories: true, attributes: nil)
        if !(didCreateDir ?? false) {
            if nil != errorPtr {
                errorPtr = creationError
            }
            return false
        }
        if (try? referencePNGData?.write(toFile: referencePath ?? "", options: .atomic)) == nil {
            return false
        }
        let testPath = _failedFilePath(for: selector, identifier: identifier, fileNameType: .failedTest)
        if (try? testPNGData?.write(toFile: testPath ?? "", options: .atomic)) == nil {
            return false
        }
        let diffPath = _failedFilePath(for: selector, identifier: identifier, fileNameType: .failedTestDiff)
        let diffImage: UIImage? = referenceImage?.fb_diff(with: testImage)
        let diffImageData: Data? = UIImagePNGRepresentation(diffImage)
        if (try? diffImageData?.write(toFile: diffPath ?? "", options: .atomic)) == nil {
            return false
        }
        print("""
            If you have Kaleidoscope installed you can run this command to see an image diff:\n\
            ksdiff "\(referencePath ?? "")" "\(testPath ?? "")"
            """)
        return true
    }

    // MARK: - Overrides
    override class func description() -> String {
        return "\(super.description) \(referenceImagesDirectory)"
    }

    // MARK: - Public API

    // MARK: - Private API
    func _fileName(for selector: Selector, identifier: String?, fileNameType: FBTestSnapshotFileNameType) -> String? {
        var fileName: String? = nil
        switch fileNameType {
        case .failedReference:
            fileName = "reference_"
        case .failedTest:
            fileName = "failed_"
        case .failedTestDiff:
            fileName = "diff_"
        default:
            fileName = ""
        }
        fileName = fileName ?? "" + (NSStringFromSelector(selector))
        if 0 < (identifier?.count ?? 0) {
            fileName = fileName ?? "" + ("_\(identifier ?? "")")
        }
        let noAgnosticOption: Bool = (agnosticOptions.rawValue & FBSnapshotTestCaseAgnosticOption.none.rawValue) == .none
        if deviceAgnostic {
            fileName = FBDeviceAgnosticNormalizedFileName(fileName)
        } else if !noAgnosticOption {
            fileName = FBDeviceAgnosticNormalizedFileNameFromOption(fileName, agnosticOptions)
        }
        if UIScreen.main.scale > 1 {
            fileName = fileName ?? "" + (String(format: "@%.fx", UIScreen.main.scale))
        }
        fileName = URL(fileURLWithPath: fileName ?? "").appendingPathExtension("png").absoluteString
        return fileName
    }

    func _referenceFilePath(for selector: Selector, identifier: String?) -> String? {
        let fileName = _fileName(for: selector, identifier: identifier, fileNameType: .reference)
        var filePath = URL(fileURLWithPath: referenceImagesDirectory).appendingPathComponent(testName).absoluteString
        filePath = URL(fileURLWithPath: filePath).appendingPathComponent(fileName).absoluteString
        return filePath
    }

    func _failedFilePath(for selector: Selector, identifier: String?, fileNameType: FBTestSnapshotFileNameType) -> String? {
        let fileName = _fileName(for: selector, identifier: identifier, fileNameType: fileNameType)
        var folderPath = NSTemporaryDirectory()
        if getenv("IMAGE_DIFF_DIR") {
            folderPath = getenv("IMAGE_DIFF_DIR")
        }
        var filePath = URL(fileURLWithPath: folderPath).appendingPathComponent(testName).absoluteString
        filePath = URL(fileURLWithPath: filePath).appendingPathComponent(fileName).absoluteString
        return filePath
    }

    func _performPixelComparison(withViewOrLayer viewOrLayer: Any?, selector: Selector, identifier: String?, tolerance: CGFloat) throws {
        let referenceImage: UIImage? = try? self.referenceImage(for: selector, identifier: identifier)
        if nil != referenceImage {
            let snapshot: UIImage? = _image(forViewOrLayer: viewOrLayer)
            let imagesSame = try? self.compareReferenceImage(referenceImage, to: snapshot, tolerance: tolerance)
            if !(imagesSame ?? false) {
                var saveError: Error? = nil
                if try? self.saveFailedReferenceImage(referenceImage, test: snapshot, selector: selector, identifier: identifier) == false {
                    if let anError = saveError {
                        print("Error saving test images: \(anError)")
                    }
                }
            }
            return imagesSame ?? false
        }
        return false
    }

    func _recordSnapshotOfViewOrLayer(_ viewOrLayer: Any?, selector: Selector, identifier: String?) throws {
        let snapshot: UIImage? = _image(forViewOrLayer: viewOrLayer)
        return try? self._saveReferenceImage(snapshot, selector: selector, identifier: identifier) ?? false
    }

    func _saveReferenceImage(_ image: UIImage?, selector: Selector, identifier: String?) throws {
        var errorPtr = errorPtr
        var didWrite = false
        if nil != image {
            let filePath = _referenceFilePath(for: selector, identifier: identifier)
            let pngData: Data? = UIImagePNGRepresentation(image)
            if nil != pngData {
                var creationError: Error? = nil
                let didCreateDir = try? fileManager?.createDirectory(atPath: URL(fileURLWithPath: filePath ?? "").deletingLastPathComponent().absoluteString, withIntermediateDirectories: true, attributes: nil)
                if !(didCreateDir ?? false) {
                    if nil != errorPtr {
                        errorPtr = creationError
                    }
                    return false
                }
                didWrite = try? pngData?.write(toFile: filePath ?? "", options: .atomic) ?? false
                if didWrite {
                    print("Reference image save at: \(filePath ?? "")")
                }
            } else {
                if nil != errorPtr {
                    errorPtr = NSError(domain: FBSnapshotTestControllerErrorDomain, code: FBSnapshotTestControllerErrorCode.pngCreationFailed.rawValue, userInfo: [FBReferenceImageFilePathKey: filePath])
                }
            }
        }
        return didWrite
    }

    func _image(forViewOrLayer viewOrLayer: Any?) -> UIImage? {
        if (viewOrLayer is UIView) {
            if usesDrawViewHierarchyInRect {
                return UIImage.fb_image(forView: viewOrLayer)
            } else {
                return UIImage.fb_image(forViewLayer: viewOrLayer)
            }
        } else if (viewOrLayer is CALayer) {
            return UIImage.fb_image(forLayer: viewOrLayer)
        } else {
            NSException.raise("Only UIView and CALayer classes can be snapshotted", format: "%@", viewOrLayer)
        }
        return nil
    }
}

